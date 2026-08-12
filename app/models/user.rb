# frozen_string_literal: true

class User < ApplicationRecord
  belongs_to :account
  has_secure_password

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true

  scope :active, -> { where(active: true) }

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end
end
