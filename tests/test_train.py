import json

import joblib
import numpy as np
import pandas as pd
import pytest
import mlflow

from src.train import train


FEATURE_NAMES = [
    "age", "workclass", "education_num", "marital_status", "occupation",
    "relationship", "sex", "capital_gain", "capital_loss", "hours_per_week",
]


@pytest.fixture
def training_result(tmp_path, monkeypatch):
    # Keep model/report artifacts and MLflow runs isolated from the real lab outputs.
    monkeypatch.chdir(tmp_path)
    mlflow.set_tracking_uri((tmp_path / "mlruns").as_uri())

    rng = np.random.default_rng(0)
    X = rng.random((200, len(FEATURE_NAMES)))
    y = rng.integers(0, 2, size=200)
    df = pd.DataFrame(X, columns=FEATURE_NAMES)
    df["target"] = y
    train_path = tmp_path / "train.csv"
    eval_path = tmp_path / "holdout.csv"
    df.iloc[:160].to_csv(train_path, index=False)
    df.iloc[160:].to_csv(eval_path, index=False)

    f1 = train(
        {"n_estimators": 10, "learning_rate": 0.1, "max_depth": 2},
        data_path=str(train_path),
        eval_path=str(eval_path),
    )
    return f1, tmp_path, df.iloc[160:].drop(columns=["target"])


def test_train_returns_float(training_result):
    f1, _, _ = training_result
    assert isinstance(f1, float)
    assert 0.0 <= f1 <= 1.0


def test_report_file_created(training_result):
    f1, tmp_path, _ = training_result
    with (tmp_path / "outputs/report.json").open() as report_file:
        report = json.load(report_file)
    assert report["f1_score"] == f1
    assert 0.0 <= report["accuracy"] <= 1.0


def test_model_file_created(training_result):
    _, tmp_path, X_eval = training_result
    model = joblib.load(tmp_path / "models/model.joblib")
    predictions = model.predict(X_eval)
    assert len(predictions) == len(X_eval)
    assert set(predictions) <= {0, 1}
