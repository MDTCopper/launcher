package io.github.copper.launcher.game

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.app.Activity
import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import copper.bridge.Bridge
import copper.bridge.art.BridgeActivity
import java.io.File
import java.util.zip.ZipFile

/**
 * 启动器的桥活动：桥只画游戏，这层铜色启动画面是启动器的显示。
 *
 * 父类 [BridgeActivity] 只在 bridge.jar 里，而这个类在宿主 APK 里，所以它必须由桥的类加载器定义
 * —— 加载器的 dex 路径同时给出两者（见 [io.github.copper.launcher.CopperComponentFactory]）。
 */
class CopperGameActivity : BridgeActivity() {
    /** 盖在 surface 上的那一层，首帧到了就淡出。 */
    private var veil: View? = null
    private var statusText: TextView? = null
    private var breath: ObjectAnimator? = null
    private var copperIcon: ImageView? = null
    private var hintText: TextView? = null
    private var ringView: ProgressRingView? = null
    private var ringAnimator: ValueAnimator? = null
    private var hintTimeout: Runnable? = null
    private var interactionEnabled = false
    private var hintVisible = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildVeil()
    }

    /** 桥在游戏交出首帧时调这里：撤掉遮罩，让画面接上。 */
    override fun onFirstFrameDrawn() {
        fadeVeil()
    }

    //region 遮罩

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun buildVeil() {
        val veilLayer = FrameLayout(this)
        veilLayer.setBackgroundColor(COPPER_BG)
        veilLayer.alpha = 0f
        veilLayer.addView(
            buildVeilContent(),
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        val ring = ProgressRingView(this).apply { visibility = View.GONE }
        ringView = ring
        veilLayer.addView(
            ring,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        // 右下角的状态文字：只有 3 秒后还停在铜色屏上的启动才会看到它，淡入之后开始呼吸。
        val status = TextView(this).apply {
            text = "正在启动游戏…"
            textSize = 14f
            setTextColor(0xFFF0F0F0.toInt())
            alpha = 0f
        }
        statusText = status
        val statusParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.END,
        ).apply {
            rightMargin = dp(24)
            bottomMargin = dp(24)
        }
        veilLayer.addView(status, statusParams)
        handler.postDelayed({
            if (veil != null && !isFinishing) {
                status.animate()
                    .alpha(1f)
                    .setDuration(300)
                    .withEndAction { startBreathing() }
                    .start()
            }
        }, STATUS_AFTER_MS)

        // 只有 6 秒后还停在铜色屏上的启动才接受点击/长按这条退路。
        handler.postDelayed({
            if (veil != null && !isFinishing)
                interactionEnabled = true
        }, INTERACTION_AFTER_MS)

        val touchLayer = View(this).apply {
            isClickable = true
            setOnTouchListener { v, event -> handleVeilTouch(v, event) }
        }
        veilLayer.addView(
            touchLayer,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )

        veil = veilLayer
        root.addView(
            veilLayer,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        veilLayer.animate().alpha(1f).setDuration(200).start()
    }

    /** 淡出遮罩并移除它：游戏画面就在下面。 */
    private fun fadeVeil() {
        val fading = veil ?: return
        veil = null
        stopRing()
        hintTimeout?.let {
            handler.removeCallbacks(it)
            hintTimeout = null
        }
        breath?.cancel()
        breath = null
        fading.animate()
            .alpha(0f)
            .setDuration(250)
            .withEndAction { root.removeView(fading) }
            .start()
    }

    /** 状态文字缓慢呼吸：游戏还没上来时的一开一合。 */
    private fun startBreathing() {
        val text = statusText ?: return
        breath = ObjectAnimator.ofFloat(text, View.ALPHA, 1f, 0.65f).apply {
            duration = 2400
            interpolator = AccelerateDecelerateInterpolator()
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            start()
        }
    }

    /** 中间：铜色图标，点击时换成「长按取消」的提示。 */
    private fun buildVeilContent(): View {
        val center = FrameLayout(this)

        val icon = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER }
        try {
            icon.setImageDrawable(packageManager.getApplicationIcon(packageName))
        } catch (ignored: Throwable) {
            val fallback = TextView(this).apply {
                text = "C"
                textSize = 48f
                setTextColor(COPPER_ACCENT)
            }
            center.addView(
                fallback,
                FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
        }
        copperIcon = icon
        center.addView(
            icon,
            FrameLayout.LayoutParams(dp(64), dp(64), Gravity.CENTER),
        )
        loadMindustryLogo()

        val hint = TextView(this).apply {
            text = "长按任意位置以取消此次启动..."
            textSize = 16f
            setTextColor(0xFFF0F0F0.toInt())
            gravity = Gravity.CENTER
            alpha = 0f
            visibility = View.GONE
        }
        hintText = hint
        center.addView(
            hint,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        return center
    }

    /** 本体 jar 里有 Mindustry 的图标：icons/icon.png。 */
    private fun loadMindustryLogo() {
        val jars = Bridge.options.gameJars
        if (jars.isEmpty())
            return
        Thread({
            for (jar in jars) {
                if (jar == null || !jar.isFile)
                    continue
                try {
                    var found = false
                    ZipFile(jar).use { zip ->
                        val entry = zip.getEntry("icons/icon.png") ?: return@use
                        found = true
                        zip.getInputStream(entry).use { input ->
                            val bitmap = BitmapFactory.decodeStream(input)
                            if (bitmap != null) {
                                runOnUiThread {
                                    copperIcon?.setImageBitmap(bitmap)
                                }
                            }
                        }
                    }
                    if (found)
                        return@Thread
                } catch (ignored: Throwable) {
                }
            }
        }, "copper-logo").start()
    }

    private fun handleVeilTouch(v: View, event: MotionEvent): Boolean {
        if (veil == null)
            return false
        if (!interactionEnabled)
            return true
        return when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                showHint()
                startRing(event.x, event.y)
                true
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                stopRing()
                true
            }

            else -> true
        }
    }

    private fun showHint() {
        val hint = hintText ?: return
        if (veil == null)
            return
        if (!hintVisible) {
            hintVisible = true
            copperIcon?.animate()?.alpha(0f)?.setDuration(150)?.start()
            hint.visibility = View.VISIBLE
            hint.alpha = 0f
            hint.animate().alpha(1f).setDuration(150).start()
            handler.postDelayed({ pulseHint() }, 160)
        } else {
            pulseHint()
        }
        val timeout = hintTimeout ?: Runnable { hideHint() }.also { hintTimeout = it }
        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, HINT_VISIBLE_MS)
    }

    private fun hideHint() {
        if (!hintVisible)
            return
        hintVisible = false
        hintText?.animate()
            ?.alpha(0f)
            ?.setDuration(150)
            ?.withEndAction {
                if (!hintVisible)
                    hintText?.visibility = View.GONE
            }
            ?.start()
        copperIcon?.animate()?.alpha(1f)?.setDuration(150)?.start()
    }

    private fun pulseHint() {
        val hint = hintText ?: return
        if (!hintVisible || veil == null)
            return
        hint.animate().cancel()
        hint.alpha = 1f
        hint.scaleX = 1f
        hint.scaleY = 1f
        hint.animate()
            .scaleX(1.12f)
            .scaleY(1.12f)
            .setDuration(160)
            .setInterpolator(OvershootInterpolator(2f))
            .withEndAction {
                hint.animate()
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(180)
                    .setInterpolator(OvershootInterpolator(2f))
                    .start()
            }
            .start()
    }

    private fun startRing(x: Float, y: Float) {
        val ring = ringView ?: return
        stopRing()
        ring.setCenter(x, y)
        ring.setProgress(0f)
        ring.visibility = View.VISIBLE
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = RING_FULL_MS
            interpolator = LinearInterpolator()
            addUpdateListener { animation -> ring.setProgress(animation.animatedValue as Float) }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: Animator) {
                    if (ringAnimator !== animation)
                        return
                    ringAnimator = null
                    ring.visibility = View.GONE
                    cancelLaunch()
                }
            })
        }
        ringAnimator = animator
        animator.start()
    }

    private fun stopRing() {
        ringAnimator?.let { animator ->
            ringAnimator = null
            animator.cancel()
        }
        ringView?.visibility = View.GONE
    }

    /** 从触点开始填充，填满就取消这次启动。 */
    private class ProgressRingView(context: Context) : View(context) {
        private val track = Paint(Paint.ANTI_ALIAS_FLAG)
        private val arc = Paint(Paint.ANTI_ALIAS_FLAG)
        private val radius: Float
        private var cx = 0f
        private var cy = 0f
        private var progress = 0f

        init {
            val density = resources.displayMetrics.density
            radius = 36f * density
            val stroke = 4f * density
            track.style = Paint.Style.STROKE
            track.strokeWidth = stroke
            track.color = 0x33C8A06E
            arc.style = Paint.Style.STROKE
            arc.strokeWidth = stroke
            arc.strokeCap = Paint.Cap.ROUND
            arc.color = COPPER_ACCENT
        }

        fun setCenter(x: Float, y: Float) {
            cx = x
            cy = y
            invalidate()
        }

        fun setProgress(value: Float) {
            progress = value
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            if (progress <= 0f)
                return
            canvas.drawCircle(cx, cy, radius, track)
            canvas.drawArc(
                cx - radius,
                cy - radius,
                cx + radius,
                cy + radius,
                -90f,
                360f * progress,
                false,
                arc,
            )
        }
    }

    /** 让玩家能放弃一次启动太久的启动。 */
    private fun cancelLaunch() {
        Log.i("copper-launcher", "bridge launch canceled by user")
        val cache = Bridge.options.cacheFolder
        if (cache != null) {
            try {
                cache.mkdirs()
                File(cache, "launch-canceled").createNewFile()
            } catch (ignored: Throwable) {
            }
        }
        leave()
        handler.postDelayed(
            { Process.killProcess(Process.myPid()) },
            500,
        )
    }

    //endregion

    //region 离场

    /** 离开时先把画面淡出到铜色，再走桥的转场与 finish：比直接切回启动器少一次闪黑。 */
    override fun performLeave() {
        // 已经在 finish 就不动：再 finish 一次会把系统正在做的退场转场覆盖掉
        if (isFinishing)
            return
        val cover = View(this).apply { setBackgroundColor(COPPER_BG) }
        cover.alpha = 0f
        root.addView(
            cover,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        cover.animate()
            .alpha(1f)
            .setDuration(300)
            .withEndAction { finishLeaving() }
            .start()
    }

    /**
     * 淡出结束后收尾：转场用启动器自己的淡入淡出，和启动时的淡入对齐。
     *
     * 桥的 `performLeave()` 给的是滑动，那是桥的默认；启动器进出都是淡的，滑动接在铜色淡出后面
     * 会读成两段动画，所以这里照它的形状自己走一遍：转场 + `finish()`。
     *
     * 游戏画面是 SurfaceView，独立图层，窗口淡出带不动它 —— 不先藏掉，淡出会一路露出游戏的
     * 最后一帧。藏完等一帧让图层真的撤掉，再上转场。
     */
    private fun finishLeaving() {
        for (index in 0 until root.childCount)
            (root.getChildAt(index) as? SurfaceView)?.visibility = View.GONE
        handler.postDelayed({
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                overrideActivityTransition(
                    Activity.OVERRIDE_TRANSITION_CLOSE,
                    android.R.anim.fade_in,
                    android.R.anim.fade_out,
                )
            } else {
                @Suppress("DEPRECATION")
                overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
            }
            finish()
        }, 32)
    }

    override fun onDestroy() {
        hintTimeout?.let {
            handler.removeCallbacks(it)
            hintTimeout = null
        }
        stopRing()
        breath?.cancel()
        breath = null
        super.onDestroy()
    }

    //endregion

    private companion object {
        /** Copper 的默认配色：启动器的深色底色与品牌色，不跟随主题。 */
        val COPPER_BG = 0xFF121212.toInt()
        val COPPER_ACCENT = 0xFFC8A06E.toInt()
        const val INTERACTION_AFTER_MS = 6000L
        const val HINT_VISIBLE_MS = 1000L
        const val RING_FULL_MS = 2500L
        const val STATUS_AFTER_MS = 3000L
    }
}
