package ru.mykids.mykids_family

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.SharedPreferenceHelper
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Recover queues saved by older releases, without opening an activity. */
class FamilyOutboxRecovery : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            intent.action != Intent.ACTION_BOOT_COMPLETED) return
        // Before the first normal setup there is no account or registered worker.
        if (SharedPreferenceHelper.getCallbackHandle(context) == -1L) return
        val pending = goAsync()
        val app = context.applicationContext
        executor.execute {
            try {
                val builder = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                    .setInputData(buildTaskInputData("family-sync", null, uniqueName = "mykids-outbox"))
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                if (Build.VERSION.SDK_INT >= 31) {
                    builder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                }
                // Preserve in-flight work and revive a previously failed chain.
                WorkManager.getInstance(app).enqueueUniqueWork(
                    "mykids-outbox", ExistingWorkPolicy.APPEND_OR_REPLACE, builder.build()
                ).result.get(8, TimeUnit.SECONDS)
            } catch (_: Exception) {
                // Existing WorkManager rescheduling and periodic sync remain intact.
                Log.w("MyKIDSOutbox", "Upload recovery scheduling unavailable")
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        private val executor = Executors.newSingleThreadExecutor()
    }
}
