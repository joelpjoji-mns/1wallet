package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class CalendarWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_calendar)

            val monthLabel = widgetData.getString("widget_calendar_month", "This Month")
            val spentToday = widgetData.getString("widget_calendar_spent_today", "$0.00")
            val spentMonth = widgetData.getString("widget_calendar_spent_month", "$0.00")

            views.setTextViewText(R.id.widget_calendar_month, monthLabel)
            views.setTextViewText(R.id.widget_calendar_spent_today, spentToday)
            views.setTextViewText(R.id.widget_calendar_spent_month, spentMonth)

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("onewallet://app/calendar")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_calendar_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
