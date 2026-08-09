# frozen_string_literal: true

namespace :calendly do
  desc "Show Calendly integration status for all senders"
  task status: :environment do
    puts ""
    puts "=" * 70
    puts "CALENDLY INTEGRATION STATUS"
    puts "=" * 70
    puts ""

    credentials_status = CalendlyCredentials.status
    if credentials_status[:configured]
      puts "OAuth Credentials: ✅ Configured"
    else
      puts "OAuth Credentials: ❌ Not configured"
      puts "  Missing client_id: #{!credentials_status[:has_client_id]}"
      puts "  Missing client_secret: #{!credentials_status[:has_client_secret]}"
      puts ""
      puts "  To configure, add to Rails credentials:"
      puts "    calendly:"
      puts "      client_id: YOUR_CLIENT_ID"
      puts "      client_secret: YOUR_CLIENT_SECRET"
    end
    puts ""

    puts "SENDERS WITH CALENDLY"
    puts "-" * 70

    Sender.includes(:organization, :mailboxes).find_each do |sender|
      status_icon = case sender.calendly_connection_status
                    when "connected" then "🟢"
                    when "error" then "🔴"
                    else "⚪"
                    end

      puts ""
      puts "#{status_icon} #{sender.full_name} (ID: #{sender.id})"
      puts "   Organization: #{sender.organization.name}"
      puts "   Status: #{sender.calendly_connection_status}"
      puts "   Calendly URL: #{sender.calendly_url || 'Not set'}"
      puts "   Mailboxes: #{sender.mailboxes.count}"

      if sender.calendly_connected?
        puts "   Connected at: #{sender.calendly_connected_at}"
        puts "   Token expires: #{sender.calendly_token_expires_at}"
        puts "   Token valid: #{sender.calendly_token_valid? ? 'Yes' : 'No'}"
      end

      if sender.calendly_connection_error.present?
        puts "   Error: #{sender.calendly_connection_error}"
      end
    end

    puts ""
    puts "=" * 70

    meeting_count = Meeting.from_calendly.count
    puts ""
    puts "MEETINGS FROM CALENDLY: #{meeting_count}"
    if meeting_count > 0
      puts "  Attributed: #{Meeting.from_calendly.attributed.count}"
      puts "  Unattributed: #{Meeting.from_calendly.unattributed.count}"
    end
    puts ""
  end

  desc "Set up test data for Calendly integration testing"
  task setup_test_data: :environment do
    puts "Setting up Calendly test data..."
    puts ""

    org = Organization.find_or_create_by!(name: "Amplifa Test") do |o|
      o.website = "https://amplifa.ai"
      o.description = "Test organization for Calendly integration"
    end
    puts "✅ Organization: #{org.name} (ID: #{org.id})"

    sender = Sender.find_or_initialize_by(organization: org, email: "test@amplifa.ai")
    sender.assign_attributes(
      first_name: "Test",
      last_name: "Sender",
      job_title: "Sales Development Representative",
      status: "active",
      signature_template: <<~HTML
        <p style="margin-top: 16px; font-family: Arial, sans-serif; font-size: 14px; color: #333;">
        Best regards,<br>
        <strong>{{full_name}}</strong><br>
        {{job_title}}
        </p>

        <p style="margin-top: 12px; font-family: Arial, sans-serif; font-size: 14px;">
        📅 <a href="{{calendly_url}}" style="color: #0066cc; text-decoration: none;">Book a time to chat</a>
        </p>
      HTML
    )
    sender.save!
    puts "✅ Sender: #{sender.full_name} (ID: #{sender.id})"
    puts "   Signature template: Set with {{calendly_url}} variable"

    email_domain = EmailDomain.find_by(organization: org, provider_type: "google")
    unless email_domain
      existing_domain = EmailDomain.find_by(domain: "getamplifa.com")
      if existing_domain
        puts "⚠️  Using existing domain: #{existing_domain.domain}"
        email_domain = existing_domain
      else
        puts "❌ No Google email domain found. Please create one first via Admin > Email Domains"
        puts "   Skipping mailbox creation..."
      end
    end

    if email_domain
      mailbox = Mailbox.find_or_initialize_by(email_domain: email_domain, email: "test@#{email_domain.domain}")
      if mailbox.new_record?
        mailbox.assign_attributes(
          first_name: "Test",
          last_name: "Sender",
          status: "active",
          daily_send_limit: 50,
          warmup_enabled: false,
          warmup_start_date: 30.days.ago,
          sender: sender
        )
        mailbox.save!
        puts "✅ Mailbox: #{mailbox.email} (ID: #{mailbox.id})"
      else
        mailbox.update!(sender: sender) if mailbox.sender != sender
        puts "✅ Mailbox: #{mailbox.email} (already exists, assigned to sender)"
      end
    end

    playbook = Playbook.find_or_initialize_by(organization: org, name: "Calendly Test Playbook")
    playbook.assign_attributes(
      status: "approved",
      value_proposition: "AI-powered email outreach that books more meetings",
      product: { "name" => "Amplifa", "description" => "AI sales automation platform" },
      personae: [
        { "title" => "Sales Manager", "pain_points" => [ "Low response rates", "Manual follow-ups" ] },
        { "title" => "VP Sales", "pain_points" => [ "Pipeline visibility", "Rep productivity" ] }
      ]
    )
    playbook.save!
    puts "✅ Playbook: #{playbook.name} (ID: #{playbook.id})"

    agent = Agent.find_or_initialize_by(organization: org, name: "Calendly Test Campaign")
    agent.assign_attributes(
      status: "active",
      playbook: playbook,
      locale: "en",
      daily_send_target: 10,
      max_leads_per_day: 5
    )
    agent.save!
    puts "✅ Agent: #{agent.name} (ID: #{agent.id})"

    if mailbox && !agent.mailboxes.include?(mailbox)
      AgentMailbox.find_or_create_by!(agent: agent, mailbox: mailbox)
      puts "   Mailbox assigned to agent"
    end

    sequence_step = SequenceStep.find_or_initialize_by(agent: agent, step_number: 1)
    sequence_step.assign_attributes(
      name: "Initial Outreach",
      delay_days: 0,
      subject_prompt: "Write a compelling subject line for {{first_name}} about improving their sales outreach",
      body_prompt: <<~PROMPT
        Write a personalized cold email to {{first_name}} {{last_name}} at {{company}}.

        They are a {{job_title}}.

        Value proposition: {{playbook.value_proposition}}

        Include a call-to-action with the Calendly link: {{calendly_link}}

        Keep it brief (3-4 sentences max), conversational, and human.
      PROMPT
    )
    sequence_step.save!
    puts "✅ Sequence Step: #{sequence_step.name}"

    puts ""
    puts "Creating 10 test leads (josephflesh+testN@gmail.com)..."
    leads_created = 0
    10.times do |i|
      num = i + 1
      email = "josephflesh+test#{num}@gmail.com"

      lead = Lead.find_or_initialize_by(organization: org, email: email)
      lead.assign_attributes(
        first_name: "Test",
        last_name: "Lead#{num}",
        job_title: [ "Sales Manager", "VP Sales", "Director of Sales", "Account Executive", "SDR Manager" ].sample,
        company: "Test Company #{num}",
        status: "active"
      )
      lead.save!

      agent_lead = AgentLead.find_or_initialize_by(agent: agent, lead: lead)
      if agent_lead.new_record?
        agent_lead.assign_attributes(
          delivery_status: "pending",
          current_step: 0,
          assigned_mailbox: mailbox
        )
        agent_lead.save!
        leads_created += 1
      end
    end
    puts "✅ Created #{leads_created} new AgentLeads (#{10 - leads_created} already existed)"

    puts ""
    puts "=" * 70
    puts "TEST DATA SETUP COMPLETE"
    puts "=" * 70
    puts ""
    puts "Next steps:"
    puts "1. Go to /admin/senders/#{sender.id} and connect Calendly"
    puts "2. Generate sample messages: rails campaign:status[#{agent.id}]"
    puts "3. Review messages at /admin/agents/#{agent.id}/sample_messages"
    puts "4. Set up localhost.run for webhook testing (see below)"
    puts ""
    puts "Webhook testing with localhost.run:"
    puts "  1. Start Rails: mise exec -- rails s"
    puts "  2. Create tunnel: ssh -R 80:localhost:3000 localhost.run"
    puts "  3. Copy the URL (e.g., https://abc123.lhr.life)"
    puts "  4. Book a meeting through the Calendly link"
    puts "  5. Check /admin/meetings for the new meeting"
    puts ""
  end

  desc "Simulate Calendly webhook for testing (invitee.created)"
  task :simulate_booking, [ :sender_id, :agent_lead_id ] => :environment do |_t, args|
    sender_id = args[:sender_id]
    agent_lead_id = args[:agent_lead_id]

    if sender_id.blank?
      puts "Usage: rails calendly:simulate_booking[sender_id,agent_lead_id]"
      puts ""
      puts "Available senders:"
      Sender.includes(:organization).find_each do |s|
        status = s.calendly_connected? ? "🟢 connected" : "⚪ #{s.calendly_connection_status}"
        puts "  [#{s.id}] #{s.full_name} (#{s.organization.name}) - #{status}"
      end
      exit 1
    end

    sender = Sender.find(sender_id)

    unless sender.calendly_connected? || ENV["FORCE"] == "true"
      puts "❌ Sender is not connected to Calendly."
      puts ""
      puts "To simulate anyway (for testing), run with FORCE=true:"
      puts "  FORCE=true rails calendly:simulate_booking[#{sender_id},#{agent_lead_id}]"
      puts ""
      puts "Or mock the connection first:"
      puts "  rails calendly:mock_connection[#{sender_id},https://calendly.com/your-link]"
      exit 1
    end

    agent_lead = nil
    if agent_lead_id.present?
      agent_lead = AgentLead.find(agent_lead_id)
    else
      agent_lead = AgentLead.joins(:agent)
                           .where(agents: { organization_id: sender.organization_id })
                           .order(created_at: :desc)
                           .first

      if agent_lead.nil?
        puts "❌ No AgentLeads found for this organization."
        puts "   Run 'rails calendly:setup_test_data' first."
        exit 1
      end

      puts "Using most recent AgentLead: #{agent_lead.id} (#{agent_lead.lead.email})"
    end

    invitee_email = agent_lead.lead.email
    invitee_name = agent_lead.lead.full_name
    scheduled_at = 1.day.from_now

    payload = {
      event: "invitee.created",
      created_at: Time.current.iso8601,
      created_by: sender.calendly_user_uri || "https://api.calendly.com/users/mock-user",
      payload: {
        event: "https://api.calendly.com/scheduled_events/#{SecureRandom.uuid}",
        invitee: {
          uri: "https://api.calendly.com/scheduled_events/#{SecureRandom.uuid}/invitees/#{SecureRandom.uuid}",
          email: invitee_email,
          name: invitee_name,
          status: "active"
        },
        scheduled_event: {
          uri: "https://api.calendly.com/scheduled_events/#{SecureRandom.uuid}",
          name: "Discovery Call",
          status: "active",
          start_time: scheduled_at.iso8601,
          end_time: (scheduled_at + 30.minutes).iso8601,
          location: {
            type: "zoom",
            join_url: "https://zoom.us/j/1234567890"
          }
        },
        tracking: {
          utm_source: "amplifa",
          utm_medium: "email",
          utm_campaign: agent_lead.agent_id.to_s,
          utm_content: agent_lead.id.to_s
        }
      }
    }

    puts ""
    puts "Simulating Calendly webhook..."
    puts "  Sender: #{sender.full_name}"
    puts "  Invitee: #{invitee_name} (#{invitee_email})"
    puts "  AgentLead ID: #{agent_lead.id}"
    puts "  Scheduled: #{scheduled_at}"
    puts ""

    result = CalendlyWebhookProcessor.process(payload: payload, sender: sender)

    if result.success?
      puts "✅ Webhook processed successfully!"
      puts "   Action: #{result.action}"
      puts "   Data: #{result.data.inspect}"

      if result.data[:meeting_id]
        meeting = Meeting.find(result.data[:meeting_id])
        puts ""
        puts "Meeting created:"
        puts "  ID: #{meeting.id}"
        puts "  Status: #{meeting.status}"
        puts "  Attributed via: #{meeting.attributed_via}"
        puts "  AgentLead: #{meeting.agent_lead_id}"
        puts "  View at: /admin/meetings/#{meeting.id}"
      end
    else
      puts "❌ Webhook processing failed!"
      puts "   Error: #{result.error}"
    end
  end

  desc "Simulate Calendly cancellation webhook"
  task :simulate_cancellation, [ :meeting_id ] => :environment do |_t, args|
    meeting_id = args[:meeting_id]

    if meeting_id.blank?
      puts "Usage: rails calendly:simulate_cancellation[meeting_id]"
      puts ""
      puts "Recent Calendly meetings:"
      Meeting.from_calendly.scheduled.order(created_at: :desc).limit(10).each do |m|
        puts "  [#{m.id}] #{m.lead.full_name} - #{m.scheduled_at.strftime('%Y-%m-%d %H:%M')}"
      end
      exit 1
    end

    meeting = Meeting.find(meeting_id)

    unless meeting.from_calendly?
      puts "❌ Meeting #{meeting_id} is not from Calendly (source: #{meeting.source})"
      exit 1
    end

    sender = meeting.sender
    unless sender
      puts "❌ Meeting has no associated sender"
      exit 1
    end

    payload = {
      event: "invitee.canceled",
      created_at: Time.current.iso8601,
      payload: {
        invitee: {
          uri: meeting.calendly_invitee_uri,
          email: meeting.invitee_email,
          status: "canceled"
        }
      }
    }

    puts "Simulating cancellation webhook for meeting #{meeting_id}..."

    result = CalendlyWebhookProcessor.process(payload: payload, sender: sender)

    if result.success?
      puts "✅ Cancellation processed!"
      puts "   Action: #{result.action}"
      meeting.reload
      puts "   Meeting status: #{meeting.status}"
    else
      puts "❌ Failed: #{result.error}"
    end
  end

  desc "Mock Calendly connection for testing (without OAuth)"
  task :mock_connection, [ :sender_id, :calendly_url ] => :environment do |_t, args|
    sender_id = args[:sender_id]
    calendly_url = args[:calendly_url]

    if sender_id.blank? || calendly_url.blank?
      puts "Usage: rails calendly:mock_connection[sender_id,calendly_url]"
      puts ""
      puts "Example:"
      puts "  rails calendly:mock_connection[1,https://calendly.com/your-name/30min]"
      puts ""
      puts "Available senders:"
      Sender.includes(:organization).find_each do |s|
        puts "  [#{s.id}] #{s.full_name} (#{s.organization.name})"
      end
      exit 1
    end

    sender = Sender.find(sender_id)

    sender.update!(
      calendly_url: calendly_url,
      calendly_connection_status: "connected",
      calendly_connected_at: Time.current,
      calendly_user_uri: "https://api.calendly.com/users/mock-#{sender.id}",
      calendly_organization_uri: "https://api.calendly.com/organizations/mock-#{sender.organization_id}"
    )

    puts "✅ Mocked Calendly connection for #{sender.full_name}"
    puts "   Calendly URL: #{calendly_url}"
    puts "   Status: connected"
    puts ""
    puts "Note: This is a mock connection for testing webhooks locally."
    puts "Real webhooks from Calendly won't work without proper OAuth."
    puts "Use 'rails calendly:simulate_booking' to test webhook processing."
  end

  desc "Test Calendly API connection for a sender"
  task :test_api, [ :sender_id ] => :environment do |_t, args|
    sender_id = args[:sender_id]

    if sender_id.blank?
      puts "Usage: rails calendly:test_api[sender_id]"
      puts ""
      puts "Connected senders:"
      Sender.calendly_connected.includes(:organization).find_each do |s|
        puts "  [#{s.id}] #{s.full_name} (#{s.organization.name})"
      end
      exit 1
    end

    sender = Sender.find(sender_id)

    unless sender.calendly_connected?
      puts "❌ Sender is not connected to Calendly"
      exit 1
    end

    puts "Testing Calendly API connection for #{sender.full_name}..."
    puts ""

    token = CalendlyOauthService.get_valid_token(sender: sender)
    if token.nil?
      puts "❌ Could not get valid token"
      exit 1
    end
    puts "✅ Token is valid"

    result = CalendlyClient.get_current_user(access_token: token)
    if result.success?
      user = result.data[:resource]
      puts "✅ API call successful"
      puts "   Name: #{user[:name]}"
      puts "   Email: #{user[:email]}"
      puts "   Scheduling URL: #{user[:scheduling_url]}"
      puts "   Timezone: #{user[:timezone]}"
    else
      puts "❌ API call failed: #{result.error}"
    end
  end

  desc "List Calendly webhooks for a sender"
  task :list_webhooks, [ :sender_id ] => :environment do |_t, args|
    sender_id = args[:sender_id]

    if sender_id.blank?
      puts "Usage: rails calendly:list_webhooks[sender_id]"
      puts ""
      puts "Connected senders:"
      Sender.calendly_connected.includes(:organization).find_each do |s|
        puts "  [#{s.id}] #{s.full_name} (#{s.organization.name})"
      end
      exit 1
    end

    sender = Sender.find(sender_id)

    unless sender.calendly_connected?
      puts "❌ Sender is not connected to Calendly"
      exit 1
    end

    token = CalendlyOauthService.get_valid_token(sender: sender)
    if token.nil?
      puts "❌ Could not get valid token"
      exit 1
    end

    result = CalendlyClient.list_webhook_subscriptions(
      organization_uri: sender.calendly_organization_uri,
      user_uri: sender.calendly_user_uri,
      access_token: token
    )

    if result.success?
      webhooks = result.data[:collection] || []
      puts ""
      puts "Webhooks for #{sender.full_name}:"
      puts "-" * 60

      if webhooks.empty?
        puts "No webhooks registered"
      else
        webhooks.each do |wh|
          puts ""
          puts "  URI: #{wh[:uri]}"
          puts "  Callback URL: #{wh[:callback_url]}"
          puts "  State: #{wh[:state]}"
          puts "  Events: #{wh[:events]&.join(', ')}"
          puts "  Created: #{wh[:created_at]}"
        end
      end
    else
      puts "❌ Failed to list webhooks: #{result.error}"
    end
  end

  desc "Register webhook with tunnel URL for testing"
  task :setup_tunnel_webhook, [ :sender_id, :tunnel_url ] => :environment do |_t, args|
    sender_id = args[:sender_id]
    tunnel_url = args[:tunnel_url]

    if sender_id.blank? || tunnel_url.blank?
      puts "Usage: rails calendly:setup_tunnel_webhook[sender_id,tunnel_url]"
      puts ""
      puts "Example:"
      puts "  rails calendly:setup_tunnel_webhook[2,https://abc123.lhr.life]"
      puts ""
      puts "Steps:"
      puts "  1. Run: ssh -R 80:localhost:3000 localhost.run"
      puts "  2. Copy the https URL from the output"
      puts "  3. Run this task with that URL"
      puts ""
      puts "Connected senders:"
      Sender.calendly_connected.includes(:organization).find_each do |s|
        puts "  [#{s.id}] #{s.full_name} (#{s.organization.name})"
      end
      exit 1
    end

    sender = Sender.find(sender_id)

    unless sender.calendly_connected?
      puts "❌ Sender is not connected to Calendly"
      exit 1
    end

    token = CalendlyOauthService.get_valid_token(sender: sender)
    if token.nil?
      puts "❌ Could not get valid token"
      exit 1
    end

    webhook_url = "#{tunnel_url.chomp('/')}/webhooks/calendly"
    puts "Setting up webhook..."
    puts "  Sender: #{sender.full_name}"
    puts "  Webhook URL: #{webhook_url}"
    puts ""

    list_result = CalendlyClient.list_webhook_subscriptions(
      organization_uri: sender.calendly_organization_uri,
      user_uri: sender.calendly_user_uri,
      access_token: token
    )

    if list_result.success?
      existing = (list_result.data[:collection] || []).find { |w| w[:callback_url]&.include?("/webhooks/calendly") }
      if existing
        puts "Found existing webhook: #{existing[:callback_url]}"
        puts "Deleting old webhook..."
        CalendlyClient.delete_webhook_subscription(webhook_uri: existing[:uri], access_token: token)
      end
    end

    signing_key = sender.calendly_webhook_signing_key || SecureRandom.hex(32)

    result = CalendlyClient.create_webhook_subscription(
      user_uri: sender.calendly_user_uri,
      organization_uri: sender.calendly_organization_uri,
      webhook_url: webhook_url,
      signing_key: signing_key,
      access_token: token
    )

    if result.success?
      webhook_uri = result.data.dig(:resource, :uri)
      sender.update!(
        calendly_webhook_uri: webhook_uri,
        calendly_webhook_signing_key: signing_key
      )

      puts "✅ Webhook registered successfully!"
      puts "   URI: #{webhook_uri}"
      puts "   Callback: #{webhook_url}"
      puts ""
      puts "Now you can:"
      puts "  1. Keep the localhost.run tunnel running"
      puts "  2. Book a meeting via the Calendly link"
      puts "  3. Watch Rails logs for the webhook"
      puts "  4. Check /admin/meetings for the new meeting"
    else
      puts "❌ Failed to create webhook: #{result.error}"
    end
  end

  desc "Delete all webhooks for a sender"
  task :delete_webhooks, [ :sender_id ] => :environment do |_t, args|
    sender_id = args[:sender_id]

    if sender_id.blank?
      puts "Usage: rails calendly:delete_webhooks[sender_id]"
      exit 1
    end

    sender = Sender.find(sender_id)

    unless sender.calendly_connected?
      puts "❌ Sender is not connected to Calendly"
      exit 1
    end

    token = CalendlyOauthService.get_valid_token(sender: sender)
    if token.nil?
      puts "❌ Could not get valid token"
      exit 1
    end

    result = CalendlyClient.list_webhook_subscriptions(
      organization_uri: sender.calendly_organization_uri,
      user_uri: sender.calendly_user_uri,
      access_token: token
    )

    if result.failure?
      puts "❌ Failed to list webhooks: #{result.error}"
      exit 1
    end

    webhooks = result.data[:collection] || []
    if webhooks.empty?
      puts "No webhooks to delete"
      exit 0
    end

    puts "Deleting #{webhooks.count} webhook(s)..."
    webhooks.each do |wh|
      puts "  Deleting: #{wh[:callback_url]}"
      CalendlyClient.delete_webhook_subscription(webhook_uri: wh[:uri], access_token: token)
    end

    sender.update!(calendly_webhook_uri: nil)
    puts "✅ Done"
  end
end
