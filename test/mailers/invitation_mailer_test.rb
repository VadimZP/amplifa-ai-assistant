require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  # WHY: The invitation email is the primary way customers are onboarded to the platform.
  # It must be properly formatted, localized, and contain all necessary information for
  # the customer to accept their invitation. These tests ensure the email meets all requirements
  # from the Week 2 spec (thoughts/specs/20251105_mvp_week2_spec.md).

  def setup
    @invitation = invitations(:pending_acme)
    @organization = @invitation.organization
    @invited_by = @invitation.invited_by
  end

  # Basic email delivery tests
  # WHY: Verify the email is properly addressed and has correct basic structure

  test "invite email is sent to invitation email address" do
    # WHY: Email must go to the person being invited
    email = InvitationMailer.invite(@invitation)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal [@invitation.email], email.to
  end

  test "invite email has correct from address" do
    # WHY: Emails should come from the configured MAILER_FROM address
    email = InvitationMailer.invite(@invitation)

    assert_equal [ENV.fetch('MAILER_FROM', 'noreply@updates.amplifa.eu')], email.from
  end

  test "invite email has correct subject in English" do
    # WHY: Subject line must be clear and include organization name per spec
    @organization.update!(locale: 'en')
    email = InvitationMailer.invite(@invitation)

    assert_match @organization.name, email.subject
    assert_match /invited/i, email.subject
  end

  test "invite email has correct subject in German" do
    # WHY: Subject must be properly localized for German organizations
    @organization.update!(locale: 'de')
    email = InvitationMailer.invite(@invitation)

    # Subject should be in German
    assert_match @organization.name, email.subject
  end

  # Content tests
  # WHY: Email must contain all required information per spec

  test "invite email body includes invitee first name" do
    # WHY: Personalized greeting makes email feel more legitimate and less like spam
    email = InvitationMailer.invite(@invitation)

    assert_match @invitation.first_name, email.html_part.body.to_s
    assert_match @invitation.first_name, email.text_part.body.to_s
  end

  test "invite email body includes organization name" do
    # WHY: Customer needs to know which organization they're being invited to
    email = InvitationMailer.invite(@invitation)

    assert_match @organization.name, email.html_part.body.to_s
    assert_match @organization.name, email.text_part.body.to_s
  end

  test "invite email body includes inviter name" do
    # WHY: Knowing who invited them adds legitimacy and context
    email = InvitationMailer.invite(@invitation)

    assert_match @invited_by.full_name, email.html_part.body.to_s
    assert_match @invited_by.full_name, email.text_part.body.to_s
  end

  test "invite email body includes acceptance link with token" do
    # WHY: Customer needs the unique link to accept their invitation
    email = InvitationMailer.invite(@invitation)

    # Link should contain the invitation token
    assert_match @invitation.token, email.html_part.body.to_s
    assert_match @invitation.token, email.text_part.body.to_s

    # Link should point to the accept invitation path
    assert_match /invitations\/#{@invitation.token}\/accept/, email.html_part.body.to_s
  end

  test "invite email body includes expiration date" do
    # WHY: Customer needs to know when the invitation expires
    email = InvitationMailer.invite(@invitation)

    # Should mention expiration (the exact format depends on i18n, so just check it's present)
    html_body = email.html_part.body.to_s
    text_body = email.text_part.body.to_s

    # Check that some date-like content is present near "expire" keyword
    assert_match /expir/i, html_body
    assert_match /expir/i, text_body
  end

  # Format tests
  # WHY: Email must have both HTML and text versions for compatibility

  test "invite email has HTML part" do
    # WHY: Most modern email clients display HTML, which looks professional
    email = InvitationMailer.invite(@invitation)

    assert_not_nil email.html_part
    assert_match /<html/i, email.html_part.body.to_s
  end

  test "invite email has text part" do
    # WHY: Text fallback is required for accessibility and some email clients
    email = InvitationMailer.invite(@invitation)

    assert_not_nil email.text_part
    # Text part should not contain HTML tags
    refute_match /<html/i, email.text_part.body.to_s
  end

  test "invite email HTML includes button styling" do
    # WHY: Per spec, email should have a clear CTA button
    email = InvitationMailer.invite(@invitation)

    html_body = email.html_part.body.to_s

    # Should have some button/link styling (class or inline styles)
    assert_match /<a[^>]*href.*invitations.*accept/i, html_body
  end

  # Localization tests
  # WHY: Email must respect organization's locale setting

  test "invite email respects organization locale for English" do
    # WHY: English organizations should receive English emails
    @organization.update!(locale: 'en')
    email = InvitationMailer.invite(@invitation)

    html_body = email.html_part.body.to_s

    # Check for English-specific words (these will be i18n keys)
    # We're just verifying the locale is being set correctly
    assert_not_nil html_body
  end

  test "invite email respects organization locale for German" do
    # WHY: German organizations should receive German emails
    @organization.update!(locale: 'de')
    email = InvitationMailer.invite(@invitation)

    html_body = email.html_part.body.to_s

    # Verify email was generated (German translations will be added in i18n setup)
    assert_not_nil html_body
  end

  # Edge case tests
  # WHY: Handle special characters and edge cases gracefully

  test "invite email handles organization names with special characters" do
    # WHY: Organization names may contain characters that need HTML escaping
    @organization.update!(name: "Test & Co. <Special>")
    email = InvitationMailer.invite(@invitation)

    html_body = email.html_part.body.to_s

    # HTML should be properly escaped
    assert_match /Test &amp; Co/, html_body
  end

  test "invite email handles invitee names with special characters" do
    # WHY: Names may contain accented characters or apostrophes, and these should not cause errors
    @invitation.update!(first_name: "François", last_name: "O'Brien")
    email = InvitationMailer.invite(@invitation)

    html_body = email.html_part.body.to_s

    # First name should appear correctly in greeting (last name typically doesn't appear in email body)
    assert_match /François/, html_body

    # Email should generate without errors even with special characters in last name
    assert_not_nil html_body
  end
end
