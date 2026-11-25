# frozen_string_literal: true
# name: vnbot-community-ranks
# about: Verified workflows, mentorship, and opportunities in VNBot Community
# version: 1.0
# authors: AIKING

register_html_builder("server:before-body-close") do
  '<script defer src="/lo-trinh/assets/navigation.js"></script>'.html_safe
end

after_initialize do
  require_relative "program"
  require_relative "controller"
  Discourse::Application.routes.prepend do
    get "/lo-trinh/assets/navigation.js", to: "vn_rank#navigation", format: false
    get "/lo-trinh/assets/style.css", to: "vn_rank#style", format: false
    get "/lo-trinh/spotlight", to: "vn_rank#spotlight"
    get "/lo-trinh", to: "vn_rank#index"
    post "/lo-trinh", to: "vn_rank#update"
  end
end
