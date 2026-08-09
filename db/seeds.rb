# frozen_string_literal: true

# db/seeds.rb
#
# Deterministic, idempotent two-org sample data for local development and QA.
#
# Design goals:
#   - Deterministic: handcrafted identity data (no Faker), stable across runs.
#   - Idempotent: destroys previously seeded rows in FK-safe order, then re-inserts.
#   - FK-complete: every association resolves.
#   - Key-less: boots and seeds with no API key set (no external calls).
#
# All foreign keys in this schema are ON DELETE RESTRICT, so cleanup order is
# significant. agent_leads <-> agent_lead_runs form a reference cycle (the
# after_create hook on AgentLead builds an AgentLeadRun and points
# current_agent_lead_run_id back at it), so that cycle is broken before delete.

SEED_PASSWORD = "password123!"
make_password = -> { BCrypt::Password.create(SEED_PASSWORD, cost: BCrypt::Engine::MIN_COST) }

# ---------------------------------------------------------------------------
# Step 0: Cleanup (delete in FK-safe order).
# ---------------------------------------------------------------------------
ConversationRead.delete_all
SentReplyAttachment.delete_all
SentReply.delete_all
ReplyAttachment.delete_all
Reply.delete_all
GeneratedMessage.delete_all
Meeting.delete_all
Conversation.delete_all
AgentLead.update_all(current_agent_lead_run_id: nil) # break agent_leads <-> agent_lead_runs cycle
AgentLeadRun.delete_all
AgentLead.delete_all
AgentMailbox.delete_all
Lead.delete_all           # leads reference lead_imports and people, so delete leads first
LeadImport.delete_all
PersonEmailAlias.delete_all
Person.delete_all
Company.delete_all
Blacklist.delete_all
SequenceStep.delete_all   # sequence_steps reference agents and global_sequences
Agent.delete_all
GlobalSequence.delete_all
Playbook.delete_all
Mailbox.delete_all
Sender.delete_all
EmailDomain.delete_all
OrganizationMembership.delete_all
Invitation.delete_all
AdminActivity.delete_all
EmailTwoFactorChallenge.delete_all
McpOauthRefreshToken.delete_all
%w[account_login_change_keys account_password_reset_keys account_remember_keys account_verification_keys].each do |table|
  ActiveRecord::Base.connection.execute("DELETE FROM #{ActiveRecord::Base.connection.quote_table_name(table)}")
end
Account.delete_all
Organization.delete_all
# NOTE: Model rows (LLM registry) are intentionally preserved.

# ---------------------------------------------------------------------------
# Step 1: LLM model registry (guarded; requires no API key).
# ---------------------------------------------------------------------------
begin
  if defined?(RubyLlmRegistrySeed)
    RubyLlmRegistrySeed.call(
      models: [],
      openrouter_api_key: ENV["OPENROUTER_API_KEY"].presence ||
                          Rails.application.credentials.dig(:openrouter, :api_key),
      rails_env: Rails.env,
      logger: Rails.logger
    )
  end
rescue StandardError => e
  puts "LLM registry seed skipped: #{e.message}"
end

# Ensure at least one Model row exists so Chat can associate without an API key.
begin
  Model.find_or_create_by!(provider: "openrouter", model_id: "deepseek/deepseek-chat") do |m|
    m.name = "DeepSeek Chat"
    m.context_window = 65_536
    m.capabilities = %w[function_calling]
    m.modalities = { "input" => %w[text], "output" => %w[text] }
    m.pricing = { "text_tokens" => { "standard" => { "input_per_million" => 0.14, "output_per_million" => 0.28 } } }
  end
rescue StandardError => e
  puts "Model registry row skipped: #{e.message}"
end

# ---------------------------------------------------------------------------
# Step 2: Amplifa admin
# ---------------------------------------------------------------------------
admin = Account.create!(
  email: "admin@amplifa.com",
  first_name: "Admin",
  last_name: "User",
  role: "amplifa_admin",
  status: "verified"
)
admin.update!(password_hash: make_password.call)

# ---------------------------------------------------------------------------
# Step 3: Primary org - "Northwind Robotics"
# ---------------------------------------------------------------------------
primary_org = Organization.create!(
  name: "Northwind Robotics",
  industry: "Technology",
  size: "51-200",
  onboarded: true,
  average_contract_value: 45_000
)

nina = Account.create!(
  email: "nina@northwind-robotics.example",
  first_name: "Nina",
  last_name: "Chen",
  organization: primary_org,
  role: "customer_admin",
  status: "verified"
)
nina.update!(password_hash: make_password.call)

noah = Account.create!(
  email: "noah@northwind-robotics.example",
  first_name: "Noah",
  last_name: "Patel",
  organization: primary_org,
  role: "customer_user",
  status: "verified"
)
noah.update!(password_hash: make_password.call)

# ---------------------------------------------------------------------------
# Step 4: Decoy org - "Sunrise Analytics"
# ---------------------------------------------------------------------------
decoy_org = Organization.create!(
  name: "Sunrise Analytics",
  industry: "Finance",
  size: "11-50",
  onboarded: true,
  average_contract_value: 12_000
)

sam = Account.create!(
  email: "sam@sunrise-analytics.example",
  first_name: "Sam",
  last_name: "Rivera",
  organization: decoy_org,
  role: "customer_admin",
  status: "verified"
)
sam.update!(password_hash: make_password.call)

# ---------------------------------------------------------------------------
# Step 5: Dual-membership user
# ---------------------------------------------------------------------------
dana = Account.create!(
  email: "dana@consultants.example",
  first_name: "Dana",
  last_name: "Kim",
  organization: primary_org,
  role: "customer_user",
  status: "verified"
)
dana.update!(password_hash: make_password.call)
# Primary-org membership is auto-created by Account#ensure_primary_organization_membership.
OrganizationMembership.create!(
  account: dana,
  organization: decoy_org,
  role: "customer_user",
  status: "active"
)

