package au.com.fivestaraccess.five_star_attendance

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val geofenceChannelName = "five_star_attendance/geofence"
    private val deviceChannelName = "five_star_attendance/device"
    private val documentChannelName = "five_star_attendance/document"
    private var permissionResult: MethodChannel.Result? = null
    private var permissionRequestCode: Int = 0
    private var documentResult: MethodChannel.Result? = null
    private val documentRequestCode = 4201

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, geofenceChannelName).setMethodCallHandler { call, result ->
            val manager = GeofenceManager(this)
            when (call.method) {
                "register" -> {
                    @Suppress("UNCHECKED_CAST")
                    val projects = call.argument<List<Map<String, Any>>>("projects") ?: emptyList()
                    manager.register(
                        projects,
                        call.argument<String>("apiBaseUrl") ?: "",
                        call.argument<String>("bearerToken") ?: "",
                        call.argument<String>("deviceUuid") ?: "",
                        result,
                    )
                }
                "clear" -> manager.clear(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(permissionStatus())
                "requestFineLocation" -> requestPermission(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                    4101,
                    result,
                )
                "requestNotifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    requestPermission(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4102, result)
                } else {
                    result.success(true)
                }
                "openAppSettings" -> {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    })
                    result.success(true)
                }
                "openLocationSettings" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, documentChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> pickDocument(result)
                "openUrl" -> {
                    val url = call.argument<String>("url")?.trim().orEmpty()
                    if (url.isEmpty()) {
                        result.error("URL_EMPTY", "Attachment URL is empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL", e.message ?: "Unable to open attachment", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun pickDocument(result: MethodChannel.Result) {
        if (documentResult != null) {
            result.error("DOCUMENT_BUSY", "Another document picker is already open", null)
            return
        }

        documentResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf("image/jpeg", "image/png", "application/pdf"),
            )
        }

        try {
            startActivityForResult(Intent.createChooser(intent, "Choose attachment"), documentRequestCode)
        } catch (e: Exception) {
            documentResult = null
            result.error("DOCUMENT_PICK", e.message ?: "Unable to open document picker", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != documentRequestCode) return

        val pending = documentResult
        documentResult = null
        if (pending == null) return

        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            pending.success(null)
            return
        }

        try {
            var displayName = "attachment"
            var reportedSize = 0L
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (nameIndex >= 0) {
                        displayName = cursor.getString(nameIndex) ?: displayName
                    }
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        reportedSize = cursor.getLong(sizeIndex)
                    }
                }
            }

            val extension = displayName.substringAfterLast('.', "bin")
                .replace(Regex("[^A-Za-z0-9]"), "")
                .ifEmpty { "bin" }
            val directory = File(cacheDir, "site_staff_uploads").apply { mkdirs() }
            val target = File(
                directory,
                "${System.currentTimeMillis()}-${UUID.randomUUID()}.$extension",
            )

            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalStateException("Unable to read selected document")
            input.use { source ->
                target.outputStream().use { destination ->
                    source.copyTo(destination)
                }
            }

            pending.success(
                mapOf(
                    "path" to target.absolutePath,
                    "name" to displayName,
                    "size" to if (reportedSize > 0) reportedSize else target.length(),
                    "mimeType" to contentResolver.getType(uri),
                ),
            )
        } catch (e: Exception) {
            pending.error("DOCUMENT_READ", e.message ?: "Unable to read selected document", null)
        }
    }

    private fun requestPermission(
        permissions: Array<String>,
        requestCode: Int,
        result: MethodChannel.Result,
    ) {
        if (permissionResult != null) {
            result.error("PERMISSION_BUSY", "Another permission request is already active", null)
            return
        }
        permissionResult = result
        permissionRequestCode = requestCode
        ActivityCompat.requestPermissions(this, permissions, requestCode)
    }

    private fun permissionStatus(): Map<String, Boolean> {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            fine
        }
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val locationManager = getSystemService(LOCATION_SERVICE) as android.location.LocationManager
        val services = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            locationManager.isLocationEnabled
        } else {
            Settings.Secure.getInt(
                contentResolver,
                Settings.Secure.LOCATION_MODE,
                0,
            ) != Settings.Secure.LOCATION_MODE_OFF
        }
        return mapOf(
            "fineLocation" to fine,
            "backgroundLocation" to background,
            "notifications" to notifications,
            "locationServices" to services,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            permissionResult?.success(
                grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED },
            )
            permissionResult = null
            permissionRequestCode = 0
        }
    }
}
