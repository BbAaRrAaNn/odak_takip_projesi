import cv2

from focus.focus_detector import FocusDetector
from session.session_manager import SessionManager
from data.session_storage import SessionStorage
from analytics.trend_analyzer import TrendAnalyzer
from analytics.ml_focus_predictor import MLFocusPredictor


def start_camera():
    cap = cv2.VideoCapture(0)

    if not cap.isOpened():
        print("camera could not be turned on")
        return

    focus_detector = FocusDetector()
    session_manager = SessionManager()
    session_storage = SessionStorage()
    trend_analyzer = TrendAnalyzer()
    ml_predictor = MLFocusPredictor()

    planned_total_minutes = 60

    previous_sessions = session_storage.load_sessions()
    trend_analysis = trend_analyzer.analyze_sessions(previous_sessions)

    focus_plan = ml_predictor.generate_focus_plan(
        sessions=previous_sessions,
        planned_total_minutes=planned_total_minutes
    )

    if ml_predictor.model is not None and len(previous_sessions) > 0:
        ml_prediction = ml_predictor.predict_next_focus_score(previous_sessions)
    else:
        ml_prediction = {
            "prediction_available": False,
            "predicted_focus_score": None,
            "message": "Henüz eğitilmiş ML modeli yok."
        }

    session_manager.start_session(
        session_plan=focus_plan
    )

    print("Session started")
    print("Planned total minutes:", planned_total_minutes)
    print("Focus plan:", focus_plan)
    print("Trend analysis:", trend_analysis)
    print("ML prediction:", ml_prediction)

    frame_counter = 0

    while True:
        ret, frame = cap.read()

        if not ret:
            print("No image was captured by the camera")
            break

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        is_focused, detection_result = focus_detector.analyze_frame(
            rgb_frame,
            frame
        )

        session_manager.update(is_focused)

        live_status = session_manager.get_live_status()
        debug_info = focus_detector.get_debug_info()

        focus_score = live_status.get("focus_score", 0)

        if focus_score >= 85:
            text = "Odak cok iyi"
            color = (74, 222, 128)
        elif focus_score >= 70:
            text = "Odak dengeli"
            color = (34, 197, 94)
        elif focus_score >= 50:
            text = "Odak dalgalaniyor"
            color = (234, 179, 8)
        elif focus_score >= 30:
            text = "Odak dususu var"
            color = (249, 115, 22)
        else:
            text = "Odak ciddi dustu"
            color = (239, 68, 68)

        cv2.putText(
            frame,
            text,
            (30, 60),
            cv2.FONT_HERSHEY_SIMPLEX,
            1,
            color,
            2
        )

        cv2.putText(
            frame,
            f"Session Score: {live_status['focus_score']}%",
            (30, 100),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.65,
            (255, 255, 255),
            2
        )

        cv2.putText(
            frame,
            f"Focus: {live_status['focus_seconds']}s Not: {live_status['not_focus_seconds']}s",
            (30, 135),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2
        )

        cv2.putText(
            frame,
            f"Short NF: {live_status['short_not_focus_ratio']} Long NF: {live_status['long_not_focus_ratio']}",
            (30, 165),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2
        )

        next_planned_break = live_status.get("next_planned_break")
        current_plan_notification = live_status.get("current_plan_notification")

        if next_planned_break is not None:
            cv2.putText(
                frame,
                f"Next Break At: {next_planned_break['work_until_minute']} min",
                (30, 200),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.55,
                (255, 255, 0),
                2
            )

        if current_plan_notification is not None:
            cv2.putText(
                frame,
                current_plan_notification["message"],
                (30, 230),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 255, 255),
                2
            )

        if live_status["warning_active"]:
            cv2.putText(
                frame,
                "Warning: Focus quality dropped",
                (30, 265),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 0, 255),
                2
            )

        if live_status["session_paused"]:
            cv2.putText(
                frame,
                "Break Mode",
                (30, 300),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (255, 255, 0),
                2
            )

            if live_status["break_ready"]:
                cv2.putText(
                    frame,
                    "Break ready. Press R to resume.",
                    (30, 335),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.6,
                    (0, 255, 255),
                    2
                )

        if debug_info:
            debug_y = 370

            focus_detector_score = debug_info.get("focus_score", "-")
            raw_focus = debug_info.get("raw_focus", "-")
            stable_focus = debug_info.get("stable_focus", "-")
            calibrated = debug_info.get("calibrated", "-")

            cv2.putText(
                frame,
                f"Detector Score: {focus_detector_score}",
                (30, debug_y),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (255, 255, 0),
                2
            )

            cv2.putText(
                frame,
                f"Raw: {raw_focus} Stable: {stable_focus} Calibrated: {calibrated}",
                (30, debug_y + 30),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (255, 255, 0),
                2
            )

            if "horizontal_delta" in debug_info and "vertical_delta" in debug_info:
                cv2.putText(
                    frame,
                    f"H-Delta: {debug_info['horizontal_delta']} V-Delta: {debug_info['vertical_delta']}",
                    (30, debug_y + 60),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.5,
                    (255, 255, 0),
                    2
                )

        if detection_result.detections:
            for detection in detection_result.detections:
                bbox = detection.bounding_box

                x = int(bbox.origin_x)
                y = int(bbox.origin_y)
                w = int(bbox.width)
                h = int(bbox.height)

                cv2.rectangle(
                    frame,
                    (x, y),
                    (x + w, y + h),
                    (0, 255, 0),
                    2
                )

        frame_counter += 1

        if frame_counter % 60 == 0:
            print("Live status:", live_status)
            print("Focus debug:", debug_info)

        cv2.imshow("FocusVision camera debug", frame)

        key = cv2.waitKey(1) & 0xFF

        if key == ord("b"):
            session_manager.start_break(
                suggested_break_seconds=focus_plan["recommended_break_seconds"],
                reason="debug_user_started_break"
            )
            print("Break started")

        if key == ord("r"):
            session_manager.end_break()
            print("Break ended")

        if key == ord("q"):
            break

    session_data = session_manager.end_session()

    if session_data is not None:
        updated_sessions = session_storage.save_session(session_data)

        updated_trend_analysis = trend_analyzer.analyze_sessions(updated_sessions)
        training_result = ml_predictor.train(updated_sessions)
        next_prediction = ml_predictor.predict_next_focus_score(updated_sessions)

        next_focus_plan = ml_predictor.generate_focus_plan(
            sessions=updated_sessions,
            planned_total_minutes=planned_total_minutes
        )

        print("Session saved:")
        print(session_data)

        print("Updated trend analysis:")
        print(updated_trend_analysis)

        print("ML training result:")
        print(training_result)

        print("Next session prediction:")
        print(next_prediction)

        print("Next focus plan:")
        print(next_focus_plan)

    cap.release()
    cv2.destroyAllWindows()
