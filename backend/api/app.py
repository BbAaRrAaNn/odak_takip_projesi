
import os
from datetime import datetime

import cv2
from fastapi import FastAPI, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from analytics.session_pattern_analyzer import SessionPatternAnalyzer
from analytics.ml_focus_predictor import MLFocusPredictor
from analytics.trend_analyzer import TrendAnalyzer
from camera.camera_service import CameraService
from data.app_state import AppStateStorage
from data.session_storage import SessionStorage
from session.session_manager import SessionManager


BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class StartSessionRequest(BaseModel):
    session_mode: str = "classic"
    camera_enabled: bool = True
    planned_total_minutes: int = 60
    pomodoro_settings: dict | None = None


class SnoozeBreakRequest(BaseModel):
    snooze_minutes: int = 5
    reason: str = "manual"
    suggested_break_minutes: int | None = None


class ExtendBreakRequest(BaseModel):
    extra_minutes: int = 5
    reason: str = "manual"


class UpdateBreakRequest(BaseModel):
    selected_break_minutes: int = 5
    reason: str = "manual"


class StartBreakRequest(BaseModel):
    reason: str = "manual"
    selected_break_minutes: int = 5
    suggested_break_minutes: int | None = None
    break_type: str = "manual"


class BreakActionRequest(BaseModel):
    reason: str = "manual"
    suggested_break_minutes: int | None = None
    selected_break_minutes: int | None = None


class NotificationActionRequest(BaseModel):
    action_type: str
    reason: str = "manual"
    suggested_break_minutes: int | None = None
    selected_break_minutes: int | None = None


class ProfileRequest(BaseModel):
    display_name: str = ""


class SettingsRequest(BaseModel):
    notifications_enabled: bool | None = None
    break_reminders_enabled: bool | None = None
    live_focus_notifications_enabled: bool | None = None
    camera_preview_default_visible: bool | None = None
    theme_mode: str | None = None
    language: str | None = None
    color_vision_mode: str | None = None


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

session_storage = SessionStorage()
app_state_storage = AppStateStorage()
trend_analyzer = TrendAnalyzer()

ml_focus_predictor = MLFocusPredictor()

session_pattern_analyzer = SessionPatternAnalyzer()

session_manager = SessionManager(
    session_storage=session_storage,
)

camera_service = CameraService(
    session_manager=session_manager,
)


@app.get("/")
def root():
    return {
        "app": "FocusVision",
        "status": "running",
    }


@app.post("/app/heartbeat")
def heartbeat():
    return {
        "success": True,
        "session_active": session_manager.session_active,
        "camera_running": camera_service.running,
    }


@app.get("/profile")
def get_profile():
    return {
        "success": True,
        "profile": app_state_storage.get_profile(),
    }


@app.post("/profile")
def update_profile(request: ProfileRequest):
    profile = app_state_storage.update_profile(
        {
            "display_name": request.display_name,
        }
    )

    return {
        "success": True,
        "profile": profile,
    }


@app.get("/settings")
def get_settings():
    return {
        "success": True,
        "settings": app_state_storage.get_settings(),
    }


@app.post("/settings")
def update_settings(request: SettingsRequest):
    payload = {
        key: value
        for key, value in request.dict().items()
        if value is not None
    }

    return {
        "success": True,
        "settings": app_state_storage.update_settings(payload),
    }


@app.post("/session/start")
def start_session(request: StartSessionRequest):
    session_mode = request.session_mode.lower().strip()

    if session_mode not in ["classic", "adaptive", "flow"]:
        session_mode = "classic"

    camera_enabled = request.camera_enabled

    if session_mode == "flow":
        camera_enabled = True

    pomodoro_settings = request.pomodoro_settings

    if session_mode == "adaptive" and not pomodoro_settings:
        plan = ml_focus_predictor.generate_focus_plan(
            sessions=session_storage.load_sessions(),
            planned_total_minutes=request.planned_total_minutes,
        )
        pomodoro_settings = {
            "work_minutes": plan.get("work_minutes", 45),
            "short_break_minutes": plan.get("short_break_minutes", 8),
            "long_break_minutes": plan.get("long_break_minutes", 18),
            "long_break_every": plan.get("long_break_every", 4),
            "cycles": plan.get("cycles", 2),
            "source": "adaptive_ai",
            "data_quality": plan.get("data_quality", "starter"),
        }

    session_manager.start_session(
        session_mode=session_mode,
        camera_enabled=camera_enabled,
        planned_total_minutes=request.planned_total_minutes,
        pomodoro_settings=pomodoro_settings,
    )

    camera_started = False

    if camera_enabled:
        camera_started = camera_service.start()
    else:
        camera_service.stop()

    if camera_enabled and not camera_started:
        if session_mode == "flow":
            session_manager.reset()

            return {
                "success": False,
                "message": "Akış modu için kamera başlatılamadı.",
                "session_mode": session_mode,
                "camera_enabled": False,
                "planned_total_minutes": request.planned_total_minutes,
                "pomodoro_settings": pomodoro_settings,
                "live_status": session_manager.get_live_status(),
                "camera_status": camera_service.get_camera_status(),
            }

        session_manager.camera_enabled = False
        camera_enabled = False

    return {
        "success": True,
        "message": "Oturum başlatıldı.",
        "session_mode": session_mode,
        "camera_enabled": camera_enabled,
        "planned_total_minutes": request.planned_total_minutes,
        "pomodoro_settings": pomodoro_settings,
        "live_status": session_manager.get_live_status(),
        "camera_status": camera_service.get_camera_status(),
    }


