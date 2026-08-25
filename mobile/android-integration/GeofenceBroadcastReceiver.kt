package au.com.fivestaraccess.five_star_attendance

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

class GeofenceBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError()) return
        val transition = when (event.geofenceTransition) { Geofence.GEOFENCE_TRANSITION_ENTER -> "enter"; Geofence.GEOFENCE_TRANSITION_EXIT -> "exit"; else -> return }
        val location = event.triggeringLocation
        val constraints = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        for (g in event.triggeringGeofences ?: emptyList()) {
            val projectId = g.requestId.removePrefix("project:").toIntOrNull() ?: continue
            NotificationHelper.showTransition(context, transition, projectId)
            val b = Data.Builder().putString("event_uuid", UUID.randomUUID().toString()).putInt("project_id", projectId).putString("transition", transition).putString("occurred_at", utcTimestamp()).putBoolean("has_location", location != null)
            if (location != null) b.putDouble("latitude", location.latitude).putDouble("longitude", location.longitude).putDouble("accuracy_m", location.accuracy.toDouble())
            WorkManager.getInstance(context).enqueue(OneTimeWorkRequestBuilder<GeofenceUploadWorker>().setConstraints(constraints).setInputData(b.build()).build())
        }
    }
    private fun utcTimestamp(): String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }.format(Date())
}
