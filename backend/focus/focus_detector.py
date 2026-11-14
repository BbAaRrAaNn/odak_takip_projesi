import math
import time

import mediapipe as mp
from mediapipe.tasks.python import vision
from mediapipe.tasks.python.core.base_options import BaseOptions


class FocusDetector:
    def __init__(self):
        self.model_path = "models/face_detection_short_range.tflite"
        self.landmarker_model_path = "models/face_landmarker.task"

        # FaceLandmarker already performs face detection. Avoid running the
        # separate detector every frame; it made the camera loop heavier.
        self.detector = None
        self.landmarker = self._create_face_landmarker()

        self.eye_history = []
        self.focus_history = []
        self.face_seen_history = []
        self.metric_history = []

        self.calibration_frames = []
        self.calibrated = False
        self.calibration_frame_limit = 30

        self.baseline = self._empty_baseline()

        self.debug_info = {}
        self.smoothed_focus_score = None
        self.no_face_started_at = None
        self.low_attention_started_at = None
        self.last_smoothing_alpha = 1.0

    def _empty_baseline(self):
        return {
            "nose_offset_ratio": None,
            "nose_signed_ratio": None,
            "vertical_ratio": None,
            "face_width": None,
            "face_height_width_ratio": None,
            "mouth_eye_ratio": None,
            "roll_angle": None,
            "eye_open_ratio": None,
            "gaze_x": None,
            "gaze_y": None,
        }

    def _create_face_detector(self):
        base_options = BaseOptions(
            model_asset_path=self.model_path,
            delegate=BaseOptions.Delegate.CPU,
        )

        options = vision.FaceDetectorOptions(
            base_options=base_options,
            min_detection_confidence=0.55,
        )

        return vision.FaceDetector.create_from_options(options)

    def _create_face_landmarker(self):
        base_options = BaseOptions(
            model_asset_path=self.landmarker_model_path,
            delegate=BaseOptions.Delegate.CPU,
        )

        options = vision.FaceLandmarkerOptions(
            base_options=base_options,
            num_faces=1,
            min_face_detection_confidence=0.55,
            min_face_presence_confidence=0.55,
            min_tracking_confidence=0.55,
        )

        return vision.FaceLandmarker.create_from_options(options)

    def analyze_frame(self, rgb_frame, frame):
        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=rgb_frame,
        )

        landmarker_result = self.landmarker.detect(mp_image)

        height, width, _ = frame.shape

        raw_focus = False
        face_found = False
        metrics = None

        if landmarker_result.face_landmarks:
            face_found = True
            self.no_face_started_at = None
            face_landmark = landmarker_result.face_landmarks[0]

            metrics = self._extract_face_metrics(
                face_landmark,
                width,
                height,
            )

            if metrics is not None:
                self._auto_calibrate(metrics)
                raw_focus = self._analyze_focus(metrics)

        if not face_found or metrics is None:
            raw_focus = self._handle_no_face()

        self._update_face_seen_history(face_found)

        stable_focus = self._smooth_focus(raw_focus)

        self.debug_info["raw_focus"] = raw_focus
        self.debug_info["stable_focus"] = stable_focus
        self.debug_info["face_found"] = face_found
        self.debug_info["calibrated"] = self.calibrated
        self.debug_info["calibration_frames"] = len(self.calibration_frames)

        return stable_focus, None

    def _extract_face_metrics(self, face_landmark, width, height):
        if len(face_landmark) <= 386:
            return None

        nose = face_landmark[1]

        left_eye_outer = face_landmark[33]
        right_eye_outer = face_landmark[263]

        left_mouth = face_landmark[61]
        right_mouth = face_landmark[291]

        chin = face_landmark[152]
        forehead = face_landmark[10]

        nose_x = nose.x * width
        nose_y = nose.y * height

        left_eye_x = left_eye_outer.x * width
        right_eye_x = right_eye_outer.x * width

        left_eye_y = left_eye_outer.y * height
        right_eye_y = right_eye_outer.y * height

        eye_center_x = (left_eye_x + right_eye_x) / 2
        eye_center_y = (left_eye_y + right_eye_y) / 2

        face_width = abs(right_eye_x - left_eye_x)

        if face_width <= 5:
            return None

        nose_signed_ratio = (nose_x - eye_center_x) / face_width
        nose_offset_ratio = abs(nose_signed_ratio)
        vertical_ratio = (nose_y - eye_center_y) / face_width

        mouth_width = abs((right_mouth.x - left_mouth.x) * width)
        mouth_eye_ratio = mouth_width / face_width

        face_height = abs((chin.y - forehead.y) * height)
        face_height_width_ratio = face_height / face_width

        roll_angle = math.degrees(
            math.atan2(
                right_eye_y - left_eye_y,
                right_eye_x - left_eye_x,
            )
        )

        eye_metrics = self._extract_eye_metrics(face_landmark, width, height)

        xs = [landmark.x * width for landmark in face_landmark[:468]]
        ys = [landmark.y * height for landmark in face_landmark[:468]]

        face_box = {
            "x": max(0, min(xs)),
            "y": max(0, min(ys)),
            "w": max(0, max(xs) - min(xs)),
            "h": max(0, max(ys) - min(ys)),
        }

        return {
            "nose_offset_ratio": nose_offset_ratio,
            "nose_signed_ratio": nose_signed_ratio,
            "vertical_ratio": vertical_ratio,
            "face_width": face_width,
            "mouth_eye_ratio": mouth_eye_ratio,
            "face_height_width_ratio": face_height_width_ratio,
            "roll_angle": roll_angle,
            "eye_open_ratio": eye_metrics["eye_open_ratio"],
            "left_eye_ratio": eye_metrics["left_eye_ratio"],
            "right_eye_ratio": eye_metrics["right_eye_ratio"],
            "gaze_x": eye_metrics["gaze_x"],
            "gaze_y": eye_metrics["gaze_y"],
            "gaze_available": eye_metrics["gaze_available"],
            "face_box": face_box,
            "landmark_count": len(face_landmark),
        }

    def _extract_eye_metrics(self, face_landmark, width, height):
        left_width = self._distance(face_landmark[33], face_landmark[133], width, height)
        right_width = self._distance(face_landmark[362], face_landmark[263], width, height)

        left_height = self._average_eye_height(
            face_landmark,
            [(159, 145), (160, 144), (158, 153)],
            height,
        )
        right_height = self._average_eye_height(
            face_landmark,
            [(386, 374), (385, 380), (387, 373)],
            height,
        )

        left_eye_ratio = left_height / left_width if left_width > 0 else 0.22
        right_eye_ratio = right_height / right_width if right_width > 0 else 0.22
        eye_open_ratio = (left_eye_ratio + right_eye_ratio) / 2

        gaze = self._extract_gaze(face_landmark, width, height)

        return {
            "eye_open_ratio": eye_open_ratio,
            "left_eye_ratio": left_eye_ratio,
            "right_eye_ratio": right_eye_ratio,
            "gaze_x": gaze["gaze_x"],
            "gaze_y": gaze["gaze_y"],
            "gaze_available": gaze["gaze_available"],
        }

    def _extract_gaze(self, face_landmark, width, height):
        if len(face_landmark) < 478:
            return {
                "gaze_x": 0.0,
                "gaze_y": 0.0,
                "gaze_available": False,
            }

        left_iris = self._average_point(face_landmark, [468, 469, 470, 471, 472], width, height)
        right_iris = self._average_point(face_landmark, [473, 474, 475, 476, 477], width, height)

        left_gaze = self._eye_gaze_offset(
            iris_point=left_iris,
            outer=face_landmark[33],
            inner=face_landmark[133],
            upper_indices=[159, 160, 158],
            lower_indices=[145, 144, 153],
            face_landmark=face_landmark,
            width=width,
            height=height,
        )
        right_gaze = self._eye_gaze_offset(
            iris_point=right_iris,
            outer=face_landmark[362],
            inner=face_landmark[263],
            upper_indices=[386, 385, 387],
            lower_indices=[374, 380, 373],
            face_landmark=face_landmark,
            width=width,
            height=height,
        )

        return {
            "gaze_x": (left_gaze["x"] + right_gaze["x"]) / 2,
            "gaze_y": (left_gaze["y"] + right_gaze["y"]) / 2,
            "gaze_available": True,
        }

    def _eye_gaze_offset(
        self,
        iris_point,
        outer,
        inner,
        upper_indices,
        lower_indices,
        face_landmark,
        width,
        height,
    ):
        outer_x = outer.x * width
        inner_x = inner.x * width
        min_x = min(outer_x, inner_x)
        max_x = max(outer_x, inner_x)
        eye_width = max(1, max_x - min_x)

        upper_y = self._average_y(face_landmark, upper_indices, height)
        lower_y = self._average_y(face_landmark, lower_indices, height)
        min_y = min(upper_y, lower_y)
        max_y = max(upper_y, lower_y)
        eye_height = max(1, max_y - min_y)

        return {
            "x": ((iris_point["x"] - min_x) / eye_width) - 0.5,
            "y": ((iris_point["y"] - min_y) / eye_height) - 0.5,
        }

    def _average_point(self, face_landmark, indices, width, height):
        points = [face_landmark[index] for index in indices]

        return {
            "x": sum(point.x * width for point in points) / len(points),
            "y": sum(point.y * height for point in points) / len(points),
        }

    def _average_y(self, face_landmark, indices, height):
        return sum(face_landmark[index].y * height for index in indices) / len(indices)

    def _average_eye_height(self, face_landmark, pairs, height):
        heights = [
            abs((face_landmark[top].y - face_landmark[bottom].y) * height)
            for top, bottom in pairs
        ]

        return sum(heights) / len(heights)

    def _distance(self, first, second, width, height):
        dx = (first.x - second.x) * width
        dy = (first.y - second.y) * height

        return math.sqrt(dx * dx + dy * dy)

    def _auto_calibrate(self, metrics):
        if self.calibrated:
            return

        if not self._usable_for_calibration(metrics):
            return

        self.calibration_frames.append(metrics)

        if len(self.calibration_frames) < self.calibration_frame_limit:
            return

        for key in self.baseline.keys():
            self.baseline[key] = self._average_metric(key)

        self.calibrated = True

    def _usable_for_calibration(self, metrics):
        if metrics.get("eye_open_ratio", 0) < 0.16:
            return False

        if metrics.get("face_width", 0) < 28:
            return False

        if abs(metrics.get("nose_signed_ratio", 0)) > 0.38:
            return False

        if metrics.get("gaze_available"):
            if abs(metrics.get("gaze_x", 0)) > 0.34:
                return False

            if abs(metrics.get("gaze_y", 0)) > 0.42:
                return False

        return True

    def _average_metric(self, key):
        values = [
            frame[key]
            for frame in self.calibration_frames
            if key in frame and isinstance(frame[key], (int, float))
        ]

        if len(values) == 0:
            return 0

        return sum(values) / len(values)

    def _analyze_focus(self, metrics):
        eyes_open = self._are_eyes_open(metrics)

        if not self.calibrated:
            starter_score = 72 if eyes_open else 48
            focus_score = self._smooth_attention_score(starter_score)
            category = self._score_category(focus_score)
            self._remember_metrics(metrics)

            self.debug_info = {
                "status": "calibrating",
                "metrics": self._rounded_metrics(metrics),
                "eyes_open": eyes_open,
                "focus_score": round(focus_score, 2),
                "raw_attention_score": starter_score,
                "focus_category": category,
                "gaze_confidence": 1.0 if metrics.get("gaze_available") else 0.0,
                "head_direction_confidence": 0.55,
                "smoothing_alpha": round(self.last_smoothing_alpha, 3),
            }

            return focus_score >= 55 and eyes_open

        horizontal_delta = abs(
            metrics["nose_signed_ratio"] - self._baseline_value("nose_signed_ratio")
        )
        absolute_horizontal = abs(metrics["nose_signed_ratio"])

        vertical_delta = abs(
            metrics["vertical_ratio"] - self._baseline_value("vertical_ratio")
        )

        face_size_change = self._safe_ratio(
            metrics["face_width"],
            self._baseline_value("face_width"),
        )

        mouth_delta = abs(
            metrics["mouth_eye_ratio"] - self._baseline_value("mouth_eye_ratio")
        )

        shape_delta = abs(
            metrics["face_height_width_ratio"] -
            self._baseline_value("face_height_width_ratio")
        )

        roll_delta = abs(metrics["roll_angle"] - self._baseline_value("roll_angle"))
        roll_delta = min(roll_delta, 360 - roll_delta)

        gaze_available = bool(metrics.get("gaze_available"))
        gaze_x_delta = 0.0
        gaze_y_delta = 0.0

        if gaze_available:
            gaze_x_delta = abs(metrics["gaze_x"] - self._baseline_value("gaze_x"))
            gaze_y_delta = abs(metrics["gaze_y"] - self._baseline_value("gaze_y"))

        head_yaw_score = self._score_smaller_is_better(
            value=max(horizontal_delta, absolute_horizontal * 0.72),
            good_limit=0.09,
            bad_limit=0.34,
        )
        head_pitch_score = self._score_smaller_is_better(
            value=vertical_delta,
            good_limit=0.12,
            bad_limit=0.42,
        )
        head_roll_score = self._score_smaller_is_better(
            value=roll_delta,
            good_limit=6.0,
            bad_limit=28.0,
        )
        head_score = (
            head_yaw_score * 0.48 +
            head_pitch_score * 0.38 +
            head_roll_score * 0.14
        )

        if gaze_available:
            gaze_x_score = self._score_smaller_is_better(
                value=gaze_x_delta,
                good_limit=0.10,
                bad_limit=0.34,
            )
            gaze_y_score = self._score_smaller_is_better(
                value=gaze_y_delta,
                good_limit=0.13,
                bad_limit=0.45,
            )
            gaze_score = gaze_x_score * 0.56 + gaze_y_score * 0.44
            gaze_confidence = 1.0
        else:
            gaze_x_score = None
            gaze_y_score = None
            gaze_score = head_score * 0.72 + 0.18
            gaze_confidence = 0.0

        eye_score = self._score_larger_is_better(
            value=metrics["eye_open_ratio"],
            good_limit=0.22,
            bad_limit=0.10,
        )

        if not eyes_open:
            eye_score = min(eye_score, 0.45)

        stability_score = self._movement_stability_score(metrics)
        distance_score = self._score_distance_change(face_size_change)
        mouth_score = self._score_smaller_is_better(
            value=mouth_delta,
            good_limit=0.14,
            bad_limit=0.38,
        )
        shape_score = self._score_smaller_is_better(
            value=shape_delta,
            good_limit=0.24,
            bad_limit=0.72,
        )

        raw_attention_score = (
            head_score * 0.28 +
            gaze_score * 0.30 +
            eye_score * 0.10 +
            stability_score * 0.14 +
            distance_score * 0.08 +
            shape_score * 0.06 +
            mouth_score * 0.04
        ) * 100

        hard_reasons = []

        if horizontal_delta > 0.42 or absolute_horizontal > 0.50:
            hard_reasons.append("head_yaw")

        if vertical_delta > 0.58:
            hard_reasons.append("head_pitch")

        if roll_delta > 34:
            hard_reasons.append("head_roll")

        if gaze_available and (gaze_x_delta > 0.44 or gaze_y_delta > 0.56):
            hard_reasons.append("gaze")

        if not eyes_open and len(self.eye_history) >= 5 and sum(self.eye_history[-5:]) <= 1:
            hard_reasons.append("eyes_closed")

        if hard_reasons:
            raw_attention_score = min(raw_attention_score, 50)

        if (
            "head_yaw" in hard_reasons and horizontal_delta > 0.55
        ) or (
            "gaze" in hard_reasons and max(gaze_x_delta, gaze_y_delta) > 0.68
        ):
            raw_attention_score = min(raw_attention_score, 28)

        raw_attention_score = self._apply_sustained_drop_cap(
            raw_attention_score,
            hard_reasons,
        )

        focus_score = self._smooth_attention_score(
            raw_attention_score,
            force_drop=bool(hard_reasons),
        )
        category = self._score_category(focus_score)

        self._remember_metrics(metrics)

        raw_focus = focus_score >= 50 and category != "severe_drop"

        self.debug_info = {
            "metrics": self._rounded_metrics(metrics),
            "baseline": self._rounded_metrics(self.baseline),
            "horizontal_delta": round(horizontal_delta, 3),
            "absolute_horizontal": round(absolute_horizontal, 3),
            "vertical_delta": round(vertical_delta, 3),
            "roll_delta": round(roll_delta, 3),
            "face_size_change": round(face_size_change, 3),
            "mouth_delta": round(mouth_delta, 3),
            "shape_delta": round(shape_delta, 3),
            "gaze_x_delta": round(gaze_x_delta, 3) if gaze_available else None,
            "gaze_y_delta": round(gaze_y_delta, 3) if gaze_available else None,
            "head_score": round(head_score, 3),
            "head_yaw_score": round(head_yaw_score, 3),
            "head_pitch_score": round(head_pitch_score, 3),
            "head_roll_score": round(head_roll_score, 3),
            "gaze_score": round(gaze_score, 3),
            "gaze_x_score": round(gaze_x_score, 3) if gaze_x_score is not None else None,
            "gaze_y_score": round(gaze_y_score, 3) if gaze_y_score is not None else None,
            "eye_score": round(eye_score, 3),
            "stability_score": round(stability_score, 3),
            "distance_score": round(distance_score, 3),
            "mouth_score": round(mouth_score, 3),
            "shape_score": round(shape_score, 3),
            "eyes_open": eyes_open,
            "raw_attention_score": round(raw_attention_score, 2),
            "focus_score": round(focus_score, 2),
            "focus_category": category,
            "hard_not_focus": bool(hard_reasons),
            "hard_reasons": hard_reasons,
            "gaze_confidence": gaze_confidence,
            "head_direction_confidence": round(head_score, 3),
            "no_face_duration": 0,
            "smoothing_alpha": round(self.last_smoothing_alpha, 3),
            "low_attention_seconds": self._low_attention_seconds(),
            "face_box": self._rounded_box(metrics.get("face_box")),
        }

        return raw_focus

    def _baseline_value(self, key):
        value = self.baseline.get(key)

        if value is None:
            return 0

        return value

    def _apply_sustained_drop_cap(self, raw_attention_score, hard_reasons):
        sustained_drop = raw_attention_score < 50 or bool(hard_reasons)
        now = time.time()

        if not sustained_drop:
            self.low_attention_started_at = None
            return raw_attention_score

        if self.low_attention_started_at is None:
            self.low_attention_started_at = now

        duration = now - self.low_attention_started_at

        if duration >= 20:
            return min(raw_attention_score, 25)

        if duration >= 12:
            return min(raw_attention_score, 38)

        if duration >= 7:
            return min(raw_attention_score, 50)

        return raw_attention_score

    def _handle_no_face(self):
        now = time.time()

        if self.no_face_started_at is None:
            self.no_face_started_at = now

        duration = now - self.no_face_started_at

        raw_score = 0
        focus_score = 0
        self.smoothed_focus_score = 0
        self.last_smoothing_alpha = 1.0

        category = "away" if duration >= 18 else "no_face"

        self.low_attention_started_at = self.low_attention_started_at or now
        self.debug_info = {
            "status": category,
            "metrics": None,
            "baseline": self._rounded_metrics(self.baseline),
            "eyes_open": False,
            "raw_attention_score": round(raw_score, 2),
            "focus_score": round(focus_score, 2),
            "focus_category": category,
            "hard_not_focus": True,
            "hard_reasons": ["no_face"],
            "face_found": False,
            "gaze_confidence": 0.0,
            "head_direction_confidence": 0.0,
            "no_face_duration": round(duration, 2),
            "smoothing_alpha": round(self.last_smoothing_alpha, 3),
        }

        return False

    def _movement_stability_score(self, metrics):
        if not self.metric_history:
            return 1.0

        previous = self.metric_history[-1]
        movement = abs(
            metrics["nose_signed_ratio"] - previous.get("nose_signed_ratio", 0)
        )
        movement += abs(
            metrics["vertical_ratio"] - previous.get("vertical_ratio", 0)
        ) * 0.8
        movement += abs(metrics["roll_angle"] - previous.get("roll_angle", 0)) / 42

        if metrics.get("gaze_available") and previous.get("gaze_available"):
            movement += abs(metrics["gaze_x"] - previous.get("gaze_x", 0)) * 0.7
            movement += abs(metrics["gaze_y"] - previous.get("gaze_y", 0)) * 0.5

        return self._score_smaller_is_better(
            value=movement,
            good_limit=0.045,
            bad_limit=0.18,
        )

    def _remember_metrics(self, metrics):
        compact = {
            key: value
            for key, value in metrics.items()
            if isinstance(value, (int, float, bool))
        }

        self.metric_history.append(compact)

        if len(self.metric_history) > 8:
            self.metric_history.pop(0)

    def _smooth_attention_score(self, raw_score, force_drop=False):
        raw_score = max(0, min(100, raw_score))

        if self.smoothed_focus_score is None:
            self.smoothed_focus_score = raw_score
            self.last_smoothing_alpha = 1.0
            return self.smoothed_focus_score

        previous = self.smoothed_focus_score

        if raw_score < previous:
            alpha = 0.40 if (force_drop or raw_score < 35) else 0.30
        else:
            alpha = 0.22 if previous < 50 else 0.28

        self.last_smoothing_alpha = alpha
        self.smoothed_focus_score = previous + (raw_score - previous) * alpha

        return max(0, min(100, self.smoothed_focus_score))

    def _low_attention_seconds(self):
        if self.low_attention_started_at is None:
            return 0

        return round(time.time() - self.low_attention_started_at, 2)

    def _score_smaller_is_better(self, value, good_limit, bad_limit):
        if value <= good_limit:
            return 1.0

        if value >= bad_limit:
            return 0.0

        return 1.0 - ((value - good_limit) / (bad_limit - good_limit))

    def _score_larger_is_better(self, value, good_limit, bad_limit):
        if value >= good_limit:
            return 1.0

        if value <= bad_limit:
            return 0.0

        return (value - bad_limit) / (good_limit - bad_limit)

    def _score_distance_change(self, ratio):
        if 0.70 <= ratio <= 1.45:
            return 1.0

        if 0.50 <= ratio < 0.70:
            return (ratio - 0.50) / 0.20

        if 1.45 < ratio <= 1.90:
            return 1.0 - ((ratio - 1.45) / 0.45)

        return 0.0

    def _safe_ratio(self, value, baseline_value):
        if baseline_value is None or baseline_value == 0:
            return 1.0

        return value / baseline_value

    def _are_eyes_open(self, metrics):
        left_closed = metrics.get("left_eye_ratio", 0.22) < 0.145
        right_closed = metrics.get("right_eye_ratio", 0.22) < 0.145
        eyes_open = not (left_closed and right_closed)

        self.eye_history.append(eyes_open)

        if len(self.eye_history) > 5:
            self.eye_history.pop(0)

        if len(self.eye_history) < 3:
            return eyes_open

        return sum(self.eye_history) >= 3

    def _update_face_seen_history(self, face_found):
        self.face_seen_history.append(face_found)

        if len(self.face_seen_history) > 12:
            self.face_seen_history.pop(0)

    def _smooth_focus(self, raw_focus):
        self.focus_history.append(raw_focus)

        if len(self.focus_history) > 8:
            self.focus_history.pop(0)

        if len(self.face_seen_history) >= 6:
            face_seen_count = sum(self.face_seen_history[-6:])

            if face_seen_count <= 2:
                return False

        focus_count = sum(self.focus_history)

        if len(self.focus_history) < 4:
            return focus_count >= 2

        return sum(self.focus_history[-5:]) >= 3

    def _score_category(self, score):
        if score >= 85:
            return "excellent"

        if score >= 70:
            return "balanced"

        if score >= 50:
            return "fluctuating"

        if score >= 30:
            return "drop"

        return "severe_drop"

    def _rounded_metrics(self, metrics):
        if metrics is None:
            return None

        rounded = {}

        for key, value in metrics.items():
            if value is None:
                rounded[key] = None
            elif isinstance(value, bool):
                rounded[key] = value
            elif isinstance(value, dict):
                rounded[key] = self._rounded_box(value)
            elif isinstance(value, (int, float)):
                rounded[key] = round(value, 3)

        return rounded

    def _rounded_box(self, box):
        if box is None:
            return None

        return {
            key: round(value, 2)
            for key, value in box.items()
            if isinstance(value, (int, float))
        }

    def reset_calibration(self):
        self.calibration_frames = []
        self.calibrated = False
        self.baseline = self._empty_baseline()

        self.eye_history = []
        self.focus_history = []
        self.face_seen_history = []
        self.metric_history = []
        self.smoothed_focus_score = None
        self.no_face_started_at = None
        self.low_attention_started_at = None
        self.last_smoothing_alpha = 1.0

    def get_debug_info(self):
        return self.debug_info
