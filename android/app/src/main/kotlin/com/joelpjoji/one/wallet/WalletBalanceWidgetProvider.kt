package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class WalletBalanceWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val widgetData = HomeWidgetPlugin.getData(context)
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_balance)

            val totalBalance = widgetData.getString("widget_total_balance", "$0.00")
            val netWorth = widgetData.getString("widget_networth", "Net Worth")
            val income = widgetData.getString("widget_income", "+$0.00")
            val expense = widgetData.getString("widget_expense", "-$0.00")

            views.setTextViewText(R.id.widget_total_balance, totalBalance)
            views.setTextViewText(R.id.widget_networth_label, netWorth)
            views.setTextViewText(R.id.widget_income_text, income)
            views.setTextViewText(R.id.widget_expense_text, expense)

            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("onewallet://app/home")
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_balance_root, pendingIntent)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
