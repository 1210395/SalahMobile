import java.util.Properties
import java.io.FileInputStream

// Release signing lives OUTSIDE the repository: android/key.properties names a
// keystore kept in C:\server\_keys. Android refuses an update signed by a
// different key, so that keystore is the most irreplaceable artefact this
// project has — see C:\server\_secrets\amarati-live-admin.txt.
//
// When the file is absent (a fresh clone, a machine without the key) the build
// falls back to the debug key rather than failing.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.olivedev.sakanpro"
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
        applicationId = "com.olivedev.sakanpro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Real phones are ARM. A universal APK also carries an x86_64 slice that
        // only an emulator can run — 27.7 MB of a 77 MB download, wasted on every
        // install. This drops it from the PLUGINS' native libraries.
        //
        // Flutter's own engine libraries are added by its gradle plugin and do
        // NOT pass through here, so the release build must ALSO be given:
        //     flutter build apk --release --target-platform android-arm,android-arm64
        // Together: 77 MB -> ~50 MB.
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The real key when it is present on this machine, the debug key
            // otherwise — a missing keystore must not break an ordinary build.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
