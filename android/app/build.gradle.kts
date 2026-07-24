import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.box"
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
        applicationId = "com.example.box"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 强制单架构 arm64：部分插件（jni、datastore）的原生 .so 会无视
        // --target-platform 打进全 ABI，用 abiFilters 兜底裁掉 v7a/x86_64。
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
        }
    }
}

android {
    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
