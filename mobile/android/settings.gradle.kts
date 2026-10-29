pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

// Apply compatible security updates before the plugins DSL creates its
// classloader. Child projects use the same policy in build.gradle.kts.
buildscript {
    val versions = java.util.Properties().apply {
        file("build-tool-versions.properties").inputStream().use { load(it) }
    }
    val pins = mapOf(
        "com.android.tools.build:gradle" to versions.getProperty("agp"),
        "org.jetbrains.kotlin:kotlin-gradle-plugin" to versions.getProperty("kotlin"),
        "com.google.gms:google-services" to versions.getProperty("googleServices"),
        "org.bouncycastle:bcpkix-jdk18on" to versions.getProperty("bouncyCastle"),
        "org.bouncycastle:bcprov-jdk18on" to versions.getProperty("bouncyCastle"),
        "org.bouncycastle:bcutil-jdk18on" to versions.getProperty("bouncyCastle"),
        "org.apache.commons:commons-lang3" to versions.getProperty("commonsLang"),
        "org.bitbucket.b_c:jose4j" to versions.getProperty("jose4j"),
        "org.jdom:jdom2" to versions.getProperty("jdom"),
        "com.google.guava:guava" to versions.getProperty("guavaJre"),
    )
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            pins[requested.group + ":" + requested.name]?.let {
                useVersion(it)
                because("Use the verified build toolchain and its compatible security fixes")
            }
        }
    }
}

plugins {
    id("com.google.gms.google-services") version "4.5.0" apply false
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.5.0" apply false
    id("com.android.library") version "9.5.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
include(":webrtc_audio_fixed")
project(":webrtc_audio_fixed").projectDir = file("../packages/webrtc_audio_fixed/android")
