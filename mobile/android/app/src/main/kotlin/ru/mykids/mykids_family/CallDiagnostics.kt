package ru.mykids.mykids_family

import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.media.AudioManager
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/** A support report contains device/error categories, never family data or tokens. */
object CallDiagnostics {
    private fun store(context: Context) =
        context.getSharedPreferences("call_diagnostics", Context.MODE_PRIVATE)

    fun record(context: Context, stage: String, code: String) {
        store(context).edit()
            .putString("stage", stage.take(60)).putString("code", code.take(60))
            .putLong("time", System.currentTimeMillis()).apply()
    }

    fun incomingPush(context: Context, message: RemoteMessage, route: String) {
        val now = System.currentTimeMillis()
        // Record only transport timings, priority and device state. Never
        // copy the payload, caller, account, call ID or Firebase token.
        val facts = JSONObject().apply {
            put("route", route)
            put("receivedAt", now)
            put("sentAt", message.sentTime)
            put("delayMs", if (message.sentTime > 0) now - message.sentTime else JSONObject.NULL)
            put("priority", message.priority)
            put("originalPriority", message.originalPriority)
            put("ttl", message.ttl)
            put("deviceLocked", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
            put("interactive", context.getSystemService(PowerManager::class.java).isInteractive)
            put("expiresInSeconds", message.data["expires_at"]?.toLongOrNull()?.let { it - now / 1000 } ?: JSONObject.NULL)
        }
        val key = if (message.data["kind"] == "call") "lastIncomingPush" else "lastCallStatePush"
        val edit = store(context).edit().putString(key, facts.toString())
        if (key == "lastIncomingPush") {
            edit.putString("incomingOutcome", "received").putLong("incomingOutcomeTime", now)
        }
        edit.apply()
    }

    fun incomingOutcome(context: Context, result: String) {
        store(context).edit().putString("incomingOutcome", result.take(60))
            .putLong("incomingOutcomeTime", System.currentTimeMillis()).apply()
    }

    fun incomingScreen(context: Context) {
        store(context).edit().putLong("lastIncomingScreenTime", System.currentTimeMillis()).apply()
    }

    fun permissions(context: Context): Map<String, Any> {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = FamilyIncomingCalls.channel(context)
        val groupBlocked = if (Build.VERSION.SDK_INT >= 28 && channel.group != null)
            manager.getNotificationChannelGroup(channel.group)?.isBlocked == true else false
        return mapOf("notifications" to manager.areNotificationsEnabled(),
            "fullScreen" to (Build.VERSION.SDK_INT < 34 || manager.canUseFullScreenIntent()),
            "callAlerts" to (channel.importance >= NotificationManager.IMPORTANCE_HIGH && !groupBlocked),
            "lockScreen" to (channel.lockscreenVisibility != Notification.VISIBILITY_SECRET),
            "microphone" to (ContextCompat.checkSelfPermission(context, android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED),
            "camera" to (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED),
            "phone" to "${Build.MANUFACTURER} ${Build.MODEL}", "android" to Build.VERSION.RELEASE)
    }

    fun report(context: Context): Map<String, Any?> {
        val stored = store(context)
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val audio = context.getSystemService(AudioManager::class.java)
        val route = if (Build.VERSION.SDK_INT >= 31) audio.communicationDevice?.type else null
        val exits = if (Build.VERSION.SDK_INT >= 30) {
            context.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(context.packageName, 0, 3).map {
                    mapOf("reason" to it.reason, "status" to it.status, "time" to it.timestamp)
                }
        } else emptyList()
        val manager = context.getSystemService(NotificationManager::class.java)
        val channel = FamilyIncomingCalls.channel(context)
        fun pushFacts(key: String): Map<String, Any?>? {
            val raw = stored.getString(key, null) ?: return null
            return try {
                val value = JSONObject(raw)
                value.keys().asSequence().associateWith { value.opt(it).let { item -> if (item == JSONObject.NULL) null else item } }
            } catch (_: org.json.JSONException) { null }
        }
        return permissions(context) + mapOf(
            "version" to packageInfo.versionName, "lastStage" to stored.getString("stage", null),
            "lastCode" to stored.getString("code", null), "lastErrorTime" to stored.getLong("time", 0),
            "audioMode" to audio.mode, "audioRouteType" to route, "recentProcessExits" to exits,
            "deviceTime" to System.currentTimeMillis(),
            "nativeAccountReady" to FamilyIncomingCalls.identityReady(context),
            "backgroundRestricted" to (Build.VERSION.SDK_INT >= 28 && context.getSystemService(ActivityManager::class.java).isBackgroundRestricted),
            "batteryUnrestricted" to context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName),
            "notificationsPaused" to (Build.VERSION.SDK_INT >= 29 && manager.areNotificationsPaused()),
            "interruptionFilter" to manager.currentInterruptionFilter,
            "callChannelImportance" to channel.importance,
            "callChannelHasSound" to (channel.sound != null),
            "lastIncomingPush" to pushFacts("lastIncomingPush"),
            "lastCallStatePush" to pushFacts("lastCallStatePush"),
            "incomingOutcome" to stored.getString("incomingOutcome", null),
            "incomingOutcomeTime" to stored.getLong("incomingOutcomeTime", 0),
            "lastIncomingScreenTime" to stored.getLong("lastIncomingScreenTime", 0))
    }
}
