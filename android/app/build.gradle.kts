plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // 不再显式声明 kotlin-android：AGP 9 内置 Kotlin，Flutter 插件在 builtInKotlin=false 下自动代为 apply KGP
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.copper.launcher"
    // permission_handler_android 硬编码 compileSdk 37，Flutter 默认 36 不满足
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

            // DO NOT minify or shrink, or io.github.copper.loader.Loader will be treated as an unused class and remove,
            // which is used in dart with jni
            isMinifyEnabled = false
            isShrinkResources = false
            // TODO: or we can introduce a proguard-rules.pro here, but i'm lazy
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
