package com.example.coffee_person

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class CoffeeStatsWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    for (appWidgetId in appWidgetIds) {
      updateAppWidget(context, appWidgetManager, appWidgetId)
    }
  }

  companion object {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_TODAY_CAFFEINE = "flutter.widget_today_caffeine_mg"
    private const val KEY_TODAY_CUPS = "flutter.widget_today_cups"
    private const val KEY_TODAY_DATE = "flutter.widget_today_date"

    fun requestUpdate(context: Context) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val componentName = ComponentName(context, CoffeeStatsWidgetProvider::class.java)
      val ids = appWidgetManager.getAppWidgetIds(componentName)
      if (ids.isEmpty()) return
      for (appWidgetId in ids) {
        updateAppWidget(context, appWidgetManager, appWidgetId)
      }
    }

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      try {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val caffeineMg = prefs.getLong(KEY_TODAY_CAFFEINE, 0L).toInt()
        val cups = prefs.getLong(KEY_TODAY_CUPS, 0L).toInt()
        val date = prefs.getString(KEY_TODAY_DATE, "") ?: ""

        val views = RemoteViews(context.packageName, R.layout.coffee_stats_widget)
        views.setTextViewText(R.id.widget_title, "今日咖啡因")
        views.setTextViewText(R.id.widget_value, "${caffeineMg} mg")
        views.setTextViewText(R.id.widget_subtitle, "今日 $cups 杯")
        views.setTextViewText(R.id.widget_date, date)

        val launchIntent = Intent(context, MainActivity::class.java).apply {
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
          context,
          0,
          launchIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

        appWidgetManager.updateAppWidget(appWidgetId, views)
      } catch (_: Throwable) {}
    }
  }
}
