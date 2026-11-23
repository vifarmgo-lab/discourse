# frozen_string_literal: true
abort "Wrong forum" unless Discourse.current_hostname == "community.vnbot.run"
ns = "vnbot_community_ops"
group = Group.find(PluginStore.get(ns,"vip_group"))
category = Category.find(PluginStore.get(ns,"vip_category"))
ActiveRecord::Base.transaction do
  user = User.new(username:"rankqa#{SecureRandom.hex(4)}",email:"rank#{SecureRandom.hex(7)}@example.invalid",active:true,trust_level:1)
  user.save!(validate:false)
  raise "VIP unexpectedly visible" if user.guardian.can_see?(category)
  %w[expert master guru].each do |rank|
    badge=Badge.find(PluginStore.get(ns,"badge_#{rank}"))
    raise "Invalid title setup" unless badge.enabled? && badge.allow_title? && !badge.multiple_grant?
    BadgeGranter.grant(badge,user)
    raise "Unsuccessful grant: #{rank}" unless UserBadge.exists?(user_id:user.id,badge_id:badge.id)
  end
  raise "Badge grants changed VIP" if Guardian.new(User.find(user.id)).can_see?(category)
  group.add(user)
  raise "Group grant failed" unless Guardian.new(User.find(user.id)).can_see?(category)
  group.remove(user)
  raise "Group removal failed" if Guardian.new(User.find(user.id)).can_see?(category)
  puts "PASS: 3 manual title badge grants; VIP denied before grant, allowed in group, denied after removal"
  raise ActiveRecord::Rollback
end
