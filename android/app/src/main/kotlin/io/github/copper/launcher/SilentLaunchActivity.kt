package io.github.copper.launcher

/**
 * 静默启动入口：和 [MainActivity] 完全同一套行为，只是清单里配了深色启动主题，
 * 快捷方式点下去不会先闪白屏，也不会让人看到启动器界面。
 */
class SilentLaunchActivity : MainActivity()
