package io.github.amchii.floatingclock

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat
import java.util.Calendar
import java.util.Locale

/**
 * 悬浮时钟前台服务。
 *
 * 关于"三分钟后自动退出"：此前该服务在 Manifest 中被声明为 shortService，
 * Android 14+ 规定 shortService 只能运行约 3 分钟，超时后系统回调 onTimeout
 * 并在数秒后直接判 ANR 杀掉应用，且 shortService 不支持 START_STICKY 重启。
 * 现已改为 specialUse（无运行时长上限、支持粘性重启），并从 startForeground()
 * 显式传入对应的 FGS 类型。
 *
 * 另外：配置（时间源偏移 / 别名 / 精度 / 小数颜色）会持久化到 SharedPreferences，
 * 即使进程被系统回收后由 START_STICKY 拉起，悬浮窗仍能以用户上次的配置恢复。
 */
class FloatingClockService : Service() {

    companion object {
        const val ACTION_STOP = "io.github.amchii.floatingclock.ACTION_STOP"
        private const val ACTION_OVERLAY_STOPPED =
            "io.github.amchii.floatingclock.OVERLAY_STOPPED"
        private const val CHANNEL_ID = "floating_clock_channel"
        private const val NOTIFICATION_ID = 1001
        private const val PREFS_NAME = "floating_clock_service"
        private val DEFAULT_FRACTION_COLOR = 0xFFC62828.toInt()
        private val BRAND_COLOR = 0xFF6C8CFF.toInt()
    }

    private lateinit var windowManager: WindowManager
    private var overlayView: View? = null
    private var overlayLayoutParams: WindowManager.LayoutParams? = null
    private var timeView: TextView? = null
    private var labelView: TextView? = null
    private var lockView: ImageView? = null
    private var isLocked = false
    private var lastRenderedText: String? = null

    // offset in milliseconds to apply to system time (ntpTime - systemTime)
    private var offsetMillis: Long = 0L
    private var label: String? = null
    private var displayPrecision = DisplayPrecision.CENTISECOND
    private var updateIntervalMs = 10L
    private var fractionColor: Int = DEFAULT_FRACTION_COLOR

