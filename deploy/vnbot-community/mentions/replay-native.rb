# frozen_string_literal: true
# Rerun the official webhook job for one mentioned post, isolated to the paired hook.
m = VNBotCommunityNative
raise "Native delivery disabled" unless m.enabled?
post = Post.find(Integer(ENV.fetch("COMMUNITY_POST_ID")))
raise "Ineligible post" unless m.eligible?(post)
hook = WebHook.find(m.get("hook_id"))
raise "Webhook mismatch" unless hook.active? && hook.payload_url == "#{m::ORIGIN}/vnbot-community/events"
Jobs.enqueue(:emit_web_hook_event, web_hook_id: hook.id, event_name: "post_created", event_type: "post",
             id: post.id, category_id: post.topic.category_id, tag_ids: post.topic.tags.pluck(:id),
             payload: WebHook.generate_payload(:post, post))
puts "Queued native delivery for eligible post #{post.id}."