# ---------------------------------------------------------------------------
# Step 6: Primary org infrastructure (data-only, no sending behavior)
# ---------------------------------------------------------------------------
domain = EmailDomain.create!(
  organization: primary_org,
  domain: "northwind-robotics.example",
  provider_type: "google",
  status: "active"
)

sender1 = Sender.create!(
  organization: primary_org,
  first_name: "Alex",
  last_name: "Morgan",
  email: "alex@northwind-robotics.example",
  job_title: "Account Executive"
)
sender2 = Sender.create!(
  organization: primary_org,
  first_name: "Jordan",
  last_name: "Lee",
  email: "jordan@northwind-robotics.example",
  job_title: "Sales Development Rep"
)

mailbox1 = Mailbox.create!(
  organization: primary_org,
  email_domain: domain,
  sender: sender1,
  email: "alex@northwind-robotics.example",
  status: "active",
  daily_send_limit: 50
)
# 'warming' is not a valid Mailbox status; a recent warmup_started_at models the warming state.
mailbox2 = Mailbox.create!(
  organization: primary_org,
  email_domain: domain,
  sender: sender2,
  email: "jordan@northwind-robotics.example",
  status: "active",
  daily_send_limit: 20,
  warmup_started_at: 5.days.ago
)

# ---------------------------------------------------------------------------
# Step 7: Playbooks (1 approved + 1 draft)
# JSONB collections use string keys because the structural validations read
# string keys on the in-memory record before it is persisted.
# ---------------------------------------------------------------------------
approved_playbook = Playbook.create!(
  organization: primary_org,
  status: "approved",
  approved_at: Time.current,
  approved_by: nina,
  language: "en",
  value_proposition: "Northwind Robotics turns visual inspection from a sampling exercise into a measurable, " \
                     "always-on quality process. VisionQC combines edge cameras, explainable defect detection, " \
                     "and production analytics so manufacturers can catch defects at line speed, trace recurring " \
                     "causes, and launch new inspection stations without building an internal computer-vision team. " \
                     "A typical pilot starts on one high-cost defect family, proves accuracy against a labeled golden " \
                     "set, and then scales across lines and plants.",
  product: {
    "name" => "VisionQC Platform",
    "description" => "An industrial visual-inspection platform combining edge inference, configurable quality " \
                     "workflows, evidence capture, and plant-level analytics. It supports reflective surfaces, " \
                     "high-speed lines, and regulated traceability requirements without sending production images " \
                     "outside the customer's environment.",
    "metadata" => {
      "category" => "Industrial AI",
      "deployment" => "Edge, on-premise, or private cloud",
      "ideal_customer" => "Multi-line manufacturers with costly defects or manual inspection bottlenecks",
      "implementation" => "Four-week pilot followed by phased line rollout"
    }
  },
  personae: [
    {
      "id" => "persona-1", "name" => "Operations Leader Olivia", "title" => "VP Operations / COO", "order" => 1,
      "pain_points" => [
        "Defects are discovered after value has already been added or the product has shipped",
        "Inspection staffing does not scale with new lines, SKUs, and shift patterns",
        "Plant reports show symptoms but not the recurring process conditions behind them",
        "Automation projects compete for capital and need a short, defensible payback period"
      ],
      "goals" => ["Increase first-pass yield", "Reduce cost of poor quality", "Standardize performance across plants"]
    },
    {
      "id" => "persona-2", "name" => "Quality Leader Quinn", "title" => "Quality Director / Head of QA", "order" => 2,
      "pain_points" => [
        "Different inspectors apply defect standards inconsistently across shifts",
        "Root-cause investigations begin with incomplete images and handwritten notes",
        "False rejects create rework while missed defects create customer escapes",
        "Audit evidence is assembled manually from multiple systems"
      ],
      "goals" => ["Create objective defect standards", "Maintain traceable evidence", "Lower false-reject rates"]
    },
    {
      "id" => "persona-3", "name" => "Engineering Leader Ethan", "title" => "VP Engineering / Automation Director", "order" => 3,
      "pain_points" => [
        "In-house vision projects stall on lighting, model maintenance, and edge deployment",
        "Every new product variant requires another brittle rules-based inspection program",
        "OT security and latency requirements rule out generic public-cloud tooling",
        "Engineering owns too many one-off systems with no common monitoring layer"
      ],
      "goals" => ["Deploy reusable inspection architecture", "Integrate with PLC and MES systems", "Keep data on-site"]
    },
    {
      "id" => "persona-4", "name" => "Plant Manager Priya", "title" => "Plant Manager / Production Manager", "order" => 4,
      "pain_points" => [
        "Line speed and quality targets are managed as competing priorities",
        "Changeovers create quality drift before the team notices a pattern",
        "Supervisors lack a live view of blocked stations and defect clusters",
        "Operators distrust black-box alerts that do not show why a part failed"
      ],
      "goals" => ["Protect throughput", "Shorten changeover stabilization", "Give operators actionable feedback"]
    }
  ],
  use_cases: [
    {
      "id" => "use-case-1", "title" => "Automotive Parts Inspection", "order" => 1,
      "description" => "Detect scratches, porosity, burrs, and machining damage on reflective components at line " \
                       "speed. Store the image, defect class, station, batch, and model version for traceability."
    },
    {
      "id" => "use-case-2", "title" => "Electronics PCB Verification", "order" => 2,
      "description" => "Verify solder joints, polarity, component presence, and connector seating while separating " \
                       "true defects from acceptable process variation."
    },
    {
      "id" => "use-case-3", "title" => "Assembly Completeness and Variant Control", "order" => 3,
      "description" => "Confirm that the correct clips, labels, fasteners, and subassemblies are present for each " \
                       "product variant before the unit leaves the station."
    },
    {
      "id" => "use-case-4", "title" => "Packaging and Label Compliance", "order" => 4,
      "description" => "Validate label text, lot codes, seals, and package integrity while retaining evidence for " \
                       "customer complaints and regulated audits."
    },
    {
      "id" => "use-case-5", "title" => "Cross-Plant Quality Analytics", "order" => 5,
      "description" => "Compare defect distributions across lines, shifts, tools, and plants to identify systemic " \
                       "causes and prioritize process-improvement work."
    }
  ],
  references: [],
  proof_points: [
    {
      "id" => "proof-1", "claim" => "40% reduction in defect escape rate", "order" => 1,
      "description" => "Achieved at a Tier 1 automotive supplier within the first six months"
    },
    {
      "id" => "proof-2", "claim" => "3-month ROI for a typical deployment", "order" => 2,
      "description" => "Average payback period across production deployments"
    },
    {
      "id" => "proof-3", "claim" => "Inspection decisions in under 120 milliseconds", "order" => 3,
      "description" => "Edge inference supports high-speed production without a round trip to the public cloud"
    },
    {
      "id" => "proof-4", "claim" => "Pilot-to-production in four weeks", "order" => 4,
      "description" => "A labeled golden set and one bounded defect family keep the first deployment measurable"
    }
  ]
)

