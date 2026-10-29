package ru.mykids.mykids_family

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.PersistableBundle

/** A family invitation grants access. Never show its text in the system preview. */
object InvitationClipboard {
    fun copy(context: Context, token: String?) {
        require(token != null && Regex("^[A-Za-z0-9_-]{43}$").matches(token)) {
            "Invalid family invitation"
        }
        val clip = ClipData.newPlainText("Приглашение MyKIDS", token).apply {
            description.extras = PersistableBundle().apply {
                // The documented literal is safe on every supported API (26+).
                putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        }
        context.getSystemService(ClipboardManager::class.java).setPrimaryClip(clip)
    }
}
