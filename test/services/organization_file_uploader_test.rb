# frozen_string_literal: true

require 'test_helper'

class OrganizationFileUploaderTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
    @admin = accounts(:amplifa_admin)
  end

  test 'rejects files larger than 25MB' do
    uploader = OrganizationFileUploader.new(@organization, @admin)
    file = sized_file(26.megabytes)

    error = assert_raises(OrganizationFileUploader::ValidationError) do
      uploader.upload(file, category: 'lead_list', applies_to_all_playbooks: true)
    end

    assert_equal 'File too large (max 25MB)', error.message
  end

  private

  def sized_file(size)
    Object.new.tap do |file|
      file.define_singleton_method(:size) { size }
    end
  end
end
