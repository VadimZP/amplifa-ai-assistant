require 'test_helper'

class OnboardingStepsTest < ActiveSupport::TestCase
  # Why: OnboardingSteps module defines the onboarding checklist logic that guides customers through setup
  # Testing this module ensures the onboarding experience works correctly

  def setup
    @org_no_steps = Organization.new(
      name: 'No Steps Org',
      status: 'onboarding',
      locale: nil,
      currency: 'EUR'
    )

    @org_profile_only = Organization.new(
      name: 'Profile Only Org',
      status: 'onboarding',
      locale: nil,
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )

    @org_all_complete = Organization.new(
      name: 'All Complete Org',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
  end

  # STEPS constant tests
  # Why: STEPS constant defines all available onboarding steps
  test 'STEPS constant is defined and frozen' do
    assert_not_nil OnboardingSteps::STEPS
    assert OnboardingSteps::STEPS.frozen?
  end

  test 'STEPS contains profile_completed step' do
    # Why: Profile completion is a critical onboarding step
    assert OnboardingSteps::STEPS.key?(:profile_completed)
  end

  test 'STEPS contains language_selected step' do
    # Why: Language selection is required for proper i18n experience
    assert OnboardingSteps::STEPS.key?(:language_selected)
  end

  test 'each step has required keys' do
    # Why: Each step needs all metadata for rendering in UI
    required_keys = %i[key title_key description_key action_url action_key check]
    OnboardingSteps::STEPS.each do |step_key, step|
      required_keys.each do |key|
        assert step.key?(key), "Step #{step_key} missing required key #{key}"
      end
    end
  end

  test 'each step check is a callable lambda' do
    # Why: Check functions must be callable to determine step completion
    OnboardingSteps::STEPS.each do |step_key, step|
      assert step[:check].respond_to?(:call), "Step #{step_key} check is not callable"
    end
  end

  # profile_completed step tests
  # Why: Profile step requires website, ACV, and Calendly URL
  test 'profile_completed check returns false when missing all fields' do
    org = Organization.new(name: 'Test', status: 'onboarding', locale: 'en', currency: 'EUR')
    result = OnboardingSteps::STEPS[:profile_completed][:check].call(org)
    refute result
  end

  test 'profile_completed check returns false when missing website' do
    org = Organization.new(
      name: 'Test',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    result = OnboardingSteps::STEPS[:profile_completed][:check].call(org)
    refute result
  end

  test 'profile_completed check returns false when missing average_contract_value' do
    org = Organization.new(
      name: 'Test',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      calendly_url: 'https://calendly.com/test/meeting'
    )
    result = OnboardingSteps::STEPS[:profile_completed][:check].call(org)
    refute result
  end

  test 'profile_completed check returns false when missing calendly_url' do
    org = Organization.new(
      name: 'Test',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000
    )
    result = OnboardingSteps::STEPS[:profile_completed][:check].call(org)
    refute result
  end

  test 'profile_completed check returns true when all required fields present' do
    # Why: Step should be marked complete when all required fields are filled
    org = Organization.new(
      name: 'Test',
      status: 'onboarding',
      locale: 'en',
      currency: 'EUR',
      website: 'https://example.com',
      average_contract_value: 10_000,
      calendly_url: 'https://calendly.com/test/meeting'
    )
    result = OnboardingSteps::STEPS[:profile_completed][:check].call(org)
    assert result
  end

  # language_selected step tests
  # Why: Language step requires locale to be explicitly set (per user decision in implementation plan)
  test 'language_selected check returns false when locale is nil' do
    # Why: User must explicitly select a language
    org = Organization.new(name: 'Test', status: 'onboarding', locale: nil, currency: 'EUR')
    result = OnboardingSteps::STEPS[:language_selected][:check].call(org)
    refute result
  end

  test 'language_selected check returns true when locale is en' do
    org = Organization.new(name: 'Test', status: 'onboarding', locale: 'en', currency: 'EUR')
    result = OnboardingSteps::STEPS[:language_selected][:check].call(org)
    assert result
  end

  test 'language_selected check returns true when locale is de' do
    org = Organization.new(name: 'Test', status: 'onboarding', locale: 'de', currency: 'EUR')
    result = OnboardingSteps::STEPS[:language_selected][:check].call(org)
    assert result
  end

  # completed_steps tests
  # Why: Need to get list of completed steps for UI rendering
  test 'completed_steps returns empty hash when no steps completed' do
    # Override locale to be nil
    @org_no_steps.define_singleton_method(:locale) { nil }
    completed = OnboardingSteps.completed_steps(@org_no_steps)
    assert_equal 0, completed.count
  end

  test 'completed_steps returns profile_completed when profile fields present' do
    completed = OnboardingSteps.completed_steps(@org_profile_only)
    assert_includes completed.keys, :profile_completed
  end

  test 'completed_steps returns all steps when all complete' do
    # Why: Should return all steps when organization has completed everything
    completed = OnboardingSteps.completed_steps(@org_all_complete)
    assert_equal 2, completed.count
    assert_includes completed.keys, :profile_completed
    assert_includes completed.keys, :language_selected
  end

  # pending_steps tests
  # Why: Need to get list of pending steps to show user what's left to do
  test 'pending_steps returns all steps when none completed' do
    @org_no_steps.define_singleton_method(:locale) { nil }
    pending = OnboardingSteps.pending_steps(@org_no_steps)
    assert_equal 2, pending.count
    assert_includes pending.keys, :profile_completed
    assert_includes pending.keys, :language_selected
  end

  test 'pending_steps returns language_selected when only profile completed' do
    # Override locale to simulate language not selected
    @org_profile_only.define_singleton_method(:locale) { nil }
    pending = OnboardingSteps.pending_steps(@org_profile_only)
    assert_includes pending.keys, :language_selected
    refute_includes pending.keys, :profile_completed
  end

  test 'pending_steps returns empty hash when all steps completed' do
    # Why: No pending steps when onboarding is complete
    pending = OnboardingSteps.pending_steps(@org_all_complete)
    assert_equal 0, pending.count
  end

  # completion_percentage tests
  # Why: Percentage is displayed in UI to show progress
  test 'completion_percentage returns 0 when no steps completed' do
    @org_no_steps.define_singleton_method(:locale) { nil }
    percentage = OnboardingSteps.completion_percentage(@org_no_steps)
    assert_equal 0, percentage
  end

  test 'completion_percentage returns 50 when one of two steps completed' do
    # Why: With 2 steps total, 1 completed = 50%
    @org_profile_only.define_singleton_method(:locale) { nil }
    percentage = OnboardingSteps.completion_percentage(@org_profile_only)
    assert_equal 50, percentage
  end

  test 'completion_percentage returns 100 when all steps completed' do
    # Why: 100% means onboarding is complete
    percentage = OnboardingSteps.completion_percentage(@org_all_complete)
    assert_equal 100, percentage
  end

  test 'completion_percentage returns integer, not float' do
    # Why: UI should display whole numbers, not decimals
    percentage = OnboardingSteps.completion_percentage(@org_all_complete)
    assert percentage.is_a?(Integer)
  end

  test 'completion_percentage handles zero total steps gracefully' do
    # Why: Edge case protection - skip this test as it's testing an unrealistic edge case
    # that would break the constant and interfere with other tests
    original_steps = OnboardingSteps::STEPS

    OnboardingSteps.send(:remove_const, :STEPS)
    OnboardingSteps.const_set(:STEPS, {}.freeze)

    percentage = OnboardingSteps.completion_percentage(@org_all_complete)
    assert_equal 0, percentage
  ensure
    OnboardingSteps.send(:remove_const, :STEPS)
    OnboardingSteps.const_set(:STEPS, original_steps)
  end

  # Step metadata tests
  # Why: UI needs correct i18n keys and URLs for each step
  test 'profile_completed has correct action_url' do
    step = OnboardingSteps::STEPS[:profile_completed]
    assert_equal '/settings/company', step[:action_url]
  end

  test 'language_selected has nil action_url' do
    # Why: Language is handled via top nav, not a dedicated page
    step = OnboardingSteps::STEPS[:language_selected]
    assert_nil step[:action_url]
  end

  test 'all steps have i18n keys for title, description, and action' do
    # Why: UI needs translation keys for all text
    OnboardingSteps::STEPS.each do |key, step|
      assert step[:title_key].present?, "Step #{key} missing title_key"
      assert step[:description_key].present?, "Step #{key} missing description_key"
      assert step[:action_key].present?, "Step #{key} missing action_key"
    end
  end
end
