/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

package me.efesser.flauncher

import android.content.Intent
import android.content.Intent.*
import android.content.pm.ActivityInfo
import android.content.pm.LauncherApps
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.UserHandle
import android.os.Build
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.app.usage.UsageEvents
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.Serializable
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

private const val METHOD_CHANNEL = "me.efesser.flauncher/method"
private const val EVENT_CHANNEL = "me.efesser.flauncher/event"
private const val USAGE_PREFERENCES = "flauncher_usage_history"
private const val USAGE_RESET_AT = "reset_at"

class MainActivity : FlutterActivity() {
    val launcherAppsCallbacks = ArrayList<LauncherApps.Callback>()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getApplications" -> result.success(getApplications())
                "launchApp" -> result.success(launchApp(call.arguments as String))
                "openSettings" -> result.success(openSettings())
                "openAppInfo" -> result.success(openAppInfo(call.arguments as String))
                "uninstallApp" -> result.success(uninstallApp(call.arguments as String))
                "installApk" -> result.success(installApk(call.arguments as String))
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
                "getUsageHistory" -> result.success(getUsageHistory(call.arguments as Int))
                "getUsageSummary" -> result.success(getUsageSummary())
                "resetUsageHistory" -> result.success(resetUsageHistory())
                "isDefaultLauncher" -> result.success(isDefaultLauncher())
                "checkForGetContentAvailability" -> result.success(checkForGetContentAvailability())
                else -> throw IllegalArgumentException()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : StreamHandler {
            lateinit var launcherAppsCallback: LauncherApps.Callback
            val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
            override fun onListen(arguments: Any?, events: EventSink) {
                launcherAppsCallback = object : LauncherApps.Callback() {
                    override fun onPackageRemoved(packageName: String, user: UserHandle) {
                        events.success(mapOf("action" to "PACKAGE_REMOVED", "packageName" to packageName))
                    }

                    override fun onPackageAdded(packageName: String, user: UserHandle) {
                        val applications = getApplication(packageName)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGE_ADDED", "activitiesInfo" to applications))
                        }
                    }

                    override fun onPackageChanged(packageName: String, user: UserHandle) {
                        val applications = getApplication(packageName)
                        if (applications.isNotEmpty()) {
                            events.success(mapOf("action" to "PACKAGE_CHANGED", "activitiesInfo" to applications))
                        }
                    }

                    override fun onPackagesAvailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                    override fun onPackagesUnavailable(packageNames: Array<out String>, user: UserHandle, replacing: Boolean) {}
                }

                launcherAppsCallbacks.add(launcherAppsCallback)
                launcherApps.registerCallback(launcherAppsCallback)
            }

