from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import joblib
import os
import boto3

app = FastAPI()

ARTIFACT_BUCKET = os.environ["ARTIFACT_BUCKET"]
MODEL_KEY = "artifacts/current/model.joblib"
MODEL_PATH = os.path.expanduser("~/models/model.joblib")


def download_model():
    """Tai model tu S3 bang IAM role cua EC2 khi server khoi dong."""
    os.makedirs(os.path.dirname(MODEL_PATH), exist_ok=True)
    boto3.client("s3").download_file(
        ARTIFACT_BUCKET,
        MODEL_KEY,
        MODEL_PATH,
    )
    print("Đã tải model từ S3.")

download_model()
model = joblib.load(MODEL_PATH)


class ScoreRequest(BaseModel):
    features: list[float]


@app.get("/healthz")
def healthz():
    """
    Endpoint kiem tra suc khoe server.
    GitHub Actions goi endpoint nay sau khi deploy de xac nhan server dang chay.

    Tra ve: {"status": "ok"}
    """
    # TODO 5: Tra ve dict {"status": "ok"}
    return {"status": "ok"}


@app.post("/score")
def score(req: ScoreRequest):
    """
    Endpoint suy luan chinh.

    Dau vao : JSON {"features": [f1, f2, ..., f10]}
    Dau ra  : JSON {"prediction": <0|1>, "label": <"thu_nhap_thap"|"thu_nhap_cao">}

    Thu tu 10 dac trung (khop voi thu tu trong FEATURE_NAMES cua test):
        age, workclass, education_num, marital_status, occupation,
        relationship, sex, capital_gain, capital_loss, hours_per_week
    """
    # TODO 6: Kiem tra so luong dac trung.
    # Neu len(req.features) != 10, raise HTTPException(status_code=400, ...)

    # TODO 7: Goi model.predict([req.features]) de lay ket qua du doan.
    # pred = model.predict(...)

    # TODO 8: Tra ve dict chua "prediction" (int) va "label" (string).
    # Nhan tuong ung: 0 -> "thu_nhap_thap", 1 -> "thu_nhap_cao"
    # return {"prediction": ..., "label": ...}
    if len(req.features) != 10:
        raise HTTPException(
            status_code=400,
            detail="Expected 10 features (adult income)",
        )

    prediction = int(model.predict([req.features])[0])

    return {
        "prediction": prediction,
        "label": "thu_nhap_cao" if prediction == 1 else "thu_nhap_thap",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080)
