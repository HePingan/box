# R8 / ProGuard 规则
#
# 开启 minify + shrinkResources 后，凡是「不被 Java/Kotlin 代码直接引用、
# 只在 manifest / XML / 反射 / JNI 里按名字出现」的类都会被误删或改名。
# 下面每条 keep 都对应一个真实的按名字引用点。

# ── manifest 里声明的组件（android:name=".XxX"，R8 看不到调用方）──
-keep class top.hpa888.box.MainActivity { *; }
-keep class top.hpa888.box.QuizAccessibilityService { *; }
-keep class top.hpa888.box.VideoDownloadService { *; }

# 无障碍服务由系统反射回调，保留其全部回调方法
-keepclassmembers class * extends android.accessibilityservice.AccessibilityService {
    public *;
}

# ── Flutter 引擎与插件桥接 ──
# MethodChannel handler 由字符串驱动；插件注册走反射
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── Media3 / ExoPlayer ──
# DownloadService 子类与 Renderer 由反射实例化
-keep class androidx.media3.** { *; }
-dontwarn androidx.media3.**

# ── 通用 Android 反射约定 ──
# Parcelable CREATOR 字段按名字查找
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
# View 的 XML 构造器（RegionSelectorView 等自定义 View 在布局里按名字实例化）
-keepclasseswithmembers class * extends android.view.View {
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}
# 枚举的 values/valueOf 被序列化按名字调用
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
# 注解与泛型签名（Gson/序列化依赖）
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── 降噪：这些是编译期可选依赖，运行时不存在也不影响 ──
-dontwarn org.slf4j.**
-dontwarn org.apache.**
-dontwarn javax.annotation.**
