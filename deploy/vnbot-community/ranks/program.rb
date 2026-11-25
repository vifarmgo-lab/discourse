# frozen_string_literal: true
module VnRank
  class Invalid < StandardError; end
  class Entry < ActiveRecord::Base
    self.table_name = "vnbot_rank_entries"
    belongs_to :user
    belongs_to :topic, optional: true
    scope :accepted, -> { where(state: "approved") }
  end
  extend self
  NAMES = %w[Expert Master Guru Legendary].freeze
  AREAS = ["Sales", "Marketing", "Vận hành", "Đào tạo", "Kỹ thuật", "Khác"].freeze
  SLUGS = %w[da-lam-voi-vnbot kho-skill-workflow].freeze
  RULES = [
    "Hai giải pháp được duyệt. Hai người khác nhau xác nhận đã làm lại thành công trên hai giải pháp khác nhau.",
    "Đã đạt Expert. Có tổng cộng bốn giải pháp, ba người được hướng dẫn triển khai thành công và hai trường hợp có kết quả trước/sau.",
    "Đã đạt Master. Hai đội riêng biệt xác nhận đã triển khai tối thiểu 30 ngày và hai thành viên được dìu dắt đã đạt Expert.",
    "Đã đạt Guru, dìu dắt hai thành viên đạt Master và chủ trì một sáng kiến mà ba đội độc lập đã dùng ít nhất 90 ngày mỗi đội. Hội đồng xem xét trước khi admin trao hạng."
  ].freeze
  BENEFITS = [
    "Trang trưng bày giải pháp đã kiểm chứng mang tên bạn và lời mời tìm người dùng thử.",
    "Có tên trong danh bạ chuyên gia, nhận lời mời tư vấn và mở buổi thực hành cho thành viên đăng ký.",
    "Tiếp cận đề bài được doanh nghiệp cho phép chia sẻ. Có thể đề xuất đồng tổ chức workshop có phí hoặc tham gia dự án.",
    "Tham gia Hội đồng cố vấn theo quý, góp ý hồ sơ danh hiệu, đề xuất phát triển nền tảng và hợp tác kinh doanh với AIKING. Phạm vi và thù lao do các bên thống nhất theo dự án."
  ].freeze
  def badge(index)
    id = PluginStore.get("vnbot_community_ops", "badge_#{NAMES.fetch(index).downcase}")
    Badge.find(id)
  end
  def council?(user)
    user && (user.staff? || level(user) == NAMES.size)
  end
  def quarter
    today = Time.zone.today
    "#{today.year} · Quý #{(today.month - 1) / 3 + 1}"
  end
  def level(user)
    return 0 unless user
    owned = UserBadge.joins(:badge).where(user_id:user.id, badges:{name:NAMES, enabled:true}).pluck("badges.name")
    NAMES.each_index.reverse_each { |i| return i+1 if owned.include?(NAMES[i]) }
    0
  end
  def contributors(min_level)
    ids = Badge.where(name:NAMES.drop(min_level-1), enabled:true).select(:id)
    User.real.where(active: true, staged: false, id: UserBadge.where(badge_id: ids).select(:user_id)).not_suspended
  end
  def topics
    elig = Topic.listable_topics.visible.where(category_id: Category.where(read_restricted: false, slug: SLUGS).select(:id))
    elig.where(archetype: "regular", id: Post.where(post_number: 1, hidden: false, post_type: Post.types[:regular]).select(:topic_id))
  end
  def flows
    Entry.accepted.where(kind: "flow", topic_id: topics.select(:id))
  end
  def verified
    flows.where(id: Entry.accepted.where(kind: "trial").select(:parent_id))
  end
  def portfolio
    verified.where(user_id: contributors(1).select(:id))
  end
  def events
    Entry.accepted.where(kind: "workshop", user_id: contributors(2).select(:id))
      .where("details->>'date' >= ?", Date.current.iso8601)
  end
  def stats(user)
    own = flows.where(user_id: user.id)
    pairs = Entry.accepted.where(kind: "trial",parent_id: own.select(:id)).distinct.pluck(:user_id,:parent_id)
    spread = [pairs.map(&:first).uniq.size, pairs.map(&:last).uniq.size, 2].min
    proofs = Entry.accepted.where(user_id: user.id)
    experts = contributors(1).select(:id)
    {
      flows: own.count, trials: spread,
      learners: proofs.where(kind: "coach").distinct.count(:peer_id),
      results: proofs.where(kind: "impact", topic_id: own.select(:topic_id)).distinct.count(:topic_id),
      teams: proofs.where(kind: "team").distinct.count(:entry_key),
      experts: proofs.where(kind: "mentor",peer_id: experts).distinct.count(:peer_id),
      masters: proofs.where(kind: "mentor_master", peer_id: contributors(2).select(:id)).distinct.count(:peer_id),
      initiatives: proofs.where(kind: "adoption", topic_id: own.select(:topic_id)).group(:topic_id)
        .having("COUNT(DISTINCT entry_key) >= 3").count.size
    }
  end
  TARGETS = [
    {flows: 2, trials: 2}, {flows: 4, learners: 3, results: 2}, {teams: 2, experts: 2},
    {masters: 2, initiatives: 1}
  ].freeze
  LABELS = {flows: "Giải pháp đã duyệt", trials: "Người thử thành công trên các giải pháp khác nhau",
    learners: "Người đã được hướng dẫn", results: "Giải pháp có số liệu trước/sau",
    teams: "Đội triển khai đủ 30 ngày", experts: "Thành viên được dìu dắt đã đạt Expert",
    masters: "Thành viên được dìu dắt đã đạt Master", initiatives: "Sáng kiến có ít nhất 3 đội sử dụng đủ 90 ngày"}.freeze
  def qualifies?(user, index)
    return false unless index.between?(0, TARGETS.size - 1) && level(user) == index
    evidence = stats(user)
    TARGETS[index].all? { |k,n| evidence.fetch(k) >= n }
  end
  def next_step(user, index, counts)
    missing = TARGETS.fetch(index).find { |key, goal| counts.fetch(key) < goal }
    return unless missing
    key, goal = missing
    left = goal - counts.fetch(key)
    if key == :trials
      own = flows.where(user_id: user.id).includes(:topic).order(:id)
      completed = Entry.accepted.where(kind: "trial", parent_id: own.select(:id)).pluck(:parent_id).uniq
      candidate = own.where.not(id: completed).first || own.first
      return ["Mời thêm một người thử độc lập cho “#{candidate.topic.title}”.", "Mở link mời dùng thử",
              "/lo-trinh?tab=trials&topic=#{candidate.topic_id}"] if candidate
    end
    steps = {
      flows: ["Nộp thêm #{left} giải pháp để được xét duyệt.", "Nộp giải pháp", "#flow"],
      learners: ["Ghi nhận thêm #{left} thành viên đã được bạn hướng dẫn triển khai.", "Gửi minh chứng hướng dẫn", "#coach"],
      results: ["Bổ sung số liệu trước và sau cho #{left} giải pháp.", "Gửi số liệu", "#impact"],
      teams: ["Cần thêm #{left} đội xác nhận đã vận hành đủ 30 ngày.", "Ghi nhận đội triển khai", "#team"],
      experts: ["Cần thêm #{left} thành viên bạn dìu dắt đạt Expert.", "Gửi minh chứng dìu dắt", "#mentor"],
      masters: ["Cần thêm #{left} thành viên bạn dìu dắt đạt Master.", "Ghi nhận thành viên Master", "#mentor_master"],
      initiatives: ["Chọn cùng một sáng kiến và ghi nhận từng đội đã dùng đủ 90 ngày.", "Ghi nhận đội dùng sáng kiến", "#adoption"]
    }
    steps[key]
  end
  def text!(s, min=8, max=1800)
    s = s.to_s.strip
    raise Invalid, "Nội dung cần từ #{min} đến #{max} ký tự." unless s.length.between?(min,max)
    s
  end
  def active_peer!(actor, name)
    peer = User.real.not_suspended.find_by(username_lower: name.to_s.strip.delete_prefix("@").downcase, active: true, staged: false)
    raise Invalid, "Hãy nhập tên một thành viên khác đang hoạt động." unless peer && peer.id != actor.id
    peer
  end
  def topic!(str,actor)
    match = str.to_s.strip.match(%r{\A(?:https://community\.vnbot\.run)?/t/(?:(?!\d+(?:/|$))[^/?#]+/)?(\d+)(?:/\d+)?/?(?:[?#].*)?\z})
    t = topics.find_by(id: match && match[1])
    raise Invalid, "Hãy dùng link bài của bạn trong Đã làm với VNBot hoặc Kho skill & workflow." unless t && t.user_id == actor.id
    t
  end
  def write(kind,user,key,attrs)
    row = Entry.find_or_initialize_by(kind: kind,user_id: user.id,entry_key: key.to_s)
    return row unless row.new_record? || row.state == "rejected"
    row.update!(attrs.merge(reviewer_id:nil))
    row
  end
  def submit(actor,p)
    raise Invalid, "Tài khoản chưa đủ điều kiện." unless actor && actor.id > 0 && actor.active? && !actor.staged? && !actor.suspended?
    kind = p[:kind].to_s
    Entry.transaction do
      actor.lock!
      case kind
      when "flow"
        t = topic!(p[:url],actor)
        raise Invalid, "Chọn lĩnh vực." unless AREAS.include?(p[:area])
        write(kind,actor,t.id,{topic_id:t.id,state:"pending",note:text!(p[:note]),details:{"area"=>p[:area]}})
      when "trial", "trial_result"
        f = flows.find(p[:id])
        raise Invalid, "Tác giả cần một người dùng thử độc lập." if f.user_id == actor.id
        row = write("trial",actor,f.id,{parent_id:f.id,topic_id:f.topic_id,state:"trying"})
        if kind=="trial_result" && %w[trying blocked].include?(row.state)
          row.update!(state:p[:outcome]=="success" ? "pending" : "blocked",note:text!(p[:note]))
        end
      when "coach","mentor","team","impact","mentor_master","adoption"
        raise Discourse::InvalidAccess if %w[mentor_master adoption].include?(kind) && level(actor) < 3
        peer = active_peer!(actor,p[:peer]) unless kind=="impact"
        proof = text!(p[:note])
        key = peer&.id
        detail = {}
        topic_id = nil
        if kind=="impact"
          t=topic!(p[:url],actor)
          raise Invalid,"Giải pháp cần được duyệt trước." unless flows.exists?(user_id:actor.id,topic_id:t.id)
          topic_id=key=t.id
          detail={"before"=>text!(p[:before],1,180),"after"=>text!(p[:after],1,180)}
        elsif %w[team adoption].include?(kind)
          name=text!(p[:team],2,120).squish
          start=Date.iso8601(p[:start].to_s) rescue nil
          days = kind == "adoption" ? 90 : 30
          raise Invalid,"Cần ít nhất #{days} ngày vận hành." unless start && start <= Date.current-days
          key=name.downcase
          detail={"team"=>name,"start"=>start.iso8601}
          if kind == "adoption"
            topic = topic!(p[:url], actor)
            raise Invalid, "Sáng kiến cần là một giải pháp đã duyệt của bạn." unless flows.exists?(user_id: actor.id, topic_id: topic.id)
            topic_id = topic.id
            key = "#{topic_id}:#{key}"
          end
        elsif kind == "mentor_master"
          raise Invalid, "Người được dìu dắt cần đạt Master." unless level(peer) >= 2
        end
        write(kind,actor,key,{peer_id:peer&.id,topic_id:topic_id,note:proof,details:detail,state:peer ? "confirm" : "pending"})
      when "confirm","decline"
        row=Entry.lock.find_by!(id:p[:id],peer_id:actor.id,kind:%w[coach team mentor mentor_master adoption])
        row.update!(state:kind=="confirm" ? "pending" : "rejected") if row.state=="confirm"
      when "rank"
        index=level(actor)
        raise Invalid,"Bạn chưa đủ minh chứng cho hạng tiếp theo." unless qualifies?(actor,index)
        raise Invalid,"Bạn cần đồng ý chia sẻ tiến độ xét hạng với Hội đồng." unless p[:consent] == "yes"
        write(kind,actor,index,{state:"pending",note:NAMES.fetch(index),details:{"council"=>true,"round"=>SecureRandom.uuid}})
      when "workshop","brief"
        if kind=="brief"
          raise Discourse::InvalidAccess unless actor.staff?
          raise Invalid,"Cần xác nhận quyền chia sẻ đề bài cho Guru." unless p[:consent]=="yes"
        else
          raise Discourse::InvalidAccess unless level(actor)>=2
        end
        title=text!(p[:title],5,130)
        date=Date.iso8601(p[:date].to_s) rescue nil
        raise Invalid,"Hãy chọn ngày từ hôm nay trở đi." unless date && date>=Date.current
        write(kind,actor,"#{date}:#{title.downcase}",{state:kind=="brief" ? "approved" : "pending", note:text!(p[:note]),details:{"title"=>title,"date"=>date.iso8601}})
      when "join","apply"
        parent = kind=="join" ? events.find(p[:id]) : Entry.accepted.where(kind:"brief").find(p[:id])
        if kind=="apply"
          raise Discourse::InvalidAccess unless level(actor)>=3
          raise Invalid,"Đề bài đã hết hạn." if parent.details["date"] < Date.current.iso8601
        end
        write(kind,actor,parent.id,{state:"approved",parent_id:parent.id,note:kind=="apply" ? text!(p[:note]) : ""})
      when "advice"
        raise Discourse::InvalidAccess unless council?(actor)
        rank = Entry.lock.find_by!(id: p[:id], kind: "rank", state: "pending")
        raise Discourse::InvalidAccess if rank.user_id == actor.id
        raise Discourse::InvalidAccess unless rank.details["council"]
        round = rank.details.fetch("round")
        write(kind, actor, "#{rank.id}:#{round}", {state: "approved", parent_id: rank.id, details: {"round"=>round}, note: text!(p[:note])})
      when "proposal"
        raise Discourse::InvalidAccess unless council?(actor)
        title = text!(p[:title], 5, 130)
        area = p[:area].to_s
        raise Invalid, "Chọn loại đề xuất." unless ["Lộ trình nền tảng", "Hợp tác kinh doanh", "Lịch họp Hội đồng"].include?(area)
        write(kind, actor, "#{quarter}:#{title.downcase}", {state: "approved", note: text!(p[:note]), details: {"title"=>title,"area"=>area,"quarter"=>quarter}})
      when "response"
        raise Discourse::InvalidAccess unless actor.staff?
        proposal = Entry.lock.find_by!(id: p[:id], kind: "proposal", state: "approved")
        proposal.update!(details: proposal.details.merge("response"=>text!(p[:note]), "responded_by"=>actor.username))
      when "approve","reject"
        review!(actor,p[:id],kind=="approve")
      else
        raise Invalid,"Thao tác không hợp lệ."
      end
    end
  end
  def review!(actor,id,approve)
    raise Discourse::InvalidAccess unless actor.staff?
    row=Entry.lock.find(id)
    raise Discourse::InvalidAccess if row.user_id==actor.id || row.peer_id==actor.id
    return unless row.state=="pending"
    raise Discourse::InvalidAccess if row.kind=="rank" && !actor.admin?
    if approve
      case row.kind
      when "rank"
        index=Integer(row.entry_key)
        raise Invalid,"Minh chứng đã thay đổi. Hãy kiểm tra tiến độ." unless qualifies?(row.user,index)
        if index == NAMES.size - 1
          independent = Entry.accepted.where(kind: "advice", parent_id: row.id).where("details->>'round' = ?", row.details.fetch("round")).where.not(user_id: [actor.id, row.user_id]).includes(:user)
          raise Invalid, "Cần ý kiến Hội đồng từ một người khác trước khi trao Legendary." unless independent.any? { |item| council?(item.user) }
        end
        grant=BadgeGranter.grant(badge(index),row.user,granted_by:actor)
        raise Invalid,"Chưa trao được huy hiệu." unless grant && UserBadge.exists?(user_id:row.user_id,badge_id:badge(index).id)
      when "trial"
        flows.find(row.parent_id)
      when "flow","impact"
        topics.where(user_id:row.user_id).find(row.topic_id)
      when "mentor"
        raise Invalid,"Người được dìu dắt chưa đạt Expert." unless level(User.find(row.peer_id))>=1
      when "mentor_master"
        raise Invalid, "Người được dìu dắt cần đạt Master." unless level(User.find(row.peer_id)) >= 2
      when "adoption"
        flows.where(user_id: row.user_id).find_by!(topic_id: row.topic_id)
      when "workshop"
        raise Invalid,"Người tổ chức cần hạng Master." unless level(row.user)>=2
      end
    end
    row.update!(state:approve ? "approved" : "rejected",reviewer_id:actor.id)
  end
end
