# frozen_string_literal: true

class Admin::Organizations::BaseController < Admin::BaseController
  before_action :set_organization

  private

  def attach_request_baseline_headers
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    query_count = 0

    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])
      next if payload[:sql].match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i)

      query_count += 1
    end

    result = yield
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

    response.set_header('X-Amplifa-Query-Count', query_count.to_s)
    response.set_header('X-Amplifa-Duration-Ms', duration_ms.to_s)

    existing_server_timing = response.get_header('Server-Timing')
    response.set_header('Server-Timing', [existing_server_timing, "app;dur=#{duration_ms}"].compact_blank.join(', '))

    result
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def organization_scope(relation)
    relation.where(organization_id: @organization.id)
  end

  def common_props
    {
      organization: serialize_organization(@organization),
      current_tab: controller_name,
      agents_for_dropdown: serialize_agents_for_dropdown(@organization.agents.not_deleted.order(:name))
    }
  end

  def serialize_organization(org)
    org.as_json(only: %i[id name website ai_reply_agent_enabled locale])
  end

  def serialize_agents_for_dropdown(agents)
    agents.map { |agent| agent.as_json(only: %i[id name status]) }
  end
end
