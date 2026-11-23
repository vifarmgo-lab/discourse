# frozen_string_literal: true
# Run with bin/rails runner. Re-running preserves staff edits and never grants membership.
abort "Unexpected forum" unless Discourse.current_hostname == "community.vnbot.run"

class VNBotCommunityOperations
  NAMESPACE = "vnbot_community_ops"
  VIP = "vnbot_vip"
  RANKS = [
    ["Expert", BadgeType::Bronze, "Đã chia sẻ một giải pháp VNBot mà người khác làm lại được."],
    ["Master", BadgeType::Silver, "Đã hướng dẫn người khác áp dụng nhiều giải pháp VNBot và có kết quả đối chiếu được."],
    ["Guru", BadgeType::Gold, "Có đóng góp chuyên sâu, bền vững và đã giúp hình thành đội ngũ chuyên gia VNBot."]
  ].freeze

  def stored(key)
    PluginStore.get(NAMESPACE, key)
  end

  def keep(key, record)
    PluginStore.set(NAMESPACE, key, record.id)
    record
  end

  def owned(key, model)
    id = stored(key)
    return unless id
    model.find(id)
  end

  def staff_room
    room = Category.find(SiteSetting.staff_category_id)
    abort "Staff category must be staff-only" unless room.read_restricted &&
      room.category_groups.pluck(:group_id).all? { |id| [Group::AUTO_GROUPS[:staff], Group::AUTO_GROUPS[:admins], Group::AUTO_GROUPS[:moderators]].include?(id) }
    room
  end

  def create_resources!
    raise "Badges must be enabled first" unless SiteSetting.enable_badges
    RANKS.each do |name, level, criteria|
      key = "badge_#{name.downcase}"
      next if owned(key, Badge)
      raise "Existing unrelated badge: #{name}" if Badge.where("lower(name) = ?", name.downcase).exists?
      keep(key, Badge.create!(name: name, badge_type_id: level, description: criteria,
        long_description: "#{criteria} Ban quản trị xét theo bài viết, lời giải và phản hồi có dẫn chứng.",
        allow_title: true, multiple_grant: false, listable: true, enabled: true, auto_revoke: false))
    end
    group = owned("vip_group", Group)
    unless group
      raise "Existing unrelated VIP group" if Group.find_by(name: VIP)
      group = keep("vip_group", Group.create!(name: VIP, full_name: "VIP VNBot Community",
        public_admission: false, allow_membership_requests: false,
        visibility_level: Group.visibility_levels[:members], members_visibility_level: Group.visibility_levels[:staff]))
    end
    raise "Unexpected VIP admission settings" if group.public_admission || group.automatic || group.automatic_membership_email_domains.present? || group.grant_trust_level.present?
    room = owned("vip_category", Category)
    perms = { VIP => :full, staff: :full }
    unless room
      raise "Existing unrelated VIP category" if Category.exists?(slug: "vnbot-vip")
      room = Category.new(name: "Thành viên VIP", slug: "vnbot-vip", color: "326553", text_color: "FFFFFF",
        user: Discourse.system_user)
      room.set_permissions(perms)
      keep("vip_category", room.tap(&:save!))
    end
    _, acl = Category.resolve_permissions(perms)
    raise "Unexpected VIP category permissions" unless room.read_restricted && room.category_groups.pluck(:group_id,:permission_type).sort == acl.sort
    ledger = staff_topic("ledger", "Sổ thời hạn VIP của VNBot Community", <<~MD)
      Admin chỉnh bài đầu này sau khi cấp, gia hạn hoặc thu hồi VIP. Mỗi thành viên đang được duyệt có đúng một dòng trong khối dưới đây, dạng `username | YYYY-MM-DD`. Hạn tính đến hết ngày ghi theo giờ Việt Nam. Xóa dòng khi đã thu hồi. Chỉ ghi tên tài khoản và hạn; chứng từ ở hệ thống quản lý quyền lợi.
      ```vip
      ```
    MD
    staff_topic("guide", "Vận hành Community · Danh hiệu, huy hiệu và VIP", <<~MD)
      **Xét danh hiệu hằng tuần.** Moderator ghi tên tài khoản, danh hiệu đề xuất, link bài/lời giải, kết quả và lý do trong chủ đề này. Tác giả không tự duyệt. Admin hoặc người phụ trách được ủy quyền đối chiếu dẫn chứng, ghi quyết định và trao huy hiệu từ [Quản lý huy hiệu](/admin/badges). Trước khi trao, kiểm tra lịch sử tài khoản để tránh trao trùng. Thành viên có thể chọn huy hiệu làm tiêu đề trong hồ sơ.
      
      #{RANKS.map { |n, _, c| "* **#{n}** — #{c}" }.join("\n")}

      Danh hiệu ghi nhận chuyên môn. Khi lên hạng, thành viên chọn danh hiệu mới để hiển thị; huy hiệu cũ vẫn ghi nhận thành tích. Nếu trao nhầm, admin thu hồi đúng huy hiệu đã trao và ghi lý do trong chủ đề. Việc trao huy hiệu không cấp quyền VIP hay quản trị.

      **VIP.** Xác nhận tài khoản diễn đàn, người phê duyệt và ngày hết hạn theo quyền lợi đã có. Thêm đúng tài khoản vào [nhóm VIP](/g/#{VIP}/members), cập nhật [sổ thời hạn](#{ledger.relative_url}). Khi hết hạn, đối chiếu nguồn quyền lợi trước khi gia hạn hoặc gỡ thành viên. Ghi quyết định và kiểm tra quyền xem [khu VIP](/c/#{room.id}). Nếu phát hiện sai lệch giữa sổ và nhóm, kiểm tra nguồn cấp quyền trước khi thay đổi.

      **Nhịp vận hành.** Hằng ngày kiểm tra [hàng chờ duyệt](/review) và câu hỏi chưa có phản hồi. Hằng tuần chọn case nổi bật, xem lời giải và xét danh hiệu. Đầu tháng đối chiếu báo cáo VIP với sổ, xử lý từng sai lệch và ghi người hoàn tất. Dữ liệu sản xuất được kiểm tra thêm sau khi gỡ quyền nếu tài liệu VIP có đường dẫn tệp riêng.
    MD
    [group, ledger]
  end

  def staff_topic(key, title, raw)
    scope = staff_room
    if topic = owned(key, Topic)
      raise "Review topic moved out of staff" unless topic.category_id == scope.id && topic.archetype == Archetype.default
      return topic
    end
    raise "Unmanaged topic title collision" if scope.topics.exists?(title: title)
    post = PostCreator.create!(Discourse.system_user, title: title, raw: raw, category: scope.id, skip_validations: true)
    keep(key, post.topic)
  end

  def audit(group, ledger)
    today = Time.current.in_time_zone("Asia/Ho_Chi_Minh").to_date
    block = ledger.first_post.raw.scan(/^```vip[ \t]*\r?\n(.*?)^```[ \t]*$/m)
    raise "Expected exactly one vip ledger block" unless block.one?
    dates = {}
    errors = []
    block.first.first.lines.each_with_index do |row, i|
      next if row.strip.empty?
      m = /\A([a-zA-Z0-9_.-]+)\s*\|\s*(\d{4}-\d{2}-\d{2})\z/.match(row.strip)
      date = (Date.iso8601(m[2]) rescue nil) if m
      if !m || !date || dates.key?(m[1].downcase)
        errors << "Dòng #{i+1} sai định dạng hoặc bị trùng."
      else
        dates[m[1].downcase] = date
      end
    end
    users = group.users.pluck(:username_lower).sort
    rows = [
      ["Có quyền nhưng thiếu ngày hết hạn", users - dates.keys],
      ["Đã hết hạn, cần xác nhận", users.select { |u| dates[u] && dates[u] < today }],
      ["Sẽ hết hạn trong 30 ngày", users.select { |u| dates[u] && (today..today+30).cover?(dates[u]) }],
      ["Có trong sổ nhưng chưa có quyền", dates.keys - users],
    ]
    body = ["Đối chiếu ngày #{today.strftime('%d/%m/%Y')} theo giờ Việt Nam. Nhóm đang có #{users.size} thành viên. Admin đối chiếu và ghi quyết định tại đây.", *errors,
      *rows.map { |name, list| "**#{name}** (#{list.size})\n" + (list.empty? ? "Không có." : list.map { |u| "- `#{u}`#{dates[u] ? " · #{dates[u]}" : ""}" }.join("\n")) }].join("\n\n")
    topic = staff_topic("audit_#{today.strftime('%Y_%m')}", "Rà quyền VIP · #{today.strftime('%m/%Y')}", body)
    post = topic.first_post
    post.revise(Discourse.system_user, { raw: body }, skip_validations: true) if post.raw != body
    puts "VIP=#{group.id} members=#{users.size} staff_guide=#{stored('guide')} ledger=#{ledger.id} audit=#{topic.id} badges=#{RANKS.map { |n,*| "#{n}:#{stored("badge_#{n.downcase}")}" }.join(',')} category=#{stored('vip_category')}"
  end
end

ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(274217, 2)")
  ops = VNBotCommunityOperations.new
  ops.audit(*ops.create_resources!)
end
