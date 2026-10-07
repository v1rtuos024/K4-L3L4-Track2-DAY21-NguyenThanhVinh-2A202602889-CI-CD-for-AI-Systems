# Báo Cáo Lab Day 21 - CI/CD cho AI Systems

| Thông tin | Nội dung |
|---|---|
| Họ và tên | Nguyễn Thành Vinh |
| MSSV | 2A202602889 |
| Lớp / Khóa | K4 |
| Repo GitHub | https://github.com/v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems |
| Ngày lập báo cáo | 07/10/2026 |

## 1. Bộ Siêu Tham Số Đã Chọn và Lý Do

Kết quả thực nghiệm GradientBoostingClassifier trên cùng tập holdout 500 mẫu được ghi nhận bằng MLflow:

| Lần chạy | n_estimators | learning_rate | max_depth | f1_score | accuracy |
|---|---|---|---|---|---|
| 1 | 100 | 0.1 | 3 | 0.710900 | 0.878 |
| 2 | 50 | 0.05 | 2 | 0.605128 | 0.846 |
| 3 | 200 | 0.1 | 5 | 0.714932 | 0.874 |

**Bộ đã chọn:** `n_estimators=200`, `learning_rate=0.1`, `max_depth=5`.

**Lý do:** Lần 3 đạt F1 cao nhất và vượt ngưỡng 0.65. Lần 1 có accuracy cao nhất nhưng F1 thấp hơn, nên không được chọn. Cấu hình 50 cây, learning rate 0.05 đạt F1 thấp nhất; tuy nhiên, cả độ sâu cũng thay đổi nên chưa thể tách riêng tác động từng tham số. Learning rate nhỏ thường cần nhiều cây hơn để học đủ; tăng số cây và độ sâu cũng làm tăng chi phí huấn luyện.

## 2. Vì Sao Ngưỡng Chất Lượng Đặt Trên F1 Chứ Không Phải Accuracy

Dữ liệu Adult có khoảng 24,8% mẫu thu nhập trên 50K. Mô hình luôn dự đoán thu nhập thấp vẫn đạt accuracy khoảng 75,2%, dù bỏ sót toàn bộ lớp dương. F1 là trung bình điều hòa của precision và recall, phản ánh khả năng nhận diện người thu nhập cao; mô hình trên có F1 bằng 0. Vì vậy, quality gate dùng F1 lớp dương với ngưỡng 0.65. Hàm `f1_score` sử dụng `average="binary"`, lớp dương là 1; weighted F1 chịu ảnh hưởng lớp đông, còn macro F1 gộp hai lớp, không đo riêng mục tiêu của gate. Release phụ thuộc Quality Gate nên bị chặn khi F1 không đạt.

## 3. Khó Khăn Gặp Phải và Cách Giải Quyết

| Khó khăn | Nguyên nhân | Cách giải quyết |
|---|---|---|
| GitHub Actions không assume được AWS role. | OIDC subject chưa khớp trust policy. | Đọc claims thực tế và cấu hình subject chính xác. |
| Release thiếu cấu hình triển khai. | Workflow chỉ đọc secrets trong khi giá trị nằm ở variables. | Bổ sung đọc variables hoặc secrets và kiểm tra trước release. |

## 4. So Sánh Bước 2 và Bước 3

Số liệu được xác minh từ log Train của [Bước 2](https://github.com/v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems/actions/runs/37583433357) và [Bước 3](https://github.com/v1rtuos024/K4-L3L4-Track2-Day21-CI-CD-for-AI-Systems/actions/runs/37585600416).

| Giai đoạn | f1_score | accuracy |
|---|---|---|
| Bước 2: 22.361 mẫu | 0.714932 | 0.874 |
| Bước 3: 44.722 mẫu | 0.735426 | 0.882 |

**Nhận xét:** Sau khi thêm 22.361 mẫu, F1 tăng 0.020494 và accuracy tăng 0.008 trên cùng holdout. Commit cập nhật con trỏ DVC kích hoạt cả bốn jobs thành công và triển khai lại API trên EC2. Kết quả cho thấy dữ liệu bổ sung có ích trong lần thử này, nhưng không bảo đảm thêm dữ liệu luôn cải thiện mô hình.