draft_playbook = Playbook.create!(
  organization: primary_org,
  status: "draft",
  language: "en",
  value_proposition: "PredictMaint combines vibration, temperature, and maintenance-history signals to help plant " \
                     "teams intervene before critical rotating equipment fails while avoiding unnecessary scheduled work.",
  product: {
    "name" => "PredictMaint",
    "description" => "Condition monitoring and maintenance prioritization for motors, pumps, gearboxes, and conveyors",
    "metadata" => { "category" => "Industrial Reliability", "deployment" => "Edge plus private cloud" }
  },
  personae: [
    {
      "id" => "persona-1", "name" => "Maintenance Lead Maya", "title" => "Head of Maintenance", "order" => 1,
      "pain_points" => ["Emergency work dominates the weekly plan", "Teams replace healthy components on fixed intervals"]
    },
    {
      "id" => "persona-2", "name" => "Reliability Engineer Riley", "title" => "Reliability Engineer", "order" => 2,
      "pain_points" => ["Sensor trends are reviewed manually", "Failure knowledge is trapped in work-order notes"]
    }
  ],
  use_cases: [
    {
      "id" => "use-case-1", "title" => "Predictive Maintenance", "order" => 1,
      "description" => "Forecast equipment failures before they happen"
    },
    {
      "id" => "use-case-2", "title" => "Maintenance Work Prioritization", "order" => 2,
      "description" => "Rank assets by operational risk, degradation trend, and production criticality"
    },
    {
      "id" => "use-case-3", "title" => "Recurring Failure Analysis", "order" => 3,
      "description" => "Connect sensor anomalies with work-order history to expose repeat root causes"
    }
  ],
  references: [],
  proof_points: [
    {
      "id" => "proof-1", "claim" => "Two-week early warning on bearing degradation", "order" => 1,
      "description" => "Pilot target for critical rotating equipment"
    }
  ]
)

# ---------------------------------------------------------------------------
# Step 8: Global sequence + steps + agents
# ---------------------------------------------------------------------------
global_seq = GlobalSequence.create!(name: "Consultative 3-Touch Manufacturing Outreach")

step1 = SequenceStep.create!(global_sequence: global_seq, position: 1, delay_days: 0, event_type: "email", name: "Opener")
step2 = SequenceStep.create!(global_sequence: global_seq, position: 2, delay_days: 3, event_type: "email", name: "Relevant proof point")
step3 = SequenceStep.create!(global_sequence: global_seq, position: 3, delay_days: 7, event_type: "email", name: "Close the loop")

active_agent = Agent.create!(
  organization: primary_org,
  playbook: approved_playbook,
  global_sequence: global_seq,
  created_by: nina,
  name: "Q3 Manufacturing Outreach",
  status: "active",
  llm_model: "openrouter/deepseek/deepseek-chat"
)

Agent.create!(
  organization: primary_org,
  playbook: approved_playbook,
  global_sequence: global_seq,
  created_by: nina,
  name: "Electronics Vertical Campaign",
  status: "paused",
  llm_model: "openrouter/deepseek/deepseek-chat"
)

# ---------------------------------------------------------------------------
# Step 9: Companies, People, Leads
# ---------------------------------------------------------------------------
companies = [
  { name: "Acme Manufacturing", website_url: "https://acme-mfg.example", domain: "acme-mfg.example" },
  { name: "TechParts Industries", website_url: "https://techparts.example", domain: "techparts.example" },
  { name: "CircuitWorks Electronics", website_url: "https://circuitworks.example", domain: "circuitworks.example" },
  { name: "PrecisionCo Aerospace", website_url: "https://precisionco.example", domain: "precisionco.example" },
  { name: "MegaFab Systems", website_url: "https://megafab.example", domain: "megafab.example" },
  { name: "AutoVision Components", website_url: "https://autovision.example", domain: "autovision.example" },
  { name: "Harbor Medical Devices", website_url: "https://harbor-medical.example", domain: "harbor-medical.example" },
  { name: "Summit Packaging Group", website_url: "https://summit-packaging.example", domain: "summit-packaging.example" }
].map { |attrs| Company.create!(attrs) }

