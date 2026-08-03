# frozen_string_literal: true

class CreateAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :api_key, null: false
      t.boolean :operator, default: false, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :accounts, :api_key, unique: true
  end
end
