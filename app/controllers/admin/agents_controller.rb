# frozen_string_literal: true

class Admin::AgentsController < Admin::BaseController
  PER_PAGE = 25

  def index
    agents = Agent.not_deleted.includes(:organization, :playbook, :created_by, :mailboxes)
                  .order(created_at: :desc)

    agents = apply_filters(agents)
    agents = apply_search(agents)

    page = (params[:page] || 1).to_i
    total_count = agents.count
    total_pages = (total_count.to_f / PER_PAGE).ceil
    agents = agents.offset((page - 1) * PER_PAGE).limit(PER_PAGE)

    render inertia: "Admin/Agents/Index", props: {
      agents: serialize_agents(agents),
      filters: {
        search: params[:search],
        status: params[:status],
        organization_id: params[:organization_id]
      },
      status_options: Agent::VISIBLE_STATUSES,
      organizations: Organization.order(:name).pluck(:name, :id).map { |name, id| { id: id, name: name } },
      pagination: {
        current_page: page,
        total_pages: total_pages,
        total_count: total_count,
        per_page: PER_PAGE
      }
    }
  end

  private

  def apply_filters(agents)
    if params[:status].present? && Agent::VISIBLE_STATUSES.include?(params[:status])
      agents = agents.where(status: params[:status])
    end

    if params[:organization_id].present?
      agents = agents.where(organization_id: params[:organization_id])
    end

    agents
  end

  def apply_search(agents)
    return agents unless params[:search].present?

    search_term = "%#{params[:search]}%"
    agents.joins(:organization).where(
      "agents.name ILIKE :term OR organizations.name ILIKE :term",
      term: search_term
    )
  end

  def serialize_agents(agents)
    agents.map do |agent|
      {
        id: agent.id,
        name: agent.name,
        status: agent.status,
        organization: {
          id: agent.organization.id,
          name: agent.organization.name
        },
        playbook_name: agent.playbook&.product_name,
        buying_signals_enabled: agent.buying_signals_enabled,
        total_leads_count: agent.total_leads_count,
        contacted_count: agent.contacted_count,
        replied_count: agent.replied_count,
        meetings_booked_count: agent.meetings_booked_count,
        reply_rate: agent.reply_rate,
        meeting_rate: agent.meeting_rate,
        created_at: agent.created_at
      }
    end
  end
end
