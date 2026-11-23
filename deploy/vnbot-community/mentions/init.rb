# frozen_string_literal: true
abort "Wrong host" unless Discourse.current_hostname == "community.vnbot.run"
ns = VNBotCommunityMentions::NS
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(274217, 3)")
  if PluginStore.get(ns, "bot_id")
    raise "Check the bot account ownership or privileges" unless VNBotCommunityMentions.bot
  else
    raise "Unmanaged username/group already exists" if User.find_by(username_lower:"vnbot") || Group.where("lower(name) = 'vnbot'").exists?
    address = "discourse-mentions@vnbot.invalid"
    raise "Unmanaged email already exists" if UserEmail.exists?(email:address)
    user = User.create!(username:"VNBot",name:"VNBot Community",email:address,active:true,
      approved:true, trust_level:1, password:SecureRandom.hex(32))
    raise "Unexpected bot privileges" if user.staff?
    PluginStore.set(ns,"bot_id",user.id)
  end
end
puts "Community bot id=#{VNBotCommunityMentions.bot.id}; configured=#{VNBotCommunityMentions.active?}"
