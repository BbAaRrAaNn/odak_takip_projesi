import cv2
import threading
import time

from focus.focus_detector import FocusDetector


class CameraService:
    def __init__(self, session_manager):
        self.session_manager = session_manager
        self.focus_detector = None

        self.cap = None
        self.running = False
        self.thread = None

        self.latest_is_focused = False
        self.latest_face_found = False
        self.latest_focus_score = 0.0
        self.latest_error = None
        self.latest_frame_time = None
        self.latest_jpeg_frame = None
        self.frame_lock = threading.Lock()
        self.target_frame_interval = 1 / 15

    def start(self):
        if self.running:
            return True

        if self.focus_detector is None:
            self.focus_detector = FocusDetector()

        self.cap = cv2.VideoCapture(0)

        if not self.cap.isOpened():
            self.latest_error = "Camera could not be opened"
            self.cap = None
            self.running = False
            return False

        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 360)
        self.cap.set(cv2.CAP_PROP_FPS, 15)
        self.cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        try:
            self.cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        except Exception:
            pass

        self.latest_error = None
        self.running = True

        self.thread = threading.Thread(
            target=self._camera_loop,
            daemon=True,
        )

        self.thread.start()
        return True

    def stop(self):
        self.running = False

        if self.thread is not None:
            self.thread.join(timeout=2)
            self.thread = None

        if self.cap is not None:
            self.cap.release()
            self.cap = None

        with self.frame_lock:
            self.latest_jpeg_frame = None
            self.latest_frame_time = None

        self.latest_is_focused = False
        self.latest_face_found = False
        self.latest_focus_score = 0.0

    def _camera_loop(self):
        while self.running:
            loop_started_at = time.time()

            if self.cap is None:
                time.sleep(0.1)
                continue

            success, frame = self.cap.read()

            if not success:
                self.latest_error = "No frame captured"
                time.sleep(0.1)
                continue

            self.latest_error = None
            frame_time = time.time()

            rgb_frame = cv2.cvtColor(
                frame,
                cv2.COLOR_BGR2RGB,
            )

            analysis_paused = self.session_manager.session_paused

            if analysis_paused:
                is_focused = False
                detection_result = None
                debug_info = {
                    "status": "break",
                    "focus_category": "break",
                    "focus_score": self.latest_focus_score,
                    "face_found": self.latest_face_found,
                }
                face_found = self.latest_face_found
            else:
                is_focused, detection_result = self.focus_detector.analyze_frame(
                    rgb_frame,
                    frame,
                )
                debug_info = self.focus_detector.get_debug_info()
                face_found = bool(debug_info.get("face_found", False))

            self.latest_is_focused = bool(is_focused)
            self.latest_face_found = face_found
            self.latest_focus_score = (
                0.0 if not face_found else self._read_focus_score(is_focused)
            )

            self.session_manager.update(
                is_focused=bool(is_focused),
                face_found=face_found,
                focus_score=self.latest_focus_score,
                focus_debug=debug_info,
            )

            self._draw_overlay(
                frame=frame,
                is_focused=bool(is_focused),
                face_found=face_found,
                focus_score=self.latest_focus_score,
                detection_result=detection_result,
            )

            encode_success, buffer = cv2.imencode(
                ".jpg",
                frame,
                [int(cv2.IMWRITE_JPEG_QUALITY), 52],
            )

            if encode_success:
                with self.frame_lock:
                    self.latest_jpeg_frame = buffer.tobytes()
                    self.latest_frame_time = frame_time

            elapsed = time.time() - loop_started_at
            time.sleep(max(0.01, self.target_frame_interval - elapsed))

    def _read_focus_score(self, is_focused):
        debug_info = self.focus_detector.get_debug_info()

        if isinstance(debug_info, dict):
            raw_score = debug_info.get("focus_score")

            if raw_score is not None:
                try:
                    score = float(raw_score)

                    if score <= 1:
                        return round(score * 100, 2)

                    return round(score, 2)
                except (TypeError, ValueError):
                    pass

        return 85.0 if is_focused else 35.0

    def _draw_overlay(
        self,
        frame,
        is_focused,
        face_found,
        focus_score,
        detection_result,
    ):
        status_text, status_color = self._overlay_status(
            focus_score=focus_score,
            face_found=face_found,
            is_focused=is_focused,
        )

        overlay = frame.copy()

        cv2.rectangle(
            overlay,
            (14, 14),
            (330, 118),
            (20, 20, 20),
            -1,
        )

        cv2.addWeighted(
            overlay,
            0.35,
            frame,
            0.65,
            0,
            frame,
        )

        cv2.putText(
            frame,
            "FocusVision",
            (28, 43),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.72,
            (255, 255, 255),
            2,
        )

        cv2.putText(
            frame,
            status_text,
            (28, 76),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.72,
            status_color,
            2,
        )

        cv2.putText(
            frame,
            f"Score: {int(focus_score)}%",
            (28, 105),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.64,
            (255, 255, 255),
            2,
        )

        if detection_result is None:
            self._draw_debug_face_box(
                frame=frame,
                status_color=status_color,
            )
            return

        detections = getattr(
            detection_result,
            "detections",
            [],
        )

        if not detections:
            self._draw_debug_face_box(
                frame=frame,
                status_color=status_color,
            )
            return

        for detection in detections:
            bbox = detection.bounding_box

            x = int(bbox.origin_x)
            y = int(bbox.origin_y)
            w = int(bbox.width)
            h = int(bbox.height)

            cv2.rectangle(
                frame,
                (x, y),
                (x + w, y + h),
                status_color,
                2,
            )

    def _draw_debug_face_box(self, frame, status_color):
        debug_info = self.focus_detector.get_debug_info()
        face_box = debug_info.get("face_box")

        if not isinstance(face_box, dict):
            metrics = debug_info.get("metrics")
            if isinstance(metrics, dict):
                face_box = metrics.get("face_box")

        if not isinstance(face_box, dict):
            return

        try:
            x = int(face_box.get("x", 0))
            y = int(face_box.get("y", 0))
            w = int(face_box.get("w", 0))
            h = int(face_box.get("h", 0))
        except (TypeError, ValueError):
            return

        if w <= 0 or h <= 0:
            return

        cv2.rectangle(
            frame,
            (x, y),
            (x + w, y + h),
            status_color,
            2,
        )

    def _overlay_status(self, focus_score, face_found, is_focused):
        if self.session_manager.session_paused:
            return "Mola aktif", (155, 163, 175)

        if not face_found:
            return "Kisi algilanmadi", (155, 163, 175)

        if focus_score >= 85:
            return "Odak cok iyi", (74, 222, 128)

        if focus_score >= 70:
            return "Odak dengeli", (34, 197, 94)

        if focus_score >= 50:
            return "Odak dalgalaniyor", (234, 179, 8)

        if focus_score >= 30:
            return "Odak dususu var", (249, 115, 22)

        if is_focused:
            return "Odak dengeli", (34, 197, 94)

        return "Odak ciddi dustu", (239, 68, 68)

    def get_latest_frame(self):
        with self.frame_lock:
            return self.latest_jpeg_frame

    def get_camera_status(self):
        focus_debug = {}

        if self.focus_detector is not None:
            focus_debug = self.focus_detector.get_debug_info()

        with self.frame_lock:
            has_frame = self.latest_jpeg_frame is not None
            latest_frame_time = self.latest_frame_time

        return {
            "camera_running": self.running,
            "latest_is_focused": self.latest_is_focused,
            "latest_face_found": self.latest_face_found,
            "latest_focus_score": self.latest_focus_score,
            "latest_error": self.latest_error,
            "latest_frame_time": latest_frame_time,
            "has_frame": has_frame,
            "focus_debug": focus_debug,
        }
