# Runbook AWS — Lab Day 21: CI/CD cho AI Systems

Runbook này dùng cấu hình hiện có trong repo: Terraform, S3, EC2 Ubuntu, DVC, MLflow và GitHub Actions OIDC. Lệnh mặc định chạy bằng PowerShell tại thư mục gốc dự án; các block Bash chạy bên trong EC2.

## 1. Kiến trúc và kết quả cần đạt

```text
Máy cá nhân --DVC push--> S3: dvc/
GitHub Actions: Unit Test -> Train -> Quality Gate -> Release
                              |                         |
                        GitHub artifacts         S3: artifacts/current/model.joblib
                                                        |
                                               EC2: income-api (8080)
```

- Unit Test kiểm tra hàm train bằng dữ liệu nhỏ.
- Train tải train_batch1 và holdout bằng DVC, huấn luyện và lưu report/model.
- Quality Gate kiểm tra F1 của lớp dương >= 0.65; accuracy không quyết định triển khai.
- Release copy API lên EC2, upload model đạt chất lượng, restart service và kiểm tra health.
- Model được chuyển giữa các job bằng GitHub artifacts; chỉ upload vào S3 current sau gate.

Kết quả cần đạt: bốn jobs xanh, `/healthz` trả `{"status":"ok"}`, `/score` trả dự đoán hợp lệ và S3 có dữ liệu/model. Runbook không xác nhận rằng một lần chạy cụ thể đã đạt các tiêu chí này.

## 2. Giá trị và file cấu hình

| Giá trị | Cấu hình của lab |
|---|---|
| AWS region | `us-east-1` |
| GitHub repo | `v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems` |
| Bucket hiện tại | `income-lab-v1rtuos024-2026` |
| DVC remote | `labstore` -> `s3://income-lab-v1rtuos024-2026/dvc` |
| EC2 user | `ubuntu` |
| SSH private key trên máy | `infra/lab-key` (RSA dùng được) |
| Systemd service | `income-api` |
| Model key | `artifacts/current/model.joblib` |
| API port | `8080` |

Không ghi cứng public IP, role ARN hoặc security group ID từ một lần chạy cũ. Lấy chúng qua Terraform outputs hoặc EC2 Console khi cần.

| File | Vai trò |
|---|---|
| `infra/main.tf`, `variables.tf`, `outputs.tf` | Hạ tầng AWS và quyền IAM |
| `infra/terraform.tfvars` | Giá trị môi trường cá nhân, không commit |
| `infra/user_data.sh` | Cài môi trường Python và systemd trên EC2 |
| `.dvc/config`, `data/*.dvc` | Remote và con trỏ dữ liệu |
| `params.yaml` | Siêu tham số huấn luyện |
| `src/train.py` | Huấn luyện, ghi MLflow, lưu report/model |
| `src/serve.py` | Tải model S3 và cung cấp API |
| `tests/test_train.py` | Kiểm tra train/report/model |
| `.github/workflows/cicd.yml` | Pipeline CI/CD |

## 3. Công cụ và profile AWS

Cài Terraform, AWS CLI, Git, OpenSSH và Python. Workflow dùng Python 3.10; máy cá nhân có thể dùng Python 3.10 hoặc 3.12 với dependencies của repo.

```powershell
terraform version
aws --version
python --version
```

### Access key cho tài khoản lab

Trong AWS Console: IAM -> User groups -> tạo `income-lab-terraform`; tạo `income-lab-user` và thêm user vào group. User chỉ cần Console access nếu muốn đăng nhập AWS Console bằng user đó.

Để dựng nhanh trong tài khoản lab riêng, có thể dùng các managed policies sau:

| Policy | Mục đích |
|---|---|
| AmazonEC2FullAccess | Tạo/quản lý EC2, key pair, EBS và security group |
| AmazonS3FullAccess | Tạo/cấu hình bucket và push/pull DVC |
| IAMFullAccess | Tạo role, policy, instance profile, OIDC provider và PassRole |
| AmazonSSMReadOnlyAccess | Đọc Ubuntu AMI từ public SSM parameter |

