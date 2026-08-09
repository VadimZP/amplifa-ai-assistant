# frozen_string_literal: true

# Customer-facing ROI Dashboard (AMP-139)
# Aggregates campaign metrics to show return on investment.
class RoiController < ApplicationController
  def index
    authorize :roi, :index?
    skip_policy_scope

    organization = Current.organization

    if current_account.amplifa_admin? && organization.nil?
      redirect_to admin_dashboard_path
      return
    end

    render inertia: 'Roi/Index', props: roi_props(organization)
  end

  def update
    organization = Current.organization
    authorize :roi, :update?
    skip_policy_scope

    if organization.update(organization_params)
      redirect_to roi_path(suppress_flash: true), notice: 'ROI values updated successfully'
    else
      render inertia: 'Roi/Index', props: roi_props(organization, errors: organization.errors.messages),
             status: :unprocessable_entity
    end
  end

  private

  def roi_props(organization, errors: nil)
    agents, conversations, meetings = load_base_data(organization)
    email_metrics = compute_email_metrics(agents, conversations)
    meeting_metrics = compute_meeting_metrics(meetings, email_metrics[:leads_contacted])
    financial = compute_financial_metrics(
      organization,
      meeting_metrics[:total_meetings],
      meeting_metrics[:positive_outcomes]
    )

    {
      metrics: {
        **email_metrics,
        **meeting_metrics,
        **financial
      },
      monthly_trends: compute_monthly_trends(conversations, meetings, 6),
      agents: agents.map { |a| { id: a.id, name: a.name } },
      current_agent_id: params[:agent_id] || 'all',
      currency: organization.currency || 'EUR',
      can_edit_metrics: policy(:roi).update?,
      errors: errors
    }.compact
  end

  def load_base_data(organization)
    agents = organization.agents.not_deleted
    conversations = organization.conversations
    meetings = organization.meetings

    # Filter by agent if requested
    if params[:agent_id].present? && params[:agent_id] != 'all'
      agent = agents.find_by(id: params[:agent_id])
      if agent
        agents = agents.where(id: agent.id)
        conversations = conversations.where(agent_id: agent.id)
        meetings = meetings.where(agent_id: agent.id)
      end
    end

    [agents, conversations, meetings]
  end

  def compute_email_metrics(agents, conversations)
    leads_contacted = count_leads_with_sent_emails(agents)
    emails_sent = GeneratedMessage
                  .joins(:agent_lead)
                  .where(agent_leads: { agent_id: agents.select(:id) })
                  .where.not(sent_at: nil)
                  .count
    emails_replied = conversations.where('replies_count > 0').count
    leads_with_sent_emails = count_leads_with_sent_emails(agents)

    {
      leads_contacted: leads_contacted,
      emails_sent: emails_sent,
      emails_replied: emails_replied,
      reply_rate: rate(emails_replied, leads_with_sent_emails)
    }
  end

  def compute_meeting_metrics(meetings, leads_contacted)
    total_meetings = meetings.count
    positive_outcomes = meetings.where(outcome: 'positive').count

    {
      total_meetings: total_meetings,
      positive_outcomes: positive_outcomes,
      meeting_rate: rate(total_meetings, leads_contacted)
    }
  end

  def compute_financial_metrics(organization, total_meetings, _positive_outcomes)
    acv = organization.average_contract_value || 0
    pipeline_revenue = total_meetings * acv
    months = [((Time.current - organization.created_at) / 1.month).ceil, 1].max
    monthly_sub = organization.monthly_subscription || 0
    total_investment = monthly_sub * months
    roi = if total_investment.positive?
            [((pipeline_revenue - total_investment) / total_investment * 100).round(0), 0].max
          else
            0
          end

    {
      acv: acv.to_f,
      pipeline_revenue: pipeline_revenue.to_f,
      total_investment: total_investment.to_f,
      months_of_partnership: months,
      roi_percentage: roi
    }
  end

  def organization_params
    params.require(:organization).permit(:average_contract_value)
  end

  def compute_monthly_trends(conversations, meetings, months)
    months.times.map do |i|
      month_start = (Time.current - i.months).beginning_of_month
      month_end = month_start.end_of_month
      month_conversations = conversations.where(created_at: month_start..month_end)
      month_mtgs = meetings.where(created_at: month_start..month_end)

      {
        month: month_start.strftime('%b'),
        sent: month_conversations.count,
        opened: 0,
        replied: month_conversations.where('replies_count > 0').count,
        meetings: month_mtgs.count,
        positive_outcomes: month_mtgs.where(outcome: 'positive').count
      }
    end.reverse
  end

  def rate(numerator, denominator)
    denominator.positive? ? (numerator.to_f / denominator * 100).round(1) : 0.0
  end

  def count_leads_with_sent_emails(agents)
    GeneratedMessage
      .joins(:agent_lead)
      .where(agent_leads: { agent_id: agents.select(:id) })
      .where.not(sent_at: nil)
      .group('agent_leads.lead_id')
      .having('COUNT(generated_messages.id) >= 1')
      .count
      .size
  end
end
