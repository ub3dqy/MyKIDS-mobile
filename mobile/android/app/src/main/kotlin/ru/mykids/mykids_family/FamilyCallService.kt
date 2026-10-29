package ru.mykids.mykids_family

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class FamilyCallService : Service() {
    companion object {
        const val RESULT = "ru.mykids.mykids_family.CALL_SERVICE_RESULT"
        val ownership = CallServiceOwnership()
    }
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val owner = intent?.getStringExtra("owner")
        val request = intent?.getStringExtra("request")
        if (!ownership.matches(owner, request)) {
            if (!ownership.windowActive) stopSelf(startId)
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(
            "ongoing_call", "Активный семейный звонок", NotificationManager.IMPORTANCE_LOW
        ))
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java)
                .putExtra("resume_call", true)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, "ongoing_call")
            .setSmallIcon(R.drawable.mykids_notification)
            .setContentTitle("MyKIDS — идёт семейный звонок")
            .setContentText("Откройте приложение для управления микрофоном и камерой")
            .setContentIntent(open)
            .setOngoing(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        val video = intent?.getBooleanExtra("video", false) == true
        var error: String? = null
        fun foreground(withCamera: Boolean) {
            if (Build.VERSION.SDK_INT >= 29) {
                val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    (if (withCamera) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0)
                startForeground(712, notification, type)
            } else startForeground(712, notification)
        }
        try {
            foreground(video)
        } catch (failure: Exception) {
            error = if (video) "Не удалось включить камеру. Звонок может продолжаться без видео" else
                "Телефон не разрешил включить микрофон для звонка. Проверьте разрешения MyKIDS"
            CallDiagnostics.record(this, if (video) "camera_service" else "microphone_service", failure.javaClass.simpleName)
            if (video) {
                try { foreground(false) } catch (_: Exception) { stopSelf() }
            } else stopSelf()
        }
        sendBroadcast(Intent(RESULT).setPackage(packageName)
            .putExtra("owner", owner).putExtra("request", request).putExtra("error", error))
        // Never restart microphone capture after process death.
        return START_NOT_STICKY
    }
}
