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
  NAMES = %w[Expert Master Guru].freeze
  AREAS = ["Sales", "Marketing", "Vận hành", "Đào tạo", "Kỹ thuật", "Khác"].freeze
  SLUGS = %w[da-lam-voi-vnbot kho-skill-workflow].freeze
  RULES = [
    "Hai giải pháp được duyệt. Hai người khác nhau xác nhận đã làm lại thành công trên hai giải pháp khác nhau.",
    "Đã đạt Expert. Có tổng cộng bốn giải pháp, ba người được hướng dẫn triển khai thành công và hai trường hợp có kết quả trước/sau.",
    "Đã đạt Master. Hai đội riêng biệt xác nhận đã triển khai tối thiểu 30 ngày và hai thành viên được dìu dắt đã đạt Expert."
  ].freeze
  BENEFITS = [
    "Trang trưng bày giải pháp đã kiểm chứng mang tên bạn và lời mời tìm người dùng thử.",
    "Có tên trong danh bạ chuyên gia, nhận lời mời tư vấn và mở buổi thực hành cho thành viên đăng ký.",
    "Tiếp cận đề bài được doanh nghiệp cho phép chia sẻ. Có thể đề xuất đồng tổ chức workshop có phí hoặc tham gia dự án."
  ].freeze
  def badge(index)
    id = PluginStore.get("vnbot_community_ops", "badge_#{NAMES.fetch(index).downcase}")
    Badge.find(id)
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
      experts: proofs.where(kind: "mentor",peer_id: experts).distinct.count(:peer_id)
    }
  end
  TARGETS = [
    {flows: 2, trials: 2}, {flows: 4, learners: 3, results: 2}, {teams: 2, experts: 2}
  ].freeze
  LABELS = {flows: "Giải pháp đã duyệt", trials: "Người thử thành công trên các giải pháp khác nhau",
    learners: "Người đã được hướng dẫn", results: "Giải pháp có số liệu trước/sau",
    teams: "Đội triển khai đủ 30 ngày", experts: "Thành viên được dìu dắt đã đạt Expert"}.freeze
  def qualifies?(user, index)
    return false unless index.between?(0,2) && level(user) == index
    evidence = stats(user)
    TARGETS[index].all? { |k,n| evidence.fetch(k) >= n }
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
      when "coach","mentor","team","impact"
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
        elsif kind=="team"
          name=text!(p[:team],2,120).squish
          start=Date.iso8601(p[:start].to_s) rescue nil
          raise Invalid,"Cần ít nhất 30 ngày vận hành." unless start && start <= Date.current-30
          key=name.downcase
          detail={"team"=>name,"start"=>start.iso8601}
        end
        write(kind,actor,key,{peer_id:peer&.id,topic_id:topic_id,note:proof,details:detail,state:peer ? "confirm" : "pending"})
      when "confirm","decline"
        row=Entry.lock.find_by!(id:p[:id],peer_id:actor.id,kind:%w[coach team mentor])
        row.update!(state:kind=="confirm" ? "pending" : "rejected") if row.state=="confirm"
      when "rank"
        index=level(actor)
        raise Invalid,"Bạn chưa đủ minh chứng cho hạng tiếp theo." unless qualifies?(actor,index)
        write(kind,actor,index,{state:"pending",note:NAMES.fetch(index)})
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
        grant=BadgeGranter.grant(badge(index),row.user,granted_by:actor)
        raise Invalid,"Chưa trao được huy hiệu." unless grant && UserBadge.exists?(user_id:row.user_id,badge_id:badge(index).id)
      when "trial"
        flows.find(row.parent_id)
      when "flow","impact"
        topics.where(user_id:row.user_id).find(row.topic_id)
      when "mentor"
        raise Invalid,"Người được dìu dắt chưa đạt Expert." unless level(User.find(row.peer_id))>=1
      when "workshop"
        raise Invalid,"Người tổ chức cần hạng Master." unless level(row.user)>=2
      end
    end
    row.update!(state:approve ? "approved" : "rejected",reviewer_id:actor.id)
  end
end
