allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Flutter plugins can declare old private copies of the same build tools.
    // Resolve every module with the application's verified plugin versions,
    // rather than retaining obsolete AGP/Kotlin transitive classpaths.
    val versions = java.util.Properties().apply {
        rootProject.file("build-tool-versions.properties").inputStream().use { load(it) }
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
    buildscript.configurations.configureEach {
        resolutionStrategy.eachDependency {
            pins[requested.group + ":" + requested.name]?.let {
                useVersion(it)
                because("Use the verified build toolchain and its compatible security fixes")
            }
        }
    }
}

// Keep the verified upstream native SDK; replace only its unsafe Java PCM
// delivery lifecycle. The module's own upstream input must remain unsubstituted.
subprojects {
    if (name != "webrtc_audio_fixed") {
        configurations.configureEach {
            resolutionStrategy.dependencySubstitution {
                substitute(module("io.github.webrtc-sdk:android:150.7871.04"))
                    .using(project(":webrtc_audio_fixed"))
                    .because("Wait for native audio start and serialize PCM delivery with stop")
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
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
