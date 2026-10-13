package com.likestore.market

import android.Manifest
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Native half of lib/src/installer/android_installer.dart. */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()

    /** Flutter calls waiting for the outcome of an install session, by session id. */
    private val pendingInstalls = mutableMapOf<Int, MethodChannel.Result>()

    private val statusListener: (Int, Int, String?, Intent?) -> Unit =
        { id, status, message, confirm -> onInstallStatus(id, status, message, confirm) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "likestore/installer")
            .setMethodCallHandler { call, result ->
                try {
                    handle(call, result)
                } catch (e: Exception) {
                    result.error("error", e.message ?: e.toString(), null)
                }
            }
        InstallEvents.listener = statusListener
    }

    override fun onDestroy() {
        if (InstallEvents.listener === statusListener) InstallEvents.listener = null
        io.shutdown()
        super.onDestroy()
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val pkg = call.argument<String>("packageName")
        when (call.method) {
            "getInstalled" -> result.success(Packages.installed(this, pkg!!)?.let {
                mapOf("versionCode" to it.first, "versionName" to it.second)
            })
            "canRequestInstalls" -> result.success(
                Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
            )
            "openInstallPermissionSettings" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startActivity(
                        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    )
                } else {
                    startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                }
                result.success(null)
            }
            "apkCertSha256" -> {
                val path = call.argument<String>("path")!!
                io.execute {
                    val hash = Packages.archiveCertSha256(this, path)
                    runOnUiThread { result.success(hash) }
                }
            }
            "install" -> install(File(call.argument<String>("path")!!), pkg!!, result)
            "launch" -> {
                val intent = packageManager.getLaunchIntentForPackage(pkg!!)
                if (intent != null) startActivity(intent)
                result.success(intent != null)
            }
            "uninstall" -> {
                startActivity(Intent(Intent.ACTION_DELETE, Uri.parse("package:$pkg")))
                result.success(null)
            }
            "setBackgroundCheck" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                UpdateCheckWorker.configure(this, enabled, call.argument<String>("catalogUrl"))
                if (enabled && Build.VERSION.SDK_INT >= 33 &&
                    checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                ) {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                }
                result.success(null)
            }
            "backgroundCheckEnabled" -> result.success(UpdateCheckWorker.isEnabled(this))
            else -> result.notImplemented()
        }
    }

    /** PackageInstaller session install (never the deprecated ACTION_VIEW intent). */
    private fun install(apk: File, targetPackage: String, result: MethodChannel.Result) {
        io.execute {
            try {
                val sessionId = ApkInstaller.startSession(this, apk, targetPackage)
                runOnUiThread { pendingInstalls[sessionId] = result }
                ApkInstaller.commit(this, sessionId)
            } catch (e: Exception) {
                runOnUiThread { result.success(mapOf("status" to "failure", "message" to (e.message ?: "$e"))) }
            }
        }
    }

    private fun onInstallStatus(sessionId: Int, status: Int, message: String?, confirm: Intent?) {
        runOnUiThread {
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> confirm?.let { startActivity(it) }
                PackageInstaller.STATUS_SUCCESS ->
                    pendingInstalls.remove(sessionId)?.success(mapOf("status" to "success"))
                PackageInstaller.STATUS_FAILURE_ABORTED ->
                    pendingInstalls.remove(sessionId)?.success(mapOf("status" to "cancelled"))
                else -> pendingInstalls.remove(sessionId)?.success(
                    mapOf("status" to "failure", "message" to (message ?: "status $status"))
                )
            }
        }
    }
}
