<?php

use App\Http\Controllers\Api\DeviceHeartbeatController;
use App\Http\Controllers\Api\GeofenceEventController;
use App\Http\Controllers\Api\MobileAuthController;
use App\Http\Controllers\Api\MobileBootstrapController;
use App\Http\Controllers\Api\TodayAttendanceController;
use Illuminate\Support\Facades\Route;

Route::prefix('mobile')->group(function () {
    Route::post('/login', [MobileAuthController::class,'login'])->middleware('throttle:10,1');
    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/logout', [MobileAuthController::class,'logout']);
        Route::get('/bootstrap', MobileBootstrapController::class);
        Route::post('/geofence-events', [GeofenceEventController::class,'store'])->middleware('throttle:120,1');
        Route::post('/device-heartbeat', [DeviceHeartbeatController::class,'store']);
        Route::get('/attendance/today', TodayAttendanceController::class);
    });
});
