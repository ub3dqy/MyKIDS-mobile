package ru.mykids.mykids_family

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.google.firebase.messaging.RemoteMessage
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.SharedPreferenceHelper
import dev.fluttercommunity.workmanager.buildTaskInputData
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Schedule before FlutterFire's ordinary dispatch job can be delayed by power saving. */
object FamilyCalendarSync {
    private const val WORK = "mykids-push-calendar-native"
    private const val JOURNAL = "family_calendar_sync"
    private val executor = Executors.newFixedThreadPool(2)

    fun handles(context: Context, message: RemoteMessage): Boolean =
        message.data["kind"] == "calendar" && Build.VERSION.SDK_INT >= 31 &&
            !FamilyIncomingCalls.foreground(context) &&
            SharedPreferenceHelper.getCallbackHandle(context) != -1L

    fun execute(action: () -> Unit) = executor.execute(action)

    fun enqueue(context: Context, message: RemoteMessage, route: String) {
        // Power preferences may change while the connected work is waiting.
        // A short calendar refresh uses Android's bounded expedited quota;
        // normal durable execution remains the fallback when quota is spent.
        val request = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
            .setInputData(buildTaskInputData("family-sync", null, uniqueName = WORK))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        // Retain every invalidation, including one arriving while a sync is in
        // flight, and do not put it behind an ordinary power-restricted job.
        WorkManager.getInstance(context)
            .enqueueUniqueWork(WORK, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
            .result.get(8, TimeUnit.SECONDS)
        record(context, message.messageId, request.id.toString(), route)
    }

    @Synchronized
    private fun record(context: Context, messageId: String?, workId: String, route: String) {
        if (messageId == null) return
        try {
            // Bounded private transport diagnostics contain no payload,
            // account, token, task or calendar data, or raw provider IDs.
            val hash = MessageDigest.getInstance("SHA-256")
                .digest(messageId.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
            val prefs = context.getSharedPreferences(JOURNAL, Context.MODE_PRIVATE)
            val records = prefs.all.filterKeys { it.matches(Regex("[0-9a-f]{64}")) }
            val edit = prefs.edit()
            val retained = records.filterKeys { it != hash }.entries.sortedBy {
                runCatching { JSONObject(it.value as String).optLong("received_at") }.getOrDefault(0L)
            }
            retained.take((retained.size - 63).coerceAtLeast(0)).forEach { edit.remove(it.key) }
            edit.putString(hash, JSONObject().apply {
                put("message_hash", hash)
                put("work_id", workId)
                put("received_at", System.currentTimeMillis())
                put("route", route)
                put("enqueued", true)
            }.toString()).commit()
        } catch (_: Exception) {
            // Diagnostics must never undo a successfully persisted refresh.
            Log.w("MyKIDSCalendarSync", "Transport diagnostics unavailable")
        }
    }
}
