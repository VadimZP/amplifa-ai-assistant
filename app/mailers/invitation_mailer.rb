class InvitationMailer < ApplicationMailer
  self.deliver_later_queue_name = :mailers

  # Sends an invitation email to a new user inviting them to join an organization on Amplifa
  #
  # @param invitation [Invitation] The invitation record containing all necessary details
  # @return [Mail::Message] The invitation email message
  def invite(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @invited_by = invitation.invited_by
    @accept_url = accept_invitation_url(invitation.token)

    # Use the organization's locale for the email
    # This ensures German customers get German emails, English customers get English emails
    I18n.with_locale(@organization.locale) do
      mail(
        to: invitation.email,
        subject: I18n.t('mailers.invitation.subject', organization: @organization.name)
      )
    end
  end
end