lead_data = [
  { first: "Marcus", last: "Johnson", email: "marcus.johnson@acme-mfg.example", title: "VP Operations", company_index: 0,
    location: "Chicago, Illinois, United States", timezone: "America/Chicago", locale: "en-US", disc: "DC", seniority: "executive", department: "operations", score: 92 },
  { first: "Sarah", last: "Williams", email: "sarah.w@acme-mfg.example", title: "Quality Manager", company_index: 0,
    location: "Milwaukee, Wisconsin, United States", timezone: "America/Chicago", locale: "en-US", disc: "SC", seniority: "manager", department: "quality", score: 84 },
  { first: "David", last: "Chen", email: "d.chen@techparts.example", title: "Director of Manufacturing", company_index: 1,
    location: "Toronto, Ontario, Canada", timezone: "America/Toronto", locale: "en-CA", disc: "DC", seniority: "director", department: "manufacturing", score: 89 },
  { first: "Emily", last: "Rodriguez", email: "emily.r@techparts.example", title: "Plant Manager", company_index: 1,
    location: "Windsor, Ontario, Canada", timezone: "America/Toronto", locale: "en-CA", disc: "DI", seniority: "manager", department: "operations", score: 80 },
  { first: "James", last: "Park", email: "j.park@circuitworks.example", title: "VP Engineering", company_index: 2,
    location: "Austin, Texas, United States", timezone: "America/Chicago", locale: "en-US", disc: "IC", seniority: "executive", department: "engineering", score: 94 },
  { first: "Lisa", last: "Thompson", email: "l.thompson@circuitworks.example", title: "Quality Director", company_index: 2,
    location: "Austin, Texas, United States", timezone: "America/Chicago", locale: "en-US", disc: "C", seniority: "director", department: "quality", score: 87 },
  { first: "Robert", last: "Martinez", email: "r.martinez@precisionco.example", title: "Chief Operating Officer", company_index: 3,
    location: "Seattle, Washington, United States", timezone: "America/Los_Angeles", locale: "en-US", disc: "D", seniority: "c_suite", department: "operations", score: 91 },
  { first: "Jennifer", last: "Davis", email: "j.davis@precisionco.example", title: "Operations Manager", company_index: 3,
    location: "Everett, Washington, United States", timezone: "America/Los_Angeles", locale: "en-US", disc: "SC", seniority: "manager", department: "operations", score: 76 },
  { first: "Michael", last: "Wilson", email: "m.wilson@megafab.example", title: "VP Manufacturing", company_index: 4,
    location: "Detroit, Michigan, United States", timezone: "America/Detroit", locale: "en-US", disc: "DI", seniority: "executive", department: "manufacturing", score: 88 },
  { first: "Amanda", last: "Brown", email: "a.brown@megafab.example", title: "Quality Director", company_index: 4,
    location: "Detroit, Michigan, United States", timezone: "America/Detroit", locale: "en-US", disc: "C", seniority: "director", department: "quality", score: 82 },
  { first: "Christopher", last: "Taylor", email: "c.taylor@autovision.example", title: "Chief Technology Officer", company_index: 5,
    location: "Stuttgart, Germany", timezone: "Europe/Berlin", locale: "en", disc: "DC", seniority: "c_suite", department: "technology", score: 90 },
  { first: "Rachel", last: "Anderson", email: "r.anderson@autovision.example", title: "Head of Quality", company_index: 5,
    location: "Stuttgart, Germany", timezone: "Europe/Berlin", locale: "en", disc: "SC", seniority: "head", department: "quality", score: 85 },
  { first: "Priya", last: "Shah", email: "priya.shah@harbor-medical.example", title: "Director of Quality Systems", company_index: 6,
    location: "Boston, Massachusetts, United States", timezone: "America/New_York", locale: "en-US", disc: "C", seniority: "director", department: "quality", score: 93 },
  { first: "Daniel", last: "Foster", email: "daniel.foster@harbor-medical.example", title: "VP Manufacturing", company_index: 6,
    location: "Boston, Massachusetts, United States", timezone: "America/New_York", locale: "en-US", disc: "DC", seniority: "executive", department: "manufacturing", score: 86 },
  { first: "Maya", last: "Green", email: "maya.green@summit-packaging.example", title: "Continuous Improvement Director", company_index: 7,
    location: "Leeds, United Kingdom", timezone: "Europe/London", locale: "en-GB", disc: "SI", seniority: "director", department: "operational_excellence", score: 83 },
  { first: "Oliver", last: "Reed", email: "oliver.reed@summit-packaging.example", title: "Procurement Director", company_index: 7,
    location: "Leeds, United Kingdom", timezone: "Europe/London", locale: "en-GB", disc: "DC", seniority: "director", department: "procurement", score: 78 }
]

