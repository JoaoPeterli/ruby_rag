class CreateDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :documents do |t|
      t.string :title, null: false
      t.string :source
      t.string :status, null: false, default: "pending"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
