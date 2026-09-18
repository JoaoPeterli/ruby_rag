source "https://rubygems.org"

gem "rails", "~> 8.0.4"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "openai"
gem "dotenv-rails", groups: [ :development, :test ]
gem "tiktoken_ruby"
gem "sidekiq"
gem "faraday", "~> 2.14"
gem "bcrypt", "~> 3.1.7"

# Painel admin (app é api_only; essas gems dão views/assets/JS só pra
# essa parte da aplicação — ver config/application.rb).
gem "propshaft", "~> 1.3"
gem "importmap-rails", "~> 2.2"
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"

# Upload de documento (Portal::) -> S3 + OCR. Infra fica pronta mas
# desligada por padrão (ver DOCUMENT_UPLOAD_ENABLED) até a qualidade
# do OCR ser avaliada.
gem "aws-sdk-s3", require: false
gem "pdf-reader"
gem "rtesseract"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "solargraph", require: false
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.5"
end
