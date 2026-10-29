package ru.mykids.mykids_family

import java.io.File
import java.nio.file.Files
import java.security.MessageDigest
import org.junit.Assert.*
import org.junit.Test

class VerifiedUpdateFilesTest {
    private fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 255) }

    private fun fixture(check: (File, File, ByteArray) -> Unit) {
        val root = Files.createTempDirectory("mykids-private-update-test-").toFile()
        try {
            val bytes = ByteArray(200000) { (it % 251).toByte() }
            val source = File(root, "external.apk").apply { writeBytes(bytes) }
            check(File(root, "internal"), source, bytes)
        } finally {
            root.walkBottomUp().forEach { it.setWritable(true) }
            root.deleteRecursively()
        }
    }

    @Test fun changingExternalApkAfterVerificationDoesNotChangeInstallerBytes() = fixture { directory, source, bytes ->
        val staged = VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), hash(bytes))
        assertEquals(directory.canonicalFile, staged.canonicalFile.parentFile)
        assertNotEquals(source.canonicalPath, staged.canonicalPath)
        source.writeBytes(ByteArray(bytes.size) { 7 })
        assertArrayEquals(bytes, staged.readBytes())
        assertFalse(directory.listFiles().orEmpty().any { it.name.endsWith(".partial") })
    }

    @Test fun repeatedAttemptReusesTheSameImmutableVerifiedBytes() = fixture { directory, source, bytes ->
        val first = VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), hash(bytes))
        source.writeBytes(ByteArray(bytes.size) { 1 })
        val again = VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), hash(bytes))
        assertEquals(first.canonicalFile, again.canonicalFile)
        assertArrayEquals(bytes, again.readBytes())
    }

    @Test fun badHashNeverPublishesAnInstallableFile() = fixture { directory, source, bytes ->
        try {
            VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), "0".repeat(64))
            fail("A modified download was accepted")
        } catch (_: IllegalStateException) { }
        assertTrue(directory.listFiles().orEmpty().isEmpty())
    }

    @Test fun truncatedOrGrowingSourceNeverPublishesAnInstallableFile() = fixture { directory, source, bytes ->
        for (length in listOf(bytes.size - 1, bytes.size + 1)) {
            try {
                VerifiedUpdateFiles.stage(directory, source, length.toLong(), hash(bytes))
                fail("An incorrect length was accepted")
            } catch (_: IllegalStateException) { }
            assertTrue(directory.listFiles().orEmpty().isEmpty())
        }
    }

    @Test fun restartingCleansInterruptedCopiesAndKeepsVerifiedPackages() = fixture { directory, source, bytes ->
        val staged = VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), hash(bytes))
        val interrupted = File(directory, ".copy-12345.partial").apply { writeText("unfinished") }
        val unrelated = File(directory, "owner-note").apply { writeText("keep") }
        VerifiedUpdateFiles.cleanupPartials(directory)
        assertFalse(interrupted.exists())
        assertTrue(unrelated.isFile)
        assertArrayEquals(bytes, staged.readBytes())
    }

    @Test fun anUnusablePrivateCacheCanBeRecoveredWithoutKeepingWrongBytes() = fixture { directory, source, bytes ->
        directory.mkdirs()
        File(directory, hash(bytes) + ".apk").writeText("interrupted or corrupted cache")
        val staged = VerifiedUpdateFiles.stage(directory, source, bytes.size.toLong(), hash(bytes))
        assertArrayEquals(bytes, staged.readBytes())
    }
}
