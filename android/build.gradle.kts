allprojects {
    repositories {
        // google()
        // mavenCentral()
        // 阿里云 Maven 中央仓库镜像
        maven("https://maven.aliyun.com/repository/public")
        // 阿里云 Google 仓库镜像
        maven("https://maven.aliyun.com/repository/google")
    }

}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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

//buildscript {
//    repositories {
//        // google()
//        // mavenCentral()
//        maven { url= "https://maven.aliyun.com/repository/google" }
//        maven { url= "https://maven.aliyun.com/repository/public" }
//    }
//}