# frozen_string_literal: true
require "net/http"
require "digest"
require "securerandom"
require "json"

module VNBotCommunityMentions
  extend self
  NS = "vnbot_community_mentions_v1"
  FILE = "/shared/vnbot-community/mention-connection.json"
  ENABLED_CATEGORY_SLUGS = %w[hoi-dap-bao-loi chung].freeze
  SCHEMA = "vnbot.community.mention.v1"
  TTL = 45.minutes
  def config
    data = if File.file?(FILE)
      JSON.parse(File.read(FILE))
    else
      from_admin_form
    end
    validate_connection(data)
  end
  def validate_connection(data)
    url = URI.parse(data.fetch("url"))
    raise "Invalid VNBot URL" unless url.is_a?(URI::HTTPS) && url.port == 443 && url.userinfo.nil? &&
      url.host.to_s.match?(/\A(?:[a-z0-9-]+\.)*vnbot\.run\z/i) && url.fragment.nil?
    key = data.fetch("header")
    value = data.fetch("value")
    raise "Invalid webhook header" unless key.match?(/\A(?:authorization|x-[a-z0-9-]+)\z/i) &&
      value.is_a?(String) && value.length.between?(12, 2048) && value.ascii_only? && !value.match?(/[[:cntrl:]]/)
    [url, key, value]
  end
  def active?
    Discourse.current_hostname == "community.vnbot.run" && (File.file?(FILE) || (File.file?(ENDPOINT) && PluginStore.get(NS, "sealed_header").present?))
  end
  def bot
    id = PluginStore.get(NS, "bot_id")
    user = User.find_by(id: id) if id
    user if user && user.username_lower == "vnbot" && user.active? && !user.staff? && !user.suspended?
  end
  def eligible?(post, bot_user)
    return false unless post && bot_user && post.user && post.user_id != bot_user.id && post.user_id.positive? &&
      post.post_type == Post.types[:regular] && !post.hidden? && !post.deleted_at && !post.user.suspended?
    topic = post.topic
    return false unless topic && topic.archetype == Archetype.default && topic.visible? && !topic.deleted_at &&
      !topic.closed? && !topic.archived? && ENABLED_CATEGORY_SLUGS.include?(topic.category&.slug) && !topic.category.read_restricted?
    return false if topic.category.topic_id == topic.id
    [Guardian.new, bot_user.guardian, post.user.guardian].all? { |g| g.can_see?(topic) && g.can_see?(post) } &&
      bot_user.guardian.can_create_post_on_topic?(topic) &&
      post.mentions.any? { |name| name.to_s.casecmp?("vnbot") }
  end
  def plain(post, limit)
    doc = Nokogiri::HTML5.fragment(post.cooked.to_s)
    doc.css("aside.quote, blockquote, script, style, img, iframe").remove
    doc.css("p,li,br,pre").each { |node| node.add_next_sibling(Nokogiri::XML::Text.new(" ",doc.document)) }
    doc.text.squish.first(limit)
  end
  def words(text)
    text.downcase.scan(/[[:alnum:]]{3,}/).uniq - %w[vnbot được trong muốn community những không giúp mình cách đang diễn]
  end
  def topics_for(post)
    return [] unless post.topic.category_id
    guards = [Guardian.new, post.user.guardian, bot.guardian]
    Topic.where(category_id: post.topic.category_id, archetype: Archetype.default, visible: true)
      .where.not(id: [post.topic_id,post.topic.category.topic_id].compact).order(bumped_at: :desc).limit(120)
      .select { |t| guards.all? { |g| g.can_see?(t) } }
  end
  def payload(post, ids: nil)
    topic = post.topic
    guards = [Guardian.new, post.user.guardian, bot.guardian]
    history = Post.where(topic_id: topic.id, post_type: Post.types[:regular], hidden: false)
      .where("post_number <= ?",post.post_number).order(post_number: :desc).limit(14).to_a
    first = topic.first_post
    history << first if first && !history.any? { |p| p.id == first.id }
    excerpts = history.sort_by(&:post_number).filter_map do |p|
      next unless p.post_type == Post.types[:regular] && !p.hidden? && !p.deleted_at && guards.all? { |g| g.can_see?(p) }
      { post_number: p.post_number, text: plain(p, 620) }
    end
    candidates = topics_for(post)
    if ids
      by_id = candidates.index_by(&:id)
      candidates = ids.filter_map { |id| by_id[id] }
    else
      keys = words("#{topic.title} #{plain(post, 800)}")
      candidates = candidates.map { |t| [t,(keys & words(t.title)).size] }.select { |_,n| n.positive? }
        .sort_by { |t,n| [-n,-t.bumped_at.to_i,t.id] }.first(3).map(&:first)
    end
    {schema: SCHEMA, post_id: post.id, topic_id: topic.id, category_id: topic.category_id,
     title: topic.title, question: plain(post, 2000), excerpts: excerpts,
     related: candidates.map { |t| {id: t.id, title: t.title} }}
  end
  def locked(id)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{Integer(id) + 600000000000})")
      yield
    end
  end
  def state(id)
    PluginStore.get(NS, "post_#{id}")
  end
  def save(id, data)
    PluginStore.set(NS, "post_#{id}", data)
  end
  def token(id, s)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{NS}:#{id}:#{s['nonce']}:#{s['digest']}")
  end
  def digest(body)
    Digest::SHA256.hexdigest(JSON.generate(body))
  end
  def dispatch(id)
    return unless active?
    url,key,value = config
    packet = locked(id) do
      post = Post.find_by(id:id)
      next unless eligible?(post,bot)
      s = state(id)
      next if s && (s["reply_id"] || s["delivered_at"] || s["expires"] < Time.now.to_i)
      b = payload(post, ids: s && s["ids"])
      if s
        next unless s["digest"] == digest(b)
      else
        s = {"nonce"=>SecureRandom.hex(16),"expires"=>TTL.from_now.to_i,"digest"=>digest(b),
             "ids"=>b[:related].pluck(:id)}
        save(id,s)
      end
      if s["dispatch_until"].to_i > Time.now.to_i
        Jobs.enqueue_in(60.seconds, :vnbot_community_mention, post_id: id)
        next
      end
      s["dispatch_until"] = 45.seconds.from_now.to_i
      save(id,s)
      b.merge(event_id: "community-post-#{id}", reply_token: token(id,s))
    end
    return unless packet
    req = Net::HTTP::Post.new(url)
    req[key] = value
    req["Content-Type"] = "application/json"
    req["Idempotency-Key"] = packet[:event_id]
    req.body = JSON.generate(packet)
    response = Net::HTTP.start(url.host,url.port,use_ssl:true,open_timeout:5,read_timeout:20) { |http| http.request(req) }
    raise "Community webhook returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
    locked(id) do
      s = state(id)
      s["delivered_at"] = Time.now.to_i
      save(id,s)
    end
  end
  def safe_text(s)
    s.to_s.gsub(/https?:\/\/\S+|www\.\S+/i, "").gsub(/[[:cntrl:]&&[^\n]]/, "").strip
      .gsub(/[^[:alnum:][:space:]]/) { |c| "&##{c.ord};" }
  end
  def accept(id, provided, answer)
    locked(id) do
      s = state(id)
      next 403 unless s && provided.match?(/\A[a-f0-9]{64}\z/) && ActiveSupport::SecurityUtils.secure_compare(provided,token(id,s))
      next 200 if s["reply_id"]
      next 410 unless active? && s["expires"] >= Time.now.to_i
      post = Post.find_by(id:id)
      next 410 unless eligible?(post,bot)
      b = payload(post,ids:s["ids"])
      next 409 unless s["digest"] == digest(b)
      next 422 unless answer.is_a?(String) && answer.strip.length.between?(2,2000) && !answer.include?(provided)
      raw = safe_text(answer)
      next 422 if raw.blank?
      links = b[:related].map { |t| "- [#{safe_text(t[:title])}](/t/#{t[:id]})" }
      raw += "\n\n**Chủ đề liên quan**\n" + links.join("\n") if links.any?
      reply = PostCreator.create!(bot, topic_id: post.topic_id, reply_to_post_number: post.post_number, raw: raw, skip_validations: true)
      s["reply_id"] = reply.id
      save(id,s)
      201
    end
  end
  class Reply
    def call(env)
      req = Rack::Request.new(env)
      return result(415) unless req.media_type == "application/json"
      raw = req.body.read(12_289)
      return result(413) if raw.bytesize > 12_288
      data = JSON.parse(raw)
      return result(422) unless data.is_a?(Hash) && data["post_id"].is_a?(Integer) && data["post_id"].between?(1,2_147_483_647)
      bearer = env["HTTP_AUTHORIZATION"].to_s[/\ABearer ([a-f0-9]{64})\z/,1]
      return result(403) unless bearer
      result(VNBotCommunityMentions.accept(data["post_id"],bearer,data["answer"]))
    rescue JSON::ParserError
      result(400)
    end
    def result(code)
      [code,{"content-type"=>"application/json","cache-control"=>"no-store"},[JSON.generate(status: code)]]
    end
  end
end

module Jobs
  class VnbotCommunityMention < ::Jobs::Base
    def execute(args)
      VNBotCommunityMentions.dispatch(Integer(args.fetch(:post_id)))
    end
  end
end
