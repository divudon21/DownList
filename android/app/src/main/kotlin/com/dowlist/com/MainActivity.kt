package com.dowlist.com

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.dowlist.com/native"
        private const val REQ_PICK_FILES = 9401
        private const val ICON_SIZE_PX = 96

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "org.chromium.chrome",
            "org.mozilla.firefox",
            "org.mozilla.firefox_beta",
            "org.mozilla.fenix",
            "org.mozilla.focus",
            "com.brave.browser",
            "com.brave.browser_beta",
            "com.microsoft.emmx",
            "com.opera.browser",
            "com.opera.mini.native",
            "com.opera.gx",
            "com.sec.android.app.sbrowser",
            "com.sec.android.app.sbrowser.beta",
            "com.UCMobile.intl",
            "com.uc.browser.en",
            "com.duckduckgo.mobile.android",
            "com.vivaldi.browser",
            "com.kiwibrowser.browser",
            "mark.via.gp",
            "mark.via",
            "com.mycompany.app.soulbrowser",
            "com.yandex.browser",
            "com.mi.globalbrowser",
            "com.android.browser",
            "com.heytap.browser",
            "com.coloros.browser",
            "com.vivo.browser",
            "com.transsion.phoenix",
            "com.jio.web",
            "com.aloha.browser",
            "com.android.documentsui",
            "com.google.android.documentsui"
        )
    }

    private var methodChannel: MethodChannel? = null
    private var pendingPickResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val uploadExecutor = Executors.newCachedThreadPool()
    private var permissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
        methodChannel = channel
        TransferService.eventSink = { payload -> mainHandler.post { methodChannel?.invokeMethod("onUploadEvent", payload) } }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppBuildInfo" -> {
                    try {
                        val flags = if (android.os.Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else @Suppress("DEPRECATION") PackageManager.GET_SIGNATURES
                        val info = packageManager.getPackageInfo(packageName, flags)
                        val signatures = if (android.os.Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") info.signatures
                        val signature = signatures?.firstOrNull() ?: throw IllegalStateException("Signing certificate unavailable")
                        val hash = java.security.MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 0xff) }
                        val code = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
                        result.success(mapOf("versionName" to (info.versionName ?: ""), "versionCode" to code, "packageName" to packageName, "signerSha256" to hash))
                    } catch (e: Exception) { result.error("BUILD_INFO_ERROR", "Could not read installed app information.", null) }
                }
                "showUpdateNotification" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("url") ?: "")
                        require(uri.scheme == "https" && uri.host == "github.com" && uri.path?.startsWith("/divudon21/DownList/releases/") == true)
                        val manager = getSystemService(android.app.NotificationManager::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= 26) {
                            manager.createNotificationChannel(android.app.NotificationChannel("downlist_updates", "App updates", android.app.NotificationManager.IMPORTANCE_DEFAULT))
                        }
                        if (!manager.areNotificationsEnabled() || (android.os.Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel("downlist_updates")?.importance == android.app.NotificationManager.IMPORTANCE_NONE)) {
                            result.success(false)
                        } else {
                            val launch = Intent(Intent.ACTION_VIEW, uri)
                            val pending = android.app.PendingIntent.getActivity(this, 9351, launch, android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE)
                            val builder = if (android.os.Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(this, "downlist_updates") else @Suppress("DEPRECATION") android.app.Notification.Builder(this)
                            val version = (call.argument<String>("version") ?: "").take(80)
                            val compatible = call.argument<Boolean>("compatible") == true
                            val text = if (compatible) "DownList $version is available." else "DownList $version is available; reinstall may be required."
                            manager.notify(9351, builder.setSmallIcon(android.R.drawable.stat_sys_download_done).setContentTitle("DownList update available").setContentText(text).setStyle(android.app.Notification.BigTextStyle().bigText(text)).setContentIntent(pending).setAutoCancel(true).build())
                            result.success(true)
                        }
                    } catch (e: SecurityException) { result.success(false) }
                    catch (e: Exception) { result.error("NOTIFICATION_ERROR", "Could not show update notification.", null) }
                }
                "clearUpdateNotification" -> {
                    getSystemService(android.app.NotificationManager::class.java).cancel(9351)
                    result.success(true)
                }
                "getAppVersion" -> {
                    try {
                        val info = packageManager.getPackageInfo(packageName, 0)
                        result.success(info.versionName ?: "")
                    } catch (_: Exception) { result.success("") }
                }
                "pickFiles" -> handlePickFiles(result)
                "startUpload" -> handleStartUpload(call, result)
                "cancelUpload" -> handleCancelUpload(call, result)
                "cancelAllUploads" -> { TransferService.cancelAll(); result.success(true) }
                "getUploadSnapshots" -> result.success(TransferService.uploadSnapshots())
                "getServerTaskSnapshots" -> result.success(TransferService.serverTaskSnapshots())
                "startServerMonitor" -> {
                    val base = call.argument<String>("baseUrl") ?: ""
                    val id = call.argument<String>("taskId") ?: ""
                    if (base.isBlank() || id.isBlank()) result.error("INVALID_ARGS", "Missing server task", null)
                    else try {
                        val intent = Intent(this, TransferService::class.java).setAction(TransferService.ACTION_MONITOR)
                            .putExtra("baseUrl", base).putExtra("taskId", id)
                            .putExtra("isGofile", call.argument<Boolean>("isGofile") == true)
                        startTransferService(intent)
                        result.success(true)
                    } catch (e: Exception) { result.error("SERVICE_ERROR", e.message, null) }
                }
                "getNotificationSettings" -> {
                    val prefs = getSharedPreferences("downlist_notifications", MODE_PRIVATE)
                    val manager = getSystemService(android.app.NotificationManager::class.java)
                    result.success(mapOf("uploads" to prefs.getBoolean("uploads", true),
                        "downloads" to prefs.getBoolean("downloads", true),
                        "enabled" to manager.areNotificationsEnabled()))
                }
                "setNotificationSetting" -> {
                    val key = call.argument<String>("key") ?: ""
                    if (key != "uploads" && key != "downloads") result.error("INVALID_ARGS", "Invalid setting", null)
                    else {
                        getSharedPreferences("downlist_notifications", MODE_PRIVATE).edit().putBoolean(key, call.argument<Boolean>("value") == true).apply()
                        TransferService.refreshNotifications()
                        result.success(true)
                    }
                }
                "requestNotificationPermission" -> requestNotificationPermission(result)
                "openNotificationSettings" -> {
                    val intent = if (android.os.Build.VERSION.SDK_INT >= 26) Intent(android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(android.provider.Settings.EXTRA_APP_PACKAGE, packageName)
                        else Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                    startActivity(intent); result.success(true)
                }
                "getMediaPlayers" -> handleGetMediaPlayers(call, result)
                "launchMediaPlayer" -> handleLaunchMediaPlayer(call, result)
                "openExternalPlayer" -> handleOpenExternalPlayer(call, result)
                "openUrl" -> {
                    try {
                        val url = call.argument<String>("url") ?: ""
                        val uri = Uri.parse(url)
                        require(uri.scheme == "https" || uri.scheme == "http")
                        startActivity(Intent(Intent.ACTION_VIEW, uri))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL_FAILED", "Unable to open link.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handlePickFiles(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("ALREADY_ACTIVE", "File picker is already open", null)
            return
        }
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
            startActivityForResult(intent, REQ_PICK_FILES)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICKER_ERROR", e.message ?: "Could not open file picker", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_PICK_FILES) return

        val callback = pendingPickResult
        pendingPickResult = null
        if (callback == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<Map<String, Any>>())
            return
        }

        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                val u = clipData.getItemAt(i)?.uri
                if (u != null) uris.add(u)
            }
        } else {
            data.data?.let { uris.add(it) }
        }

        val pickedList = mutableListOf<Map<String, Any>>()
        for (uri in uris) {
            try {
                contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: Exception) {
            }

            var displayName = "file_${System.currentTimeMillis()}"
            var sizeBytes = 0L

            try {
                contentResolver.query(
                    uri,
                    arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                    null,
                    null,
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (nameIdx >= 0 && !cursor.isNull(nameIdx)) {
                            val n = cursor.getString(nameIdx)
                            if (!n.isNullOrBlank()) displayName = n
                        }
                        val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                        if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                            sizeBytes = cursor.getLong(sizeIdx)
                        }
                    }
                }
            } catch (_: Exception) {
            }

            if (sizeBytes <= 0L) {
                try {
                    contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                        if (afd.length > 0L) sizeBytes = afd.length
                    }
                } catch (_: Exception) {
                }
            }

            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            pickedList.add(
                mapOf(
                    "uri" to uri.toString(),
                    "name" to displayName,
                    "size" to sizeBytes,
                    "mimeType" to mimeType
                )
            )
        }

        callback.success(pickedList)
    }

    private fun startTransferService(intent: Intent) {
        if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
    }

    private fun handleStartUpload(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("uploadId")
        val uri = call.argument<String>("uri")
        val url = call.argument<String>("uploadUrl")
        if (id.isNullOrBlank() || uri.isNullOrBlank() || url.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing upload arguments", null); return
        }
        try {
            val intent = Intent(this, TransferService::class.java).setAction(TransferService.ACTION_UPLOAD)
                .putExtra("uploadId", id).putExtra("uri", uri).putExtra("uploadUrl", url)
                .putExtra("fileName", call.argument<String>("fileName") ?: "file")
                .putExtra("fileSize", (call.argument<Number>("fileSize"))?.toLong() ?: 0L)
            startTransferService(intent)
            result.success(true)
        } catch (e: Exception) { result.error("SERVICE_ERROR", e.message, null) }
    }

    private fun handleCancelUpload(call: MethodCall, result: MethodChannel.Result) {
        call.argument<String>("uploadId")?.let { TransferService.cancel(it) }
        result.success(true)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (android.os.Build.VERSION.SDK_INT < 33 || checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(getSystemService(android.app.NotificationManager::class.java).areNotificationsEnabled()); return
        }
        if (permissionResult != null) { result.error("BUSY", "Permission request already open", null); return }
        permissionResult = result
        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 9402)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 9402) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }

    private fun queryAllActivities(intent: Intent): List<ResolveInfo> {
        val combined = LinkedHashMap<String, ResolveInfo>()
        try {
            for (info in packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)) {
                val key = "${info.activityInfo.packageName}/${info.activityInfo.name}"
                combined.putIfAbsent(key, info)
            }
        } catch (_: Exception) {
        }
        try {
            for (info in packageManager.queryIntentActivities(intent, 0)) {
                val key = "${info.activityInfo.packageName}/${info.activityInfo.name}"
                combined.putIfAbsent(key, info)
            }
        } catch (_: Exception) {
        }
        return combined.values.toList()
    }

    private fun discoverMediaPlayers(
        streamUrl: String,
        fileName: String,
        mimeType: String
    ): List<ResolveInfo> {
        val isAudio = mimeType.startsWith("audio/")
        val genericMime = if (isAudio) "audio/*" else "video/*"
        val fallbackExt = if (isAudio) "mp3" else "mp4"
        val rawExt = fileName.substringAfterLast('.', "").lowercase()
        val safeExt = if (rawExt.matches(Regex("[a-z0-9]{2,5}"))) rawExt else fallbackExt

        // Dynamically detect generic web browser activities (apps matching a plain webpage URL)
        val plainWebIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.example.com/"))
        val webBrowserActivities = queryAllActivities(plainWebIntent)
            .map { "${it.activityInfo.packageName}/${it.activityInfo.name}" }
            .toSet()

        val streamUri = Uri.parse(streamUrl)
        // Ordered from explicit network stream handlers -> generic video/audio players
        val probes = listOf(
            Intent(Intent.ACTION_VIEW).apply { setDataAndType(streamUri, mimeType) },
            Intent(Intent.ACTION_VIEW).apply { setDataAndType(streamUri, genericMime) },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("http://example.com/stream.$safeExt"), genericMime)
            },
            Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com/stream.$safeExt")),
            Intent(Intent.ACTION_VIEW).apply {
                val contentSample = if (isAudio) {
                    "content://media/external/audio/media/1"
                } else {
                    "content://media/external/video/media/1"
                }
                setDataAndType(Uri.parse(contentSample), genericMime)
            },
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse("file:///storage/emulated/0/stream.$safeExt"), genericMime)
            }
        )

        val selfPkg = applicationContext.packageName
        val byPackage = LinkedHashMap<String, ResolveInfo>()

        for (probe in probes) {
            for (info in queryAllActivities(probe)) {
                val ai = info.activityInfo ?: continue
                val pkg = ai.packageName ?: continue
                val actKey = "$pkg/${ai.name}"
                if (pkg == selfPkg) continue
                if (!ai.exported) continue
                if (pkg in BROWSER_PACKAGES) continue
                if (actKey in webBrowserActivities) continue

                byPackage.putIfAbsent(pkg, info)
            }
        }

        return byPackage.values.toList()
    }

    private fun drawableToPngBytes(drawable: Drawable): ByteArray {
        val bmp = Bitmap.createBitmap(ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        drawable.setBounds(0, 0, ICON_SIZE_PX, ICON_SIZE_PX)
        drawable.draw(canvas)
        val out = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
        bmp.recycle()
        return out.toByteArray()
    }

    private fun handleGetMediaPlayers(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url") ?: ""
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"

        if (url.isBlank()) {
            result.error("INVALID_URL", "Stream URL is empty", null)
            return
        }

        uploadExecutor.execute {
            try {
                val resolved = discoverMediaPlayers(url, fileName, mimeType)
                val items = resolved.map { info ->
                    val ai = info.activityInfo
                    val appLabel = info.loadLabel(packageManager)?.toString()?.trim()
                        ?.takeIf { it.isNotEmpty() }
                        ?: ai.applicationInfo.loadLabel(packageManager)?.toString()?.trim()
                        ?: ai.packageName
                    val iconBytes = try {
                        drawableToPngBytes(info.loadIcon(packageManager))
                    } catch (_: Exception) {
                        ByteArray(0)
                    }
                    Triple(
                        appLabel,
                        ai.packageName,
                        mapOf<String, Any>(
                            "packageName" to ai.packageName,
                            "activityName" to ai.name,
                            "label" to appLabel,
                            "icon" to iconBytes
                        )
                    )
                }.sortedBy { it.first.lowercase() }.map { it.third }

                mainHandler.post {
                    result.success(items)
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("QUERY_ERROR", e.message ?: "Could not query media players", null)
                }
            }
        }
    }

    private fun buildStreamIntent(
        uri: Uri,
        fileName: String,
        mimeType: String,
        packageName: String? = null,
        activityName: String? = null
    ): Intent {
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            putExtra("title", fileName)
            putExtra(Intent.EXTRA_TITLE, fileName)
            putExtra("forcename", fileName)
            putExtra("secure_uri", true)
            if (!packageName.isNullOrBlank() && !activityName.isNullOrBlank()) {
                setClassName(packageName, activityName)
            } else if (!packageName.isNullOrBlank()) {
                setPackage(packageName)
            }
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun handleLaunchMediaPlayer(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"
        val packageName = call.argument<String>("packageName")
        val activityName = call.argument<String>("activityName")

        if (url.isNullOrBlank() || packageName.isNullOrBlank()) {
            result.error("INVALID_ARGS", "Missing player launch parameters", null)
            return
        }

        val uri = Uri.parse(url)
        val genericMime = if (mimeType.startsWith("audio/")) "audio/*" else "video/*"

        try {
            startActivity(buildStreamIntent(uri, fileName, mimeType, packageName, activityName))
            result.success(true)
            return
        } catch (_: Exception) {
        }

        try {
            startActivity(buildStreamIntent(uri, fileName, genericMime, packageName, activityName))
            result.success(true)
            return
        } catch (_: Exception) {
        }

        try {
            startActivity(buildStreamIntent(uri, fileName, genericMime, packageName, null))
            result.success(true)
        } catch (e: Exception) {
            result.error("PLAYER_ERROR", e.message ?: "Failed to launch selected player", null)
        }
    }

    private fun handleOpenExternalPlayer(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val fileName = call.argument<String>("fileName") ?: "Stream"
        val mimeType = call.argument<String>("mimeType") ?: "video/*"

        if (url.isNullOrBlank()) {
            result.error("INVALID_URL", "Stream URL is empty", null)
            return
        }

        try {
            val uri = Uri.parse(url)
            val players = discoverMediaPlayers(url, fileName, mimeType)
            if (players.isNotEmpty()) {
                val target = players[0].activityInfo
                startActivity(
                    buildStreamIntent(uri, fileName, mimeType, target.packageName, target.name)
                )
                result.success(true)
                return
            }

            val genericMime = if (mimeType.startsWith("audio/")) "audio/*" else "video/*"
            startActivity(buildStreamIntent(uri, fileName, genericMime))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error(
                "NO_VIDEO_PLAYER",
                "No video player app found. Please install VLC, MX Player, or another video player.",
                null
            )
        } catch (e: Exception) {
            result.error("PLAYER_ERROR", e.message ?: "Failed to launch video player", null)
        }
    }

    override fun onDestroy() {
        TransferService.eventSink = null
        methodChannel = null
        uploadExecutor.shutdownNow()
        super.onDestroy()
    }
}
