package com.joelpjoji.one.wallet

import android.content.Context
import android.graphics.BitmapFactory
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class NotificationResourcesTest {
    @Test fun pluginCanResolveNotificationIconsByName() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resources = context.resources
        val icon = resources.getIdentifier("ic_notification", "drawable", context.packageName)
        assertNotEquals("Notification small icon must resolve by its plugin resource name", 0, icon)
        val largeIcon = resources.getIdentifier("ic_launcher_foreground", "drawable", context.packageName)
        assertNotEquals("Notification large icon must resolve as a drawable", 0, largeIcon)
        requireNotNull(BitmapFactory.decodeResource(resources, largeIcon))
        requireNotNull(resources.getDrawable(icon, context.theme))
    }
}
