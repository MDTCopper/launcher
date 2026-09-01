plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    // 不再显式声明 kotlin-android：AGP 9 内置 Kotlin，Flutter 插件在 builtInKotlin=false 下自动代为 apply KGP
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.copper.launcher"
    compileSdk = flutter.compileSdkVersion
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
