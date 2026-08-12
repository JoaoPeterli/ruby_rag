# frozen_string_literal: true

class DisableVectorExtension < ActiveRecord::Migration[8.0]
  def change
    disable_extension "vector"
  end
end
