package com.github.tfox.flutter_vless

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.net.TrafficStats
import android.os.Build
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class AppTrafficMonitor(private val context: Context) {
    private val pm = context.packageManager
    private val executor = Executors.newSingleThreadExecutor()
    private val prevTraffic = mutableMapOf<Int, LongArray>()
    private val iconCache = mutableMapOf<String, String>()

    @Volatile
    private var cached: List<Map<String, Any>> = emptyList()

    init {
        executor.execute {
            cacheIcons()
            while (!Thread.currentThread().isInterrupted) {
                cached = pollDeltas()
                try {
                    Thread.sleep(1000)
                } catch (_: InterruptedException) {
                    break
                }
            }
        }
    }

    fun getTrafficStats(): List<Map<String, Any>> = cached

    private fun cacheIcons() {
        val packages = if (Build.VERSION.SDK_INT >= 33) {
            pm.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(PackageManager.GET_META_DATA)
        }
        for (pkg in packages) {
            try {
                val drawable = pm.getApplicationIcon(pkg)
                val bmp = if (drawable is BitmapDrawable) {
                    drawable.bitmap
                } else {
                    val b = Bitmap.createBitmap(
                        drawable.intrinsicWidth.coerceAtLeast(1),
                        drawable.intrinsicHeight.coerceAtLeast(1),
                        Bitmap.Config.ARGB_8888
                    )
                    Canvas(b).let { c ->
                        drawable.setBounds(0, 0, c.width, c.height)
                        drawable.draw(c)
                    }
                    b
                }
                val scaled = Bitmap.createScaledBitmap(bmp, 72, 72, true)
                if (scaled !== bmp) bmp.recycle()
                val out = ByteArrayOutputStream()
                scaled.compress(Bitmap.CompressFormat.WEBP_LOSSY, 75, out)
                scaled.recycle()
                iconCache[pkg.packageName] =
                    Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
            } catch (_: Exception) {
            }
        }
    }

    private fun pollDeltas(): List<Map<String, Any>> {
        val packages = if (Build.VERSION.SDK_INT >= 33) {
            pm.getInstalledApplications(
                PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
            )
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(PackageManager.GET_META_DATA)
        }
        val result = mutableListOf<Map<String, Any>>()
        for (pkg in packages) {
            val uid = pkg.uid
            if (uid < 0) continue
            val rx = TrafficStats.getUidRxBytes(uid)
            val tx = TrafficStats.getUidTxBytes(uid)
            val p = prevTraffic[uid]
            prevTraffic[uid] = longArrayOf(rx, tx)
            if (p == null) continue
            val drx = rx - p[0]
            val dtx = tx - p[1]
            if (drx <= 0 && dtx <= 0) continue
            result.add(
                mapOf(
                    "uid" to uid,
                    "packageName" to pkg.packageName,
                    "label" to (pm.getApplicationLabel(pkg)?.toString()
                        ?: pkg.packageName),
                    "icon" to (iconCache[pkg.packageName] ?: ""),
                    "rxBytes" to drx,
                    "txBytes" to dtx
                )
            )
        }
        return result
    }

    fun dispose() {
        executor.shutdownNow()
    }
}
