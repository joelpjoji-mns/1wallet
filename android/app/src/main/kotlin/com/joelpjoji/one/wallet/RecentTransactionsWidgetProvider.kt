package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class RecentTransactionsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_recent_transactions)

            val name1 = widgetData.getString("widget_recent_name_1", "No recent transactions")
            val amount1 = widgetData.getString("widget_recent_amount_1", "")
            val name2 = widgetData.getString("widget_recent_name_2", "")
            val amount2 = widgetData.getString("widget_recent_amount_2", "")
            val name3 = widgetData.getString("widget_recent_name_3", "")
            val amount3 = widgetData.getString("widget_recent_amount_3", "")

            views.setTextViewText(R.id.widget_recent_name_1, name1)
            views.setTextViewText(R.id.widget_recent_amount_1, amount1)
            views.setTextViewText(R.id.widget_recent_name_2, name2)
            views.setTextViewText(R.id.widget_recent_amount_2, amount2)
            views.setTextViewText(R.id.widget_recent_name_3, name3)
            views.setTextViewText(R.id.widget_recent_amount_3, amount3)

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("onewallet://app/transactions")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_recent_root, pendingIntent)
            views.setOnClickPendingIntent(R.id.widget_recent_more_btn, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
