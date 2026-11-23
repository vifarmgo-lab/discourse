# VNBot Community · vận hành danh hiệu, VIP và lượt nhắc

## Dành cho ban quản trị

- [Huy hiệu](https://community.vnbot.run/admin/badges) cho phép trao Expert, Master, Guru. Thành viên có thể chọn huy hiệu làm danh hiệu trên hồ sơ. Mỗi lần xét cần một đề cử, dẫn chứng công khai hoặc nội bộ phù hợp và người duyệt. Trao danh hiệu không thay đổi quyền vào lớp, quyền VIP hay quyền quản trị.
- [Hướng dẫn vận hành nội bộ](https://community.vnbot.run/t/18) có tiêu chí từng hạng và quy trình thu hồi khi trao nhầm.
- [Sổ thời hạn VIP](https://community.vnbot.run/t/17) ghi username và ngày hết hạn đã duyệt. Quyền thực tế nằm trong [nhóm vnbot_vip](https://community.vnbot.run/g/vnbot_vip/members). Chủ đề trong [khu VIP](https://community.vnbot.run/c/10) chỉ dành cho nhóm và staff. Với tài liệu nhạy cảm dùng nơi lưu có kiểm tra quyền tải.
- Lúc 09:00 ngày 1 hằng tháng theo giờ Việt Nam, diễn đàn tạo hoặc cập nhật một báo cáo riêng cho staff về thành viên thiếu hạn, đã hết hạn, sắp hết hạn trong 30 ngày hoặc có trong sổ mà chưa có quyền. Admin xác nhận trước khi cấp, gia hạn hay gỡ. Có thể chạy lại ngay bằng `systemctl start vnbot-community-vip.service`. [Báo cáo tháng 11/2026](https://community.vnbot.run/t/19).

## Dành cho người quản trị tích hợp

1. Trên GDATA, chạy `vip.sh` để thiết lập nhóm, huy hiệu, chủ đề nội bộ và timer. Chạy `mentions.sh` để cài plugin phục vụ diễn đàn. Bộ cài kiểm tra hostname, chạy kiểm thử tải quyền trong giao dịch hoàn tác và chỉ nạp lại dịch vụ sau khi đạt.
2. Trên VNBot.run, dùng bot **VNBot** trong workspace **VNBot Community**, routine **Trả lời khi được nhắc trên Community**. Chỉ dùng URL và header của routine này để chạy `connect.py` trong console GDATA. Trường nhập ẩn. Không lưu các giá trị này trong Git, bài diễn đàn hay tài liệu.
3. Một lượt nhắc thật trong [Hỏi đáp & báo lỗi](https://community.vnbot.run/c/hoi-dap-bao-loi/6) tạo sự kiện. Payload mang câu hỏi, trích đoạn công khai tính đến bài vừa nhắc và tối đa ba chủ đề gợi ý trong cùng chuyên mục. Hỏi bot tóm tắt chủ đề hoặc gợi ý bài liên quan. Bot không nhận bài ở lớp, VIP, Staff, tin nhắn riêng hoặc ghi chú của moderator.
4. Agent gửi `POST /vnbot-community/reply` với JSON `post_id` và `answer`. Token một lượt nằm trong header Authorization. Diễn đàn kiểm tra lại quyền, trạng thái, nội dung và thời hạn trước khi đăng. Trả `201` khi đăng thành công, `200` khi nhận lại cùng kết quả, `409/410` khi nguồn bị thay đổi hoặc không còn đủ điều kiện, `403` khi sai xác thực. Không ghi header, token hay URL chứa bí mật vào nhật ký.
5. Khi thay đổi phiên bản, chạy lại `mentions/verify.rb` trong Rails runner. Sau khi kết nối hoặc đổi khóa phải thử một lượt nhắc thật và xác nhận câu trả lời xuất hiện đúng chủ đề, đúng tài khoản, đúng một lần. Khi tạm dừng, di chuyển file kết nối riêng khỏi vị trí `/shared/vnbot-community/mention-connection.json` và giữ trong kho bí mật an toàn. Các callback còn chờ ngừng đăng khi cấu hình bị ngắt.
