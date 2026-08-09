# WHY: Sends email notifications for all playbook status changes and activity
# This enables async communication between Amplifa admins and customers during the approval workflow
class PlaybookMailer < ApplicationMailer
  self.deliver_later_queue_name = :mailers
  default from: "Amplifa <#{ENV.fetch('MAILER_FROM', 'noreply@updates.amplifa.eu')}>"

  # WHY: Notify admins when AI generation completes successfully
  # So they can review and publish the generated playbook to customers
  def playbook_generated(playbook, initiated_by)
    @playbook = playbook
    @organization = playbook.organization
    @product_name = playbook.product_name
    @initiated_by = initiated_by
    @admin_emails = Account.amplifa_admins.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: @admin_emails,
        subject: I18n.t('mailers.playbook.generated.subject',
                        product: @product_name,
                        organization: @organization.name)
      )
    end
  end

  # WHY: Notify admins when AI generation fails
  # So they can investigate and retry or manually create the playbook
  def playbook_generation_failed(organization, website_url, product_name, error_message, initiated_by)
    @organization = organization
    @website_url = website_url
    @product_name = product_name
    @error_message = error_message
    @initiated_by = initiated_by
    @admin_emails = Account.amplifa_admins.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: @admin_emails,
        subject: I18n.t('mailers.playbook.generation_failed.subject',
                        product: product_name,
                        organization: @organization.name)
      )
    end
  end

  # WHY: Notify admins when customer requests changes
  # So they can see the feedback and make necessary edits
  def changes_requested(playbook, requested_by, comment)
    @playbook = playbook
    @organization = playbook.organization
    @requested_by = requested_by
    @comment = comment
    @admin_emails = Account.amplifa_admins.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: @admin_emails,
        subject: I18n.t('mailers.playbook.changes_requested.subject',
                        organization: @organization.name,
                        product: @playbook.product_name)
      )
    end
  end

  # WHY: Notify admins and customers when playbook is approved
  # Celebrates success and informs team that playbook is ready to use
  def playbook_approved(playbook, approved_by)
    @playbook = playbook
    @organization = playbook.organization
    @approved_by = approved_by

    # Send to admins and all customer users
    recipient_emails = Account.amplifa_admins.pluck(:email) +
                       @organization.all_users.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: recipient_emails.uniq,
        subject: I18n.t('mailers.playbook.approved.subject',
                        product: @playbook.product_name,
                        organization: @organization.name)
      )
    end
  end

  # WHY: Notify customer when admin moves playbook back to draft after making edits
  # So customer knows to review the updated playbook
  def moved_to_draft(playbook)
    @playbook = playbook
    @organization = playbook.organization
    @customer_admin_emails = @organization.admin_users.pluck(:email)
    return if @customer_admin_emails.empty?

    I18n.with_locale(@organization.locale) do
      mail(
        to: @customer_admin_emails,
        subject: I18n.t('mailers.playbook.moved_to_draft.subject',
                        product: @playbook.product_name)
      )
    end
  end

  # WHY: Notify customer when admin publishes draft for first time
  # So customer knows a new playbook is ready for their review
  def ready_for_review(playbook)
    @playbook = playbook
    @organization = playbook.organization
    @customer_emails = @organization.all_users.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: @customer_emails,
        subject: I18n.t('mailers.playbook.ready_for_review.subject',
                        product: @playbook.product_name)
      )
    end
  end

  # WHY: Notify relevant parties when playbook is archived
  # So everyone knows the playbook is no longer active
  def playbook_archived(playbook, archived_by)
    @playbook = playbook
    @organization = playbook.organization
    @archived_by = archived_by

    # Send to admins and customer admins
    recipient_emails = Account.amplifa_admins.pluck(:email) +
                       @organization.admin_users.pluck(:email)

    I18n.with_locale(@organization.locale) do
      mail(
        to: recipient_emails.uniq,
        subject: I18n.t('mailers.playbook.archived.subject',
                        product: @playbook.product_name)
      )
    end
  end

  # WHY: Notify opposite party when new comment is added
  # Enables async conversation between admins and customers
  def new_comment(playbook, comment)
    @playbook = playbook
    @organization = playbook.organization
    @comment = comment
    @commenter = comment.account

    # Send to admins if commenter is customer, and vice versa
    recipient_emails = if @commenter.amplifa_admin?
                         @organization.all_users.pluck(:email)
                       else
                         Account.amplifa_admins.pluck(:email)
                       end

    I18n.with_locale(@organization.locale) do
      mail(
        to: recipient_emails,
        subject: I18n.t('mailers.playbook.new_comment.subject',
                        product: @playbook.product_name)
      )
    end
  end
end
