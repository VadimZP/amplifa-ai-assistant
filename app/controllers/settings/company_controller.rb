class Settings::CompanyController < ApplicationController
  # WHY: This controller uses a singular resource (:company) so it only has edit/update actions.
  # Rails 8.1 raises an error if a callback's :only/:except option references a non-existent action.
  # Since ApplicationController defines callbacks with index in only:/except: options,
  # we must skip those callbacks and handle authorization manually via authorize_organization.
  skip_after_action :verify_policy_scoped
  skip_after_action :verify_authorized

  before_action :load_organization
  before_action :authorize_organization

  def edit
    # WHY: Skip policy scope since we're working with a single organization
    # (the current user's organization), not a collection
    skip_policy_scope

    # WHY: Render the company settings form with current organization data
    # and authorization status so the frontend knows if fields should be editable
    render inertia: 'Customer/Settings/Company', props: {
      organization: @organization.as_json(
        only: %i[
          id name website average_contract_value
          monthly_subscription calendly_url currency locale
        ]
      ),
      canEdit: policy(@organization).update_company_settings?,
      # WHY: Provide currency options for the dropdown selector
      currencies: %w[EUR USD GBP CHF]
    }
  end

  def update
    # WHY: Skip policy scope since we're working with a single organization
    skip_policy_scope

    # WHY: Check if profile is incomplete before update so we can detect
    # if this update completes the onboarding step
    was_profile_incomplete = !@organization.onboarding_steps_completed.include?(:profile_completed)

    if @organization.update(organization_params)
      # WHY: Check if this update completed the profile onboarding step
      # so we can provide feedback to the user
      profile_now_complete = @organization.onboarding_steps_completed.include?(:profile_completed)
      step_completed = was_profile_incomplete && profile_now_complete

      # WHY: Log the update activity for audit trail
      AdminActivity.create!(
        account: current_account,
        organization: @organization,
        action: 'organization_updated',
        details: {
          fields: organization_params.keys,
          onboarding_step_completed: step_completed
        },
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      # WHY: Build flash message with onboarding step completion feedback
      flash_message = 'Company settings updated successfully'
      flash_message += ' - Onboarding step completed! ✓' if step_completed

      redirect_to edit_settings_company_path, notice: flash_message
    else
      # WHY: If validation fails, re-render the form with error messages
      # The Inertia response will include errors prop for display
      render inertia: 'Customer/Settings/Company', props: {
        organization: @organization,
        canEdit: policy(@organization).update_company_settings?,
        currencies: %w[EUR USD GBP CHF],
        errors: @organization.errors.messages
      }
    end
  end

  private

  def load_organization
    # WHY: Load the current user's organization for all settings actions
    # Customer users always work with their own organization
    @organization = Current.organization
  end

  def authorize_organization
    # WHY: Redirect amplifa admins away from customer settings since they don't have an organization
    # Admins should use the admin panel to edit organizations
    if current_account.amplifa_admin?
      skip_policy_scope
      redirect_to admin_dashboard_path and return
    end

    # WHY: Customer users can VIEW settings (read-only) but cannot UPDATE
    # We authorize the view differently from the update
    # For viewing (edit action), any customer can see their org settings
    # For updating (update action), only customer_admin can edit
    if action_name == 'update'
      # WHY: Only customer admins can update settings
      authorize @organization, :update_company_settings?
    else
      # WHY: All customers can view their organization (read-only for customer_user)
      authorize @organization, :show?
    end
  end

  def organization_params
    # WHY: Only permit fields that customers should be able to update
    # Monthly subscription is NOT included (admin-only per spec)
    # Currency and locale are included to allow customers to update preferences
    params.require(:organization).permit(
      :website,
      :average_contract_value,
      :calendly_url,
      :currency
      # NOTE: monthly_subscription is intentionally excluded (admin-only field)
    )
  end
end
