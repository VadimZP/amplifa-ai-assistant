# frozen_string_literal: true

# Base controller for all admin controllers.
# Provides centralized authentication for Amplifa admins, ensuring consistent
# authorization across the entire admin interface.
#
# All admin controllers should inherit from this class instead of ApplicationController.
# This eliminates the need for each admin controller to define its own ensure_amplifa_admin
# method and before_action callback.
#
# WHY skip_after_action :verify_policy_scoped:
# Admin controllers are protected by require_amplifa_admin! which ensures only admins
# can access these actions. The policies already grant full access to admins via
# ApplicationPolicy. Since admin controllers typically load all records (not scoped),
# we skip Pundit's verification to avoid needing skip_policy_scope in every action.
class Admin::BaseController < ApplicationController
  LEAD_SEQUENCE_CONTACTED_THRESHOLD = 0.95

  AGENT_SEQUENCE_STAT_SELECTS = [
    'COUNT(*) AS total_leads_count',
    'COUNT(*) FILTER (WHERE sequence_position <= 0) AS not_contacted_leads_count'
  ].freeze

  before_action :require_amplifa_admin!
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  private

  # Require the current user to be an Amplifa admin.
  # Uses safe navigation to handle nil current_account (unauthenticated users).
  # Redirects non-admins to root with access denied message.
  def require_amplifa_admin!
    unless current_account&.amplifa_admin?
      redirect_to root_path, alert: 'Access denied'
    end
  end

  def agent_sequence_summaries_by_org_id(org_ids)
    org_ids = Array(org_ids).compact
    return {} if org_ids.empty?

    agents = agents_for_sequence_summaries(org_ids)
    stats_by_agent_id = agent_sequence_stats_by_agent_id(agents.map(&:id))

    grouped_agent_sequence_summaries(agents, stats_by_agent_id)
  end

  def grouped_agent_sequence_summaries(agents, stats_by_agent_id)
    agents.group_by(&:organization_id).transform_values do |org_agents|
      org_agents.map do |agent|
        serialize_agent_sequence_summary(agent, stats_by_agent_id[agent.id])
      end
    end
  end

  def agents_for_sequence_summaries(org_ids)
    Agent.not_deleted.where(organization_id: org_ids)
         .order(:organization_id, Arel.sql('LOWER(agents.name) ASC'), :id)
         .to_a
  end

  def agent_sequence_stats_by_agent_id(agent_ids)
    return {} if agent_ids.empty?

    stats_by_agent_id = base_agent_sequence_stats_by_agent_id(agent_ids)
    sequence_position_counts_by_agent_id = sequence_position_counts_by_agent_id(agent_ids)
    send_stats_by_agent_id = agent_send_stats_by_agent_id(agent_ids)

    agent_ids.index_with do |agent_id|
      build_agent_sequence_stats_hash(agent_id, stats_by_agent_id, sequence_position_counts_by_agent_id,
                                      send_stats_by_agent_id)
    end
  end

  def base_agent_sequence_stats_by_agent_id(agent_ids)
    AgentLead
      .where(agent_id: agent_ids)
      .group(:agent_id)
      .select(:agent_id, *AGENT_SEQUENCE_STAT_SELECTS)
      .index_by(&:agent_id)
  end

  def sequence_position_counts_by_agent_id(agent_ids)
    AgentLead
      .where(agent_id: agent_ids)
      .where('sequence_position > 0')
      .group(:agent_id, :sequence_position)
      .count
      .each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |((agent_id, sequence_position), count), result|
        result[agent_id][sequence_position] = count
      end
  end

  def agent_send_stats_by_agent_id(agent_ids)
    total_sent_by_agent_id = sent_counts_by_agent_id(agent_ids)
    sent_today_by_agent_id = sent_counts_by_agent_id(agent_ids, stat_date: Date.current)

    agent_ids.index_with do |agent_id|
      agent_send_stats_hash(agent_id, total_sent_by_agent_id, sent_today_by_agent_id)
    end
  end

  def sent_counts_by_agent_id(agent_ids, stat_date: nil)
    scope = GeneratedMessage.joins(:agent_lead)
                            .where(agent_leads: { agent_id: agent_ids }, status: 'sent')
    scope = scope.where(sent_at: stat_date.all_day) if stat_date
    scope.group('agent_leads.agent_id').count
  end

  def agent_send_stats_hash(agent_id, total_sent_by_agent_id, sent_today_by_agent_id)
    {
      emails_sent: total_sent_by_agent_id[agent_id].to_i,
      emails_sent_today: sent_today_by_agent_id[agent_id].to_i
    }
  end

  def build_agent_sequence_stats_hash(agent_id, stats_by_agent_id, sequence_position_counts_by_agent_id,
                                      send_stats_by_agent_id)
    agent_sequence_stats_hash(
      stats_by_agent_id[agent_id],
      sequence_position_counts_by_agent_id[agent_id],
      send_stats_by_agent_id[agent_id]
    )
  end

  def agent_sequence_stats_hash(stats, sequence_position_counts, send_stats)
    total_leads = stats&.read_attribute('total_leads_count').to_i
    not_contacted_leads = stats&.read_attribute('not_contacted_leads_count').to_i

    {
      total_leads_count: total_leads,
      not_contacted_leads_count: not_contacted_leads,
      emails_sent: send_stats.fetch(:emails_sent, 0),
      emails_sent_today: send_stats.fetch(:emails_sent_today, 0),
      all_reached_sequence_step: threshold_reached_sequence_step(total_leads, sequence_position_counts)
    }
  end

  def serialize_agent_sequence_summary(agent, stats)
    total_leads = stats&.fetch(:total_leads_count, 0).to_i
    not_contacted_leads = stats&.fetch(:not_contacted_leads_count, 0).to_i

    { id: agent.id, name: agent.name, status: agent.status }.merge(
      agent_sequence_stat_attributes(total_leads, not_contacted_leads, stats)
    )
  end

  def agent_sequence_stat_attributes(total_leads, not_contacted_leads, stats)
    all_reached_sequence_step = stats&.fetch(:all_reached_sequence_step, nil)

    {
      total_leads_count: total_leads,
      not_contacted_leads_count: not_contacted_leads,
      emails_sent: stats&.fetch(:emails_sent, 0).to_i,
      emails_sent_today: stats&.fetch(:emails_sent_today, 0).to_i,
      all_reached_sequence_step: all_reached_sequence_step,
      all_leads_contacted: total_leads.positive? && all_reached_sequence_step.present?
    }
  end

  def threshold_reached_sequence_step(total_leads, sequence_position_counts)
    return nil unless total_leads.positive?

    reached_leads = 0
    sorted_sequence_position_counts = sequence_position_counts.sort_by do |sequence_position, _count|
      -sequence_position
    end
    sorted_sequence_position_counts.each do |sequence_position, count|
      reached_leads += count
      return sequence_position if (reached_leads.to_f / total_leads) >= LEAD_SEQUENCE_CONTACTED_THRESHOLD
    end

    nil
  end
end
