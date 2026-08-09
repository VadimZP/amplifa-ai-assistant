# frozen_string_literal: true

class ProcessLeadImportJob < ApplicationJob
  queue_as :lead_imports

  discard_on ActiveRecord::RecordNotFound do |_job, error|
    Rails.logger.error("Lead import not found: #{error.message}")
  end

  def perform(lead_import_id)
    lead_import = LeadImport.find(lead_import_id)

    Rails.logger.info("Starting lead import ##{lead_import.id} for organization #{lead_import.organization_id}")

    service = LeadImportService.new(lead_import)
    success = service.call

    if success
      Rails.logger.info(
        "Lead import ##{lead_import.id} completed: " \
        "created=#{lead_import.created_count}, " \
        "updated=#{lead_import.updated_count}, " \
        "blacklisted=#{lead_import.blacklisted_count}, " \
        "skipped=#{lead_import.skipped_count}, " \
        "errors=#{lead_import.error_count}"
      )

      notify_admins_import_completed(lead_import)
    else
      error_detail = service.last_error || extract_error_from_import(lead_import)
      persist_failure_reason(lead_import, error_detail)
      notify_admins_import_failed(lead_import, error_detail)
      Rails.logger.error("Lead import ##{lead_import.id} failed without retry: #{error_detail}")
    end
  rescue StandardError => e
    Rails.logger.error("Lead import ##{lead_import_id} crashed without retry: #{e.class}: #{e.message}")
    persist_unexpected_failure(lead_import_id, e.message)
    lead_import = LeadImport.find_by(id: lead_import_id)
    notify_admins_import_failed(lead_import, e.message) if lead_import
  end

  private

  def extract_error_from_import(lead_import)
    lead_import.reload
    first_error = lead_import.errors_detail&.first
    first_error&.dig('error') || 'Unknown error'
  end

  def persist_failure_reason(lead_import, error_detail)
    failure_message = "Import failed: #{error_detail}"

    lead_import.reload
    lead_import.update!(status: 'failed', completed_at: Time.current) unless lead_import.failed?

    existing_errors = Array(lead_import.errors_detail)
    return if existing_errors.any? { |error| error['row'] == 0 && error['error'] == failure_message }

    lead_import.add_error(row: 0, message: failure_message)
    lead_import.error_count = [lead_import.error_count, lead_import.errors_detail.length].max
    lead_import.save!
  end

  def persist_unexpected_failure(lead_import_id, error_detail)
    lead_import = LeadImport.find_by(id: lead_import_id)
    return unless lead_import

    persist_failure_reason(lead_import, error_detail)
  end

  def notify_admins_import_completed(lead_import)
    return if lead_import.imported_by.amplifa_admin?

    AdminNotificationMailer.customer_lead_import_completed(lead_import).deliver_later
  end

  def notify_admins_import_failed(lead_import, error_detail)
    return if lead_import.imported_by.amplifa_admin?

    AdminNotificationMailer.customer_lead_import_failed(lead_import, error_detail).deliver_later
  end
end
