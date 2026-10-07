# Bước 3 - Huấn Luyện Liên Tục Khi Có Dữ Liệu Mới

Mục tiêu: Mô phỏng vai trò của một kỹ sư dữ liệu bổ sung thêm dữ liệu mới. Chỉ cần một lần `git push` là pipeline tự động huấn luyện lại và triển khai lại mà không cần bất kỳ thao tác thủ công nào.

---

## 3.1 Tìm Hiểu Quy Trình Trước Khi Bắt Đầu

Trước khi thực hiện, hãy đọc lại workflow trigger trong `.github/workflows/cicd.yml`:

```yaml
on:
  push:
    branches: [main]
    paths:
      - 'data/**.dvc'    # <- Pipeline được kích hoạt khi file .dvc thay đổi
      - 'src/**.py'
      - 'params.yaml'
```

Đây là chốt mấu chốt của Bước 3: khi bạn thay đổi nội dung file CSV và cập nhật file `.dvc` tương ứng, GitHub Actions sẽ tự động kích hoạt toàn bộ pipeline.

---

## 3.2 Thêm Dữ Liệu Mới

Script `append_batch.py` đã được cung cấp sẵn. Script này ghép `train_batch2.csv` (22.361 mẫu mới) vào `train_batch1.csv`:

```bash
python append_batch.py
```

Kết quả mong đợi:

```
Cap nhat du lieu: 22361 -> 44722 mau
```

Xác nhận kích thước dữ liệu mới:

```bash
wc -l data/train_batch1.csv
# Kết quả mong đợi: 44723 (44722 dòng dữ liệu + 1 dòng tiêu đề)
```

---

## 3.3 Phiên Bản Hóa Dữ Liệu Mới Và Kích Hoạt Pipeline

Đây là bước quan trọng nhất. Thực hiện theo đúng thứ tự:

```bash
# 1. Thông báo cho DVC rằng file dữ liệu đã thay đổi
dvc add data/train_batch1.csv

# 2. Commit file con trỏ DVC đã cập nhật vào git
#    Lưu ý: commit file .dvc, KHÔNG phải file CSV
git add data/train_batch1.csv.dvc
git commit -m "data: bổ sung 22361 mẫu dữ liệu mới (train_batch2)"

# 3. Đẩy dữ liệu mới lên cloud storage trước
#    Bước này đảm bảo CI runner có thể pull dữ liệu mới khi pipeline bắt đầu
dvc push

# 4. Đẩy git commit lên GitHub - thao tác này kích hoạt GitHub Actions
git push origin main
```

Tại sao phải `dvc push` trước `git push`? Nếu git push được thực hiện trước, GitHub Actions sẽ bắt đầu và cố gắng `dvc pull` dữ liệu mới khi dữ liệu đó chưa có trên cloud storage, dẫn đến lỗi.

---

## 3.4 Theo Dõi Pipeline Phản Ứng

Vào tab **Actions** trên repo GitHub. Trong vài giây sau khi push, pipeline sẽ tự động bắt đầu.

Xác nhận commit message trong pipeline khớp với commit vừa tạo:

```
data: bổ sung 22361 mẫu dữ liệu mới (train_batch2)
```

Điều này chứng minh pipeline được kích hoạt bởi commit dữ liệu, không phải commit code.

Theo dõi từng job:

1. **Unit Test** - unit tests chạy trên code hiện tại (không thay đổi so với Bước 2).
2. **Train** - CI runner pull tập dữ liệu mới (44.722 mẫu) từ cloud storage, huấn luyện lại mô hình, upload `model.joblib` mới lên cloud storage.
3. **Quality Gate** - kiểm tra `f1_score >= 0.65`, nếu không đạt thì pipeline dừng tại đây.
4. **Release** - nếu quality gate qua, service trên VM được restart với mô hình mới.

---

## 3.5 Xác Nhận Mô Hình Mới Đã Được Triển Khai

Sau khi pipeline hoàn thành:

```bash
VM_IP=<YOUR_VM_IP>

# Kiểm tra server đang chạy
curl http://$VM_IP:8080/healthz

# Gửi yêu cầu dự đoán
curl -X POST http://$VM_IP:8080/score \
  -H "Content-Type: application/json" \
  -d '{"features": [28, 2, 14, 2, 11, 0, 1, 0, 0, 45]}'
```

Mô hình mới huấn luyện trên 44.722 mẫu sẽ được phục vụ. Không có bất kỳ thao tác thủ công nào cần thiết.

---

## 3.6 So Sánh Kết Quả

Tải file `outputs/report.json` từ artifacts của hai lần chạy để so sánh:

| Chỉ số | Bước 2 (22.361 mẫu) | Bước 3 (44.722 mẫu) |
|---|---|---|
| f1_score | 0.71493 | 0.73542 |
| accuracy | 0.874 | 0.882 |

Điền vào bảng trên dựa trên kết quả thực tế của bạn.

