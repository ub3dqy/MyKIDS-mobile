package ru.mykids.mykids_family

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import java.util.UUID
import android.view.WindowManager
import android.app.KeyguardManager
import android.graphics.Color
import android.widget.FrameLayout
import android.widget.TextView
import android.view.Gravity
import androidx.core.content.ContextCompat
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.AudioAttributes
import androidx.lifecycle.Lifecycle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var updates: FamilyUpdates? = null
    private var ringtone: Ringtone? = null
    private var callChannel: MethodChannel? = null
    private var callCover: TextView? = null
    private val ownership get() = FamilyCallService.ownership
    private val handler = Handler(Looper.getMainLooper())
    private data class CallStart(val owner: String, val result: MethodChannel.Result)
    private val callStarts = mutableMapOf<String, CallStart>()
    private fun coverIncoming() {
        if (!FamilyIncomingCalls.validIntent(this, intent) || callCover != null) return
        callCover = TextView(this).apply {
            text = "MyKIDS\nПодключаем семейный звонок…"
            gravity = Gravity.CENTER
            textSize = 22f
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.rgb(15, 23, 40))
            isClickable = true
        }
        findViewById<FrameLayout>(android.R.id.content).addView(callCover, FrameLayout.LayoutParams(-1, -1))
    }
    private fun revealIncoming() {
        callCover?.let { findViewById<FrameLayout>(android.R.id.content).removeView(it) }
        callCover = null
    }
    private val callChanged = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == FamilyCallService.RESULT) {
                val request = intent.getStringExtra("request")
                val pending = callStarts.remove(request) ?: return
                if (!ownership.matches(pending.owner, request) || intent.getStringExtra("owner") != pending.owner) {
                    pending.result.error("CALL_SERVICE", "Этот экран звонка уже закрыт", null)
                    return
                }
                val error = intent.getStringExtra("error")
                if (error == null) pending.result.success(null)
                else pending.result.error("CALL_SERVICE", error, null)
                return
            }
            callChannel?.invokeMethod("callChanged", null)
        }
    }
    private fun callWindow(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(enabled); setTurnScreenOn(enabled) }
        else if (enabled) window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        val allowed = FamilyIncomingCalls.validIntent(this, intent)
        super.onCreate(savedInstanceState)
        callWindow(allowed || ownership.windowActive)
        coverIncoming()
        ContextCompat.registerReceiver(this, callChanged, IntentFilter(FamilyIncomingCalls.CHANGED).apply {
            addAction(FamilyCallService.RESULT)
        }, ContextCompat.RECEIVER_NOT_EXPORTED)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("resume_call", false) && ownership.windowActive) {
            callWindow(true)
            return
        }
        setIntent(intent)
        callWindow(ownership.windowActive || FamilyIncomingCalls.validIntent(this, intent))
        coverIncoming()
        callChannel?.invokeMethod("incoming", null)
    }
    private fun stopRinging() { ringtone?.stop(); ringtone = null }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        updates?.dispose()
        updates = FamilyUpdates(this).also {
            it.attach(MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.mykids/updates"))
        }
        callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.mykids/calls")
        callChannel!!.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "copyInvitation" -> {
                            check(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) && !isFinishing &&
                                !getSystemService(KeyguardManager::class.java).isKeyguardLocked) {
                                "Open the unlocked application before copying an invitation"
                            }
                            InvitationClipboard.copy(this, call.argument<String>("token"))
                        }
                        "identity" -> FamilyIncomingCalls.identity(this, call.argument<String>("user") ?: "", call.argument<String>("session") ?: "")
                        "pendingIncoming" -> { result.success(FamilyIncomingCalls.takeIntent(this, intent)); return@setMethodCallHandler }
                        "dismissIncoming" -> FamilyIncomingCalls.dismiss(this, call.argument<String>("id") ?: "")
                        "claimCall" -> {
                            val owner = call.argument<String>("owner") ?: error("Missing call owner")
                            val id = call.argument<String>("id") ?: error("Missing call id")
                            require(owner.isNotBlank() && owner.length <= 200 && id.isNotBlank() && id.length <= 200)
                            ownership.claim(owner, id)
                        }
                        "revealIncoming" -> {
                            if (ownership.ownsCall(call.argument<String>("owner"), call.argument<String>("id")) &&
                                intent.getStringExtra("family_call_id") == call.argument<String>("id")) revealIncoming()
                        }
                        "finishIncoming" -> {
                            if (!ownership.windowActive &&
                                intent.getStringExtra("family_call_id") == call.argument<String>("id") &&
                                intent.getStringExtra("family_call_nonce") == call.argument<String>("nonce") &&
                                intent.getStringExtra("family_call_user") == call.argument<String>("user")) {
                                callWindow(false)
                                if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) moveTaskToBack(true)
                                revealIncoming()
                            }
                        }
                        "finishCallScreen" -> {
                            if (ownership.owns(call.argument<String>("owner")) && !ownership.windowActive &&
                                !FamilyIncomingCalls.validIntent(this, intent)) {
                                callWindow(false)
                                if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) moveTaskToBack(true)
                            }
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        "permissions" -> {
                            result.success(CallDiagnostics.permissions(this))
                            return@setMethodCallHandler
                        }
                        "callDiagnostics" -> { result.success(CallDiagnostics.report(this)); return@setMethodCallHandler }
                        "deviceLocked" -> { result.success(getSystemService(KeyguardManager::class.java).isKeyguardLocked); return@setMethodCallHandler }
                        "reportCallFailure" -> CallDiagnostics.record(this,
                            call.argument<String>("stage") ?: "call", call.argument<String>("code") ?: "unknown")
                        "ring" -> {
                            if (lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) && !isFinishing) {
                                if (ringtone == null) ringtone = RingtoneManager.getRingtone(this,
                                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)).also {
                                    it?.audioAttributes = AudioAttributes.Builder()
                                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
                                    if (Build.VERSION.SDK_INT >= 28) it?.isLooping = true
                                }
                                if (ringtone?.isPlaying != true) ringtone?.play()
                            }
                        }
                        "stopRinging" -> stopRinging()
                        "start" -> {
                            val owner = call.argument<String>("owner") ?: error("Missing call owner")
                            val request = UUID.randomUUID().toString()
                            check(ownership.start(owner, request)) { "Closed call screen" }
                            callWindow(true)
                            callStarts[request] = CallStart(owner, result)
                            val intent = Intent(this, FamilyCallService::class.java)
                                .putExtra("video", call.argument<Boolean>("video") ?: false)
                                .putExtra("owner", owner)
                                .putExtra("request", request)
                            try {
                                startForegroundService(intent)
                            } catch (failure: Exception) {
                                callStarts.remove(request)
                                CallDiagnostics.record(this, "call_service_start", failure.javaClass.simpleName)
                                throw failure
                            }
                            handler.postDelayed({
                                callStarts.remove(request)?.let {
                                    if (ownership.expire(it.owner, request)) stopService(Intent(this, FamilyCallService::class.java))
                                    it.result.error("CALL_SERVICE", "Телефон не запустил службу звонка. Попробуйте ещё раз", null)
                                }
                            }, 4500)
                            return@setMethodCallHandler
                        }
                        "stop" -> {
                            if (ownership.stop(call.argument<String>("owner"))) {
                                stopService(Intent(this, FamilyCallService::class.java))
                                callWindow(FamilyIncomingCalls.validIntent(this, intent))
                            }
                        }
                        "notificationSettings" -> startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        )
                        "callNotificationSettings" -> startActivity(FamilyIncomingCalls.settingsIntent()
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                        "batterySettings" -> startActivity(
                            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        )
                        "fullScreenSettings" -> {
                            if (Build.VERSION.SDK_INT >= 34) {
                                startActivity(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.parse("package:$packageName")))
                            } else {
                                startActivity(FamilyIncomingCalls.settingsIntent()
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName))
                            }
                        }
                        else -> { result.notImplemented(); return@setMethodCallHandler }
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("CALL_SERVICE", "Не удалось изменить настройки звонка", null)
                }
            }
    }

    override fun onPause() {
        stopRinging()
        super.onPause()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        callStarts.values.forEach { it.result.error("CALL_SERVICE", "Экран звонка закрыт", null) }
        callStarts.clear()
        unregisterReceiver(callChanged)
        callChannel = null
        stopRinging()
        updates?.dispose()
        super.onDestroy()
    }
}
