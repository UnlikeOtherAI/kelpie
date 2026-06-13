package com.kelpie.browser.network

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.kelpie.browser.MainActivity
import com.kelpie.browser.R

/**
 * Foreground service that owns the HTTP server and mDNS advertiser so they keep
 * serving while the device is dozing or the Activity is in the background. The
 * service runs in the main process; MainActivity stages the `HTTPServer` and
 * `MDNSAdvertiser` instances via `NetworkServiceState` before calling
 * `startForegroundService`, and clears them on destroy.
 *
 * Foreground service type is `connectedDevice` because the device is
 * advertising itself on the LAN for other devices (the CLI / MCP host) to
 * connect to — the closest fit among the Android 14 mandatory types.
 */
class KelpieNetworkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        startForegroundWithNotification()

        val stage = NetworkServiceState.snapshot()
        if (stage == null) {
            Log.w(TAG, "Started without staged HTTPServer/MDNSAdvertiser; stopping.")
            stopSelf()
            return START_NOT_STICKY
        }

        if (!stage.httpServer.isRunning) {
            try {
                stage.httpServer.start()
            } catch (e: Exception) {
                Log.e(TAG, "HTTPServer failed to start: ${e.message}")
            }
        }
        stage.mdnsAdvertiser.ensureRegistered()

        // If the user removes the app from the recent task list we want the
        // service to stop with it (matches the Activity's onDestroy path).
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        val stage = NetworkServiceState.snapshot()
        if (stage != null) {
            try {
                stage.mdnsAdvertiser.shutdown()
            } catch (e: Exception) {
                Log.w(TAG, "mDNS shutdown error: ${e.message}")
            }
            try {
                stage.httpServer.stop()
            } catch (e: Exception) {
                Log.w(TAG, "HTTPServer stop error: ${e.message}")
            }
        }
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // User swiped the app away from recents: shut down cleanly so the
        // notification disappears and the port is freed.
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun startForegroundWithNotification() {
        ensureNotificationChannel()
        val notification = buildNotification()
        // The 3-arg form (with foregroundServiceType) is API 29+; the 2-arg
        // form is the supported path on API 28. The manifest still declares
        // foregroundServiceType=connectedDevice so API 29+ honours it.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun ensureNotificationChannel() {
        // minSdk is 28 — channels (added in O / 26) always exist.
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val channel =
            NotificationChannel(
                CHANNEL_ID,
                "Kelpie network",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps the local-network HTTP server reachable"
                setShowBadge(false)
            }
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openAppIntent =
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
        val pendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        return NotificationCompat
            .Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Kelpie is reachable")
            .setContentText("Listening for commands on the local network")
            .setOngoing(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(pendingIntent)
            .build()
    }

    companion object {
        private const val TAG = "KelpieNetworkService"
        private const val CHANNEL_ID = "kelpie_network"
        private const val NOTIFICATION_ID = 0x4B454C50 // "KELP"

        fun start(context: Context) {
            val intent = Intent(context, KelpieNetworkService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, KelpieNetworkService::class.java))
        }
    }
}