            override fun onCancel(arguments: Any?) {
                launcherApps.unregisterCallback(launcherAppsCallback)
                launcherAppsCallbacks.remove(launcherAppsCallback)
            }
        })
    }

    override fun onDestroy() {
        val launcherApps = getSystemService(LAUNCHER_APPS_SERVICE) as LauncherApps
        launcherAppsCallbacks.forEach(launcherApps::unregisterCallback)
        super.onDestroy()
    }

    private fun getApplications(): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
        val nonTvActivitiesInfo = queryIntentActivities(true)
                .filter { nonTvActivityInfo -> !tvActivitiesInfo.any { tvActivityInfo -> tvActivityInfo.packageName == nonTvActivityInfo.packageName } }
        return tvActivitiesInfo.map { buildAppMap(it, false) } + nonTvActivitiesInfo.map { buildAppMap(it, true) }
    }

    fun getApplication(packageName: String): List<Map<String, Serializable?>> {
        val tvActivitiesInfo = queryIntentActivities(false)
                .filter { it.packageName == packageName }
                .map { buildAppMap(it, false) }
        return if (tvActivitiesInfo.isNotEmpty()) {
            tvActivitiesInfo
        } else {
            queryIntentActivities(true)
                    .filter { it.packageName == packageName }
                    .map { buildAppMap(it, true) }
        }
    }

    private fun queryIntentActivities(sideloaded: Boolean) = packageManager
            .queryIntentActivities(Intent(ACTION_MAIN, null)
                    .addCategory(if (sideloaded) CATEGORY_LAUNCHER else CATEGORY_LEANBACK_LAUNCHER), 0)
            .map(ResolveInfo::activityInfo)

    private fun buildAppMap(activityInfo: ActivityInfo, sideloaded: Boolean) = mapOf(
            "name" to activityInfo.loadLabel(packageManager).toString(),
            "packageName" to activityInfo.packageName,
            "banner" to activityInfo.loadBanner(packageManager)?.let(::drawableToByteArray),
            "icon" to activityInfo.loadIcon(packageManager)?.let(::drawableToByteArray),
            "version" to packageManager.getPackageInfo(activityInfo.packageName, 0).versionName,
            "sideloaded" to sideloaded,
    )

    private fun launchApp(packageName: String) = try {
        val intent = packageManager.getLeanbackLaunchIntentForPackage(packageName)
                ?: packageManager.getLaunchIntentForPackage(packageName)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun openSettings() = try {
        startActivity(Intent(Settings.ACTION_SETTINGS))
        true
    } catch (e: Exception) {
        false
    }

    private fun openAppInfo(packageName: String) = try {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun uninstallApp(packageName: String) = try {
        Intent(ACTION_DELETE)
                .setData(Uri.fromParts("package", packageName, null))
                .let(::startActivity)
        true
    } catch (e: Exception) {
        false
    }

    private fun installApk(filePath: String) = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName")))
            false
        } else {
            val apk = File(filePath)
            if (!apk.exists() || !apk.isFile || apk.length() == 0L) {
                false
            } else {
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", apk)
                startActivity(Intent(ACTION_VIEW)
                        .setDataAndType(uri, "application/vnd.android.package-archive")
                        .addFlags(FLAG_GRANT_READ_URI_PERMISSION or FLAG_ACTIVITY_NEW_TASK))
                true
            }
        }
    } catch (e: Exception) {
        false
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun openUsageAccessSettings() = try {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                .setData(Uri.parse("package:$packageName")))
        true
    } catch (e: Exception) {
        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
        true
    }

    private fun getUsageHistory(requestedDays: Int): List<Map<String, Serializable>> {
        if (!hasUsageAccess()) return emptyList()
        val days = requestedDays.coerceIn(1, 30)
        val manager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.getDefault())
        val result = ArrayList<Map<String, Serializable>>()
        for (offset in 0 until days) {
            val startCalendar = Calendar.getInstance().apply {
                add(Calendar.DAY_OF_YEAR, -offset)
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val dayStart = startCalendar.timeInMillis
            val start = maxOf(dayStart, usageResetAt())
            val end = minOf(dayStart + 24L * 60L * 60L * 1000L, System.currentTimeMillis())
            if (start >= end) continue
            val usageByPackage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                getInteractiveForegroundUsage(manager, start, end)
            } else {
                manager.queryAndAggregateUsageStats(start, end).mapValues { it.value.totalTimeInForeground }
            }
            usageByPackage.entries
                    .filter { it.value >= 60000L }
                    .sortedByDescending { it.value }
                    .forEach { usage ->
                        val label = try {
                            packageManager.getApplicationLabel(
                                    packageManager.getApplicationInfo(usage.key, 0)).toString()
                        } catch (e: Exception) {
                            usage.key
                        }
                        result.add(mapOf(
                                "packageName" to usage.key,
                                "label" to label,
                                "day" to formatter.format(startCalendar.time),
                                "minutes" to (usage.value / 60000L).toInt()
                        ))
                    }
        }
        return result
    }

    private fun getUsageSummary(): Map<String, Serializable> {
        val now = System.currentTimeMillis()
        val result = HashMap<String, Serializable>()
        result["uptimeMinutes"] = (SystemClock.elapsedRealtime() / 60000L).toInt()
        if (!hasUsageAccess()) {
            result["hasAccess"] = false
            result["todayMinutes"] = 0
            result["weekMinutes"] = 0
            result["monthMinutes"] = 0
            return result
        }
        val manager = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
        fun startOf(period: Int): Long = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            when (period) {
                1 -> set(Calendar.DAY_OF_WEEK, firstDayOfWeek)
                2 -> set(Calendar.DAY_OF_MONTH, 1)
            }
        }.timeInMillis
        fun totalSince(start: Long): Int {
            val effectiveStart = maxOf(start, usageResetAt())
            if (effectiveStart >= now) return 0
            val usage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                getInteractiveForegroundUsage(manager, effectiveStart, now)
            } else {
                manager.queryAndAggregateUsageStats(effectiveStart, now).mapValues { it.value.totalTimeInForeground }
            }
            return (usage.values.sum() / 60000L).toInt()
        }
        result["hasAccess"] = true
        result["todayMinutes"] = totalSince(startOf(0))
        result["weekMinutes"] = totalSince(startOf(1))
        result["monthMinutes"] = totalSince(startOf(2))
        return result
    }

    private fun getInteractiveForegroundUsage(
            manager: UsageStatsManager, start: Long, end: Long): Map<String, Long> {
        val totals = HashMap<String, Long>()
        var foregroundPackage: String? = null
        var activeSince: Long? = null
        var screenInteractive = true
        // Read a short lead-in so that an app or screen state which began before
        // the requested period is reconstructed at the period boundary.
        val bootstrapStart = maxOf(0L, start - 7L * 24L * 60L * 60L * 1000L)
        val events = manager.queryEvents(bootstrapStart, end)
        val event = UsageEvents.Event()

        fun stopCounting(at: Long) {
            val app = foregroundPackage
            val since = activeSince
            if (app != null && since != null && at > since) {
                totals[app] = (totals[app] ?: 0L) + (at - since)
            }
            activeSince = null
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    val app = event.packageName ?: continue
                    if (foregroundPackage != app) stopCounting(event.timeStamp)
                    foregroundPackage = app
                    if (screenInteractive) activeSince = maxOf(start, event.timeStamp)
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val app = event.packageName ?: continue
                    if (foregroundPackage == app) {
                        stopCounting(event.timeStamp)
                        foregroundPackage = null
                    }
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    if (screenInteractive) stopCounting(event.timeStamp)
                    screenInteractive = false
                }
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    screenInteractive = true
                    if (foregroundPackage != null) activeSince = maxOf(start, event.timeStamp)
                }
            }
        }
        if (screenInteractive) stopCounting(end)
        return totals
    }

    private fun usageResetAt(): Long =
            getSharedPreferences(USAGE_PREFERENCES, MODE_PRIVATE).getLong(USAGE_RESET_AT, 0L)

    private fun resetUsageHistory(): Boolean {
        getSharedPreferences(USAGE_PREFERENCES, MODE_PRIVATE)
                .edit()
                .putLong(USAGE_RESET_AT, System.currentTimeMillis())
                .apply()
        return true
    }

    private fun checkForGetContentAvailability() = try {
        val intentActivities = packageManager.queryIntentActivities(Intent(ACTION_GET_CONTENT, null).setTypeAndNormalize("image/*"), 0)
        intentActivities.isNotEmpty()
    } catch (e: Exception) {
        false
    }

    private fun isDefaultLauncher() = try {
        val defaultLauncher = packageManager.resolveActivity(Intent(ACTION_MAIN).addCategory(CATEGORY_HOME), 0)
        defaultLauncher?.activityInfo?.packageName == packageName
    } catch (e: Exception) {
        false
    }

    private fun drawableToByteArray(drawable: Drawable): ByteArray {
        fun drawableToBitmap(drawable: Drawable): Bitmap {
            val bitmap = Bitmap.createBitmap(drawable.intrinsicWidth, drawable.intrinsicHeight, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            return bitmap
        }

        val bitmap = drawableToBitmap(drawable)
        val stream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
        return stream.toByteArray()
    }
}
