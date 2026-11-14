import json
import os


class SessionStorage:
    def __init__(
        self,
        file_path="data/sessions.json",
    ):
        if not os.path.isabs(file_path):
            backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            file_path = os.path.join(backend_dir, file_path)

        self.file_path = file_path
        self.ensure_file()

    def ensure_file(self):
        folder = os.path.dirname(
            self.file_path
        )

        if folder:
            os.makedirs(
                folder,
                exist_ok=True,
            )

        if not os.path.exists(
            self.file_path
        ):
            with open(
                self.file_path,
                "w",
                encoding="utf-8",
            ) as file:
                json.dump(
                    [],
                    file,
                    indent=4,
                    ensure_ascii=False,
                )

    def load_sessions(self):
        self.ensure_file()

        try:
            with open(
                self.file_path,
                "r",
                encoding="utf-8",
            ) as file:
                data = json.load(file)

            if isinstance(data, list):
                return data

            return []

        except json.JSONDecodeError:
            return []

        except FileNotFoundError:
            self.ensure_file()
            return []

    def save_session(
        self,
        session_data,
    ):
        sessions = self.load_sessions()

        sessions.append(session_data)

        with open(
            self.file_path,
            "w",
            encoding="utf-8",
        ) as file:
            json.dump(
                sessions,
                file,
                indent=4,
                ensure_ascii=False,
            )

        return sessions

    def clear_sessions(self):
        with open(
            self.file_path,
            "w",
            encoding="utf-8",
        ) as file:
            json.dump(
                [],
                file,
                indent=4,
                ensure_ascii=False,
            )

        return []

    def get_session_count(self):
        return len(self.load_sessions())
