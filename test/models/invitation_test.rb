require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  # Why: Invitations are the primary way customers are added to organizations
  # We need to ensure the invitation system is robust and secure

  def setup
    @organization = organizations(:acme)
    @admin = accounts(:amplifa_admin)
  end

  # Token generation tests
  # Why: Tokens must be unique and securely generated for invitation security
  test "should automatically generate token on creation" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    assert_nil invitation.token
    invitation.save!
    assert_not_nil invitation.token
    # Why: URL-safe base64 with 32 bytes generates a 43-character string
    assert_equal 43, invitation.token.length
  end

  test "should not overwrite existing token" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      token: "existing-token"
    )
    invitation.save!
    assert_equal "existing-token", invitation.token
  end

  test "should require unique token" do
    # Why: Duplicate tokens would be a severe security issue
    invitation1 = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test1@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )

    invitation2 = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test2@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      token: invitation1.token
    )
    refute invitation2.valid?
    assert_includes invitation2.errors[:token], "has already been taken"
  end

  # Expiration tests
  # Why: Invitations must expire for security and to keep the system clean
  test "should automatically set expires_at to 7 days from now" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    invitation.save!
    # Why: Check that it's approximately 7 days (within 1 minute to account for test execution time)
    expected = 7.days.from_now
    assert_in_delta expected.to_i, invitation.expires_at.to_i, 60
  end

  test "should not overwrite existing expires_at" do
    custom_expiry = 3.days.from_now
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: custom_expiry
    )
    invitation.save!
    assert_in_delta custom_expiry.to_i, invitation.expires_at.to_i, 1
  end

  test "expired? returns true when status is pending and past expiration" do
    # Why: We need to correctly identify expired invitations
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      token: SecureRandom.urlsafe_base64(32)
    )
    invitation.save(validate: false)
    assert invitation.expired?
  end

  test "expired? returns false when not past expiration" do
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.from_now
    )
    refute invitation.expired?
  end

  test "expired? returns false when status is not pending" do
    # Why: Only pending invitations can be expired
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      status: 'accepted'
    )
    refute invitation.expired?
  end

  # Email validation tests
  # Why: Email must be valid format and unique per status for invitation system to work
  test "should require email to be present" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:email], "can't be blank"
  end

  test "should require email to be valid format" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "invalid-email",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:email], "is invalid"
  end

  test "should allow same email if previous invitation is cancelled" do
    # Why: Users should be able to be re-invited after cancellation
    Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'cancelled'
    )

    invitation2 = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    assert invitation2.valid?
  end

  test "should not allow same email with pending invitation" do
    # Why: Prevent duplicate pending invitations for the same email
    Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'pending'
    )

    invitation2 = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation2.valid?
    assert_includes invitation2.errors[:email], "already has a pending or accepted invitation"
  end

  test "should allow same email with pending invitation in another organization" do
    Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "multi-org@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'pending'
    )

    invitation2 = Invitation.new(
      organization: organizations(:beta),
      invited_by: @admin,
      email: "multi-org@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_admin"
    )

    assert invitation2.valid?
  end

  # Name validation tests
  # Why: Names are required to create the account and personalize the invitation email
  test "should require first_name" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:first_name], "can't be blank"
  end

  test "should require last_name" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:last_name], "can't be blank"
  end

  test "should enforce maximum length for first_name" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "a" * 101,
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:first_name], "is too long (maximum is 100 characters)"
  end

  test "should enforce maximum length for last_name" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "a" * 101,
      role: "customer_user"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:last_name], "is too long (maximum is 100 characters)"
  end

  # Role validation tests
  # Why: Only customer roles should be invitable, not amplifa_admin
  test "should require role to be present" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:role], "can't be blank"
  end

  test "should accept customer_admin role" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_admin"
    )
    assert invitation.valid?
  end

  test "should accept customer_user role" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    assert invitation.valid?
  end

  test "should not accept amplifa_admin role" do
    # Why: Amplifa admins should not be invited through customer invitations
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "amplifa_admin"
    )
    refute invitation.valid?
    assert_includes invitation.errors[:role], "is not included in the list"
  end

  # Status validation tests
  # Why: Status must be valid for proper invitation lifecycle management
  test "should default status to pending" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    invitation.save!
    assert_equal 'pending', invitation.status
  end

  test "should only accept valid status values" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'invalid_status'
    )
    refute invitation.valid?
    assert_includes invitation.errors[:status], "is not included in the list"
  end

  # Association tests
  # Why: Proper associations are required for invitation lifecycle and audit trail
  test "should belong to organization" do
    invitation = Invitation.new(
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert invitation.errors[:organization].present?
  end

  test "should belong to invited_by account" do
    invitation = Invitation.new(
      organization: @organization,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    refute invitation.valid?
    assert invitation.errors[:invited_by].present?
  end

  test "should optionally belong to account" do
    # Why: Account is null until invitation is accepted
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      account: nil
    )
    assert invitation.valid?
  end

  # Scope tests
  # Why: Scopes are used to filter invitations in the admin interface
  test "pending scope returns only non-expired pending invitations" do
    # Create pending non-expired
    pending_valid = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "pending@example.com",
      first_name: "Pending",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.from_now
    )

    # Create pending expired (bypass validation)
    expired_inv = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "expired@example.com",
      first_name: "Expired",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      token: SecureRandom.urlsafe_base64(32)
    )
    expired_inv.save(validate: false)

    pending_invitations = Invitation.pending
    assert_includes pending_invitations, pending_valid
    assert pending_invitations.all? { |i| i.status == 'pending' && i.expires_at > Time.current }
  end

  test "expired scope returns only expired pending invitations" do
    # Create expired invitation (bypass validation)
    expired = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "expired@example.com",
      first_name: "Expired",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      token: SecureRandom.urlsafe_base64(32)
    )
    expired.save(validate: false)

    expired_invitations = Invitation.expired
    assert_includes expired_invitations, expired
    assert expired_invitations.all? { |i| i.status == 'pending' && i.expires_at <= Time.current }
  end

  test "for_organization scope returns invitations for specific organization" do
    org2 = Organization.create!(name: "Other Org", status: 'onboarding', locale: 'en', currency: 'EUR')

    invitation1 = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test1@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )

    Invitation.create!(
      organization: org2,
      invited_by: @admin,
      email: "test2@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )

    org_invitations = Invitation.for_organization(@organization)
    assert_includes org_invitations, invitation1
    assert org_invitations.all? { |i| i.organization_id == @organization.id }
  end

  test "recent scope orders by created_at descending" do
    # Why: The recent scope should return invitations newest first
    # Create invitations with different times
    old = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "old@example.com",
      first_name: "Old",
      last_name: "User",
      role: "customer_user",
      created_at: 2.days.ago
    )

    recent = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "recent@example.com",
      first_name: "Recent",
      last_name: "User",
      role: "customer_user",
      created_at: 1.hour.ago
    )

    # Why: Query only the invitations we just created to avoid fixture interference
    invitations = Invitation.where(id: [old.id, recent.id]).recent.to_a
    assert_equal recent.id, invitations.first.id
    assert invitations.first.created_at > invitations.last.created_at
  end

  # Method tests
  test "can_be_accepted? returns true for pending non-expired invitation" do
    # Why: Only pending non-expired invitations should be acceptable
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.from_now
    )
    assert invitation.can_be_accepted?
  end

  test "can_be_accepted? returns false for expired invitation" do
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      token: SecureRandom.urlsafe_base64(32)
    )
    invitation.save(validate: false)
    refute invitation.can_be_accepted?
  end

  test "can_be_accepted? returns false for accepted invitation" do
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'accepted'
    )
    refute invitation.can_be_accepted?
  end

  test "cancel! updates status to cancelled" do
    # Why: Admins need to be able to cancel pending invitations
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user"
    )
    assert_equal 'pending', invitation.status
    invitation.cancel!
    assert_equal 'cancelled', invitation.status
  end

  test "cancel! returns false for non-pending invitation" do
    # Why: Only pending invitations can be cancelled
    invitation = Invitation.create!(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      status: 'accepted'
    )
    result = invitation.cancel!
    assert_equal false, result
    assert_equal 'accepted', invitation.reload.status
  end

  test "resend! generates new token and extends expiration" do
    # Why: Admins need to be able to resend expired invitations
    invitation = Invitation.new(
      organization: @organization,
      invited_by: @admin,
      email: "test@example.com",
      first_name: "Test",
      last_name: "User",
      role: "customer_user",
      expires_at: 1.day.ago,
      token: SecureRandom.urlsafe_base64(32)
    )
    invitation.save(validate: false)

    old_token = invitation.token
    old_expiry = invitation.expires_at

    # Why: resend! should generate a new token, extend expiration, and send email
    # Email delivery is tested in mailer tests, here we just verify the model state changes
    assert invitation.resend!

    # Why: Verify token changed
    assert_not_equal old_token, invitation.token

    # Why: Verify expiration was extended to 7 days from now
    assert invitation.expires_at > old_expiry
    assert invitation.expires_at > Time.current

    # Why: Verify sent_at was updated
    assert_not_nil invitation.sent_at
    assert invitation.sent_at >= Time.current - 1.second
  end
end
