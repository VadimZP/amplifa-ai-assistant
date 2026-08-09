# frozen_string_literal: true

# Assigns a knowledge-base playbook attachment to a specific playbook.
class PlaybookAttachmentPlaybook < ApplicationRecord
  belongs_to :playbook_attachment
  belongs_to :playbook

  validates :playbook_id, uniqueness: { scope: :playbook_attachment_id }
end