Đây là quyền rộng, không phải bộ quyền tối thiểu. IAMFullAccess có thể quản lý IAM toàn tài khoản. Với tài khoản dùng chung, dùng policy tùy chỉnh giới hạn tài nguyên lab và để quản trị viên phê duyệt quyền tạo role/PassRole.

Trong user -> Security credentials -> Create access key -> CLI, tạo access key. Không dùng access key của root; không đưa key vào Git, runbook hay ảnh nộp bài.

```powershell
aws configure --profile income-lab
```

Nhập access key ID, secret access key, region `us-east-1`, output `json`.

```powershell
$env:AWS_PROFILE = "income-lab"
$env:AWS_DEFAULT_REGION = "us-east-1"
aws sts get-caller-identity
aws configure list-profiles
```

Nếu tài khoản dùng IAM Identity Center:

```powershell
aws configure sso --profile income-lab
aws sso login --profile income-lab
$env:AWS_PROFILE = "income-lab"
```

Các biến PowerShell chỉ có hiệu lực trong terminal hiện tại. Khi mở terminal mới, đặt lại profile. Nếu đang có AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY trong môi trường, chúng có thể khiến CLI dùng danh tính khác profile; kiểm tra Account và Arn bằng get-caller-identity.

## 4. Môi trường Python và MLflow

Nếu chưa có virtual environment:

```powershell
python -m venv .venv
```

Kích hoạt và cài dependencies:

```powershell
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python -m pytest tests/ -v
python src/train.py
```

Nếu `.venv` báo `No Python at ...`, kiểm tra Python cài trên máy và tạo lại virtual environment với Python khả dụng. Lỗi này xảy ra trước khi mã train chạy.

Repo đã ràng buộc `setuptools<82` và `sqlalchemy>=1.4,<2.1` để tương thích MLflow 2.13.

Train mặc định ghi vào `sqlite:///mlflow.db` khi chạy script. Mở UI từ cùng thư mục gốc:

```powershell
mlflow ui --backend-store-uri sqlite:///mlflow.db
```

UI ở `http://127.0.0.1:5000`. Nếu muốn xem các run cũ trong file store, dừng UI hiện tại rồi chạy:

```powershell
mlflow ui --backend-store-uri ./mlruns
```

MLflow database tạo trong GitHub runner không tự xuất hiện trong UI trên máy cá nhân; workflow hiện lưu report và model thành GitHub artifacts.

## 5. Cấu hình Terraform

Sử dụng các file hiện có trong `infra/`. Hạ tầng dùng VPC/public subnet có sẵn, không tạo VPC mới. Subnet phải có route ra Internet Gateway và thuộc region `us-east-1`.

Nếu chưa có SSH key, tạo một lần; không ghi đè key đang được EC2 sử dụng:

```powershell
ssh-keygen -t rsa -b 4096 -f ".\infra\lab-key" -C "income-lab"
```

Workflow hiện không cung cấp passphrase khi dùng key. Nếu dùng key riêng cho CI với passphrase, cần bổ sung cơ chế giải mã phù hợp; cấu hình hiện tại cần private key không có passphrase. Giữ private key ngoài Git và thay key khi kết thúc lab nếu tiếp tục sử dụng server.

Lấy public IP máy cá nhân:

```powershell
Invoke-RestMethod https://checkip.amazonaws.com
```

Ví dụ `infra/terraform.tfvars`:

```hcl
region              = "us-east-1"
bucket_name         = "TEN_BUCKET_DUY_NHAT_CUA_BAN"
vpc_id              = "vpc-xxxxxxxx"
subnet_id           = "subnet-xxxxxxxx"
admin_cidr          = "IP_PUBLIC_MAY_BAN/32"
ssh_public_key_path = "C:/duong-dan/repo/infra/lab-key.pub"
github_repo         = "v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems"
```

Tên bucket phải duy nhất. Nếu dùng hạ tầng hiện có, giữ đúng tên bucket đã tạo.

`admin_cidr` là IP public của mạng máy bạn, không phải IP GitHub. `/32` chỉ cho phép đúng một IPv4. Đặt giá trị trong tfvars; sửa `description` của variable không thay đổi giá trị.

