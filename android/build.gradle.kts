allprojects {
    repositories {
         // --- 专门针对 Flutter 特制砖的官方国内镜像（最新加入！） ---
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        
        // --- 刚才加的阿里云超跑通道（负责安卓通用砖） ---
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/spring-plugin") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
        // ---------------------------------------------
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
