# frozen_string_literal: true
raise "Unexpected forum" unless Discourse.current_hostname == "community.vnbot.run"
ActiveRecord::Base.transaction do
  db = ActiveRecord::Base.connection
  db.execute("SELECT pg_advisory_xact_lock(82196604)")
  unless db.table_exists?(:vnbot_rank_entries)
    db.create_table(:vnbot_rank_entries) do |t|
      t.string :kind, null: false
      t.bigint :user_id, null: false
      t.string :entry_key, null: false
      t.bigint :topic_id
      t.bigint :peer_id
      t.bigint :parent_id
      t.string :state, null: false
      t.text :note, null: false, default: ""
      t.jsonb :details, null: false, default: {}
      t.bigint :reviewer_id
      t.timestamps
    end
    db.add_index :vnbot_rank_entries, [:kind,:user_id,:entry_key], unique: true, name: "vn_rank_identity"
    db.add_index :vnbot_rank_entries, [:kind,:state,:topic_id], name: "vn_rank_topic"
    db.add_index :vnbot_rank_entries, [:kind,:peer_id,:state], name: "vn_rank_confirm"
  end
end
