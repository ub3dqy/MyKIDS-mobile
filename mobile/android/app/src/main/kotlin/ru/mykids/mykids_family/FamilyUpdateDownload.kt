package ru.mykids.mykids_family

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.MethodCall
import java.io.File
import java.security.MessageDigest

/** Android owns the transfer; destroying an Activity never cancels it. */
class FamilyUpdateDownload(context: Context) {
    companion object { private val lock = Any() }
    private val context = context.applicationContext
    private val manager = context.getSystemService(DownloadManager::class.java)
    private val preferences = context.getSharedPreferences("mykids-update-download", Context.MODE_PRIVATE)

    fun directory(): File = File(checkNotNull(context.getExternalFilesDir(null)), "mykids-updates").canonicalFile

    private data class Offer(val name: String, val code: Long, val bytes: Long, val hash: String, val url: String) {
        val identity: String get() = "$name|$code|$bytes|$hash|$url"
    }

    private fun offer(call: MethodCall): Offer {
        val name = call.argument<String>("fileName") ?: ""
        val code = call.argument<Number>("versionCode")?.toLong() ?: 0
        val bytes = call.argument<Number>("bytes")?.toLong() ?: 0
        val hash = call.argument<String>("sha256") ?: ""
        val url = call.argument<String>("url") ?: ""
        check(context.packageName == "ru.mykids.mykids_family.parent")
        check(Regex("MyKIDS-\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}\\.apk").matches(name))
        check(code in 1..2100000000L && bytes in 1..(512L * 1024 * 1024))
        check(Regex("[0-9a-f]{64}").matches(hash))
        check(url == "https://api.xn--80ajzgig.online/downloads/$name")
        return Offer(name, code, bytes, hash, url)
    }

    private fun file(offer: Offer): File {
        val directory = directory()
        val file = File(directory, offer.name).canonicalFile
        check(file.parentFile == directory)
        return file
    }

    private fun destinationMatches(local: String?, offer: Offer): Boolean {
        val uri = local?.let(Uri::parse) ?: return false
        val path = uri.path ?: return false
        return uri.scheme == "file" && File(path).canonicalFile == file(offer)
    }

    private fun valid(file: File, offer: Offer): Boolean {
        if (!file.isFile || file.length() != offer.bytes) return false
        val hash = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { stream ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == offer.hash
    }

    private fun remember(offer: Offer, id: Long) {
        check(preferences.edit().putString("identity", offer.identity).putLong("id", id)
            .putString("fileName", offer.name).commit())
    }

    // Recover even if Android killed the app between enqueue() and saving its ID.
    private fun find(offer: Offer): Long {
        manager.query(DownloadManager.Query()).use { cursor ->
            while (cursor.moveToNext()) {
                val url = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_URI))
                val local = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                // Android leaves LOCAL_URI null until it has created the destination file.
                if (url == offer.url && (local == null || destinationMatches(local, offer)) &&
                    cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TITLE)) == "Обновление MyKIDS") {
                    val id = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_ID))
                    remember(offer, id)
                    return id
                }
            }
        }
        return -1
    }

    private fun status(offer: Offer): Map<String, Any> {
        val id = if (preferences.getString("identity", null) == offer.identity)
            preferences.getLong("id", -1).takeIf { it > 0 } ?: find(offer) else -1
        if (id > 0) {
            manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                if (cursor.moveToFirst()) {
                    check(cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_URI)) == offer.url)
                    val state = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                    val local = cursor.getString(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI))
                    check((local == null && state != DownloadManager.STATUS_SUCCESSFUL) || destinationMatches(local, offer))
                    val received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                    val total = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
                    if (received > offer.bytes || (total > 0 && total != offer.bytes)) {
                        manager.remove(id)
                        return mapOf("state" to "failed", "message" to "Размер обновления не соответствует ожидаемому")
                    }
                    return when (state) {
                        DownloadManager.STATUS_PENDING, DownloadManager.STATUS_RUNNING, DownloadManager.STATUS_PAUSED ->
                            mapOf("state" to (if (state == DownloadManager.STATUS_PAUSED) "paused" else "running"),
                                "id" to id, "received" to received.coerceAtLeast(0), "bytes" to offer.bytes)
                        DownloadManager.STATUS_SUCCESSFUL -> if (valid(file(offer), offer))
                            mapOf("state" to "ready", "id" to id, "received" to offer.bytes, "bytes" to offer.bytes)
                        else mapOf("state" to "failed", "message" to "Файл обновления повреждён. Попробуйте скачать ещё раз")
                        else -> {
                            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                            mapOf("state" to "failed", "message" to
                                if (reason == DownloadManager.ERROR_INSUFFICIENT_SPACE)
                                    "Недостаточно места для скачивания обновления. Освободите память и попробуйте ещё раз."
                                else "Android не смог скачать обновление. Проверьте интернет и свободное место")
                        }
                    }
                }
            }
        }
        // Completed files remain usable when the system has cleared its download history.
        return if (valid(file(offer), offer))
            mapOf("state" to "ready", "received" to offer.bytes, "bytes" to offer.bytes)
        else mapOf("state" to "idle")
    }

    fun handle(call: MethodCall): Map<String, Any> = synchronized(lock) { handleRequest(call) }

    private fun handleRequest(call: MethodCall): Map<String, Any> {
        val offer = offer(call)
        if (call.method == "downloadStatus") return status(offer)
        if (call.method == "cancelDownload") {
            if (preferences.getString("identity", null) == offer.identity) {
                val id = preferences.getLong("id", -1).takeIf { it > 0 } ?: find(offer)
                if (id > 0) manager.remove(id)
                file(offer).delete()
                check(preferences.edit().clear().commit())
            }
            return mapOf("state" to "idle")
        }
        check(call.method == "startDownload")
        val existing = status(offer)
        if (existing["state"] in setOf("running", "paused", "ready")) return existing
        // Only an explicit new download replaces a failed or older update.
        val oldId = preferences.getLong("id", -1)
        if (oldId > 0) manager.remove(oldId)
        val oldName = preferences.getString("fileName", null)
        if (oldName != null && Regex("MyKIDS-\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}\\.apk").matches(oldName)) {
            val old = File(directory(), oldName).canonicalFile
            if (old.parentFile == directory()) old.delete()
        }
        check(directory().isDirectory || directory().mkdirs())
        val target = file(offer)
        check(!target.exists() || target.delete())
        remember(offer, -1)
        val request = DownloadManager.Request(Uri.parse(offer.url))
            .setDestinationInExternalFilesDir(context, null, "mykids-updates/${offer.name}")
            .setTitle("Обновление MyKIDS")
            .setDescription("Можно заблокировать телефон. Загрузка продолжится.")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverRoaming(false)
        val id = manager.enqueue(request)
        remember(offer, id)
        return status(offer)
    }
}
