import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Permanent Meloria signing key.
// Local builds read android/key.properties; GitHub builds read repository secrets.
// The key file itself is NEVER committed (see .gitignore).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}
fun signValue(name: String, env: String): String? =
    (keyProps.getProperty(name) ?: System.getenv(env))?.takeIf { it.isNotBlank() }

android {
    namespace = "com.meloria.meloria_siddha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.meloriasiddha.staff"
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
    }

    signingConfigs {
        create("release") {
            val store = signValue("storeFile", "MELORIA_KEYSTORE_PATH")
            if (store != null) {
                storeFile = file(store)
                storePassword = signValue("storePassword", "MELORIA_KEYSTORE_PASSWORD")
                keyAlias = signValue("keyAlias", "MELORIA_KEY_ALIAS") ?: "meloria"
                keyPassword = signValue("keyPassword", "MELORIA_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            val release = signingConfigs.getByName("release")
            // Falls back to debug signing only if the Meloria key is not available.
            signingConfig = if (release.storeFile != null) release else signingConfigs.getByName("debug")
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
