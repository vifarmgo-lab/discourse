# frozen_string_literal: true
# Exercise the application logic in one rollback-only transaction, without calling the agent.
require "rack/mock"
m = VNBotCommunityMentions
raise "Wrong forum or service identity" unless Discourse.current_hostname == "community.vnbot.run" && m.bot && !m.bot.staff?
def assertion(label, passed)
  raise "FAIL: #{label}" unless passed
  puts "PASS: #{label}"
end
ActiveRecord::Base.transaction do
  q = Category.find_by!(slug:m::PILOT)
  klass = Category.find_by!(slug:"lop-thu-nghiem")
  vip = Category.find_by!(slug:"vnbot-vip")
  qa = User.new(username:"qa#{SecureRandom.hex(4)}",email:"qa#{SecureRandom.hex(5)}@example.invalid",active:true,trust_level:1)
  qa.save!(validate:false)
  topic = Topic.create!(title:"Kiểm tra nội bộ #{SecureRandom.hex(4)}", category:q, user:qa)
  question = Post.new(topic:topic,user:qa,post_number:1,raw:"@VNBot tóm tắt chủ đề kiểm thử này",cooked:'<p><a class="mention">@VNBot</a> tóm tắt chủ đề kiểm thử này</p>')
  question.save!(validate:false)
  assertion("public mention accepted",m.eligible?(question,m.bot))
  assertion("invalid callback rejected",m.accept(question.id,"0"*64,"demo") == 403)
  [klass,vip].each do |private_room|
    topic.update_column(:category_id,private_room.id)
    question.reload
    assertion("restricted #{private_room.slug} denied",!m.eligible?(question,m.bot) && !Guardian.new.can_see?(topic.reload))
  end
  topic.update_column(:category_id,q.id)
  question.reload
  whisper = Post.new(topic:topic,user:qa,post_number:2,post_type:Post.types[:whisper],raw:"STAFF_TEST_DATA",cooked:"STAFF_TEST_DATA")
  whisper.save!(validate:false)
  assertion("whisper not a trigger",!m.eligible?(whisper,m.bot))
  b=m.payload(question)
  assertion("summary includes the question but no staff text",b[:question].include?("tóm tắt") && !b.to_json.include?("STAFF_TEST_DATA"))
  question.update_column(:cooked,"<p>VNBot trong văn bản thường</p>")
  assertion("unmentioned post ignored",!m.eligible?(question.reload,m.bot))
  question.update_column(:cooked,'<p><a class="mention">@VNBot</a> câu hỏi thử</p>')
  question.reload
  body=m.payload(question)
  s={"nonce"=>SecureRandom.hex(16),"expires"=>45.minutes.from_now.to_i,"digest"=>m.digest(body),"ids"=>body[:related].pluck(:id)}
  m.save(question.id,s)
  tok=m.token(question.id,s)
  topic.update_column(:category_id,klass.id)
  assertion("reply denied after category moves private",m.accept(question.id,tok,"Câu trả lời thử.") == 410)
  topic.update_column(:category_id,q.id)
  # With no connection file, the production gate also rejects authentic callbacks.
  if m.active?
    assertion("authentic reply written once",m.accept(question.id,tok,"Một câu trả lời thử nghiệm.") == 201)
    assertion("callback retry returns previous result",m.accept(question.id,tok,"Một lần nữa.") == 200)
  end
  assertion("live VIP is inaccessible to nonmembers",!qa.guardian.can_see?(vip))
  raise ActiveRecord::Rollback
end
puts "PASS: rollback complete; production users and posts unchanged by this test"