Terraform chỉ đọc public key `.pub`. Bucket private, dùng SSE-S3 và policy yêu cầu HTTPS; EBS được mã hóa; EC2 yêu cầu IMDSv2. EC2 role chỉ đọc file model. GitHub role chỉ đọc DVC, ghi model và mở/đóng SSH trên security group của lab.

Nếu account đã có GitHub OIDC provider, nhập ARN vào tfvars để tái sử dụng:

```hcl
github_oidc_provider_arn = "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
```

Chạy từ thư mục gốc:

```powershell
terraform "-chdir=infra" init
terraform "-chdir=infra" fmt
terraform "-chdir=infra" validate
terraform "-chdir=infra" plan "-out=lab.tfplan"
terraform "-chdir=infra" apply "lab.tfplan"
terraform "-chdir=infra" output
```

Đọc plan trước apply. Nếu đang đứng trong `infra`, bỏ `-chdir=infra`. PowerShell nên đặt nguyên đối số `-out=lab.tfplan` trong dấu nháy.

`user_data_replace_on_change = true`: sửa user_data có thể khiến Terraform tạo lại EC2. Thay đổi AMI cũng có thể thay instance; kiểm tra plan. Không apply Terraform trong lúc release đang mở rule SSH tạm.

## 6. Kiểm tra EC2 và systemd

```powershell
$ServerHost = terraform "-chdir=infra" output -raw server_host
$ServerHost = "$ServerHost".Trim()
Write-Output "EC2 IP: [$ServerHost]"
Test-NetConnection -ComputerName $ServerHost -Port 22
ssh -i ".\infra\lab-key" "ubuntu@$ServerHost"
```

Bên trong EC2:

```bash
sudo cloud-init status --wait
~/venv/bin/python --version
~/venv/bin/pip show boto3 scikit-learn
sudo systemctl cat income-api
ls -ld ~/src ~/models
```

Service cần có bucket/region thực tế và ExecStart `/home/ubuntu/venv/bin/python /home/ubuntu/src/serve.py`. EC2 role tự cung cấp credentials cho boto3; không copy access key lên VM.

