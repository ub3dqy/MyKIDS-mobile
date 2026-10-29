package ru.mykids.mykids_family

import android.app.Notification
import android.app.ActivityOptions
import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.Parcel
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import io.flutter.plugins.firebase.messaging.FlutterFirebaseRemoteMessageLiveData
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingBackgroundService
import io.flutter.plugins.firebase.messaging.ContextHolder
import java.util.UUID
import java.util.concurrent.Executors

/** Handle the actual FlutterFire broadcast entry point before starting Dart. */
class FamilyMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    companion object {
        private val executor = Executors.newSingleThreadExecutor()
    }
    override fun onReceive(context: Context, intent: Intent) {
        val extras = intent.extras ?: return
        val message = RemoteMessage(extras)
        if (message.data["kind"] !in listOf("call", "call_state")) {
            if (FamilyCalendarSync.handles(context, message)) {
                if (!FamilyIncomingCalls.claimMessage(message)) return
                val pending = goAsync()
                FamilyCalendarSync.execute {
                    try {
                        FamilyCalendarSync.enqueue(context, message, "receiver")
                    } catch (failure: Exception) {
                        CallDiagnostics.record(context, "calendar_push", failure.javaClass.simpleName)
                        // The original durable FlutterFire path remains a
                        // fallback if native scheduling is unavailable.
                        super.onReceive(context, intent)
                    } finally {
                        pending.finish()
                    }
                }
                return
            }
            if (FamilyIncomingCalls.claimMessage(message)) super.onReceive(context, intent)
            return
        }
        // Keep the broadcast alive while preferences and notification work run
        // off the main thread, just as FlutterFire does for other messages.
        val pending = goAsync()
        executor.execute {
            try {
                FamilyIncomingCalls.message(context, message, "receiver")
            } catch (failure: Exception) {
                CallDiagnostics.incomingOutcome(context, "processing_failed")
                CallDiagnostics.record(context, "incoming_push", failure.javaClass.simpleName)
            } finally {
                pending.finish()
            }
        }
    }
}

/** Retain the Firebase SDK service path used by existing phone installations. */
class FamilyMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.data["kind"] !in listOf("call", "call_state")) {
            // FlutterFire's service implementation intentionally does nothing:
            // it normally relies on its broadcast receiver. Preserve generic
            // delivery too when the SDK reaches this service directly.
            if (!FamilyIncomingCalls.claimMessage(message)) return
            if (FamilyCalendarSync.handles(this, message)) {
                try {
                    FamilyCalendarSync.enqueue(this, message, "service")
                    return
                } catch (failure: Exception) {
                    CallDiagnostics.record(this, "calendar_push", failure.javaClass.simpleName)
                }
            }
            if (ContextHolder.getApplicationContext() == null) ContextHolder.setApplicationContext(applicationContext)
            if (FamilyIncomingCalls.foreground(this)) {
                FlutterFirebaseRemoteMessageLiveData.getInstance().postRemoteMessage(message)
            } else {
                val intent = Intent(this, FlutterFirebaseMessagingBackgroundService::class.java)
                val parcel = Parcel.obtain()
                try {
                    message.writeToParcel(parcel, 0)
                    // The pinned FlutterFire background service expects this key.
                    intent.putExtra("notification", parcel.marshall())
                } finally {
                    parcel.recycle()
                }
                FlutterFirebaseMessagingBackgroundService.enqueueMessageProcessing(this, intent,
                    message.originalPriority == RemoteMessage.PRIORITY_HIGH)
            }
            return
        }
        try {
            FamilyIncomingCalls.message(this, message, "service")
        } catch (failure: Exception) {
            CallDiagnostics.incomingOutcome(this, "processing_failed")
            CallDiagnostics.record(this, "incoming_push", failure.javaClass.simpleName)
        }
    }
}

object FamilyIncomingCalls {
    const val CHANGED = "ru.mykids.mykids_family.CALL_CHANGED"
    private const val CHANNEL = "family_calls_native_v1"
    private fun prefs(context: Context) = context.getSharedPreferences("family_incoming_calls", Context.MODE_PRIVATE)
    private fun notificationId(id: String) = 1000 + (id.hashCode() and Int.MAX_VALUE) % 500000000
    private fun validId(id: String) = Regex("^[0-9a-f]{32}$").matches(id)
    private val receivedMessages = LinkedHashSet<String>()

    @Synchronized
    fun claimMessage(message: RemoteMessage): Boolean {
        message.messageId?.let {
            if (!receivedMessages.add(it)) return false
            if (receivedMessages.size > 100) receivedMessages.remove(receivedMessages.first())
        }
        return true
    }

