package com.likestore.market

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

object ApkInstaller {
    const val ACTION_STATUS = "com.likestore.market.INSTALL_STATUS"

    /** Creates a session and streams the APK into it. Returns the session id. */
    fun startSession(context: Context, apk: File, targetPackage: String): Int {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(targetPackage)
            setSize(apk.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setInstallReason(PackageManager.INSTALL_REASON_USER)
            }
            // Android 12+: no prompt for updates of apps this store installed.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        try {
            installer.openSession(sessionId).use { session ->
                FileInputStream(apk).use { input ->
                    session.openWrite("base.apk", 0, apk.length()).use { out ->
                        input.copyTo(out, 1 shl 16)
                        session.fsync(out)
                    }
                }
            }
        } catch (e: Exception) {
            installer.abandonSession(sessionId)
            throw e
        }
        return sessionId
    }

    fun commit(context: Context, sessionId: Int) {
        val intent = Intent(context, InstallReceiver::class.java).setAction(ACTION_STATUS)
        // The system adds the status extras, so the PendingIntent must be mutable.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0)
        val pending = PendingIntent.getBroadcast(context, sessionId, intent, flags)
        context.packageManager.packageInstaller.openSession(sessionId).use { it.commit(pending.intentSender) }
    }
}

/** Receives install session results and hands them to the open activity. */
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
        InstallEvents.dispatch(context, sessionId, status, message, confirm)
    }
}

object InstallEvents {
    var listener: ((Int, Int, String?, Intent?) -> Unit)? = null

    fun dispatch(context: Context, sessionId: Int, status: Int, message: String?, confirm: Intent?) {
        val l = listener
        if (l != null) {
            l(sessionId, status, message, confirm)
        } else if (status == PackageInstaller.STATUS_PENDING_USER_ACTION && confirm != null) {
            // No activity to show the system prompt from; try anyway.
            context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

object Packages {
    /** (versionCode, versionName) of an installed package, or null. */
    fun installed(context: Context, packageName: String): Pair<Long, String>? = try {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= 33) {
            pm.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageInfo(packageName, 0)
        }
        val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        code to (info.versionName ?: "")
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /** SHA-256 (hex) of the certificate an APK file is signed with, or null. */
    fun archiveCertSha256(context: Context, path: String): String? {
        val pm = context.packageManager
        val cert: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
                ?.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
        } else {
            @Suppress("DEPRECATION")
            pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
                ?.signatures?.firstOrNull()?.toByteArray()
        }
        return cert?.let { bytes ->
            MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        }
    }
}