User data chỉ enable service, chưa start vì code/model có thể chưa tồn tại. Workflow copy code và start service trong release. Nếu bootstrap lỗi:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
```

Public IP có thể đổi sau stop/start. Kiểm tra EC2 Console, cập nhật SERVER_HOST; nếu tạo lại VM, cập nhật cả host fingerprint và SSH key khi cần.

## 7. Đẩy dữ liệu bằng DVC

Từ máy cá nhân với AWS_PROFILE đã đặt:

```powershell
$LabBucket = terraform "-chdir=infra" output -raw artifact_bucket
```

Nếu chưa khởi tạo DVC, chạy một lần:

```powershell
dvc init
dvc remote add -d labstore "s3://$LabBucket/dvc"
```

Nếu đã có remote như repo hiện tại:

```powershell
dvc remote modify labstore url "s3://$LabBucket/dvc"
```

Tiếp tục:

```powershell
dvc remote modify labstore region us-east-1
dvc add data/train_batch1.csv
dvc add data/holdout.csv
dvc add data/train_batch2.csv
dvc push
```

Kiểm tra S3 Console -> bucket -> `dvc/`. Objects được đặt tên theo hash; không cần thấy tên CSV gốc. Commit `.dvc/config` và `data/*.dvc`, không commit credentials hoặc CSV.

## 8. GitHub Secrets, Variables và SSH fingerprint

Trong đúng repo: Settings -> Secrets and variables -> Actions.

### Repository Secrets

| Tên | Giá trị |
|---|---|
| AWS_ROLE_ARN | `terraform -chdir=infra output -raw github_role_arn` |
| ARTIFACT_BUCKET | Output `artifact_bucket`; chỉ tên bucket, không có s3:// |
| SERVER_HOST | Public IPv4 EC2 hiện tại |
| SERVER_USER | `ubuntu` |
| SERVER_SSH_KEY | Toàn bộ private key `infra/lab-key` |

### Repository Variables

| Tên | Giá trị |
|---|---|
| SECURITY_GROUP_ID | Output `security_group_id` |
| SERVER_SSH_FINGERPRINT | Fingerprint SHA256 host key ED25519 của EC2 |

Workflow hiện nhận hai Variables này từ Secrets nếu Variables không có giá trị. Nếu cả hai nơi có giá trị, Variables được ưu tiên. Giá trị chỉ đặt dưới GitHub Environment không tự áp dụng vì các jobs chưa khai báo environment.

Lấy fingerprint qua kết nối SSH tin cậy:

```powershell
ssh -i ".\infra\lab-key" "ubuntu@$ServerHost" `
  "sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256"
```

Chỉ chép phần `SHA256:...`, không chép số bit, tên máy hoặc `(ED25519)`.

RSA private key của client và ED25519 host key của server phục vụ hai mục đích khác nhau, không cần cùng thuật toán. Không dùng fingerprint của `lab-key.pub` cho SERVER_SSH_FINGERPRINT.

## 9. OIDC: khớp trust policy với token thực tế

GitHub Actions không dùng access key của user máy cá nhân. Hai jobs Train/Release có `id-token: write` và assume role qua OIDC.

Provider: `https://token.actions.githubusercontent.com`; audience: `sts.amazonaws.com`; trust action: `sts:AssumeRoleWithWebIdentity`.

GitHub có định dạng subject cũ dùng tên repo và định dạng immutable chứa owner/repo IDs. Không suy đoán định dạng hoặc mở wildcard để bỏ qua lỗi.

Nếu Authenticate to AWS báo `Not authorized to perform sts:AssumeRoleWithWebIdentity`:

1. Kiểm tra secret AWS_ROLE_ARN trỏ đúng output role GitHub.
2. Chạy workflow trên main; xem bước `Show OIDC trust claims` trong job Train.
3. Chép giá trị `sub` thực tế vào tfvars:

```hcl
github_oidc_subject = "GIA_TRI_SUB_DAY_DU_TU_LOG"
```

4. Chạy Terraform plan/apply để cập nhật trust policy:

```powershell
terraform "-chdir=infra" plan "-out=lab.tfplan"
terraform "-chdir=infra" apply "lab.tfplan"
```

5. Chạy lại workflow. Khi chỉ sửa cấu hình AWS hoặc GitHub Variables/Secrets, có thể Re-run failed jobs. Khi sửa YAML, push commit mới rồi chạy workflow của commit mới.

Bước chẩn đoán chỉ in iss/aud/sub/repository/ref và mask token. Không gửi hoặc chụp JWT/access key/private key.

## 10. Commit và kích hoạt pipeline

Kiểm tra trước khi push:

```powershell
python -m pytest tests/ -v
git diff --check
```

Ví dụ stage các file lab:

```powershell
git add .github/workflows/cicd.yml src/train.py src/serve.py tests/test_train.py
git add requirements.txt params.yaml .gitignore
git add .dvc/config .dvc/.gitignore .dvcignore data/*.dvc
git add infra/main.tf infra/variables.tf infra/outputs.tf
git add infra/user_data.sh infra/.terraform.lock.hcl
git diff --cached --stat
git commit -m "feat: configure AWS model CI/CD"
git push origin main
```

Giữ `.terraform.lock.hcl` trong Git. Không stage state, plan, tfvars hay private key. `.gitignore` hiện bỏ qua `infra/lab-key`; nếu đổi tên private key, bổ sung tên mới.

Workflow chạy khi push main có thay đổi paths được khai báo hoặc Actions -> Income Model CI/CD -> Run workflow -> main. Push chỉ sửa runbook/Terraform không tự kích hoạt workflow hiện tại; dùng Run workflow khi cần.

### Quan sát Release

1. Kiểm tra deployment configuration đầy đủ.
2. Assume GitHub role qua OIDC.
3. Lấy public IP runner GitHub và mở TCP 22 chỉ cho IP đó /32.
4. Scan host key và so sánh với fingerprint đã cấu hình.
5. Copy `src/serve.py`, upload model từ GitHub artifact lên S3.
6. SSH restart `income-api`, thử health check tối đa 20 lần.
7. Đóng rule SSH tạm và xóa private key khỏi runner.

Runner IP là máy GitHub Actions, khác admin_cidr của máy bạn. Workflow dùng concurrency để tránh hai releases ghi model đồng thời. Nếu runner bị dừng đột ngột, kiểm tra và xóa rule SSH tạm còn sót. Cấu hình hiện tại chưa có rollback tự động: nếu health check thất bại sau publish, S3 current đã bị ghi đè.

## 11. Kiểm tra API và model

Trong EC2:

```bash
sudo systemctl status income-api --no-pager
sudo journalctl -u income-api -n 100 --no-pager
curl -fsS http://localhost:8080/healthz
```

Trên máy cá nhân:

```powershell
$ServerHost = terraform "-chdir=infra" output -raw server_host
curl.exe "http://${ServerHost}:8080/healthz"
curl.exe -X POST "http://${ServerHost}:8080/score" `
  -H "Content-Type: application/json" `
  --data-raw '{"features":[28,2,14,2,11,0,1,0,0,45]}'
```

Nếu PowerShell truyền JSON không đúng cho curl.exe, dùng:

```powershell
Invoke-RestMethod `
  -Uri "http://${ServerHost}:8080/score" `
  -Method Post `
  -ContentType "application/json" `
  -Body '{"features":[28,2,14,2,11,0,1,0,0,45]}'
```

Health trả status ok. Score trả prediction 0 hoặc 1 với label tương ứng; không giả định mọi model đều dự đoán cùng nhãn. API nhận đúng 10 đặc trưng theo thứ tự trong serve.py. API HTTP cổng 8080 chỉ mở cho admin_cidr để kiểm tra lab; triển khai dùng chung cần TLS và cơ chế xác thực phù hợp.

Kiểm tra model trên S3 bằng CLI:

```powershell
aws s3api head-object --bucket $LabBucket --key artifacts/current/model.joblib
```

## 12. Bảng xử lý lỗi

| Triệu chứng | Kiểm tra và cách xử lý |
|---|---|
| Terraform Too many command line arguments | Dùng `terraform plan "-out=lab.tfplan"`; -chdir là flag trước subcommand. |
| SSM GetParameter AccessDenied | User chạy Terraform cần quyền đọc public SSM parameter; thêm AmazonSSMReadOnlyAccess trong group lab. |
| Region ARN không như dự kiến | Kiểm tra provider, var.region, tfvars, DVC region, workflow và region của VPC/subnet. |
| pkg_resources missing | Cài requirements hoặc `python -m pip install "setuptools<82"`. |
| FallbackAsyncAdaptedQueuePool import error | Cài requirements hoặc `python -m pip install "sqlalchemy>=1.4,<2.1"`. |
| MLflow UI No runs logged | Train và UI phải cùng tracking URI; SQLite và mlruns là hai store riêng. |
| OIDC Assuming role lặp lại / Not authorized | Kiểm tra role ARN, provider và sub thực tế; apply trust policy khớp token. |
| Release Missing SECURITY_GROUP_ID/fingerprint | Thêm repository Variables/Secrets đúng tên; nếu đổi YAML cần chạy commit mới. |
| UnauthorizedOperation khi mở SSH | Apply policy github_deploy_network; role chỉ quản lý security group lab. |
| SSH không có hostname | Gán lại $ServerHost trong terminal hiện tại; in ra để kiểm tra. |
| SSH timeout | Kiểm tra IP, instance Running/status checks, SG, public subnet/IGW và admin_cidr hiện tại. |
| SSH Connection refused | Kiểm tra đúng IP, EC2 boot xong và sshd đang chạy; SG chặn thường gây timeout. |
| SSH Permission denied publickey | Kiểm tra user ubuntu, private key khớp key pair và key không cần nhập passphrase. |
| Fingerprint mismatch | Lấy host ED25519 fingerprint của đúng EC2; kiểm tra IP có đổi/tạo lại instance không. |
| dvc push/pull AccessDenied | Máy cá nhân cần quyền ghi dvc/; GitHub role cần ListBucket prefix dvc/ và GetObject dvc/*. |
| ModuleNotFoundError google.cloud trên EC2 | Serve AWS dùng boto3; bỏ import GCP và chạy lại release để copy code mới. |
| API không lên sau restart | Xem journalctl, file S3, EC2 role, ARTIFACT_BUCKET, Python dependencies và đường dẫn ExecStart. |
| API local ok nhưng máy cá nhân không gọi được | TCP 8080 phải cho phép public IP máy bạn trong admin_cidr. |
| Quality Gate fail nhưng accuracy cao | Kiểm tra F1 lớp dương; chọn params đạt F1 >= 0.65, không hạ gate theo accuracy. |

## 13. Ảnh nộp bài và báo cáo

Lưu ảnh tại `nop-bai/anh-chup-man-hinh/`:

| File | Nội dung |
|---|---|
| 01-mlflow-ui.png | Kết quả các lần thử siêu tham số Bước 1 |
| 02-actions-buoc-2.png | Bốn jobs Unit Test, Train, Quality Gate, Release xanh |
| 04-curl-api.png | Terminal có IP EC2, lệnh health/score và kết quả |
| 05-cloud-storage.png | S3 Console thấy dữ liệu dvc/ và artifacts/current/model.joblib |

Chụp S3: Console -> S3 -> Buckets -> bucket lab -> Objects. Chụp nội dung `dvc/` có hash objects/thư mục; chụp `artifacts/current/` có model.joblib và breadcrumb. Dùng Win+Shift+S, ghép hai ảnh bằng Paint thành 05-cloud-storage.png nếu cần. Không cần mở public bucket để chụp.

Tải report JSON từ artifact `report` của lần chạy tương ứng để điền báo cáo; không dùng số liệu tests. Mục 1 của `nop-bai/bao-cao.md` ghi các run Bước 1; phần so sánh Bước 2/Bước 3 dùng report của từng pipeline tương ứng.

## 14. Bước 3 và thay đổi sau triển khai

Theo `tasks/buoc-3.md` để thêm batch2. Workflow hiện chỉ pull batch1/holdout; train.py mặc định đọc batch1. Dvc push batch2 đơn thuần không làm model tự học thêm dữ liệu; cần cập nhật quy trình dữ liệu/huấn luyện theo Bước 3.

Nếu đổi region/bucket: cập nhật Terraform, DVC remote, workflow, service environment và GitHub Secrets. Nếu IP máy cá nhân đổi: sửa admin_cidr trong tfvars rồi plan/apply khi không có release đang chạy.

## 15. Dọn tài nguyên

EC2, EBS, public IPv4 và S3 có thể phát sinh phí. Stop EC2 không xóa EBS/S3. Lưu report, ảnh nộp bài và dữ liệu cần giữ trước khi dọn.

```powershell
terraform "-chdir=infra" plan -destroy
terraform "-chdir=infra" destroy
```

Đây là thao tác xóa hạ tầng thật; chỉ chạy sau khi hoàn thành lab. Bucket có force_destroy=false nên destroy có thể bị chặn nếu còn objects. Chủ động sao lưu/xóa đúng dữ liệu bucket lab trước khi tiếp tục; nếu bật versioning, cần xử lý cả versions/delete markers. Giữ Terraform state tới khi dọn xong để quản lý tài nguyên còn lại.

Sau khi dọn, thu hồi access key và quyền rộng của user lab. Không xóa OIDC provider dùng chung bởi dự án khác; cấu hình github_oidc_provider_arn cho provider có sẵn để Terraform không sở hữu nó.

## 16. Tài liệu tham khảo

- [Terraform install](https://developer.hashicorp.com/terraform/install)
- [Terraform plan](https://developer.hashicorp.com/terraform/cli/commands/plan)
- [Terraform state và dữ liệu nhạy cảm](https://developer.hashicorp.com/terraform/language/manage-sensitive-data)
- [Canonical Ubuntu AMI](https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/)
- [AWS IAM role cho EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)
- [AWS S3 Block Public Access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)
- [GitHub OIDC với AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
- [GitHub OIDC subject và immutable IDs](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims)
- [AWS configure-aws-credentials](https://github.com/aws-actions/configure-aws-credentials)
- [AWS authorize-security-group-ingress](https://docs.aws.amazon.com/cli/latest/reference/ec2/authorize-security-group-ingress.html)
- [AWS revoke-security-group-ingress](https://docs.aws.amazon.com/cli/latest/reference/ec2/revoke-security-group-ingress.html)

Tài liệu lab: [Bước 2](buoc-2.md), [Bước 3](buoc-3.md).
