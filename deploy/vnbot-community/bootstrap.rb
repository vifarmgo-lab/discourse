# frozen_string_literal: true

# Run inside the official Discourse container: bin/rails runner /tmp/bootstrap.rb
# Only prepares local community content. SMTP, DNS and object storage are configured separately.
unless Discourse.current_hostname == "community.vnbot.run"
  abort "Set the forum hostname to community.vnbot.run before running this bootstrap."
end

class VNBotCommunityBeta
  GROUP = "vnbot_lop_thu_nghiem"
  MARKER = "vnbot_community_beta"
  SETTINGS = {
    title: "VNBot Community",
    site_description: "Chia sẻ giải pháp làm bằng VNBot, tìm skill và hỏi trực tiếp người đã triển khai.",
    default_locale: "vi",
    invite_only: true,
    approve_post_count: 1,
    newuser_max_links: 2,
    newuser_max_embedded_media: 1,
    max_image_size_kb: 4096,
    backup_frequency: 1,
    solved_enabled: true,
  }.freeze

  PUBLIC_ACCESS = { everyone: :full }.freeze
  CATEGORIES = [
    ["bat-dau-thong-bao", "Bắt đầu & thông báo", "23665B",
     "Hướng dẫn bắt đầu, nội quy cộng đồng và thông báo chính thức từ VNBot.",
     "", { everyone: :readonly, staff: :full }],
    ["hoi-dap-bao-loi", "Hỏi đáp & báo lỗi", "276CA5",
     "Hỏi cách sử dụng VNBot, báo lỗi và đánh dấu câu trả lời đã giải quyết được vấn đề.",
     "Mình muốn làm gì?\n\nMình đã thử những bước nào?\n\nMình mong đợi gì và đã thấy gì?", PUBLIC_ACCESS],
    ["da-lam-voi-vnbot", "Đã làm với VNBot", "735292",
     "Chia sẻ một giải pháp đã làm, cách triển khai và kết quả để người khác có thể thử lại.",
     "Bài toán ban đầu\n\nCác bước thực hiện\n\nKết quả quan sát được\n\nLink dùng thử hoặc tài liệu", PUBLIC_ACCESS],
    ["kho-skill-workflow", "Kho skill & workflow", "9B6126",
     "Giới thiệu skill, workflow và đường dẫn mở đúng tài nguyên trên Store.",
     "Tên và phiên bản\n\nDùng cho việc gì?\n\nCần chuẩn bị gì?\n\nLink mở đúng tài nguyên\n\nCách dùng và kết quả mong đợi", PUBLIC_ACCESS],
    ["lop-thu-nghiem", "Lớp thử nghiệm", "53716B",
     "Khu thảo luận dành cho giảng viên và học viên được mời vào nhóm thử nghiệm.",
     "", { GROUP => :full, staff: :full }],
  ].freeze

  def run
    # Serialize concurrent runs and commit the group, ACLs and initial post together.
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(274217, 1)")
      existing_group = Group.find_by(name: GROUP)
      if existing_group && (existing_group.public_admission || existing_group.automatic ||
          existing_group.automatic_membership_email_domains.present? || existing_group.group_users.exists?) &&
          Category.find_by(slug: "lop-thu-nghiem")&.custom_fields&.fetch(MARKER, nil) != "1"
        raise "The classroom group is already in use. Inspect its membership before setup."
      end
      group = existing_group || Group.create!(
        name: GROUP, full_name: "Lớp thử nghiệm VNBot", public_admission: false,
        allow_membership_requests: false,
      )
      raise "Classroom group has automatic admission" if group.public_admission || group.automatic_membership_email_domains.present?

      @categories = CATEGORIES.to_h do |slug, name, color, description, template, permissions|
        category = Category.find_or_initialize_by(parent_category_id: nil, slug: slug)
        if category.new_record?
          category.assign_attributes(
            name: name, user: Discourse.system_user, color: color, text_color: "FFFFFF",
            description: description, topic_template: template,
          )
          category.custom_fields[MARKER] = "1"
          category.custom_fields["enable_accepted_answers"] = "true" if slug == "hoi-dap-bao-loi"
          category.set_permissions(permissions)
          category.save!
        elsif category.custom_fields[MARKER] != "1"
          raise "An existing category uses #{slug}. Review before merging."
        end
        private_expected, acl = Category.resolve_permissions(permissions)
        category.reload
        actual = category.category_groups.pluck(:group_id, :permission_type).sort
        raise "Review category access for #{slug}" unless category.read_restricted == private_expected && actual == acl.sort
        [slug, category]
      end

      notice = @categories.fetch("bat-dau-thong-bao")
      title = "Bắt đầu với VNBot Community"
      welcome_id = notice.custom_fields["vnbot_welcome_topic_id"]
      unless Topic.exists?(category_id: notice.id, id: welcome_id)
        raw = <<~MD
          Chào bạn đến với cộng đồng VNBot!

          * Muốn tạo agent đầu tiên? Mở [hướng dẫn VNBot](https://vnbot.run/help/).
          * Đang kẹt ở một bước? Vào [Hỏi đáp & báo lỗi](/c/hoi-dap-bao-loi/#{@categories.fetch("hoi-dap-bao-loi").id}), ghi lại bước đã thử và kết quả bạn nhìn thấy.
          * Có giải pháp để chia sẻ? Đăng vào [Đã làm với VNBot](/c/da-lam-voi-vnbot/#{@categories.fetch("da-lam-voi-vnbot").id}). Nếu có skill đi kèm, thêm đường dẫn tới đúng trang tài nguyên.
          * Tìm mẫu để dùng lại? Xem [Kho skill & workflow](/c/kho-skill-workflow/#{@categories.fetch("kho-skill-workflow").id}) hoặc mở [AIKING Store](https://store.aikingx.vn/).

          Trước khi đăng ảnh minh họa, hãy che thông tin khách hàng, mật khẩu và mã truy cập.
        MD
        post = PostCreator.create!(Discourse.system_user, title: title, raw: raw, category: notice.id, skip_validations: true)
        notice.custom_fields["vnbot_welcome_topic_id"] = post.topic_id.to_s
        notice.save_custom_fields
      end
    end

    # Apply after data commits. Running again resumes if an option is unavailable.
    SETTINGS.each { |key, value| SiteSetting.public_send("#{key}=", value) unless SiteSetting.public_send(key) == value }
    horizon = Theme.find(Theme::CORE_THEMES.fetch("horizon"))
    horizon.set_default! unless horizon.default?
    puts "Beta categories: #{@categories.values.map(&:slug).join(', ')}"
    puts "Invitation-only: #{SiteSetting.invite_only}. Default language: #{SiteSetting.default_locale}."
  end
end

VNBotCommunityBeta.new.run
