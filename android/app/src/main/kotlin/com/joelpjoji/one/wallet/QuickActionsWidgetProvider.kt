package com.joelpjoji.one.wallet

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class QuickActionsWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_quick_actions)

            fun makePendingIntent(route: String, requestCode: Int): PendingIntent {
                val intent = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("onewallet://app$route")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                return PendingIntent.getActivity(
                    context,
                    requestCode,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            }

            views.setOnClickPendingIntent(
                R.id.widget_action_add_expense,
                makePendingIntent("/transactions/new?type=expense", appWidgetId * 10 + 1)
            )
            views.setOnClickPendingIntent(
                R.id.widget_action_add_income,
                makePendingIntent("/transactions/new?type=income", appWidgetId * 10 + 2)
            )
            views.setOnClickPendingIntent(
                R.id.widget_action_scan,
                makePendingIntent("/transactions/scan", appWidgetId * 10 + 3)
            )

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
