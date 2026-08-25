package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

object NotificationHelper {
    private const val CHANNEL_ID = "site_attendance"
    fun showTransition(context: Context, transition: String, projectId: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Site attendance", NotificationManager.IMPORTANCE_DEFAULT))
        val entering = transition == "enter"
        val notification = NotificationCompat.Builder(context, CHANNEL_ID).setSmallIcon(android.R.drawable.ic_menu_mylocation).setContentTitle(if (entering) "Site arrival detected" else "Site departure detected").setContentText(if (entering) "Automatic check-in is being recorded for project #$projectId." else "Automatic check-out is being processed for project #$projectId.").setAutoCancel(true).build()
        manager.notify(projectId * 10 + if (entering) 1 else 2, notification)
    }
}
