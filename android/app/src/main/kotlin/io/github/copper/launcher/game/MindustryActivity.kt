package io.github.copper.launcher.game

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.util.TypedValue
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import io.github.copper.launcher.CopperComponentFactory
import io.github.copper.launcher.R

/**
 * 两种启动方式共用的占位 Activity。
 *
 * 启动成功时 [CopperComponentFactory] 会把它换成游戏自己的 Activity；失败时把堆栈写进
 * [errorMessage]，这里负责把堆栈显示出来。没有错误信息就立即关掉自己。
 */
class MindustryActivity : Activity() {
    /** 启动失败时的堆栈；由 [CopperComponentFactory] 在失败分支写入。 */
    var errorMessage: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val error = errorMessage
        if (error.isNullOrBlank()) {
            finishAndRemoveTask()
            return
        }

        val density = resources.displayMetrics.density

        val textView = TextView(this).apply {
            text = error
            typeface = android.graphics.Typeface.MONOSPACE
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }

        val horizontalScrollView = HorizontalScrollView(this).apply {
            addView(textView)
        }

        // 堆栈又长又宽，两个方向都要能滚；但高度要封顶，否则按钮会被挤出屏幕
        val scrollView = object : ScrollView(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val maxHeight = (350 * density).toInt()
                val heightSize = MeasureSpec.getSize(heightMeasureSpec)
                val mode = MeasureSpec.getMode(heightMeasureSpec)
                val newHeightSpec =
                    if (heightSize > maxHeight || mode == MeasureSpec.UNSPECIFIED) {
                        MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST)
                    } else {
                        heightMeasureSpec
                    }
                super.onMeasure(widthMeasureSpec, newHeightSpec)
            }
        }.apply {
            background = GradientDrawable().apply {
                setColor(0x1F888888)
                cornerRadius = 8f * density
            }
            val pad = (8 * density).toInt()
            setPadding(pad, pad, pad, pad)
            addView(horizontalScrollView)
        }

        val container = FrameLayout(this)
        val params = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        val margin = (16 * density).toInt()
        params.setMargins(margin, margin, margin, margin)
        container.addView(scrollView, params)

        val titleSpan = SpannableString(getString(R.string.error_title)).apply {
            setSpan(ForegroundColorSpan(Color.RED), 0, length, 0)
        }

        val dialog = AlertDialog.Builder(this)
            .setTitle(titleSpan)
            .setView(container)
            .setPositiveButton(getString(R.string.close), null)
            .setNeutralButton(getString(R.string.copy_stacktrace), null)
            .setOnDismissListener { finishAndRemoveTask() }
            .create()

        dialog.show()

        dialog.window?.let { window ->
            val width = (resources.displayMetrics.widthPixels * 0.95).toInt()
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
        }

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL)?.setOnClickListener {
            val clipboard = getSystemService(CLIPBOARD_SERVICE) as? ClipboardManager
            clipboard?.setPrimaryClip(ClipData.newPlainText("Error Stacktrace", error))
            Toast.makeText(this, getString(R.string.copied_stacktrace), Toast.LENGTH_SHORT).show()
        }
    }
}
