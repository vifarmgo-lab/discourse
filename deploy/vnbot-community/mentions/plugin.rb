# frozen_string_literal: true
# name: vnbot-community-mentions
# about: Route explicitly mentioned, publicly readable Community Q&A posts to the dedicated VNBot workspace
# version: 1.0
# authors: AIKING

after_initialize do
  require File.expand_path("bridge", __dir__)
  require File.expand_path("admin_connection", __dir__)
  Discourse::Application.routes.append do
    get "/vnbot-community/connection", to: "vn_bot_community_connection#show"
    post "/vnbot-community/connection", to: "vn_bot_community_connection#update"
    post "/vnbot-community/reply", to: VNBotCommunityMentions::Reply.new
  end
  DiscourseEvent.on(:post_created) do |post, _opts, _user|
    next unless post.raw.to_s.match?(/@vnbot\b/i) && VNBotCommunityMentions.active?
    id = post.id
    ActiveRecord.after_all_transactions_commit { Jobs.enqueue(:vnbot_community_mention, post_id: id) }
  end
end
