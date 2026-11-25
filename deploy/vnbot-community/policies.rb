# frozen_string_literal: true

# Run in the Community Rails environment. Staff can edit the source posts after publication.
raise "Unexpected forum" unless URI(Discourse.base_url).host == "community.vnbot.run"

pages = {
  privacy_topic_id: {
    title: "Chính sách quyền riêng tư của VNBot Community",
    raw: <<~MARKDOWN,
      Chính sách này áp dụng cho diễn đàn **community.vnbot.run** do AIKING vận hành. Bài viết và tệp bạn gửi lên diễn đàn được lưu trên hệ thống Community.

      ## Diễn đàn xử lý dữ liệu gì?

      Khi bạn tạo tài khoản, Community lưu địa chỉ email, tên người dùng và các thông tin bạn tự thêm vào hồ sơ. Nếu bạn chọn đăng nhập qua một dịch vụ khác, diễn đàn nhận thông tin tài khoản mà dịch vụ đó cung cấp để xác thực và liên kết tài khoản của bạn.

      Community lưu bài viết, phản hồi, tệp đính kèm và các tương tác bạn thực hiện. Cookie giúp duy trì phiên đăng nhập và ghi nhớ lựa chọn của bạn. Nhật ký kỹ thuật có thể gồm địa chỉ IP, thời điểm truy cập và thông tin trình duyệt. Đội vận hành dùng các thông tin này để cung cấp diễn đàn, xử lý báo lỗi, bảo vệ tài khoản và hạn chế spam.

      ## Ai có thể xem nội dung?

      Bài bạn đăng ở chuyên mục công khai có thể được bất kỳ ai đọc, sao chép hoặc tìm thấy qua công cụ tìm kiếm. Bài trong lớp riêng được giới hạn theo quyền của nhóm. Đường dẫn tệp đính kèm có thể có phạm vi truy cập khác với bài viết. Với giáo trình giới hạn người xem hoặc tài liệu khách hàng, hãy dùng liên kết có kiểm tra quyền tại nơi lưu. Trước khi gửi ảnh chụp màn hình, hãy che email, số điện thoại, khóa API và thông tin khách hàng.

      ## Lưu trữ, gửi thư và sao lưu

      Community chạy trên GDATA. Bản sao lưu của diễn đàn và tệp tải lên được lưu ngoài máy chủ trên Cloudflare R2 để phục hồi khi có sự cố. Community sử dụng Resend để gửi thư, chẳng hạn như lời mời và thông báo tài khoản. Dữ liệu đã chỉnh sửa hoặc gỡ trên diễn đàn có thể còn trong bản sao lưu trước đó.

      ## Xem, chỉnh sửa hoặc yêu cầu xử lý dữ liệu

      Bạn có thể chỉnh sửa thông tin hồ sơ và lựa chọn nhận thông báo trong phần thiết lập tài khoản. Để yêu cầu truy cập, chỉnh sửa hoặc xóa dữ liệu, hãy liên hệ riêng với quản trị viên được liệt kê tại [Giới thiệu về Community](/about). Nếu mất quyền đăng nhập, bạn có thể tìm kênh hỗ trợ tại [trang VNBot](https://vnbot.run/) và xin liên hệ riêng. Khi gửi yêu cầu, hãy cho biết tên tài khoản và nội dung cần xử lý. Đừng gửi mật khẩu, mã xác thực hoặc giấy tờ cá nhân vào nhóm công khai.

      [Điều khoản sử dụng của Community](/tos)
    MARKDOWN
  },
  tos_topic_id: {
    title: "Điều khoản sử dụng VNBot Community",
    raw: <<~MARKDOWN,
      VNBot Community là diễn đàn do AIKING vận hành để thành viên hỏi đáp, chia sẻ kinh nghiệm triển khai VNBot và tham gia các lớp được cấp quyền. Các điều khoản dưới đây áp dụng khi bạn sử dụng **community.vnbot.run**.

      ## Tài khoản và quyền truy cập

      Hãy bảo vệ thông tin đăng nhập của bạn và sử dụng diễn đàn bằng tài khoản của mình. Nếu nghi ngờ tài khoản bị người khác sử dụng, hãy liên hệ với [quản trị viên](/about). Chỉ chia sẻ nội dung của lớp riêng ra bên ngoài khi bạn có quyền làm việc đó.

      ## Nội dung bạn chia sẻ

      Chỉ đăng nội dung do bạn tạo hoặc có quyền sử dụng và chia sẻ. Khi trích dẫn, hãy ghi nguồn và tuân thủ điều kiện sử dụng của tác giả. Trước khi đăng ví dụ triển khai, tệp hoặc ảnh chụp, hãy kiểm tra quyền chia sẻ và loại bỏ thông tin cá nhân, bí mật kinh doanh, mật khẩu và khóa truy cập.

      ## Thảo luận và kiểm duyệt

      Hãy đăng đúng chuyên mục, trao đổi lịch sự và góp ý vào nội dung. Không mạo danh, quấy rối, gửi spam, phát tán nội dung trái phép hoặc tiết lộ thông tin riêng tư của người khác. Khi thấy bài vi phạm, hãy dùng chức năng báo cáo trên bài đó để đội điều hành xem xét. Quản trị viên có thể ẩn hoặc gỡ nội dung và hạn chế tài khoản vi phạm theo [Nội quy cộng đồng](/guidelines).

      ## Phản hồi và quyền riêng tư

      Để đề nghị xem xét một quyết định kiểm duyệt hoặc báo vấn đề liên quan đến nội dung của bạn, hãy liên hệ riêng với [quản trị viên Community](/about) và cung cấp đường dẫn đến bài liên quan. Việc thu thập, sử dụng và lưu trữ dữ liệu trên diễn đàn được mô tả trong [Chính sách quyền riêng tư](/privacy).
    MARKDOWN
  }
}

staff = Category.find(SiteSetting.staff_category_id)
raise "Expected a staff-only source category" unless staff.read_restricted?
linked_pages = {}
Topic.transaction do
  Topic.connection.execute("SELECT pg_advisory_xact_lock(3645291)")
  pages.each do |setting, page|
    current = SiteSetting.get(setting)
    if current.to_i > 0
      linked_pages[setting] = Topic.find(current)
      next
    end
    topic = Topic.find_by(category_id: staff.id, title: page.fetch(:title))
    if topic
      raise "Review existing policy topic #{topic.id}" unless topic.first_post.raw == page.fetch(:raw)
    else
      topic = PostCreator.create!(
        Discourse.system_user,
        title: page.fetch(:title), raw: page.fetch(:raw), category: staff.id,
        skip_validations: true, skip_jobs: true
      ).topic
    end
    linked_pages[setting] = topic
  end
end
linked_pages.each do |setting, topic|
  SiteSetting.set(setting, topic.id) if SiteSetting.get(setting).to_i < 1
  raise "Setting changed concurrently: #{setting}" unless SiteSetting.get(setting).to_i == topic.id
  puts "#{setting}=#{topic.id}"
end