@app.post("/session/end")
def end_session():
    camera_service.stop()

    session_data = session_manager.end_session()

    sessions = session_storage.load_sessions()

    try:
        training_result = ml_focus_predictor.train(
            sessions=sessions,
        )
    except Exception as error:
        training_result = {
            "success": False,
            "message": "Model eğitimi tamamlanamadı.",
            "error": str(error),
        }

    trend_result = trend_analyzer.analyze_sessions(
        sessions=sessions,
    )

    return {
        "success": True,
        "message": "Oturum kaydedildi.",
        "session_data": session_data,
        "training_result": training_result,
        "trend_result": trend_result,
    }


@app.get("/session/live")
def get_live_status():
    return {
        "live_status": session_manager.get_live_status(),
        "camera_status": camera_service.get_camera_status(),
    }


@app.get("/session/plan")
def get_session_plan():
    sessions = session_storage.load_sessions()

    plan = ml_focus_predictor.generate_focus_plan(
        sessions=sessions,
        planned_total_minutes=session_manager.planned_total_minutes,
    )

    return {
        "success": True,
        "session_plan": plan,
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/start")
def start_break(request: StartBreakRequest | None = None):
    payload = request or StartBreakRequest()

    session_manager.start_break(
        reason=payload.reason,
        selected_break_minutes=payload.selected_break_minutes,
        suggested_break_minutes=payload.suggested_break_minutes,
        break_type=payload.break_type,
    )

    return {
        "success": True,
        "message": "Mola başlatıldı.",
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/end")
def end_break():
    session_manager.end_break()

    return {
        "success": True,
        "message": "Mola bitirildi.",
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/accept")
def accept_break(request: BreakActionRequest | None = None):
    payload = request or BreakActionRequest()

    session_manager.accept_break(
        reason=payload.reason,
        suggested_break_minutes=payload.suggested_break_minutes,
        selected_break_minutes=payload.selected_break_minutes,
    )

    return {
        "success": True,
        "message": "Mola kabul edildi.",
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/decline")
def decline_break(request: BreakActionRequest | None = None):
    payload = request or BreakActionRequest()

    session_manager.decline_break(
        reason=payload.reason,
        suggested_break_minutes=payload.suggested_break_minutes,
    )

    return {
        "success": True,
        "message": "Mola reddedildi.",
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/snooze")
def snooze_break(request: SnoozeBreakRequest):
    session_manager.snooze_break(
        snooze_minutes=request.snooze_minutes,
        reason=request.reason,
        suggested_break_minutes=request.suggested_break_minutes,
    )

    return {
        "success": True,
        "message": "Mola ertelendi.",
        "snooze_minutes": request.snooze_minutes,
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/extend")
def extend_break(request: ExtendBreakRequest):
    session_manager.extend_break(
        extra_minutes=request.extra_minutes,
        reason=request.reason,
    )

    return {
        "success": True,
        "message": "Mola uzatıldı.",
        "extra_minutes": request.extra_minutes,
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/break/update")
def update_break(request: UpdateBreakRequest):
    session_manager.update_break_duration(
        selected_break_minutes=request.selected_break_minutes,
        reason=request.reason,
    )

    return {
        "success": True,
        "message": "Mola süresi güncellendi.",
        "selected_break_minutes": request.selected_break_minutes,
        "live_status": session_manager.get_live_status(),
    }


@app.post("/session/notification/action")
def record_notification_action(request: NotificationActionRequest):
    session_manager.record_notification_action(
        request.action_type,
        reason=request.reason,
        suggested_break_minutes=request.suggested_break_minutes,
        selected_break_minutes=request.selected_break_minutes,
    )

    return {
        "success": True,
        "live_status": session_manager.get_live_status(),
    }


@app.get("/sessions")
def get_sessions():
    sessions = session_storage.load_sessions()

    return {
        "success": True,
        "session_count": len(sessions),
        "sessions": sessions,
    }


@app.get("/analytics/trend")
def get_trend_analysis():
    sessions = session_storage.load_sessions()

    return trend_analyzer.analyze_sessions(
        sessions=sessions,
    )


@app.get("/analytics/focus-plan")
def get_focus_plan(
    planned_total_minutes: int = 90,
):
    sessions = session_storage.load_sessions()

    return ml_focus_predictor.generate_focus_plan(
        sessions=sessions,
        planned_total_minutes=planned_total_minutes,
    )


@app.post("/camera/start")
def start_camera():
    started = camera_service.start()
    session_manager.camera_enabled = bool(started)

    return {
        "success": bool(started),
        "message": (
            "Kamera başlatıldı."
            if started
            else "Kamera başlatılamadı; izin veya cihaz durumunu kontrol et."
        ),
        "camera_status": camera_service.get_camera_status(),
        "live_status": session_manager.get_live_status(),
    }


@app.post("/camera/stop")
def stop_camera():
    camera_service.stop()
    session_manager.camera_enabled = False

    return {
        "success": True,
        "message": "Kamera durduruldu.",
        "camera_status": camera_service.get_camera_status(),
        "live_status": session_manager.get_live_status(),
    }


@app.get("/camera/permission/check")
def check_camera_permission():
    if camera_service.running:
        return {
            "success": True,
            "camera_available": True,
            "camera_running": True,
            "message": "Kamera aktif oturumda çalışıyor.",
            "camera_status": camera_service.get_camera_status(),
        }

    capture = cv2.VideoCapture(0)
    available = capture.isOpened()

    if available:
        capture.release()

    return {
        "success": available,
        "camera_available": available,
        "camera_running": False,
        "message": (
            "Kamera erişimi kullanılabilir."
            if available
            else "Kamera açılamadı; macOS kamera iznini kontrol et."
        ),
    }


@app.get("/camera/frame")
def get_camera_frame():
    frame = camera_service.get_latest_frame()

    if frame is None:
        return Response(status_code=204)

    return Response(
        content=frame,
        media_type="image/jpeg",
    )


@app.post("/data/export")
def export_data():
    sessions = session_storage.load_sessions()
    state = app_state_storage.load_state()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    export_path = os.path.join(
        BACKEND_DIR,
        "data",
        f"focusvision-export-{timestamp}.json",
    )

    payload = {
        "exported_at": datetime.now().isoformat(),
        "profile": state["profile"],
        "settings": state["settings"],
        "sessions": sessions,
    }

    os.makedirs(os.path.dirname(export_path), exist_ok=True)

    with open(export_path, "w", encoding="utf-8") as file:
        import json

        json.dump(payload, file, indent=4, ensure_ascii=False)

    return {
        "success": True,
        "export_path": os.path.abspath(export_path),
        "session_count": len(sessions),
        "message": "Veri dışa aktarma tamamlandı.",
    }


@app.post("/data/clear-history")
def clear_history():
    session_storage.clear_sessions()

    return {
        "success": True,
        "message": "Oturum geçmişi temizlendi.",
        "session_count": 0,
    }


@app.post("/data/clear-cache")
def clear_cache():
    cache = app_state_storage.clear_cache_metadata()

    return {
        "success": True,
        "cache": cache,
        "message": "Yerel geçici cache metadata temizlendi; oturum geçmişi korunuyor.",
    }


@app.post("/model/retrain")
def retrain_model():
    sessions = session_storage.load_sessions()

    try:
        result = ml_focus_predictor.train(sessions=sessions)
    except Exception as error:
        result = {
            "success": False,
            "message": "Model eğitimi tamamlanamadı.",
            "error": str(error),
        }

    return {
        "success": result.get("success", False),
        "training_result": result,
    }
@app.get("/analytics/patterns")
def get_patterns():
    sessions = session_storage.load_sessions()

    result = (
        session_pattern_analyzer.analyze(
            sessions=sessions,
        )
    )

    return {
        "success": True,
        "patterns": result,
    }
