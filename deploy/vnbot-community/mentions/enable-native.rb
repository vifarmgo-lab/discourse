# frozen_string_literal: true
# Run on AI-Server01 after installing the adapter and the workspace sender.
m = VNBotCommunityNative
raise "Wrong forum" unless Discourse.base_url == m::ORIGIN
bot = m::Bridge.bot
raise "Dedicated nonstaff bot required" unless bot && !bot.staff? && m::Bridge.active?
m::Bridge.config
der = ENV.fetch("COMMUNITY_PUBLIC_DER")
key = OpenSSL::PKey.read(Base64.strict_decode64(der))
raise "Workspace public Ed25519 key required" unless key.oid == "ED25519" && key.public_to_der == Base64.strict_decode64(der)
categories = Category.where(slug: m::Bridge::ENABLED_CATEGORY_SLUGS).to_a
raise "Expected both public categories" unless categories.size == 2 && categories.none?(&:read_restricted?)
m::Bridge.locked(0) do
  pinned = m.get("workspace_public_der")
  raise "Workspace public key changed; review pairing" if pinned && pinned != der
  if (api_id = m.get("api_id"))
    api = ApiKey.active.find(api_id)
    raise "Review bot API configuration" unless api.user_id == bot.id && api.granular? &&
      api.api_key_scopes.pluck(:resource, :action) == [["topics","write"]] &&
      ApiKey.hash_key(m::Bridge.encryptor.decrypt_and_verify(m.get("api_sealed"), purpose: m::NS)) == api.key_hash
  else
    api = ApiKey.new(user: bot, created_by: Discourse.system_user, description: "VNBot Community — trả lời lượt nhắc", scope_mode: :granular)
    api.api_key_scopes.build(resource: "topics", action: "write")
    api.save!
    m.set("api_sealed", m::Bridge.encryptor.encrypt_and_sign(api.key, purpose: m::NS))
    m.set("api_id", api.id)
  end
  url = "#{m::ORIGIN}/vnbot-community/events"
  hook = m.get("hook_id") ? WebHook.find(m.get("hook_id")) : WebHook.new(payload_url: url)
  raise "Review existing webhook" if hook.payload_url != url || (hook.new_record? && WebHook.exists?(payload_url: url))
  hook.secret = SecureRandom.hex(32) if hook.secret.blank?
  hook.assign_attributes(active: true, verify_certificate: true, wildcard_web_hook: false,
                         categories: categories, web_hook_event_types: [WebHookEventType.find_by!(name: "post_created")])
  hook.save!
  m.set("workspace_public_der", der)
  m.set("hook_id", hook.id)
  m.set("enabled", true)
end
puts "Native webhook enabled, scoped single-user posting key provisioned on GDATA."
