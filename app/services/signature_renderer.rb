# frozen_string_literal: true

# Renders sender signature templates with variable interpolation.
# Supports HTML templates with {{variable}} placeholders that get replaced
# with actual sender/organization data.
class SignatureRenderer
  SENDER_VARIABLES = %w[sender_first_name sender_last_name sender_full_name sender_nickname sender_job_title sender_email sender_calendly_url sender_calendly_link sender_linkedin_url
                        sender_company].freeze

  LEAD_VARIABLES = %w[lead_first_name lead_last_name lead_full_name lead_company lead_job_title lead_email
                      lead_location lead_linkedin_url lead_company_website].freeze

  VARIABLES = (SENDER_VARIABLES + LEAD_VARIABLES).freeze

  def initialize(sender, lead: nil, agent: nil, agent_lead: nil)
    @sender = sender
    @lead = lead
    @agent = agent
    @agent_lead = agent_lead
  end

  def render
    return '' if @sender.signature_template.blank?

    template = @sender.signature_template.dup
    VARIABLES.each do |var|
      template.gsub!("{{#{var}}}", value_for(var).to_s)
    end
    template
  end

  def self.available_variables
    VARIABLES.map { |var| "{{#{var}}}" }
  end

  private

  def value_for(variable)
    # Handle lead_ prefix first
    if variable.start_with?('lead_')
      field = variable.sub(/^lead_/, '')
      return @lead&.public_send(field).to_s
    end

    # Strip sender_ prefix to get the actual field name
    field_name = variable.sub(/^sender_/, '')

    case field_name
    when 'full_name'
      @sender.full_name
    when 'nickname'
      @sender.nickname.presence || @sender.first_name
    when 'company'
      @sender.organization&.name
    when 'calendly_link'
      @sender.calendly_url
    else
      @sender.public_send(field_name) if @sender.respond_to?(field_name)
    end
  end
end
