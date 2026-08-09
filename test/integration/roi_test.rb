require 'test_helper'

class RoiTest < ActionDispatch::IntegrationTest
  test 'agent filter scopes ROI metrics to selected agent' do
    admin = accounts(:customer_admin)
    organization = organizations(:acme)
    mailbox = mailboxes(:acme_mailbox_one)

    agent_a = organization.agents.create!(
      created_by: admin,
      name: 'ROI Agent A',
      status: 'active',
      locale: 'en',
      default_timezone: 'Europe/Berlin',
      contacted_count: 120
    )

    agent_b = organization.agents.create!(
      created_by: admin,
      name: 'ROI Agent B',
      status: 'active',
      locale: 'en',
      default_timezone: 'Europe/Berlin',
      contacted_count: 60
    )

    lead_a = organization.leads.create!(email: 'roi-agent-a@example.com')
    lead_b = organization.leads.create!(email: 'roi-agent-b@example.com')

    agent_lead_a = AgentLead.create!(agent: agent_a, lead: lead_a)
    agent_lead_b = AgentLead.create!(agent: agent_b, lead: lead_b)

    unique_suffix = "#{Time.current.to_i}_#{rand(10_000)}"

    step_one = SequenceStep.create!(
      agent: agent_a,
      position: 1,
      event_type: 'email',
      name: 'Step 1',
      delay_days: 0,
      active: true
    )

    step_two = SequenceStep.create!(
      agent: agent_a,
      position: 2,
      event_type: 'email',
      name: 'Step 2',
      delay_days: 1,
      active: true
    )

    step_b = SequenceStep.create!(
      agent: agent_b,
      position: 1,
      event_type: 'email',
      name: 'Step B1',
      delay_days: 0,
      active: true
    )

    GeneratedMessage.create!(
      agent_lead: agent_lead_a,
      sequence_step: step_one,
      subject: 'First email',
      body: 'Body 1',
      status: 'sent',
      sent_at: 2.days.ago
    )

    GeneratedMessage.create!(
      agent_lead: agent_lead_a,
      sequence_step: step_two,
      subject: 'Second email',
      body: 'Body 2',
      status: 'sent',
      sent_at: 1.day.ago
    )

    GeneratedMessage.create!(
      agent_lead: agent_lead_b,
      sequence_step: step_b,
      subject: 'Agent B email',
      body: 'Body B',
      status: 'sent',
      sent_at: 1.day.ago
    )

    Conversation.create!(
      organization: organization,
      lead: lead_a,
      mailbox: mailbox,
      agent: agent_a,
      status: 'open',
      replies_count: 1,
      unread_count: 0
    )

    Conversation.create!(
      organization: organization,
      lead: lead_b,
      mailbox: mailbox,
      agent: agent_b,
      status: 'open',
      replies_count: 1,
      unread_count: 0
    )

    Meeting.create!(
      organization: organization,
      agent: agent_a,
      agent_lead: agent_lead_a,
      lead: lead_a,
      status: 'completed',
      source: 'manual',
      outcome: 'positive'
    )

    Meeting.create!(
      organization: organization,
      agent: agent_b,
      agent_lead: agent_lead_b,
      lead: lead_b,
      status: 'completed',
      source: 'manual',
      outcome: 'positive'
    )

    login_as(admin)

    get roi_path, headers: inertia_headers
    assert_response :success
    all_props = inertia_props
    all_metrics = all_props['metrics']

    get roi_path, params: { agent_id: agent_a.id }, headers: inertia_headers
    assert_response :success
    filtered_props = inertia_props
    filtered_metrics = filtered_props['metrics']

    assert_equal agent_a.id.to_s, filtered_props['current_agent_id']
    assert_equal 3, all_metrics['emails_sent']
    assert_equal 2, filtered_metrics['emails_sent']
    assert_equal 2, all_metrics['leads_contacted']
    assert_equal 1, filtered_metrics['leads_contacted']
    assert_equal 1, filtered_metrics['emails_replied']
    assert_equal 100.0, filtered_metrics['reply_rate']
    assert_equal 1, filtered_metrics['total_meetings']
    assert_equal 100.0, filtered_metrics['meeting_rate']
  end
end
