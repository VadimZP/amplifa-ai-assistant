# frozen_string_literal: true

class Company < ApplicationRecord
  has_many :people, foreign_key: :current_company_id, dependent: :nullify, inverse_of: :current_company

  validates :name, presence: true
  validates :normalized_domain, uniqueness: true, allow_blank: true

  before_validation :normalize_company_identity

  def self.normalize_domain(value)
    return nil if value.blank?

    normalized = value.to_s.strip.downcase
    normalized = "https://#{normalized}" unless normalized.match?(%r{\Ahttps?://}i)
    host = URI.parse(normalized).host&.downcase
    host&.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    nil
  end

  def self.normalize_website_url(value)
    return nil if value.blank?

    normalized = value.to_s.strip
    normalized = "https://#{normalized}" unless normalized.start_with?('http://', 'https://')
    normalized.chomp('/')
  end

  def self.find_or_create_from_identity(name:, website_url:)
    normalized_domain = normalize_domain(website_url)
    normalized_website_url = normalize_website_url(website_url)
    display_name = name.presence || normalized_domain || normalized_website_url
    return nil if display_name.blank?

    company = if normalized_domain.present?
                find_or_initialize_by(normalized_domain: normalized_domain)
              else
                new
              end

    company.assign_attributes(
      name: company.name.presence || display_name,
      domain: company.domain.presence || normalized_domain,
      normalized_domain: company.normalized_domain.presence || normalized_domain,
      website_url: company.website_url.presence || normalized_website_url
    )

    company.save! if company.new_record? || company.changed?
    company
  end

  def website
    website_url
  end

  private

  def normalize_company_identity
    self.website_url = self.class.normalize_website_url(website_url)
    self.normalized_domain = self.class.normalize_domain(website_url || domain)
    self.domain = normalized_domain if domain.blank? && normalized_domain.present?
    self.name = normalized_domain if name.blank? && normalized_domain.present?
  end
end
