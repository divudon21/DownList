package com.dowlist.com

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.InputStream
import java.lang.ref.WeakReference
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Keeps active device uploads and server task monitoring alive while the app is backgrounded. */
class TransferService : Service() {
    class ActiveUpload(
        val cancelled: AtomicBoolean = AtomicBoolean(false),
        @Volatile var connection: HttpURLConnection? = null,
        @Volatile var inputStream: InputStream? = null
    )
    data class ServerTask(val base: String, val id: String, val gofile: Boolean,
        @Volatile var label: String = "Connecting", @Volatile var progress: Int = -1,
        @Volatile var failures: Int = 0, @Volatile var filename: String = "",
        @Volatile var current: Long = 0, @Volatile var total: Long = 0,
        @Volatile var speed: Double = 0.0)

    companion object {
        const val ACTION_UPLOAD = "com.dowlist.com.UPLOAD"
        const val ACTION_MONITOR = "com.dowlist.com.MONITOR"
        private const val BUFFER_SIZE = 65536
        private const val CHANNEL_ID = "downlist_transfers"
        private const val NOTIFICATION_ID = 7314
        private val activeUploads = ConcurrentHashMap<String, ActiveUpload>()
        private val snapshots = ConcurrentHashMap<String, Map<String, Any?>>()
        private val serverTasks = ConcurrentHashMap<String, ServerTask>()
        private val executor = Executors.newFixedThreadPool(2)
        @Volatile var eventSink: ((Map<String, Any?>) -> Unit)? = null
        @Volatile private var service: WeakReference<TransferService>? = null

        fun uploadSnapshots(): List<Map<String, Any?>> = snapshots.values.toList()
        fun serverTaskSnapshots(): List<Map<String, Any>> = serverTasks.values.map {
            mapOf("baseUrl" to it.base, "taskId" to it.id, "isGofile" to it.gofile)
        }
        fun cancel(id: String) {
            val active = activeUploads[id] ?: return
            active.cancelled.set(true)
            Thread {
                try { active.inputStream?.close() } catch (_: Exception) {}
                try { active.connection?.disconnect() } catch (_: Exception) {}
            }.start()
        }
        fun cancelAll() { activeUploads.keys.toList().forEach { cancel(it) } }
        fun refreshNotifications() { service?.get()?.mainHandler?.post { service?.get()?.updateNotification() } }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val monitorExecutor = Executors.newSingleThreadScheduledExecutor()

    override fun onCreate() {
        super.onCreate()
        service = WeakReference(this)
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL_ID, "Transfers", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Upload and server task progress"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        monitorExecutor.scheduleWithFixedDelay({ pollServerTasks() }, 0, 3, TimeUnit.SECONDS)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Android requires foreground promotion immediately, including when notifications are denied.
        val notification = makeNotification()
        if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(NOTIFICATION_ID, notification)
        when (intent?.action) {
            ACTION_UPLOAD -> {
                val id = intent.getStringExtra("uploadId") ?: return START_NOT_STICKY
                val uri = intent.getStringExtra("uri") ?: return START_NOT_STICKY
                val url = intent.getStringExtra("uploadUrl") ?: return START_NOT_STICKY
                val name = intent.getStringExtra("fileName") ?: "file"
                val size = intent.getLongExtra("fileSize", 0L)
                val active = ActiveUpload()
                if (activeUploads.putIfAbsent(id, active) == null) {
                    snapshots[id] = mapOf("uploadId" to id, "uri" to uri, "fileName" to name,
                        "totalBytes" to size, "uploadedBytes" to 0L, "status" to "uploading")
                    executor.execute { runStreamingUpload(id, uri, name, size, url, active) }
                }
            }
            ACTION_MONITOR -> {
                val base = intent.getStringExtra("baseUrl") ?: return START_NOT_STICKY
                val id = intent.getStringExtra("taskId") ?: return START_NOT_STICKY
                val key = "$base|$id"
                serverTasks.putIfAbsent(key, ServerTask(base, id, intent.getBooleanExtra("isGofile", false)))
            }
            else -> { stopIfIdle() }
        }
        updateNotification()
        return START_NOT_STICKY
    }

    private fun emitUploadEvent(payload: Map<String, Any?>) {
        val id = payload["uploadId"] as? String ?: return
        val prior = snapshots[id] ?: emptyMap()
        val merged = prior + payload
        snapshots[id] = if (payload["status"] == "uploading" && (prior["totalBytes"] as? Number)?.toLong() == 0L)
            merged + mapOf("totalBytes" to 0L) else merged
        eventSink?.invoke(snapshots[id]!!)
        refreshNotifications()
    }

    private fun stopIfIdle() {
        mainHandler.postDelayed({
            if (activeUploads.isEmpty() && serverTasks.isEmpty()) {
                if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
                stopSelf()
            }
        }, 500)
    }

    private fun pollServerTasks() {
        for ((key, task) in serverTasks.entries) {
            var conn: HttpURLConnection? = null
            try {
                conn = URL(task.base.trimEnd('/') + "/status/" + Uri.encode(task.id)).openConnection() as HttpURLConnection
                conn.connectTimeout = 15000; conn.readTimeout = 15000
                if (conn.responseCode !in 200..299) throw IllegalStateException("Server unavailable")
                val data = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
                val status = data.optString("status", "unknown").lowercase()
                val hasLink = data.optString("gofile_url", "").let { it.isNotBlank() && it != "null" }
                val total = data.optLong("total_size", 0)
                val current = data.optLong("downloaded", 0)
                task.filename = data.optString("original_filename", "").take(100)
                task.current = current
                task.total = total
                task.speed = data.optDouble("speed", 0.0)
                task.label = when (status) {
                    "downloading" -> "Downloading on server"
                    "uploading_to_gofile" -> "Uploading to GoFile"
                    "completed" -> if (task.gofile && !hasLink) "Preparing GoFile upload" else "Completed"
                    "extracting" -> "Extracting"
                    else -> status.replace('_', ' ').replaceFirstChar { it.uppercase() }
                }
                task.progress = if (total > 0 && status != "completed" && !(status == "uploading_to_gofile" && (current <= 0 || current >= total)))
                    ((current.toDouble() / total * 100).toInt()).coerceIn(0, 100) else -1
                task.failures = 0
                val terminal = status in setOf("error", "failed", "cancelled", "extraction_error", "extracted", "done", "finished") ||
                    (status == "completed" && (!task.gofile || hasLink))
                if (terminal) serverTasks.remove(key, task)
            } catch (_: Exception) {
                task.label = "Waiting for server"
                task.progress = -1
                task.failures++
                // Avoid an endless foreground service if a server disappears.
                if (task.failures >= 120) serverTasks.remove(key, task)
            } finally { conn?.disconnect() }
        }
        refreshNotifications()
        if (activeUploads.isEmpty() && serverTasks.isEmpty()) stopIfIdle()
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes < 1024) return "$bytes B"
        val units = arrayOf("KB", "MB", "GB", "TB")
        var value = bytes.toDouble() / 1024
        var index = 0
        while (value >= 1024 && index < units.lastIndex) { value /= 1024; index++ }
        return String.format(java.util.Locale.US, "%.1f %s", value, units[index])
    }

