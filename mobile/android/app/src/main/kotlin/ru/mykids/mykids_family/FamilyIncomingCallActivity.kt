package ru.mykids.mykids_family

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.os.Build
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.ScrollView
import android.text.TextUtils
import androidx.core.content.ContextCompat

/** Only the caller and incoming-call controls are visible over the device lock. */
class FamilyIncomingCallActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var registered = false
    private val changed = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (!FamilyIncomingCalls.validIntent(this@FamilyIncomingCallActivity, this@FamilyIncomingCallActivity.intent)) finish()
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!FamilyIncomingCalls.validIntent(this, intent)) { finish(); return }
        CallDiagnostics.incomingScreen(this)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        if (intent.getStringExtra("family_call_action") in listOf("answer", "decline")) {
            forward(intent.getStringExtra("family_call_action")!!)
            return
        }
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(32, 32, 32, 32)
            setBackgroundColor(Color.rgb(15, 23, 40))
        }
        layout.addView(TextView(this).apply {
            text = "MyKIDS"
            textSize = 18f
            gravity = Gravity.CENTER
            setTextColor(Color.LTGRAY)
        })
        layout.addView(TextView(this).apply {
            text = FamilyIncomingCalls.caller(this@FamilyIncomingCallActivity, intent)
            textSize = 30f
            maxLines = 2
            ellipsize = TextUtils.TruncateAt.END
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 24)
            setTextColor(Color.WHITE)
        })
        layout.addView(TextView(this).apply {
            text = if (intent.getBooleanExtra("family_call_video", false)) "Входящий видеозвонок" else "Входящий аудиозвонок"
            textSize = 20f
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
        })
        layout.addView(TextView(this).apply {
            text = "Ответьте, чтобы начать разговор"
            textSize = 16f
            gravity = Gravity.CENTER
            setTextColor(Color.LTGRAY)
            setPadding(0, 24, 0, 48)
        })
        fun button(label: String, action: String, color: Int) = Button(this).apply {
            text = label
            textSize = 18f
            setTextColor(Color.WHITE)
            backgroundTintList = android.content.res.ColorStateList.valueOf(color)
            minHeight = (64 * resources.displayMetrics.density).toInt()
            setOnClickListener {
                if (!FamilyIncomingCalls.validIntent(this@FamilyIncomingCallActivity, intent)) { finish(); return@setOnClickListener }
                forward(action)
            }
        }
        layout.addView(button("Ответить", "answer", Color.rgb(18, 145, 83)), LinearLayout.LayoutParams(-1, -2))
        layout.addView(button("Отклонить", "decline", Color.rgb(209, 50, 67)), LinearLayout.LayoutParams(-1, -2))
        setContentView(ScrollView(this).apply { isFillViewport = true; addView(layout) })
        ContextCompat.registerReceiver(this, changed, IntentFilter(FamilyIncomingCalls.CHANGED), ContextCompat.RECEIVER_NOT_EXPORTED)
        registered = true
        val expires = intent.getLongExtra("family_call_expires", 0) * 1000
        handler.postDelayed({
            FamilyIncomingCalls.dismiss(this, intent.getStringExtra("family_call_id") ?: "")
            finish()
        }, (expires - System.currentTimeMillis()).coerceAtLeast(0))
    }
    private fun forward(action: String) {
        if (!FamilyIncomingCalls.validIntent(this, intent)) { finish(); return }
        startActivity(Intent(intent).setClass(this, MainActivity::class.java)
            .putExtra("family_call_action", action)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (registered) unregisterReceiver(changed)
        super.onDestroy()
    }
}
