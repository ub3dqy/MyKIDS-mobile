import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Native resources are required for notification delivery after process death.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    buildFeatures {
        resValues = true
    }
    namespace = "ru.mykids.mykids_family"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Reuse the registered package and production signer for one family app.
        applicationId = "ru.mykids.mykids_family.parent"
        resValue("string", "app_name", "MyKIDS")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // A release must never silently use a debug signing key.
            val keyFile = rootProject.file("key.properties")
            if (keyFile.exists()) {
                val keyProperties = Properties().apply {
                    keyFile.inputStream().use { load(it) }
                }
                val familySigning = signingConfigs.create("familyRelease") {
                    storeFile = file(keyProperties.getProperty("storeFile"))
                    storePassword = keyProperties.getProperty("storePassword")
                    keyAlias = keyProperties.getProperty("keyAlias")
                    keyPassword = keyProperties.getProperty("keyPassword")
                }
                signingConfig = familySigning
            } else if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
                throw GradleException("Release signing is required: configure android/key.properties")
            }
        }
    }
}

dependencies {
    val verifiedNativeVersions = Properties().apply {
        rootProject.file("build-tool-versions.properties").inputStream().use { load(it) }
    }
    constraints {
        implementation("com.google.guava:guava:${verifiedNativeVersions.getProperty("guavaAndroid")}") {
            because("Use the compatible upstream correction for CVE-2026-102554")
        }
    }
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    // AGP uses consistent test/target dependency resolution. Flutter's test
    // plugin otherwise leaves the debug target on an older runner version.
    debugImplementation("androidx.test:runner:1.7.0")
    debugImplementation("androidx.test.ext:junit:1.3.0")
    // Match the Firebase version pinned by the installed FlutterFire plugin.
    implementation(platform("com.google.firebase:firebase-bom:35.1.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Match the installed workmanager_android plugin's native runtime.
    implementation("androidx.work:work-runtime:2.12.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
