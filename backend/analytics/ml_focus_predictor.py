import os
import joblib
import pandas as pd

from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split


class MLFocusPredictor:
    def __init__(self):
        backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.model_path = os.path.join(backend_dir, "models", "focus_model.pkl")
        self.model = None

        self.feature_columns = [
            "planned_total_minutes",
            "previous_focus_score",
            "previous_active_minutes",
            "previous_break_minutes",
            "previous_distraction_count",
            "camera_enabled_value",
        ]

        self.load_model()

    def load_model(self):
        if os.path.exists(self.model_path):
            try:
                self.model = joblib.load(self.model_path)
            except Exception:
                self.model = None

    def train(self, sessions):
        training_rows = self._build_training_rows(sessions)

        if len(training_rows) < 10:
            return {
                "success": False,
                "message": "Model eğitimi için en az 10 uygun oturum gerekiyor.",
                "sample_count": len(training_rows),
            }

        dataframe = pd.DataFrame(training_rows)

        x = dataframe[self.feature_columns]
        y = dataframe["target_focus_score"]

        if len(dataframe) >= 20:
            x_train, x_test, y_train, y_test = train_test_split(
                x,
                y,
                test_size=0.2,
                random_state=42,
            )
        else:
            x_train = x
            y_train = y
            x_test = x
            y_test = y

        model = RandomForestRegressor(
            n_estimators=120,
            random_state=42,
            min_samples_leaf=2,
        )

        model.fit(x_train, y_train)

        score = model.score(x_test, y_test)

        os.makedirs(
            os.path.dirname(self.model_path),
            exist_ok=True,
        )

        joblib.dump(model, self.model_path)

        self.model = model

        return {
            "success": True,
            "message": "Focus modeli yeniden eğitildi.",
            "sample_count": len(training_rows),
            "model_score": round(float(score), 3),
        }

    def generate_focus_plan(
        self,
        sessions,
        planned_total_minutes=90,
    ):
        camera_sessions = [
            session
            for session in sessions
            if session.get("camera_enabled", True) is True
        ]

        if len(camera_sessions) < 3:
            plan = self.default_plan(
                planned_total_minutes=planned_total_minutes,
            )
            plan["sample_count"] = len(sessions)

            if sessions:
                plan["data_quality"] = "limited"
                plan["reason"] = (
                    "Öneriler başlangıç seviyesinde. Geçmiş local oturumlar "
                    "ve hedef süre kullanılıyor; kamera açık daha fazla "
                    "oturumla plan kişiselleşir."
                )

            return plan

        recent_session = camera_sessions[-1]

        previous_focus_score = self._to_float(
            recent_session.get("focus_score", 70),
        )

        previous_active_minutes = self._to_float(
            recent_session.get("active_seconds", 0),
        ) / 60

        previous_break_minutes = self._to_float(
            recent_session.get("break_seconds", 0),
        ) / 60

        previous_distraction_count = self._to_float(
            recent_session.get("distraction_count", 0),
        )

        predicted_focus = self.predict_focus_score(
            planned_total_minutes=planned_total_minutes,
            previous_focus_score=previous_focus_score,
            previous_active_minutes=previous_active_minutes,
            previous_break_minutes=previous_break_minutes,
            previous_distraction_count=previous_distraction_count,
            camera_enabled=True,
        )

        average_drop_second = self.average_focus_drop_second(
            camera_sessions,
        )

        work_block_seconds = self.calculate_work_block(
            predicted_focus_score=predicted_focus,
            average_focus_drop_second=average_drop_second,
        )

        break_seconds = self.calculate_break_length(
            predicted_focus_score=predicted_focus,
            sessions=sessions,
        )

        planned_breaks = self.build_planned_breaks(
            planned_total_minutes=planned_total_minutes,
            work_block_seconds=work_block_seconds,
            break_seconds=break_seconds,
            predicted_focus_score=predicted_focus,
        )
        pomodoro = self.build_pomodoro_settings(
            planned_total_minutes=planned_total_minutes,
            work_block_seconds=work_block_seconds,
            break_seconds=break_seconds,
            predicted_focus_score=predicted_focus,
        )

        return {
            "recommended_work_block_seconds": round(work_block_seconds, 2),
            "recommended_break_seconds": round(break_seconds, 2),
            "work_minutes": pomodoro["work_minutes"],
            "short_break_minutes": pomodoro["short_break_minutes"],
            "long_break_minutes": pomodoro["long_break_minutes"],
            "long_break_every": pomodoro["long_break_every"],
            "cycles": pomodoro["cycles"],
            "estimated_total_minutes": pomodoro["estimated_total_minutes"],
            "first_break_minute": pomodoro["first_break_minute"],
            "first_long_break_minute": pomodoro["first_long_break_minute"],
            "recommended_total_minutes": planned_total_minutes,
            "predicted_focus_quality": round(predicted_focus, 2),
            "planned_breaks": planned_breaks,
            "data_quality": (
                "personalized"
                if len(camera_sessions) >= 10
                else "limited"
            ),
            "sample_count": len(camera_sessions),
            "reason": self.generate_reason(
                predicted_focus_score=predicted_focus,
                work_block_seconds=work_block_seconds,
                break_seconds=break_seconds,
            ),
        }

    def predict_focus_score(
        self,
        planned_total_minutes,
        previous_focus_score,
        previous_active_minutes,
        previous_break_minutes,
        previous_distraction_count,
        camera_enabled,
    ):
        if self.model is None:
            return self.heuristic_prediction(
                planned_total_minutes=planned_total_minutes,
                previous_focus_score=previous_focus_score,
                previous_distraction_count=previous_distraction_count,
            )

        row = pd.DataFrame([
            {
                "planned_total_minutes": planned_total_minutes,
                "previous_focus_score": previous_focus_score,
                "previous_active_minutes": previous_active_minutes,
                "previous_break_minutes": previous_break_minutes,
                "previous_distraction_count": previous_distraction_count,
                "camera_enabled_value": 1 if camera_enabled else 0,
            }
        ])

        prediction = self.model.predict(
            row[self.feature_columns],
        )[0]

        return max(
            0,
            min(
                100,
                float(prediction),
            ),
        )

    def heuristic_prediction(
        self,
        planned_total_minutes,
        previous_focus_score,
        previous_distraction_count,
    ):
        prediction = previous_focus_score

        if planned_total_minutes >= 180:
            prediction -= 10
        elif planned_total_minutes >= 120:
            prediction -= 5
        elif planned_total_minutes <= 45:
            prediction += 4

        prediction -= previous_distraction_count * 0.8

        return max(
            0,
            min(
                100,
                prediction,
            ),
        )

    def _build_training_rows(self, sessions):
        rows = []

        camera_sessions = [
            session
            for session in sessions
            if session.get("camera_enabled", True) is True
        ]

        for index in range(1, len(camera_sessions)):
            previous_session = camera_sessions[index - 1]
            current_session = camera_sessions[index]

            rows.append({
                "planned_total_minutes": self._to_float(
                    current_session.get("planned_total_minutes", 60),
                ),
                "previous_focus_score": self._to_float(
                    previous_session.get("focus_score", 0),
                ),
                "previous_active_minutes": self._to_float(
                    previous_session.get("active_seconds", 0),
                ) / 60,
                "previous_break_minutes": self._to_float(
                    previous_session.get("break_seconds", 0),
                ) / 60,
                "previous_distraction_count": self._to_float(
                    previous_session.get("distraction_count", 0),
                ),
                "camera_enabled_value": 1,
                "target_focus_score": self._to_float(
                    current_session.get("focus_score", 0),
                ),
            })

        return rows

    def average_focus_drop_second(self, sessions):
        values = []

        for session in sessions:
            value = session.get("first_focus_drop_second")

            if value is not None:
                values.append(
                    self._to_float(value),
                )

        if not values:
            return 45 * 60

        return sum(values) / len(values)

    def calculate_work_block(
        self,
        predicted_focus_score,
        average_focus_drop_second,
    ):
        if predicted_focus_score >= 85:
            result = average_focus_drop_second + 10 * 60
        elif predicted_focus_score >= 75:
            result = average_focus_drop_second + 5 * 60
        elif predicted_focus_score >= 60:
            result = average_focus_drop_second
        else:
            result = average_focus_drop_second - 10 * 60

        return max(
            20 * 60,
            min(
                90 * 60,
                result,
            ),
        )

    def calculate_break_length(
        self,
        predicted_focus_score,
        sessions,
    ):
        durations = []

        for session in sessions:
            for item in session.get("break_segments", []):
                duration = item.get("actual_duration", 0)
                durations.append(
                    self._to_float(duration),
                )

        average_break = 5 * 60

        if durations:
            average_break = sum(durations) / len(durations)

        if predicted_focus_score < 60:
            average_break += 3 * 60
        elif predicted_focus_score > 85:
            average_break -= 60

        return max(
            3 * 60,
            min(
                15 * 60,
                average_break,
            ),
        )

    def build_planned_breaks(
        self,
        planned_total_minutes,
        work_block_seconds,
        break_seconds,
        predicted_focus_score=72,
    ):
        planned_breaks = []
        settings = self.build_pomodoro_settings(
            planned_total_minutes=planned_total_minutes,
            work_block_seconds=work_block_seconds,
            break_seconds=break_seconds,
            predicted_focus_score=predicted_focus_score,
        )

        work_block_minutes = settings["work_minutes"]
        short_break_minutes = settings["short_break_minutes"]
        long_break_minutes = settings["long_break_minutes"]
        long_break_every = settings["long_break_every"]
        cycles = settings["cycles"]

        current_minute = work_block_minutes
        cycle = 1

        while cycle < cycles:
            is_long = long_break_every > 0 and cycle % long_break_every == 0
            break_minutes = long_break_minutes if is_long else short_break_minutes
            planned_breaks.append({
                "work_until_minute": current_minute,
                "break_duration_minutes": break_minutes,
                "break_type": "long" if is_long else "short",
                "cycle": cycle,
            })

            current_minute += work_block_minutes + break_minutes
            cycle += 1

        return planned_breaks

    def build_pomodoro_settings(
        self,
        planned_total_minutes,
        work_block_seconds,
        break_seconds,
        predicted_focus_score,
    ):
        work_minutes = max(
            20,
            min(90, round(work_block_seconds / 60)),
        )
        short_break_minutes = max(
            3,
            min(20, round(break_seconds / 60)),
        )

        if predicted_focus_score >= 82:
            long_break_every = 4
            long_break_minutes = max(12, short_break_minutes + 8)
        elif predicted_focus_score >= 65:
            long_break_every = 4
            long_break_minutes = max(15, short_break_minutes + 10)
        else:
            long_break_every = 3
            long_break_minutes = max(18, short_break_minutes + 12)

        long_break_minutes = min(35, long_break_minutes)
        cycles = max(1, round(planned_total_minutes / work_minutes))

        while cycles * work_minutes < planned_total_minutes:
            cycles += 1

        break_total = 0
        first_long_break_minute = None

        for cycle in range(1, cycles):
            is_long = long_break_every > 0 and cycle % long_break_every == 0
            break_total += long_break_minutes if is_long else short_break_minutes

            if is_long and first_long_break_minute is None:
                first_long_break_minute = cycle * work_minutes + break_total

        return {
            "work_minutes": work_minutes,
            "short_break_minutes": short_break_minutes,
            "long_break_minutes": long_break_minutes,
            "long_break_every": long_break_every,
            "cycles": cycles,
            "estimated_total_minutes": cycles * work_minutes + break_total,
            "first_break_minute": work_minutes,
            "first_long_break_minute": first_long_break_minute,
        }

    def generate_reason(
        self,
        predicted_focus_score,
        work_block_seconds,
        break_seconds,
    ):
        work_minutes = round(work_block_seconds / 60)
        break_minutes = round(break_seconds / 60)

        if predicted_focus_score >= 85:
            return (
                f"AI tahmini odak kaliten güçlü. "
                f"{work_minutes} dakikalık çalışma blokları ve "
                f"{break_minutes} dakikalık molalar öneriliyor."
            )

        if predicted_focus_score >= 70:
            return (
                f"AI dengeli bir odak ritmi bekliyor. "
                f"{work_minutes} dakika çalışma ve "
                f"{break_minutes} dakika mola uygun görünüyor."
            )

        if predicted_focus_score >= 55:
            return (
                f"AI odakta dalgalanma bekliyor. "
                f"Daha kontrollü {work_minutes} dakikalık bloklar öneriliyor."
            )

        return (
            f"AI erken dikkat düşüşü riski görüyor. "
            f"Kısa çalışma blokları ve daha düzenli molalar öneriliyor."
        )

    def default_plan(
        self,
        planned_total_minutes=90,
    ):
        if planned_total_minutes <= 45:
            work_block = 25 * 60
            break_block = 5 * 60
        elif planned_total_minutes <= 120:
            work_block = 45 * 60
            break_block = 8 * 60
        else:
            work_block = 55 * 60
            break_block = 10 * 60

        return {
            "recommended_work_block_seconds": work_block,
            "recommended_break_seconds": break_block,
            **self.build_pomodoro_settings(
                planned_total_minutes=planned_total_minutes,
                work_block_seconds=work_block,
                break_seconds=break_block,
                predicted_focus_score=72,
            ),
            "recommended_total_minutes": planned_total_minutes,
            "predicted_focus_quality": 72,
            "planned_breaks": self.build_planned_breaks(
                planned_total_minutes=planned_total_minutes,
                work_block_seconds=work_block,
                break_seconds=break_block,
                predicted_focus_score=72,
            ),
            "data_quality": "starter",
            "sample_count": 0,
            "reason": (
                "Henüz yeterli kişisel model verisi olmadığı için "
                "başlangıç çalışma planı kullanılıyor."
            ),
        }

    def _to_float(self, value):
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0