leads = lead_data.map do |d|
  company = companies[d[:company_index]]
  full_name = "#{d[:first]} #{d[:last]}"

  person = Person.create!(
    first_name: d[:first],
    last_name: d[:last],
    full_name: full_name,
    email: d[:email],
    job_title: d[:title],
    company: company.name,
    company_website: company.website_url,
    current_company: company,
    location: d[:location],
    timezone: d[:timezone],
    timezone_resolved_at: 3.days.ago,
    timezone_source: "location",
    preferred_locale: d[:locale],
    locale_source: "linkedin_languages_plus_location",
    email_provider: d[:company_index].even? ? "google" : "microsoft",
    email_provider_detected_at: 3.days.ago,
    linkedin_url: "https://www.linkedin.com/in/#{d[:first].downcase}-#{d[:last].downcase}-northwind-seed",
    linkedin_handle: "#{d[:first].downcase}-#{d[:last].downcase}-northwind-seed",
    linkedin_scraped_at: 4.days.ago,
    linkedin_scraped_data: {
      "full_name" => full_name,
      "headline" => "#{d[:title]} at #{company.name}",
      "location" => d[:location],
      "languages" => [d[:locale].start_with?("en") ? "English" : "German"],
      "current_company" => company.name,
      "current_position" => { "title" => d[:title], "started_at" => "2021-04" },
      "summary" => "Manufacturing leader focused on measurable quality, throughput, and scalable operations.",
      "skills" => ["Lean manufacturing", "Quality systems", "Operational excellence", "Automation"],
      "experience" => [
        { "title" => d[:title], "company" => company.name, "duration" => "3 yrs 8 mos" },
        { "title" => "Operations Program Lead", "company" => "Fictional Industrial Group", "duration" => "4 yrs" }
      ]
    },
    linkedin_posts_scraped_at: 4.days.ago,
    linkedin_posts_scraped_data: {
      "posts" => [
        { "text" => "Proud of the team for completing our latest line-improvement workshop.", "posted_at" => "2026-06-18" },
        { "text" => "Quality data is useful only when operators can act on it during the shift.", "posted_at" => "2026-05-09" }
      ]
    },
    disc_profile: d[:disc],
    disc_profile_source: "linkedin_inferred",
    disc_profile_assessed_at: 3.days.ago,
    disc_profile_data: {
      "confidence" => d[:score] / 100.0,
      "reasoning" => "Role history and public writing suggest a #{d[:disc]} communication style with a practical, data-led focus."
    },
    company_website_scraped_at: 4.days.ago,
    company_website_scraped_data: {
      "company_name" => company.name,
      "industry" => %w[Automotive Electronics Aerospace Industrial Medical Packaging][d[:company_index] % 6],
      "employee_range" => d[:company_index] < 4 ? "500-1000" : "200-500",
      "headquarters" => d[:location].split(",").last.to_s.strip,
      "description" => "Fictional manufacturer investing in automation, traceability, and resilient production systems.",
      "capabilities" => ["Multi-site production", "Automated assembly", "Regulated quality processes"]
    }
  )

  Lead.create!(
    organization: primary_org,
    person: person,
    first_name: d[:first],
    last_name: d[:last],
    full_name: full_name,
    email: d[:email],
    job_title: d[:title],
    company: company.name,
    company_website: company.website_url,
    linkedin_url: person.linkedin_url,
    location: d[:location],
    custom_fields: {
      "seniority" => d[:seniority],
      "department" => d[:department],
      "lead_score" => d[:score],
      "employee_range" => d[:company_index] < 4 ? "500-1000" : "200-500",
      "technologies" => ["MES", "ERP", "Industrial cameras"],
      "research_note" => "Likely owner or influencer for quality automation initiatives."
    }
  )
end

# ---------------------------------------------------------------------------
# Step 10: Lead import (data record)
# ---------------------------------------------------------------------------
LeadImport.create!(
  organization: primary_org,
  imported_by: nina,
  status: "completed",
  source: "csv",
  original_filename: "manufacturing_leads_q3.csv",
  column_mapping: { "email" => "email", "first_name" => "first_name", "last_name" => "last_name" },
  total_rows: lead_data.length,
  processed_rows: lead_data.length,
  created_count: lead_data.length,
  error_count: 0,
  started_at: 2.days.ago,
  completed_at: 2.days.ago + 5.minutes
)

# ---------------------------------------------------------------------------
# Step 11: AgentLeads + Conversations + Messages (email threads)
# ---------------------------------------------------------------------------
agent_leads = leads.map.with_index do |lead, i|
  in_sequence = i < 13
  AgentLead.create!(
    agent: active_agent,
    lead: lead,
    assigned_mailbox: i.even? ? mailbox1 : mailbox2,
    delivery_status: in_sequence ? "in_sequence" : "not_contacted",
    status: in_sequence ? "generated" : "pending",
    sequence_position: in_sequence ? ((i % 3) + 1) : 0
  )
end

