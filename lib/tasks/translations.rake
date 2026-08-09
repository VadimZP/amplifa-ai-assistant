# frozen_string_literal: true

# Rake tasks for translation file management and analysis.
# Used to identify duplicate translation values across locale files.

namespace :translations do
  desc "Find duplicate translation values across en.yml and de.yml with safe/unsafe verdicts"
  task find_duplicates: :environment do
    require "yaml"

    # Dynamic namespace segments that should NEVER be consolidated
    DYNAMIC_SEGMENTS = %w[
      statuses roles types event_types outcomes sources
      categories interest_status comment_types delivery_statuses
    ].freeze

    en_file = Rails.root.join("config/locales/en.yml")
    de_file = Rails.root.join("config/locales/de.yml")

    unless File.exist?(en_file) && File.exist?(de_file)
      puts "❌ Error: Missing locale files"
      puts "  Expected: #{en_file}" unless File.exist?(en_file)
      puts "  Expected: #{de_file}" unless File.exist?(de_file)
      exit 1
    end

    en_data = YAML.load_file(en_file)
    de_data = YAML.load_file(de_file)

    # Flatten nested YAML hash into dot-separated key => value pairs
    flatten = ->(hash, prefix = "") do
      hash.each_with_object({}) do |(k, v), result|
        full_key = prefix.empty? ? k.to_s : "#{prefix}.#{k}"
        if v.is_a?(Hash)
          result.merge!(flatten.call(v, full_key))
        else
          result[full_key] = v
        end
      end
    end

    en_flat = flatten.call(en_data)
    de_flat = flatten.call(de_data)

    # Check if a key is inside a dynamic namespace
    in_dynamic_namespace = ->(key) do
      parts = key.split(".")
      parts.any? { |part| DYNAMIC_SEGMENTS.include?(part) }
    end

    # Check if a value contains interpolation variables
    has_interpolation = ->(value) do
      value.is_a?(String) && value.match?(/%\{[^}]+\}/)
    end

    # Identify existing admin.common and common keys
    existing_common = {}
    en_flat.each do |key, value|
      next unless value.is_a?(String)
      if key.match?(/\Aen\.admin\.common\./) || key.match?(/\Aen\.common\./)
        existing_common[value] ||= []
        existing_common[value] << key
      end
    end

    # Group keys by English value (only string values with 2+ occurrences)
    value_groups = en_flat.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(key, value), groups|
      next unless value.is_a?(String) && value.strip.length > 0
      groups[value] << key
    end

    duplicates = value_groups.select { |_v, keys| keys.length > 1 }

    # Classify each duplicate group
    safe = []
    unsafe = []
    excluded = []
    interpolation_flagged = []

    duplicates.each do |en_value, keys|
      # Check if ALL keys are in dynamic namespaces
      dynamic_keys = keys.select { |k| in_dynamic_namespace.call(k) }
      non_dynamic_keys = keys - dynamic_keys

      # If all keys are dynamic, exclude the whole group
      if non_dynamic_keys.empty?
        excluded << { value: en_value, keys: keys, reason: "All keys in dynamic namespaces" }
        next
      end

      # Flag interpolation
      if has_interpolation.call(en_value)
        interpolation_flagged << { value: en_value, keys: keys }
        next
      end

      # Check German consistency for non-dynamic keys
      de_values = non_dynamic_keys.filter_map do |en_key|
        # Convert en.xxx to de.xxx
        de_key = en_key.sub(/\Aen\./, "de.")
        de_flat[de_key]
      end

      german_consistent = de_values.uniq.length <= 1

      # Build entry
      entry = {
        value: en_value,
        keys: keys,
        dynamic_keys: dynamic_keys,
        non_dynamic_keys: non_dynamic_keys,
        german_values: de_values.uniq,
        german_consistent: german_consistent,
        has_common_equivalent: existing_common.key?(en_value)
      }

      if german_consistent
        safe << entry
      else
        unsafe << entry
      end
    end

    # Sort by occurrence count (most duplicated first)
    safe.sort_by! { |e| -e[:keys].length }
    unsafe.sort_by! { |e| -e[:keys].length }
    excluded.sort_by! { |e| -e[:keys].length }

    # Output
    puts "=" * 70
    puts "  Translation Duplicate Analysis"
    puts "=" * 70
    puts ""
    puts "  Source files:"
    puts "    English: #{en_file} (#{en_flat.count} keys)"
    puts "    German:  #{de_file} (#{de_flat.count} keys)"
    puts ""

    total_safe_keys = safe.sum { |e| e[:non_dynamic_keys].length }
    total_unsafe_keys = unsafe.sum { |e| e[:non_dynamic_keys].length }
    total_excluded_keys = excluded.sum { |e| e[:keys].length }

    puts "-" * 70
    puts "  SUMMARY"
    puts "-" * 70
    puts ""
    puts "  Total duplicate groups:       #{duplicates.count}"
    puts "  ✅ SAFE to consolidate:        #{safe.count} groups (#{total_safe_keys} keys)"
    puts "  ⚠️  UNSAFE (German divergent):  #{unsafe.count} groups (#{total_unsafe_keys} keys)"
    puts "  🚫 EXCLUDED (dynamic):         #{excluded.count} groups (#{total_excluded_keys} keys)"
    puts "  📝 INTERPOLATION (manual):     #{interpolation_flagged.count} groups"
    puts ""
    puts "  Keys with existing common.*:  #{safe.count { |e| e[:has_common_equivalent] }}"
    puts ""

    # SAFE section
    puts "=" * 70
    puts "  ✅ SAFE TO CONSOLIDATE (#{safe.count} groups)"
    puts "  German translations match across all instances"
    puts "=" * 70
    puts ""

    safe.each_with_index do |entry, idx|
      common_marker = entry[:has_common_equivalent] ? " [HAS COMMON EQUIVALENT]" : ""
      puts "  #{idx + 1}. \"#{entry[:value]}\" (#{entry[:keys].length} keys)#{common_marker}"

      if entry[:german_values].any?
        puts "     German: \"#{entry[:german_values].first}\""
      else
        puts "     German: (no translations found)"
      end

      entry[:non_dynamic_keys].each do |key|
        puts "     - #{key}"
      end

      if entry[:dynamic_keys].any?
        entry[:dynamic_keys].each do |key|
          puts "     - #{key} [DYNAMIC - skip]"
        end
      end

      puts ""
    end

    # UNSAFE section
    if unsafe.any?
      puts "=" * 70
      puts "  ⚠️  UNSAFE — German Translations Diverge (#{unsafe.count} groups)"
      puts "  These share English values but have DIFFERENT German translations"
      puts "=" * 70
      puts ""

      unsafe.each_with_index do |entry, idx|
        puts "  #{idx + 1}. \"#{entry[:value]}\" (#{entry[:keys].length} keys)"
        puts "     German values: #{entry[:german_values].map { |v| "\"#{v}\"" }.join(", ")}"

        entry[:non_dynamic_keys].each do |key|
          de_key = key.sub(/\Aen\./, "de.")
          de_val = de_flat[de_key]
          puts "     - #{key} → DE: #{de_val.nil? ? "(missing)" : "\"#{de_val}\""}"
        end

        if entry[:dynamic_keys].any?
          entry[:dynamic_keys].each do |key|
            puts "     - #{key} [DYNAMIC - skip]"
          end
        end

        puts ""
      end
    end

    # EXCLUDED section
    if excluded.any?
      puts "=" * 70
      puts "  🚫 EXCLUDED — Dynamic Namespaces (#{excluded.count} groups)"
      puts "  All keys in these groups are within dynamic namespaces"
      puts "=" * 70
      puts ""

      excluded.first(20).each_with_index do |entry, idx|
        puts "  #{idx + 1}. \"#{entry[:value]}\" (#{entry[:keys].length} keys)"
        entry[:keys].first(5).each do |key|
          puts "     - #{key}"
        end
        puts "     ... and #{entry[:keys].length - 5} more" if entry[:keys].length > 5
        puts ""
      end

      if excluded.length > 20
        puts "  ... and #{excluded.length - 20} more excluded groups"
        puts ""
      end
    end

    # INTERPOLATION section
    if interpolation_flagged.any?
      puts "=" * 70
      puts "  📝 INTERPOLATION — Manual Review Required (#{interpolation_flagged.count} groups)"
      puts "  These values contain %{...} variables and need manual verification"
      puts "=" * 70
      puts ""

      interpolation_flagged.each_with_index do |entry, idx|
        puts "  #{idx + 1}. \"#{entry[:value]}\" (#{entry[:keys].length} keys)"
        entry[:keys].first(5).each do |key|
          puts "     - #{key}"
        end
        puts "     ... and #{entry[:keys].length - 5} more" if entry[:keys].length > 5
        puts ""
      end
    end

    puts "=" * 70
    puts "  Analysis complete."
    puts "=" * 70
  end
