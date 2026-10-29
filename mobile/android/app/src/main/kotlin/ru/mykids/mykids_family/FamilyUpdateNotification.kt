package ru.mykids.mykids_family

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** A tap on the system download notification opens MyKIDS, never an unchecked APK. */
class FamilyUpdateNotification : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_NOTIFICATION_CLICKED) return
        val id = context.getSharedPreferences("mykids-update-download", Context.MODE_PRIVATE).getLong("id", -1)
        val ids = intent.getLongArrayExtra(DownloadManager.EXTRA_NOTIFICATION_CLICK_DOWNLOAD_IDS) ?: return
        if (id > 0 && id in ids) context.startActivity(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
    }
}
