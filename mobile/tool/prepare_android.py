#!/usr/bin/env python3
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
PACKAGE_DIR = ANDROID / "app/src/main/kotlin/au/com/fivestaraccess/five_star_attendance"
INTEGRATION = ROOT / "android-integration"
if not ANDROID.exists(): raise SystemExit("android/ is missing")
PACKAGE_DIR.mkdir(parents=True, exist_ok=True)
for source in INTEGRATION.glob("*.kt"): shutil.copy2(source, PACKAGE_DIR / source.name)
manifest = ANDROID / "app/src/main/AndroidManifest.xml"
text = manifest.read_text()
permissions = ['    <uses-permission android:name="android.permission.INTERNET" />','    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />','    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />','    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />','    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />']
for permission in permissions:
    if permission not in text: text = text.replace(">", ">\n" + permission, 1)
text = text.replace('android:label="five_star_attendance"', 'android:label="Five Star Attendance"')
receivers = '''\n        <receiver android:name=".GeofenceBroadcastReceiver" android:exported="false" />\n        <receiver android:name=".BootReceiver" android:enabled="true" android:exported="false">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED" />\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n            </intent-filter>\n        </receiver>\n'''
if 'android:name=".GeofenceBroadcastReceiver"' not in text: text = text.replace("    </application>", receivers + "    </application>")
manifest.write_text(text)
kts = ANDROID / "app/build.gradle.kts"
if kts.exists():
    gradle = kts.read_text()
    if 'play-services-location' not in gradle: gradle += '''\n\ndependencies {\n    implementation("com.google.android.gms:play-services-location:21.3.0")\n    implementation("androidx.work:work-runtime-ktx:2.10.1")\n}\n'''
    kts.write_text(gradle)
else: raise SystemExit("Could not find app/build.gradle.kts")
print("Android scaffold prepared")