conversation_scenarios = [
  {
    interest: "interested", status: "open", unread: true,
    subject: "Reducing false rejects on machined components",
    opener: "We noticed #{companies[0].name} is expanding its precision machining capacity. VisionQC can distinguish " \
            "surface defects from acceptable finish variation without slowing the line.",
    inbound: "This is timely. We lose several hours each week reviewing false rejects from our current camera rules. " \
             "Can you share how you build the golden set and what accuracy threshold you require before going live?",
    response: "Absolutely. We normally start with 300 to 500 labeled images across good parts and the two highest-cost " \
              "defect families. I can walk you through the acceptance test and a sample confusion matrix.",
    follow_up: "That would be useful. Please include our quality manager and send two options for next week."
  },
  {
    interest: "meeting_request", status: "open", unread: false,
    subject: "A four-week inspection pilot for your new line",
    opener: "Your new automated line creates a good opportunity to prove visual inspection on one bounded station " \
            "before standardizing the approach across the plant.",
    inbound: "We are commissioning the line now. Tuesday at 10:00 ET or Thursday at 14:00 ET would work for a " \
             "technical introduction. Please include our controls engineer.",
    response: "Thursday at 14:00 ET works. I will send an agenda covering cameras and lighting, PLC handoff, data " \
              "retention, and how we measure false accepts during the pilot."
  },
  {
    interest: "not_interested", status: "closed", unread: false,
    subject: "Quality automation priorities for this year",
    opener: "We help automotive suppliers introduce objective inspection without replacing their existing MES or " \
            "building a computer-vision team.",
    inbound: "Thanks for the note. Our automation budget is already committed through the end of the year, so this " \
             "is not something we can evaluate right now. Please check back next spring."
  },
  {
    interest: "wrong_person", status: "closed", unread: true,
    subject: "Who owns automated inspection at your plant?",
    opener: "I am trying to understand who owns the quality-automation roadmap for the new assembly cells.",
    inbound: "I manage production scheduling rather than inspection technology. The right person is Elena Brooks, " \
             "our Director of Quality Systems. I have forwarded your note to her."
  },
  {
    interest: "interested", status: "open", unread: false,
    subject: "On-premise vision analytics and plant security",
    opener: "VisionQC can run entirely on-site while still giving engineering a common analytics layer across stations.",
    inbound: "Our security team will not allow production images to leave the plant. Can inference, model storage, " \
             "and audit evidence all remain on-premise? We also need SSO and role-based access.",
    response: "Yes. The edge runtime, image store, and model registry can remain inside your network. The management " \
              "plane supports SSO and role-scoped access, and outbound connectivity can be disabled after deployment.",
    follow_up: "Please send the architecture diagram and security questionnaire before we schedule the next call."
  },
  {
    interest: "meeting_request", status: "open", unread: true,
    subject: "PCB inspection without another rules-engine project",
    opener: "CircuitWorks could use one reusable inspection workflow for polarity, placement, and solder quality " \
            "instead of maintaining separate brittle rules for every board revision.",
    inbound: "We have a new controller board entering validation next month. I can meet Friday morning with our test " \
             "engineering lead to review whether your approach fits the cycle time."
  },
  {
    interest: "not_interested", status: "closed", unread: false,
    subject: "Inspection modernization at PrecisionCo",
    opener: "We help regulated manufacturers retain inspection evidence and standardize defect decisions across shifts.",
    inbound: "We recently renewed our incumbent inspection platform and are not considering alternatives. Please " \
             "remove me from future outreach."
  },
  {
    interest: "wrong_person", status: "open", unread: true,
    subject: "Traceable quality evidence for aerospace assemblies",
    opener: "VisionQC links each decision to the image, model version, station, and batch for audit-ready traceability.",
    inbound: "This belongs with Supplier Quality, not Operations. Please contact Morgan Ellis, who owns incoming " \
             "inspection and supplier corrective actions."
  },
  {
    interest: "interested", status: "snoozed", unread: false,
    snoozed_until: 12.days.from_now,
    subject: "Separating real defects from cosmetic variation",
    opener: "A golden-set pilot can quantify false accepts and false rejects before your team changes the production process.",
    inbound: "Our biggest issue is cosmetic variation that customers accept but the current system rejects. What " \
             "precision and recall have you achieved on reflective housings?",
    response: "The result depends on defect definition and lighting, so we avoid quoting a generic accuracy number. " \
              "We agree the acceptance matrix with your quality team and report every class separately.",
    follow_up: "Understood. Our lead engineer is traveling; follow up in two weeks and we will share sample images."
  },
  {
    interest: "not_interested", status: "closed", unread: false,
    subject: "Vision inspection for your new machining cell",
    opener: "A focused pilot could measure whether automated inspection reduces containment work on the new cell.",
    inbound: "I do not consent to further sales contact. Please delete my details from your outreach list and confirm " \
             "that I will not be contacted again."
  },
  {
    interest: "interested", status: "open", unread: true,
    subject: "Pilot scope for high-mix manufacturing",
    opener: "High-mix plants can reuse a common camera and workflow while versioning the inspection model by product variant.",
    inbound: "We run more than 80 variants in batches as small as 20. How much labeled data is needed per variant, " \
             "and can operators select the correct recipe from the work order?",
    response: "The base model can share visual features across related variants, while the station loads the approved " \
              "recipe from the work-order context. We would first cluster the variants by geometry and defect family."
  },
  {
    interest: "meeting_request", status: "open", unread: false,
    subject: "Quality analytics across multiple plants",
    opener: "VisionQC gives plant teams local control while allowing leadership to compare defect patterns across sites.",
    inbound: "We discussed this internally and would like a 30-minute overview for our quality directors in Germany " \
             "and the US. Wednesday at 16:00 CET is currently open.",
    response: "Wednesday at 16:00 CET is confirmed. I will keep the overview focused on governance, model versioning, " \
              "and how local plants retain ownership of their data."
  },
  {
    interest: "interested", status: "open", unread: true,
    subject: "Audit-ready inspection for medical device packaging",
    opener: "VisionQC can verify seal integrity, label content, and lot codes while retaining evidence by device batch.",
    inbound: "We need electronic records that support our validation package. Can you provide model-change controls, " \
             "user audit trails, and a documented challenge-set protocol?",
    response: "Yes. The validation package includes the approved challenge set, model version history, access audit " \
              "events, and a controlled promotion workflow from test to production."
  },
  {
    interest: "not_interested", status: "closed", unread: false,
    subject: "Inspection capacity for Harbor Medical",
    opener: "Automated evidence capture can reduce the manual review burden on regulated packaging lines.",
    inbound: "The concept is relevant, but our validation team is fully allocated to an ERP rollout this year. We " \
             "cannot support another validated system project until next budget cycle."
  },
  {
    interest: "interested", status: "open", unread: false,
    subject: "Reducing label and seal escapes",
    opener: "A combined label, seal, and package-integrity station can prevent common customer complaints before shipment.",
    inbound: "Could you support both printed-code verification and seal contamination on the same station? We have " \
             "limited conveyor space and cannot add two separate systems.",
    response: "Yes, provided the camera geometry gives both regions sufficient resolution. We would test the combined " \
              "cycle with your minimum line spacing and worst-case package materials."
  },
  {
    interest: "wrong_person", status: "open", unread: true,
    subject: "Who owns packaging quality improvement?",
    opener: "I am looking for the owner of packaging inspection and continuous-improvement initiatives.",
    inbound: "I manage supplier contracts, not plant quality. Your best contact is our Continuous Improvement Director; " \
             "I have copied her on this reply."
  }
]

