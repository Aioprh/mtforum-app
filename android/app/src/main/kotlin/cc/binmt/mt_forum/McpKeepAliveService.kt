package cc.binmt.mt_forum

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
import androidx.core.app.NotificationCompat

/**
 * MCP 服务的前台保活。
 *
 * App 退到后台后，普通进程随时可能被系统回收或冻结，Dart 里的 HttpServer
 * 跟着断掉，电脑上的 AI 客户端就再也连不上。这里挂一个前台服务：通知栏
 * 常驻一条低优先级通知，进程会被系统当作「正在运行」对待，不会因为
 * 内存回收或后台限制被清掉。
 *
 * 服务本身不跑任何业务，只负责把宿主进程按住；HTTP 监听仍然在 Flutter 侧。
 */
class McpKeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "mt_forum_mcp"
        private const val NOTIFICATION_ID = 8642
        private const val ACTION_START = "cc.binmt.mt_forum.MCP_KEEP_ALIVE_START"
        private const val ACTION_STOP = "cc.binmt.mt_forum.MCP_KEEP_ALIVE_STOP"
        private const val EXTRA_PORT = "port"

        /** 给 MethodChannel 查询用：服务是否还在跑。 */
        @Volatile
        var running: Boolean = false
            private set

        fun start(context: Context, port: Int) {
            val intent = Intent(context, McpKeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_PORT, port)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, McpKeepAliveService::class.java))
        }
    }

    private var port: Int = 8642

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        port = intent?.getIntExtra(EXTRA_PORT, port) ?: port
        // 必须在 onStartCommand 里立刻挂上前台通知，否则系统会按
        // 「startForegroundService 但没 startForeground」直接 ANR。
        promoteToForeground()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun promoteToForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("open_mcp", true)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mcp)
            .setContentTitle("MCP 服务运行中")
            .setContentText("端口 $port · 局域网 AI 客户端可连接")
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "MCP 服务", NotificationManager.IMPORTANCE_MIN).apply {
            description = "MCP 服务后台保活时显示的常驻通知"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }
}