**Đừng giả định rằng thêm dữ liệu sẽ luôn làm mô hình tốt hơn.** Với bộ dữ liệu này, hai nửa dữ liệu được chia ngẫu nhiên từ cùng một nguồn, nên chúng có cùng phân phối. Gấp đôi dữ liệu trong tình huống đó thường chỉ làm chỉ số dao động trong khoảng nhỏ, thậm chí giảm nhẹ — mô hình đã học gần hết những gì có thể học từ 22.361 mẫu đầu tiên.

Trong báo cáo, hãy trả lời: kết quả của bạn tăng hay giảm, và bạn giải thích điều đó thế nào? Một câu trả lời trung thực "f1 giảm 0,01 vì dữ liệu mới cùng phân phối, không mang thêm thông tin mới" được đánh giá cao hơn một kết luận sai rằng thêm dữ liệu luôn tốt hơn.

Điều thực sự được kiểm chứng ở Bước 3 không phải là chỉ số cao hơn, mà là **quy trình tự động chạy đúng**: dữ liệu mới đi hết một vòng từ commit đến sản phẩm đang phục vụ, không cần ai can thiệp.

---

## Xử Lý Sự Cố

**Pipeline Bước 3 không được kích hoạt**

Xác nhận bạn đã commit file `.dvc`, không phải file CSV:

```bash
git log --name-only -1
```

Kết quả mong đợi:

```
data/train_batch1.csv.dvc
```

Nếu thấy `data/train_batch1.csv`, bạn đã commit nhầm file. Thêm file CSV vào `.gitignore` và commit lại.

**Lỗi `dvc push` - file quá lớn**

Không có vấn đề. Các cloud provider đều hỗ trợ file có kích thước lớn trong gói miễn phí/trial. Kiểm tra lại xác thực:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=sa-key.json
dvc push
```

**f1_score ở Bước 3 thấp hơn Bước 2**

Đây là tình huống bình thường, xem giải thích ở mục 3.6. Model vẫn được triển khai nếu `f1_score` vẫn >= 0.65. Nếu tụt xuống dưới ngưỡng thì bước Release sẽ bị chặn - đây là hành vi mong muốn của quality gate, không phải lỗi của bạn.

---

## Tóm Tắt Những Gì Bạn Đã Xây Dựng

Sau khi hoàn thành cả ba bước, bạn đã xây dựng một hệ thống MLOps có khả năng hoạt động trong thực tế:

```
Bước 1 - Thực nghiệm cục bộ
  MLflow ghi lại mọi thí nghiệm trên máy cá nhân.
  So sánh nhiều bộ siêu tham số và chọn bộ tốt nhất.
  Chọn đúng chỉ số đánh giá cho dữ liệu mất cân bằng lớp.

Bước 2 - CI/CD tự động
  Push code -> GitHub Actions huấn luyện trên môi trường sạch.
  DVC quản lý phiên bản dữ liệu, đảm bảo khả năng tái tạo.
  Quality gate: chỉ các mô hình đạt f1_score >= 0.65 mới được triển khai.
  FastAPI trên Cloud VM phục vụ dự đoán qua REST API.

Bước 3 - Huấn luyện liên tục
  Thêm dữ liệu mới -> cập nhật DVC -> git push.
  Toàn bộ pipeline Bước 2 chạy lại hoàn toàn tự động.
  VM luôn phục vụ mô hình mới nhất đã qua kiểm tra chất lượng.
```

Đây là vòng phản hồi cơ bản của một hệ thống MLOps trong thực tế sản xuất: dữ liệu mới -> huấn luyện -> kiểm tra chất lượng -> triển khai tự động.

---

## Kết Quả Cần Đạt - Bước 3

- Chụp màn hình một lần chạy GitHub Actions được kích hoạt bởi commit dữ liệu, lưu thành
  `nop-bai/anh-chup-man-hinh/03-actions-buoc-3.png`.
  Xác nhận: commit message hiển thị trong tên của lần chạy Actions là commit dữ liệu của bạn.
- Cả bốn jobs (Unit Test, Train, Quality Gate, Release) đều hoàn thành thành công.
- So sánh f1_score giữa Bước 2 và Bước 3 đã được điền vào bảng ở mục 3.6, kèm giải thích.

---

## Hoàn Tất Hồ Sơ Nộp Bài

Đến đây bạn đã có đủ dữ liệu để hoàn thiện phần nộp bài:

1. Kiểm tra đủ 5 ảnh trong [nop-bai/anh-chup-man-hinh/](../nop-bai/anh-chup-man-hinh/),
   đúng tên file và đúng thứ tự.
2. Điền nốt [nop-bai/bao-cao.md](../nop-bai/bao-cao.md) — đặc biệt là mục 4 (so sánh Bước 2
   và Bước 3), rồi xóa toàn bộ các khối chú thích hướng dẫn và kiểm tra báo cáo không vượt
   quá 1 trang A4.
3. Đi hết checklist trong [nop-bai/README.md](../nop-bai/README.md) trước khi `git push`.

---

Quay lại: [Bước 2 - Pipeline CI/CD tự động](buoc-2.md)
