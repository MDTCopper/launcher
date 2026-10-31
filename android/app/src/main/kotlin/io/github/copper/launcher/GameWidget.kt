package io.github.copper.launcher

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews

/**
 * 1x1 桌面小组件：一个版本一个，点一下直接启动游戏。
 *
 * 和固定快捷方式不同，小组件的外观完全由我们自己的 bitmap 决定，没有桌面的白卡片与来源角标；
 * 组件里自己画版本名，因为不少桌面会隐藏图标下方文字。
 *
 * 版本信息怎么和组件实例对上：一键添加前先记一份「待绑定版本」，Launcher 添加组件时会把
 * appWidgetId 交给 [GameWidgetConfigActivity]，由它把两者绑定起来；`onUpdate` 只认这份绑定
 * （有的桌面不会把 pin 的 extras 放进 `getAppWidgetOptions`）。
 */
object GameWidget {
    /** pin 成功回调的 action（系统会额外带上 APPWIDGET_ID），作为绑定兜底 */
    const val ACTION_WIDGET_PINNED = "io.github.copper.launcher.WIDGET_PINNED"

    /** RemoteViews 走 Binder，图不能太大 */
    private const val WIDGET_SIZE = 320

    private const val PREFS = "game_widgets"

    fun isSupported(context: Context): Boolean =
        AppWidgetManager.getInstance(context).isRequestPinAppWidgetSupported

    /** 请求把小组件固定到桌面；桌面不支持时返回 false（只能引导用户去小组件面板自己加） */
    fun requestPin(
        activity: Activity,
        versionId: String,
        tag: String,
        jarPath: String,
    ): Boolean {
        val manager = AppWidgetManager.getInstance(activity)
        if (!manager.isRequestPinAppWidgetSupported) return false
        savePending(activity, versionId, tag, jarPath)

        val extras = Bundle().apply {
            putString(GameShortcut.EXTRA_VERSION_ID, versionId)
            putString(GameShortcut.EXTRA_TAG, tag)
            putString(GameShortcut.EXTRA_JAR_PATH, jarPath)
        }
        // 回调里能拿到这次新建的组件 id，作为配置页之外的兜底
        val successCallback = PendingIntent.getBroadcast(
            activity,
            versionId.hashCode(),
            Intent(activity, GameWidgetProvider::class.java).apply {
                action = ACTION_WIDGET_PINNED
                putExtra(GameShortcut.EXTRA_VERSION_ID, versionId)
                putExtra(GameShortcut.EXTRA_TAG, tag)
                putExtra(GameShortcut.EXTRA_JAR_PATH, jarPath)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return manager.requestPinAppWidget(
            ComponentName(activity, GameWidgetProvider::class.java),
            extras,
            successCallback,
        )
    }

    /** 一键添加前记下要绑的版本；配置页取走并清掉 */
    fun savePending(context: Context, versionId: String, tag: String, jarPath: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString("pending_version", versionId)
            .putString("pending_tag", tag)
            .putString("pending_jar", jarPath)
            .apply()
    }

    fun takePending(context: Context): Binding? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val versionId = prefs.getString("pending_version", null) ?: return null
        val binding = Binding(
            versionId = versionId,
            tag = prefs.getString("pending_tag", "").orEmpty(),
            jarPath = prefs.getString("pending_jar", "").orEmpty(),
        )
        prefs.edit()
            .remove("pending_version")
            .remove("pending_tag")
            .remove("pending_jar")
            .apply()
        return binding
    }

    fun saveBinding(
        context: Context,
        appWidgetId: Int,
        versionId: String,
        tag: String,
        jarPath: String,
    ) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(key(appWidgetId, "version"), versionId)
            .putString(key(appWidgetId, "tag"), tag)
            .putString(key(appWidgetId, "jar"), jarPath)
            .apply()
    }

