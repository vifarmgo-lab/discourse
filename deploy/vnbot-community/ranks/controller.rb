# frozen_string_literal: true
class VnRankController < ::ApplicationController
  prepend_view_path File.expand_path("views",__dir__)
  skip_before_action :check_xhr, :preload_json
  before_action :ensure_logged_in, only: :update
  helper_method :kind_label, :state_label, :actions, :current_user, :reg_link
  TABS = %w[start me trials verified directory events briefs review member].freeze
  KINDS = {"flow"=>"Giải pháp", "trial"=>"Dùng thử", "coach"=>"Hướng dẫn triển khai", "impact"=>"Kết quả trước/sau",
    "team"=>"Đội đã vận hành", "mentor"=>"Dìu dắt Expert", "rank"=>"Xét danh hiệu", "workshop"=>"Buổi thực hành",
    "brief"=>"Đề bài doanh nghiệp", "join"=>"Đăng ký buổi thực hành", "apply"=>"Đề xuất hợp tác"}.freeze
  STATES = {"trying"=>"Đang thử","blocked"=>"Gặp vướng mắc","approved"=>"Đã xác nhận","pending"=>"Chờ duyệt",
    "confirm"=>"Chờ người liên quan xác nhận","rejected"=>"Cần bổ sung"}.freeze
  def kind_label(k) = KINDS.fetch(k,k)
  def state_label(k) = STATES.fetch(k,k)
  def reg_link(user)
    "/new-message?username=#{ERB::Util.url_encode(user.username)}"
  end
  def actions(kind, id=nil)
    {kind:kind,id:id,tab:@tab,focus:params[:topic]}.compact
  end
  def navigation
    render plain: File.read(File.join(__dir__,"navigation.js")), content_type:"application/javascript"
  end
  def style
    render plain: File.read(File.join(__dir__,"style.css")), content_type:"text/css"
  end
  def index
    @actor=current_user
    @level=VnRank.level(@actor)
    @tab=TABS.include?(params[:tab]) ? params[:tab] : "start"
    if @tab=="me" && !@actor
      return redirect_to("/login?redirect=/lo-trinh%3Ftab%3Dme")
    end
    raise Discourse::InvalidAccess if @tab=="review" && !@actor&.staff?
    data=VnRank::Entry
    case @tab
    when "me"
      @stats=VnRank.stats(@actor)
      @ready=@level<3 && VnRank.qualifies?(@actor,@level)
      @mine=data.where(user_id:@actor.id).order(updated_at: :desc).limit(100)
      @confirm=data.where(peer_id:@actor.id,state:"confirm").order(:id)
      @feedback=data.where(kind:"trial",parent_id:VnRank.flows.where(user_id:@actor.id).select(:id),state:%w[approved blocked]).includes(:user).order(updated_at: :desc).limit(60)
    when "trials","verified"
      rows=@tab=="verified" ? VnRank.portfolio : VnRank.flows
      rows=rows.where(topic_id:params[:topic].to_i) if params[:topic].present?
      @flows=rows.includes(:topic,:user).order(id: :desc).limit(100)
      @attempts=@actor ? data.where(kind:"trial",user_id:@actor.id,parent_id:@flows.map(&:id)).index_by(&:parent_id) : {}
    when "member"
      @person=VnRank.contributors(1).find_by!(username_lower:params[:name].to_s.downcase)
      @person_level=VnRank.level(@person)
      @flows=VnRank.portfolio.where(user_id:@person.id).includes(:topic).order(id: :desc)
    when "directory"
      people=VnRank.contributors(2)
      if VnRank::AREAS.include?(params[:area])
        people=people.where(id:VnRank.flows.where("details->>'area' = ?",params[:area]).select(:user_id))
      end
      @people=people.order(:username_lower).limit(150)
    when "events"
      @events=VnRank.events.includes(:user).order(Arel.sql("details->>'date' ASC")).limit(100)
      @joins=@actor ? data.where(kind:"join",user_id:@actor.id).pluck(:parent_id) : []
      ids=@events.select{|e| @actor && (@actor.id==e.user_id || @actor.staff?)}.map(&:id)
      @participants=data.where(kind:"join",parent_id:ids).includes(:user).group_by(&:parent_id)
    when "briefs"
      raise Discourse::InvalidAccess unless @actor && (@level>=3 || @actor.staff?)
      @briefs=data.accepted.where(kind:"brief").where("details->>'date' >= ?",Date.current.iso8601).order(id: :desc)
      offers=data.where(kind:"apply",parent_id:@briefs.select(:id))
      @offers=(@actor.staff? ? offers : offers.where(user_id:@actor.id)).includes(:user).group_by(&:parent_id)
    when "review"
      @queue=data.where(state:"pending").includes(:user).order(:id).limit(100)
    end
    response.headers["Cache-Control"]="private, no-store"
    response.headers["Referrer-Policy"]="same-origin"
    render template:"rank/index",layout:false
  end
  def spotlight
    response.headers["Cache-Control"]="private, no-store"
    if params[:name].present?
      person = User.real.where(active:true,staged:false).not_suspended.find_by(username_lower:params[:name].to_s.downcase)
      return render json:{mine:person.present? && current_user&.id==person.id, ranked:VnRank.level(person)>0}
    end
    if params[:topic].present?
      yes=VnRank.flows.exists?(topic_id:params[:topic].to_i)
      return render json:{eligible:yes}
    end
    choice = lambda do |scope|
      n=scope.count
      scope.reorder(:id).offset(Date.current.jd % n).first if n.positive?
    end
    options=[]
    if f=choice.call(VnRank.portfolio)
      options << {text:"Dùng thử · #{f.topic.title}",url:"/lo-trinh?tab=trials&topic=#{f.topic_id}"}
    end
    if e=choice.call(VnRank.events)
      options << {text:"Đăng ký · #{e.details["title"]}",url:"/lo-trinh?tab=events#item-#{e.id}"}
    end
    if f=choice.call(VnRank.portfolio.where(user_id:VnRank.contributors(3).select(:id)))
      options << {text:"Mời trao đổi · #{f.user.username} · #{f.topic.title}",url:"/lo-trinh?tab=member&name=#{ERB::Util.url_encode(f.user.username)}"}
    end
    render json:{items:options}
  end
  def update
    VnRank.submit(current_user,params)
    tab=TABS.include?(params[:tab]) ? params[:tab] : "me"
    parts={tab:tab,done:1}
    parts[:topic]=params[:focus].to_i if params[:focus].present?
    redirect_to "/lo-trinh?#{parts.to_query}",status: :see_other
  rescue VnRank::Invalid => e
    render plain:e.message,status: :unprocessable_entity
  end
end