    fun foreground(context: Context): Boolean =
        !context.getSystemService(KeyguardManager::class.java).isKeyguardLocked &&
            context.getSystemService(PowerManager::class.java).isInteractive &&
            context.getSystemService(ActivityManager::class.java).runningAppProcesses?.any {
                it.pid == Process.myPid() && it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            } == true

    @Synchronized
    fun message(context: Context, message: RemoteMessage, route: String) {
        // Some delivery implementations may use both registered Firebase
        // entry points. Process one transport message only once per process.
        if (!claimMessage(message)) return
        CallDiagnostics.incomingPush(context, message, route)
        receive(context, message.data, foreground(context))
    }

    @Synchronized
    fun identityReady(context: Context): Boolean =
        validId(prefs(context).getString("user", "") ?: "") &&
            Regex("^[0-9a-f]{64}$").matches(prefs(context).getString("session", "") ?: "")

    fun channel(context: Context): NotificationChannel {
        val manager = context.getSystemService(NotificationManager::class.java)
        val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        manager.createNotificationChannel(NotificationChannel(CHANNEL, "Входящие семейные звонки", NotificationManager.IMPORTANCE_HIGH).apply {
            setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE), attributes)
            enableVibration(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        })
        // Reusing the channel preserves choices made in the phone settings.
        return manager.getNotificationChannel(CHANNEL)
    }

    fun settingsIntent(): Intent = Intent(android.provider.Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
        .putExtra(android.provider.Settings.EXTRA_CHANNEL_ID, CHANNEL)

    @Synchronized
    fun caller(context: Context, intent: Intent): String =
        if (validIntent(context, intent)) prefs(context).getString("caller:${intent.getStringExtra("family_call_id")}", "Семейный звонок") ?: "Семейный звонок"
        else "Семейный звонок"

    @Synchronized
    fun identity(context: Context, user: String, session: String) {
        val store = prefs(context)
        if (store.getString("session", "") != session || store.getString("user", "") != user) {
            val manager = context.getSystemService(NotificationManager::class.java)
            store.all.keys.filter { it.startsWith("nonce:") }.forEach {
                manager.cancel(notificationId(it.substringAfter(':')))
            }
            store.edit().clear().apply()
        }
        if (validId(user) && Regex("^[0-9a-f]{64}$").matches(session)) {
            store.edit().putString("user", user).putString("session", session).apply()
        }
        context.sendBroadcast(Intent(CHANGED).setPackage(context.packageName))
    }

    @Synchronized
    fun dismiss(context: Context, id: String) {
        if (!validId(id)) return
        context.getSystemService(NotificationManager::class.java).cancel(notificationId(id))
        prefs(context).edit().remove("nonce:$id").apply()
        prefs(context).edit().remove("expiry:$id").apply()
        prefs(context).edit().remove("caller:$id").apply()
    }

    // The UI can switch accounts while this broadcast runs on its worker.
    // Keep validation and posting in the same lock as identity changes.
    @Synchronized
    fun receive(context: Context, data: Map<String, String>, foreground: Boolean = false) {
        val store = prefs(context)
        fun rejected(reason: String) {
            if (data["kind"] == "call") CallDiagnostics.incomingOutcome(context, reason)
        }
        val id = data["entity_id"]
        val user = data["user_id"]
        if (id == null || user == null || !validId(id)) { rejected("invalid_message"); return }
        if (!identityReady(context)) { rejected("account_not_ready"); return }
        if (user != store.getString("user", "")) { rejected("different_account"); return }
        val now = System.currentTimeMillis() / 1000
        store.all.filterKeys { it.startsWith("expiry:") }.forEach { (key, value) ->
            if (value is Long && value <= now) dismiss(context, key.substringAfter(':'))
        }
        // End markers also prevent a reordered invitation from ringing again.
        store.all.filterKeys { it.startsWith("closed:") }.forEach { (key, value) ->
            if (value is Long && value < now - 7200) store.edit().remove(key).apply()
        }
        if (data["kind"] == "call_state") {
            if (data["closed"] == "true") {
                store.edit().putLong("closed:$id", now).apply()
                dismiss(context, id)
            }
            context.sendBroadcast(Intent(CHANGED).setPackage(context.packageName))
            return
        }
        val expires = data["expires_at"]?.toLongOrNull()
        if (expires == null) { rejected("invalid_expiration"); return }
        if (expires <= now) { rejected("expired"); return }
        if (expires > now + 65) { rejected("clock_difference"); return }
        if (store.contains("closed:$id")) { rejected("already_closed"); return }
        if (store.getString("nonce:$id", null) != null && store.getLong("expiry:$id", 0) > now) {
            // A retry after process restart must keep the original buttons
            // valid instead of replacing the nonce underneath the open screen.
            rejected("duplicate_invitation")
            return
        }
        if (foreground) {
            // The app shows its invitation and plays its ringtone after this
            // refresh. Avoid posting a second audible invitation on top of it.
            CallDiagnostics.incomingOutcome(context, "foreground_refresh")
            context.sendBroadcast(Intent(CHANGED).setPackage(context.packageName))
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java)
        if (!manager.areNotificationsEnabled()) { rejected("notifications_disabled"); return }
        val callChannel = channel(context)
        if (callChannel.importance == NotificationManager.IMPORTANCE_NONE) { rejected("call_channel_disabled"); return }
        val caller = (data["caller_name"] ?: "Семейный звонок")
            .replace(Regex("[\\p{Cntrl}\\u202a-\\u202e\\u2066-\\u2069]"), " ").trim().take(200)
            .ifEmpty { "Семейный звонок" }
        val nonce = UUID.randomUUID().toString()
        store.edit().putString("nonce:$id", nonce).putLong("expiry:$id", expires).putString("caller:$id", caller).apply()
        fun action(value: String): PendingIntent {
            val intent = Intent(context, FamilyIncomingCallActivity::class.java)
                .setData(Uri.parse("mykids://incoming/$id/$value"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                .putExtra("family_call_id", id).putExtra("family_call_user", user)
                .putExtra("family_call_nonce", nonce).putExtra("family_call_expires", expires)
                .putExtra("family_call_action", value)
                .putExtra("family_call_video", data["video"] == "true")
            // This immutable intent can only open the private incoming-call
            // activity, whose account, nonce and expiry are checked again.
            // Android 15+ requires the creator to explicitly grant the
            // background launch needed by an urgent call on the lock screen.
            val options = if (Build.VERSION.SDK_INT >= 35) ActivityOptions.makeBasic().apply {
                setPendingIntentCreatorBackgroundActivityStartMode(
                    if (Build.VERSION.SDK_INT >= 36) ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOW_ALWAYS
                    else ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
            }.toBundle() else null
            return PendingIntent.getActivity(context, notificationId(id), intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE, options)
        }
        val open = action("show")
        val answer = action("answer")
        val decline = action("decline")
        val builder = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.mykids_notification)
            .setContentTitle(caller)
            .setContentText(if (data["video"] == "true") "Входящий видеозвонок MyKIDS" else "Входящий аудиозвонок MyKIDS")
            .setSubText("MyKIDS")
            .setCategory(Notification.CATEGORY_CALL).setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(open).setFullScreenIntent(open, true)
            .setTimeoutAfter((expires - now) * 1000).setOngoing(true)
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setStyle(Notification.CallStyle.forIncomingCall(
                Person.Builder().setName(caller).setImportant(true).build(), decline, answer)
                .setIsVideo(data["video"] == "true"))
        } else {
            builder.addAction(Notification.Action.Builder(null, "Отклонить", decline).build())
                .addAction(Notification.Action.Builder(null, "Ответить", answer).build())
        }
        val notification = builder.build()
        notification.flags = notification.flags or Notification.FLAG_INSISTENT
        manager.notify(notificationId(id), notification)
        CallDiagnostics.incomingOutcome(context, "notification_posted")
        context.sendBroadcast(Intent(CHANGED).setPackage(context.packageName))
    }

    @Synchronized
    fun validIntent(context: Context, intent: Intent?): Boolean {
        if (intent == null) return false
        val id = intent.getStringExtra("family_call_id") ?: return false
        val nonce = intent.getStringExtra("family_call_nonce") ?: return false
        val store = prefs(context)
        return validId(id) && !store.contains("closed:$id") &&
            intent.getStringExtra("family_call_user") == store.getString("user", "") &&
            nonce == store.getString("nonce:$id", null) &&
            intent.getLongExtra("family_call_expires", 0) > System.currentTimeMillis() / 1000
    }

    @Synchronized
    fun takeIntent(context: Context, intent: Intent?): Map<String, String>? {
        if (!validIntent(context, intent) || intent!!.getBooleanExtra("family_call_handled", false)) return null
        intent.putExtra("family_call_handled", true)
        return mapOf("id" to intent.getStringExtra("family_call_id")!!,
            "nonce" to intent.getStringExtra("family_call_nonce")!!,
            "user" to intent.getStringExtra("family_call_user")!!,
            "action" to (intent.getStringExtra("family_call_action") ?: "show"))
    }
}
