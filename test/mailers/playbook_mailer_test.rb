require 'test_helper'

class PlaybookMailerTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers

  def setup
    Rails.application.routes.default_url_options[:host] = 'test.host'
    # WHY: Create test data for all mailer scenarios
    @amplifa_admin = accounts(:amplifa_admin)
    @customer_admin = accounts(:customer_admin)
    @organization = organizations(:acme)

    # Create a playbook for testing
    @playbook = Playbook.create!(
      organization: @organization,
      product: { 'name' => 'Test CRM Platform', 'description' => 'A test product', 'metadata' => {} },
      language: 'en',
      value_proposition: 'Transform your sales process',
      personae: [
        { 'id' => SecureRandom.uuid, 'name' => 'Sales Director Sarah', 'title' => 'VP Sales',
          'pain_points' => ['Too much manual work'], 'order' => 1 }
      ],
      use_cases: [
        { 'id' => SecureRandom.uuid, 'title' => 'Lead Generation', 'description' => 'Generate qualified leads',
          'order' => 1 }
      ],
      references: [],
      proof_points: [],
      status: 'draft'
    )
  end

  test 'playbook_generated sends email to all admins' do
    # WHY: Verify admins are notified when AI generation completes
    email = PlaybookMailer.playbook_generated(@playbook, @amplifa_admin)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check that email goes to all amplifa admins
    assert_includes email.to, @amplifa_admin.email

    # WHY: Check subject contains product and organization names
    assert_match @playbook.product_name, email.subject
    assert_match @organization.name, email.subject

    # WHY: Check body contains generated content details
    assert_match @playbook.product_name, email.body.encoded
    assert_match @amplifa_admin.full_name, email.body.encoded
  end

  test 'playbook_generated uses organization locale for translations' do
    # WHY: Verify emails are sent in organization's language
    @organization.update!(locale: 'de')

    email = PlaybookMailer.playbook_generated(@playbook, @amplifa_admin)

    # WHY: German subject should contain "generiert"
    assert_match(/generiert/, email.subject)
  end

  test 'playbook_generation_failed sends error details' do
    # WHY: Verify admins are notified of generation failures with error details
    error_message = 'Failed to scrape website: timeout'

    email = PlaybookMailer.playbook_generation_failed(
      @organization,
      'https://example.com',
      'New Product',
      error_message,
      @amplifa_admin
    )

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check error message is included
    assert_match error_message, email.body.encoded
    assert_match 'example.com', email.body.encoded
    assert_match 'New Product', email.body.encoded
  end

  test 'changes_requested sends email to admins with customer feedback' do
    # WHY: Verify admins receive customer's change requests
    comment = @playbook.playbook_comments.create!(
      account: @customer_admin,
      body: 'Please add more use cases for enterprise clients',
      comment_type: 'request_changes'
    )

    email = PlaybookMailer.changes_requested(@playbook, @customer_admin, comment)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check comment body is included
    assert_match comment.body, email.body.encoded
    assert_match @customer_admin.full_name, email.body.encoded
  end

  test 'playbook_approved sends email to admins and all customers' do
    # WHY: Verify approval notification goes to all relevant parties
    @playbook.approve!(@customer_admin)

    email = PlaybookMailer.playbook_approved(@playbook, @customer_admin)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check both admins and customers receive it
    admin_emails = Account.amplifa_admins.pluck(:email)
    customer_emails = @organization.all_users.pluck(:email)
    all_recipients = (admin_emails + customer_emails).uniq

    all_recipients.each do |recipient|
      assert_includes email.to, recipient
    end

    # WHY: Check approver is mentioned
    assert_match @customer_admin.full_name, email.body.encoded
  end

  test 'moved_to_draft sends email to customer admins only' do
    # WHY: Verify only customer admins are notified when playbook returns to draft
    @playbook.update!(status: 'changes_requested')

    email = PlaybookMailer.moved_to_draft(@playbook)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check email goes to customer admins
    customer_admin_emails = @organization.admin_users.pluck(:email)
    customer_admin_emails.each do |recipient|
      assert_includes email.to, recipient
    end
  end

  test 'moved_to_draft does not send email when organization has no customer admins' do
    org_without_admins = Organization.create!(
      name: 'No Admin Org',
      locale: 'en',
      status: 'active'
    )

    playbook_without_admins = Playbook.create!(
      organization: org_without_admins,
      product: { 'name' => 'No Admin Product', 'description' => 'A test product', 'metadata' => {} },
      language: 'en',
      value_proposition: 'Test value proposition',
      personae: [
        { 'id' => SecureRandom.uuid, 'name' => 'Persona', 'title' => 'Role', 'pain_points' => ['Pain'], 'order' => 1 }
      ],
      use_cases: [
        { 'id' => SecureRandom.uuid, 'title' => 'Use case', 'description' => 'Description', 'order' => 1 }
      ],
      references: [],
      proof_points: [],
      status: 'draft'
    )

    assert_no_emails do
      PlaybookMailer.moved_to_draft(playbook_without_admins).deliver_now
    end
  end

  test 'ready_for_review sends email to all customers' do
    # WHY: Verify all customer users are notified of new playbook
    email = PlaybookMailer.ready_for_review(@playbook)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check email goes to all customer users
    customer_emails = @organization.all_users.pluck(:email)
    customer_emails.each do |recipient|
      assert_includes email.to, recipient
    end

    # WHY: Check product name is in email
    assert_match @playbook.product_name, email.body.encoded
  end

  test 'playbook_archived sends email to admins and customer admins' do
    # WHY: Verify relevant parties are notified of archiving
    email = PlaybookMailer.playbook_archived(@playbook, @amplifa_admin)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check archiver is mentioned
    assert_match @amplifa_admin.full_name, email.body.encoded
  end

  test 'new_comment sends email to admins when customer comments' do
    # WHY: Verify admins are notified of customer comments
    comment = @playbook.playbook_comments.create!(
      account: @customer_admin,
      body: 'This looks great!',
      comment_type: 'general'
    )

    email = PlaybookMailer.new_comment(@playbook, comment)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check email goes to admins (opposite of commenter's role)
    admin_emails = Account.amplifa_admins.pluck(:email)
    admin_emails.each do |recipient|
      assert_includes email.to, recipient
    end

    # WHY: Check comment content is included
    assert_match comment.body, email.body.encoded
    assert_match @customer_admin.full_name, email.body.encoded
  end

  test 'new_comment sends email to customers when admin comments' do
    # WHY: Verify customers are notified of admin comments
    comment = @playbook.playbook_comments.create!(
      account: @amplifa_admin,
      body: "We've updated the playbook based on your feedback",
      comment_type: 'general'
    )

    email = PlaybookMailer.new_comment(@playbook, comment)

    assert_emails 1 do
      email.deliver_now
    end

    # WHY: Check email goes to customers (opposite of commenter's role)
    customer_emails = @organization.all_users.pluck(:email)
    customer_emails.each do |recipient|
      assert_includes email.to, recipient
    end
  end

  test 'all mailers generate both HTML and text versions' do
    # WHY: Verify email clients without HTML support can read emails
    email = PlaybookMailer.playbook_generated(@playbook, @amplifa_admin)

    assert_equal 2, email.parts.length
    assert_equal 'text/plain', email.parts.first.content_type.split(';').first
    assert_equal 'text/html', email.parts.last.content_type.split(';').first
  end

  test 'mailers use correct from address' do
    # WHY: Verify emails come from configured sender
    email = PlaybookMailer.playbook_generated(@playbook, @amplifa_admin)

    expected_from = ENV.fetch('MAILER_FROM', 'noreply@updates.amplifa.eu')
    assert_includes email.from, expected_from
  end

end
