package au.com.fivestaraccess.five_star_attendance

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class GeofenceUploadWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(GeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        val base = prefs.getString(GeofenceManager.KEY_API_BASE_URL, null) ?: return Result.failure()
        val token = prefs.getString(GeofenceManager.KEY_BEARER_TOKEN, null) ?: return Result.failure()
        val device = prefs.getString(GeofenceManager.KEY_DEVICE_UUID, null) ?: return Result.failure()
        return try {
            val payload = JSONObject().apply { put("event_uuid", inputData.getString("event_uuid")); put("project_id", inputData.getInt("project_id", 0)); put("device_uuid", device); put("transition", inputData.getString("transition")); put("occurred_at", inputData.getString("occurred_at")); if (inputData.getBoolean("has_location", false)) { put("latitude", inputData.getDouble("latitude", 0.0)); put("longitude", inputData.getDouble("longitude", 0.0)); put("accuracy_m", inputData.getDouble("accuracy_m", 0.0)) } }.toString()
            val c = URL("$base/geofence-events").openConnection() as HttpURLConnection
            c.requestMethod = "POST"; c.connectTimeout = 15000; c.readTimeout = 15000; c.doOutput = true; c.setRequestProperty("Authorization", "Bearer $token"); c.setRequestProperty("Content-Type", "application/json"); c.outputStream.use { it.write(payload.toByteArray()) }
            val code = c.responseCode; c.disconnect(); if (code in 200..299) Result.success() else if (code in 400..499) Result.failure() else Result.retry()
        } catch (_: Exception) { Result.retry() }
    }
}
