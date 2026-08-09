require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

RubyLLM.configure do |config|
  config.use_new_acts_as = true
end

module Amplifa
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

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

    # Internationalization configuration
    config.i18n.available_locales = %i[en de es pt-BR fr pl cs it]
    config.i18n.default_locale = :en
    config.i18n.fallbacks = [:en]
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.yml')]

    # Disable Active Storage analyzers globally – we were getting 1000s of
    # AnalyzeJobs enqueued just to analyze LinkedIn profile photos. Turn
    # analysis back on manually for any other uploads that need it.
    config.active_storage.analyzers = []
  end
end
