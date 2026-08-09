# frozen_string_literal: true

class MeetingAssignmentMailer < ApplicationMailer
  self.deliver_later_queue_name = :mailers

  def assignment_notification
    @meeting = params[:meeting]
    @assignee = params[:assignee]
    @assigned_by = params[:assigned_by]
    @organization = @meeting.organization
    @lead = @meeting.lead
    @agent = @meeting.agent
    @meetings_url = meetings_url

    I18n.with_locale(@organization.locale) do
      mail(
        to: @assignee.email,
        subject: t(
          'mailers.meeting_assignment.subject',
          default: "You've been assigned a meeting with %<lead_name>s",
          lead_name: @lead&.full_name || @lead&.email || 'a lead'
        )
      )
    end
  end
end
