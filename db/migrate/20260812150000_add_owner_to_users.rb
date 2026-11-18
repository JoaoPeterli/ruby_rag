class AddOwnerToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :owner, :boolean, null: false, default: false
  end
end
