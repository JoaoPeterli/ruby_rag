require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RubyRagJlp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # O painel admin (Admin::*, ver app/controllers/admin/) precisa de
    # sessão/cookies pra login — reativado só pra isso, a API sob
    # api/v1/* (ApplicationController < ActionController::API) continua
    # sem esse middleware.
    config.session_store :cookie_store, key: "_ruby_rag_jlp_admin_session"
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options
    config.middleware.use ActionDispatch::Flash

    config.active_job.queue_adapter = :sidekiq

    # schema.rb (Ruby DSL) não captura triggers/functions SQL crus,
    # como o document_chunks_search_vector_trigger. Sem isso, o banco
    # de teste (carregado a partir do schema) fica sem o trigger e
    # search_vector nunca é preenchido. structure.sql captura tudo.
    config.active_record.schema_format = :sql

    config.generators do |g|
      g.test_framework :rspec, fixture: false
    end
  end
end
