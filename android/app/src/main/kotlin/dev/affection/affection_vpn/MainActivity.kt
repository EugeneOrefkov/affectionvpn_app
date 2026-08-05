package dev.affection.affection_vpn

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstallUnknownApps" -> result.success(canInstallUnknownApps())
                "openUnknownSourcesSettings" -> {
                    openUnknownSourcesSettings()
                    result.success(null)
                }
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.error("bad_argument", "apk path is required", null)
                    } else {
                        installApk(File(path), result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun canInstallUnknownApps(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        return packageManager.canRequestPackageInstalls()
    }

    private fun openUnknownSourcesSettings() {
        val uri = Uri.parse("package:$packageName")
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // Settings.ACTION_MANAGE_APP_ALL_UNKNOWN_APP_SOURCES is not exposed
            // in the SDK stubs, use the documented constant value directly.
            Intent("android.settings.MANAGE_APP_ALL_UNKNOWN_APP_SOURCES", uri)
        } else {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, uri)
        }
        startActivity(intent)
    }

    private fun installApk(file: File, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            result.error("unsupported", "PackageInstaller requires API 24+", null)
            return
        }
        if (!file.exists()) {
            result.error("not_found", "APK file not found: ${file.absolutePath}", null)
            return
        }

        val receiver = InstallResultReceiver(result)
        val filter = IntentFilter(ACTION_INSTALL_RESULT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }

        try {
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            params.setAppPackageName(packageName)

            val sessionId = packageManager.packageInstaller.createSession(params)
            val session = packageManager.packageInstaller.openSession(sessionId)

            file.inputStream().use { input ->
                val size = file.length()
                val output = session.openWrite("affection_vpn", 0, size)
                input.copyTo(output)
                session.fsync(output)
                output.close()
            }

            val intent = Intent(ACTION_INSTALL_RESULT)
            intent.setPackage(packageName)
            intent.putExtra(PackageInstaller.EXTRA_SESSION_ID, sessionId)
            val pendingIntent = PendingIntent.getBroadcast(
                this,
                sessionId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            session.commit(pendingIntent.intentSender)
            session.close()
        } catch (e: Exception) {
            runCatching { unregisterReceiver(receiver) }
            result.error("install_failed", e.message ?: "failed to start install", null)
        }
    }

    private class InstallResultReceiver(
        private val result: MethodChannel.Result,
    ) : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -1)
            if (status == PackageInstaller.STATUS_SUCCESS) {
                result.success(true)
            } else {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                    ?: "install status $status"
                result.error("install_failed", message, null)
            }
            runCatching { context.unregisterReceiver(this) }
        }
    }

    companion object {
        private const val CHANNEL = "dev.affection.affection_vpn/installer"
        private const val ACTION_INSTALL_RESULT =
            "dev.affection.affection_vpn.INSTALL_RESULT"
    }
}