end

module LocaleTranslationTools
  module_function

  INTERPOLATION_PATTERN = /%\{[^}]+\}/
  MOJIBAKE_PATTERN = /[ÃÂâ]/

  def locale_file(locale)
    Rails.root.join("config/locales/#{locale}.yml")
  end

  def load_locale_root(locale)
    path = locale_file(locale)
    raise ArgumentError, "Missing locale file: #{path}" unless File.exist?(path)

    root = load_locale_data(locale)[locale.to_s]
    raise ArgumentError, "Missing top-level locale key #{locale.inspect} in #{path}" unless root.is_a?(Hash)

    root
  end

  def load_locale_data(locale)
    path = locale_file(locale)
    raise ArgumentError, "Missing locale file: #{path}" unless File.exist?(path)

    YAML.safe_load_file(path, aliases: true, permitted_classes: [Date, Time])
  end

  def flatten_leaves(value, prefix = [], result = {})
    if value.is_a?(Hash)
      value.each do |key, child|
        flatten_leaves(child, prefix + [key.to_s], result)
      end
    else
      result[prefix.join(".")] = value
    end

    result
  end

  def interpolation_tokens(value)
    return [] unless value.is_a?(String)

    value.scan(INTERPOLATION_PATTERN).sort
  end

  def normalize_model_text(value)
    return value unless value.is_a?(String) && value.match?(MOJIBAKE_PATTERN)

    normalized = value.encode('ISO-8859-1').force_encoding('UTF-8')
    normalized.valid_encoding? ? normalized : value
  rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
    value
  end

  def value_type(value)
    case value
    when String then "string"
    when Integer then "integer"
    when Float then "float"
    when TrueClass, FalseClass then "boolean"
    when NilClass then "nil"
    when Array then "array"
    else value.class.name
    end
  end

  def locale_pair(source_locale, target_locale)
    source_root = load_locale_root(source_locale)
    target_root = load_locale_root(target_locale)

    [flatten_leaves(source_root), flatten_leaves(target_root)]
  end

  def nested_value(hash, key)
    key.split(".").reduce(hash) do |current, segment|
      return nil unless current.is_a?(Hash)

      current[segment]
    end
  end

  def set_nested_value!(hash, key, value)
    segments = key.split(".")
    leaf = segments.pop
    parent = segments.reduce(hash) do |current, segment|
      child = current[segment]
      raise ArgumentError, "Missing or non-hash parent for #{key.inspect} at #{segment.inspect}" unless child.is_a?(Hash)

      child
    end

    parent[leaf] = value
  end

  def create_nested_value!(hash, key, value)
    segments = key.split(".")
    leaf = segments.pop
    parent = segments.reduce(hash) do |current, segment|
      current[segment] ||= {}
      raise ArgumentError, "Non-hash parent for #{key.inspect} at #{segment.inspect}" unless current[segment].is_a?(Hash)

      current[segment]
    end

    parent[leaf] = value
  end

  def parse_positive_integer(value, default)
    return default if value.blank?

    Integer(value).tap do |integer|
      raise ArgumentError, "must be positive" unless integer.positive?
    end
  end

  def parse_statuses(value, default)
    statuses = value.to_s.split(",").map { |status| status.strip.downcase }.reject(&:blank?)
    statuses.presence || default
  end

  def parse_key_prefixes(value)
    value.to_s.split(",").map do |prefix|
      normalized = prefix.strip
      next if normalized.blank?

      normalized.end_with?(".") ? normalized : "#{normalized}."
    end.compact
  end
