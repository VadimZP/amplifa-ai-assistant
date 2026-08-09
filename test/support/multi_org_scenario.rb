# Reusable builder for the AMP-435 multi-organization scenario.
#
# Creates all records on demand inside the calling test (no global fixtures),
# so it cannot pollute the shared fixture set or break count-based assertions
# in unrelated tests.
module MultiOrgScenario
  Result = Struct.new(
    :account,
    :org_a,
    :org_b,
    :org_archived,
    :org_deactivated,
    :membership_a,
    :membership_b,
    :membership_archived,
    :membership_deactivated,
    keyword_init: true
  )

  # Builds:
  # - org_a / org_b: distinct ACTIVE organizations (deactivated_at: nil, archived_at: nil)
  # - org_archived: organization with archived_at set
  # - org_deactivated: organization with deactivated_at set
  # - account: verified customer account (Rodauth-compatible password_hash) with:
  #   * membership_a: ACTIVE customer_admin membership in org_a
  #     (auto-created by Account.after_create :ensure_primary_organization_membership,
  #     NOT created twice here — see app/models/account.rb:97-104)
  #   * membership_b: ACTIVE customer_user membership in org_b
  #   * membership_archived: active-status membership in the archived org
  #   * membership_deactivated: active-status membership in the deactivated org
  #
  # Returns a MultiOrgScenario::Result exposing all of the above.
  def build_multi_org_scenario(password: 'password')
    suffix = SecureRandom.hex(4)

    org_a = create_multi_org!("Multi Org A #{suffix}")
    org_b = create_multi_org!("Multi Org B #{suffix}")
    org_archived = create_multi_org!("Multi Org Archived #{suffix}")
    org_deactivated = create_multi_org!("Multi Org Deactivated #{suffix}")

    # after_create :ensure_primary_organization_membership auto-creates the
    # active customer_admin membership in org_a (the account's primary org).
    account = Account.create!(
      email: "multi-org-#{suffix}@example.com",
      first_name: 'Multi',
      last_name: 'Org',
      role: 'customer_admin',
      organization: org_a,
      status: :verified,
      password_hash: RodauthApp.rodauth.allocate.password_hash(password)
    )

    membership_a = account.organization_memberships.find_by!(organization: org_a)
    membership_b = account.organization_memberships.create!(
      organization: org_b, role: 'customer_user', status: 'active'
    )
    membership_archived = account.organization_memberships.create!(
      organization: org_archived, role: 'customer_user', status: 'active'
    )
    membership_deactivated = account.organization_memberships.create!(
      organization: org_deactivated, role: 'customer_user', status: 'active'
    )

    org_archived.archive!
    org_deactivated.deactivate!

    Result.new(
      account: account,
      org_a: org_a,
      org_b: org_b,
      org_archived: org_archived,
      org_deactivated: org_deactivated,
      membership_a: membership_a,
      membership_b: membership_b,
      membership_archived: membership_archived,
      membership_deactivated: membership_deactivated
    )
  end

  private

  def create_multi_org!(name)
    Organization.create!(name: name, status: 'active')
  end
end