agent_leads.each_with_index do |agent_lead, i|
  lead = agent_lead.lead
  mailbox = agent_lead.assigned_mailbox
  scenario = conversation_scenarios.fetch(i)
  interest = scenario.fetch(:interest)
  is_unread = scenario.fetch(:unread)
  reply_time = (18 - i).days.ago + 4.hours

  conversation = Conversation.create!(
    organization: primary_org,
    lead: lead,
    mailbox: mailbox,
    agent: active_agent,
    agent_lead: agent_lead,
    interest_status: interest,
    status: scenario.fetch(:status),
    snoozed_until: scenario[:snoozed_until],
    assigned_to: %w[interested meeting_request].include?(interest) ? (i.even? ? nina : noah) : nil,
    last_reply_at: reply_time
  )

  gen_msg = GeneratedMessage.create!(
    agent_lead: agent_lead,
    sequence_step: step1,
    mailbox: mailbox,
    message_kind: "sequence",
    status: "sent",
    subject: scenario.fetch(:subject),
    body: "Hi #{lead.first_name},\n\n#{scenario.fetch(:opener)}\n\nWould it be useful to compare notes for 20 minutes?",
    original_subject: scenario.fetch(:subject),
    original_body: scenario.fetch(:opener),
    ai_model: "openrouter/deepseek/deepseek-chat",
    input_tokens: 840 + (i * 17),
    output_tokens: 118 + (i * 3),
    generation_time_ms: 1_050 + (i * 41),
    sent_at: (18 - i).days.ago + 1.hour
  )

  reply = Reply.create!(
    conversation: conversation,
    lead: lead,
    mailbox: mailbox,
    generated_message: gen_msg,
    api_message_id: "seed-reply-#{i}-1@amplifa.seed",
    message_id: "<seed-reply-#{i}-1@#{companies[i / 2].domain}>",
    subject: "Re: #{scenario.fetch(:subject)}",
    body_plain: scenario.fetch(:inbound),
    body_html: "<p>#{scenario.fetch(:inbound)}</p>",
    from_address: lead.email,
    to_addresses: [mailbox.email],
    received_at: reply_time,
    read_at: is_unread ? nil : reply_time + 1.hour,
    requires_response: %w[interested meeting_request wrong_person].include?(interest),
    responded: scenario[:response].present?,
    responded_at: scenario[:response].present? ? reply_time + 2.hours : nil,
    match_source: "thread_headers",
    match_confidence: "high"
  )

  ConversationRead.create!(account: nina, conversation: conversation, last_read_at: Time.current) unless is_unread

  next unless scenario[:response]

  sent_reply = SentReply.create!(
    conversation: conversation,
    reply: reply,
    mailbox: mailbox,
    sent_by: nina,
    to_address: lead.email,
    subject: "Re: #{scenario.fetch(:subject)}",
    body_plain: scenario.fetch(:response),
    body_html: "<p>#{scenario.fetch(:response)}</p>",
    status: "sent",
    message_id: "<seed-sent-reply-#{i}@northwind-robotics.example>",
    sent_at: reply_time + 2.hours
  )

  next unless scenario[:follow_up]

  Reply.create!(
    conversation: conversation,
    lead: lead,
    mailbox: mailbox,
    generated_message: gen_msg,
    api_message_id: "seed-reply-#{i}-2@amplifa.seed",
    message_id: "<seed-reply-#{i}-2@#{companies[i / 2].domain}>",
    in_reply_to: sent_reply.message_id,
    subject: "Re: #{scenario.fetch(:subject)}",
    body_plain: scenario.fetch(:follow_up),
    body_html: "<p>#{scenario.fetch(:follow_up)}</p>",
    from_address: lead.email,
    to_addresses: [mailbox.email],
    received_at: reply_time + 5.hours,
    read_at: is_unread ? nil : reply_time + 6.hours,
    requires_response: true,
    match_source: "in_reply_to",
    match_confidence: "high"
  )
end

# ---------------------------------------------------------------------------
# Step 12: Meetings (each must reference a matching agent_lead + agent + lead)
# ---------------------------------------------------------------------------
agent_lead_by_lead_id = agent_leads.index_by(&:lead_id)

meeting_specs = [
  { lead: leads[0], status: "scheduled", scheduled_at: 3.days.from_now,
    notes: "Pilot scoping with VP Operations and Quality Manager; review golden-set requirements." },
  { lead: leads[2], status: "scheduled", scheduled_at: 7.days.from_now,
    notes: "Technical discovery with Manufacturing Director and controls engineer." },
  { lead: leads[4], status: "completed", scheduled_at: 5.days.ago,
    notes: "Cycle-time fit confirmed. Next step is a PCB image-set review with test engineering." },
  { lead: leads[6], status: "completed", scheduled_at: 10.days.ago,
    notes: "Strong on-premise requirement. Security questionnaire and architecture diagram requested." },
  { lead: leads[8], status: "no_show", scheduled_at: 3.days.ago,
    notes: "No response after reminder. Follow up once and then close the loop." },
  { lead: leads[1], status: "cancelled", scheduled_at: 2.days.ago,
    notes: "Budget frozen until next planning cycle; permission given to reconnect in March." },
  { lead: leads[12], status: "scheduled", scheduled_at: 10.days.from_now,
    notes: "Validation workshop covering audit trails, challenge sets, and model-change controls." },
  { lead: leads[14], status: "completed", scheduled_at: 14.days.ago,
    notes: "Combined label and seal inspection appears feasible within the available conveyor footprint." }
]

