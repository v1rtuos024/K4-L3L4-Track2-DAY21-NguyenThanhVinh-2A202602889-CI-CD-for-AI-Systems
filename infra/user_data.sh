#!/bin/bash
set -euxo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y python3-venv python3-pip

sudo -u ubuntu python3 -m venv /home/ubuntu/venv

/home/ubuntu/venv/bin/pip install \
  fastapi==0.111.0 \
  uvicorn==0.29.0 \
  scikit-learn==1.4.2 \
  joblib==1.4.2 \
  boto3

install -d -o ubuntu -g ubuntu \
  /home/ubuntu/models /home/ubuntu/src

cat > /etc/systemd/system/income-api.service <<'SERVICE'
[Unit]
Description=Income Model Inference Server
After=network-online.target
Wants=network-online.target

[Service]
User=ubuntu
WorkingDirectory=/home/ubuntu
Environment="ARTIFACT_BUCKET=${bucket_name}"
Environment="AWS_DEFAULT_REGION=${region}"
ExecStart=/home/ubuntu/venv/bin/python /home/ubuntu/src/serve.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable income-api
