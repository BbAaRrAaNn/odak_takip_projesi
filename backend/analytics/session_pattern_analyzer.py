class SessionPatternAnalyzer:
    def analyze(
        self,
        sessions,
    ):
        if len(sessions) == 0:
            return {
                "best_mode": None,
                "best_focus_hour": None,
                "camera_usage_ratio": 0,
                "average_session_minutes": 0,
                "average_break_minutes": 0,
                "most_productive_pattern": None,
            }

        mode_scores = {}

        hour_scores = {}

        total_minutes = 0

        total_break_minutes = 0

        camera_enabled_count = 0

        productive_sessions = []

        for session in sessions:
            focus_score = self.to_float(
                session.get(
                    "focus_score",
                    0,
                )
            )

            active_minutes = (
                self.to_float(
                    session.get(
                        "active_seconds",
                        0,
                    )
                ) / 60
            )

            break_minutes = (
                self.to_float(
                    session.get(
                        "break_seconds",
                        0,
                    )
                ) / 60
            )

            total_minutes += (
                active_minutes
            )

            total_break_minutes += (
                break_minutes
            )

            if session.get(
                "camera_enabled",
                True,
            ):
                camera_enabled_count += 1

            mode = session.get(
                "session_mode",
                "classic",
            )

            if mode not in mode_scores:
                mode_scores[mode] = []

            mode_scores[mode].append(
                focus_score
            )

            date_text = session.get(
                "date",
                "",
            )

            hour = self.extract_hour(
                date_text
            )

            if hour is not None:
                if hour not in hour_scores:
                    hour_scores[hour] = []

                hour_scores[hour].append(
                    focus_score
                )

            if focus_score >= 80:
                productive_sessions.append({
                    "mode": mode,
                    "active_minutes":
                        round(
                            active_minutes,
                            2,
                        ),
                    "break_minutes":
                        round(
                            break_minutes,
                            2,
                        ),
                    "focus_score":
                        round(
                            focus_score,
                            2,
                        ),
                })

        best_mode = None

        best_mode_score = -1

        for mode, values in mode_scores.items():
            average = (
                sum(values) /
                len(values)
            )

            if average > best_mode_score:
                best_mode_score = average
                best_mode = mode

        best_focus_hour = None

        best_hour_score = -1

        for hour, values in hour_scores.items():
            average = (
                sum(values) /
                len(values)
            )

            if average > best_hour_score:
                best_hour_score = average
                best_focus_hour = hour

        camera_usage_ratio = (
            camera_enabled_count /
            len(sessions)
        ) * 100

        most_productive_pattern = None

        if productive_sessions:
            most_productive_pattern = max(
                productive_sessions,
                key=lambda item:
                    item[
                        "focus_score"
                    ],
            )

        return {
            "best_mode":
                best_mode,

            "best_focus_hour":
                best_focus_hour,

            "camera_usage_ratio":
                round(
                    camera_usage_ratio,
                    2,
                ),

            "average_session_minutes":
                round(
                    total_minutes /
                    len(sessions),
                    2,
                ),

            "average_break_minutes":
                round(
                    total_break_minutes /
                    len(sessions),
                    2,
                ),

            "most_productive_pattern":
                most_productive_pattern,
        }

    def extract_hour(
        self,
        text,
    ):
        try:
            time_part = (
                text.split(" ")[1]
            )

            hour = int(
                time_part.split(":")[0]
            )

            return hour

        except Exception:
            return None

    def to_float(
        self,
        value,
    ):
        try:
            return float(value)

        except (
            TypeError,
            ValueError,
        ):
            return 0