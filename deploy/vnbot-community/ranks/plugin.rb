# frozen_string_literal: true
# name: vnbot-community-ranks
# about: Verified workflows, mentorship, and opportunities in VNBot Community
# version: 1.0
# authors: AIKING

navigation = File.read(File.expand_path("navigation.js", __dir__)).html_safe
register_html_builder("server:before-body-close") do |controller|
  view = controller.view_context
  view.content_tag(:script, navigation, id: "vnbot-rank-navigation", nonce: view.csp_nonce_placeholder)
end

after_initialize do
  require_relative "program"
  require_relative "controller"
  Discourse::Application.routes.prepend do
    get "/lo-trinh/assets/style.css", to: "vn_rank#style", format: false
    get "/lo-trinh/spotlight", to: "vn_rank#spotlight"
    get "/lo-trinh", to: "vn_rank#index"
    post "/lo-trinh", to: "vn_rank#update"
  end
end
