package io.github.copper;

import android.app.*;
import android.content.*;
import android.graphics.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.*;
import android.text.style.*;
import android.util.*;
import android.view.*;
import android.widget.*;

import io.github.copper.launcher.R;

/**
 * Placeholder activity used as the launch entry of both ways of running the game.
 *
 * <p>{@link CopperComponentFactory} replaces it with the game activity when the launch succeeds, or
 * sets {@link #errorMessage} to show a failure dialog when it fails. Without an error message it
 * closes itself immediately.</p>
 */
public class MindustryActivity extends Activity {
    public String errorMessage;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        String error = errorMessage;
        if (error == null || error.trim().isEmpty()) {
            finishAndRemoveTask();
            return;
        }

        float density = getResources().getDisplayMetrics().density;

        TextView textView = new TextView(this);
        textView.setText(error);
        textView.setTypeface(Typeface.MONOSPACE);
        textView.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);

        HorizontalScrollView horizontalScrollView = new HorizontalScrollView(this);
        horizontalScrollView.addView(textView);

        // A stack trace is long and wide, so the dialog scrolls both ways - but only up to a point,
        // or the buttons would be pushed off the screen.
        ScrollView scrollView = new ScrollView(this) {
            @Override
            protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
                int maxHeight = (int) (350 * density);
                int heightSize = MeasureSpec.getSize(heightMeasureSpec);
                int mode = MeasureSpec.getMode(heightMeasureSpec);

                int newHeightSpec = (heightSize > maxHeight || mode == MeasureSpec.UNSPECIFIED)
                        ? MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST)
                        : heightMeasureSpec;
                super.onMeasure(widthMeasureSpec, newHeightSpec);
            }
        };
        GradientDrawable background = new GradientDrawable();
        background.setColor(0x1F888888);
        background.setCornerRadius(8f * density);
        scrollView.setBackground(background);
        int pad = (int) (8 * density);
        scrollView.setPadding(pad, pad, pad, pad);
        scrollView.addView(horizontalScrollView);

        FrameLayout container = new FrameLayout(this);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
        int margin = (int) (16 * density);
        params.setMargins(margin, margin, margin, margin);
        container.addView(scrollView, params);

        SpannableString titleSpan = new SpannableString(getString(R.string.error_title));
        titleSpan.setSpan(new ForegroundColorSpan(Color.RED), 0, titleSpan.length(), 0);

        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle(titleSpan)
                .setView(container)
                .setPositiveButton(getString(R.string.close), null)
                .setNeutralButton(getString(R.string.copy_stacktrace), null)
                .setOnDismissListener(d -> finishAndRemoveTask())
                .create();

        dialog.show();

        Window window = dialog.getWindow();
        if (window != null) {
            int width = (int) (getResources().getDisplayMetrics().widthPixels * 0.95);
            window.setLayout(width, ViewGroup.LayoutParams.WRAP_CONTENT);
        }

        dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> {
            android.content.ClipboardManager clipboard =
                    (android.content.ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
            ClipData clip = ClipData.newPlainText("Error Stacktrace", error);
            clipboard.setPrimaryClip(clip);
            Toast.makeText(this, getString(R.string.copied_stacktrace), Toast.LENGTH_SHORT).show();
        });
    }
}
