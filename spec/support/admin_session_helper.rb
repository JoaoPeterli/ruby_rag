# frozen_string_literal: true

# Usado pelos request specs de Admin::* — loga via sessão (não Bearer
# token) do mesmo jeito que Admin::SessionsController#create.
module AdminSessionHelper
  def sign_in_as(account)
    post admin_session_path, params: { api_key: account.api_key }
  end
end

RSpec.configure do |config|
  config.include AdminSessionHelper, type: :request
end