meeting_specs.each do |spec|
  agent_lead = agent_lead_by_lead_id.fetch(spec[:lead].id)
  Meeting.create!(
    organization: primary_org,
    agent: active_agent,
    agent_lead: agent_lead,
    lead: spec[:lead],
    status: spec[:status],
    source: "manual",
    scheduled_at: spec[:scheduled_at],
    notes: spec[:notes]
  )
end

# ---------------------------------------------------------------------------
# Step 13: Blacklists (domain entries)
# ---------------------------------------------------------------------------
%w[competitor.example spam-domain.example unsubscribed.example].each do |value|
  Blacklist.create!(
    organization: primary_org,
    created_by: nina,
    value: value,
    value_type: "domain",
    source: "manual"
  )
end

# ---------------------------------------------------------------------------
# Step 14: Decoy org minimal data (for cross-org denial tests)
# ---------------------------------------------------------------------------
decoy_company = Company.create!(
  name: "Sunrise Data Systems",
  website_url: "https://sunrise-data.example",
  domain: "sunrise-data.example"
)
decoy_person = Person.create!(
  first_name: "Taylor",
  last_name: "Morgan",
  full_name: "Taylor Morgan",
  email: "taylor@sunrise-data.example",
  job_title: "Director of Revenue Operations",
  company: decoy_company.name,
  company_website: decoy_company.website_url,
  current_company: decoy_company,
  location: "New York, New York, United States",
  timezone: "America/New_York",
  timezone_source: "location",
  preferred_locale: "en-US",
  locale_source: "linkedin_languages_plus_location",
  email_provider: "microsoft",
  email_provider_detected_at: 2.days.ago,
  linkedin_url: "https://www.linkedin.com/in/taylor-morgan-sunrise-seed",
  linkedin_handle: "taylor-morgan-sunrise-seed",
  linkedin_scraped_at: 2.days.ago,
  linkedin_scraped_data: {
    "full_name" => "Taylor Morgan",
    "headline" => "Director of Revenue Operations at Sunrise Data Systems",
    "location" => "New York, New York, United States",
    "current_company" => decoy_company.name,
    "skills" => ["Revenue operations", "Forecasting", "Sales analytics"]
  },
  disc_profile: "DC",
  disc_profile_source: "linkedin_inferred",
  disc_profile_assessed_at: 2.days.ago,
  disc_profile_data: {
    "confidence" => 0.72,
    "reasoning" => "Fictional profile indicates a decisive, analytical communication style."
  }
)
decoy_lead = Lead.create!(
  organization: decoy_org,
  person: decoy_person,
  first_name: decoy_person.first_name,
  last_name: decoy_person.last_name,
  full_name: decoy_person.full_name,
  email: decoy_person.email,
  job_title: decoy_person.job_title,
  company: decoy_company.name,
  company_website: decoy_company.website_url,
  linkedin_url: decoy_person.linkedin_url,
  location: decoy_person.location,
  custom_fields: {
    "seniority" => "director",
    "department" => "revenue_operations",
    "lead_score" => 74,
    "research_note" => "Fictional record used to verify cross-organization isolation."
  }
)
decoy_domain = EmailDomain.create!(
  organization: decoy_org,
  domain: "sunrise-analytics.example",
  provider_type: "microsoft",
  microsoft_tenant_id: "seed-tenant-sunrise",
  status: "active"
)
decoy_mailbox = Mailbox.create!(
  organization: decoy_org,
  email_domain: decoy_domain,
  email: "sam@sunrise-analytics.example",
  status: "active",
  daily_send_limit: 30
)
decoy_conversation = Conversation.create!(
  organization: decoy_org,
  lead: decoy_lead,
  mailbox: decoy_mailbox,
  interest_status: "interested",
  status: "open",
  assigned_to: sam
)
Reply.create!(
  conversation: decoy_conversation,
  lead: decoy_lead,
  mailbox: decoy_mailbox,
  api_message_id: "seed-decoy-reply-1@amplifa.seed",
  message_id: "<seed-decoy-reply-1@sunrise-data.example>",
  subject: "Re: Forecast visibility across the revenue team",
  body_plain: "The workflow comparison is relevant. Could you show how permissions differ for sales managers and finance?",
  body_html: "<p>The workflow comparison is relevant. Could you show how permissions differ for sales managers and finance?</p>",
  from_address: decoy_lead.email,
  to_addresses: [decoy_mailbox.email],
  received_at: 2.days.ago,
  requires_response: true,
  match_source: "thread_headers",
  match_confidence: "high"
)

# ---------------------------------------------------------------------------
# Step 15: Print credentials + counts
# ---------------------------------------------------------------------------
puts ""
puts "=" * 60
puts "SEEDS COMPLETE"
puts "=" * 60
puts ""
puts "Login credentials (password: #{SEED_PASSWORD}):"
puts "  Amplifa Admin:    admin@amplifa.com"
puts "  Primary Admin:    nina@northwind-robotics.example"
puts "  Primary User:     noah@northwind-robotics.example"
puts "  Decoy Admin:      sam@sunrise-analytics.example"
puts "  Dual-Membership:  dana@consultants.example"
puts ""
puts "Primary org: Northwind Robotics (#{primary_org.id})"
puts "Decoy org:   Sunrise Analytics (#{decoy_org.id})"
puts ""
puts "Counts:"
puts "  Organizations:  #{Organization.count}"
puts "  Accounts:       #{Account.count}"
puts "  Memberships:    #{OrganizationMembership.count}"
puts "  Leads:          #{Lead.count}"
puts "  Agents:         #{Agent.count}"
puts "  Conversations:  #{Conversation.count}"
puts "  Replies:        #{Reply.count} (unread: #{Reply.where(read_at: nil).count})"
puts "  Meetings:       #{Meeting.count}"
