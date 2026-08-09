# frozen_string_literal: true

namespace :senders do
  desc 'Dry run sender window assignment before deploy (read-only)'
  task dry_run_window_assignment: :environment do
    dry_run = SenderWindowAssignmentDryRun.new(
      scope: Sender.includes(:organization)
                   .joins(:organization)
                   .order('organizations.name ASC, senders.id ASC')
    )
    rows = dry_run.call
    report = dry_run.summary(rows)

    puts '=' * 80
    puts 'Sender Window Assignment Dry Run'
    puts '=' * 80
    puts ''
    puts 'This task is read-only. It does not write sender windows.'
    puts "Senders scanned: #{report[:total_senders]}"
    puts "Comparable legacy timezones: #{report[:comparable_timezones]}"
    puts "Comparable legacy windows: #{report[:comparable_windows]}"
    puts "Timezone mismatches: #{report[:mismatched_timezones]}"
    puts "Window mismatches: #{report[:mismatched_windows]}"
    puts "Mixed legacy timezones: #{report[:mixed_legacy_timezones]}"
    puts "Mixed legacy windows: #{report[:mixed_legacy_windows]}"
    puts "Senders without linked agents: #{report[:senders_without_linked_agents]}"
    puts ''

    unless dry_run.legacy_window_comparison_available?
      puts 'Legacy agent send-window columns are not present in this database.'
      puts 'Run this against a pre-migration production/staging copy to compare sender windows with agent windows.'
      puts ''
    end

    unless dry_run.legacy_timezone_comparison_available?
      puts 'Legacy agent timezone data is not available in this database.'
      puts ''
    end

    flagged_rows = rows.reject { |row| row[:flags] == ['ok'] }

    if flagged_rows.empty?
      puts '✅ No sender assignment mismatches detected.'
    else
      puts '⚠️ Review these senders before deploy:'
      puts ''

      flagged_rows.each do |row|
        puts "[#{row[:organization_name]}] Sender ##{row[:sender_id]} - #{row[:sender_name]}"
        puts "  Current sender timezone/window: #{row[:sender_timezone]} | #{row[:sender_window]}"
        puts "  Legacy linked agents: #{row[:legacy_agent_count]}"
        puts "  Legacy timezone consensus: #{row[:legacy_timezone_consensus] || '(none)'}"
        puts "  Legacy window consensus: #{row[:legacy_window_consensus] || '(none)'}"
        puts "  Legacy timezone values: #{row[:legacy_timezone_values].join(', ').presence || '(none)'}"
        puts "  Legacy window values: #{row[:legacy_window_values].join(', ').presence || '(none)'}"
        puts "  Flags: #{row[:flags].join(', ')}"
        puts ''
      end
    end

    next unless ENV['VERBOSE'] == '1'

    puts '-' * 80
    puts 'All senders'
    puts '-' * 80
    puts ''

    rows.each do |row|
      puts "[#{row[:organization_name]}] Sender ##{row[:sender_id]} - #{row[:sender_name]}"
      puts "  #{row[:sender_timezone]} | #{row[:sender_window]} | Flags: #{row[:flags].join(', ')}"
    end
  end
end