    private fun makeNotification(): Notification {
        val prefs = getSharedPreferences("downlist_notifications", MODE_PRIVATE)
        val showUploads = prefs.getBoolean("uploads", true)
        val showDownloads = prefs.getBoolean("downloads", true)
        val uploads = if (showUploads) activeUploads.keys.mapNotNull { snapshots[it] } else emptyList()
        val downloads = serverTasks.values.filter {
            if (it.label == "Uploading to GoFile" || it.label == "Preparing GoFile upload") showUploads else showDownloads
        }
        val lines = mutableListOf<String>()
        var progress = -1
        for (u in uploads) {
            val total = (u["totalBytes"] as? Number)?.toLong() ?: 0L
            val current = (u["uploadedBytes"] as? Number)?.toLong() ?: 0L
            val percent = if (total > 0) ((current.toDouble() / total) * 100).toInt().coerceIn(0, 100) else -1
            if (progress == -1 && percent >= 0) progress = percent
            val speed = (u["speed"] as? Number)?.toDouble() ?: 0.0
            val amount = if (total > 0) " · ${formatBytes(current)}/${formatBytes(total)}" else " · ${formatBytes(current)}"
            lines.add("Uploading ${u["fileName"] ?: "file"}${if (percent >= 0) " · $percent%" else ""}$amount${if (speed > 0) " · ${formatBytes(speed.toLong())}/s" else ""}")
        }
        for (task in downloads) {
            if (progress == -1 && task.progress >= 0) progress = task.progress
            val name = if (task.filename.isNotBlank()) " · ${task.filename}" else ""
            val amount = if (task.progress >= 0) " · ${task.progress}% · ${formatBytes(task.current)}/${formatBytes(task.total)}" else ""
            val speed = if (task.progress >= 0 && task.speed > 0) " · ${formatBytes(task.speed.toLong())}/s" else ""
            lines.add(task.label + name + amount + speed)
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID) else @Suppress("DEPRECATION") Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.stat_sys_upload)
            .setContentTitle("DownList transfers")
            .setContentText(lines.firstOrNull() ?: "Transfer running")
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(100, if (progress < 0) 0 else progress, progress < 0)
        if (lines.size > 1) {
            val style = Notification.InboxStyle().setSummaryText("${lines.size} active transfers")
            lines.take(5).forEach { style.addLine(it) }
            builder.setStyle(style)
        } else if (lines.size == 1) {
            builder.setStyle(Notification.BigTextStyle().bigText(lines[0]))
        }
        return builder.build()
    }

    private fun updateNotification() {
        if (activeUploads.isNotEmpty() || serverTasks.isNotEmpty()) {
            try { getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, makeNotification()) } catch (_: SecurityException) {}
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        service = null
        monitorExecutor.shutdownNow()
        super.onDestroy()
    }
    private fun runStreamingUpload(
        uploadId: String,
        uriStr: String,
        fileName: String,
        declaredSize: Long,
        uploadUrl: String,
        active: ActiveUpload
    ) {
        val wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DownList:upload")
        wakeLock.acquire(6 * 60 * 60 * 1000L)
        var conn: HttpURLConnection? = null
        var rawStream: InputStream? = null
        try {
            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val uri = Uri.parse(uriStr)
            rawStream = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Cannot read selected file from storage")
            active.inputStream = rawStream

            val boundary = "----DownListBoundary${UUID.randomUUID().toString().replace("-", "")}"
            val safeName = fileName
                .replace("\"", "_")
                .replace("\r", "")
                .replace("\n", "")

            val headerStr = buildString {
                append("--").append(boundary).append("\r\n")
                append("Content-Disposition: form-data; name=\"file\"; filename=\"")
                    .append(safeName)
                    .append("\"\r\n")
                append("Content-Type: application/octet-stream\r\n\r\n")
            }
            val footerStr = "\r\n--$boundary--\r\n"

            val headerBytes = headerStr.toByteArray(Charsets.UTF_8)
            val footerBytes = footerStr.toByteArray(Charsets.UTF_8)

            conn = (URL(uploadUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doInput = true
                doOutput = true
                useCaches = false
                connectTimeout = 30_000
                readTimeout = 300_000
                setRequestProperty("Connection", "Keep-Alive")
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
                if (declaredSize > 0L) {
                    val totalLen = headerBytes.size.toLong() + declaredSize + footerBytes.size.toLong()
                    setFixedLengthStreamingMode(totalLen)
                } else {
                    setChunkedStreamingMode(BUFFER_SIZE)
                }
            }

            active.connection = conn
            if (active.cancelled.get()) {
                conn.disconnect()
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val buf = ByteArray(BUFFER_SIZE)
            var uploaded = 0L
            var lastReportTime = System.currentTimeMillis()
            var lastReportBytes = 0L
            var smoothedSpeed = 0.0

            BufferedOutputStream(conn.outputStream, BUFFER_SIZE).use { out ->
                out.write(headerBytes)
                BufferedInputStream(rawStream, BUFFER_SIZE).use { input ->
                    while (!active.cancelled.get()) {
                        val maxToRead = if (declaredSize > 0L) {
                            val remaining = declaredSize - uploaded
                            if (remaining <= 0L) break
                            minOf(buf.size.toLong(), remaining).toInt()
                        } else {
                            buf.size
                        }

                        val readCount = input.read(buf, 0, maxToRead)
                        if (readCount == -1) break

                        out.write(buf, 0, readCount)
                        uploaded += readCount

                        val now = System.currentTimeMillis()
                        val elapsed = now - lastReportTime
                        if (elapsed >= 200L) {
                            val instantSpeed = ((uploaded - lastReportBytes) * 1000.0) / elapsed.toDouble()
                            smoothedSpeed = if (smoothedSpeed <= 0.0) {
                                instantSpeed
                            } else {
                                smoothedSpeed * 0.65 + instantSpeed * 0.35
                            }
                            lastReportTime = now
                            lastReportBytes = uploaded
                            emitUploadEvent(
                                mapOf(
                                    "uploadId" to uploadId,
                                    "status" to "uploading",
                                    "uploadedBytes" to uploaded,
                                    "totalBytes" to if (declaredSize > 0L) declaredSize else uploaded,
                                    "speed" to smoothedSpeed
                                )
                            )
                        }
                    }
                }

                if (active.cancelled.get()) {
                    emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                    return
                }

                out.write(footerBytes)
                out.flush()
            }

            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
                return
            }

            val code = conn.responseCode
            val responseStream = if (code in 200..299) conn.inputStream else conn.errorStream
            val responseBody = responseStream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""

            if (code in 200..299) {
                val finalTotal = if (declaredSize > 0L) declaredSize else uploaded
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "completed",
                        "uploadedBytes" to finalTotal,
                        "totalBytes" to finalTotal,
                        "speed" to 0.0,
                        "responseBody" to responseBody
                    )
                )
            } else {
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "error",
                        "error" to "Upload failed (HTTP $code): ${responseBody.take(180)}"
                    )
                )
            }
        } catch (e: Exception) {
            if (active.cancelled.get()) {
                emitUploadEvent(mapOf("uploadId" to uploadId, "status" to "cancelled"))
            } else {
                emitUploadEvent(
                    mapOf(
                        "uploadId" to uploadId,
                        "status" to "error",
                        "error" to (e.message ?: "Upload interrupted")
                    )
                )
            }
        } finally {
            activeUploads.remove(uploadId)
            if (wakeLock.isHeld) wakeLock.release()
            refreshNotifications()
            stopIfIdle()
            try {
                rawStream?.close()
            } catch (_: Exception) {
            }
            try {
                conn?.disconnect()
            } catch (_: Exception) {
            }
        }
    }


}
