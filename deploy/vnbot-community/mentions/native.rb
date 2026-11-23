# frozen_string_literal: true
require "base64"
require "openssl"

# Native Discourse webhook -> signed workspace result -> native single-user REST API.
module VNBotCommunityNative
  extend self
  Bridge = VNBotCommunityMentions
  NS = "vnbot_community_native_v2"
  ORIGIN = "https://community.vnbot.run"
  SCHEMA = "vnbot.community.mention.v2"
  TTL = 45.minutes

  def get(name)
    PluginStore.get(NS, name)
  end

  def set(name, value)
    PluginStore.set(NS, name, value)
  end

  def enabled?
    Discourse.base_url == ORIGIN && get("enabled") == true
  end

  def paired_hook
    WebHook.find_by(id: get("hook_id"), payload_url: "#{ORIGIN}/vnbot-community/events", active: true)
  end

  def eligible?(post)
    return false unless Bridge.eligible?(post, Bridge.bot) { |category| paired_hook&.categories&.exists?(category.id) }
    markup = Nokogiri::HTML5.fragment(post.cooked)
    markup.css("aside.quote,blockquote,pre,code").remove
    markup.css("a.mention").any? { |a| a["href"].to_s.casecmp?("/u/vnbot") && a.text.casecmp?("@vnbot") }
  end

  def prepare(id)
    return unless enabled?
    Bridge.locked(id) do
      post = Post.find_by(id: id)
      next unless eligible?(post)
      next if Bridge.state(id)&.fetch("reply_id", nil)
      state = get("p#{id}")
      if !state
        next if Post.with_deleted.exists?(topic_id: post.topic_id, reply_to_post_number: post.post_number, user_id: Bridge.bot.id)
        body = Bridge.payload(post)
        state = {"event" => SecureRandom.uuid, "expires" => TTL.from_now.to_i,
                 "digest" => Bridge.digest(body), "ids" => body[:related].pluck(:id)}
        set("p#{id}", state)
      end
      next if state["reply_id"] || state["sent"] || state["raw"] || state["expires"] < Time.now.to_i
      body = Bridge.payload(post, ids: state["ids"])
      next unless state["digest"] == Bridge.digest(body)
      body.merge(schema: SCHEMA, event_id: state["event"])
    end
  end

  def send_question(id)
    packet = prepare(id)
    return unless packet
    uri, header, credential = Bridge.config
    request = Net::HTTP::Post.new(uri)
    request[header] = credential
    request["Content-Type"] = "application/json"
    request["Idempotency-Key"] = packet[:event_id]
    request.body = JSON.generate(packet)
    response = https(uri, request)
    raise "VNBot routine HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    Bridge.locked(id) do
      state = get("p#{id}")
      if state && state["event"] == packet[:event_id]
        state["sent"] = true
        set("p#{id}", state)
      end
    end
  end

  def https(uri, request)
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 25) { |http| http.request(request) }
  end

  def signed_event?(raw, signature)
    hook = paired_hook
    return false if !hook || hook.secret.blank? || !signature.match?(/\Asha256=[0-9a-f]{64}\z/)
    expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', hook.secret, raw)}"
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def signed_result?(raw, signature)
    der = get("workspace_public_der")
    return false if !der || !signature.match?(/\A[A-Za-z0-9+\/=]{88}\z/)
    OpenSSL::PKey.read(Base64.strict_decode64(der)).verify(nil, Base64.strict_decode64(signature), raw)
  rescue ArgumentError, OpenSSL::PKey::PKeyError
    false
  end

  def current_body(id, state)
    return if !state || state["expires"] < Time.now.to_i
    post = Post.find_by(id: id)
    return unless eligible?(post)
    body = Bridge.payload(post, ids: state["ids"])
    body if Bridge.digest(body) == state["digest"]
  end

  def accept_result(data)
    id = data["post_id"]
    answer = data["answer"]
    return 422 unless id.is_a?(Integer) && id.between?(1, 2_147_483_647) &&
      answer.is_a?(String) && answer.strip.length.between?(2, 1500)
    code = Bridge.locked(id) do
      state = get("p#{id}")
      next 404 unless state && state["event"] == data["event_id"]
      next 200 if state["reply_id"]
      body = current_body(id, state)
      next 410 unless body
      raw = Bridge.safe_text(answer)
      next 422 if raw.blank?
      links = body[:related].map { |t| "- [#{Bridge.safe_text(t[:title])}](/t/#{t[:id]})" }
      raw += "\n\n**Chủ đề liên quan**\n" + links.join("\n") if links.any?
      next 409 if state["raw"] && state["raw"] != raw
      state["raw"] = raw
      set("p#{id}", state)
      202
    end
    Jobs.enqueue(:vnbot_native_publish, post_id: id) if code == 202
    code
  end

  # This callback executes inside the native Post save transaction. Replayed API
  # requests take the same advisory lock and see the committed original reply.
  def reserve_reply!(reply)
    return unless enabled? && reply.user_id == Bridge.bot&.id && reply.post_type == Post.types[:regular]
    question = Post.find_by(topic_id: reply.topic_id, post_number: reply.reply_to_post_number)
    raise Discourse::InvalidAccess unless question
    Bridge.locked(question.id) do
      state = get("p#{question.id}")
      raise Discourse::InvalidAccess unless state && !state["reply_id"] && state["raw"] == reply.raw &&
        current_body(question.id, state)
      reply.instance_variable_set(:@community_question_id, question.id)
    end
  end

  def record_reply!(reply)
    id = reply.instance_variable_get(:@community_question_id)
    return unless id
    state = get("p#{id}")
    state["reply_id"] = reply.id
    state.delete("raw")
    set("p#{id}", state)
  end

  def publish(id)
    return unless enabled?
    state = get("p#{id}")
    return if !state || state["reply_id"] || !state["raw"] || !current_body(id, state)
    post = Post.find(id)
    key = Bridge.encryptor.decrypt_and_verify(get("api_sealed"), purpose: NS)
    request = Net::HTTP::Post.new("/posts.json")
    request["Api-Key"] = key
    request["Api-Username"] = Bridge.bot.username
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(topic_id: post.topic_id, reply_to_post_number: post.post_number, raw: state["raw"])
    response = https(URI(ORIGIN), request)
    return if get("p#{id}")&.fetch("reply_id", nil)
    raise "Discourse REST publication unconfirmed (HTTP #{response.code})"
  end

  class Endpoint
    def initialize(kind)
      @kind = kind
    end

    def call(env)
      native = VNBotCommunityNative
      return result(503) unless native.enabled?
      req = Rack::Request.new(env)
      return result(415) unless req.media_type == "application/json"
      limit = @kind == :event ? 2.megabytes : 12_288
      raw = req.body.read(limit + 1)
      return result(413) if raw.bytesize > limit
      if @kind == :event
        return result(403) unless native.signed_event?(raw, env["HTTP_X_DISCOURSE_EVENT_SIGNATURE"].to_s)
        return result(204) unless env["HTTP_X_DISCOURSE_EVENT"] == "post_created" &&
          env["HTTP_X_DISCOURSE_EVENT_TYPE"] == "post" && env["HTTP_X_DISCOURSE_INSTANCE"] == ORIGIN
        parsed = JSON.parse(raw)
        id = parsed.dig("post", "id") if parsed.is_a?(Hash) && parsed["post"].is_a?(Hash)
        return result(422) unless id.is_a?(Integer) && id.between?(1, 2_147_483_647)
        Jobs.enqueue(:vnbot_native_dispatch, post_id: id) if native.eligible?(Post.find_by(id: id))
        result(204)
      else
        return result(403) unless native.signed_result?(raw, env["HTTP_X_VNBOT_SIGNATURE"].to_s)
        data = JSON.parse(raw)
        result(data.is_a?(Hash) ? native.accept_result(data) : 422)
      end
    rescue JSON::ParserError
      result(400)
    end

    def result(code)
      [code, {"cache-control" => "no-store"}, []]
    end
  end
end

module Jobs
  class VnbotNativeDispatch < ::Jobs::Base
    def execute(args)
      VNBotCommunityNative.send_question(Integer(args.fetch(:post_id)))
    end
  end

  class VnbotNativePublish < ::Jobs::Base
    def execute(args)
      VNBotCommunityNative.publish(Integer(args.fetch(:post_id)))
    end
  end
end
