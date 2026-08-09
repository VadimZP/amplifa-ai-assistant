ENV['RAILS_ENV'] ||= 'test'
ENV['MAILER_FROM'] ||= 'noreply@updates.amplifa.eu'
require_relative '../config/environment'
require 'rails/test_help'
require 'webmock/minitest'
require 'minitest/mock'

module Warning
  class << self
    alias original_warn warn

    def warn(message)
      return if message.include?('JSON.unparse is deprecated and will be removed in json 3.0.0')
      return if message.include?('literal string will be frozen in the future')

      original_warn(message)
    end
  end
end

# WHY: Allow connections to localhost and rubyllm.com for tests (webmock blocks all by default)
WebMock.disable_net_connect!(allow_localhost: true, allow: 'rubyllm.com')

# Load reusable test support modules (test/support/*.rb)
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |file| require file }

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    # Disabled temporarily due to PostgreSQL referential integrity permission issues
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include MultiOrgScenario

    # Add more helper methods to be used by all tests here...
  end
end

module ActionDispatch
  class IntegrationTest
    include ActiveJob::TestHelper

    # WHY: Helper method to set Inertia headers required for Inertia.js requests
    def inertia_headers
      {
        'HTTP_X_INERTIA' => 'true',
        'HTTP_X_INERTIA_VERSION' => ViteRuby.digest,
        'HTTP_ACCEPT' => 'text/html, application/xhtml+xml',
        'HTTP_X_REQUESTED_WITH' => 'XMLHttpRequest'
      }
    end

    # WHY: Helper to log in users for integration tests with Rodauth authentication
    # Password is 'password123' for amplifa_admin, 'password' for other users
    def login_as(account)
      password = account.email.include?('amplifa') ? 'password123' : 'password'
      perform_enqueued_jobs do
        post login_path, params: { email: account.email, password: password }
      end

      return unless account.requires_email_two_factor_authentication?

      verification_url = ActionMailer::Base.deliveries.last.text_part.body.to_s.match(%r{https?://\S+})[0]
      get URI.parse(verification_url).request_uri
    end

    # WHY: Helper to extract Inertia props from the response
    # This allows us to verify what data is being sent to the frontend
    def inertia_props
      JSON.parse(response.body)['props']
    end

    # WHY: Helper to verify the correct Inertia page component is rendered
    def assert_inertia_component(page_name)
      component = JSON.parse(response.body)['component']
      assert_equal page_name, component,
                   "Expected Inertia page '#{page_name}' but got '#{component}'"
    end

    def count_sql_queries
      query_count = 0

      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
        next if payload[:cached]
        next if %w[SCHEMA TRANSACTION].include?(payload[:name])
        next if payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i)

        query_count += 1
      end

      yield
      query_count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end
  end
end