    fun deleteBinding(context: Context, appWidgetId: Int) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(key(appWidgetId, "version"))
            .remove(key(appWidgetId, "tag"))
            .remove(key(appWidgetId, "jar"))
            .apply()
    }

    fun binding(context: Context, appWidgetId: Int): Binding? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val versionId = prefs.getString(key(appWidgetId, "version"), null) ?: return null
        return Binding(
            versionId = versionId,
            tag = prefs.getString(key(appWidgetId, "tag"), "").orEmpty(),
            jarPath = prefs.getString(key(appWidgetId, "jar"), "").orEmpty(),
        )
    }

    data class Binding(val versionId: String, val tag: String, val jarPath: String)

    private fun key(appWidgetId: Int, name: String) = "widget_${appWidgetId}_$name"

    /** 按绑定渲染一个组件实例 */
    fun render(context: Context, appWidgetId: Int) {
        val manager = AppWidgetManager.getInstance(context)
        val binding = binding(context, appWidgetId) ?: optionsBinding(manager, appWidgetId)
        val versionId = binding?.versionId.orEmpty()
        val tag = binding?.tag.orEmpty()
        val jarPath = binding?.jarPath.orEmpty()
        Log.i("GameWidget", "更新小组件 $appWidgetId version=$versionId tag=$tag")

        val views = RemoteViews(context.packageName, R.layout.game_widget)
        views.setImageViewBitmap(R.id.game_widget_icon, iconOf(context, jarPath, tag))
        views.setOnClickPendingIntent(R.id.game_widget_root, launchIntent(context, versionId))
        manager.updateAppWidget(appWidgetId, views)
    }

    /** 有的桌面会把 pin 时的 extras 放进组件 options，能读到就用它兜底 */
    private fun optionsBinding(manager: AppWidgetManager, appWidgetId: Int): Binding? {
        val options = manager.getAppWidgetOptions(appWidgetId)
        val versionId = options.getString(GameShortcut.EXTRA_VERSION_ID) ?: return null
        return Binding(
            versionId = versionId,
            tag = options.getString(GameShortcut.EXTRA_TAG).orEmpty(),
            jarPath = options.getString(GameShortcut.EXTRA_JAR_PATH).orEmpty(),
        )
    }

    private fun launchIntent(context: Context, versionId: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = GameShortcut.ACTION_LAUNCH_GAME
            putExtra(GameShortcut.EXTRA_VERSION_ID, versionId)
        }
        return PendingIntent.getActivity(
            context,
            versionId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 小组件里画的内容：深色圆角卡片 + 版本 jar 里的 logo + 版本名。
     *
     * 版本名画进组件里，桌面隐藏图标文字时也能区分版本；字太长会按比例缩小。
     */
    fun iconOf(context: Context, jarPath: String, tag: String): Bitmap {
        val logo = GameShortcut.loadLogo(jarPath)
            ?: BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)

        val size = WIDGET_SIZE
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        val radius = size * 0.18f
        canvas.drawRoundRect(
            RectF(0f, 0f, size.toFloat(), size.toFloat()),
            radius,
            radius,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.parseColor("#1E1E1E") },
        )

        val logoSize = (size * 0.60f).toInt()
        canvas.drawBitmap(
            Bitmap.createScaledBitmap(logo, logoSize, logoSize, true),
            (size - logoSize) / 2f,
            size * 0.10f,
            Paint(Paint.FILTER_BITMAP_FLAG),
        )

        val text = tag.trim()
        if (text.isNotEmpty()) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.parseColor("#F0E6D8")
                textAlign = Paint.Align.CENTER
                typeface = Typeface.DEFAULT_BOLD
                textSize = size * 0.11f
            }
            while (paint.measureText(text) > size * 0.86f && paint.textSize > size * 0.05f) {
                paint.textSize *= 0.94f
            }
            canvas.drawText(text, size / 2f, size * 0.88f, paint)
        }
        return bitmap
    }
}

/** Launcher 添加组件时先起这里：把「待绑定版本」落到这个 appWidgetId 上 */
class GameWidgetConfigActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            setResult(RESULT_CANCELED)
            finish()
            return
        }
        GameWidget.takePending(this)?.let {
            GameWidget.saveBinding(this, appWidgetId, it.versionId, it.tag, it.jarPath)
        }
        GameWidget.render(this, appWidgetId)
        setResult(
            RESULT_OK,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId),
        )
        finish()
    }
}

class GameWidgetProvider : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == GameWidget.ACTION_WIDGET_PINNED) {
            val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, -1)
            if (appWidgetId < 0) return
            GameWidget.saveBinding(
                context,
                appWidgetId,
                intent.getStringExtra(GameShortcut.EXTRA_VERSION_ID).orEmpty(),
                intent.getStringExtra(GameShortcut.EXTRA_TAG).orEmpty(),
                intent.getStringExtra(GameShortcut.EXTRA_JAR_PATH).orEmpty(),
            )
            GameWidget.render(context, appWidgetId)
            return
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) GameWidget.render(context, appWidgetId)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        GameWidget.render(context, appWidgetId)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) GameWidget.deleteBinding(context, appWidgetId)
    }
}
