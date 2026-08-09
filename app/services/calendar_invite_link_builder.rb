# frozen_string_literal: true

require 'time'

class CalendarInviteLinkBuilder
  GOOGLE_BASE_URL = 'https://calendar.google.com/calendar/render'
  OUTLOOK_BASE_URL = 'https://outlook.office.com/calendar/0/deeplink/compose'
  MAX_ATTACHMENT_BYTES = 512.kilobytes
  OUTLOOK_QUERY_BYTES_LIMIT = 2_048
  OUTLOOK_TRUNCATION_MARKER = '...'
  OUTLOOK_BODY_SECTION_SEPARATOR = ' | '
  OUTLOOK_BODY_VALUE_SEPARATOR = '; '
  VIRTUAL_MEETING_HOSTS = %w[
    zoom.us
    teams.microsoft.com
    meet.google.com
    webex.com
    skype.com
  ].freeze
  FLOATING_TIME_PATTERN = /\A(?<year>\d{4})(?<month>\d{2})(?<day>\d{2})T(?<hour>\d{2})(?<minute>\d{2})(?<second>\d{2})\z/
  ISO_FLOATING_TIME_PATTERN =
    /\A(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T(?<hour>\d{2}):(?<minute>\d{2})(?::(?<second>\d{2})(?:\.\d+)?)?\z/
  URL_PATTERN = %r{https?://[^\s<>]+}
  WINDOWS_TIME_ZONES = {
    'UTC' => 'Etc/UTC',
    'GMT Standard Time' => 'Europe/London',
    'W. Europe Standard Time' => 'Europe/Berlin',
    'Central Europe Standard Time' => 'Europe/Budapest',
    'Romance Standard Time' => 'Europe/Paris',
    'Central European Standard Time' => 'Europe/Warsaw',
    'E. Europe Standard Time' => 'Europe/Chisinau',
    'FLE Standard Time' => 'Europe/Kyiv',
    'GTB Standard Time' => 'Europe/Bucharest',
    'Israel Standard Time' => 'Asia/Jerusalem',
    'Arabian Standard Time' => 'Asia/Dubai',
    'Arab Standard Time' => 'Asia/Riyadh',
    'India Standard Time' => 'Asia/Kolkata',
    'SE Asia Standard Time' => 'Asia/Bangkok',
    'China Standard Time' => 'Asia/Shanghai',
    'Singapore Standard Time' => 'Asia/Singapore',
    'Tokyo Standard Time' => 'Asia/Tokyo',
    'Korea Standard Time' => 'Asia/Seoul',
    'AUS Eastern Standard Time' => 'Australia/Sydney',
    'E. Australia Standard Time' => 'Australia/Brisbane',
    'New Zealand Standard Time' => 'Pacific/Auckland',
    'Hawaiian Standard Time' => 'Pacific/Honolulu',
    'Alaskan Standard Time' => 'America/Anchorage',
    'Pacific Standard Time' => 'America/Los_Angeles',
    'Mountain Standard Time' => 'America/Denver',
    'US Mountain Standard Time' => 'America/Phoenix',
    'Central Standard Time' => 'America/Chicago',
    'Eastern Standard Time' => 'America/New_York',
    'Atlantic Standard Time' => 'America/Halifax'
  }.freeze

  def self.build(file:, fallback_title: nil, file_size_bytes: nil)
    new(file:, fallback_title:, file_size_bytes:).build
  end

  def self.build_from_event_data(event_data:, fallback_title: nil)
    new(event_data:, fallback_title:).build_from_event_data
  end

  def self.event_data_from_ics(content:, source:, fallback_title: nil)
    new(fallback_title:).event_data_from_ics(content:, source:)
  end

  def initialize(file: nil, fallback_title: nil, event_data: nil, file_size_bytes: nil)
    @file = file
    @fallback_title = fallback_title
    @event_data = event_data
    @file_size_bytes = file_size_bytes
  end

  def build
    return nil unless @file&.attached?
    return nil if attachment_too_large?

    event = parse_event(@file.download)
    return nil unless event

    build_urls(event)
  rescue StandardError => e
    Rails.logger.warn("CalendarInviteLinkBuilder failed for attachment #{@file&.blob_id}: #{e.class} #{e.message}")
    nil
  end

  def build_from_event_data
    event = normalize_event_data(@event_data)
    return nil unless event

    build_urls(event)
  rescue StandardError => e
    Rails.logger.warn("CalendarInviteLinkBuilder failed for event data: #{e.class} #{e.message}")
    nil
  end

  def event_data_from_ics(content:, source:)
    event = parse_event(content)
    return nil unless event

    {
      source: source,
      message_type: calendar_message_type(content),
      title: event[:title],
      description: event[:raw_description],
      location: event[:location],
      start_at: structured_datetime(event[:start_at]),
      end_at: structured_datetime(event[:end_at]),
      organizer_name: event.dig(:organizer, :name),
      organizer_email: event.dig(:organizer, :email),
      attendees: event[:attendees]&.map { |attendee| attendee.slice(:name, :email).compact },
      conference_links: event[:conference_links]
    }.compact
  rescue StandardError => e
    Rails.logger.warn("CalendarInviteLinkBuilder failed to extract event data from ICS: #{e.class} #{e.message}")
    nil
  end

  private

  def build_urls(event)
    {
      google_url: build_google_url(event),
      outlook_url: build_outlook_url(event)
    }
  end

  def parse_event(content)
    event_lines = extract_event_lines(unfold_lines(content.to_s))
    return nil if event_lines.empty?

    properties = parse_properties(event_lines)
    start_at = parse_datetime(first_property(properties, 'DTSTART'))
    return nil unless start_at

    end_at = parse_datetime(first_property(properties, 'DTEND')) || default_end_at(start_at)
    organizer = parse_contact(first_property(properties, 'ORGANIZER'))
    attendees = parse_attendees(properties['ATTENDEE'])
    recurrence_rule = normalize_rrule(first_property_value(properties, 'RRULE'))
    transparency = normalize_transparency(first_property_value(properties, 'TRANSP'))
    event_status = first_property_value(properties, 'STATUS')&.upcase
    categories = parse_categories(properties['CATEGORIES'])
    uid = first_property_value(properties, 'UID')
    location = first_property_value(properties, 'LOCATION')
    description = first_property_value(properties, 'DESCRIPTION')
    event_url = first_property_value(properties, 'URL')
    conference_links = parse_conference_links(properties['CONFERENCE'])
    supplemental_lines = build_supplemental_lines(
      description:,
      location:,
      event_url:,
      conference_links:,
      organizer:,
      attendees:,
      recurrence_rule:,
      event_status:,
      categories:,
      uid:
    )

    {
      title: first_property_value(properties, 'SUMMARY').presence || @fallback_title.presence || 'Calendar event',
      description: combine_description(description, supplemental_lines),
      raw_description: description,
      location: location,
      event_url: event_url,
      start_at: start_at,
      end_at: end_at,
      all_day: start_at[:kind] == :date && end_at[:kind] == :date,
      google_timezone: google_timezone_for(start_at),
      organizer: organizer,
      attendees: attendees,
      conference_links: conference_links,
      attendee_emails: attendees.filter_map { |attendee| attendee[:email] }.uniq,
      recurrence_rule: recurrence_rule,
      event_status: event_status,
      categories: categories,
      uid: uid,
      transparency: transparency
    }
  end

  def calendar_message_type(content)
    method = first_property_value(parse_properties(unfold_lines(content.to_s)), 'METHOD')&.upcase

    case method
    when 'REQUEST'
      'meetingRequest'
    when 'CANCEL'
      'meetingCancelled'
    else
      method&.downcase
    end
  end

  def structured_datetime(datetime)
    return nil unless datetime

    case datetime[:kind]
    when :date
      { date_time: datetime[:date].iso8601 }
    when :utc
      { date_time: datetime[:time].utc.iso8601 }
    when :zoned
      { date_time: datetime[:time].strftime('%Y-%m-%dT%H:%M:%S'), time_zone: datetime[:tzid] }.compact
    when :floating
      { date_time: format('%<year>04d-%<month>02d-%<day>02dT%<hour>02d:%<minute>02d:%<second>02d', datetime[:parts]) }
    end
  end

  def normalize_event_data(event_data)
    data = event_data.to_h.with_indifferent_access
    start_at = parse_structured_datetime(data[:start_at])
    return nil unless start_at

    end_at = parse_structured_datetime(data[:end_at]) || default_end_at(start_at)
    attendees = normalize_structured_attendees(data[:attendees])
    conference_links = normalize_structured_conference_links(data[:conference_links])
    organizer = {
      name: data[:organizer_name].presence,
      email: data[:organizer_email].presence
    }.compact.presence
    supplemental_lines = build_supplemental_lines(
      description: data[:description].presence,
      location: data[:location],
      event_url: data[:event_url].presence,
      conference_links: conference_links,
      organizer: organizer,
      attendees: attendees,
      recurrence_rule: nil,
      event_status: data[:message_type].presence,
      categories: [],
      uid: nil
    )
    timezone_label = structured_timezone_label(data, start_at, end_at)
    supplemental_lines << "Timezone: #{timezone_label}" if timezone_label.present?

    {
      title: data[:title].presence || @fallback_title.presence || 'Calendar event',
      description: combine_description(data[:description], supplemental_lines),
      raw_description: data[:description].presence,
      location: data[:location].presence,
      event_url: data[:event_url].presence,
      start_at: start_at,
      end_at: end_at,
      all_day: start_at[:kind] == :date && end_at[:kind] == :date,
      google_timezone: google_timezone_for(start_at),
      organizer: organizer,
      attendees: attendees,
      conference_links: conference_links,
      attendee_emails: attendees.filter_map { |attendee| attendee[:email] }.uniq,
      recurrence_rule: nil,
      event_status: data[:message_type].presence,
      timezone_label: timezone_label,
      transparency: nil
    }
  end

  def normalize_structured_attendees(attendees)
    Array(attendees).filter_map do |attendee|
      attendee_hash = attendee.to_h.with_indifferent_access
      email = attendee_hash[:email].presence
      name = attendee_hash[:name].presence
      next if email.blank? && name.blank?

      { email: email, name: name }.compact
    end
  end

  def normalize_structured_conference_links(conference_links)
    Array(conference_links).filter_map do |link|
      link_hash = link.to_h.with_indifferent_access
      url = link_hash[:url].presence
      next if url.blank?

      {
        label: link_hash[:label].presence || event_link_label(url) || 'Join meeting',
        url: url
      }
    end
  end

  def parse_structured_datetime(value)
    property = value.to_h.with_indifferent_access
    date_time_value = property[:date_time].presence
    return nil if date_time_value.blank?

    return { kind: :date, date: Date.iso8601(date_time_value) } if date_time_value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    return parse_offset_datetime(date_time_value) if date_time_value.match?(/[zZ]\z|[+-]\d{2}:\d{2}\z/)

    match = date_time_value.match(ISO_FLOATING_TIME_PATTERN)
    return nil unless match

    parts = match.named_captures.transform_values { |part| part.to_i }
    normalized_tzid = normalized_timezone_name(property[:time_zone])
    return { kind: :floating, parts: parts } if normalized_tzid.blank?

    time_zone = ActiveSupport::TimeZone[normalized_tzid] || Time.find_zone(normalized_tzid)
    return { kind: :floating, parts: parts } unless time_zone

    {
      kind: :zoned,
      time: time_zone.local(parts['year'], parts['month'], parts['day'], parts['hour'], parts['minute'],
                            parts['second']),
      tzid: normalized_tzid
    }
  end

  def parse_offset_datetime(value)
    time = Time.iso8601(value)

    { kind: :utc, time: time.utc }
  rescue ArgumentError
    nil
  end

  def normalized_timezone_name(value)
    timezone = value.to_s.strip
    return nil if timezone.blank?

    WINDOWS_TIME_ZONES[timezone] || timezone
  end

  def structured_timezone_label(data, start_at, end_at)
    data[:time_zone].presence ||
      data.dig(:start_at, :time_zone).presence ||
      data.dig(:end_at, :time_zone).presence ||
      start_at[:tzid].presence ||
      end_at[:tzid].presence
  end

  def unfold_lines(content)
    content.gsub(/\r\n?/, "\n").lines.each_with_object([]) do |line, unfolded|
      stripped_line = line.delete_suffix("\n")

      if stripped_line.start_with?(' ', "\t") && unfolded.any?
        unfolded[-1] += stripped_line[1..]
      else
        unfolded << stripped_line
      end
    end
  end

  def extract_event_lines(lines)
    in_event = false
    event_lines = []

    lines.each do |line|
      if line == 'BEGIN:VEVENT'
        in_event = true
        next
      end

      break if line == 'END:VEVENT'

      event_lines << line if in_event
    end

    event_lines
  end

  def parse_properties(lines)
    lines.each_with_object({}) do |line, properties|
      name_and_params, raw_value = line.split(':', 2)
      next unless name_and_params && raw_value

      name, *param_parts = name_and_params.split(';')
      next unless name

      properties[name] ||= []
      properties[name] << {
        value: unescape_text(raw_value),
        params: parse_params(param_parts)
      }
    end
  end

  def first_property(properties, name)
    properties[name]&.first
  end

  def first_property_value(properties, name)
    first_property(properties, name)&.fetch(:value, nil)
  end

  def parse_params(parts)
    parts.each_with_object({}) do |part, params|
      key, value = part.split('=', 2)
      params[key] = strip_param_quotes(value) if key && value
    end
  end

  def strip_param_quotes(value)
    value.to_s.strip.gsub(/\A"|"\z/, '')
  end

  def parse_datetime(property)
    return nil unless property

    value = property[:value]
    params = property[:params]

    if params['VALUE'] == 'DATE' || value.match?(/\A\d{8}\z/)
      { kind: :date, date: Date.strptime(value, '%Y%m%d') }
    elsif value.end_with?('Z')
      parse_utc_datetime(value)
    elsif params['TZID'].present?
      parse_zoned_datetime(value, params['TZID'])
    elsif (match = value.match(FLOATING_TIME_PATTERN))
      {
        kind: :floating,
        parts: match.named_captures.transform_values(&:to_i)
      }
    end
  end

  def parse_zoned_datetime(value, tzid)
    match = value.match(FLOATING_TIME_PATTERN)
    return nil unless match

    normalized_tzid = normalized_timezone_name(tzid)
    time_zone = ActiveSupport::TimeZone[normalized_tzid] || Time.find_zone(normalized_tzid)
    return nil unless time_zone

    parts = match.named_captures.transform_values(&:to_i)

    {
      kind: :zoned,
      time: time_zone.local(parts['year'], parts['month'], parts['day'], parts['hour'], parts['minute'],
                            parts['second']),
      tzid: normalized_tzid
    }
  end

  def attachment_too_large?
    size = @file_size_bytes || inferred_file_size_bytes
    size.present? && size > MAX_ATTACHMENT_BYTES
  end

  def inferred_file_size_bytes
    return @file.byte_size if @file.respond_to?(:byte_size)
    return @file.blob.byte_size if @file.respond_to?(:blob) && @file.blob.respond_to?(:byte_size)

    nil
  end

  def parse_utc_datetime(value)
    match = value.delete_suffix('Z').match(FLOATING_TIME_PATTERN)
    return nil unless match

    parts = match.named_captures.transform_values(&:to_i)

    {
      kind: :utc,
      time: Time.utc(parts['year'], parts['month'], parts['day'], parts['hour'], parts['minute'], parts['second'])
    }
  end

  def parse_contact(property)
    return nil unless property

    value = property[:value].to_s.sub(/\Amailto:/i, '')
    return nil if value.blank?

    {
      email: value,
      name: property[:params]['CN'].presence
    }
  end

  def parse_attendees(properties)
    Array(properties).filter_map do |property|
      contact = parse_contact(property)
      next unless contact

      contact.merge(role: property[:params]['ROLE'].presence)
    end
  end

  def parse_categories(properties)
    Array(properties).flat_map do |property|
      property[:value].to_s.split(',').map(&:strip)
    end.reject(&:blank?).uniq
  end

  def normalize_rrule(value)
    return nil if value.blank?

    value.start_with?('RRULE:') ? value : "RRULE:#{value}"
  end

  def normalize_transparency(value)
    case value&.upcase
    when 'TRANSPARENT'
      :free
    when 'OPAQUE'
      :busy
    end
  end

  def parse_conference_links(properties)
    Array(properties).filter_map do |property|
      url = extract_first_url(property[:value])
      next unless url

      {
        label: property[:params]['LABEL'].presence || conference_label(property[:params]['FEATURE']),
        url: url
      }
    end
  end

  def conference_label(feature)
    case feature&.upcase
    when 'VIDEO'
      'Join meeting'
    when 'PHONE'
      'Dial-in'
    else
      'Conference'
    end
  end

  def build_supplemental_lines(description:, location:, event_url:, conference_links:, organizer:, attendees:,
                               recurrence_rule:, event_status:, categories:, uid:)
    lines = []
    seen_urls = urls_in_text(description)

    conference_links.each do |link|
      append_url_line(lines, seen_urls, link[:label], link[:url])
    end

    append_url_line(lines, seen_urls, event_link_label(event_url), event_url)
    append_url_line(lines, seen_urls, 'Location link', location) if url?(location)

    organizer_text = format_contact(organizer)
    lines << "Organizer: #{organizer_text}" if organizer_text.present?

    attendee_text = attendees.map { |attendee| format_contact(attendee) }.reject(&:blank?).uniq.join(', ')
    lines << "Attendees: #{attendee_text}" if attendee_text.present?
    lines << "Recurrence: #{recurrence_rule}" if recurrence_rule.present?
    lines << "Status: #{event_status}" if event_status.present?
    lines << "Categories: #{categories.join(', ')}" if categories.any?
    lines << "UID: #{uid}" if uid.present?
    lines
  end

  def append_url_line(lines, seen_urls, label, url)
    return if url.blank? || label.blank? || seen_urls.include?(url)

    lines << "#{label}: #{url}"
    seen_urls << url
  end

  def event_link_label(url)
    return nil if url.blank?

    virtual_meeting_url?(url) ? 'Join meeting' : 'Event link'
  end

  def combine_description(description, supplemental_lines)
    base = description.to_s.strip
    extras = supplemental_lines.reject(&:blank?).join("\n")
    return base if extras.blank?
    return extras if base.blank?

    "#{base}\n\n#{extras}"
  end

  def urls_in_text(text)
    text.to_s.scan(URL_PATTERN).uniq
  end

  def extract_first_url(text)
    text.to_s[URL_PATTERN]
  end

  def url?(text)
    text.to_s.match?(%r{\Ahttps?://}i)
  end

  def virtual_meeting_url?(url)
    host = URI.parse(url).host.to_s.downcase
    return false if host.blank?

    virtual_meeting_host?(host)
  rescue URI::InvalidURIError
    false
  end

  def virtual_meeting_host?(host)
    VIRTUAL_MEETING_HOSTS.any? do |allowed_host|
      host == allowed_host || host.end_with?(".#{allowed_host}")
    end
  end

  def format_contact(contact)
    return nil unless contact

    return "#{contact[:name]} <#{contact[:email]}>" if contact[:name].present? && contact[:email].present?

    contact[:email].presence || contact[:name].presence
  end

  def default_end_at(start_at)
    case start_at[:kind]
    when :date
      { kind: :date, date: start_at[:date] + 1.day }
    else
      start_at
    end
  end

  def google_timezone_for(datetime)
    datetime[:kind] == :zoned ? datetime[:tzid] : nil
  end

  def build_google_url(event)
    params = {
      action: 'TEMPLATE',
      text: event[:title],
      dates: "#{format_google_datetime(event[:start_at])}/#{format_google_datetime(event[:end_at])}",
      details: event[:description].presence,
      location: event[:location].presence,
      ctz: event[:google_timezone],
      add: event[:attendee_emails].presence&.join(','),
      recur: event[:recurrence_rule],
      trp: google_transparency(event[:transparency])
    }.compact

    "#{GOOGLE_BASE_URL}?#{URI.encode_www_form(params)}"
  end

  def build_outlook_url(event)
    params = {
      path: '/calendar/action/compose',
      rru: 'addevent',
      startdt: format_outlook_datetime(event[:start_at]),
      enddt: format_outlook_datetime(event[:end_at]),
      subject: event[:title],
      body: event[:description].presence,
      location: event[:location].presence,
      allday: event[:all_day] ? 'true' : nil,
      to: event[:attendee_emails].presence&.join(','),
      freebusy: outlook_transparency(event[:transparency])
    }.compact

    params[:body] = compact_outlook_body(event, params) if outlook_query_too_long?(params)

    "#{OUTLOOK_BASE_URL}?#{encode_outlook_params(params)}"
  end

  def compact_outlook_body(event, params)
    body = outlook_essential_body_sections(event).each_with_object([]) do |section, sections|
      candidate = (sections + [section]).join(OUTLOOK_BODY_SECTION_SEPARATOR)
      sections << section if outlook_query_fits?(params.merge(body: candidate))
    end.join(OUTLOOK_BODY_SECTION_SEPARATOR)

    description = single_line_outlook_text(event[:raw_description])
    return body.presence if description.blank?

    separator = body.present? ? OUTLOOK_BODY_SECTION_SEPARATOR : ''
    truncate_outlook_body_to_fit(params, description, body, separator)
  end

  def outlook_essential_body_sections(event)
    seen_urls = []
    sections = []
    link_lines = []

    urls_in_text(event[:raw_description]).each do |url|
      append_outlook_link_line(link_lines, seen_urls, 'Join meeting', url) if virtual_meeting_url?(url)
    end

    Array(event[:conference_links]).each do |link|
      append_outlook_link_line(link_lines, seen_urls, link[:label].presence || event_link_label(link[:url]), link[:url])
    end

    append_outlook_link_line(link_lines, seen_urls, event_link_label(event[:event_url]), event[:event_url])
    append_outlook_link_line(link_lines, seen_urls, 'Location link', event[:location]) if url?(event[:location])
    sections << outlook_section('Meeting links', link_lines) if link_lines.any?

    organizer_text = format_contact(event[:organizer])
    sections << outlook_section('Organizer', [organizer_text]) if organizer_text.present?
    sections << outlook_section('Timezone', [event[:timezone_label]]) if event[:timezone_label].present?

    attendee_lines = Array(event[:attendees]).map { |attendee| format_contact(attendee) }.reject(&:blank?).uniq
    sections << outlook_section('Attendees', attendee_lines.map { |attendee| "- #{attendee}" }) if attendee_lines.any?

    detail_lines = []
    detail_lines << "Recurrence: #{event[:recurrence_rule]}" if event[:recurrence_rule].present?
    detail_lines << "Status: #{event[:event_status]}" if event[:event_status].present?
    detail_lines << "Categories: #{event[:categories].join(', ')}" if Array(event[:categories]).any?
    detail_lines << "UID: #{event[:uid]}" if event[:uid].present?
    sections << outlook_section('Event details', detail_lines) if detail_lines.any?

    sections.uniq
  end

  def append_outlook_link_line(lines, seen_urls, label, url)
    return if url.blank? || label.blank? || seen_urls.include?(url)

    lines << "#{label}: #{url}"
    seen_urls << url
  end

  def outlook_section(title, lines)
    "#{title}: #{lines.reject(&:blank?).join(OUTLOOK_BODY_VALUE_SEPARATOR)}"
  end

  def truncate_outlook_body_to_fit(params, description, prefix, separator)
    full_body = [prefix.presence, outlook_description_section(description)].compact.join(separator)
    return full_body if outlook_query_fits?(params.merge(body: full_body))
    return prefix.presence if outlook_prefix_with_marker_too_long?(params, prefix, separator)

    low = 0
    high = description.length
    best = prefix.presence

    while low <= high
      midpoint = (low + high) / 2
      candidate = outlook_body_candidate(prefix, description[0...midpoint].to_s, separator)

      if candidate.present? && outlook_query_fits?(params.merge(body: candidate))
        best = candidate
        low = midpoint + 1
      else
        high = midpoint - 1
      end
    end

    best
  end

  def outlook_prefix_with_marker_too_long?(params, prefix, separator)
    prefix.present? && !outlook_query_fits?(params.merge(
      body: "#{prefix}#{separator}#{outlook_description_section(OUTLOOK_TRUNCATION_MARKER)}"
    ))
  end

  def outlook_body_candidate(prefix, description, separator)
    candidate_description = description.strip

    [
      prefix.presence,
      candidate_description.presence && outlook_description_section("#{candidate_description}#{OUTLOOK_TRUNCATION_MARKER}")
    ].compact.join(separator)
  end

  def outlook_description_section(description)
    outlook_section('Description', [single_line_outlook_text(description)])
  end

  def single_line_outlook_text(text)
    text.to_s.gsub(/\s+/, ' ').strip
  end

  def outlook_query_too_long?(params)
    !outlook_query_fits?(params)
  end

  def outlook_query_fits?(params)
    encode_outlook_params(params.compact).bytesize <= OUTLOOK_QUERY_BYTES_LIMIT
  end

  def encode_outlook_params(params)
    URI.encode_www_form(params).gsub('+', '%20')
  end

  def google_transparency(value)
    case value
    when :free
      'false'
    when :busy
      'true'
    end
  end

  def outlook_transparency(value)
    case value
    when :free
      'free'
    when :busy
      'busy'
    end
  end

  def format_google_datetime(datetime)
    case datetime[:kind]
    when :date
      datetime[:date].strftime('%Y%m%d')
    when :utc
      datetime[:time].utc.strftime('%Y%m%dT%H%M%SZ')
    when :zoned
      datetime[:time].strftime('%Y%m%dT%H%M%S')
    when :floating
      format('%<year>04d%<month>02d%<day>02dT%<hour>02d%<minute>02d%<second>02d', datetime[:parts])
    end
  end

  def format_outlook_datetime(datetime)
    case datetime[:kind]
    when :date
      datetime[:date].iso8601
    when :utc
      datetime[:time].utc.strftime('%Y-%m-%dT%H:%M:%S')
    when :zoned
      datetime[:time].strftime('%Y-%m-%dT%H:%M:%S')
    when :floating
      format('%<year>04d-%<month>02d-%<day>02dT%<hour>02d:%<minute>02d:%<second>02d', datetime[:parts])
    end
  end

  def unescape_text(value)
    value
      .gsub('\\n', "\n")
      .gsub('\\N', "\n")
      .gsub('\\,', ',')
      .gsub('\\;', ';')
      .gsub('\\\\', '\\')
  end
end
