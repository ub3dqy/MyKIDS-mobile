import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

plugins { id("com.android.library") }

group = "ru.mykids.webrtc"
version = "150.7871.04-mykids1"

val upstream by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
    isTransitive = false
}
dependencies { add(upstream.name, "io.github.webrtc-sdk:android:150.7871.04") }

fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(65536)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
}

val prepared = layout.buildDirectory.dir("verified-upstream")
val fixedSource = file("src/main/java/org/webrtc/audio/WebRtcAudioRecord.java")
val prepareUpstream = tasks.register("prepareVerifiedUpstream") {
    inputs.files(upstream)
    inputs.file(fixedSource)
    outputs.dir(prepared)
    doLast {
        val aar = upstream.singleFile
        val expected = "1872dda4e3bf7d6ea6f7c6e11861332081c57081a1e62fc82fab72415c69c84c"
        require(sha256(aar) == expected) { "WebRTC AAR differs from the verified upstream artifact" }
        val directory = prepared.get().asFile.apply { mkdirs() }
        val abis = listOf("armeabi-v7a", "arm64-v8a", "x86_64", "x86")
        val nativePaths = abis.map { "jni/$it/libjingle_peerconnection_so.so" }
        val omitted = mutableSetOf<String>()
        val replace = setOf(
            "org/webrtc/audio/WebRtcAudioRecord.class",
            "org/webrtc/audio/WebRtcAudioRecord\$1.class",
            "org/webrtc/audio/WebRtcAudioRecord\$AudioRecordThread.class",
        )
        val hashes = mutableMapOf<String, String>()
        ZipFile(aar).use { zip ->
            val entries = zip.entries().asSequence().map { it.name }.toSet()
            require(entries == (nativePaths + listOf("AndroidManifest.xml", "classes.jar")).toSet()) {
                "Unexpected WebRTC archive structure"
            }
            val jar = File(directory, "webrtc-core.jar")
            ZipInputStream(zip.getInputStream(zip.getEntry("classes.jar"))).use { input ->
                ZipOutputStream(jar.outputStream()).use { output ->
                    while (true) {
                        val entry = input.nextEntry ?: break
                        if (entry.name in replace) {
                            omitted.add(entry.name)
                        } else {
                            output.putNextEntry(ZipEntry(entry.name).apply { time = 0L })
                            input.copyTo(output)
                            output.closeEntry()
                        }
                        input.closeEntry()
                    }
                }
            }
            require(omitted == replace) { "The three verified WebRtcAudioRecord classes were not replaced" }
            for (name in nativePaths) {
                val destination = File(directory, name).apply { parentFile.mkdirs() }
                zip.getInputStream(zip.getEntry(name)).use { input ->
                    destination.outputStream().use { output -> input.copyTo(output) }
                }
                hashes[name.removePrefix("jni/")] = sha256(destination)
            }
        }
        val nativeJson = hashes.entries.joinToString(",") { "\"${it.key}\":\"${it.value}\"" }
        File(directory, "assets/mykids-webrtc-audio-fix.json").apply {
            parentFile.mkdirs()
            writeText("""{"fix":"native-audio-start-stop-delivery-gate-v1","upstream_version":"150.7871.04","upstream_aar_sha256":"$expected","patched_source_sha256":"${sha256(fixedSource)}","native_libraries":{$nativeJson}}""")
        }
    }
}

android {
    namespace = "org.webrtc"
    compileSdk = 36
    defaultConfig { minSdk = 21 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
// Use AGP's public source-set interface. The legacy Kotlin accessor narrows
// library source sets to a removed implementation type under AGP 9.4.
extensions.configure<com.android.build.api.dsl.LibraryExtension> {
    sourceSets.getByName("main").apply {
        jniLibs.srcDir(files(prepared.map { it.dir("jni") }).builtBy(prepareUpstream))
        assets.srcDir(files(prepared.map { it.dir("assets") }).builtBy(prepareUpstream))
    }
}
dependencies {
    api(files(prepared.map { it.file("webrtc-core.jar") }).builtBy(prepareUpstream))
    implementation("androidx.annotation:annotation:1.11.0")
}
tasks.named("preBuild") { dependsOn(prepareUpstream) }
