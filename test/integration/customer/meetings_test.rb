# frozen_string_literal: true

require 'test_helper'

class Customer::MeetingsTest < ActionDispatch::IntegrationTest
  test 'customer can view meetings index with meeting metadata' do
    login_as(accounts(:customer_admin))

    get meetings_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 'Meetings/Index', body['component']
    assert body['props']['meetings'].is_a?(Array)
    assert body['props']['assignable_users'].is_a?(Array)

    meeting = body['props']['meetings'].first
    assert meeting.key?('created_at')
    assert meeting.key?('status')
    assert meeting.key?('notes')
    assert meeting.key?('lead')
    assert meeting.key?('agent')
    assert meeting.key?('assigned_to_account')
  end

  test 'customer can search leads for manual meeting creation' do
    login_as(accounts(:customer_admin))

    get search_leads_meetings_path, params: { q: leads(:john_doe).email }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    emails = body['leads'].map { |lead| lead['email'] }

    assert_includes emails, leads(:john_doe).email
  end

  test 'lead search returns first assigned agents and has more state' do
    login_as(accounts(:customer_admin))

    21.times do |index|
      Lead.create!(
        organization: organizations(:acme),
        email: "manual-search-#{index}@example.com",
        first_name: 'Manual',
        last_name: "Search #{index}"
      )
    end

    get search_leads_meetings_path, params: { q: 'manual-search' }, as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 20, body['leads'].length
    assert_equal true, body['has_more']

    get search_leads_meetings_path, params: { q: leads(:john_doe).email }, as: :json

    assert_response :success
    john = JSON.parse(response.body)['leads'].find { |lead| lead['id'] == leads(:john_doe).id }

    assert john
    assert_equal [agents(:draft_agent).id, agents(:ready_agent).id], john['assigned_agent_ids']
  end

  test 'lead search handles umlauts and sharp s' do
    login_as(accounts(:customer_admin))
    lead = Lead.create!(
      organization: organizations(:acme),
      email: 'unicode-search@example.com',
      first_name: 'Müller',
      last_name: 'Groß',
      company: 'Größe GmbH'
    )

    get search_leads_meetings_path, params: { q: 'Muller' }, as: :json

    assert_response :success
    emails = JSON.parse(response.body)['leads'].map { |result| result['email'] }

    assert_includes emails, lead.email

    get search_leads_meetings_path, params: { q: 'Gross' }, as: :json

    assert_response :success
    emails = JSON.parse(response.body)['leads'].map { |result| result['email'] }

    assert_includes emails, lead.email
  end

  test 'customer can manually create a meeting for an existing lead' do
    login_as(accounts(:customer_admin))
    scheduled_at = 3.days.from_now.change(sec: 0)

    assert_difference('Meeting.count', 1) do
      post meetings_path,
           params: {
             agent_id: agents(:draft_agent).id,
             lead_id: leads(:john_doe).id,
             scheduled_at: scheduled_at.iso8601,
             notes: 'Created from the customer meetings page.'
           },
           as: :json
    end

    assert_response :created
    meeting = Meeting.order(:created_at).last
    assert_equal leads(:john_doe), meeting.lead
    assert_equal agents(:draft_agent), meeting.agent
    assert_equal 'scheduled', meeting.status
    assert_equal 'Created from the customer meetings page.', meeting.notes
    assert_in_delta scheduled_at.to_i, meeting.scheduled_at.to_i, 2
  end

  test 'customer can manually create a meeting with a new skeleton lead' do
    login_as(accounts(:customer_admin))
    email = 'manual-meeting-lead@example.com'

    assert_difference('Lead.count', 1) do
      assert_difference('AgentLead.count', 1) do
        assert_difference('Meeting.count', 1) do
          post meetings_path,
               params: {
                 agent_id: agents(:draft_agent).id,
                 notes: 'Discuss expansion opportunity.',
                 lead: {
                   name: 'Marta Müller',
                   email: email,
                   company: 'Example GmbH',
                   role: 'Head of Growth'
                 }
               },
               as: :json
        end
      end
    end

    assert_response :created
    lead = Lead.find_by!(email: email)
    meeting = Meeting.order(:created_at).last
    assert_equal lead, meeting.lead
    assert_equal 'Marta', lead.first_name
    assert_equal 'Müller', lead.last_name
    assert_equal 'Example GmbH', lead.company
    assert_equal 'Head of Growth', lead.job_title
    assert_equal 'scheduling', meeting.status
    assert_equal 'Discuss expansion opportunity.', meeting.notes
  end

  test 'customer can assign meeting to a teammate and notify them by email' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    assignee = accounts(:customer_user)

    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs do
      post assign_meeting_path(meeting),
           params: { assigned_to_account_id: assignee.id },
           as: :json
    end

    assert_response :success
    assert_equal assignee, meeting.reload.assigned_to_account
    assert_equal 1, ActionMailer::Base.deliveries.size
    assert_equal [assignee.email], ActionMailer::Base.deliveries.last.to
    assert_includes ActionMailer::Base.deliveries.last.body.encoded, meeting.lead.full_name
  end

  test 'customer cannot assign meeting to another organizations teammate' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    post assign_meeting_path(meeting),
         params: { assigned_to_account_id: accounts(:growth_lab_user).id },
         as: :json

    assert_response :not_found
    assert_nil meeting.reload.assigned_to_account
  end

  test 'customer only sees own organization meetings' do
    login_as(accounts(:customer_user))

    get meetings_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    agent_ids = Agent.where(organization: organizations(:acme)).pluck(:id)

    body['props']['meetings'].each do |meeting|
      assert_includes agent_ids, meeting.dig('agent', 'id')
    end
  end

  test 'customer meetings are sorted by date added then scheduled date' do
    login_as(accounts(:customer_admin))

    base_attributes = {
      organization: organizations(:acme),
      agent_lead: agent_leads(:john_in_draft),
      lead: leads(:john_doe),
      agent: agents(:draft_agent),
      status: 'positive',
      source: 'manual',
      outcome: 'positive'
    }

    older_meeting = Meeting.create!(
      **base_attributes,
      meeting_type: 'demo',
      scheduled_at: 5.days.from_now,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )

    newer_meeting = Meeting.create!(
      **base_attributes,
      meeting_type: 'follow_up',
      scheduled_at: 1.day.from_now,
      created_at: 1.day.ago,
      updated_at: 1.day.ago
    )

    get meetings_path, params: { status_filter: 'positive' }, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    ids = body['props']['meetings'].map { |meeting| meeting['id'] }

    assert_operator ids.index(newer_meeting.id), :<, ids.index(older_meeting.id)
  end

  test 'scheduled filter includes rescheduled meetings' do
    login_as(accounts(:customer_admin))

    rescheduled_meeting = Meeting.create!(
      organization: organizations(:acme),
      agent_lead: agent_leads(:john_in_draft),
      lead: leads(:john_doe),
      agent: agents(:draft_agent),
      status: 'rescheduled',
      source: 'manual',
      meeting_type: 'follow_up',
      scheduled_at: 4.days.from_now
    )

    get meetings_path, params: { status_filter: 'scheduled' }, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    ids = body['props']['meetings'].map { |meeting| meeting['id'] }

    assert_includes ids, meetings(:scheduled_discovery).id
    assert_includes ids, rescheduled_meeting.id
    assert_equal 2, body.dig('props', 'tab_counts', 'scheduled')
  end

  test 'customer can request meeting removal' do
    login_as(accounts(:customer_user))
    meeting = meetings(:scheduled_discovery)

    post request_removal_meeting_path(meeting), headers: { 'Accept' => 'application/json' }

    assert_response :success
    assert_equal 'pending_removal', meeting.reload.status
  end

  test 'customer can request meeting removal with an optional comment' do
    login_as(accounts(:customer_user))
    meeting = meetings(:scheduled_discovery)

    post request_removal_meeting_path(meeting),
         params: { comment: 'The lead changed jobs, so this is no longer relevant.' },
         as: :json

    assert_response :success
    assert_equal 'pending_removal', meeting.reload.status
    assert_equal 'The lead changed jobs, so this is no longer relevant.', meeting.removal_comment
  end

  test 'customer meetings index includes stored removal comment in serialized meeting payload' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(status: 'pending_removal', removal_comment: 'Duplicate meeting for the same lead.')

    get meetings_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    serialized_meeting = body['props']['meetings'].find { |item| item['id'] == meeting.id }

    assert_equal 'Duplicate meeting for the same lead.', serialized_meeting['removal_comment']
  end

  test 'customer cannot request removal for a completed meeting' do
    login_as(accounts(:customer_user))
    meeting = meetings(:completed_demo)

    post request_removal_meeting_path(meeting), headers: { 'Accept' => 'application/json' }

    assert_response :unprocessable_entity
    assert_equal 'completed', meeting.reload.status
  end

  test 'customer can manually reschedule a meeting' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    new_time = 5.days.from_now.change(sec: 0)

    post reschedule_meeting_path(meeting), params: {
      scheduled_at: new_time.iso8601
    }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'rescheduled', body.dig('meeting', 'status')
    assert_in_delta new_time.to_i, meeting.reload.scheduled_at.to_i, 2
  end

  test 'customer can set time for a scheduling meeting without marking it rescheduled' do
    login_as(accounts(:customer_admin))

    meeting = Meeting.create!(
      organization: organizations(:acme),
      agent_lead: agent_leads(:john_in_draft),
      lead: leads(:john_doe),
      agent: agents(:draft_agent),
      status: 'scheduling',
      source: 'manual',
      meeting_type: 'discovery'
    )
    new_time = 3.days.from_now.change(sec: 0)

    post reschedule_meeting_path(meeting), params: {
      scheduled_at: new_time.iso8601
    }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'scheduled', body.dig('meeting', 'status')
    assert_in_delta new_time.to_i, meeting.reload.scheduled_at.to_i, 2
  end

  test 'customer can update meeting time for any status without changing terminal or special status' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    %w[completed positive neutral no_show cancelled pending_removal].each_with_index do |status, index|
      outcome = status.in?(%w[positive neutral no_show]) ? status : nil
      meeting.update!(status: status, outcome: outcome, scheduled_at: (index + 1).days.ago)
      new_time = (index + 2).days.from_now.change(sec: 0)

      post reschedule_meeting_path(meeting), params: {
        scheduled_at: new_time.iso8601
      }, as: :json

      assert_response :success
      assert_equal true, JSON.parse(response.body)['success']
      assert_equal status, meeting.reload.status
      assert_in_delta new_time.to_i, meeting.scheduled_at.to_i, 2
    end
  end

  test 'customer cannot reschedule another organizations meeting' do
    login_as(accounts(:growth_lab_admin))
    meeting = meetings(:scheduled_discovery)

    post reschedule_meeting_path(meeting), params: {
      scheduled_at: 2.days.from_now.iso8601
    }, as: :json

    assert_response :not_found
  end

  test 'customer can update meeting notes' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    patch update_notes_meeting_path(meeting), params: { notes: 'Updated meeting notes' }, as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal true, body['success']
    assert_equal 'Updated meeting notes', body.dig('meeting', 'notes')
    assert_equal 'Updated meeting notes', meeting.reload.notes
  end

  test 'customer cannot update notes for another organizations meeting' do
    login_as(accounts(:growth_lab_admin))
    meeting = meetings(:scheduled_discovery)

    patch update_notes_meeting_path(meeting), params: { notes: 'Unauthorized notes' }, as: :json

    assert_response :not_found
    assert_equal 'Initial discovery call', meeting.reload.notes
  end

  test 'customer can mark a past meeting as positive' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(scheduled_at: 2.hours.ago, outcome: nil)

    post set_outcome_meeting_path(meeting), params: { outcome: 'positive' }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'positive', body.dig('meeting', 'status')
    assert_equal 'positive', body.dig('meeting', 'outcome')
    assert_equal 'positive', meeting.reload.status
    assert_equal 'positive', meeting.outcome
  end

  test 'customer can change an existing meeting outcome' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(status: 'positive', outcome: 'positive', completed_at: 1.hour.ago)

    post set_outcome_meeting_path(meeting), params: { outcome: 'neutral' }, as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal true, body['success']
    assert_equal 'neutral', body.dig('meeting', 'status')
    assert_equal 'neutral', body.dig('meeting', 'outcome')
    assert_equal 'neutral', meeting.reload.status
    assert_equal 'neutral', meeting.outcome
  end

  test 'customer can change outcome for a completed meeting with an outcome' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:completed_demo)

    post set_outcome_meeting_path(meeting), params: { outcome: 'neutral' }, as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal true, body['success']
    assert_equal 'neutral', body.dig('meeting', 'status')
    assert_equal 'neutral', body.dig('meeting', 'outcome')
    assert_equal 'neutral', meeting.reload.status
    assert_equal 'neutral', meeting.outcome
  end

  test 'customer can mark a past meeting as neutral' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(scheduled_at: 2.hours.ago, outcome: nil)

    post set_outcome_meeting_path(meeting), params: { outcome: 'neutral' }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'neutral', body.dig('meeting', 'status')
    assert_equal 'neutral', meeting.reload.status
    assert_equal 'neutral', meeting.outcome
  end

  test 'customer can mark a meeting without time as positive' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(status: 'scheduling', scheduled_at: nil, outcome: nil)

    post set_outcome_meeting_path(meeting), params: { outcome: 'positive' }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'positive', body.dig('meeting', 'status')
    assert_equal 'positive', meeting.reload.status
    assert_equal 'positive', meeting.outcome
  end

  test 'customer can mark a meeting without time as no show' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(status: 'scheduling', scheduled_at: nil, outcome: nil)

    post set_outcome_meeting_path(meeting), params: { outcome: 'no_show' }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'no_show', body.dig('meeting', 'status')
    assert_equal 'no_show', meeting.reload.status
    assert_equal 'no_show', meeting.outcome
  end

  test 'customer cannot mark a future meeting as positive' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    post set_outcome_meeting_path(meeting), params: { outcome: 'positive' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'scheduled', meeting.reload.status
  end

  test 'customer can mark a past meeting as no show' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.update!(scheduled_at: 3.hours.ago)

    post set_outcome_meeting_path(meeting), params: { outcome: 'no_show' }, as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body['success']
    assert_equal 'no_show', body.dig('meeting', 'status')
    assert_equal 'no_show', body.dig('meeting', 'outcome')
    assert_equal 'no_show', meeting.reload.status
    assert_equal 'no_show', meeting.outcome
  end

  test 'customer cannot mark a future meeting as no show' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    post set_outcome_meeting_path(meeting), params: { outcome: 'no_show' }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'scheduled', meeting.reload.status
  end

  test 'customer cannot reschedule a meeting with an invalid time' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    post reschedule_meeting_path(meeting), params: {
      scheduled_at: 'not-a-time'
    }, as: :json

    assert_response :unprocessable_entity
    assert_equal 'scheduled', meeting.reload.status
  end

  test 'customer can fetch lead modal for a blacklisted meeting lead' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)
    meeting.lead.blacklist!(reason: 'Do not contact')

    get lead_modal_meeting_path(meeting), as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal meeting.lead.id, body['id']
    assert_equal meeting.lead.blacklist_reason, body['blacklist_reason']
  end

  test 'customer lead modal includes declined removal comments for the selected meeting' do
    login_as(accounts(:customer_admin))
    meeting = meetings(:scheduled_discovery)

    meeting.meeting_declined_comments.create!(
      account: accounts(:amplifa_admin),
      body: 'Please keep the meeting and continue scheduling with the lead.'
    )

    get lead_modal_meeting_path(meeting), as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 1, body['meeting_declined_comments'].length
    assert_equal 'Please keep the meeting and continue scheduling with the lead.',
                 body.dig('meeting_declined_comments', 0, 'body')
    assert_equal accounts(:amplifa_admin).full_name, body.dig('meeting_declined_comments', 0, 'account', 'full_name')
  end
end
