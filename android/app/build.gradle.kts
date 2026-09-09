plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// JPush AppKey 是公开的应用标识，不是服务端凭据。与官方客户端保持一致：
// 普通构建使用官方 AppKey；连接独立开发/测试应用时可通过环境变量覆盖。
// Master Secret 永远只配置在 Push Gateway，不进入 Android 包或仓库。
val defaultJPushAppKey = "d7fa4b31dd21064e095d29d5"
val jpushAppKey = System.getenv("JPUSH_APP_KEY")?.trim()
    .takeUnless { it.isNullOrEmpty() }
    ?: defaultJPushAppKey
val jpushChannel = System.getenv("JPUSH_CHANNEL")?.trim().takeUnless { it.isNullOrEmpty() }
    ?: "official"
val releaseKeystorePath = System.getenv("ANDROID_KEYSTORE_PATH")?.trim()
val releaseStorePassword = System.getenv("ANDROID_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
val hasReleaseSigning = !releaseKeystorePath.isNullOrEmpty() &&
    !releaseStorePassword.isNullOrEmpty() && !releaseKeyPassword.isNullOrEmpty()

android {
    namespace = "cloud.baizhi.chat"
    // file_picker's current Android lifecycle dependency requires API 36.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cloud.baizhi.chat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["JPUSH_APPKEY"] = jpushAppKey
        manifestPlaceholders["JPUSH_CHANNEL"] = jpushChannel
        manifestPlaceholders["JPUSH_CONFIGURED"] = jpushAppKey.isNotEmpty().toString()
        buildConfigField("boolean", "JPUSH_CONFIGURED", jpushAppKey.isNotEmpty().toString())
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = "magicchat"
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // GitHub Release 使用固定发布证书；本地未提供证书时保留侧载构建能力。
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug"
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("cn.jiguang.sdk:jpush:6.2.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
