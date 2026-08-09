# frozen_string_literal: true

require 'test_helper'
require 'uri'

class CalendarInviteLinkBuilderTest < ActiveSupport::TestCase
  test 'builds google and outlook links for a timed invite attachment' do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(File.binread(Rails.root.join('test/fixtures/files/sample.ics'))),
      filename: 'invite.ics',
      content_type: 'text/calendar'
    )

    document = Struct.new(:attached?, :download, :blob_id).new(true, blob.download, blob.id)
    links = CalendarInviteLinkBuilder.build(file: document, fallback_title: 'invite')

    assert_not_nil links
    assert_includes links[:google_url], 'calendar.google.com/calendar/render'
    assert_includes links[:google_url], 'text=Demo+call'
    assert_includes links[:google_url], 'dates=20260415T090000Z%2F20260415T093000Z'
    assert_includes links[:outlook_url], 'outlook.office.com/calendar/0/deeplink/compose'
    assert_includes links[:outlook_url], 'subject=Demo%20call'
    assert_includes links[:outlook_url], 'startdt=2026-04-15T09%3A00%3A00'
    refute_includes links[:outlook_url], 'startdt=2026-04-15T09%3A00%3A00Z'
  end

  test 'builds all-day links from date-based events' do
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 123)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART;VALUE=DATE:20260510
      SUMMARY:Offsite
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')

    assert_not_nil links
    assert_includes links[:google_url], 'dates=20260510%2F20260511'
    assert_includes links[:outlook_url], 'startdt=2026-05-10'
    assert_includes links[:outlook_url], 'enddt=2026-05-11'
    assert_includes links[:outlook_url], 'allday=true'
  end

  test 'preserves common invite fields and virtual meeting details' do
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 456)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:event-123@example.com
      DTSTART:20260510T150000Z
      DTEND:20260510T160000Z
      SUMMARY:Pipeline review
      DESCRIPTION:Review Q2 pipeline
      LOCATION:HQ Board Room
      URL:https://app.example.com/meetings/123
      ORGANIZER;CN=Alex Founder:mailto:alex@example.com
      ATTENDEE;CN=Taylor Buyer:mailto:taylor@example.com
      ATTENDEE:mailto:sam@example.com
      RRULE:FREQ=WEEKLY;COUNT=3
      TRANSP:TRANSPARENT
      STATUS:TENTATIVE
      CATEGORIES:Sales,Demo
      CONFERENCE;VALUE=URI;FEATURE=VIDEO;LABEL=Zoom Join:https://zoom.us/j/123456789?pwd=secret
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')

    google_params = query_params(links[:google_url])
    outlook_params = query_params(links[:outlook_url])

    assert_equal 'Pipeline review', google_params['text']
    assert_equal '20260510T150000Z/20260510T160000Z', google_params['dates']
    assert_equal 'taylor@example.com,sam@example.com', google_params['add']
    assert_equal 'RRULE:FREQ=WEEKLY;COUNT=3', google_params['recur']
    assert_equal 'false', google_params['trp']
    assert_includes google_params['details'], 'Review Q2 pipeline'
    assert_includes google_params['details'], 'Zoom Join: https://zoom.us/j/123456789?pwd=secret'
    assert_includes google_params['details'], 'Event link: https://app.example.com/meetings/123'
    assert_includes google_params['details'], 'Organizer: Alex Founder <alex@example.com>'
    assert_includes google_params['details'], 'Attendees: Taylor Buyer <taylor@example.com>, sam@example.com'
    assert_includes google_params['details'], 'Status: TENTATIVE'
    assert_includes google_params['details'], 'Categories: Sales, Demo'
    assert_includes google_params['details'], 'UID: event-123@example.com'

    assert_equal 'Pipeline review', outlook_params['subject']
    assert_equal '2026-05-10T15:00:00', outlook_params['startdt']
    assert_equal '2026-05-10T16:00:00', outlook_params['enddt']
    assert_equal 'taylor@example.com,sam@example.com', outlook_params['to']
    assert_equal 'free', outlook_params['freebusy']
    assert_equal 'HQ Board Room', outlook_params['location']
    assert_includes outlook_params['body'], 'Zoom Join: https://zoom.us/j/123456789?pwd=secret'
    assert_includes outlook_params['body'], 'Recurrence: RRULE:FREQ=WEEKLY;COUNT=3'
  end

  test 'builds links from structured calendar event data' do
    links = CalendarInviteLinkBuilder.build_from_event_data(
      event_data: {
        title: 'Project kickoff',
        message_type: 'meetingRequest',
        location: 'Teams',
        organizer_name: 'Event Organizer',
        organizer_email: 'organizer@example.com',
        attendees: [
          { name: 'Guest One', email: 'guest1@example.com' },
          { email: 'guest2@example.com' }
        ],
        conference_links: [
          { label: 'Join meeting', url: 'https://teams.microsoft.com/l/meetup-join/abc123' }
        ],
        start_at: {
          date_time: '2025-01-03T15:00:00.0000000',
          time_zone: 'Pacific Standard Time'
        },
        end_at: {
          date_time: '2025-01-03T15:30:00.0000000',
          time_zone: 'Pacific Standard Time'
        }
      }
    )

    google_params = query_params(links[:google_url])
    outlook_params = query_params(links[:outlook_url])

    assert_equal 'Project kickoff', google_params['text']
    assert_equal '20250103T150000/20250103T153000', google_params['dates']
    assert_equal 'America/Los_Angeles', google_params['ctz']
    assert_equal 'guest1@example.com,guest2@example.com', google_params['add']
    assert_includes google_params['details'], 'Join meeting: https://teams.microsoft.com/l/meetup-join/abc123'
    assert_includes google_params['details'], 'Organizer: Event Organizer <organizer@example.com>'
    assert_includes google_params['details'], 'Attendees: Guest One <guest1@example.com>, guest2@example.com'
    assert_includes google_params['details'], 'Status: meetingRequest'
    assert_includes google_params['details'], 'Timezone: Pacific Standard Time'

    assert_equal 'Project kickoff', outlook_params['subject']
    assert_equal '2025-01-03T15:00:00', outlook_params['startdt']
    assert_equal '2025-01-03T15:30:00', outlook_params['enddt']
    assert_equal 'guest1@example.com,guest2@example.com', outlook_params['to']
    assert_equal 'Teams', outlook_params['location']
    assert_includes links[:outlook_url], '/calendar/0/deeplink/compose'
    assert_includes outlook_params['body'], 'Join meeting: https://teams.microsoft.com/l/meetup-join/abc123'
    assert_includes outlook_params['body'], 'Organizer: Event Organizer <organizer@example.com>'
    assert_includes outlook_params['body'], 'Attendees: Guest One <guest1@example.com>, guest2@example.com'
    assert_includes outlook_params['body'], 'Timezone: Pacific Standard Time'
  end

  test 'compacts long structured event descriptions in outlook links while preserving essentials' do
    teams_url = 'https://teams.microsoft.com/l/meetup-join/abc123?context=meeting'
    long_description = "Brief agenda for the meeting.\n#{'Corporate confidentiality notice. ' * 300}"

    links = CalendarInviteLinkBuilder.build_from_event_data(
      event_data: {
        title: 'Future Day planning',
        message_type: 'meetingRequest',
        description: long_description,
        location: 'Microsoft Teams',
        organizer_name: 'Event Organizer',
        organizer_email: 'organizer@example.com',
        attendees: [
          { name: 'Guest One', email: 'guest1@example.com' },
          { email: 'guest2@example.com' }
        ],
        conference_links: [
          { label: 'Join meeting', url: teams_url }
        ],
        start_at: {
          date_time: '2026-07-20T11:00:00',
          time_zone: 'W. Europe Standard Time'
        },
        end_at: {
          date_time: '2026-07-20T11:30:00',
          time_zone: 'W. Europe Standard Time'
        }
      }
    )

    outlook_params = query_params(links[:outlook_url])

    assert_operator URI(links[:outlook_url]).query.bytesize, :<=, CalendarInviteLinkBuilder::OUTLOOK_QUERY_BYTES_LIMIT
    assert_equal 'Future Day planning', outlook_params['subject']
    assert_equal '2026-07-20T11:00:00', outlook_params['startdt']
    assert_equal '2026-07-20T11:30:00', outlook_params['enddt']
    assert_equal 'Microsoft Teams', outlook_params['location']
    assert_equal 'guest1@example.com,guest2@example.com', outlook_params['to']
    assert_includes outlook_params['body'], "Meeting links: Join meeting: #{teams_url}"
    assert_includes outlook_params['body'], 'Organizer: Event Organizer <organizer@example.com>'
    assert_includes outlook_params['body'], 'Timezone: W. Europe Standard Time'
    assert_includes outlook_params['body'], 'Attendees: - Guest One <guest1@example.com>; - guest2@example.com'
    assert_includes outlook_params['body'], 'Description: Brief agenda for the meeting.'
    assert_includes outlook_params['body'], ' | '
    refute_includes outlook_params['body'], "\r\n"
    refute_includes outlook_params['body'], "\n"
    refute_includes outlook_params['body'], '<br'
    assert_includes outlook_params['body'], CalendarInviteLinkBuilder::OUTLOOK_TRUNCATION_MARKER
    assert_operator outlook_params['body'].length, :<, long_description.length
    refute_includes outlook_params['body'], 'full details are in the original message'
    refute_includes outlook_params['body'], 'Corporate confidentiality notice. ' * 100
  end

  test 'compacts long invite attachment descriptions in outlook links while preserving meeting links' do
    teams_url = 'https://teams.microsoft.com/l/meetup-join/attachment-meeting?context=meeting'
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 792)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART;TZID="W. Europe Standard Time":20260720T110000
      DTEND;TZID="W. Europe Standard Time":20260720T113000
      SUMMARY:Future Day attachment
      DESCRIPTION:Brief agenda for the meeting. #{'Long legal disclaimer. ' * 300}
      LOCATION:Microsoft Teams
      ORGANIZER;CN=Event Organizer:mailto:organizer@example.com
      ATTENDEE;CN=Guest One:mailto:guest1@example.com
      CONFERENCE;VALUE=URI;FEATURE=VIDEO;LABEL=Join meeting:#{teams_url}
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')
    outlook_params = query_params(links[:outlook_url])

    assert_operator URI(links[:outlook_url]).query.bytesize, :<=, CalendarInviteLinkBuilder::OUTLOOK_QUERY_BYTES_LIMIT
    assert_equal 'Future Day attachment', outlook_params['subject']
    assert_equal '2026-07-20T11:00:00', outlook_params['startdt']
    assert_equal '2026-07-20T11:30:00', outlook_params['enddt']
    assert_equal 'Microsoft Teams', outlook_params['location']
    assert_equal 'guest1@example.com', outlook_params['to']
    assert_includes outlook_params['body'], "Meeting links: Join meeting: #{teams_url}"
    assert_includes outlook_params['body'], 'Organizer: Event Organizer <organizer@example.com>'
    assert_includes outlook_params['body'], 'Attendees: - Guest One <guest1@example.com>'
    assert_includes outlook_params['body'], 'Description: Brief agenda for the meeting.'
    assert_includes outlook_params['body'], ' | '
    refute_includes outlook_params['body'], "\r\n"
    refute_includes outlook_params['body'], "\n"
    refute_includes outlook_params['body'], '<br'
    assert_includes outlook_params['body'], CalendarInviteLinkBuilder::OUTLOOK_TRUNCATION_MARKER
    refute_includes outlook_params['body'], 'full details are in the original message'
    refute_includes outlook_params['body'], 'Long legal disclaimer. ' * 100
  end

  test 'builds timed links for ICS invites with Outlook timezone identifiers' do
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 789)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART;TZID=Pacific Standard Time:20250103T150000
      DTEND;TZID=Pacific Standard Time:20250103T153000
      SUMMARY:Project kickoff
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')

    google_params = query_params(links[:google_url])
    outlook_params = query_params(links[:outlook_url])

    assert_equal 'Project kickoff', google_params['text']
    assert_equal '20250103T150000/20250103T153000', google_params['dates']
    assert_equal 'America/Los_Angeles', google_params['ctz']

    assert_equal 'Project kickoff', outlook_params['subject']
    assert_equal '2025-01-03T15:00:00', outlook_params['startdt']
    assert_equal '2025-01-03T15:30:00', outlook_params['enddt']
  end

  test 'builds timed links for ICS invites with quoted Outlook timezone identifiers' do
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 790)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART;TZID="Pacific Standard Time":20250103T150000
      DTEND;TZID="Pacific Standard Time":20250103T153000
      SUMMARY:Quoted kickoff
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')

    google_params = query_params(links[:google_url])
    outlook_params = query_params(links[:outlook_url])

    assert_equal 'Quoted kickoff', google_params['text']
    assert_equal 'America/Los_Angeles', google_params['ctz']
    assert_equal '2025-01-03T15:00:00', outlook_params['startdt']
    assert_equal '2025-01-03T15:30:00', outlook_params['enddt']
  end

  test 'extracts structured event data from an ICS invite' do
    event_data = CalendarInviteLinkBuilder.event_data_from_ics(
      source: 'google_gmail',
      content: <<~ICS
        BEGIN:VCALENDAR
        VERSION:2.0
        METHOD:REQUEST
        BEGIN:VEVENT
        DTSTART;TZID="Pacific Standard Time":20250103T150000
        DTEND;TZID="Pacific Standard Time":20250103T153000
        SUMMARY:Project kickoff
        LOCATION:Teams
        ORGANIZER;CN=Event Organizer:mailto:organizer@example.com
        ATTENDEE;CN=Guest One:mailto:guest1@example.com
        END:VEVENT
        END:VCALENDAR
      ICS
    )

    assert_equal 'google_gmail', event_data[:source]
    assert_equal 'meetingRequest', event_data[:message_type]
    assert_equal 'Project kickoff', event_data[:title]
    assert_equal 'Teams', event_data[:location]
    assert_equal '2025-01-03T15:00:00', event_data.dig(:start_at, :date_time)
    assert_equal 'America/Los_Angeles', event_data.dig(:start_at, :time_zone)
    assert_equal 'Event Organizer', event_data[:organizer_name]
    assert_equal 'organizer@example.com', event_data[:organizer_email]
    assert_equal [{ name: 'Guest One', email: 'guest1@example.com' }], event_data[:attendees]
  end

  test 'does not label deceptive meeting-like hosts as join links' do
    file = Struct.new(:attached?, :download, :blob_id).new(true, <<~ICS, 791)
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      DTSTART:20250103T150000Z
      DTEND:20250103T153000Z
      SUMMARY:Security review
      DESCRIPTION:https://teams.microsoft.com.evil.example/join/123
      END:VEVENT
      END:VCALENDAR
    ICS

    links = CalendarInviteLinkBuilder.build(file:, fallback_title: 'invite')
    outlook_params = query_params(links[:outlook_url])

    assert_includes outlook_params['body'], 'https://teams.microsoft.com.evil.example/join/123'
    refute_includes outlook_params['body'], 'Join meeting: https://teams.microsoft.com.evil.example/join/123'
  end

  test 'returns nil for oversized ICS attachments without downloading them' do
    oversized_file = Class.new do
      attr_reader :blob_id, :byte_size

      def initialize
        @blob_id = 991
        @byte_size = CalendarInviteLinkBuilder::MAX_ATTACHMENT_BYTES + 1
      end

      def attached?
        true
      end

      def download
        raise 'download should not be called for oversized attachment'
      end
    end.new

    assert_nil CalendarInviteLinkBuilder.build(file: oversized_file, fallback_title: 'invite')
  end

  private

  def query_params(url)
    URI.decode_www_form(URI(url).query).to_h
  end
end
