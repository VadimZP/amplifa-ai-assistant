# frozen_string_literal: true

require 'test_helper'

class AdminNotificationMailerTest < ActionMailer::TestCase
  test 'customer_lead_import_completed notifies all amplifa admins' do
    lead_import = lead_imports(:completed_import)

    email = AdminNotificationMailer.customer_lead_import_completed(lead_import)

    assert_emails 1 do
      email.deliver_now
    end

    assert_includes email.subject, lead_import.organization.name
    assert_includes email.subject, lead_import.imported_by.full_name
    assert_includes email.body.encoded, lead_import.original_filename
  end

  test 'customer_lead_import_failed includes failure reason' do
    lead_import = lead_imports(:failed_import)

    email = AdminNotificationMailer.customer_lead_import_failed(lead_import, 'CSV parsing failed')

    assert_emails 1 do
      email.deliver_now
    end

    assert_includes email.subject, lead_import.organization.name
    assert_includes email.body.encoded, 'CSV parsing failed'
  end

  test 'lead_list_file_uploaded notifies all amplifa admins' do
    organization = organizations(:acme)
    uploader = accounts(:customer_admin)
    playbook = playbooks(:approved_playbook)

    lead_list_file = organization.organization_files.new(
      uploaded_by: uploader,
      original_filename: 'prospects-no-emails.xlsx',
      file_size_bytes: 12_345,
      content_type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
    lead_list_file.file.attach(io: StringIO.new('fake content'), filename: 'prospects-no-emails.xlsx')
    lead_list_file.save!
    lead_list_file.playbooks << playbook

    email = AdminNotificationMailer.lead_list_file_uploaded(lead_list_file)

    assert_emails 1 do
      email.deliver_now
    end

    admin_emails = Account.amplifa_admins.pluck(:email)
    assert_equal admin_emails.sort, email.to.sort
    assert_includes email.subject, organization.name
    assert_includes email.subject, uploader.full_name
    assert_includes email.body.encoded, 'prospects-no-emails.xlsx'
    assert_includes email.body.encoded, uploader.full_name
    assert_includes email.body.encoded, uploader.email
    assert_includes email.body.encoded, organization.name
    assert_includes email.body.encoded, playbook.product_name
  end

  test 'integration_connected sends support email with all required details' do
    organization = organizations(:acme)
    account = accounts(:customer_admin)
    integration_name = 'HubSpot'
    api_key = 'sk_test_abc123xyz789'

    email = AdminNotificationMailer.integration_connected(organization, account, integration_name, api_key)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ['hello@amplifa.ai'], email.to
    assert_match organization.name, email.subject
    assert_match integration_name, email.subject
    assert_match account.full_name, email.body.encoded
    assert_match account.email, email.body.encoded
    assert_match organization.name, email.body.encoded
    assert_match integration_name, email.body.encoded
    assert_match api_key, email.body.encoded
  end

  test 'billing_interest includes optional lead context when provided' do
    organization = organizations(:acme)
    account = accounts(:customer_admin)
    lead = leads(:john_doe)

    email = AdminNotificationMailer.billing_interest(
      organization,
      account,
      'upgrade_for_buying_signals',
      'Upgrade to get buying signals',
      lead
    )

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ['hello@amplifa.ai'], email.to
    assert_includes email.subject, organization.name
    assert_includes email.subject, 'Upgrade to get buying signals'
    assert_includes email.body.encoded, account.full_name
    assert_includes email.body.encoded, account.email
    assert_includes email.body.encoded, lead.display_name
    assert_includes email.body.encoded, lead.email
    assert_includes email.body.encoded, lead.company
    assert_includes email.body.encoded, lead.job_title
  end

end
