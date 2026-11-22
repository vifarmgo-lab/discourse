# VNBot Community

Các tệp trong thư mục này dùng cho bản beta của `community.vnbot.run`. Lõi dùng bộ cài Docker chính thức của Discourse. Cấu hình beta được áp dụng cho diễn đàn sau khi cài xong.

## Kiểm tra và cài đặt

1. Chạy `bash preflight.sh TEN_MAY` trên VPS đích. Đọc danh sách cổng, tiến trình Docker và dung lượng đĩa trước khi chạy bộ cài.
2. Dùng [hướng dẫn self-host Discourse](https://github.com/discourse/discourse/blob/main/docs/INSTALL-cloud.md) trên máy đã xác nhận. Chọn hostname `community.vnbot.run`, địa chỉ quản trị thuộc AIKING và SMTP đã xác thực. Tạo quản trị viên ban đầu trước khi mời thành viên.
3. Sau khi forum hoạt động, chép `bootstrap.rb` vào máy và chạy các lệnh dưới đây từ thư mục chứa tệp. Ví dụ này dùng tên container mặc định `app`.

```sh
docker cp bootstrap.rb app:/tmp/vnbot-community-bootstrap.rb
docker exec -u discourse -w /var/www/discourse app bundle exec rails runner /tmp/vnbot-community-bootstrap.rb
```

Script tạo bốn khu công khai và một khu lớp giới hạn theo nhóm. Các thành viên trong nhóm lớp do quản trị viên hoặc chủ nhóm được ủy quyền thêm. Script không tạo người dùng, không cấp quyền quản trị và không gửi thư mời. Bản thử bật chế độ chỉ đăng ký bằng lời mời. Muốn thử đăng ký, hãy tạo lời mời giới hạn theo địa chỉ nhận được phê duyệt.

## Nhận diện, kho ảnh và sao lưu

Bật Horizon và tiếng Việt bằng script. Chọn logo từ tài sản đang hiển thị tại [trang chính VNBot](https://vnbot.run/). Nạp logo trong phần nhận diện của quản trị và kiểm tra cả hai chế độ sáng/tối.

Áp dụng [cấu hình Cloudflare R2 của Discourse](https://meta.discourse.org/t/configure-an-s3-compatible-object-storage-provider-for-uploads/148916) cho đúng môi trường. Hai bucket riêng cho media và backup dùng các thiết lập `DISCOURSE_S3_UPLOAD_BUCKET` và `DISCOURSE_S3_BACKUP_BUCKET`. Bật `DISCOURSE_ENABLE_S3_UPLOADS`. Chọn `DISCOURSE_BACKUP_LOCATION=s3` sau khi ứng dụng đọc/ghi được bucket backup. Giữ bucket backup riêng tư. Giữ bản sao độc lập của media. Chỉ nhận tệp riêng của lớp qua hệ thống kiểm tra quyền truy cập. Kiểm thử cả URL tệp đã sao chép trước khi đưa tài liệu thật vào lớp.

Tên người dùng SMTP, mật khẩu, API token, khóa R2 và cấu hình app.yml thật lưu trên máy triển khai hoặc trình quản lý bí mật.

## Nghiệm thu trước beta

- HTTPS hợp lệ. Một lời mời thử tới đúng hộp thư, thành viên kích hoạt, đăng xuất, đặt lại mật khẩu và đăng nhập lại được.
- Thành viên thường đọc thông báo và đăng trong khu hỏi đáp. Moderator thấy bài đầu cần duyệt. Thử đăng ảnh, nhúng YouTube, đánh dấu lời giải và mở link skill trên điện thoại.
- Dùng hai tài khoản để thử khu lớp. Tài khoản ngoài nhóm không mở được bài hay tệp riêng, kể cả bằng URL trực tiếp. Gỡ thành viên thử ra khỏi nhóm rồi kiểm tra lại.
- Tạo backup. Khôi phục trên một instance thử với bucket tách biệt, tắt gửi email và webhook. Đối chiếu tài khoản, quyền nhóm, bài và media. Chỉ mời nhóm beta thật sau khi các kiểm tra đạt.
