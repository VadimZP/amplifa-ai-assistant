# frozen_string_literal: true

namespace :ruby_llm do
  desc 'Refresh RubyLLM models from provider APIs'
  task refresh_models: :environment do
    start_time = Time.current
    before_count = Model.count

    puts 'Refreshing RubyLLM models from provider APIs...'

    Model.refresh!

    after_count = Model.count
    elapsed = ((Time.current - start_time) * 1000).round

    puts "Refresh complete. Models: #{before_count} → #{after_count} (#{elapsed}ms)"
    puts 'Restart the app to reload the in-memory registry.'
  end
end
