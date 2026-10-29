package ru.mykids.mykids_family;

import static org.junit.Assert.*;

import android.content.Context;
import android.content.pm.ProviderInfo;
import android.net.Uri;
import androidx.core.content.FileProvider;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.SecureRandom;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Exercise the real Android provider, not a host filesystem substitute. */
@RunWith(AndroidJUnit4.class)
public class VerifiedUpdateProviderTest {
    @Test public void installerReadsOnlyThePrivateVerifiedCopy() throws Exception {
        Context context = InstrumentationRegistry.getInstrumentation().getTargetContext();
        String authority = context.getPackageName() + ".updates";
        ProviderInfo provider = context.getPackageManager().resolveContentProvider(authority, 0);
        assertNotNull(provider);
        assertFalse(provider.exported);
        assertTrue(provider.grantUriPermissions);
        byte[] bytes = new byte[65539];
        new SecureRandom().nextBytes(bytes);
        StringBuilder hash = new StringBuilder();
        for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes)) {
            hash.append(String.format("%02x", value & 255));
        }
        File source = File.createTempFile("mykids-update-provider-", ".apk", context.getExternalFilesDir(null));
        File staged = null;
        try {
            try (FileOutputStream output = new FileOutputStream(source)) { output.write(bytes); }
            staged = VerifiedUpdateFiles.INSTANCE.stage(
                new File(context.getFilesDir(), VerifiedUpdateFiles.DIRECTORY), source, bytes.length, hash.toString());
            Uri uri = FileProvider.getUriForFile(context, authority, staged);
            assertEquals("content", uri.getScheme());
            assertTrue(uri.getPath().startsWith("/verified-updates/"));
            try (FileOutputStream output = new FileOutputStream(source)) { output.write(new byte[bytes.length]); }
            try (InputStream input = context.getContentResolver().openInputStream(uri)) {
                assertNotNull(input);
                java.io.ByteArrayOutputStream content = new java.io.ByteArrayOutputStream();
                byte[] buffer = new byte[4096];
                for (int count; (count = input.read(buffer)) != -1;) { content.write(buffer, 0, count); }
                assertArrayEquals(bytes, content.toByteArray());
            }
            try {
                FileProvider.getUriForFile(context, authority, source);
                fail("The external download directory must not be shared with the installer");
            } catch (IllegalArgumentException expected) { /* The original mutable file is outside the provider. */ }
        } finally {
            assertTrue(!source.exists() || source.delete());
            if (staged != null) assertTrue(!staged.exists() || staged.delete());
        }
    }
}
