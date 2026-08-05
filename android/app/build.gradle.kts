import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signStoreFile = providers.gradleProperty("AFFECTION_STORE_FILE").orNull
val signStorePassword = providers.gradleProperty("AFFECTION_STORE_PASSWORD").orNull
val signKeyAlias = providers.gradleProperty("AFFECTION_KEY_ALIAS").orNull
val signKeyPassword = providers.gradleProperty("AFFECTION_KEY_PASSWORD").orNull
val hasReleaseSigning = !signStoreFile.isNullOrBlank() &&
        !signStorePassword.isNullOrBlank() &&
        !signKeyAlias.isNullOrBlank() &&
        !signKeyPassword.isNullOrBlank()
val signingMode = if (hasReleaseSigning) "release" else "debug"
if (!hasReleaseSigning) {
    println("WARNING: release signing properties not found, falling back to debug key")
}

android {
    namespace = "dev.affection.affection_vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.affection.affection_vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = File(signStoreFile!!)
                storePassword = signStorePassword
                keyAlias = signKeyAlias
                keyPassword = signKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(signingMode)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
