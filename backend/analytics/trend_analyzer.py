class TrendAnalyzer:
    def analyze_sessions(
        self,
        sessions,
    ):
        if len(sessions) == 0:
            return {
                "session_count": 0,
                "average_focus_score": 0,
                "trend_message":
                    "Henüz yeterli oturum verisi yok.",
                "dashboard_summary": {},
                "insights": [],
            }

        total_focus_score = 0
        total_focus_seconds = 0
        total_active_seconds = 0
        total_break_seconds = 0
        total_distractions = 0

        focus_scores = []

        camera_sessions = 0

        for session in sessions:
            focus_score = self.to_float(
                session.get(
                    "focus_score",
                    0,
                )
            )

            active_seconds = self.to_float(
                session.get(
                    "active_seconds",
                    0,
                )
            )

            break_seconds = self.to_float(
                session.get(
                    "break_seconds",
                    0,
                )
            )

            focus_seconds = self.to_float(
                session.get(
                    "focus_seconds",
                    0,
                )
            )

            distraction_count = self.to_float(
                session.get(
                    "distraction_count",
                    0,
                )
            )

            total_focus_score += (
                focus_score
            )

            total_active_seconds += (
                active_seconds
            )

            total_break_seconds += (
                break_seconds
            )

            total_focus_seconds += (
                focus_seconds
            )

            total_distractions += (
                distraction_count
            )

            if session.get(
                "camera_enabled",
                True,
            ):
                focus_scores.append(
                    focus_score
                )

                camera_sessions += 1

        average_focus_score = 0

        if camera_sessions > 0:
            average_focus_score = (
                sum(focus_scores)
                / camera_sessions
            )

        focus_ratio = 0

        if total_active_seconds > 0:
            focus_ratio = (
                total_focus_seconds
                / total_active_seconds
            ) * 100

        dashboard_summary = {
            "total_active_seconds":
                round(
                    total_active_seconds,
                    2,
                ),

            "total_break_seconds":
                round(
                    total_break_seconds,
                    2,
                ),

            "total_focus_seconds":
                round(
                    total_focus_seconds,
                    2,
                ),

            "focus_ratio":
                round(
                    focus_ratio,
                    2,
                ),

            "total_distractions":
                int(
                    total_distractions
                ),

            "camera_sessions":
                camera_sessions,
        }

        trend_message = (
            self.generate_trend_message(
                average_focus_score=
                    average_focus_score,

                focus_ratio=
                    focus_ratio,

                total_distractions=
                    total_distractions,

                session_count=
                    len(sessions),
            )
        )

        insights = (
            self.generate_insights(
                sessions=sessions,
                average_focus_score=
                    average_focus_score,
                focus_ratio=
                    focus_ratio,
            )
        )

        return {
            "session_count":
                len(sessions),

            "average_focus_score":
                round(
                    average_focus_score,
                    2,
                ),

            "trend_message":
                trend_message,

            "dashboard_summary":
                dashboard_summary,

            "insights":
                insights,
        }

    def generate_trend_message(
        self,
        average_focus_score,
        focus_ratio,
        total_distractions,
        session_count,
    ):
        if session_count < 5:
            return (
                "AI sistemi kullanıcı alışkanlıklarını öğreniyor."
            )

        if average_focus_score >= 85:
            return (
                "Odak kalitesi oldukça güçlü ilerliyor."
            )

        if average_focus_score >= 72:
            return (
                "Çalışma ritmi genel olarak dengeli görünüyor."
            )

        if average_focus_score >= 60:
            return (
                "AI dikkat dalgalanmalarının arttığını gözlemliyor."
            )

        return (
            "AI erken dikkat kayıpları ve düşük odak ritmi tespit ediyor."
        )

    def generate_insights(
        self,
        sessions,
        average_focus_score,
        focus_ratio,
    ):
        insights = []

        if average_focus_score >= 85:
            insights.append({
                "title":
                    "Yüksek Odak Stabilitesi",
                "description":
                    "Son oturumlar boyunca güçlü bir dikkat dengesi korunuyor.",
            })

        elif average_focus_score >= 70:
            insights.append({
                "title":
                    "Dengeli Çalışma Ritmi",
                "description":
                    "AI sistemi çalışma temposunun genel olarak stabil ilerlediğini görüyor.",
            })

        else:
            insights.append({
                "title":
                    "Dikkat Dalgalanması",
                "description":
                    "Son oturumlarda dikkat düşüşleri daha sık tekrar ediyor.",
            })

        long_sessions = 0

        for session in sessions:
            active_seconds = (
                self.to_float(
                    session.get(
                        "active_seconds",
                        0,
                    )
                )
            )

            if active_seconds >= (
                90 * 60
            ):
                long_sessions += 1

        if long_sessions >= 5:
            insights.append({
                "title":
                    "Uzun Çalışma Blokları",
                "description":
                    "Kullanıcı uzun süreli çalışma oturumlarını sürdürebiliyor.",
            })

        low_focus_sessions = 0

        for session in sessions:
            focus_score = (
                self.to_float(
                    session.get(
                        "focus_score",
                        0,
                    )
                )
            )

            if (
                session.get(
                    "camera_enabled",
                    True,
                )
                and focus_score < 55
            ):
                low_focus_sessions += 1

        if low_focus_sessions >= 4:
            insights.append({
                "title":
                    "AI Mola Önerisi",
                "description":
                    "Sistem daha kısa çalışma blokları öneriyor.",
            })

        camera_disabled = 0

        for session in sessions:
            if not session.get(
                "camera_enabled",
                True,
            ):
                camera_disabled += 1

        if camera_disabled >= 5:
            insights.append({
                "title":
                    "Kamera Kapalı Oturumlar",
                "description":
                    "Bazı oturumlarda yalnızca süre tabanlı takip kullanılmış.",
            })

        return insights

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