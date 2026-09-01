package io.github.copper.loader

import android.app.Activity
import android.app.AlertDialog
import android.content.ClipData
import android.content.ClipboardManager
import android.graphics.Color
import android.graphics.Typeface
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
import io.github.copper.launcher.R

/**
 * Placeholder activity used as the launch entry of the loader.
 *
 * <p>{@link LoaderComponentFactory} replaces it with the game activity when the
 * launch succeeds, or sets {@link #errorMessage} to show a failure dialog when
 * it fails. Without an error message it closes itself immediately.</p>
 */
class MindustryActivity : Activity() {

    @JvmField
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
            typeface = Typeface.MONOSPACE
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }

        val horizontalScrollView = HorizontalScrollView(this).apply {
            addView(textView)
        }

        val scrollView = object : ScrollView(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val maxHeight = (350 * density).toInt()
                val heightSize = MeasureSpec.getSize(heightMeasureSpec)
                val mode = MeasureSpec.getMode(heightMeasureSpec)

                val newHeightSpec = if (heightSize > maxHeight || mode == MeasureSpec.UNSPECIFIED) {
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

        val container = FrameLayout(this).apply {
            val params = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                val margin = (16 * density).toInt()
                setMargins(margin, margin, margin, margin)
            }
            addView(scrollView, params)
        }

        // --- AlertDialog ---
        val titleSpan = SpannableString(getString(R.string.error_title))
        titleSpan.setSpan(ForegroundColorSpan(Color.RED), 0, titleSpan.length, 0)

        val dialog = AlertDialog.Builder(this)
            .setTitle(titleSpan)
            .setView(container)
            .setPositiveButton(getString(R.string.close)) { _, _ -> }
            .setNeutralButton(getString(R.string.copy_stacktrace), null)
            .setOnDismissListener {
                finishAndRemoveTask()
            }
            .create()

        dialog.show()

        dialog.window?.let { window ->
            val width = (resources.displayMetrics.widthPixels * 0.95).toInt()
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT)
        }

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
            val clipboard = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("Error Stacktrace", error)
            clipboard.setPrimaryClip(clip)
            Toast.makeText(this, getString(R.string.copied_stacktrace), Toast.LENGTH_SHORT).show()
        }
    }
}