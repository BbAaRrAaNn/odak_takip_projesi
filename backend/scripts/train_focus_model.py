import sys
import os

sys.path.append(
    os.path.abspath(
        os.path.join(
            os.path.dirname(__file__),
            "..",
        )
    )
)

from analytics.ml_focus_predictor import MLFocusPredictor
from data.session_storage import SessionStorage


def main():
    storage = SessionStorage()
    sessions = storage.load_sessions()

    predictor = MLFocusPredictor()

    result = predictor.train(
        sessions=sessions,
    )

    print(result)


if __name__ == "__main__":
    main()