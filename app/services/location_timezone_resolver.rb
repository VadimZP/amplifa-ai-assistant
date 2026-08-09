# frozen_string_literal: true

class LocationTimezoneResolver
  LOCATION_TIMEZONE_MAP = {
    'new york' => 'America/New_York',
    'nyc' => 'America/New_York',
    'manhattan' => 'America/New_York',
    'brooklyn' => 'America/New_York',
    'boston' => 'America/New_York',
    'philadelphia' => 'America/New_York',
    'washington' => 'America/New_York',
    'dc' => 'America/New_York',
    'atlanta' => 'America/New_York',
    'miami' => 'America/New_York',
    'florida' => 'America/New_York',
    'chicago' => 'America/Chicago',
    'illinois' => 'America/Chicago',
    'dallas' => 'America/Chicago',
    'houston' => 'America/Chicago',
    'texas' => 'America/Chicago',
    'austin' => 'America/Chicago',
    'denver' => 'America/Denver',
    'colorado' => 'America/Denver',
    'phoenix' => 'America/Phoenix',
    'arizona' => 'America/Phoenix',
    'los angeles' => 'America/Los_Angeles',
    'la' => 'America/Los_Angeles',
    'san francisco' => 'America/Los_Angeles',
    'sf' => 'America/Los_Angeles',
    'san diego' => 'America/Los_Angeles',
    'seattle' => 'America/Los_Angeles',
    'california' => 'America/Los_Angeles',
    'portland' => 'America/Los_Angeles',
    'oregon' => 'America/Los_Angeles',
    'nevada' => 'America/Los_Angeles',
    'las vegas' => 'America/Los_Angeles',
    'alaska' => 'America/Anchorage',
    'hawaii' => 'Pacific/Honolulu',
    'massachusetts' => 'America/New_York',
    'new jersey' => 'America/New_York',
    'connecticut' => 'America/New_York',
    'pennsylvania' => 'America/New_York',
    'ohio' => 'America/New_York',
    'michigan' => 'America/Detroit',
    'georgia' => 'America/New_York',
    'north carolina' => 'America/New_York',
    'virginia' => 'America/New_York',
    'minnesota' => 'America/Chicago',
    'wisconsin' => 'America/Chicago',
    'missouri' => 'America/Chicago',
    'tennessee' => 'America/Chicago',
    'indiana' => 'America/Indiana/Indianapolis',
    'utah' => 'America/Denver',
    'new mexico' => 'America/Denver',
    'toronto' => 'America/Toronto',
    'vancouver' => 'America/Vancouver',
    'montreal' => 'America/Montreal',
    'calgary' => 'America/Edmonton',
    'ottawa' => 'America/Toronto',
    'ontario' => 'America/Toronto',
    'british columbia' => 'America/Vancouver',
    'alberta' => 'America/Edmonton',
    'quebec' => 'America/Montreal',
    'london' => 'Europe/London',
    'manchester' => 'Europe/London',
    'birmingham' => 'Europe/London',
    'edinburgh' => 'Europe/London',
    'glasgow' => 'Europe/London',
    'uk' => 'Europe/London',
    'united kingdom' => 'Europe/London',
    'england' => 'Europe/London',
    'scotland' => 'Europe/London',
    'wales' => 'Europe/London',
    'ireland' => 'Europe/Dublin',
    'dublin' => 'Europe/Dublin',
    'germany' => 'Europe/Berlin',
    'deutschland' => 'Europe/Berlin',
    'berlin' => 'Europe/Berlin',
    'munich' => 'Europe/Berlin',
    'münchen' => 'Europe/Berlin',
    'frankfurt' => 'Europe/Berlin',
    'hamburg' => 'Europe/Berlin',
    'cologne' => 'Europe/Berlin',
    'köln' => 'Europe/Berlin',
    'düsseldorf' => 'Europe/Berlin',
    'stuttgart' => 'Europe/Berlin',
    'austria' => 'Europe/Vienna',
    'österreich' => 'Europe/Vienna',
    'vienna' => 'Europe/Vienna',
    'wien' => 'Europe/Vienna',
    'switzerland' => 'Europe/Zurich',
    'schweiz' => 'Europe/Zurich',
    'zurich' => 'Europe/Zurich',
    'zürich' => 'Europe/Zurich',
    'geneva' => 'Europe/Zurich',
    'genf' => 'Europe/Zurich',
    'bern' => 'Europe/Zurich',
    'basel' => 'Europe/Zurich',
    'france' => 'Europe/Paris',
    'paris' => 'Europe/Paris',
    'lyon' => 'Europe/Paris',
    'marseille' => 'Europe/Paris',
    'netherlands' => 'Europe/Amsterdam',
    'amsterdam' => 'Europe/Amsterdam',
    'rotterdam' => 'Europe/Amsterdam',
    'belgium' => 'Europe/Brussels',
    'brussels' => 'Europe/Brussels',
    'spain' => 'Europe/Madrid',
    'madrid' => 'Europe/Madrid',
    'barcelona' => 'Europe/Madrid',
    'italy' => 'Europe/Rome',
    'rome' => 'Europe/Rome',
    'milan' => 'Europe/Rome',
    'milano' => 'Europe/Rome',
    'portugal' => 'Europe/Lisbon',
    'lisbon' => 'Europe/Lisbon',
    'poland' => 'Europe/Warsaw',
    'warsaw' => 'Europe/Warsaw',
    'czech' => 'Europe/Prague',
    'prague' => 'Europe/Prague',
    'sweden' => 'Europe/Stockholm',
    'stockholm' => 'Europe/Stockholm',
    'norway' => 'Europe/Oslo',
    'oslo' => 'Europe/Oslo',
    'denmark' => 'Europe/Copenhagen',
    'copenhagen' => 'Europe/Copenhagen',
    'finland' => 'Europe/Helsinki',
    'helsinki' => 'Europe/Helsinki',
    'greece' => 'Europe/Athens',
    'athens' => 'Europe/Athens',
    'romania' => 'Europe/Bucharest',
    'bucharest' => 'Europe/Bucharest',
    'hungary' => 'Europe/Budapest',
    'budapest' => 'Europe/Budapest',
    'india' => 'Asia/Kolkata',
    'mumbai' => 'Asia/Kolkata',
    'delhi' => 'Asia/Kolkata',
    'bangalore' => 'Asia/Kolkata',
    'bengaluru' => 'Asia/Kolkata',
    'chennai' => 'Asia/Kolkata',
    'hyderabad' => 'Asia/Kolkata',
    'pune' => 'Asia/Kolkata',
    'japan' => 'Asia/Tokyo',
    'tokyo' => 'Asia/Tokyo',
    'osaka' => 'Asia/Tokyo',
    'china' => 'Asia/Shanghai',
    'beijing' => 'Asia/Shanghai',
    'shanghai' => 'Asia/Shanghai',
    'shenzhen' => 'Asia/Shanghai',
    'guangzhou' => 'Asia/Shanghai',
    'hong kong' => 'Asia/Hong_Kong',
    'singapore' => 'Asia/Singapore',
    'australia' => 'Australia/Sydney',
    'sydney' => 'Australia/Sydney',
    'melbourne' => 'Australia/Melbourne',
    'brisbane' => 'Australia/Brisbane',
    'perth' => 'Australia/Perth',
    'new zealand' => 'Pacific/Auckland',
    'auckland' => 'Pacific/Auckland',
    'wellington' => 'Pacific/Auckland',
    'south korea' => 'Asia/Seoul',
    'seoul' => 'Asia/Seoul',
    'taiwan' => 'Asia/Taipei',
    'taipei' => 'Asia/Taipei',
    'philippines' => 'Asia/Manila',
    'manila' => 'Asia/Manila',
    'indonesia' => 'Asia/Jakarta',
    'jakarta' => 'Asia/Jakarta',
    'thailand' => 'Asia/Bangkok',
    'bangkok' => 'Asia/Bangkok',
    'vietnam' => 'Asia/Ho_Chi_Minh',
    'malaysia' => 'Asia/Kuala_Lumpur',
    'kuala lumpur' => 'Asia/Kuala_Lumpur',
    'israel' => 'Asia/Jerusalem',
    'tel aviv' => 'Asia/Jerusalem',
    'uae' => 'Asia/Dubai',
    'dubai' => 'Asia/Dubai',
    'abu dhabi' => 'Asia/Dubai',
    'saudi arabia' => 'Asia/Riyadh',
    'riyadh' => 'Asia/Riyadh',
    'turkey' => 'Europe/Istanbul',
    'istanbul' => 'Europe/Istanbul',
    'brazil' => 'America/Sao_Paulo',
    'sao paulo' => 'America/Sao_Paulo',
    'rio de janeiro' => 'America/Sao_Paulo',
    'argentina' => 'America/Argentina/Buenos_Aires',
    'buenos aires' => 'America/Argentina/Buenos_Aires',
    'chile' => 'America/Santiago',
    'santiago' => 'America/Santiago',
    'colombia' => 'America/Bogota',
    'bogota' => 'America/Bogota',
    'mexico' => 'America/Mexico_City',
    'mexico city' => 'America/Mexico_City',
    'south africa' => 'Africa/Johannesburg',
    'johannesburg' => 'Africa/Johannesburg',
    'cape town' => 'Africa/Johannesburg',
    'nigeria' => 'Africa/Lagos',
    'lagos' => 'Africa/Lagos',
    'kenya' => 'Africa/Nairobi',
    'nairobi' => 'Africa/Nairobi',
    'egypt' => 'Africa/Cairo',
    'cairo' => 'Africa/Cairo',
    'russia' => 'Europe/Moscow',
    'moscow' => 'Europe/Moscow',
    'st petersburg' => 'Europe/Moscow',
    'saint petersburg' => 'Europe/Moscow'
  }.freeze

  COUNTRY_CODE_MAP = {
    'us' => 'America/New_York',
    'usa' => 'America/New_York',
    'ca' => 'America/Toronto',
    'gb' => 'Europe/London',
    'de' => 'Europe/Berlin',
    'fr' => 'Europe/Paris',
    'it' => 'Europe/Rome',
    'es' => 'Europe/Madrid',
    'nl' => 'Europe/Amsterdam',
    'be' => 'Europe/Brussels',
    'at' => 'Europe/Vienna',
    'ch' => 'Europe/Zurich',
    'se' => 'Europe/Stockholm',
    'no' => 'Europe/Oslo',
    'dk' => 'Europe/Copenhagen',
    'fi' => 'Europe/Helsinki',
    'pl' => 'Europe/Warsaw',
    'cz' => 'Europe/Prague',
    'ie' => 'Europe/Dublin',
    'pt' => 'Europe/Lisbon',
    'gr' => 'Europe/Athens',
    'au' => 'Australia/Sydney',
    'nz' => 'Pacific/Auckland',
    'jp' => 'Asia/Tokyo',
    'cn' => 'Asia/Shanghai',
    'in' => 'Asia/Kolkata',
    'sg' => 'Asia/Singapore',
    'hk' => 'Asia/Hong_Kong',
    'kr' => 'Asia/Seoul',
    'tw' => 'Asia/Taipei',
    'br' => 'America/Sao_Paulo',
    'mx' => 'America/Mexico_City',
    'ar' => 'America/Argentina/Buenos_Aires',
    'za' => 'Africa/Johannesburg',
    'ae' => 'Asia/Dubai',
    'il' => 'Asia/Jerusalem',
    'ru' => 'Europe/Moscow',
    'tr' => 'Europe/Istanbul'
  }.freeze

  def self.resolve(location)
    new(location).resolve
  end

  def initialize(location)
    @location = location
  end

  def resolve
    return nil if @location.blank?

    normalized = normalize_location(@location)

    timezone = LOCATION_TIMEZONE_MAP[normalized]
    return timezone if timezone.present?

    LOCATION_TIMEZONE_MAP.each do |pattern, tz|
      return tz if normalized.match?(/\b#{Regexp.escape(pattern)}\b/)
    end

    COUNTRY_CODE_MAP.each do |code, tz|
      return tz if normalized.match?(/\b#{Regexp.escape(code)}\b/)
    end

    parts = @location.split(',').map(&:strip).map { |p| normalize_location(p) }
    parts.each do |part|
      timezone = LOCATION_TIMEZONE_MAP[part]
      return timezone if timezone.present?

      timezone = COUNTRY_CODE_MAP[part]
      return timezone if timezone.present?
    end

    nil
  end

  private

  def normalize_location(location)
    return '' if location.blank?

    location
      .downcase
      .gsub(/[^\p{L}\s]/, '')
      .gsub(/\s+/, ' ')
      .strip
  end
end
