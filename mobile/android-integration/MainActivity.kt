package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val geofenceChannelName = "five_star_attendance/geofence"
    private val deviceChannelName = "five_star_attendance/device"
    private var permissionResult: MethodChannel.Result? = null
    private var permissionRequestCode: Int = 0

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, geofenceChannelName).setMethodCallHandler { call, result ->
            val manager = GeofenceManager(this)
            when (call.method) {
                "register" -> {
                    @Suppress("UNCHECKED_CAST") val projects = call.argument<List<Map<String, Any>>>("projects") ?: emptyList()
                    manager.register(projects, call.argument<String>("apiBaseUrl") ?: "", call.argument<String>("bearerToken") ?: "", call.argument<String>("deviceUuid") ?: "", result)
                }
                "clear" -> manager.clear(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(permissionStatus())
                "requestFineLocation" -> requestPermission(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), 4101, result)
                "requestNotifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) requestPermission(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4102, result) else result.success(true)
                "openAppSettings" -> { startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply { data = Uri.parse("package:$packageName") }); result.success(true) }
                "openLocationSettings" -> { startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPermission(permissions: Array<String>, requestCode: Int, result: MethodChannel.Result) {
        if (permissionResult != null) { result.error("PERMISSION_BUSY", "Another permission request is already active", null); return }
        permissionResult = result; permissionRequestCode = requestCode; ActivityCompat.requestPermissions(this, permissions, requestCode)
    }

    private fun permissionStatus(): Map<String, Boolean> {
        val fine = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED else fine
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED else true
        val lm = getSystemService(LOCATION_SERVICE) as android.location.LocationManager
        val services = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) lm.isLocationEnabled else Settings.Secure.getInt(contentResolver, Settings.Secure.LOCATION_MODE, 0) != Settings.Secure.LOCATION_MODE_OFF
        return mapOf("fineLocation" to fine, "backgroundLocation" to background, "notifications" to notifications, "locationServices" to services)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            permissionResult = null; permissionRequestCode = 0
        }
    }
}
