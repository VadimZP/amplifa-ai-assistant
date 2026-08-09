# frozen_string_literal: true

# Mailer for sending notifications to Amplifa admins about
# customer actions that require admin attention.
class AdminNotificationMailer < ApplicationMailer
  self.deliver_later_queue_name = :mailers
  default to: -> { admin_emails }

  def samples_approved(agent, approver)
    @agent = agent
    @approver = approver
    @organization = agent.organization
    @approved_at = agent.samples_approved_at

    mail(
      subject: t('mailers.admin_notification.samples_approved.subject', agent_name: agent.name)
    )
  end

  def samples_changes_requested(agent, requester, feedback, lead = nil)
    @agent = agent
    @requester = requester
    @organization = agent.organization
    @feedback = feedback
    @lead = lead

    mail(
      subject: t('mailers.admin_notification.samples_changes_requested.subject', agent_name: agent.name)
    )
  end

  def sample_messages_generated(agent, initiated_by, generated_count, error_count)
    @agent = agent
    @initiated_by = initiated_by
    @organization = agent.organization
    @generated_count = generated_count
    @error_count = error_count

    mail(
      subject: t('mailers.admin_notification.sample_messages_generated.subject', agent_name: agent.name)
    )
  end

  def billing_interest(organization, account, action_name, action_label, lead = nil)
    @organization = organization
    @account = account
    @action_name = action_name
    @action_label = action_label
    @lead = lead

    mail(
      to: 'hello@amplifa.ai',
      subject: t('mailers.admin_notification.billing_interest.subject',
                 organization_name: organization.name,
                 action_name: action_label)
    )
  end

  def integration_connected(organization, account, integration_name, api_key)
    @organization = organization
    @account = account
    @integration_name = integration_name
    @api_key = api_key

    mail(
      to: 'hello@amplifa.ai',
      subject: t('mailers.admin_notification.integration_connected.subject',
                 organization_name: organization.name,
                 integration_name: integration_name)
    )
  end

  def customer_lead_import_completed(lead_import)
    @lead_import = lead_import
    @organization = lead_import.organization
    @imported_by = lead_import.imported_by
    @agent = lead_import.agent
    @imported_count = lead_import.created_count + lead_import.updated_count + lead_import.blacklisted_count

    mail(
      subject: t('mailers.admin_notification.customer_lead_import_completed.subject',
                 organization_name: @organization.name,
                 importer_name: @imported_by.full_name)
    )
  end

  def customer_lead_import_failed(lead_import, failure_reason = nil)
    @lead_import = lead_import
    @organization = lead_import.organization
    @imported_by = lead_import.imported_by
    @agent = lead_import.agent
    @failure_reason = failure_reason.presence || lead_import.errors_detail&.first&.dig('error') || 'Unknown error'

    mail(
      subject: t('mailers.admin_notification.customer_lead_import_failed.subject',
                 organization_name: @organization.name,
                 importer_name: @imported_by.full_name)
    )
  end

  def lead_list_file_uploaded(lead_list_file)
    @lead_list_file = lead_list_file
    @organization = lead_list_file.organization
    @uploaded_by = lead_list_file.uploaded_by
    @playbooks = lead_list_file.playbooks.order(:id)

    mail(
      subject: t('mailers.admin_notification.lead_list_file_uploaded.subject',
                 organization_name: @organization.name,
                 uploader_name: @uploaded_by.full_name)
    )
  end

  def buying_signals_completion_rate_alert(**stats)
    assign_buying_signals_completion_rate_alert_attributes(stats)

    mail(
      to: 'hello@amplifa.ai',
      subject: t(
        'mailers.admin_notification.buying_signals_completion_rate_alert.subject',
        completion_rate_percent: @completion_rate_percent,
        threshold_percent: @threshold_percent,
        window_minutes: @window_minutes
      )
    )
  end

  private

  def admin_emails
    Account.where(role: 'amplifa_admin').pluck(:email)
  end

  def assign_buying_signals_completion_rate_alert_attributes(stats)
    @window_minutes = stats.fetch(:window_minutes)
    @threshold_percent = stats.fetch(:threshold_percent)
    @completed_count = stats.fetch(:completed_count)
    @failed_count = stats.fetch(:failed_count)
    @total_count = stats.fetch(:total_count)
    @completion_rate = stats.fetch(:completion_rate)
    @completion_rate_percent = stats.fetch(:completion_rate_percent)
  end
end
