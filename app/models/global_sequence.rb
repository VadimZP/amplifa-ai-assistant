# frozen_string_literal: true

class GlobalSequence < ApplicationRecord
  has_many :sequence_steps, dependent: :destroy
  has_many :agents, dependent: :nullify

  validates :name, presence: true
end