    private val calendar = Calendar.getInstance()
    private val handler = Handler(Looper.getMainLooper())
    private val updateRunnable = object : Runnable {
        override fun run() {
            updateTime()
            handler.postDelayed(this, updateIntervalMs)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        restoreConfig()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // 通知栏"停止"动作
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        // 再次调用 startOverlay 时更新显示配置；为 null（START_STICKY 重启）
        // 时保留从 SharedPreferences 恢复的配置。
        intent?.let {
            offsetMillis = it.getLongExtra("offset", offsetMillis)
            if (it.hasExtra("label")) label = it.getStringExtra("label")
            if (it.hasExtra("precision")) applyPrecision(it.getStringExtra("precision"))
            if (it.hasExtra("fractionColor")) {
                fractionColor = it.getIntExtra("fractionColor", fractionColor)
            }
            saveConfig()
        }

        startForegroundWithNotification()

        if (!Settings.canDrawOverlays(this)) {
            // 权限被撤销时不要让服务空转
            stopSelf()
            return START_NOT_STICKY
        }
        if (overlayView == null) createOverlay()

        // 避免重复 startOverlay 时叠加多个刷新任务
        handler.removeCallbacks(updateRunnable)
        handler.post(updateRunnable)
        updateTime()
        return START_STICKY
    }

    /**
     * 兜底：正常情况下 specialUse 不会触发超时。个别 ROM 若仍回调，主动停止
     * 前台服务以避免系统判 ANR 直接杀掉整个应用；随后由 START_STICKY 拉起。
     */
    override fun onTimeout(startId: Int, fgsType: Int) {
        handler.removeCallbacks(updateRunnable)
        stopSelf()
    }

    override fun onDestroy() {
        handler.removeCallbacks(updateRunnable)
        removeOverlay()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        val intent = Intent(ACTION_OVERLAY_STOPPED).setPackage(packageName)
        sendBroadcast(intent)
        super.onDestroy()
    }

    // ---------------------------------------------------------------------
    // 前台服务与通知
    // ---------------------------------------------------------------------

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "悬浮时间",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "悬浮时钟持续运行的状态通知"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun immutableFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("悬浮时间")
        .setContentText("悬浮时钟正在运行 · 点按返回应用")
        .setSmallIcon(R.drawable.ic_stat_clock)
        .setContentIntent(
            PendingIntent.getActivity(
                this, 0, Intent(this, MainActivity::class.java), immutableFlags()
            )
        )
        .addAction(
            R.drawable.ic_close,
            "停止",
            PendingIntent.getService(
                this,
                1,
                Intent(this, FloatingClockService::class.java).setAction(ACTION_STOP),
                immutableFlags()
            )
        )
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .build()

    private fun startForegroundWithNotification() {
        val notification = buildNotification()
        // Android 14+ 需要显式声明类型，且必须与 Manifest 中的 specialUse 一致。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ---------------------------------------------------------------------
    // 配置持久化
    // ---------------------------------------------------------------------

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun saveConfig() {
        prefs().edit()
            .putLong("offset", offsetMillis)
            .putString("label", label)
            .putString(
                "precision",
                if (displayPrecision == DisplayPrecision.DECISECOND) "decisecond"
                else "centisecond"
            )
            .putInt("fractionColor", fractionColor)
            .apply()
    }

    private fun restoreConfig() {
        val p = prefs()
        offsetMillis = p.getLong("offset", 0L)
        label = p.getString("label", null)
        applyPrecision(p.getString("precision", "centisecond"))
        fractionColor = p.getInt("fractionColor", DEFAULT_FRACTION_COLOR)
    }

    // ---------------------------------------------------------------------
    // 悬浮窗 UI
    // ---------------------------------------------------------------------

    private fun createOverlay() {
        val density = resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density).toInt()

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.START or Gravity.TOP
            x = dp(16f)
            y = dp(96f)
        }
        overlayLayoutParams = lp

        // 卡片：深色渐变 + 细描边 + 大圆角 + 阴影
        val background = GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(
                Color.argb(242, 26, 32, 52),
                Color.argb(238, 12, 16, 28)
            )
        ).apply {
            cornerRadius = dp(18f).toFloat()
            setStroke(dp(1f).coerceAtLeast(1), 0x33FFFFFF)
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            this.background = background
            setPadding(dp(14f), dp(10f), dp(10f), dp(10f))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                elevation = dp(10f).toFloat()
            }
        }

        // 顶部一行：状态点 + 来源名 + (弹性空间) + 锁定 + 关闭
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val dot = View(this).apply {
            val size = dp(6f)
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                marginEnd = dp(6f)
            }
            this.background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(BRAND_COLOR)
            }
        }
        header.addView(dot)

        val aliasTv = TextView(this).apply {
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            isSingleLine = true
            ellipsize = TextUtils.TruncateAt.END
            maxWidth = dp(150f)
            includeFontPadding = false
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        header.addView(aliasTv)
        labelView = aliasTv

        fun controlButton(iconRes: Int, description: String, onClick: () -> Unit): ImageView {
            val size = dp(26f)
            return ImageView(this).apply {
                layoutParams = LinearLayout.LayoutParams(size, size).apply {
                    marginStart = dp(6f)
                }
                setBackgroundResource(R.drawable.overlay_control_bg)
                setImageResource(iconRes)
                setPadding(dp(6f), dp(6f), dp(6f), dp(6f))
                scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = description
                alpha = 0.85f
                setOnClickListener { onClick() }
            }
        }

        val pin = controlButton(
            R.drawable.ic_pin_unlocked,
            "锁定位置"
        ) {
            isLocked = !isLocked
            lockView?.setImageResource(
                if (isLocked) R.drawable.ic_pin_locked else R.drawable.ic_pin_unlocked
            )
            lockView?.alpha = if (isLocked) 1f else 0.85f
            lockView?.contentDescription = if (isLocked) "解锁位置" else "锁定位置"
        }
        lockView = pin
        header.addView(pin)
        header.addView(controlButton(R.drawable.ic_close, "关闭悬浮窗") { stopSelf() })
        card.addView(header)

        // 大字时间
        val tv = TextView(this).apply {
            typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 23f)
            setShadowLayer(dp(3f).toFloat(), 0f, dp(1f).toFloat(), 0x66000000)
            isSingleLine = true
            includeFontPadding = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                letterSpacing = 0.02f
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply { topMargin = dp(4f) }
        }
        timeView = tv
        card.addView(tv)

        // 拖动：锁定后不再响应；坐标限制在屏幕范围内
        card.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                if (isLocked) return false
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = lp.x
                        initialY = lp.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        val maxX = (resources.displayMetrics.widthPixels - v.width).coerceAtLeast(0)
                        val maxY = (resources.displayMetrics.heightPixels - v.height).coerceAtLeast(0)
                        lp.x = (initialX + dx).coerceIn(0, maxX)
                        lp.y = (initialY + dy).coerceIn(0, maxY)
                        try {
                            windowManager.updateViewLayout(v, lp)
                        } catch (_: Exception) {
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> return true
                }
                return false
            }
        })

        overlayView = card
        try {
            windowManager.addView(card, lp)
        } catch (e: Exception) {
            overlayView = null
        }
    }

    private fun removeOverlay() {
        try {
            overlayView?.let { windowManager.removeView(it) }
        } catch (_: Exception) {
        }
        overlayView = null
        overlayLayoutParams = null
        timeView = null
        labelView = null
        lockView = null
        lastRenderedText = null
    }

    private fun updateTime() {
        val tv = timeView ?: return
        val display = currentTimeText()
        val plain = display.toString()
        if (plain != lastRenderedText) {
            tv.text = display
            lastRenderedText = plain
        }

        val aliasTv = labelView ?: return
        val value = label?.takeIf { it.isNotEmpty() } ?: "系统时间"
        if (aliasTv.text?.toString() != value) aliasTv.text = value
    }

    private fun currentTimeText(): CharSequence {
        calendar.timeInMillis = System.currentTimeMillis() + offsetMillis
        val h = calendar.get(Calendar.HOUR_OF_DAY)
        val m = calendar.get(Calendar.MINUTE)
        val s = calendar.get(Calendar.SECOND)
        val ms = calendar.get(Calendar.MILLISECOND)
        val base = String.format(Locale.getDefault(), "%02d:%02d:%02d", h, m, s)
        val fraction = if (displayPrecision == DisplayPrecision.CENTISECOND) {
            String.format(Locale.getDefault(), "%02d", ms / 10)
        } else {
            (ms / 100).toString()
        }
        val display = "$base.$fraction"
        val spannable = SpannableString(display)
        val dotIndex = display.lastIndexOf('.')
        if (dotIndex in 0 until display.length - 1) {
            spannable.setSpan(
                ForegroundColorSpan(fractionColor),
                dotIndex + 1,
                display.length,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            )
        }
        return spannable
    }

    private fun applyPrecision(raw: String?) {
        displayPrecision = when (raw) {
            "decisecond" -> DisplayPrecision.DECISECOND
            else -> DisplayPrecision.CENTISECOND
        }
        updateIntervalMs = if (displayPrecision == DisplayPrecision.CENTISECOND) 10L else 100L
    }
}

private enum class DisplayPrecision {
    CENTISECOND,
    DECISECOND
}
