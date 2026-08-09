# frozen_string_literal: true

class MailPollingChannel < ApplicationCable::Channel
  def subscribed
    organization = Organization.find_by(id: params[:organization_id])

    if organization && can_access_organization?(organization)
      stream_for organization
    else
      reject
    end
  end

  def unsubscribed
  end

  private

  def can_access_organization?(organization)
    return true if current_account.amplifa_admin?

    current_account.active_organization_memberships.exists?(organization_id: organization.id)
  end
end
