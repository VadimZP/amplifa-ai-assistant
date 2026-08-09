module OnboardingSteps
  STEPS = {
    profile_completed: {
      key: 'profile_completed',
      title_key: 'onboarding.steps.profile_completed.title',
      description_key: 'onboarding.steps.profile_completed.description',
      action_url: '/settings/company',
      action_key: 'onboarding.steps.profile_completed.action',
      check: ->(org) {
        org.website.present? &&
        org.average_contract_value.present? &&
        org.calendly_url.present?
      }
    },
    language_selected: {
      key: 'language_selected',
      title_key: 'onboarding.steps.language_selected.title',
      description_key: 'onboarding.steps.language_selected.description',
      action_url: nil, # Handled via top nav
      action_key: 'onboarding.steps.language_selected.action',
      check: ->(org) { org.locale.present? }
      # NOTE: Changed from spec to require explicit selection for all users
    }
  }.freeze

  def self.completed_steps(organization)
    STEPS.select { |key, step| step[:check].call(organization) }
  end

  def self.pending_steps(organization)
    STEPS.reject { |key, step| step[:check].call(organization) }
  end

  def self.completion_percentage(organization)
    completed = completed_steps(organization).count
    total = STEPS.count
    return 0 if total.zero?
    (completed.to_f / total * 100).round
  end
end
