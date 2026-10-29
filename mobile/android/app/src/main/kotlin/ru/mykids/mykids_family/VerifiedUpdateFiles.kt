package ru.mykids.mykids_family

import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/** The installer must read the same private bytes that passed verification. */
internal object VerifiedUpdateFiles {
    const val DIRECTORY = "mykids-verified-updates"
    private val lock = Any()

    fun stage(directory: File, source: File, expectedBytes: Long, expectedHash: String): File = synchronized(lock) {
        require(expectedBytes in 1..(512L * 1024 * 1024))
        require(Regex("[0-9a-f]{64}").matches(expectedHash))
        check(directory.isDirectory || directory.mkdirs())
        val root = directory.canonicalFile
        val target = File(root, "$expectedHash.apk")
        if (target.isFile && target.length() == expectedBytes && hash(target) == expectedHash) {
            check(target.setReadOnly())
            return@synchronized target
        }
        // Intact staged files are immutable. Remove only an unusable cache,
        // then restore the exact same expected bytes under its hash.
        check(!target.exists() || target.delete())
        val partial = File.createTempFile(".copy-", ".partial", root)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            var total = 0L
            source.inputStream().use { input ->
                FileOutputStream(partial).use { output ->
                    val buffer = ByteArray(65536)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        check(total <= expectedBytes)
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            check(total == expectedBytes && hex(digest.digest()) == expectedHash)
            check(partial.setReadOnly())
            Files.move(partial.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            target
        } finally {
            partial.delete()
        }
    }

    fun cleanupPartials(directory: File) = synchronized(lock) {
        // The shared lock excludes every live copy, including another Activity.
        // Anything still named .partial is therefore an interrupted copy.
        val root = directory.canonicalFile
        for (file in root.listFiles().orEmpty()) {
            if (Regex("\\.copy-[A-Za-z0-9-]+\\.partial").matches(file.name) &&
                file.isFile && file.canonicalFile.parentFile == root) check(file.delete())
        }
    }

    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return hex(digest.digest())
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
}
