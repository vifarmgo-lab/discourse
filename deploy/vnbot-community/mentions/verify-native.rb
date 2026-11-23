# frozen_string_literal: true
# Exercises a real native post save and a signature round trip without external I/O.
require "rack/mock"
m = VNBotCommunityNative
b = m::Bridge
raise "Wrong forum" unless Discourse.base_url == m::ORIGIN && b.bot
def check(label, ok)
  raise "FAIL: #{label}" unless ok
  puts "PASS #{label}"
end
ActiveRecord::Base.transaction do
  hook = WebHook.new(payload_url: "#{m::ORIGIN}/vnbot-community/events", active: true, secret: SecureRandom.hex(32))
  hook.save!(validate: false)
  signing = OpenSSL::PKey.generate_key("ED25519")
  m.set("workspace_public_der", Base64.strict_encode64(signing.public_to_der))
  m.set("enabled", true)
  m.set("hook_id", hook.id)
  event = '{"post":{"id":1}}'
  check("signed webhook", m.signed_event?(event, "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', hook.secret, event)}"))
  check("unsigned webhook", !m.signed_event?(event, ""))
  check("workspace signature", m.signed_result?(event, Base64.strict_encode64(signing.sign(nil, event))))
  check("changed result rejected", !m.signed_result?(event + " ", Base64.strict_encode64(signing.sign(nil, event))))
  general = Category.find_by!(slug: "chung")
  user = User.new(username:"qa#{SecureRandom.hex(4)}",email:"qa#{SecureRandom.hex(4)}@example.invalid",active:true,trust_level:1)
  user.save!(validate:false)
  topic = Topic.create!(title:"Community webhook QA #{SecureRandom.hex(4)}", category:general, user:user)
  question = Post.new(topic:topic,user:user,post_number:1,raw:"@VNBot Tóm tắt bài kiểm tra.",
                      cooked:'<p><a class="mention" href="/u/vnbot">@VNBot</a> Tóm tắt bài kiểm tra.</p>')
  question.disable_rate_limits!
  question.save!(validate:false)
  check("empty webhook category list denies mentions", !m.eligible?(question))
  hook.categories << general
  check("direct mention in a selected category", m.eligible?(question))
  news = Category.find_by!(slug: "ban-tin-ai")
  topic.update_column(:category_id, news.id)
  check("unselected public category denied", !m.eligible?(question.reload))
  hook.categories << news
  check("newly selected public category accepted", m.eligible?(question))
  hook.categories.delete(news)
  check("removing a category takes effect immediately", !m.eligible?(question))
  topic.update_column(:category_id, general.id)
  question.reload
  question.update_column(:cooked, "<blockquote>#{question.cooked}</blockquote>")
  check("quoted mention ignored", !m.eligible?(question.reload))
  question.update_column(:cooked, '<a class="mention" href="/u/vnbot">@VNBot</a> Hỏi một câu.')
  message = m.prepare(question.id)
  check("packet omits posting secrets", message[:event_id] && !message.key?(:reply_token))
  state = m.get("p#{question.id}")
  state["raw"] = "Đây là một câu trả lời mẫu để kiểm tra tính duy nhất."
  m.set("p#{question.id}", state)
  reply_opts = {topic:topic, user:b.bot, post_number:2, reply_to_post_number:1, raw:state["raw"], cooked:"<p>test</p>"}
  vip = Category.find_by!(slug:"vnbot-vip")
  hook.categories << vip
  topic.update_column(:category_id, vip.id)
  check("moved-to-private topic rejected", m.current_body(question.id, state).nil?)
  topic.update_column(:category_id, general.id)
  reply = Post.new(reply_opts)
  reply.disable_rate_limits!
  reply.save!(validate:false)
  check("reply receipt saved in same transaction", m.get("p#{question.id}")["reply_id"] == reply.id)
  begin
    duplicate = Post.new(reply_opts.merge(post_number:3))
    duplicate.disable_rate_limits!
    duplicate.save!(validate:false)
    raise "Duplicate unexpectedly persisted"
  rescue Discourse::InvalidAccess
    check("duplicate delivery rejected", true)
  end
  raise ActiveRecord::Rollback
end
