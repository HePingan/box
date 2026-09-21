import java.util.Properties
import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- 更新验签密钥：顶层读取 ------------------------------------------------
// 为什么在顶层读：下面的 android {} 里是 receiver scope，Kotlin DSL 不保证
// 局部 val 在那里可见；这两个值要同时被 android {} 和 task 用到，放顶层最稳。
// 注意 key.properties 本身也要在这里重新读一次（原来那份是 android{} 内的局部变量）。
val updateSignKeyProperties: Properties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        f.inputStream().use { load(it) }
    }
}

// 更新验签密钥。来源（与 tool/build_release_with_update_sign.sh 一致）：
// 脚本 export UPDATE_SIGNATURE_SECRET → flutter 以 --dart-define 传下来，
// Gradle 侧可直接从环境变量读到。key.properties 的 updateSignatureSecret
// 是给「不走脚本、手动配密钥」留的口子（本仓当前没填）。
val updateSignSecret: String? =
    (updateSignKeyProperties.getProperty("updateSignatureSecret")
        ?: System.getenv("UPDATE_SIGNATURE_SECRET"))
        ?.takeIf { it.isNotBlank() }

// 是否在用**正式 release 签名**。本机没配 keystore 时会 fallback 到 debug 签名
// （见 buildTypes.release），那种包只是装机测试用，不应被守卫阻断。
val realReleaseSigning: Boolean =
    !(updateSignKeyProperties.getProperty("storeFile")
        ?: System.getenv("ANDROID_KEYSTORE_FILE")).isNullOrBlank()

// 只取短指纹，绝不打印密钥本身（构建日志会外传）
fun updateSignFingerprint(secret: String): String =
    MessageDigest.getInstance("SHA-256")
        .digest(secret.toByteArray())
        .joinToString("") { "%02x".format(it) }
        .take(12)

android {
    namespace = "top.hpa888.box"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "top.hpa888.box"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 交付单架构 arm64，避免第三方插件把 v7a/x86_64 原生库一并打入。
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }
    }

    val keyPropertiesFile = rootProject.file("key.properties")
    val keyProperties = Properties().apply {
        if (keyPropertiesFile.exists()) {
            keyPropertiesFile.inputStream().use { load(it) }
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keyProperties.getProperty("storeFile")
                ?: System.getenv("ANDROID_KEYSTORE_FILE")
            val storePasswordValue = keyProperties.getProperty("storePassword")
                ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")
            val keyAliasValue = keyProperties.getProperty("keyAlias")
                ?: System.getenv("ANDROID_KEY_ALIAS")
            val keyPasswordValue = keyProperties.getProperty("keyPassword")
                ?: System.getenv("ANDROID_KEY_PASSWORD")

            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = storePasswordValue
            keyAlias = keyAliasValue
            keyPassword = keyPasswordValue
        }
    }

    buildTypes {
        release {
            // 本机未配置正式 keystore 时，允许产出仅供安装测试的 debug-signed release APK。
            // 配置 key.properties 或 ANDROID_KEYSTORE_* 后自动改用正式 release 签名。
            val releaseStoreFile = keyProperties.getProperty("storeFile")
                ?: System.getenv("ANDROID_KEYSTORE_FILE")
            signingConfig = if (releaseStoreFile.isNullOrBlank()) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }

            // R8 代码压缩 + 资源压缩。keep 规则见 proguard-rules.pro：
            // manifest 声明的组件、Flutter/Media3 反射入口都必须显式保留。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

android {
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    // ---- 更新验签密钥构建守卫（A 档）---------------------------------------
    // 为什么需要：
    //   tool/build_release_with_update_sign.sh 用 --dart-define 把验签密钥注入产物。
    //   若有人直接敲 `flutter build apk --release`，会得到一个**看起来完全正常**的包：
    //   applicationId / versionCode / 签名证书指纹全对，但 libapp.so 里没有密钥。
    //   用户装上后每次检查更新都报「更新清单签名校验未通过」，且永远收不到后续版本。
    //   历史上已因此发错两次：1.7.3(173)、1.8.5(185)。
    //   判据值（updateSignSecret / realReleaseSigning）在文件顶层已算好。
    val verifyUpdateSignInjected = tasks.register("verifyUpdateSignInjected") {
        group = "verification"
        description = "确保 release 构建注入了更新验签密钥（否则更新链路必断）"
        // 永远不复用上一次的输出：密钥由外部环境变量注入，Gradle 不把它算作
        // task input，一旦 UP-TO-DATE 就会被跳过，守卫形同虚设。
        outputs.upToDateWhen { false }
        doLast {
            val secret = updateSignSecret
            if (realReleaseSigning && secret == null) {
                throw GradleException(
                    """
                    |
                    |[错误] release 构建缺少更新验签密钥，已阻断。
                    |
                    |这个包装到用户手机上后，每次「检查更新」都会失败，并且永远收不到
                    |后续版本（更新链路是断的），但产物本身看不出任何异常。
                    |
                    |正确命令：
                    |  bash tool/build_release_with_update_sign.sh
                    |
                    |若你确实在走正式脚本却看到这条，请检查脚本是否真的把
                    |UPDATE_SIGNATURE_SECRET 传给了 flutter build。
                    |""".trimMargin()
                )
            } else if (secret != null) {
                logger.lifecycle("    构建守卫    : 已确认验签密钥存在（指纹 ${updateSignFingerprint(secret)}）")
            } else {
                logger.lifecycle("    构建守卫    : 非正式签名构建，跳过（仅供本地装机测试）")
            }
        }
    }

    // 挂到 assembleRelease 之前。用 configureEach + dependsOn 而不是直接写在
    // buildTypes 里：assembleRelease 由 AGP 动态创建，配置阶段拿不到它的引用。
    tasks.configureEach {
        if (name == "assembleRelease") {
            dependsOn(verifyUpdateSignInjected)
        }
    }
}

dependencies {
    // Media3 Download — background HLS/MP4 downloads via DownloadService
    implementation("androidx.media3:media3-exoplayer:1.2.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.2.1")
    implementation("androidx.media3:media3-session:1.2.1")

    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
