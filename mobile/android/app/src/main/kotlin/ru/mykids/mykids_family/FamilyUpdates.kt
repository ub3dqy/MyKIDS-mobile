package ru.mykids.mykids_family

import android.content.Intent
import android.app.KeyguardManager
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.storage.StorageManager
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicLong

@Suppress("DEPRECATION")
class FamilyUpdates(private val activity: FlutterFragmentActivity) {
    private val executor = Executors.newSingleThreadExecutor()
    private val sequence = AtomicLong()
    private val downloads = FamilyUpdateDownload(activity)
    private val verifiedDirectory = File(activity.filesDir, VerifiedUpdateFiles.DIRECTORY)
    private val flags = if (Build.VERSION.SDK_INT >= 28)
        PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    private fun code(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28)
        info.longVersionCode else info.versionCode.toLong()

    private fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun signers(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= 28)
            info.signingInfo?.apkContentsSigners else info.signatures
        return signatures?.map { digest(it.toByteArray()) }?.toSet() ?: emptySet()
    }

    private fun installSpace(): Long {
        val storage = activity.getSystemService(StorageManager::class.java)
            ?: return activity.filesDir.usableSpace
        return try {
            storage.getAllocatableBytes(storage.getUuidForPath(activity.filesDir))
        } catch (_: IOException) {
            activity.filesDir.usableSpace
        }
    }

    fun attach(channel: MethodChannel) {
        executor.execute {
            // A completed installation no longer needs its private staged APK.
            // Only our hash-named, already installed packages are removed.
            try {
                VerifiedUpdateFiles.cleanupPartials(verifiedDirectory)
                val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
                for (file in verifiedDirectory.listFiles().orEmpty()) {
                    if (!Regex("[0-9a-f]{64}\\.apk").matches(file.name) || !file.isFile ||
                        file.canonicalFile.parentFile != verifiedDirectory.canonicalFile) continue
                    val old = activity.packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: continue
                    if (old.packageName == activity.packageName && code(old) <= code(installed) &&
                        signers(old) == signers(installed)) file.delete()
                }
            } catch (_: Exception) { /* Retention must never block checking an update. */ }
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "cancelUpdate") {
                sequence.incrementAndGet()
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method == "appInfo") {
                try {
                    val info = activity.packageManager.getPackageInfo(activity.packageName, flags)
                    val certificates = signers(info)
                    check(certificates.size == 1)
                    result.success(mapOf("package" to activity.packageName,
                        "version" to info.versionName, "versionCode" to code(info),
                        "signerSha256" to certificates.single(),
                        "updateDirectory" to downloads.directory().absolutePath))
                } catch (_: Exception) { result.error("UPDATE_INFO", "Не удалось определить версию приложения", null) }
                return@setMethodCallHandler
            }
            if (call.method in setOf("startDownload", "downloadStatus", "cancelDownload")) {
                executor.execute {
                    try {
                        val state = downloads.handle(call)
                        activity.runOnUiThread { result.success(state) }
                    } catch (error: Exception) {
                        android.util.Log.w("MyKIDSUpdates", "Download state error", error)
                        activity.runOnUiThread { result.error("UPDATE_DOWNLOAD", "Не удалось скачать обновление. Проверьте интернет и свободное место", null) }
                    }
                }
                return@setMethodCallHandler
            }
            if (call.method !in setOf("installUpdate", "verifyUpdate")) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val name = call.argument<String>("fileName") ?: ""
            val expectedCode = call.argument<Number>("versionCode")?.toLong() ?: 0
            val expectedBytes = call.argument<Number>("bytes")?.toLong() ?: 0
            val expectedHash = call.argument<String>("sha256") ?: ""
            val requestSequence = sequence.incrementAndGet()
            executor.execute {
                try {
                    check(activity.packageName == "ru.mykids.mykids_family.parent")
                    check(Regex("MyKIDS-\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}\\.apk").matches(name))
                    check(Regex("[0-9a-f]{64}").matches(expectedHash))
                    val directory = downloads.directory()
                    val source = File(directory, name).canonicalFile
                    check(source.parentFile == directory && source.isFile)
                    check(expectedBytes in 1..(512L * 1024 * 1024) && source.length() == expectedBytes)
                    if (installSpace() < expectedBytes) {
                        activity.runOnUiThread {
                            result.error("UPDATE_SPACE",
                                "Недостаточно места для проверки обновления. Освободите память и повторите. Скачанный файл сохранён.", null)
                        }
                        return@execute
                    }
                    val file = VerifiedUpdateFiles.stage(verifiedDirectory, source, expectedBytes, expectedHash)
                    val installed = activity.packageManager.getPackageInfo(activity.packageName, flags)
                    val candidate = activity.packageManager.getPackageArchiveInfo(file.absolutePath, flags)
                        ?: throw IllegalStateException("Invalid APK")
                    check(candidate.packageName == activity.packageName)
                    check(code(candidate) == expectedCode && expectedCode > code(installed))
                    check(candidate.applicationInfo?.minSdkVersion?.let { it <= Build.VERSION.SDK_INT } == true)
                    val currentSigners = signers(installed)
                    check(currentSigners.isNotEmpty() && currentSigners == signers(candidate))
                    // The system installer first stages another full copy of the APK.
                    // Its staging failure can otherwise be reported as a misleading parse error.
                    if (call.method == "installUpdate" && installSpace() < file.length()) {
                        activity.runOnUiThread {
                            result.error("UPDATE_SPACE",
                                "Недостаточно места для установки обновления. Освободите память и нажмите «Установить» ещё раз. Скачанный файл сохранён.", null)
                        }
                        return@execute
                    }
                    activity.runOnUiThread {
                        try {
                            check(!activity.isFinishing && !activity.isDestroyed)
                            check(sequence.get() == requestSequence)
                            if (call.method == "verifyUpdate") {
                                result.success("verified")
                            } else if (!activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) ||
                                activity.getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
                                result.success("ready")
                            } else if (!activity.packageManager.canRequestPackageInstalls()) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:${activity.packageName}")))
                                result.success("permission_required")
                            } else {
                                val uri = FileProvider.getUriForFile(activity,
                                    "${activity.packageName}.updates", file)
                                activity.startActivity(Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                                result.success("installer_opened")
                            }
                        } catch (_: Exception) { result.error("UPDATE_INSTALL", "Не удалось открыть установку обновления", null) }
                    }
                } catch (_: IOException) {
                    activity.runOnUiThread { result.error("UPDATE_SPACE",
                        "Не удалось подготовить обновление. Проверьте свободное место и повторите. Скачанный файл сохранён.", null) }
                } catch (_: Exception) {
                    activity.runOnUiThread { result.error("UPDATE_INVALID", "Обновление не прошло проверку подписи и целостности", null) }
                }
            }
        }
    }

    fun dispose() {
        sequence.incrementAndGet()
        executor.shutdown()
    }
}
