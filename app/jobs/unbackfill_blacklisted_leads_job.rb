# frozen_string_literal: true

class UnbackfillBlacklistedLeadsJob < ApplicationJob
  queue_as :default

  def perform(blacklist_attributes)
    attributes = blacklist_attributes.symbolize_keys
    leads = candidate_leads(attributes[:organization_id])
    return if leads.empty?

    counts = reconcile_leads(leads)
    log_reconciliation(attributes, counts)
  end

  private

  def candidate_leads(organization_id)
    scope = Lead.blacklisted
    return scope unless organization_id.present?

    scope.where(organization_id: organization_id)
  end

  def reconcile_leads(leads)
    counts = { unblacklisted: 0, refreshed: 0 }

    leads.find_each { |lead| reconcile_lead(lead, counts) }

    counts
  end

  def reconcile_lead(lead, counts)
    reason_attributes = remaining_blacklist_reason_attributes(lead)

    return unblacklist_lead(lead, counts) if reason_attributes.nil?
    return if blacklist_reason_current?(lead, reason_attributes)

    refresh_blacklist_reason(lead, reason_attributes, counts)
  end

  def remaining_blacklist_reason_attributes(lead)
    Blacklist.blacklist_reason_attributes(
      email: lead.email,
      organization: lead.organization,
      company_website: lead.company_website
    )
  end

  def unblacklist_lead(lead, counts)
    lead.unblacklist!
    counts[:unblacklisted] += 1
  end

  def blacklist_reason_current?(lead, reason_attributes)
    reason_attributes[:reason] == lead.blacklist_reason &&
      reason_attributes[:category] == lead.blacklist_reason_category
  end

  def refresh_blacklist_reason(lead, reason_attributes, counts)
    lead.update!(
      blacklist_reason: reason_attributes[:reason],
      blacklist_reason_category: reason_attributes[:category]
    )
    counts[:refreshed] += 1
  end

  def log_reconciliation(attributes, counts)
    Rails.logger.info(
      '[UnbackfillBlacklistedLeadsJob] ' \
      "Reconciled #{counts[:unblacklisted]} lead(s) and refreshed #{counts[:refreshed]} lead(s) " \
      "for removed blacklist #{attributes[:value_type]}=#{attributes[:value]} " \
      "(org=#{attributes[:organization_id] || 'global'})"
    )
  end
end
