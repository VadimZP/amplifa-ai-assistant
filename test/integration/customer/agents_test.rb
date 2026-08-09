# frozen_string_literal: true

require 'test_helper'

class Customer::AgentsTest < ActionDispatch::IntegrationTest
  test 'customer can view lead table index' do
    login_as(accounts(:customer_admin))

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal 'Customer/Agents/Index', body['component']
    assert body['props']['agent_leads'].is_a?(Array)
    assert body['props']['agents'].is_a?(Array)
    assert body['props']['filters'].is_a?(Hash)
    assert body['props']['pagination'].is_a?(Hash)
    assert body['props'].key?('sent_today_count')
  end

  test 'customer can view index page with downloadable agents list' do
    login_as(accounts(:customer_admin))

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    assert_inertia_component('Customer/Agents/Index')

    downloadable_agents = inertia_props['downloadable_agents']
    downloadable_agent_ids = downloadable_agents.map { |agent| agent['id'] }

    assert_includes downloadable_agent_ids, agents(:draft_agent).id
    assert_includes downloadable_agent_ids, agents(:ready_agent).id
    assert_includes downloadable_agent_ids, agents(:active_agent).id
    assert_not_includes downloadable_agent_ids, agents(:other_org_agent).id
  end

  test 'customer can download selected agent leads as csv' do
    login_as(accounts(:customer_admin))

    get download_customer_agents_path(agent_id: agents(:draft_agent).id)

    assert_response :success
    assert_match(%r{text/csv}, response.content_type)
    assert_includes response.headers['Content-Disposition'], 'attachment'

    lines = response.body.split("\n")
    assert_equal ColumnMappingService::MAPPABLE_FIELDS.join(','), lines.first.strip
    assert_includes response.body, 'john.doe@example.com'
    assert_includes response.body, 'jane.smith@testcorp.com'
    assert_no_match(/linkedin_scraped_data|disc_profile|company_website_content/, response.body)
  end

  test "customer cannot download other organization's agent leads" do
    login_as(accounts(:customer_admin))

    get download_customer_agents_path(agent_id: agents(:other_org_agent).id)

    assert_response :not_found
  end

  test 'index only returns organization agent leads' do
    login_as(accounts(:customer_user))

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    lead_rows = body['props']['agent_leads']

    acme_agent_ids = Agent.where(organization: organizations(:acme)).pluck(:id)
    lead_rows.each do |row|
      assert_includes acme_agent_ids, row['agent']['id']
    end
  end

  test 'index filters by agent' do
    login_as(accounts(:customer_admin))
    agent = agents(:draft_agent)

    get customer_agents_path(agent_id: agent.id), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    body['props']['agent_leads'].each do |row|
      assert_equal agent.id, row['agent']['id']
    end

    assert_equal agent.id.to_s, body['props']['filters']['agent_id']
  end

  test 'index filters by delivery status' do
    login_as(accounts(:customer_admin))

    get customer_agents_path(status: 'not_contacted'), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    body['props']['agent_leads'].each do |row|
      assert_equal 'not_contacted', row['delivery_status']
    end
  end

  test 'index keeps status counts stable when filtering by delivery status' do
    login_as(accounts(:customer_admin))

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    all_status_counts = JSON.parse(response.body).dig('props', 'status_counts')

    get customer_agents_path(status: 'not_contacted'), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    body['props']['agent_leads'].each do |row|
      assert_equal 'not_contacted', row['delivery_status']
    end

    assert_equal all_status_counts, body.dig('props', 'status_counts')
  end

  test 'index hides blacklisted leads and excludes them from status counts' do
    login_as(accounts(:customer_admin))
    leads(:john_doe).blacklist!(reason: 'Do not contact')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.none? { |row| row.dig('lead', 'id') == leads(:john_doe).id })
    assert_equal 1, body['props']['status_counts']['not_contacted']
  end

  test 'index shows replied leads blacklisted because of reply interest' do
    login_as(accounts(:customer_admin))

    leads(:john_doe).blacklist!(
      reason: Blacklist.reply_interest_reason('interested'),
      category: Blacklist.reply_interest_reason_category('interested')
    )
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.any? { |row| row.dig('lead', 'id') == leads(:john_doe).id })
    assert_equal 1, body['props']['status_counts']['replied']
  end

  test 'index hides manual blacklist entries even when reason text matches reply interest copy' do
    login_as(accounts(:customer_admin))

    blacklist = Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: leads(:john_doe).email,
      value_type: 'email',
      source: 'manual',
      reason: Blacklist.reply_interest_reason('interested')
    )
    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.none? { |row| row.dig('lead', 'id') == leads(:john_doe).id })
  end

  test 'index shows reply-interest lead when another blacklist rule still applies' do
    login_as(accounts(:customer_admin))

    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'example.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Domain blocked'
    )
    leads(:john_doe).blacklist!(
      reason: Blacklist.reply_interest_reason('interested'),
      category: Blacklist.reply_interest_reason_category('interested')
    )
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.any? { |row| row.dig('lead', 'id') == leads(:john_doe).id })
  end

  test 'index shows wrong person blacklists in replied category' do
    login_as(accounts(:customer_admin))

    leads(:john_doe).blacklist!(
      reason: Blacklist.reply_interest_reason('wrong_person'),
      category: Blacklist.reply_interest_reason_category('wrong_person')
    )
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.any? { |row| row.dig('lead', 'id') == leads(:john_doe).id })
    wrong_person_row = rows.find { |row| row.dig('lead', 'id') == leads(:john_doe).id }
    assert_equal 'reply_wrong_person', wrong_person_row.dig('lead', 'blacklist_reason_category')
  end

  test 'index exposes meeting request interest tag separately from interested' do
    login_as(accounts(:customer_admin))

    lead = leads(:john_doe)
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('meeting_request'),
      category: Blacklist.reply_interest_reason_category('meeting_request')
    )
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    meeting_request_row = rows.find { |row| row.dig('lead', 'id') == lead.id }
    assert_equal 'reply_interested', meeting_request_row.dig('lead', 'blacklist_reason_category')
    assert_equal 'meeting_request', meeting_request_row.dig('lead', 'interest_tag')
  end

  test 'index hides leads matched only by wildcard company website domains' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.update!(email: 'safe@allowed.ch', company_website: 'https://www.kienbaum.de/about')

    blacklist = Blacklist.create!(
      organization: lead.organization,
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard visibility block'
    )
    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    assert(rows.none? { |row| row.dig('lead', 'id') == lead.id })
  end

  test 'index includes playbook approval state for agent controls' do
    login_as(accounts(:customer_admin))

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    agents_payload = body['props']['agents']

    draft_agent_payload = agents_payload.find { |agent| agent['id'] == agents(:draft_agent).id }
    active_agent_payload = agents_payload.find { |agent| agent['id'] == agents(:active_agent).id }

    assert_not_nil draft_agent_payload
    assert_not_nil active_agent_payload
    assert_equal false, draft_agent_payload['playbook_approved']
    assert_equal true, active_agent_payload['playbook_approved']
  end

  test 'index supports search filter' do
    login_as(accounts(:customer_admin))

    get customer_agents_path(search: 'john'), headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)

    body['props']['agent_leads'].each do |row|
      haystack = [
        row.dig('lead', 'email'),
        row.dig('lead', 'display_name'),
        row.dig('lead', 'company')
      ].compact.join(' ').downcase

      assert haystack.include?('john')
    end
  end

  test 'index sorts all statuses with in sequence first' do
    login_as(accounts(:customer_admin))

    in_sequence_lead = agent_leads(:john_in_draft)
    other_status_lead = agent_leads(:jane_in_draft)

    in_sequence_lead.update!(delivery_status: 'in_sequence', created_at: 3.days.ago)
    other_status_lead.update!(delivery_status: 'not_contacted', created_at: Time.current)

    get customer_agents_path, headers: inertia_headers

    assert_response :success
    body = JSON.parse(response.body)
    rows = body['props']['agent_leads']

    in_sequence_index = rows.index { |row| row['id'] == in_sequence_lead.id }
    other_status_index = rows.index { |row| row['id'] == other_status_lead.id }

    assert_not_nil in_sequence_index
    assert_not_nil other_status_index
    assert_operator in_sequence_index, :<, other_status_index
  end

  test 'customer can fetch lead modal payload' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    conversations(:acme_john_conversation).update!(interest_status: 'wrong_person')

    get customer_lead_modal_path(lead), as: :json

    assert_response :success
    body = JSON.parse(response.body)

    assert_equal lead.id, body['id']
    assert body['agent_leads'].is_a?(Array)
    assert body['conversations'].is_a?(Array)
    assert_equal lead.disc_profile, body['disc_profile']
    assert_equal lead.linkedin_headline, body['linkedin_headline']
    assert_equal lead.linkedin_summary, body['linkedin_summary']
    assert_equal lead.company_website_content.truncate(3000), body['company_website_content']
    assert body.key?('linkedin_profile_photo_url')
    assert body.key?('linkedin_posts')
    assert body.key?('linkedin_scraped_at')
    assert body.key?('linkedin_posts_scraped_at')
    assert body.key?('company_website_scraped_at')
    assert body.key?('disc_profile_assessed_at')
    assert body.key?('blacklist_reason')
    assert body['linkedin_posts'].is_a?(Array) || body['linkedin_posts'].nil?
    assert body['custom_fields'].is_a?(Hash) || body['custom_fields'].nil?
    assert_equal lead.blacklisted, body['blacklisted'] if body.key?('blacklisted')

    if body['conversations'].any?
      assert body['conversations'].first['thread'].is_a?(Array)
      assert body['conversations'].first.key?('interest_status')
      assert_equal 'wrong_person', body['conversations'].first['interest_status']
    end
  end

  test 'customer can manually set lead meeting request from agents workflow and store manual blacklist reason' do
    login_as(accounts(:customer_admin))

    conversation = conversations(:acme_john_conversation)
    conversation.update!(interest_status: nil)
    lead = conversation.lead
    lead.unblacklist!
    Blacklist.where(organization: lead.organization, value: lead.email, value_type: 'email').delete_all

    agent_lead = agent_leads(:john_in_draft)
    agent_lead.meetings.where.not(status: 'cancelled').destroy_all
    agent_lead.update!(meeting_booked_at: nil, meeting_notes: nil)

    assert_difference 'Meeting.count', 1 do
      post update_interest_status_reply_path(conversation),
           params: { interest_status: 'meeting_request', reason_context: 'manual' },
           headers: { 'Accept' => 'application/json' }
    end

    assert_response :success
    assert_equal 'meeting_request', conversation.reload.interest_status

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Auto-blacklisted from manually set interest tag: Meeting request', lead.blacklist_reason

    blacklist_entry = Blacklist.find_by!(organization: lead.organization, value: lead.email, value_type: 'email')
    assert_equal 'interested', blacklist_entry.source
    assert_equal 'Auto-blacklisted from manually set interest tag: Meeting request', blacklist_entry.reason
    assert_equal 'reply_interested', blacklist_entry.reason_category
  end

  test 'customer can manually set lead meeting request from agents workflow without a human reply in the thread' do
    login_as(accounts(:customer_admin))

    lead = leads(:john_doe)
    conversation = Conversation.create!(
      organization: organizations(:acme),
      lead: lead,
      mailbox: mailboxes(:acme_mailbox_two),
      agent: agents(:draft_agent),
      status: 'open',
      replies_count: 0,
      unread_count: 0,
      last_reply_at: nil,
      last_reply_preview: nil
    )

    lead.unblacklist!
    Blacklist.where(organization: lead.organization, value: lead.email, value_type: 'email').delete_all

    agent_lead = agent_leads(:john_in_draft)
    agent_lead.meetings.where.not(status: 'cancelled').destroy_all
    agent_lead.update!(meeting_booked_at: nil, meeting_notes: nil)

    get customer_lead_modal_path(lead), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    modal_conversation = body.fetch('conversations').find { |entry| entry['id'] == conversation.id }

    assert_not_nil modal_conversation
    assert_equal [], modal_conversation['thread']
    assert_nil modal_conversation['interest_status']

    assert_difference 'Meeting.count', 1 do
      post update_interest_status_reply_path(conversation),
           params: { interest_status: 'meeting_request', reason_context: 'manual' },
           headers: { 'Accept' => 'application/json' }
    end

    assert_response :success
    assert_equal 'meeting_request', conversation.reload.interest_status

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Auto-blacklisted from manually set interest tag: Meeting request', lead.blacklist_reason

    blacklist_entry = Blacklist.find_by!(organization: lead.organization, value: lead.email, value_type: 'email')
    assert_equal 'interested', blacklist_entry.source
    assert_equal 'Auto-blacklisted from manually set interest tag: Meeting request', blacklist_entry.reason
    assert_equal 'reply_interested', blacklist_entry.reason_category
  end

  test 'customer can manually set lead meeting request from agents workflow without an existing conversation' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "noconversation-#{SecureRandom.hex(4)}@example.com",
      first_name: 'No',
      last_name: 'Conversation',
      full_name: 'No Conversation'
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )

    get customer_lead_modal_path(lead), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body['conversations']
    assert_equal mailboxes(:acme_mailbox_two).id, body.dig('agent_leads', 0, 'assigned_mailbox', 'id')

    assert_difference 'Conversation.count', 1 do
      assert_difference 'Meeting.count', 1 do
        post customer_lead_update_interest_status_path(lead),
             params: { interest_status: 'meeting_request', agent_lead_id: agent_lead.id },
             headers: { 'Accept' => 'application/json' }
      end
    end

    assert_response :success
    response_body = JSON.parse(response.body)
    conversation = Conversation.find(response_body['conversation_id'])

    assert_equal lead.id, conversation.lead_id
    assert_equal mailboxes(:acme_mailbox_two).id, conversation.mailbox_id
    assert_equal agents(:draft_agent).id, conversation.agent_id
    assert_equal 'meeting_request', conversation.interest_status

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Auto-blacklisted from manually set interest tag: Meeting request', lead.blacklist_reason
  end

  test 'customer agents manual interest update rejects mismatched campaign conversation context' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "campaign-mismatch-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Campaign',
      last_name: 'Mismatch',
      full_name: 'Campaign Mismatch'
    )
    first_agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_one),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    second_agent_lead = AgentLead.create!(
      agent: agents(:ready_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    wrong_conversation = Conversation.create!(
      organization: organizations(:acme),
      lead: lead,
      mailbox: mailboxes(:acme_mailbox_one),
      agent: agents(:draft_agent),
      status: 'open',
      replies_count: 0,
      unread_count: 0,
      last_reply_at: nil,
      last_reply_preview: nil
    )

    assert_no_difference 'Conversation.count' do
      post customer_lead_update_interest_status_path(lead),
           params: {
             interest_status: 'interested',
             agent_lead_id: second_agent_lead.id,
             conversation_id: wrong_conversation.id
           },
           headers: { 'Accept' => 'application/json' }
    end

    assert_response :unprocessable_entity
    body = JSON.parse(response.body)
    assert_equal 'Selected campaign does not match the existing conversation mailbox.', body['error']
    assert_nil wrong_conversation.reload.interest_status
    assert_nil first_agent_lead.reload.meeting_booked_at
    assert_nil second_agent_lead.reload.meeting_booked_at
  end

  test 'customer can open reply conversation from agents modal and create missing conversation without blacklisting lead' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "reply-open-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Reply',
      last_name: 'Open',
      full_name: 'Reply Open'
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )

    assert_difference 'Conversation.count', 1 do
      post customer_lead_open_reply_conversation_path(lead),
           params: { agent_lead_id: agent_lead.id },
           headers: { 'Accept' => 'application/json' }
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    conversation = Conversation.find(response_body['conversation_id'])

    assert_equal lead.id, conversation.lead_id
    assert_equal mailboxes(:acme_mailbox_two).id, conversation.mailbox_id
    assert_equal agents(:draft_agent).id, conversation.agent_id
    assert_equal replies_path(selected_id: conversation.id, compose: 1), response_body['redirect_url']
    assert_not lead.reload.blacklisted?
  end

  test 'customer open reply conversation inherits lead interest tag when target conversation is unset' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "reply-inherit-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Reply',
      last_name: 'Inherit',
      full_name: 'Reply Inherit'
    )
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('interested', manual: true),
      category: Blacklist.reply_interest_reason_category('interested')
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    conversation = Conversation.create!(
      organization: organizations(:acme),
      lead: lead,
      mailbox: mailboxes(:acme_mailbox_two),
      agent: agents(:draft_agent),
      status: 'open'
    )

    assert_nil conversation.interest_status

    post customer_lead_open_reply_conversation_path(lead),
         params: { agent_lead_id: agent_lead.id },
         headers: { 'Accept' => 'application/json' }

    assert_response :success
    response_body = JSON.parse(response.body)

    assert_equal conversation.id, response_body['conversation_id']
    assert_equal 'interested', conversation.reload.interest_status
  end

  test 'customer open reply conversation does not overwrite explicit conversation interest status' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "reply-preserve-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Reply',
      last_name: 'Preserve',
      full_name: 'Reply Preserve'
    )
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('interested', manual: true),
      category: Blacklist.reply_interest_reason_category('interested')
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    conversation = Conversation.create!(
      organization: organizations(:acme),
      lead: lead,
      mailbox: mailboxes(:acme_mailbox_two),
      agent: agents(:draft_agent),
      status: 'open',
      interest_status: 'wrong_person'
    )

    post customer_lead_open_reply_conversation_path(lead),
         params: { agent_lead_id: agent_lead.id },
         headers: { 'Accept' => 'application/json' }

    assert_response :success
    assert_equal 'wrong_person', conversation.reload.interest_status
  end

  test 'customer open reply conversation includes return_to agents modal url when provided' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "reply-return-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Reply',
      last_name: 'Return',
      full_name: 'Reply Return'
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    return_to = "/agents?lead_id=#{lead.id}&agent_lead_id=#{agent_lead.id}"

    post customer_lead_open_reply_conversation_path(lead),
         params: { agent_lead_id: agent_lead.id, return_to: return_to },
         headers: { 'Accept' => 'application/json' }

    assert_response :success

    response_body = JSON.parse(response.body)
    conversation = Conversation.find(response_body['conversation_id'])
    assert_equal replies_path(selected_id: conversation.id, compose: 1, return_to: return_to), response_body['redirect_url']
  end

  test 'customer can open existing reply conversation after lead restart cleared campaign mailbox' do
    login_as(accounts(:customer_admin))

    lead = Lead.create!(
      organization: organizations(:acme),
      email: "reply-restarted-#{SecureRandom.hex(4)}@example.com",
      first_name: 'Reply',
      last_name: 'Restarted',
      full_name: 'Reply Restarted'
    )
    agent_lead = AgentLead.create!(
      agent: agents(:draft_agent),
      lead: lead,
      assigned_mailbox: mailboxes(:acme_mailbox_two),
      status: 'pending',
      delivery_status: 'not_contacted',
      sequence_position: 0
    )
    conversation = Conversation.create!(
      organization: organizations(:acme),
      lead: lead,
      mailbox: mailboxes(:acme_mailbox_one),
      agent: agents(:draft_agent),
      status: 'open'
    )

    post customer_lead_open_reply_conversation_path(lead),
         params: { agent_lead_id: agent_lead.id, conversation_id: conversation.id },
         headers: { 'Accept' => 'application/json' }

    assert_response :success
    response_body = JSON.parse(response.body)
    assert_equal conversation.id, response_body['conversation_id']
    assert_equal replies_path(selected_id: conversation.id, compose: 1), response_body['redirect_url']
  end

  test 'customer user can manually set lead not interested and request meeting removal with manual blacklist reason' do
    login_as(accounts(:customer_user))

    conversation = conversations(:acme_john_conversation)
    conversation.update!(interest_status: 'interested')
    lead = conversation.lead
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('interested', manual: true),
      category: Blacklist.reply_interest_reason_category('interested')
    )
    Blacklist.upsert_reply_interest_entry!(
      lead: lead,
      interest_status: 'interested',
      actor: accounts(:customer_user),
      reason: Blacklist.reply_interest_reason('interested', manual: true)
    )

    agent_lead = agent_leads(:john_in_draft)
    meeting = agent_lead.meetings.where.not(status: 'cancelled').order(created_at: :desc).first
    assert_not_nil meeting

    assert_no_difference 'Meeting.count' do
      post update_interest_status_reply_path(conversation),
           params: { interest_status: 'not_interested', reason_context: 'manual' },
           headers: { 'Accept' => 'application/json' }
    end

    assert_response :success
    assert_equal 'not_interested', conversation.reload.interest_status
    assert_equal 'pending_removal', meeting.reload.status

    lead.reload
    assert lead.blacklisted?
    assert_equal 'Auto-blacklisted from manually set interest tag: Not interested', lead.blacklist_reason

    blacklist_entry = Blacklist.find_by!(organization: lead.organization, value: lead.email, value_type: 'email')
    assert_equal 'unsubscribe', blacklist_entry.source
    assert_equal 'Auto-blacklisted from manually set interest tag: Not interested', blacklist_entry.reason
    assert_equal 'reply_not_interested', blacklist_entry.reason_category
  end

  test 'customer cannot fetch modal for blacklisted lead' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.blacklist!(reason: 'Do not contact')

    get customer_lead_modal_path(lead), as: :json

    assert_response :not_found
  end

  test 'customer can fetch modal for lead blacklisted because of reply interest category' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.blacklist!(
      reason: Blacklist.reply_interest_reason('not_interested'),
      category: Blacklist.reply_interest_reason_category('not_interested')
    )
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get customer_lead_modal_path(lead), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal lead.id, body['id']
  end

  test 'customer cannot fetch modal for lead matched only by wildcard company website domain' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.update!(email: 'safe@allowed.ch', company_website: 'https://www.kienbaum.de/about')

    blacklist = Blacklist.create!(
      organization: lead.organization,
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard modal block'
    )
    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    get customer_lead_modal_path(lead), as: :json

    assert_response :not_found
  end

  test 'lead modal payload includes html body when plain reply body is missing' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    reply = replies(:john_doe_reply)

    reply.update!(body_plain: nil, body_html: '<p>Hello from <strong>HTML</strong> body.</p>')

    get customer_lead_modal_path(lead), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    thread = body.fetch('conversations').flat_map { |conversation| conversation.fetch('thread') }
    reply_message = thread.find { |message| message['source'] == 'reply' && message['id'] == reply.id }

    assert_not_nil reply_message
    assert_nil reply_message['body_plain']
    assert_match(/Hello from/, reply_message['body_html'])
  end

  test 'customer cannot fetch modal for other organization lead' do
    login_as(accounts(:customer_user))

    get customer_lead_modal_path(leads(:growth_lab_lead)), as: :json

    assert_response :not_found
  end

  test 'customer agent show hides blacklisted leads' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.blacklist!(reason: 'Do not contact')

    get customer_agent_path(agents(:active_agent)), headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Agents/Show'
    assert_equal [], inertia_props['leads']
    assert_equal 0, inertia_props.dig('leads_pagination', 'total_count')
  end

  test 'customer agent show includes leads blacklisted because of reply interest' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.blacklist!(reason: Blacklist.reply_interest_reason('interested'))
    conversations(:acme_john_conversation).update!(interest_status: 'interested')
    agent_leads(:john_in_ready).update!(delivery_status: 'replied')

    get customer_agent_path(agents(:ready_agent)), headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Agents/Show'
    assert_equal([lead.id], inertia_props['leads'].map { |entry| entry['id'] })
    assert_equal 1, inertia_props.dig('leads_pagination', 'total_count')
  end

  test 'customer csv download excludes manual blacklists but includes reply-interest blacklists' do
    login_as(accounts(:customer_admin))

    leads(:john_doe).blacklist!(reason: 'Do not contact')
    leads(:jane_smith).blacklist!(reason: Blacklist.reply_interest_reason('not_interested'))
    conversations(:acme_jane_conversation).update!(interest_status: 'not_interested')
    agent_leads(:jane_in_draft).update!(delivery_status: 'replied')

    get download_customer_agents_path(agent_id: agents(:draft_agent).id)

    assert_response :success
    assert_match(%r{text/csv}, response.content_type)
    assert_not_includes response.body, 'john.doe@example.com'
    assert_includes response.body, 'jane.smith@testcorp.com'
  end

  test 'customer csv download includes reply-interest leads with another blacklist rule' do
    login_as(accounts(:customer_admin))

    Blacklist.create!(
      organization: organizations(:acme),
      created_by: accounts(:customer_admin),
      value: 'example.com',
      value_type: 'domain',
      source: 'manual',
      reason: 'Domain blocked'
    )
    leads(:john_doe).blacklist!(reason: Blacklist.reply_interest_reason('interested'))
    conversations(:acme_john_conversation).update!(interest_status: 'interested')
    agent_leads(:john_in_draft).update!(delivery_status: 'replied')

    get download_customer_agents_path(agent_id: agents(:draft_agent).id)

    assert_response :success
    assert_includes response.body, 'john.doe@example.com'
  end

  test 'customer agent show hides leads matched only by wildcard company website domains' do
    login_as(accounts(:customer_admin))
    lead = leads(:john_doe)
    lead.update!(email: 'safe@allowed.ch', company_website: 'https://www.kienbaum.de/about')

    blacklist = Blacklist.create!(
      organization: lead.organization,
      created_by: accounts(:customer_admin),
      value: 'kienbaum.*',
      value_type: 'domain',
      source: 'manual',
      reason: 'Wildcard show block'
    )
    BackfillBlacklistedLeadsJob.perform_now(blacklist.id)

    get customer_agent_path(agents(:active_agent)), headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Agents/Show'
    assert_equal [], inertia_props['leads']
    assert_equal 0, inertia_props.dig('leads_pagination', 'total_count')
  end

  test 'customer can open active agent after assigned playbook is deleted' do
    account = accounts(:customer_admin)
    login_as(account)

    playbook = Playbook.create!(
      organization: organizations(:acme),
      product: { name: 'Disposable customer playbook', description: 'For customer show', metadata: {} },
      status: 'approved',
      language: 'en',
      value_proposition: 'Disposable customer playbook',
      personae: [{ 'id' => SecureRandom.uuid, 'name' => 'Persona', 'title' => 'VP Sales', 'order' => 1 }],
      use_cases: [{ 'id' => SecureRandom.uuid, 'title' => 'Use case', 'description' => 'Desc', 'order' => 1 }],
      references: [],
      proof_points: [],
      approved_at: Time.current,
      approved_by: account
    )
    agent = Agent.create!(
      organization: organizations(:acme),
      playbook: playbook,
      created_by: account,
      name: 'Customer-visible active agent',
      description: 'Still visible after deletion',
      status: 'active',
      launched_at: 2.days.ago,
      locale: 'en',
      default_timezone: 'Europe/Berlin'
    )

    playbook.destroy!

    get customer_agent_path(agent), headers: inertia_headers

    assert_response :success
    assert_inertia_component 'Customer/Agents/Show'
    assert_nil inertia_props.dig('agent', 'playbook')
  end

  test 'customer can pause selected active agent' do
    login_as(accounts(:customer_admin))
    agent = agents(:active_agent)
    agent.update!(launched_at: 2.days.ago, paused_at: nil, status: 'active')

    post pause_campaign_customer_agent_path(agent), headers: inertia_headers

    assert_response :redirect
    assert_redirected_to customer_agents_path(agent_id: agent.id)
    agent.reload
    assert_equal 'paused', agent.status
    assert_not_nil agent.paused_at
  end

  test 'customer can resume selected paused agent' do
    login_as(accounts(:customer_admin))
    agent = agents(:active_agent)
    agent.update!(launched_at: 2.days.ago, paused_at: 1.hour.ago, status: 'paused')

    post resume_campaign_customer_agent_path(agent), headers: inertia_headers

    assert_response :redirect
    assert_redirected_to customer_agents_path(agent_id: agent.id)
    agent.reload
    assert_equal 'active', agent.status
    assert_nil agent.paused_at
  end

  test 'pause campaign keeps status when agent cannot be paused' do
    login_as(accounts(:customer_admin))
    agent = agents(:active_agent)
    agent.update!(launched_at: nil, paused_at: nil, status: 'active')

    post pause_campaign_customer_agent_path(agent), headers: inertia_headers

    assert_response :redirect
    agent.reload
    assert_equal 'active', agent.status
  end

  test 'customer user cannot pause selected active agent' do
    login_as(accounts(:customer_user))
    agent = agents(:active_agent)
    agent.update!(launched_at: 2.days.ago, paused_at: nil, status: 'active')

    post pause_campaign_customer_agent_path(agent), headers: inertia_headers

    assert_response :redirect
    assert_equal 'You are not authorized to perform this action.', flash[:alert]

    agent.reload
    assert_equal 'active', agent.status
    assert_nil agent.paused_at
  end

  test 'customer user cannot resume selected paused agent' do
    login_as(accounts(:customer_user))
    agent = agents(:active_agent)
    agent.update!(launched_at: 2.days.ago, paused_at: 1.hour.ago, status: 'paused')

    post resume_campaign_customer_agent_path(agent), headers: inertia_headers

    assert_response :redirect
    assert_equal 'You are not authorized to perform this action.', flash[:alert]

    agent.reload
    assert_equal 'paused', agent.status
    assert_not_nil agent.paused_at
  end

  test "customer cannot pause other organization's agent" do
    login_as(accounts(:customer_admin))
    other_agent = agents(:other_org_agent)

    post pause_campaign_customer_agent_path(other_agent), headers: inertia_headers

    assert_response :not_found
  end

  # ──────────────────────────────────────────────────────────────────────────
  # AMP-435 §8: the campaign-controls UI must key off the CURRENT-WORKSPACE
  # membership role. The index emits can_manage_campaigns from the current
  # membership so the pause/resume controls mirror server AgentPolicy
  # enforcement instead of the legacy global account.role.
  # ──────────────────────────────────────────────────────────────────────────
  test 'index gates can_manage_campaigns by current-workspace membership role' do
    scenario = build_multi_org_scenario
    scenario.org_a.update!(onboarded: true)
    scenario.org_b.update!(onboarded: true)

    login_as(scenario.account)

    post workspace_switch_path, params: { organization_id: scenario.org_b.id }

    get customer_agents_path, headers: inertia_headers
    assert_response :success
    assert_inertia_component 'Customer/Agents/Index'
    assert_equal false, inertia_props['can_manage_campaigns'],
                 'customer_user in the current workspace must NOT manage campaigns'

    post workspace_switch_path, params: { organization_id: scenario.org_a.id }

    get customer_agents_path, headers: inertia_headers
    assert_response :success
    assert_equal true, inertia_props['can_manage_campaigns'],
                 'customer_admin in the current workspace must manage campaigns'
  end
end
