# VNBot Community

Các tệp trong thư mục này dùng cho bản beta của `community.vnbot.run`. Lõi dùng bộ cài Docker chính thức của Discourse. Cấu hình beta được áp dụng cho diễn đàn sau khi cài xong.

## Kiểm tra và cài đặt

1. Chạy `bash preflight.sh TEN_MAY` trên VPS đích. Đọc danh sách cổng, tiến trình Docker và dung lượng đĩa trước khi chạy bộ cài.
2. Trên máy GDATA dành riêng cho diễn đàn, chạy `bash install.sh` rồi nhập email đã được chủ dự án chọn. Bộ cài dùng Docker chính thức của Discourse, dựng HTTPS và áp dụng cấu hình beta. Chủ tài khoản xác nhận đúng email qua Discourse ID. Nếu cần gửi thư mời hoặc đặt lại mật khẩu qua email, cấu hình riêng dịch vụ SMTP với tên miền đã xác minh.
3. Để chạy lại phần thiết lập chuyên mục sau khi container đã sẵn sàng, dùng các lệnh dưới đây từ thư mục chứa tệp.

```sh
docker cp bootstrap.rb app:/tmp/vnbot-community-bootstrap.rb
docker exec -u discourse -w /var/www/discourse app bundle exec rails runner /tmp/vnbot-community-bootstrap.rb
```

Script tạo bốn khu công khai và một khu lớp giới hạn theo nhóm. Các thành viên trong nhóm lớp do quản trị viên hoặc chủ nhóm được ủy quyền thêm. Script không tạo người dùng, không cấp quyền quản trị và không gửi thư mời. Bản thử bật chế độ chỉ đăng ký bằng lời mời. Muốn thử đăng ký, hãy tạo lời mời giới hạn theo địa chỉ nhận được phê duyệt.

## Nhận diện, kho ảnh và sao lưu

Chạy `bash check.sh brand` trên AI-Server01 để áp dụng logo sáng/tối và favicon từ trang chính VNBot. Bước này cũng kiểm tra chuyên mục, phân quyền đọc/đăng, ngôn ngữ và giao diện.

Chạy `bash storage.sh` để kết nối hai bucket R2 riêng tư. Nhập endpoint và khóa S3 tại Console. Khóa cần quyền Object Read & Write cho đúng hai bucket, có thể giới hạn IP ở địa chỉ ra Internet của VPS. Tệp đăng trên diễn đàn được phục vụ từ VPS. Mỗi giờ máy chép tệp mới hoặc đã thay đổi lên `vnbot-community-media/uploads/` và các bản backup hoàn chỉnh lên `vnbot-community-backup/default/`. Discourse tạo backup hằng ngày. Khi muốn sao chép ngay, chạy `systemctl start vnbot-community-storage.service`.

Chạy `bash check.sh restore` để tạo bản sao lưu, đọc lại từ R2, so sánh với tệp gốc và phục hồi SQL vào PostgreSQL trong một container thử tách mạng. Kiểm tra quyền lớp ở cả cấp bài viết và đường dẫn tệp trước khi chia sẻ tệp riêng. Trong thời gian thử nghiệm, tài liệu riêng của lớp dùng liên kết kiểm tra quyền tại nguồn.

Tên người dùng SMTP, mật khẩu, API token, khóa R2 và cấu hình app.yml thật lưu trên máy triển khai hoặc trình quản lý bí mật.

## Nghiệm thu trước beta

- HTTPS hợp lệ. Một lời mời thử tới đúng hộp thư, thành viên kích hoạt, đăng xuất, đặt lại mật khẩu và đăng nhập lại được.
- Thành viên thường đọc thông báo và đăng trong khu hỏi đáp. Moderator thấy bài đầu cần duyệt. Thử đăng ảnh, nhúng YouTube, đánh dấu lời giải và mở link skill trên điện thoại.
- Dùng hai tài khoản để thử khu lớp. Tài khoản ngoài nhóm không mở được bài hay tệp riêng, kể cả bằng URL trực tiếp. Gỡ thành viên thử ra khỏi nhóm rồi kiểm tra lại.
- Tạo backup. Khôi phục trên một instance thử với bucket tách biệt, tắt gửi email và webhook. Đối chiếu tài khoản, quyền nhóm, bài và media. Chỉ mời nhóm beta thật sau khi các kiểm tra đạt.
