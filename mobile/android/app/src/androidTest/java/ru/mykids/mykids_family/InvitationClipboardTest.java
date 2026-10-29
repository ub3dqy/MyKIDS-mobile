package ru.mykids.mykids_family;

import static org.junit.Assert.*;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;

/** Actual system clipboard, confined by the host to its disposable Android guest. */
@RunWith(AndroidJUnit4.class)
public class InvitationClipboardTest {
    private void check(boolean invalid) {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        Activity activity = instrumentation.startActivitySync(new Intent()
            .setClassName(context, "ru.mykids.mykids_family.ClipboardProbeActivity")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        instrumentation.waitForIdleSync();
        String token = "a".repeat(43);
        try {
            instrumentation.runOnMainSync(() -> InvitationClipboard.INSTANCE.copy(activity, token));
            if (invalid) {
                instrumentation.runOnMainSync(() -> {
                    try {
                        InvitationClipboard.INSTANCE.copy(activity, "invalid");
                        fail("An invalid token must not replace a clipboard value");
                    } catch (IllegalArgumentException expected) { /* Valid prior content stays. */ }
                });
            }
            ClipboardManager clipboard = activity.getSystemService(ClipboardManager.class);
            assertTrue(clipboard.hasPrimaryClip());
            assertEquals(1, clipboard.getPrimaryClip().getItemCount());
            assertEquals(token, clipboard.getPrimaryClip().getItemAt(0).getText().toString());
            assertEquals("Приглашение MyKIDS", clipboard.getPrimaryClipDescription().getLabel());
            assertTrue(clipboard.getPrimaryClipDescription().getExtras()
                .getBoolean("android.content.extra.IS_SENSITIVE"));
        } finally {
            instrumentation.runOnMainSync(() -> {
                // This is a synthetic guest, without the owner's clipboard data.
                if (android.os.Build.VERSION.SDK_INT >= 28) {
                    activity.getSystemService(ClipboardManager.class).clearPrimaryClip();
                }
                activity.finish();
            });
        }
    }

    @Test public void invitationIsMarkedSensitiveInTheActualClipboard() { check(false); }
    @Test public void malformedInvitationCannotOverwriteTheActualClipboard() { check(true); }
}
