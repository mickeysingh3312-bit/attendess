package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import org.json.JSONArray

object NotificationHelper {
    private const val CHANNEL_ID = "site_attendance"

    fun showTransition(context: Context, transition: String, projectId: Int) {
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) != PackageManager.PERMISSION_GRANTED
        ) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Site attendance",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }

        val project = projectLabel(context, projectId)
        val entering = transition == "enter"
        val title = if (entering) "Site arrival detected" else "Site departure detected"
        val body = if (entering) {
            "Automatic check-in is being recorded for $project."
        } else {
            "Automatic checkout is being processed for $project. Your grace period still applies."
        }

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .build()

        manager.notify(projectId * 10 + if (entering) 1 else 2, notification)
    }

    private fun projectLabel(context: Context, projectId: Int): String {
        return try {
            val prefs = context.getSharedPreferences(GeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
            val raw = prefs.getString("projects_json", null) ?: return "project #$projectId"
            val projects = JSONArray(raw)
            for (index in 0 until projects.length()) {
                val project = projects.getJSONObject(index)
                if (project.optInt("id") != projectId) continue
                val code = project.optString("code").trim()
                val name = project.optString("name").trim()
                return when {
                    code.isNotEmpty() && name.isNotEmpty() -> "$code · $name"
                    name.isNotEmpty() -> name
                    code.isNotEmpty() -> code
                    else -> "project #$projectId"
                }
            }
            "project #$projectId"
        } catch (_: Exception) {
            "project #$projectId"
        }
    }
}
