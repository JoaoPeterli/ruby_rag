# frozen_string_literal: true

class CreateAdminAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_audit_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.jsonb :details, null: false, default: {}

      t.timestamps
    end

    add_index :admin_audit_logs, :action
    add_index :admin_audit_logs, [ :target_type, :target_id ]
  end
end
