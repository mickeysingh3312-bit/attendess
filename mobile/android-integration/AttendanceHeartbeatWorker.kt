package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume

class AttendanceHeartbeatWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return Result.failure()
        }

        val prefs = applicationContext.getSharedPreferences(GeofenceManager.PREFS_NAME, Context.MODE_PRIVATE)
        val base = prefs.getString(GeofenceManager.KEY_API_BASE_URL, null) ?: return Result.failure()
        val token = prefs.getString(GeofenceManager.KEY_BEARER_TOKEN, null) ?: return Result.failure()
        val device = prefs.getString(GeofenceManager.KEY_DEVICE_UUID, null) ?: return Result.failure()
        val location = currentLocation() ?: return Result.retry()

        return try {
            val payload = JSONObject().apply {
                put("device_uuid", device)
                put("recorded_at", utcTimestamp(location.time))
                put("latitude", location.latitude)
                put("longitude", location.longitude)
                put("accuracy_m", location.accuracy.toDouble())
            }.toString()
            val connection = URL("$base/location-snapshot").openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.connectTimeout = 15000
            connection.readTimeout = 15000
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.outputStream.use { it.write(payload.toByteArray()) }
            val code = connection.responseCode
            connection.disconnect()
            when {
                code in 200..299 -> Result.success()
                code in 400..499 -> Result.failure()
                else -> Result.retry()
            }
        } catch (_: Exception) {
            Result.retry()
        }
    }

    private suspend fun currentLocation(): android.location.Location? = withTimeoutOrNull(20000) {
        suspendCancellableCoroutine { continuation ->
            val cancellation = CancellationTokenSource()
            continuation.invokeOnCancellation { cancellation.cancel() }
            LocationServices.getFusedLocationProviderClient(applicationContext)
                .getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, cancellation.token)
                .addOnSuccessListener { location ->
                    if (continuation.isActive) continuation.resume(location)
                }
                .addOnFailureListener {
                    if (continuation.isActive) continuation.resume(null)
                }
        }
    }

    private fun utcTimestamp(milliseconds: Long): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(milliseconds))

    companion object {
        private const val WORK_NAME = "attendance-location-heartbeat"

        fun schedule(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
            val request = PeriodicWorkRequestBuilder<AttendanceHeartbeatWorker>(15, TimeUnit.MINUTES)
                .setConstraints(constraints)
                .build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        fun cancel(context: Context) {
            WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        }
    }
}
