# frozen_string_literal: true
require "cgi"

module VNBotCommunityMentions
  ENDPOINT = "/shared/vnbot-community/mention-endpoint"
  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("vnbot-community-webhook-header-v1",32),
      cipher: "aes-256-gcm",serializer: JSON
    )
  end
  def self.from_admin_form
    endpoint = File.read(ENDPOINT).strip
    sealed = PluginStore.get(NS,"sealed_header")
    values = encryptor.decrypt_and_verify(sealed,purpose: Digest::SHA256.hexdigest(endpoint)) if sealed
    raise "Webhook authorization required" unless values.is_a?(Hash)
    values.merge("url"=>endpoint)
  end
  def self.install_header(text)
    raise ArgumentError if !File.file?(ENDPOINT) || File.file?(FILE)
    endpoint = File.read(ENDPOINT).strip
    raise ArgumentError unless text.is_a?(String) && text.bytesize.between?(12,2150) && !text.strip.match?(/[[:cntrl:]]/)
    clean = text.strip
    if clean.match?(/\ABearer\s+/i)
      name,value = "Authorization",clean
    else
      name,value = clean.split(":",2).map(&:strip)
    end
    raise ArgumentError unless name.present? && value.present? && name.match?(/\A(?:Authorization|X-[A-Za-z0-9-]+)\z/i) &&
      !value.match?(/\*{3,}|•{3,}/) && !value.match?(/\Ahttps?:/i)
    data = {"header"=>name,"value"=>value}
    validate_connection(data.merge("url"=>endpoint))
    sealed = encryptor.encrypt_and_sign(data,purpose: Digest::SHA256.hexdigest(endpoint))
    PluginStore.set(NS,"sealed_header",sealed)
  end
end

class VnBotCommunityConnectionController < Admin::AdminController
  # A standard same-origin HTML form with Discourse's usual session, admin and CSRF checks.
  skip_before_action :check_xhr
  before_action :private_response
  def show
    render_form
  end
  def update
    return head :forbidden unless request.origin == Discourse.base_url && !is_api? && !is_user_api?
    VNBotCommunityMentions.install_header(params[:secret_header])
    redirect_to "/vnbot-community/connection?saved=1", status: :see_other
  rescue ArgumentError, URI::InvalidURIError, RuntimeError
    render_form("Chưa lưu. Hãy sao chép toàn bộ dòng Tiêu đề xác thực của đúng quy trình VNBot Community.", status: :unprocessable_entity)
  end
  private
  def private_response
    response.headers["Cache-Control"] = "no-store"
    # Chrome needs the form origin for a normal same-site POST.
    response.headers["Referrer-Policy"] = "same-origin"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Content-Security-Policy"] = "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"
  end
  def render_form(error=nil,status: :ok)
    ready = File.file?(VNBotCommunityMentions::ENDPOINT) && !File.file?(VNBotCommunityMentions::FILE)
    saved = params[:saved] == "1" && VNBotCommunityMentions.active?
    message = error || (saved ? "Đã lưu Tiêu đề trên máy chủ Community." : "")
    token = CGI.escapeHTML(form_authenticity_token)
    form = if ready
      <<~HTML
        <form method="post" action="/vnbot-community/connection" autocomplete="off">
          <input type="hidden" name="authenticity_token" value="#{token}">
          <label for="secret_header">Tiêu đề xác thực webhook</label>
          <input id="secret_header" name="secret_header" type="password" autocomplete="new-password" spellcheck="false" required maxlength="2150">
          <button type="submit">Lưu kết nối</button>
        </form>
      HTML
    else
      "<p>Đầu nhận hiện được quản lý qua console GDATA.</p>"
    end
    page = <<~HTML
      <!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Kết nối VNBot · VNBot Community</title>
      <style>body{font:17px/1.55 system-ui,sans-serif;color:#18342b;margin:0;background:#f6f8f7}main{box-sizing:border-box;max-width:640px;margin:8vh auto;background:white;padding:clamp(20px,5vw,44px);border:1px solid #d3ddd7;border-radius:12px}h1{line-height:1.2}label{font-weight:650;display:block}input[type=password]{display:block;width:100%;box-sizing:border-box;padding:12px;border:1px solid #85968b;border-radius:6px;margin:8px 0 18px;font:inherit}button{font:inherit;color:white;background:#23624c;border:0;border-radius:6px;padding:10px 22px}a{color:#235e49}</style></head>
      <body><main><h1>Kết nối VNBot</h1><p>Trong workspace <strong>VNBot Community</strong>, mở bot <strong>VNBot</strong> và quy trình <strong>Trả lời khi được nhắc trên Community</strong>. Bấm <strong>Sao chép Tiêu đề</strong> rồi dán vào ô bên dưới. URL của quy trình do máy chủ GDATA quản lý.</p>
      <p role="status">#{CGI.escapeHTML(message)}</p>#{form}<p><a href="/c/hoi-dap-bao-loi/6">Mở Hỏi đáp &amp; báo lỗi</a></p></main></body></html>
    HTML
    render html: page.html_safe, status: status, layout:false
  end
end
