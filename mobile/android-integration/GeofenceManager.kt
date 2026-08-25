package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class GeofenceManager(private val context: Context) {
    private val client = LocationServices.getGeofencingClient(context)
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val pendingIntent: PendingIntent by lazy {
        PendingIntent.getBroadcast(context, 9001, Intent(context, GeofenceBroadcastReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE)
    }
    fun register(projects: List<Map<String, Any>>, baseUrl: String, token: String, deviceUuid: String, result: MethodChannel.Result) {
        if (!hasRequiredLocationPermissions()) { result.error("LOCATION_PERMISSION", "Precise and background location permissions are required", null); return }
        persistConfiguration(projects, baseUrl, token, deviceUuid)
        registerInternal(projects, { result.success(true) }, { result.error("GEOFENCE_REGISTER", it.message, null) })
    }
    fun registerSaved() { if (!hasRequiredLocationPermissions()) return; val raw = prefs.getString(KEY_PROJECTS, null) ?: return; registerInternal(decodeProjects(raw), {}, {}) }
    fun clear(result: MethodChannel.Result) { prefs.edit().remove(KEY_PROJECTS).apply(); client.removeGeofences(pendingIntent).addOnSuccessListener { result.success(true) }.addOnFailureListener { result.error("GEOFENCE_CLEAR", it.message, null) } }
    private fun registerInternal(projects: List<Map<String, Any>>, ok: () -> Unit, fail: (Exception) -> Unit) {
        val geofences = projects.take(95).mapNotNull { p ->
            val id = (p["id"] as? Number)?.toInt() ?: return@mapNotNull null
            val lat = (p["latitude"] as? Number)?.toDouble() ?: return@mapNotNull null
            val lng = (p["longitude"] as? Number)?.toDouble() ?: return@mapNotNull null
            val radius = (p["radius"] as? Number)?.toFloat()?.coerceAtLeast(100f) ?: 150f
            Geofence.Builder().setRequestId("project:$id").setCircularRegion(lat, lng, radius).setExpirationDuration(Geofence.NEVER_EXPIRE).setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER or Geofence.GEOFENCE_TRANSITION_EXIT).build()
        }
        client.removeGeofences(pendingIntent).addOnCompleteListener {
            if (geofences.isEmpty()) { ok(); return@addOnCompleteListener }
            if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) { fail(SecurityException("Location permission was removed")); return@addOnCompleteListener }
            val request = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofences(geofences).build()
            client.addGeofences(request, pendingIntent).addOnSuccessListener { ok() }.addOnFailureListener { fail(it) }
        }
    }
    private fun hasRequiredLocationPermissions(): Boolean {
        val fine = ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine) return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED else true
    }
    private fun persistConfiguration(projects: List<Map<String, Any>>, baseUrl: String, token: String, deviceUuid: String) {
        val array = JSONArray(); projects.take(95).forEach { array.put(JSONObject(it)) }
        prefs.edit().putString(KEY_API_BASE_URL, baseUrl).putString(KEY_BEARER_TOKEN, token).putString(KEY_DEVICE_UUID, deviceUuid).putString(KEY_PROJECTS, array.toString()).apply()
    }
    private fun decodeProjects(raw: String): List<Map<String, Any>> = try { val a = JSONArray(raw); buildList { for (i in 0 until a.length()) { val o = a.getJSONObject(i); add(mapOf("id" to o.getInt("id"), "latitude" to o.getDouble("latitude"), "longitude" to o.getDouble("longitude"), "radius" to o.optDouble("radius", 150.0))) } } } catch (_: Exception) { emptyList() }
    companion object { const val PREFS_NAME = "attendance_native"; const val KEY_API_BASE_URL = "api_base_url"; const val KEY_BEARER_TOKEN = "bearer_token"; const val KEY_DEVICE_UUID = "device_uuid"; private const val KEY_PROJECTS = "projects_json" }
}
