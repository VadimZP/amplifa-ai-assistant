# frozen_string_literal: true

class PersonEmailAlias < ApplicationRecord
  belongs_to :person

  before_validation :normalize_email

  validates :email, presence: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: 'must be a valid email address' },
                    uniqueness: { case_sensitive: false }
  validate :email_differs_from_primary_email
  validate :email_not_used_by_another_person

  def self.normalize_email_value(value)
    value.to_s.strip.downcase.presence
  end

  private

  def normalize_email
    self.email = self.class.normalize_email_value(email)
  end

  def email_differs_from_primary_email
    return if person.blank? || email.blank?
    return unless person.email.casecmp?(email)

    errors.add(:email, 'must differ from the person primary email')
  end

  def email_not_used_by_another_person
    return if email.blank?

    existing_person = Person.where('LOWER(email) = ?', email.downcase).where.not(id: person_id).first
    return unless existing_person

    errors.add(:email, 'is already used as a person primary email')
  end
end
