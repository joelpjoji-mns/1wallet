package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class AccountsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_accounts)

            val count = widgetData.getString("widget_accounts_count", "0 accounts")
            val name1 = widgetData.getString("widget_acc_name_1", "No accounts")
            val bal1 = widgetData.getString("widget_acc_bal_1", "")
            val name2 = widgetData.getString("widget_acc_name_2", "")
            val bal2 = widgetData.getString("widget_acc_bal_2", "")
            val name3 = widgetData.getString("widget_acc_name_3", "")
            val bal3 = widgetData.getString("widget_acc_bal_3", "")

            views.setTextViewText(R.id.widget_accounts_count, count)
            views.setTextViewText(R.id.widget_acc_name_1, name1)
            views.setTextViewText(R.id.widget_acc_bal_1, bal1)
            views.setTextViewText(R.id.widget_acc_name_2, name2)
            views.setTextViewText(R.id.widget_acc_bal_2, bal2)
            views.setTextViewText(R.id.widget_acc_name_3, name3)
            views.setTextViewText(R.id.widget_acc_bal_3, bal3)

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("onewallet://app/accounts")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_accounts_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
