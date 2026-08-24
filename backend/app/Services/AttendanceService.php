<?php

namespace App\Services;

use App\Jobs\FinalizeCheckoutJob;
use App\Models\AttendanceSession;
use App\Models\GeofenceEvent;
use Illuminate\Support\Facades\DB;

class AttendanceService
{
    public function process(GeofenceEvent $event): ?AttendanceSession
    {
        return DB::transaction(function () use ($event) {
            if ($event->processed_at) {
                return AttendanceSession::where('check_in_event_id', $event->id)
                    ->orWhere('check_out_event_id', $event->id)->first();
            }

            $session = match ($event->transition) {
                'enter' => $this->handleEnter($event),
                'exit' => $this->handleExit($event),
                default => null,
            };

            $event->forceFill(['processed_at' => now()])->save();
            return $session;
        });
    }

    private function handleEnter(GeofenceEvent $event): AttendanceSession
    {
        $session = AttendanceSession::where('user_id',$event->user_id)
            ->where('project_id',$event->project_id)->where('status','open')->lockForUpdate()->first();

        if ($session) {
            if ($session->pending_exit_event_id) {
                $session->pending_exit_event_id = null;
                $session->save();
            }
            return $session;
        }

        return AttendanceSession::create([
            'user_id'=>$event->user_id,'project_id'=>$event->project_id,
            'check_in_event_id'=>$event->id,'check_in_at'=>$event->occurred_at,
            'status'=>'open','source'=>'auto',
        ]);
    }

    private function handleExit(GeofenceEvent $event): ?AttendanceSession
    {
        $session = AttendanceSession::where('user_id',$event->user_id)
            ->where('project_id',$event->project_id)->where('status','open')->lockForUpdate()->first();
        if (!$session) return null;

        $session->pending_exit_event_id = $event->id;
        $session->save();
        FinalizeCheckoutJob::dispatch($session->id, $event->id)
            ->delay(now()->addMinutes(config('attendance.exit_grace_minutes')));
        return $session;
    }

    public function finalizeExit(int $sessionId, int $eventId): void
    {
        DB::transaction(function () use ($sessionId, $eventId) {
            $session = AttendanceSession::lockForUpdate()->find($sessionId);
            if (!$session || $session->status !== 'open' || (int)$session->pending_exit_event_id !== $eventId) return;
            $event = GeofenceEvent::find($eventId);
            if (!$event) return;

            $session->check_out_event_id = $event->id;
            $session->check_out_at = $event->occurred_at;
            $session->duration_seconds = max(0, $session->check_in_at->diffInSeconds($event->occurred_at, false));
            $session->pending_exit_event_id = null;
            $session->status = 'closed';
            $session->save();
        });
    }
}