end

namespace :translations do
  desc "Audit locale completeness against a source locale: rake translations:audit_locale[en,de]"
  task :audit_locale, [:source_locale, :target_locale] => :environment do |_task, args|
    source_locale = (args[:source_locale] || ENV["SOURCE_LOCALE"] || "en").to_s
    target_locale = (args[:target_locale] || ENV["TARGET_LOCALE"]).to_s

    if target_locale.blank?
      warn "Usage: mise exec -- rake 'translations:audit_locale[en,de]'"
      warn "Or: SOURCE_LOCALE=en TARGET_LOCALE=de mise exec -- rake translations:audit_locale"
      exit 2
    end

    source_flat, target_flat = LocaleTranslationTools.locale_pair(source_locale, target_locale)

    source_keys = source_flat.keys.sort
    target_keys = target_flat.keys.sort
    shared_keys = source_keys & target_keys

    missing_keys = source_keys - target_keys
    extra_keys = target_keys - source_keys
    type_mismatches = shared_keys.filter_map do |key|
      source_type = LocaleTranslationTools.value_type(source_flat[key])
      target_type = LocaleTranslationTools.value_type(target_flat[key])
      next if source_type == target_type

      [key, source_type, target_type]
    end
    interpolation_mismatches = shared_keys.filter_map do |key|
      source_tokens = LocaleTranslationTools.interpolation_tokens(source_flat[key])
      target_tokens = LocaleTranslationTools.interpolation_tokens(target_flat[key])
      next if source_tokens == target_tokens

      [key, source_tokens, target_tokens]
    end

    puts "Locale coverage audit"
    puts "Source: #{source_locale} (#{source_keys.count} leaf keys)"
    puts "Target: #{target_locale} (#{target_keys.count} leaf keys)"
    puts "Missing keys: #{missing_keys.count}"
    puts "Extra keys: #{extra_keys.count}"
    puts "Type mismatches: #{type_mismatches.count}"
    puts "Interpolation mismatches: #{interpolation_mismatches.count}"

    if missing_keys.any?
      puts "\nMissing in #{target_locale}:"
      missing_keys.each { |key| puts "  - #{key}" }
    end

    if extra_keys.any?
      puts "\nExtra in #{target_locale}:"
      extra_keys.each { |key| puts "  - #{key}" }
    end

    if type_mismatches.any?
      puts "\nType mismatches:"
      type_mismatches.each do |key, source_type, target_type|
        puts "  - #{key}: #{source_locale}=#{source_type}, #{target_locale}=#{target_type}"
      end
    end

    if interpolation_mismatches.any?
      puts "\nInterpolation mismatches:"
      interpolation_mismatches.each do |key, source_tokens, target_tokens|
        puts "  - #{key}: #{source_locale}=#{source_tokens.inspect}, #{target_locale}=#{target_tokens.inspect}"
      end
    end

    issue_count = missing_keys.count + extra_keys.count + type_mismatches.count + interpolation_mismatches.count
    exit(issue_count.zero? ? 0 : 1)
  end

  desc "Fill missing target locale keys from a source locale: rake translations:fill_missing_locale[en,de]"
  task :fill_missing_locale, [:source_locale, :target_locale] => :environment do |_task, args|
    source_locale = (args[:source_locale] || ENV["SOURCE_LOCALE"] || "en").to_s
    target_locale = (args[:target_locale] || ENV["TARGET_LOCALE"]).to_s
    model = ENV.fetch("MODEL", "deepseek/deepseek-v4-pro")
    batch_size = LocaleTranslationTools.parse_positive_integer(ENV["BATCH_SIZE"], 25)
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])

    if target_locale.blank?
      warn "Usage: mise exec -- rake 'translations:fill_missing_locale[en,de]'"
      warn "Optional env: MODEL=deepseek/deepseek-v4-pro BATCH_SIZE=25 DRY_RUN=1"
      exit 2
    end

    source_data = LocaleTranslationTools.load_locale_data(source_locale)
    target_data = LocaleTranslationTools.load_locale_data(target_locale)
    source_root = source_data.fetch(source_locale)
    target_root = target_data.fetch(target_locale)
    source_flat = LocaleTranslationTools.flatten_leaves(source_root)
    target_flat = LocaleTranslationTools.flatten_leaves(target_root)

    missing = source_flat.keys.sort.filter_map do |key|
      next if target_flat.key?(key)

      { key: key, source: source_flat[key], string: source_flat[key].is_a?(String) }
    end

    string_missing = missing.select { |item| item[:string] }
    non_string_missing = missing.reject { |item| item[:string] }

    puts "Missing keys: #{missing.count}"
    puts "Missing string keys to translate: #{string_missing.count}"
    puts "Missing non-string keys to copy: #{non_string_missing.count}"

    if dry_run
      missing.each { |item| puts "  - #{item[:key]}" }
      exit 0
    end

    openrouter_api_key = ENV["OPENROUTER_API_KEY"].presence ||
                         Rails.application.credentials.dig(:openrouter, :api_key)
    if openrouter_api_key.blank? && string_missing.any?
      warn "Missing OpenRouter API key. Set OPENROUTER_API_KEY or Rails credentials openrouter.api_key."
      exit 2
    end

    target_path = LocaleTranslationTools.locale_file(target_locale)
    non_string_missing.each do |item|
      LocaleTranslationTools.create_nested_value!(target_root, item[:key], item[:source])
    end

    if non_string_missing.any? && string_missing.empty?
      File.write(target_path, YAML.dump(target_data))
      puts "Copied #{non_string_missing.count} non-string keys to #{target_path}"
    end

    schema = RubyLLM::Schema.create do
      array :translations, description: "#{target_locale} translations for the requested i18n keys" do
        object do
          string :key, description: "The exact i18n key from the request"
          string :translation, description: "The target-locale translation"
        end
      end
    end

    system_prompt = <<~PROMPT
      You translate Rails i18n UI strings from #{source_locale} to #{target_locale}.
      Use natural, concise UI copy appropriate for the target locale.
      For German, use formal address (Sie/Ihr) when addressing the user.
      Preserve every interpolation placeholder exactly, e.g. %{count}, %{name}, %{email}.
      Preserve product names, brand names, URLs, email examples, model names, code identifiers, and i18n key names.
      Return proper UTF-8 text. Never return mojibake such as Ã¼, Ã¤, Ã¶, ÃŸ, â, or Â·.
      Return one translation for every key, using the exact key string from the request.
    PROMPT

    total_batches = (string_missing.count.to_f / batch_size).ceil
    string_missing.each_slice(batch_size).with_index do |batch, batch_index|
      puts "Starting batch #{batch_index + 1}/#{total_batches} (#{batch.count} keys)"

      prompt = <<~PROMPT
        Translate these missing #{target_locale} locale values.

        #{batch.map { |item| "- #{item[:key]}: #{item[:source].inspect}" }.join("\n")}
      PROMPT

      response = RubyLLM.chat(model: model, provider: :openrouter, assume_model_exists: true)
                         .with_temperature(0.0)
                         .with_instructions(system_prompt)
                         .with_schema(schema)
                         .ask(prompt)

      translated = Array(response.content.fetch("translations")).index_by { |row| row.fetch("key") }
      batch.each do |item|
        row = translated[item[:key]]
        raise "Batch #{batch_index + 1}: missing translation for #{item[:key]}" unless row

        translation = LocaleTranslationTools.normalize_model_text(row.fetch("translation").to_s)
        source_placeholders = LocaleTranslationTools.interpolation_tokens(item[:source])
        translation_placeholders = LocaleTranslationTools.interpolation_tokens(translation)
        if source_placeholders != translation_placeholders
          raise "Batch #{batch_index + 1}: placeholder mismatch for #{item[:key]} source=#{source_placeholders.inspect} translation=#{translation_placeholders.inspect}"
        end

        LocaleTranslationTools.create_nested_value!(target_root, item[:key], translation)
      end

      File.write(target_path, YAML.dump(target_data))
      puts "Finished batch #{batch_index + 1}/#{total_batches}; wrote #{target_path}"
    end

    puts "Updated #{target_path}"
  end

  desc "Review translation quality with RubyLLM/OpenRouter: rake translations:review_locale_quality[en,de]"
  task :review_locale_quality, [:source_locale, :target_locale] => :environment do |_task, args|
    require "json"
    require "set"

    source_locale = (args[:source_locale] || ENV["SOURCE_LOCALE"] || "en").to_s
    target_locale = (args[:target_locale] || ENV["TARGET_LOCALE"]).to_s
    model = ENV.fetch("MODEL", "deepseek/deepseek-v4-pro")
    limit = LocaleTranslationTools.parse_positive_integer(ENV["LIMIT"], 25)
    key_pattern = ENV["KEY_PATTERN"].present? ? Regexp.new(ENV["KEY_PATTERN"]) : nil
    excluded_key_prefixes = LocaleTranslationTools.parse_key_prefixes(ENV["EXCLUDE_KEY_PREFIXES"])
    report_path = Pathname.new(ENV.fetch("REPORT", Rails.root.join("tmp/locale_quality_#{source_locale}_#{target_locale}.jsonl").to_s))
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV["DRY_RUN"])
    overwrite = ActiveModel::Type::Boolean.new.cast(ENV["OVERWRITE"])

    if target_locale.blank?
      warn "Usage: mise exec -- rake 'translations:review_locale_quality[en,de]'"
      warn "Optional env: MODEL=deepseek/deepseek-v4-pro LIMIT=25 KEY_PATTERN='customer_settings\\.' EXCLUDE_KEY_PREFIXES=admin REPORT=tmp/report.jsonl DRY_RUN=1 OVERWRITE=1"
      exit 2
    end

    source_flat, target_flat = LocaleTranslationTools.locale_pair(source_locale, target_locale)
    completed_keys = Set.new
    if report_path.exist? && !overwrite
      report_path.each_line.with_index(1) do |line, line_number|
        next if line.strip.blank?

        row = JSON.parse(line)
        completed_keys << row["key"].to_s if row["key"].present?
      rescue JSON::ParserError => e
        warn "Invalid JSON in existing report #{report_path} line #{line_number}: #{e.message}"
        exit 2
      end
    end

    all_pairs = source_flat.keys.sort.filter_map do |key|
      source_value = source_flat[key]
      target_value = target_flat[key]
      next unless source_value.is_a?(String) && target_value.is_a?(String)
      next if key_pattern && !key.match?(key_pattern)
      next if excluded_key_prefixes.any? { |prefix| key.start_with?(prefix) }

      [key, source_value, target_value]
    end

    pairs = all_pairs.reject { |key, _source_value, _target_value| completed_keys.include?(key) }.first(limit)

    if pairs.empty?
      puts "No pending string translation pairs matched."
      puts "Matched keys: #{all_pairs.count}"
      puts "Already reviewed: #{completed_keys.count}" unless completed_keys.empty?
      exit 0
    end

    if dry_run
      puts "Locale quality review dry run"
      puts "Source: #{source_locale}"
      puts "Target: #{target_locale}"
      puts "Model: #{model}"
      puts "Matched keys: #{all_pairs.count}"
      puts "Already reviewed: #{completed_keys.count}"
      puts "Excluded prefixes: #{excluded_key_prefixes.join(", ")}" if excluded_key_prefixes.any?
      puts "Keys that would be reviewed now: #{pairs.count}"
      pairs.each { |key, _source_value, _target_value| puts "  - #{key}" }
      exit 0
    end

    openrouter_api_key = ENV["OPENROUTER_API_KEY"].presence ||
                         Rails.application.credentials.dig(:openrouter, :api_key)
    if openrouter_api_key.blank?
      warn "Missing OpenRouter API key. Set OPENROUTER_API_KEY or Rails credentials openrouter.api_key."
      exit 2
    end

    report_path.dirname.mkpath

    schema = RubyLLM::Schema.create do
      string :status, description: "One of: ok, bad, unclear", enum: %w[ok bad unclear]
      string :issue, description: "Short explanation. Empty string when status is ok."
      string :suggested_translation, description: "Improved target translation, or the current translation if status is ok."
    end

    system_prompt = <<~PROMPT
      You review Rails i18n translations one key at a time.
      Decide whether the target translation is accurate, natural, idiomatic UI copy for the target locale, and appropriate for the i18n key path.
      Preserve every interpolation placeholder exactly, such as %{count} or %{name}.
      Preserve product names, brand names, URLs, email examples, code examples, and technical identifiers unless they are clearly user-facing prose.
      Return proper UTF-8 German text. Never return mojibake such as Ã¼, Ã¤, Ã¶, ÃŸ, â, or Â·.
      Return status ok when the translation is good, bad when it should be changed, and unclear when more product context is needed.
    PROMPT

    puts "Locale quality review"
    puts "Source: #{source_locale}"
    puts "Target: #{target_locale}"
    puts "Model: #{model}"
    puts "Matched keys: #{all_pairs.count}"
    puts "Already reviewed: #{completed_keys.count}"
    puts "Excluded prefixes: #{excluded_key_prefixes.join(", ")}" if excluded_key_prefixes.any?
    puts "Keys this run: #{pairs.count}"
    puts "Report: #{report_path}"
    puts "Mode: #{overwrite ? "overwrite" : "append/resume"}"
    puts "-" * 60

    status_counts = Hash.new(0)

    File.open(report_path, overwrite ? "w" : "a") do |report|
      pairs.each_with_index do |(key, source_value, target_value), index|
        prompt = <<~PROMPT
          Key: #{key}
          Source locale: #{source_locale}
          Target locale: #{target_locale}

          Source text:
          #{source_value}

          Current target translation:
          #{target_value}
        PROMPT

        response = RubyLLM.chat(model: model, provider: :openrouter, assume_model_exists: true)
                           .with_temperature(0.0)
                           .with_instructions(system_prompt)
                           .with_schema(schema)
                           .ask(prompt)

        content = response.content
        status = content.fetch("status").to_s
        issue = content.fetch("issue", "").to_s
        suggestion = LocaleTranslationTools.normalize_model_text(content.fetch("suggested_translation", target_value).to_s)
        status_counts[status] += 1

        row = {
          key: key,
          source_locale: source_locale,
          target_locale: target_locale,
          source: source_value,
          target: target_value,
          status: status,
          issue: issue,
          suggested_translation: suggestion
        }
        report.puts(JSON.generate(row))

        puts format("[%<index>d/%<total>d] %<status>s %<key>s", index: index + 1, total: pairs.count, status: status.upcase, key: key)
        puts "  #{issue}" if issue.present?
      end
    end

    puts "-" * 60
    puts "Summary: #{status_counts.sort.map { |status, count| "#{status}=#{count}" }.join(", ")}"
    puts "Report written to #{report_path}"
    exit(status_counts["bad"].positive? ? 1 : 0)
  end

  desc "Apply bad/unclear suggestions from a locale quality JSONL report: rake translations:apply_quality_report[de,tmp/report.jsonl]"
  task :apply_quality_report, [:target_locale, :report_path] => :environment do |_task, args|
    require "json"

    target_locale = (args[:target_locale] || ENV["TARGET_LOCALE"]).to_s
    report_path = Pathname.new((args[:report_path] || ENV["REPORT"]).to_s)
    apply = ActiveModel::Type::Boolean.new.cast(ENV["APPLY"])
    statuses = LocaleTranslationTools.parse_statuses(ENV["STATUSES"], %w[bad unclear])

    if target_locale.blank? || report_path.to_s.blank?
      warn "Usage: mise exec -- rake 'translations:apply_quality_report[de,tmp/locale_quality_en_de.jsonl]'"
      warn "Dry-run is the default. Set APPLY=1 to write config/locales/<target_locale>.yml."
      warn "Optional env: STATUSES=bad,unclear"
      exit 2
    end

    unless report_path.exist?
      warn "Missing report file: #{report_path}"
      exit 2
    end

    data = LocaleTranslationTools.load_locale_data(target_locale)
    target_root = data.fetch(target_locale)
    target_path = LocaleTranslationTools.locale_file(target_locale)

    selected = []
    skipped = []

    report_path.each_line.with_index(1) do |line, line_number|
      next if line.strip.blank?

      row = JSON.parse(line)
      status = row["status"].to_s.downcase
      reviewer_decision = row["reviewer_decision"].to_s.downcase
      next unless statuses.include?(status) || reviewer_decision == "rejected"

      key = row.fetch("key")
      suggestion = LocaleTranslationTools.normalize_model_text(row["suggested_translation"].to_s)
      current_value = LocaleTranslationTools.nested_value(target_root, key)

      if suggestion.blank?
        skipped << [line_number, key, "blank suggested_translation"]
        next
      end

      unless current_value.is_a?(String)
        skipped << [line_number, key, "current value is not a string or key is missing"]
        next
      end

      if row["target"].present? && current_value != row["target"]
        skipped << [line_number, key, "stale report target does not match current locale value"]
        next
      end

      source_tokens = LocaleTranslationTools.interpolation_tokens(row["source"].to_s)
      suggestion_tokens = LocaleTranslationTools.interpolation_tokens(suggestion)
      if source_tokens != suggestion_tokens
        skipped << [line_number, key, "placeholder mismatch source=#{source_tokens.inspect} suggestion=#{suggestion_tokens.inspect}"]
        next
      end

      selected << {
        line_number: line_number,
        key: key,
        status: status,
        before: current_value,
        after: suggestion
      }
    rescue JSON::ParserError => e
      skipped << [line_number, "(invalid json)", e.message]
    end

    puts "Locale quality report apply"
    puts "Target: #{target_locale}"
    puts "Report: #{report_path}"
    puts "Statuses: #{statuses.join(", ")}"
    puts "Mode: #{apply ? "APPLY" : "DRY RUN"}"
    puts "Selected updates: #{selected.count}"
    puts "Skipped rows: #{skipped.count}"

    selected.each do |change|
      puts "\n#{change[:status].upcase} #{change[:key]}"
      puts "  - #{change[:before]}"
      puts "  + #{change[:after]}"
    end

    if skipped.any?
      puts "\nSkipped:"
      skipped.each do |line_number, key, reason|
        puts "  line #{line_number} #{key}: #{reason}"
      end
    end

    unless apply
      puts "\nDry run only. Re-run with APPLY=1 to write #{target_path}."
      exit(skipped.empty? ? 0 : 1)
    end

    selected.each do |change|
      LocaleTranslationTools.set_nested_value!(target_root, change[:key], change[:after])
    end

    backup_path = target_path.sub_ext(".yml.bak")
    FileUtils.cp(target_path, backup_path)
    File.write(target_path, YAML.dump(data))

    puts "\nApplied #{selected.count} updates to #{target_path}."
    puts "Backup written to #{backup_path}."
    exit(skipped.empty? ? 0 : 1)
  end

  desc "Generate static HTML review UI for locale quality JSONL: rake translations:quality_report_html[tmp/report.jsonl,tmp/report.html]"
  task :quality_report_html, [:report_path, :html_path] => :environment do |_task, args|
    require "cgi"
    require "json"

    report_path = Pathname.new((args[:report_path] || ENV["REPORT"]).to_s)
    html_path = Pathname.new((args[:html_path] || ENV["HTML"] || report_path.sub_ext(".html")).to_s)

    if report_path.to_s.blank?
      warn "Usage: mise exec -- rake 'translations:quality_report_html[tmp/locale_quality_en_de.jsonl,tmp/locale_quality_en_de.html]'"
      exit 2
    end

    unless report_path.exist?
      warn "Missing report file: #{report_path}"
      exit 2
    end

    rows = []
    report_path.each_line.with_index(1) do |line, line_number|
      next if line.strip.blank?

      rows << JSON.parse(line).merge("line_number" => line_number)
    rescue JSON::ParserError => e
      warn "Invalid JSON in #{report_path} line #{line_number}: #{e.message}"
      exit 2
    end

    status_counts = rows.each_with_object(Hash.new(0)) { |row, counts| counts[row["status"].to_s] += 1 }
    payload = JSON.generate(rows)

    html = <<~HTML
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Locale Quality Review</title>
        <style>
          :root { color-scheme: dark; --bg: #111318; --panel: #191d24; --muted: #9aa4b2; --text: #edf2f7; --border: #2b3240; --accent: #67e8f9; --bad: #f87171; --unclear: #fbbf24; --ok: #34d399; }
          * { box-sizing: border-box; }
          body { margin: 0; background: var(--bg); color: var(--text); font: 14px/1.45 system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
          header { position: sticky; top: 0; z-index: 5; background: rgba(17,19,24,.96); border-bottom: 1px solid var(--border); padding: 18px 24px; backdrop-filter: blur(8px); }
          h1 { margin: 0 0 8px; font-size: 22px; }
          .summary { color: var(--muted); display: flex; flex-wrap: wrap; gap: 12px; }
          main { display: grid; grid-template-columns: minmax(0, 1fr) 420px; gap: 18px; padding: 18px 24px 40px; }
          .toolbar, .feedback { background: var(--panel); border: 1px solid var(--border); border-radius: 14px; padding: 14px; }
          .toolbar { margin-bottom: 14px; display: grid; grid-template-columns: 1fr 160px 160px 160px; gap: 10px; align-items: end; }
          label { display: grid; gap: 5px; color: var(--muted); font-size: 12px; }
          input, select, textarea, button { border-radius: 9px; border: 1px solid var(--border); background: #0f1217; color: var(--text); padding: 9px 10px; font: inherit; }
          textarea { width: 100%; min-height: 90px; resize: vertical; }
          button { cursor: pointer; background: #202633; }
          button:hover { border-color: var(--accent); }
          .rows { display: grid; gap: 12px; }
          .row { background: var(--panel); border: 1px solid var(--border); border-radius: 14px; padding: 14px; }
          .row-header { display: flex; justify-content: space-between; gap: 12px; align-items: start; margin-bottom: 10px; }
          .key { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: var(--accent); overflow-wrap: anywhere; }
          .badge { padding: 3px 8px; border-radius: 999px; font-size: 12px; font-weight: 700; text-transform: uppercase; }
          .badge.ok { color: #06281d; background: var(--ok); }
          .badge.bad { color: #3b0606; background: var(--bad); }
          .badge.unclear { color: #352000; background: var(--unclear); }
          .grid { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; }
          .cell { border: 1px solid var(--border); border-radius: 10px; padding: 10px; background: #12161d; white-space: pre-wrap; overflow-wrap: anywhere; }
          .cell-title { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .08em; margin-bottom: 6px; }
          .issue { margin-top: 10px; color: var(--muted); }
          .actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 12px; }
          .actions button.active { border-color: var(--accent); box-shadow: 0 0 0 1px var(--accent) inset; }
          .custom-inline { flex: 1 1 280px; min-width: 220px; }
          .feedback { position: sticky; top: 100px; max-height: calc(100vh - 120px); overflow: auto; }
          .feedback textarea { min-height: 360px; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
          .feedback-actions { display: flex; gap: 8px; margin: 10px 0; }
          .empty { color: var(--muted); padding: 20px; text-align: center; border: 1px dashed var(--border); border-radius: 14px; }
          @media (max-width: 1100px) { main { grid-template-columns: 1fr; } .toolbar { grid-template-columns: 1fr 1fr; } .grid { grid-template-columns: 1fr; } .feedback { position: static; max-height: none; } }
        </style>
      </head>
      <body>
        <header>
          <h1>Locale Quality Review</h1>
          <div class="summary">
            <span>Report: #{CGI.escapeHTML(report_path.to_s)}</span>
            <span>Total: #{rows.count}</span>
            <span>OK: #{status_counts["ok"]}</span>
            <span>Bad: #{status_counts["bad"]}</span>
            <span>Unclear: #{status_counts["unclear"]}</span>
          </div>
        </header>
        <main>
          <section>
            <div class="toolbar">
              <label>Search <input id="search" type="search" placeholder="key or text"></label>
              <label>Status <select id="statusFilter"><option value="all">All</option><option value="ok">OK</option><option value="bad">Bad</option><option value="unclear">Unclear</option></select></label>
              <label>Decision <select id="decisionFilter"><option value="all">All</option><option value="undecided">Undecided</option><option value="accepted">Accepted</option><option value="rejected">Rejected</option></select></label>
              <label>Sort <select id="sortBy"><option value="status">Status: Bad, Unclear, OK</option><option value="key">Key A-Z</option><option value="decision">Decision</option></select></label>
            </div>
            <div id="rows" class="rows"></div>
          </section>
          <aside class="feedback">
            <h2>Feedback JSONL</h2>
            <p style="color: var(--muted);">Only rejected rows with replacement translations appear here. Accepted OK rows and accepted suggestions are omitted.</p>
            <div class="feedback-actions">
              <button id="copyFeedback" type="button">Copy JSONL</button>
              <button id="downloadFeedback" type="button">Download JSONL</button>
              <button id="clearProgress" type="button">Clear saved progress</button>
            </div>
            <textarea id="feedbackOutput" readonly></textarea>
          </aside>
        </main>
        <script>
          const rows = #{payload};
          const state = new Map();
          const statusOrder = { bad: 0, unclear: 1, ok: 2 };
          const storageKey = 'locale-quality-review:' + #{JSON.generate(report_path.to_s)};

          function initialDecision(_row) { return 'accepted'; }
          function rowStorageKey(row) { return row.key + ':' + row.line_number; }

          function loadSavedState() {
            try {
              return JSON.parse(localStorage.getItem(storageKey) || '{}');
            } catch (_error) {
              return {};
            }
          }

          function saveState() {
            const saved = {};
            rows.forEach((row, index) => {
              const current = state.get(index);
              if (current.decision !== initialDecision(row) || current.custom.trim()) {
                saved[rowStorageKey(row)] = current;
              }
            });
            localStorage.setItem(storageKey, JSON.stringify(saved));
          }

          const savedState = loadSavedState();
          rows.forEach((row, index) => {
            state.set(index, savedState[rowStorageKey(row)] || { decision: initialDecision(row), custom: '' });
          });

          function escapeHtml(value) {
            return String(value ?? '').replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[char]));
          }

          function filteredRows() {
            const search = document.getElementById('search').value.toLowerCase();
            const status = document.getElementById('statusFilter').value;
            const decision = document.getElementById('decisionFilter').value;
            const sortBy = document.getElementById('sortBy').value;

            return rows.map((row, index) => ({ row, index })).filter(({ row, index }) => {
              const current = state.get(index);
              const haystack = [row.key, row.source, row.target, row.issue, row.suggested_translation].join(' ').toLowerCase();
              return (status === 'all' || row.status === status) &&
                (decision === 'all' || current.decision === decision) &&
                (!search || haystack.includes(search));
            }).sort((a, b) => {
              if (sortBy === 'key') return a.row.key.localeCompare(b.row.key);
              if (sortBy === 'decision') return state.get(a.index).decision.localeCompare(state.get(b.index).decision) || a.row.key.localeCompare(b.row.key);
              return (statusOrder[a.row.status] ?? 99) - (statusOrder[b.row.status] ?? 99) || a.row.key.localeCompare(b.row.key);
            });
          }

          function renderRows() {
            const container = document.getElementById('rows');
            const visible = filteredRows();
            if (!visible.length) {
              container.innerHTML = '<div class="empty">No rows match the current filters.</div>';
              return;
            }

            container.innerHTML = visible.map(({ row, index }) => {
              const current = state.get(index);
              return `
                <article class="row" data-index="${index}">
                  <div class="row-header">
                    <div class="key">${escapeHtml(row.key)}</div>
                    <span class="badge ${escapeHtml(row.status)}">${escapeHtml(row.status)}</span>
                  </div>
                  <div class="grid">
                    <div class="cell"><div class="cell-title">Source</div>${escapeHtml(row.source)}</div>
                    <div class="cell"><div class="cell-title">Current translation</div>${escapeHtml(row.target)}</div>
                    <div class="cell"><div class="cell-title">Suggested translation</div>${escapeHtml(row.suggested_translation)}</div>
                  </div>
                  ${row.issue ? `<div class="issue"><strong>Issue:</strong> ${escapeHtml(row.issue)}</div>` : ''}
                  <div class="actions">
                    <button type="button" data-action="toggle-rejected" class="${current.decision === 'rejected' ? 'active' : ''}">${current.decision === 'rejected' ? 'Undo reject' : 'Reject'}</button>
                    ${current.decision === 'rejected' ? `<input class="custom-inline" type="text" data-custom placeholder="Required replacement translation" value="${escapeHtml(current.custom)}">` : ''}
                  </div>
                </article>
              `;
            }).join('');
          }

          function feedbackRows() {
            const output = [];
            rows.forEach((row, index) => {
              const current = state.get(index);
              if (current.decision === 'rejected' && current.custom.trim()) {
                output.push({
                  key: row.key,
                  source_locale: row.source_locale,
                  target_locale: row.target_locale,
                  source: row.source,
                  target: row.target,
                  status: row.status,
                  reviewer_decision: 'rejected',
                  suggested_translation: current.custom.trim()
                });
              }
            });
            return output;
          }

          function renderFeedback() {
            document.getElementById('feedbackOutput').value = feedbackRows().map((row) => JSON.stringify(row)).join('\\n');
          }

          document.addEventListener('click', (event) => {
            const button = event.target.closest('button[data-action]');
            if (!button) return;
            const rowElement = button.closest('.row');
            const index = Number(rowElement.dataset.index);
            const current = state.get(index);
            if (button.dataset.action === 'toggle-rejected') {
              if (current.decision === 'rejected') {
                current.decision = 'accepted';
                current.custom = '';
              } else {
                current.decision = 'rejected';
              }
            }
            state.set(index, current);
            saveState();
            renderRows();
            renderFeedback();
          });

          document.addEventListener('input', (event) => {
            if (event.target.matches('#search, #statusFilter, #decisionFilter, #sortBy')) {
              renderRows();
              return;
            }
            if (event.target.matches('input[data-custom]')) {
              const rowElement = event.target.closest('.row');
              const index = Number(rowElement.dataset.index);
              const current = state.get(index);
              current.custom = event.target.value;
              current.decision = 'rejected';
              state.set(index, current);
              saveState();
              renderFeedback();
            }
          });

          document.getElementById('clearProgress').addEventListener('click', () => {
            if (!confirm('Clear saved review progress for this report in this browser?')) return;
            localStorage.removeItem(storageKey);
            rows.forEach((row, index) => state.set(index, { decision: initialDecision(row), custom: '' }));
            renderRows();
            renderFeedback();
          });

          document.getElementById('copyFeedback').addEventListener('click', async () => {
            await navigator.clipboard.writeText(document.getElementById('feedbackOutput').value);
          });

          document.getElementById('downloadFeedback').addEventListener('click', () => {
            const blob = new Blob([document.getElementById('feedbackOutput').value], { type: 'application/jsonl' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
            const targetLocale = rows[0]?.target_locale || 'locale';
            a.href = url;
            a.download = `locale_quality_feedback_${targetLocale}_${timestamp}.jsonl`;
            a.click();
            URL.revokeObjectURL(url);
          });

          function initializePage() {
            renderRows();
            renderFeedback();
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initializePage);
          } else {
            initializePage();
          }
        </script>
      </body>
      </html>
    HTML

    html_path.dirname.mkpath
    File.write(html_path, html)
    puts "Wrote #{html_path}"
    puts "Rows: #{rows.count}"
  end
end
