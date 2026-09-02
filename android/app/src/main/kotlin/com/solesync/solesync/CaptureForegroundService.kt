package com.solesync.solesync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * Foreground service whose only job is to keep this app's process -- and
 * the single Flutter engine/isolate running inside it, where all the BLE
 * decoding, GPS tracking, and frame-file writing actually happens -- alive
 * while the app is backgrounded (screen locked, user switched apps).
 *
 * Without this, Android (Samsung devices especially) is likely to suspend
 * or kill the app once it's no longer visible, silently truncating a
 * long/all-day capture session. This service does no capture work itself;
 * it just holds a persistent notification, which is what exempts the
 * process from that kind of background suspension for as long as it runs.
 */
class CaptureForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "insole_capture_channel"
        private const val NOTIFICATION_ID = 1001
        const val ACTION_START = "start"
        const val ACTION_STOP = "stop"
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            // The int-flag overload (STOP_FOREGROUND_REMOVE) needs API 24;
            // this app's minSdk is 23, so use the older boolean overload,
            // which behaves the same and is supported on every API level.
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Insole recording",
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.description = "Keeps insole capture running while the app is in the background"
            manager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE,
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Recording insole data")
            .setContentText("Tap to return to NurvoSync")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(contentIntent)
            .build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
