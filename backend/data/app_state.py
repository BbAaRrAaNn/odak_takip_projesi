import json
import os
from copy import deepcopy
from datetime import datetime


class AppStateStorage:
    def __init__(
        self,
        file_path="data/app_state.json",
    ):
        if not os.path.isabs(file_path):
            backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            file_path = os.path.join(backend_dir, file_path)

        self.file_path = file_path
        self.ensure_file()

    @property
    def default_state(self):
        return {
            "profile": {
                "display_name": "",
                "premium": False,
            },
            "settings": {
                "notifications_enabled": True,
                "break_reminders_enabled": True,
                "live_focus_notifications_enabled": True,
                "camera_preview_default_visible": True,
                "theme_mode": "light",
                "language": "tr",
                "color_vision_mode": "standard",
            },
            "cache": {
                "last_cache_clear_at": None,
            },
        }

    def ensure_file(self):
        folder = os.path.dirname(self.file_path)

        if folder:
            os.makedirs(folder, exist_ok=True)

        if not os.path.exists(self.file_path):
            self.save_state(self.default_state)

    def load_state(self):
        self.ensure_file()

        try:
            with open(self.file_path, "r", encoding="utf-8") as file:
                data = json.load(file)
        except (json.JSONDecodeError, FileNotFoundError):
            data = {}

        state = deepcopy(self.default_state)

        if isinstance(data, dict):
            for key in ["profile", "settings", "cache"]:
                if isinstance(data.get(key), dict):
                    for state_key, value in data[key].items():
                        if state_key in state[key]:
                            state[key][state_key] = value

        return state

    def save_state(self, state):
        folder = os.path.dirname(self.file_path)

        if folder:
            os.makedirs(folder, exist_ok=True)

        with open(self.file_path, "w", encoding="utf-8") as file:
            json.dump(state, file, indent=4, ensure_ascii=False)

        return state

    def get_profile(self):
        return self.load_state()["profile"]

    def update_profile(self, profile):
        state = self.load_state()
        clean_profile = {}

        for key in ["display_name"]:
            value = profile.get(key)
            if value is not None:
                clean_profile[key] = str(value).strip()

        state["profile"].update(clean_profile)
        self.save_state(state)
        return state["profile"]

    def get_settings(self):
        return self.load_state()["settings"]

    def update_settings(self, settings):
        state = self.load_state()
        allowed = self.default_state["settings"]

        for key, value in settings.items():
            if key not in allowed:
                continue

            if isinstance(allowed[key], bool):
                state["settings"][key] = bool(value)
            elif key == "theme_mode":
                state["settings"][key] = value if value in ["light", "dark"] else "light"
            elif key == "language":
                state["settings"][key] = "tr"
            elif key == "color_vision_mode":
                state["settings"][key] = (
                    value
                    if value
                    in [
                        "standard",
                        "protanopia",
                        "deuteranopia",
                        "tritanopia",
                        "achromatopsia",
                    ]
                    else "standard"
                )
            else:
                state["settings"][key] = value

        self.save_state(state)
        return state["settings"]

    def clear_cache_metadata(self):
        state = self.load_state()
        state["cache"]["last_cache_clear_at"] = datetime.now().isoformat()
        self.save_state(state)
        return state["cache"]
