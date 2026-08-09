# frozen_string_literal: true

# Assigns an organization file to a specific playbook.
class OrganizationFilePlaybook < ApplicationRecord
  belongs_to :organization_file
  belongs_to :playbook

  validates :playbook_id, uniqueness: { scope: :organization_file_id }
end
