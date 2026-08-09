# frozen_string_literal: true

# Real-time updates for organization file extraction and summarization status.
class OrganizationFilesChannel < ApplicationCable::Channel
  def self.broadcast_file_update(file)
    payload = { file: OrganizationFileSerializer.new(file.organization).serialize(file.reload) }

    broadcast_to(file.organization, payload)
    broadcast_to_playbooks(file, payload)
  end

  def self.playbook_stream_name(playbook)
    "playbook:#{playbook.id}"
  end

  def self.broadcast_to_playbooks(file, payload)
    return unless file.is_a?(PlaybookAttachment) && file.knowledge_base?

    visible_playbooks(file).find_each do |playbook|
      broadcast_to(playbook_stream_name(playbook), payload)
    end
  end

  def self.visible_playbooks(file)
    return file.organization.playbooks if file.applies_to_all_playbooks?

    file.assigned_playbooks
  end

  def subscribed
    if params[:playbook_id].present?
      subscribe_to_playbook
    else
      subscribe_to_admin_organization
    end
  end

  def unsubscribed; end

  private

  def subscribe_to_admin_organization
    organization = Organization.find_by(id: params[:organization_id])

    if organization && current_account.amplifa_admin?
      stream_for organization
    else
      reject
    end
  end

  def subscribe_to_playbook
    playbook = Playbook.find_by(id: params[:playbook_id])

    if playbook && can_access_playbook?(playbook)
      stream_for self.class.playbook_stream_name(playbook)
    else
      reject
    end
  end

  def can_access_playbook?(playbook)
    return true if current_account.amplifa_admin?

    current_account.active_organization_memberships.exists?(organization_id: playbook.organization_id)
  end
end
