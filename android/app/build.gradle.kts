import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // 不再显式声明 kotlin-android：AGP 9 内置 Kotlin，Flutter 插件在 builtInKotlin=false 下自动代为 apply KGP
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.copper.launcher"    // permission_handler_android 硬编码 compileSdk 37，Flutter 默认 36 不满足
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.copper.launcher"
        // copper loader requires min api level: 30
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ABI 分包：每个 ABI 一个 APK，另出一个整包（universal）。
    // 游戏载荷（JRE / arc 原生库）本来就按 abi 分包，安装包也分开能少带别人的 so。
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }

    signingConfigs {
        getByName("debug") {
            // CI 上不能指望 AGP 去 ~/.android 找 debug keystore（runner 的 user.home /
            // ANDROID_SDK_HOME 跟本机不一样，测试里它反而自己生成了一把新的）⇒
            // 由 COPPER_DEBUG_KEYSTORE 把固定那把的路径直接喂进来；
            // 本机不设这个变量，行为与原来完全一致
            val pinned = System.getenv("COPPER_DEBUG_KEYSTORE")
            if (!pinned.isNullOrBlank()) storeFile = file(pinned)
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // 开 R8：入口 / 组件工厂 / 生成通道的 keep 规则在 proguard-rules.pro。
            // 这些类有反射和字符串通道名，不能只靠可达性分析。
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Android 桥的生成物（AndroidCall / AndroidEvent）随源码提交：每次构建前仍用 Dart
// 重新生成，免得改了注解忘了重跑，编出来还是旧的。
val flutterSdkPath: String = Properties().apply {
    val localProperties = rootProject.file("local.properties")
    if (localProperties.exists()) localProperties.inputStream().use { load(it) }
}.getProperty("flutter.sdk").orEmpty()

val isWindowsHost = org.gradle.internal.os.OperatingSystem.current().isWindows

// 优先用 SDK 自带的 dart 可执行文件：Windows 上直接跑 .bat 需要 cmd 代劳
val dartExecutable = run {
    val fromSdk = if (isWindowsHost) {
        "$flutterSdkPath/bin/cache/dart-sdk/bin/dart.exe"
    } else {
        "$flutterSdkPath/bin/cache/dart-sdk/bin/dart"
    }
    if (file(fromSdk).exists()) {
        listOf(fromSdk)
    } else {
        val script = if (isWindowsHost) "$flutterSdkPath/bin/dart.bat" else "$flutterSdkPath/bin/dart"
        if (isWindowsHost) listOf("cmd", "/c", script) else listOf(script)
    }
}

val generateBridgeCode by tasks.registering(Exec::class) {
    group = "flutter"
    description = "根据 @DartCall / @DartAsyncCall / @KotlinEvent 生成 Android 桥代码"
    workingDir = rootProject.projectDir.parentFile
    commandLine(dartExecutable + listOf("run", "tool/android_bridge/generate.dart"))
    // 注解写在源码里，构建输入无法完整表达，别让 Gradle 以为可以跳过
    outputs.upToDateWhen { false }
    doFirst {
        check(flutterSdkPath.isNotEmpty()) {
            "local.properties 里没有 flutter.sdk，跑不了 Android 桥生成器"
        }
    }
}

tasks.named("preBuild") { dependsOn(generateBridgeCode) }
tasks.matching {
    it.name.startsWith("compileFlutterBuild") || it.name.endsWith("Kotlin")
}.configureEach { dependsOn(generateBridgeCode) }
