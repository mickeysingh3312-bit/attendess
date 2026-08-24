package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.MethodChannel

class GeofenceManager(private val context: Context) {
    private val client = LocationServices.getGeofencingClient(context)
    private val pendingIntent: PendingIntent by lazy {
        val intent = Intent(context, GeofenceBroadcastReceiver::class.java)
        PendingIntent.getBroadcast(context, 9001, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }

    fun register(projects: List<Map<String, Any>>, baseUrl: String, token: String, deviceUuid: String, result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("LOCATION_PERMISSION", "Fine location permission is required", null)
            return
        }

        val prefs = context.getSharedPreferences("attendance_native", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("api_base_url", baseUrl)
            .putString("bearer_token", token)
            .putString("device_uuid", deviceUuid)
            .apply()

        val geofences = projects.take(95).mapNotNull { project ->
            val id = (project["id"] as? Number)?.toInt() ?: return@mapNotNull null
            val lat = (project["latitude"] as? Number)?.toDouble() ?: return@mapNotNull null
            val lng = (project["longitude"] as? Number)?.toDouble() ?: return@mapNotNull null
            val radius = (project["radius"] as? Number)?.toFloat() ?: 150f

            Geofence.Builder()
                .setRequestId("project:$id")
                .setCircularRegion(lat, lng, radius)
                .setExpirationDuration(Geofence.NEVER_EXPIRE)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT)
                .setLoiteringDelay(60000)
                .build()
        }

        client.removeGeofences(pendingIntent).addOnCompleteListener {
            if (geofences.isEmpty()) {
                result.success(true)
                return@addOnCompleteListener
            }

            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofences(geofences)
                .build()

            client.addGeofences(request, pendingIntent)
                .addOnSuccessListener { result.success(true) }
                .addOnFailureListener { e -> result.error("GEOFENCE_REGISTER", e.message, null) }
        }
    }

    fun clear(result: MethodChannel.Result) {
        client.removeGeofences(pendingIntent)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { result.error("GEOFENCE_CLEAR", it.message, null) }
    }
}
