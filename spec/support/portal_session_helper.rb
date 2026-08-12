# frozen_string_literal: true

# Usado pelos request specs de Portal::* -- loga via sessão do mesmo
# jeito que Portal::SessionsController#create.
module PortalSessionHelper
  def sign_in_as_user(user, password: "senha1234")
    post portal_session_path, params: { email: user.email, password: password }
  end
end

RSpec.configure do |config|
  config.include PortalSessionHelper, type: :request
end
