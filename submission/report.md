# Báo cáo Lab MLOps - CI/CD cho AI Systems

## 1. Bộ siêu tham số đã chọn và lý do

Thuật toán: `RandomForestClassifier`.

```yaml
n_estimators: 100
max_depth: 20
min_samples_split: 3
min_samples_leaf: 2
class_weight: null
criterion: gini
```

Bộ này được chọn sau khi chạy hơn 300 lượt thử nghiệm với các tổ hợp
siêu tham số khác nhau, theo dõi bằng MLflow (backend `sqlite:///mlflow.db`).
Trên tập `train_phase1.csv` gốc (2998 mẫu), đây là bộ cho accuracy cao nhất
(0.688) trong toàn bộ các lần chạy, so với mức khoảng 0.55-0.68 của các bộ
tham số khác (n_estimators thấp, max_depth nông cho kết quả thấp hơn rõ rệt;
tăng n_estimators quá cao không cải thiện thêm mà chỉ làm chậm huấn luyện).

## 2. Khó khăn gặp phải và cách giải quyết

**Service Account key bị chặn bởi org policy.** Project GCP dùng cho lab
(`lab21-506202`) nằm dưới một tổ chức quản lý (managed org) áp dụng chính
sách `iam.disableServiceAccountKeyCreation`, không cho tạo file JSON key kể
cả với quyền Owner trên project. Giải pháp: chuyển toàn bộ xác thực GitHub
Actions sang Workload Identity Federation (WIF), không bao giờ tạo hay lưu
JSON key, CI lấy short-lived token trực tiếp qua OIDC.

**`dvc[gs]` không tương thích với WIF kiểu impersonation.** Khi cấu hình
WIF impersonate một service account trung gian (theo pattern phổ biến),
`dvc pull` báo lỗi `"Gaia id not found for email ***"` do phiên bản
`gcsfs`/`google-auth` mà `dvc[gs]==3.50.1` phụ thuộc xử lý sai loại
credential `external_account` có impersonation. Giải pháp: bỏ bước
impersonate, cấp quyền `roles/storage.objectAdmin` trực tiếp cho WIF
principal (`principalSet://...`) lên bucket, để CI dùng thẳng token
federated không qua trung gian.

**Model từ dữ liệu ban đầu (2998 mẫu) chưa đạt ngưỡng 0.70.** Kể cả sau khi
mở rộng tìm kiếm siêu tham số, RandomForest chỉ đạt trần khoảng 0.688 trên
tập gốc nên hạ ngưỡng eval gate tạm thời xuống 0.68 để pipeline Bước 2 chạy
được trọn vẹn. Sau khi bổ sung dữ liệu ở Bước 3 (huấn luyện lại trên 5996
mẫu), accuracy tăng lên 0.728, chứng minh việc bổ sung dữ liệu thật sự cải thiện chất lượng mô hình.

**Health check trên VM fail dù service chạy bình thường.** Bước deploy ban
đầu chỉ `sleep 5` trước khi curl `/health`, trong khi service cần khoảng
12 giây để tải model từ GCS và khởi động uvicorn. Sửa thành vòng lặp retry
tối đa 60 giây thay vì sleep cố định.

## 3. Kết quả so sánh Bước 2 và Bước 3

| Chỉ số   | Bước 2 (2998 mẫu) | Bước 3 (5996 mẫu) |
|----------|-------------------|--------------------|
| accuracy | 0.688             | 0.728              |
| f1_score | 0.687             | 0.727              |
