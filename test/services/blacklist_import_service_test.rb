# frozen_string_literal: true

require "test_helper"

class BlacklistImportServiceTest < ActiveSupport::TestCase
  setup do
    @organization = organizations(:acme)
    @created_by = accounts(:customer_admin)
  end

  # === Basic Import Tests ===

  # WHY: Verify service creates blacklist entries from text input
  test "imports emails from text input" do
    input = "spam@example.com\nbad@test.com"

    assert_difference "Blacklist.count", 2 do
      result = BlacklistImportService.new(
        organization: @organization,
        created_by: @created_by
      ).call(input)

      assert_equal 2, result[:created_count]
      assert_equal 0, result[:skipped_count]
    end
  end

  # WHY: Verify domains are detected and imported correctly
  test "imports domains from text input" do
    input = "spammer.com\nbad-domain.org"

    assert_difference "Blacklist.count", 2 do
      result = BlacklistImportService.new(
        organization: @organization,
        created_by: @created_by
      ).call(input)

      assert_equal 2, result[:created_count]
    end

    assert Blacklist.exists?(value: "spammer.com", value_type: "domain")
    assert Blacklist.exists?(value: "bad-domain.org", value_type: "domain")
  end

  # WHY: Verify mixed emails and domains are correctly detected
  test "imports mixed emails and domains" do
    input = "spam@example.com\nspammer.com\nbad@test.org"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 3, result[:created_count]
    assert Blacklist.exists?(value: "spam@example.com", value_type: "email")
    assert Blacklist.exists?(value: "spammer.com", value_type: "domain")
    assert Blacklist.exists?(value: "bad@test.org", value_type: "email")
  end

  # === Duplicate Handling Tests ===

  # WHY: Duplicates should be skipped to avoid unique constraint errors
  test "skips duplicate entries" do
    Blacklist.create!(
      organization: @organization,
      created_by: @created_by,
      value: "existing@example.com",
      value_type: "email",
      source: "manual"
    )

    input = "existing@example.com\nnew@example.com"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 1, result[:created_count]
    assert_equal 1, result[:skipped_count]
  end

  # WHY: Same value can exist in different organizations
  test "allows same value in different organizations" do
    other_org = organizations(:growth_lab)

    Blacklist.create!(
      organization: other_org,
      created_by: @created_by,
      value: "shared@example.com",
      value_type: "email",
      source: "manual"
    )

    input = "shared@example.com"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 1, result[:created_count]
  end

  # === Validation Tests ===

  # WHY: Invalid formats should be reported but not stop import
  test "handles invalid email formats" do
    input = "valid@example.com\nnot-an-email\nalso-invalid@\nanother@valid.com"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 2, result[:created_count]
    assert_equal 2, result[:invalid_count]
    assert result[:errors].length >= 2
  end

  # WHY: Invalid domains should be tracked as invalid
  test "handles invalid domain formats" do
    input = "valid-domain.com\ninvalid\n-starts-with-dash.com\nalso-valid.org"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 2, result[:created_count]
    assert result[:invalid_count] >= 1
  end

  # === Normalization Tests ===

  # WHY: Input should be normalized (lowercase, trimmed)
  test "normalizes values to lowercase and trimmed" do
    input = "  UPPERCASE@EXAMPLE.COM  \n  DOMAIN.COM  "

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 2, result[:created_count]
    assert Blacklist.exists?(value: "uppercase@example.com")
    assert Blacklist.exists?(value: "domain.com")
  end

  # === Edge Cases ===

  # WHY: Empty input should return empty results without error
  test "handles empty input" do
    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call("")

    assert_equal 0, result[:created_count]
    assert_equal 0, result[:skipped_count]
    assert_equal 0, result[:invalid_count]
  end

  # WHY: Nil input should be handled gracefully
  test "handles nil input" do
    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(nil)

    assert_equal 0, result[:created_count]
  end

  # WHY: Blank lines should be skipped without counting as errors
  test "handles input with blank lines" do
    input = "valid@example.com\n\n\nanother@valid.com\n  \n"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 2, result[:created_count]
    assert_equal 0, result[:invalid_count]
  end

  # WHY: Windows-style line endings should work
  test "handles Windows-style line endings" do
    input = "first@example.com\r\nsecond@example.com\r\nthird.com"

    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call(input)

    assert_equal 3, result[:created_count]
  end

  # === Source Tracking Tests ===

  # WHY: Source should be customizable for different import methods
  test "uses specified source for entries" do
    result = BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by,
      source: "unsubscribe"
    ).call("unsubscribed@example.com")

    entry = Blacklist.find_by(value: "unsubscribed@example.com")
    assert_equal "unsubscribe", entry.source
  end

  # WHY: Default source should be 'import'
  test "defaults source to import" do
    BlacklistImportService.new(
      organization: @organization,
      created_by: @created_by
    ).call("default-source@example.com")

    entry = Blacklist.find_by(value: "default-source@example.com")
    assert_equal "import", entry.source
  end

  # === Global Blacklist Tests ===

  # WHY: Should support creating global entries (organization = nil)
  test "creates global blacklist entries when organization is nil" do
    amplifa_admin = accounts(:amplifa_admin)

    result = BlacklistImportService.new(
      organization: nil,
      created_by: amplifa_admin
    ).call("global-spam@example.com")

    assert_equal 1, result[:created_count]

    entry = Blacklist.find_by(value: "global-spam@example.com")
    assert_nil entry.organization_id
    assert entry.global?
  end
end
