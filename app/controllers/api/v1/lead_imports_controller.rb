# frozen_string_literal: true

# API endpoint for lead import progress polling
# Allows frontend to check import status and progress via AJAX
class Api::V1::LeadImportsController < ApplicationController
  # Skip callbacks that reference :index action (this controller only has :show)
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :set_lead_import

  def show
    # Authorize access using the existing LeadImportPolicy
    authorize @lead_import

    render json: serialize_lead_import(@lead_import)
  end

  private

  def set_lead_import
    @lead_import = LeadImport.find(params[:id])
  end

  def serialize_lead_import(lead_import)
    {
      id: lead_import.id,
      status: lead_import.status,
      total_rows: lead_import.total_rows,
      processed_rows: lead_import.processed_rows,
      created_count: lead_import.created_count,
      updated_count: lead_import.updated_count,
      skipped_count: lead_import.skipped_count,
      blacklisted_count: lead_import.blacklisted_count,
      error_count: lead_import.error_count,
      progress_percentage: lead_import.progress_percentage,
      started_at: lead_import.started_at&.iso8601,
      completed_at: lead_import.completed_at&.iso8601,
      duration_seconds: lead_import.duration_seconds,
      errors_detail: lead_import.errors_detail
    }
  end
end
