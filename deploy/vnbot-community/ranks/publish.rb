# frozen_string_literal: true
raise "Wrong forum" unless Discourse.current_hostname=="community.vnbot.run"
ActiveRecord::Base.transaction do
  VnRank::NAMES.each_with_index do |name,i|
    b=VnRank.badge(i)
    raise "Unexpected badge" unless b.name==name && b.allow_title
    b.update!(description:VnRank::RULES[i], long_description:"#{VnRank::RULES[i]} #{VnRank::BENEFITS[i]} <a href='/lo-trinh'>Xem lộ trình và nộp minh chứng</a>.")
  end
  id=PluginStore.get("vnbot_community_ops","guide")
  if id && (post=Topic.find(id).first_post)
    raw=post.raw
    unless raw.include?("/lo-trinh?tab=review")
      # Replace only the former rank instructions, preserving the independent VIP rules.
      head, marker, tail=raw.partition("**VIP.**")
      updated="**Xét danh hiệu.** Thành viên và người dùng thử gửi minh chứng tại [Lộ trình chuyên gia](/lo-trinh). Moderator đối chiếu hồ sơ trong [Hàng chờ xét duyệt](/lo-trinh?tab=review). Admin khác người nộp thực hiện trao hạng qua hàng chờ khi hệ thống xác nhận đủ tiêu chí. Quyền lớp và VIP được cấp riêng.\n\n"
      if marker.present? && head.start_with?("**Xét danh hiệu hằng tuần.**")
        raw=updated+marker+tail
      else
        raw=updated+raw
      end
      post.revise(Discourse.system_user,{raw:raw},skip_validations:true)
    end
  end
end
