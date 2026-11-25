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
    submit(u,"rank")
    row=VnRank::Entry.find_by!(kind:"rank",user_id:u.id,entry_key:i.to_s)
    submit(staff,"approve",id:row.id)
    submit(staff,"approve",id:row.id)
    assert_rank(VnRank.level(u)==i+1,"sequential award")
  end
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
  # Exercise actual routes and templates under isolated local request sessions.
  app=ActionDispatch::Integration::Session.new(Rails.application)
  app.host! Discourse.current_hostname
  app.https!
  %w[start trials verified directory events].each do |tab|
    app.get "/lo-trinh",params:{tab:tab}
    assert_rank(app.response.status==200 && app.response.body.include?("Lộ trình chuyên gia"),"guest GET #{tab}: #{app.response.status}")
  end
  app.get "/lo-trinh",params:{tab:"briefs"}
  assert_rank([302,403,404].include?(app.response.status),"private briefs")
  app.get "/lo-trinh/spotlight",params:{topic:flows.first.topic_id}
  assert_rank(JSON.parse(app.response.body)["eligible"]==true,"post action discovery")
  puts "PASS four independent workflows, distinct testers, three ranks, human review, workshop enrollment, Guru brief, VIP isolation and public web routes"
  raise ActiveRecord::Rollback
end
