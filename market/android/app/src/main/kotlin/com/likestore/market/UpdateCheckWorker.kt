package com.likestore.market

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Periodic background check: notifies when the catalog has newer versions of
 * installed apps. It only shows a notification; the store itself verifies the
 * catalog signature before anything is downloaded or installed.
 */
class UpdateCheckWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val prefs = prefs(applicationContext)
        val url = prefs.getString(KEY_URL, null) ?: return Result.success()
        val body = try {
            fetch("$url?t=${System.currentTimeMillis() / 1000}")
        } catch (_: IOException) {
            return Result.retry()
        }

        val updates = mutableListOf<String>()
        val apps = JSONObject(body).optJSONArray("apps") ?: return Result.success()
        for (i in 0 until apps.length()) {
            val app = apps.optJSONObject(i) ?: continue
            val android = app.optJSONObject("packages")?.optJSONObject("android") ?: continue
            val pkg = android.optString("packageName", app.optString("id"))
            val available = android.optLong("versionCode", 0)
            val installed = Packages.installed(applicationContext, pkg) ?: continue
            if (available > installed.first) updates += "${app.optString("name", pkg)}:$available"
        }

        // Notify once per distinct set of updates.
        val key = updates.sorted().joinToString("|")
        if (updates.isNotEmpty() && key != prefs.getString(KEY_LAST, null)) {
            notify(updates.map { it.substringBeforeLast(':') })
        }
        prefs.edit().putString(KEY_LAST, key).apply()
        return Result.success()
    }

    private fun fetch(url: String): String {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.connectTimeout = 20_000
        conn.readTimeout = 20_000
        try {
            if (conn.responseCode != 200) throw IOException("HTTP ${conn.responseCode}")
            return conn.inputStream.bufferedReader().use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    private fun notify(names: List<String>) {
        val ctx = applicationContext
        if (Build.VERSION.SDK_INT >= 33 &&
            ctx.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) return
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "App updates", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
        val open = PendingIntent.getActivity(
            ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val title = if (names.size == 1) "Update available" else "${names.size} updates available"
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(ctx, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(ctx)
        }
        nm.notify(
            NOTIFICATION_ID,
            builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
                .setContentTitle(title)
                .setContentText(names.joinToString(", "))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        )
    }

    companion object {
        private const val WORK = "likestore-update-check"
        private const val CHANNEL = "updates"
        private const val NOTIFICATION_ID = 1
        private const val KEY_URL = "catalogUrl"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_LAST = "lastNotified"

        private fun prefs(ctx: Context) = ctx.getSharedPreferences("update_check", Context.MODE_PRIVATE)

        fun isEnabled(ctx: Context) = prefs(ctx).getBoolean(KEY_ENABLED, false)

        fun configure(ctx: Context, enabled: Boolean, catalogUrl: String?) {
            prefs(ctx).edit().putBoolean(KEY_ENABLED, enabled).putString(KEY_URL, catalogUrl).apply()
            val wm = WorkManager.getInstance(ctx)
            if (!enabled) {
                wm.cancelUniqueWork(WORK)
                return
            }
            val request = PeriodicWorkRequestBuilder<UpdateCheckWorker>(6, TimeUnit.HOURS)
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .build()
            wm.enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
        }
    }
}
