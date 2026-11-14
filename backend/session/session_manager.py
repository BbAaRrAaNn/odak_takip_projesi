import time
from datetime import datetime


class SessionManager:
    def __init__(
        self,
        session_storage,
    ):
        self.session_storage = session_storage
        self.reset()

    def reset(self):
        self.session_active = False
        self.session_mode = "classic"
        self.camera_enabled = False
        self.planned_total_minutes = 60
        self.pomodoro_settings = None

        self.session_start_time = None
        self.last_update_time = None
        self.session_paused = False
        self.break_started_at = None
        self.current_break_seconds = 0
        self.current_break_start_second = None
        self.current_break_target_seconds = 0
        self.current_break_type = None
        self.current_break_reason = None
        self.current_break_suggested_minutes = None

        self.current_work_start_second = None

        self.total_break_seconds = 0
        self.total_away_seconds = 0
        self.focus_seconds = 0
        self.not_focus_seconds = 0
        self.active_seconds = 0

        self.distraction_count = 0
        self.last_focus_state = True
        self.last_face_found = True
        self.current_not_focus_start = None
        self.pending_no_face_started_at = None
        self.pending_no_face_seconds = 0
        self.away_threshold_seconds = 18
        self.away_active = False
        self.away_started_at = None
        self.current_away_start_second = None
        self.first_focus_drop_second = None

        self.focus_drop_events = []
        self.work_segments = []
        self.break_segments = []
        self.away_segments = []
        self.notification_actions = []
        self.minute_snapshots = []
        self.last_snapshot_minute = -1
        self.current_attention_score = None
        self.attention_score_total = 0
        self.attention_score_seconds = 0
        self.attention_sample_count = 0
        self.latest_focus_debug = {}

    def start_session(
        self,
        session_mode="classic",
        camera_enabled=True,
        planned_total_minutes=60,
        pomodoro_settings=None,
    ):
        self.reset()

        now = time.time()

        self.session_active = True
        self.session_mode = session_mode
        self.camera_enabled = camera_enabled
        self.planned_total_minutes = planned_total_minutes
        self.pomodoro_settings = pomodoro_settings

        self.session_start_time = now
        self.last_update_time = now
        self.current_work_start_second = 0

    def total_elapsed_seconds(
        self,
        include_current_break=False,
        include_current_away=False,
    ):
        total = (
            self.active_seconds
            + self.total_break_seconds
            + self.total_away_seconds
        )

        if (
            include_current_break
            and self.session_paused
            and self.break_started_at is not None
        ):
            total += time.time() - self.break_started_at

        if (
            include_current_away
            and self.away_active
            and self.away_started_at is not None
        ):
            total += time.time() - self.away_started_at

        return total

    def sync_time(
        self,
        is_focused=None,
        face_found=None,
        focus_score=None,
        focus_debug=None,
    ):
        if not self.session_active:
            return

        if focus_debug is not None:
            self.latest_focus_debug = focus_debug

        if self.session_paused:
            return

        current_time = time.time()

        if self.last_update_time is None:
            self.last_update_time = current_time
            return

        delta = current_time - self.last_update_time
        self.last_update_time = current_time

        if delta <= 0:
            return

        if is_focused is None:
            is_focused = self.last_focus_state

        if face_found is None:
            face_found = self.last_face_found

        if not self.camera_enabled:
            self.active_seconds += delta
            self.save_snapshot()
            return

        if focus_score is not None:
            self.update_attention_score(
                focus_score=focus_score,
                delta=0,
                include_sample=False,
            )

        if not face_found:
            self.last_face_found = False
            self.last_focus_state = False

            if self.pending_no_face_started_at is None:
                self.pending_no_face_started_at = current_time - delta

            self.pending_no_face_seconds = (
                current_time - self.pending_no_face_started_at
            )

            if (
                not self.away_active
                and self.pending_no_face_seconds >= self.away_threshold_seconds
            ):
                self.start_away()

            return

        if self.away_active:
            self.end_away(current_time)
            self.last_focus_state = bool(is_focused)
            self.last_face_found = True
            return

        if self.pending_no_face_started_at is not None:
            pending_duration = current_time - self.pending_no_face_started_at
            self.commit_short_no_face(pending_duration)
            self.pending_no_face_started_at = None
            self.pending_no_face_seconds = 0
            self.last_focus_state = bool(is_focused)
            self.last_face_found = True
            self.save_snapshot()
            return

        self.active_seconds += delta
        self.update_attention_score(
            focus_score=self.derived_focus_score(
                focus_score=focus_score,
                is_focused=is_focused,
            ),
            delta=delta,
            include_sample=True,
        )
        self.last_face_found = True

        if is_focused:
            self.focus_seconds += delta

            if self.current_not_focus_start is not None:
                not_focus_duration = (
                    current_time - self.current_not_focus_start
                )

                if not_focus_duration >= 10:
                    self.distraction_count += 1
                    timeline_second = self.total_elapsed_seconds()

                    event_score = self.event_focus_score(
                        fallback=self.calculate_focus_score(),
                    )
                    event_category = self.score_focus_category(event_score)

                    event = {
                        "time_second": round(self.active_seconds, 2),
                        "start_second": round(
                            max(0, timeline_second - not_focus_duration),
                            2,
                        ),
                        "end_second": round(timeline_second, 2),
                        "duration": round(not_focus_duration, 2),
                        "focus_score": round(event_score, 2),
                        "focus_category": event_category,
                    }

                    self.focus_drop_events.append(event)

                    if self.first_focus_drop_second is None:
                        self.first_focus_drop_second = round(
                            self.active_seconds,
                            2,
                        )

                self.current_not_focus_start = None

        else:
            self.not_focus_seconds += delta

            if self.current_not_focus_start is None:
                self.current_not_focus_start = current_time

        self.last_focus_state = bool(is_focused)
        self.save_snapshot()

    def update(
        self,
        is_focused=True,
        face_found=None,
        focus_score=None,
        focus_debug=None,
    ):
        self.sync_time(
            is_focused=bool(is_focused),
            face_found=face_found,
            focus_score=focus_score,
            focus_debug=focus_debug,
        )

    def derived_focus_score(self, focus_score=None, is_focused=True):
        if focus_score is not None:
            return focus_score

        if self.current_attention_score is not None:
            return self.current_attention_score

        return 82 if is_focused else 32

    def update_attention_score(
        self,
        focus_score,
        delta=0,
        include_sample=False,
    ):
        try:
            score = float(focus_score)
        except (TypeError, ValueError):
            return

        score = max(0, min(100, score))
        self.current_attention_score = score

        if include_sample and delta > 0:
            self.attention_score_total += score * delta
            self.attention_score_seconds += delta
            self.attention_sample_count += 1

    def commit_short_no_face(self, duration):
        if duration <= 0:
            return

        self.active_seconds += duration
        self.not_focus_seconds += duration

        if duration >= 10:
            self.distraction_count += 1
            timeline_second = self.total_elapsed_seconds()

            event_score = self.event_focus_score(
                fallback=self.calculate_focus_score(),
            )

            event = {
                "time_second": round(self.active_seconds, 2),
                "start_second": round(max(0, timeline_second - duration), 2),
                "end_second": round(timeline_second, 2),
                "duration": round(duration, 2),
                "focus_score": round(event_score, 2),
                "focus_category": "no_face",
                "reason": "brief_no_face",
            }

            self.focus_drop_events.append(event)

            if self.first_focus_drop_second is None:
                self.first_focus_drop_second = round(self.active_seconds, 2)

    def start_away(self):
        if self.away_active:
            return

        self.close_work_segment()

        self.away_active = True
        self.away_started_at = self.pending_no_face_started_at or time.time()
        self.current_away_start_second = self.total_elapsed_seconds()

        self.record_notification_action(
            "away_detected",
            reason="no_face",
        )

    def end_away(self, current_time=None):
        if not self.away_active:
            return

        if current_time is None:
            current_time = time.time()

        duration = current_time - self.away_started_at
        start_second = self.current_away_start_second

        if start_second is None:
            start_second = self.total_elapsed_seconds()

        self.total_away_seconds += max(0, duration)

        self.away_segments.append(
            {
                "start_second": round(start_second, 2),
                "end_second": round(start_second + duration, 2),
                "duration": round(duration, 2),
                "reason": "no_face",
            }
        )

        self.away_active = False
        self.away_started_at = None
        self.current_away_start_second = None
        self.pending_no_face_started_at = None
        self.pending_no_face_seconds = 0
        self.last_face_found = True
        self.current_not_focus_start = None
        self.current_work_start_second = self.total_elapsed_seconds()

        self.record_notification_action(
            "away_resumed",
            reason="face_returned",
        )

    def save_snapshot(self):
        minute = int(self.active_seconds // 60)

        if minute <= self.last_snapshot_minute:
            return

        self.last_snapshot_minute = minute

        focus_score = self.calculate_focus_score()
        focus_category = self.score_focus_category(focus_score)

        self.minute_snapshots.append(
            {
                "minute": minute,
                "focus_score": round(focus_score, 2),
                "focus_category": focus_category,
                "state": "work",
            }
        )

    def calculate_focus_score(
        self,
    ):
        if not self.camera_enabled:
            return 0

        if self.current_attention_score is not None and not self.session_paused:
            return max(
                0,
                min(100, self.current_attention_score),
            )

        if self.attention_score_seconds > 0:
            return max(
                0,
                min(100, self.attention_score_total / self.attention_score_seconds),
            )

        if self.active_seconds <= 0:
            return 0

        score = (self.focus_seconds / self.active_seconds) * 100
        score -= self.distraction_count * 1.5

        return max(
            0,
            min(100, score),
        )

    def final_focus_score(self):
        if not self.camera_enabled:
            return 0

        if self.attention_score_seconds > 0:
            return max(
                0,
                min(100, self.attention_score_total / self.attention_score_seconds),
            )

        return self.calculate_focus_score()

    def today_active_seconds(self):
        today = datetime.now().strftime("%d.%m.%Y")
        total = self.active_seconds

        try:
            sessions = self.session_storage.load_sessions()
        except Exception:
            return total

        for session in sessions:
            if not str(session.get("date", "")).startswith(today):
                continue

            try:
                total += float(session.get("active_seconds", 0) or 0)
            except (TypeError, ValueError):
                continue

        return total

    def close_work_segment(self):
        if self.current_work_start_second is None:
            return

        end_second = self.total_elapsed_seconds()
        duration = end_second - self.current_work_start_second

        if duration <= 0:
            return

        self.work_segments.append(
            {
                "start_second": round(self.current_work_start_second, 2),
                "end_second": round(end_second, 2),
                "duration": round(duration, 2),
                "focus_score": round(self.calculate_focus_score(), 2),
                "focus_category": self.score_focus_category(
                    self.calculate_focus_score(),
                ),
            }
        )

        self.current_work_start_second = None

    def start_break(
        self,
        reason="manual",
        selected_break_minutes=5,
        suggested_break_minutes=None,
        break_type="manual",
    ):
        if not self.session_active:
            return

        if self.session_paused:
            return

        if self.away_active:
            self.end_away()
        else:
            self.sync_time()
        self.close_work_segment()

        self.session_paused = True
        self.break_started_at = time.time()
        self.current_break_start_second = self.total_elapsed_seconds()
        self.current_break_target_seconds = max(
            1,
            selected_break_minutes,
        ) * 60
        self.current_break_type = break_type
        self.current_break_reason = reason
        self.current_break_suggested_minutes = suggested_break_minutes

        self.record_notification_action(
            "break_started",
            reason=reason,
            suggested_break_minutes=suggested_break_minutes,
            selected_break_minutes=selected_break_minutes,
        )

    def end_break(self):
        if not self.session_paused:
            return

        current_time = time.time()
        break_duration = current_time - self.break_started_at

        start_second = self.current_break_start_second

        if start_second is None:
            start_second = self.total_elapsed_seconds()

        self.total_break_seconds += break_duration

        self.break_segments.append(
            {
                "start_second": round(start_second, 2),
                "end_second": round(start_second + break_duration, 2),
                "duration": round(break_duration, 2),
                "actual_duration": round(break_duration, 2),
                "planned_duration": round(
                    self.current_break_target_seconds,
                    2,
                ),
                "break_type": self.current_break_type,
                "reason": self.current_break_reason,
            }
        )

        self.break_started_at = None
        self.current_break_start_second = None
        self.current_break_target_seconds = 0
        self.current_break_type = None
        self.current_break_reason = None
        self.current_break_suggested_minutes = None
        self.session_paused = False
        self.last_update_time = current_time
        self.current_work_start_second = self.total_elapsed_seconds()

        self.record_notification_action(
            "break_ended",
            reason="manual",
        )

    def record_notification_action(
        self,
        action,
        reason=None,
        suggested_break_minutes=None,
        selected_break_minutes=None,
        **extra,
    ):
        timestamp = time.time()

        item = {
            "action": action,
            "action_type": action,
            "timestamp": timestamp,
            "time": timestamp,
            "active_second": round(self.active_seconds, 2),
            "reason": reason,
            "camera_enabled": self.camera_enabled,
            "session_mode": self.session_mode,
            "focus_score": round(self.calculate_focus_score(), 2),
            "focus_state": self.current_focus_state(),
            "focus_category": self.focus_category(),
            "suggested_break_minutes": suggested_break_minutes,
            "selected_break_minutes": selected_break_minutes,
        }

        item.update(extra)

        self.notification_actions.append(item)

    def accept_break(
        self,
        reason="manual",
        suggested_break_minutes=None,
        selected_break_minutes=None,
    ):
        self.record_notification_action(
            "break_accepted",
            reason=reason,
            suggested_break_minutes=suggested_break_minutes,
            selected_break_minutes=selected_break_minutes,
        )

    def decline_break(
        self,
        reason="manual",
        suggested_break_minutes=None,
    ):
        self.record_notification_action(
            "break_declined",
            reason=reason,
            suggested_break_minutes=suggested_break_minutes,
        )

    def snooze_break(
        self,
        snooze_minutes=5,
        reason="manual",
        suggested_break_minutes=None,
    ):
        self.record_notification_action(
            "break_snoozed",
            reason=reason,
            suggested_break_minutes=suggested_break_minutes,
            selected_break_minutes=snooze_minutes,
            minutes=snooze_minutes,
        )

    def extend_break(
        self,
        extra_minutes=5,
        reason="manual",
    ):
        if not self.session_paused:
            return

        self.current_break_seconds += extra_minutes * 60
        self.current_break_target_seconds += extra_minutes * 60

        self.record_notification_action(
            "break_extended",
            reason=reason,
            minutes=extra_minutes,
            selected_break_minutes=round(
                self.current_break_target_seconds / 60,
                2,
            ),
        )

    def update_break_duration(
        self,
        selected_break_minutes=5,
        reason="manual",
    ):
        if not self.session_paused:
            return

        self.current_break_target_seconds = max(
            1,
            selected_break_minutes,
        ) * 60

        self.record_notification_action(
            "break_duration_changed",
            reason=reason,
            selected_break_minutes=selected_break_minutes,
        )

    def get_live_status(self):
        self.sync_time()

        current_focus_score = self.calculate_focus_score()

        live_break_seconds = self.total_break_seconds
        live_away_seconds = self.total_away_seconds

        if self.session_paused and self.break_started_at is not None:
            current_break_elapsed = time.time() - self.break_started_at
            live_break_seconds += current_break_elapsed
        else:
            current_break_elapsed = 0

        if self.away_active and self.away_started_at is not None:
            current_away_elapsed = time.time() - self.away_started_at
            live_away_seconds += current_away_elapsed
        else:
            current_away_elapsed = 0

        current_break_remaining = max(
            0,
            self.current_break_target_seconds - current_break_elapsed,
        )

        current_not_focus_seconds = 0

        if (
            self.current_not_focus_start is not None
            and not self.away_active
            and self.camera_enabled
        ):
            current_not_focus_seconds = time.time() - self.current_not_focus_start

        return {
            "session_active": self.session_active,
            "session_mode": self.session_mode,
            "camera_enabled": self.camera_enabled,
            "planned_total_minutes": self.planned_total_minutes,
            "pomodoro_settings": self.pomodoro_settings,
            "total_seconds": round(
                self.active_seconds + live_break_seconds + live_away_seconds,
                2,
            ),
            "active_seconds": round(self.active_seconds, 2),
            "today_active_seconds": round(self.today_active_seconds(), 2),
            "focus_seconds": round(self.focus_seconds, 2),
            "not_focus_seconds": round(self.not_focus_seconds, 2),
            "break_seconds": round(live_break_seconds, 2),
            "away_seconds": round(live_away_seconds, 2),
            "focus_score": round(current_focus_score, 2),
            "focus_state": self.current_focus_state(),
            "focus_category": self.focus_category(current_focus_score),
            "distraction_count": self.distraction_count,
            "session_paused": self.session_paused,
            "away_active": self.away_active,
            "current_away_seconds": round(current_away_elapsed, 2),
            "no_face_seconds": round(self.pending_no_face_seconds, 2),
            "away_threshold_seconds": self.away_threshold_seconds,
            "current_not_focus_seconds": round(current_not_focus_seconds, 2),
            "current_break_seconds": round(current_break_elapsed, 2),
            "current_break_remaining_seconds": round(
                current_break_remaining,
                2,
            ),
            "current_break_target_seconds": round(
                self.current_break_target_seconds,
                2,
            ),
            "current_break_started_at": (
                datetime.fromtimestamp(self.break_started_at).strftime(
                    "%H:%M"
                )
                if self.break_started_at is not None
                else None
            ),
            "current_break_type": self.current_break_type,
            "current_break_reason": self.current_break_reason,
            "first_focus_drop_second": self.first_focus_drop_second,
            "focus_drop_events": self.focus_drop_events,
            "notification_actions": self.notification_actions,
            "minute_snapshots": self.minute_snapshots,
            "work_segments": self.work_segments,
            "break_segments": self.break_segments,
            "away_segments": self.away_segments,
        }

    def end_session(self):
        if not self.session_active:
            return {}

        if self.away_active:
            self.end_away()
        elif self.pending_no_face_started_at is not None:
            pending_duration = time.time() - self.pending_no_face_started_at
            self.commit_short_no_face(pending_duration)
            self.pending_no_face_started_at = None
            self.pending_no_face_seconds = 0

        if self.session_paused:
            self.end_break()
        else:
            self.sync_time()

        self.close_work_segment()

        focus_score = self.final_focus_score()

        session_data = {
            "date": datetime.now().strftime("%d.%m.%Y %H:%M"),
            "session_mode": self.session_mode,
            "camera_enabled": self.camera_enabled,
            "planned_total_minutes": self.planned_total_minutes,
            "total_seconds": round(
                self.active_seconds
                + self.total_break_seconds
                + self.total_away_seconds,
                2,
            ),
            "active_seconds": round(self.active_seconds, 2),
            "focus_seconds": round(self.focus_seconds, 2),
            "not_focus_seconds": round(self.not_focus_seconds, 2),
            "break_seconds": round(self.total_break_seconds, 2),
            "away_seconds": round(self.total_away_seconds, 2),
            "focus_score": round(focus_score, 2),
            "focus_state": self.current_focus_state(),
            "focus_category": self.focus_category(focus_score),
            "distraction_count": self.distraction_count,
            "minute_snapshots": self.minute_snapshots,
            "work_segments": self.work_segments,
            "break_segments": self.break_segments,
            "away_segments": self.away_segments,
            "focus_drop_events": self.focus_drop_events,
            "notification_actions": self.notification_actions,
            "first_focus_drop_second": self.first_focus_drop_second,
            "timeline_segments": self.build_timeline_segments(),
        }

        if self.pomodoro_settings is not None:
            session_data["pomodoro_settings"] = self.pomodoro_settings

        self.session_storage.save_session(session_data)
        self.reset()

        return session_data

    def current_focus_state(self):
        return self.focus_category()

    def focus_category(self, score=None):
        if self.away_active:
            return "away"

        if self.session_paused:
            return "break"

        if not self.camera_enabled:
            return "camera_off"

        if not self.last_face_found or self.pending_no_face_started_at is not None:
            return "no_face"

        if score is None:
            score = self.calculate_focus_score()

        return self.score_focus_category(score)

    def score_focus_category(self, score):
        if not self.camera_enabled:
            return "camera_off"

        if score >= 85:
            return "excellent"

        if score >= 70:
            return "balanced"

        if score >= 50:
            return "fluctuating"

        if score >= 30:
            return "drop"

        return "severe_drop"

    def event_focus_score(self, fallback=40):
        if not self.camera_enabled:
            return 0

        try:
            score = float(fallback)
        except (TypeError, ValueError):
            score = 40

        if score < 30:
            return min(score, 25)

        return min(score, 40)

    def number(self, value, default=0):
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    def focus_drop_ranges_for_segment(self, start_second, end_second):
        ranges = []

        for event in self.focus_drop_events:
            duration = self.number(event.get("duration"), 0)
            event_end = self.number(
                event.get("end_second", event.get("time_second", 0)),
                0,
            )

            if "start_second" in event:
                event_start = self.number(event.get("start_second"), 0)
            else:
                event_start = max(0, event_end - duration)

            overlap_start = max(start_second, event_start)
            overlap_end = min(end_second, event_end)

            if overlap_end > overlap_start:
                score = self.number(event.get("focus_score"), 40)
                category = event.get("focus_category")

                if not category:
                    category = self.score_focus_category(score)

                ranges.append(
                    {
                        "start": overlap_start,
                        "end": overlap_end,
                        "score": score,
                        "category": category,
                    }
                )

        return sorted(ranges, key=lambda item: item["start"])

    def build_work_timeline_segments(self, item, focus_score):
        start_second = self.number(item.get("start_second"), 0)
        duration = self.number(item.get("duration"), 0)
        end_second = self.number(
            item.get("end_second"),
            start_second + duration,
        )

        if end_second <= start_second:
            end_second = start_second + duration

        if end_second <= start_second:
            return []

        if not self.camera_enabled:
            return [
                {
                    "type": "work",
                    "start_second": round(start_second, 2),
                    "end_second": round(end_second, 2),
                    "duration": round(end_second - start_second, 2),
                    "focus_score": 0,
                    "focus_state": "camera_off",
                    "focus_category": "camera_off",
                }
            ]

        drops = self.focus_drop_ranges_for_segment(start_second, end_second)
        category = self.score_focus_category(focus_score)

        if not drops:
            return [
                {
                    "type": "work",
                    "start_second": round(start_second, 2),
                    "end_second": round(end_second, 2),
                    "duration": round(end_second - start_second, 2),
                    "focus_score": focus_score,
                    "focus_state": category,
                    "focus_category": category,
                }
            ]

        segments = []
        cursor = start_second

        for drop in drops:
            drop_start = drop["start"]
            drop_end = drop["end"]

            if drop_start > cursor:
                segments.append(
                    {
                        "type": "work",
                        "start_second": round(cursor, 2),
                        "end_second": round(drop_start, 2),
                        "duration": round(drop_start - cursor, 2),
                        "focus_score": focus_score,
                        "focus_state": category,
                        "focus_category": category,
                    }
                )

            drop_score = self.number(drop.get("score"), 40)
            drop_category = drop.get("category") or self.score_focus_category(
                drop_score
            )

            segments.append(
                {
                    "type": "focus_drop",
                    "start_second": round(drop_start, 2),
                    "end_second": round(drop_end, 2),
                    "duration": round(drop_end - drop_start, 2),
                    "focus_score": drop_score,
                    "focus_state": drop_category,
                    "focus_category": drop_category,
                }
            )

            cursor = max(cursor, drop_end)

        if cursor < end_second:
            segments.append(
                {
                    "type": "work",
                    "start_second": round(cursor, 2),
                    "end_second": round(end_second, 2),
                    "duration": round(end_second - cursor, 2),
                    "focus_score": focus_score,
                    "focus_state": category,
                    "focus_category": category,
                }
            )

        return [item for item in segments if item.get("duration", 0) > 0]

    def build_timeline_segments(self):
        segments = []
        focus_score = round(self.calculate_focus_score(), 2)

        for item in self.work_segments:
            segments.extend(
                self.build_work_timeline_segments(
                    item,
                    self.number(item.get("focus_score"), focus_score),
                )
            )

        for item in self.break_segments:
            segments.append(
                {
                    "type": "break",
                    "start_second": item.get("start_second", 0),
                    "end_second": item.get("end_second", 0),
                    "duration": item.get("actual_duration", 0),
                    "break_type": item.get("break_type"),
                    "reason": item.get("reason"),
                    "focus_state": "break",
                    "focus_category": "break",
                }
            )

        for item in self.away_segments:
            segments.append(
                {
                    "type": "away",
                    "start_second": item.get("start_second", 0),
                    "end_second": item.get("end_second", 0),
                    "duration": item.get("duration", 0),
                    "reason": item.get("reason"),
                    "focus_state": "away",
                    "focus_category": "away",
                }
            )

        return sorted(
            segments,
            key=lambda item: item.get("start_second", 0),
        )
