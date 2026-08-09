# frozen_string_literal: true

# Retroactively marks existing leads as blacklisted when a new Blacklist entry is created.
# Handles both email and domain entries, for global and org-specific blacklists.
class BackfillBlacklistedLeadsJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  def perform(blacklist_id)
    blacklist = Blacklist.find(blacklist_id)

    leads = matching_leads(blacklist)
    return if leads.empty?

    reason = blacklist.effective_reason
    category = blacklist.reason_category

    leads.find_each do |lead|
      lead.blacklist!(reason: reason, category: category)
    end

    Rails.logger.info(
      "[BackfillBlacklistedLeadsJob] Blacklist #{blacklist_id}: " \
      "marked #{leads.count} lead(s) as blacklisted " \
      "(#{blacklist.value_type}=#{blacklist.value}, org=#{blacklist.organization_id || 'global'})"
    )
  end

  private

  def matching_leads(blacklist)
    scope = Lead.not_blacklisted

    scope = scope.where(organization_id: blacklist.organization_id) unless blacklist.global?

    case blacklist.value_type
    when 'email'
      scope.where('LOWER(email) = ?', blacklist.value.downcase)
    when 'domain'
      scope.where(
        "#{Lead::EMAIL_DOMAIN_SQL} LIKE :value OR #{Lead::COMPANY_WEBSITE_DOMAIN_SQL} LIKE :value",
        value: Blacklist.sql_like_pattern(blacklist.value)
      )
    else
      Lead.none
    end
  end
end
