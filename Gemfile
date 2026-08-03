source "https://rubygems.org"

gem "rails", "~> 8.0.4"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "openai"
gem "neighbor"
gem "dotenv-rails", groups: [ :development, :test ]
gem "tiktoken_ruby"
gem "sidekiq"
gem "faraday", "~> 2.0"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "solargraph", require: false
end
