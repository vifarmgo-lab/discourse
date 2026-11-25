# frozen_string_literal: true
raise "Unexpected host" unless Discourse.current_hostname == "community.vnbot.run"
def assert_rank(ok, message)
  raise "Rank verification: #{message}" unless ok
end
def sample_user(admin:false)
  name="vrqa#{SecureRandom.hex(5)}"
  u=User.new(username:name,email:"#{name}@example.invalid",active:true,trust_level:1,admin:admin)
  u.save!(validate:false)
  u
end
def must_deny
  yield
rescue Discourse::InvalidAccess, VnRank::Invalid, ActiveRecord::RecordNotFound
  true
else
  raise "Expected denied action"
end
def submit(u,kind,**p)
  VnRank.submit(u,p.merge(kind:kind))
end
ActiveRecord::Base.transaction do
  a=sample_user
  b=sample_user
  c=sample_user
  d=sample_user
  staff=sample_user(admin:true)
  room=Category.find_by!(slug:"da-lam-voi-vnbot")
  flows=[]
  4.times do |n|
    t=Topic.new(title:"Bài kiểm thử #{SecureRandom.hex(6)}",user:a,category:room,archetype:"regular")
    t.disable_rate_limits!
    t.save!
    post=Post.new(topic:t,user:a,post_number:1,raw:"Hướng dẫn mẫu và đầu ra minh chứng cho lộ trình.",cooked:"<p>Demo</p>")
    post.disable_rate_limits!
    post.save!
    submit(a,"flow",url:"/t/#{t.id}",area:"Sales",note:"Hướng dẫn và demo có thể làm lại")
    f=VnRank::Entry.find_by!(kind:"flow",user_id:a.id,topic_id:t.id)
    submit(staff,"approve",id:f.id)
    flows << f
  end
  must_deny{submit(a,"trial",id:flows.first.id)}
  must_deny{submit(a,"rank")}
  must_deny{submit(a,"workshop")}
  must_deny{submit(a,"brief")}
  [[b,0],[b,1],[c,1]].each_with_index do |(person,i), idx|
    submit(person,"trial",id:flows[i].id)
    submit(person,"trial_result",id:flows[i].id,note:"Đã chạy lại đúng kết quả",outcome:"success")
    r=VnRank::Entry.find_by!(kind:"trial",user_id:person.id,parent_id:flows[i].id)
    submit(staff,"approve",id:r.id)
    assert_rank(!VnRank.qualifies?(a,0),"two distinct testers required") if idx==1
  end
  def award(u,staff)
    i=VnRank.level(u)
    submit(u,"rank",consent:"yes")
    row=VnRank::Entry.find_by!(kind:"rank",user_id:u.id,entry_key:i.to_s)
    submit(staff,"approve",id:row.id)
    submit(staff,"approve",id:row.id)
    assert_rank(VnRank.level(u)==i+1,"sequential award")
  end
  assert_rank(VnRank.next_step(b, 0, VnRank.stats(b)).last=="#flow","Newbie has an actionable first step")
  award(a,staff)
  assert_rank(VnRank.portfolio.where(user_id:a.id).count==2,"verified portfolio")
  [b,c,d].each do |peer|
    submit(a,"coach",peer:peer.username,note:"Đã hướng dẫn triển khai thực tế")
    row=VnRank::Entry.find_by!(kind:"coach",user_id:a.id,peer_id:peer.id)
    must_deny{submit(a,"confirm",id:row.id)}
    submit(peer,"confirm",id:row.id)
    submit(staff,"approve",id:row.id)
  end
  flows.first(2).each do |f|
    submit(a,"impact",url:"/t/#{f.topic_id}",before:"3 giờ",after:"1 giờ",note:"Cùng công việc, đầu ra được đối chiếu")
    submit(staff,"approve",id:VnRank::Entry.find_by!(kind:"impact",user_id:a.id,topic_id:f.topic_id).id)
  end
  award(a,staff)
  date=Date.current+5
  common={title:"Thực hành mẫu",date:date.iso8601,note:"09:00 giờ Việt Nam, buổi thử nội bộ"}
  submit(a,"workshop",**common)
  w=VnRank::Entry.find_by!(user_id:a.id,kind:"workshop")
  submit(staff,"approve",id:w.id)
  2.times {submit(b,"join",id:w.id)}
  assert_rank(VnRank::Entry.where(kind:"join",parent_id:w.id,user_id:b.id).count==1,"single registration")
  [b,c].each_with_index do |p,i|
    must_deny{submit(a,"team",team:"Too new",start:(Date.current-1).iso8601,peer:p.username,note:"Chưa đủ ngày")}
    submit(a,"team",team:"Team #{i}",start:(Date.current-30).iso8601,peer:p.username,note:"Đã xác nhận 30 ngày vận hành")
    row=VnRank::Entry.find_by!(kind:"team",user_id:a.id,peer_id:p.id)
    submit(p,"confirm",id:row.id)
    submit(staff,"approve",id:row.id)
    BadgeGranter.grant(VnRank.badge(0),p,granted_by:staff)
    submit(a,"mentor",peer:p.username,note:"Đã dìu dắt thành viên đạt Expert")
    row=VnRank::Entry.find_by!(kind:"mentor",user_id:a.id,peer_id:p.id)
    submit(p,"confirm",id:row.id)
    submit(staff,"approve",id:row.id)
  end
  award(a,staff)
  submit(staff,"brief",**common.merge(consent:"yes"))
  brief=VnRank::Entry.find_by!(kind:"brief",user_id:staff.id)
  must_deny{submit(b,"apply",id:brief.id,note:"Đề xuất thử")}
  submit(a,"apply",id:brief.id,note:"Cách phối hợp triển khai")
  assert_rank(!GroupUser.exists?(user_id:a.id,group_id:Group.find_by!(name:"vnbot_vip").id),"VIP remains independent")
  assert_rank(!VnRank.council?(a),"Guru has no council seat")
  must_deny { submit(a, "proposal", **common) }
  must_deny { submit(b, "adoption") }
  reviewer = sample_user(admin: true)
  note = "Đã đối chiếu vai trò chủ trì và hoạt động thực tế"
  [b,c].each do |peer|
    must_deny { submit(a,"mentor_master", peer:peer.username, note:note) }
    BadgeGranter.grant(VnRank.badge(1),peer,granted_by:staff)
    submit(a,"mentor_master",peer:peer.username,note:note)
    row=VnRank::Entry.find_by!(kind:"mentor_master",user_id:a.id,peer_id:peer.id)
    submit(peer,"confirm",id:row.id)
    submit(staff,"approve",id:row.id)
  end
  proof = {peer:b.username, url:"/t/#{flows[0].topic_id}", team:"Đội A", note:note, start:(Date.current-89).iso8601}
  must_deny { submit(a,"adoption",**proof) }
  [[0,b,"Đội A"],[0,c,"Đội B"],[1,d,"Đội C"],[0,b," Đội   A "],[0,d,"Đội C"]].each_with_index do |(index,peer,team),i|
    submit(a,"adoption",**proof.merge(peer:peer.username,url:"/t/#{flows[index].topic_id}",team:team,start:(Date.current-90).iso8601))
    row=VnRank::Entry.find_by!(kind:"adoption",user_id:a.id,topic_id:flows[index].topic_id,peer_id:peer.id)
    submit(peer,"confirm",id:row.id)
    submit(staff,"approve",id:row.id)
    assert_rank(!VnRank.qualifies?(a,3),"mixed initiatives and duplicate teams excluded") if i<4
  end
  must_deny { submit(a,"rank") }
  submit(a,"rank",consent:"yes")
  row=VnRank::Entry.find_by!(kind:"rank",user_id:a.id,entry_key:"3")
  must_deny { submit(staff,"approve",id:row.id) }
  must_deny { submit(b,"advice",id:row.id,note:note) }
  submit(staff,"advice",id:row.id,note:note)
  must_deny { submit(staff,"approve",id:row.id) }
  submit(reviewer,"advice",id:row.id,note:note)
  submit(staff,"reject",id:row.id)
  submit(a,"rank",consent:"yes")
  must_deny { submit(staff,"approve",id:row.id) }
  submit(reviewer,"advice",id:row.id,note:note)
  submit(staff,"approve",id:row.id)
  assert_rank(VnRank.level(a)==4 && VnRank.council?(a) && !a.reload.staff?, "Legendary advisory seat without staff permissions")
  submit(a,"proposal",title:"Sáng kiến chung",area:"Hợp tác kinh doanh",note:note)
  prop=VnRank::Entry.find_by!(kind:"proposal",user_id:a.id)
  must_deny { submit(a,"response",id:prop.id,note:note) }
  must_deny { submit(a,"approve",id:prop.id) }
  submit(staff,"response",id:prop.id,note:note)
  assert_rank(prop.reload.details["response"]==note && prop.details["quarter"]==VnRank.quarter,"quarterly council and AIKING reply")
  assert_rank(!GroupUser.exists?(user_id:a.id,group_id:Group.find_by!(name:"vnbot_vip").id),"Legendary does not confer VIP")
  # Exercise actual routes and templates under isolated local request sessions.
  app=ActionDispatch::Integration::Session.new(Rails.application)
  app.host! Discourse.current_hostname
  app.https!
  app.get "/latest", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36" }
  html=Nokogiri::HTML(app.response.body)
  script=html.at_css("script#vnbot-rank-navigation")
  assert_rank(app.response.status==200 && script && script["nonce"].present? && script.content.include?("Lộ trình chuyên gia"), "homepage navigation with CSP nonce")
  %w[start trials verified directory events].each do |tab|
    app.get "/lo-trinh",params:{tab:tab}
    assert_rank(app.response.status==200 && app.response.body.include?("Lộ trình chuyên gia"),"guest GET #{tab}: #{app.response.status}")
  end
  app.get "/lo-trinh"
  levels=Nokogiri::HTML(app.response.body).css(".levels h2").map(&:text)
  assert_rank(levels == ["Cấp 1 · Newbie","Cấp 2 · Expert","Cấp 3 · Master","Cấp 4 · Guru","Cấp 5 · Legendary"],"five tiers in order")
  app.get "/lo-trinh",params:{tab:"council"}
  assert_rank([302,403,404].include?(app.response.status),"private council")
  app.get "/lo-trinh",params:{tab:"briefs"}
  assert_rank([302,403,404].include?(app.response.status),"private briefs")
  app.get "/lo-trinh/spotlight",params:{topic:flows.first.topic_id}
  assert_rank(JSON.parse(app.response.body)["eligible"]==true,"post action discovery")
  [[a, "council", "Chương trình nghị sự"], [a, "me", "Cấp 5 · Legendary"], [b, "me", "Tiến tới Guru"], [staff, "review", "Hồ sơ chờ duyệt"]].each do |user,tab,marker|
    signed = ActionDispatch::Integration::Session.new(Rails.application)
    signed.host! Discourse.current_hostname
    signed.https!
    # This session belongs to a synthetic account in the rolled-back transaction.
    session_token = UserAuthToken.generate!(user_id: user.id, client_ip: "127.0.0.1")
    signed.cookies[Auth::DefaultCurrentUserProvider::TOKEN_COOKIE] = session_token.unhashed_auth_token
    signed.get "/lo-trinh", params: {tab: tab}
    assert_rank(signed.response.status==200 && signed.response.body.include?(marker), "signed-in #{tab} #{signed.response.status}")
    if user == b
      signed.get "/lo-trinh", params: {tab: "council"}
      assert_rank([302,403,404].include?(signed.response.status), "lower rank cannot enter council")
    end
  end
  puts "PASS five tiers; four sequential awards; 89/90 days; distinct teams on the same initiative; independent council review and resubmission; advisory agenda; staff and VIP isolation; routes"
  raise ActiveRecord::Rollback
end
