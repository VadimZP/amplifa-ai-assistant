# frozen_string_literal: true

namespace :organizations do
  desc 'Backfill organization own-domain blacklist entries from website URLs'
  task backfill_website_domain_blacklists: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV['DRY_RUN'])
    batch_size = ENV.fetch('BATCH_SIZE', 200).to_i
    scope = Organization.all
    scope = scope.where(id: ENV['ORG_ID']) if ENV['ORG_ID'].present?

    puts '=' * 60
    puts 'Organization Domain Blacklist Backfill'
    puts '=' * 60
    puts "Scope: #{scope.count} organizations"
    puts "Batch size: #{batch_size}"
    puts "Mode: #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
    puts ''

    result = OrganizationDomainBlacklistBackfill.new(
      scope: scope,
      dry_run: dry_run,
      batch_size: batch_size
    ).run

    puts '=' * 40
    puts 'Results:'
    puts "  Total scanned: #{result.total_scanned}"
    puts "  Eligible (website present): #{result.eligible}"
    puts "  Created: #{result.created}"
    puts "  Already existed: #{result.existing}"
    puts "  Skipped: #{result.skipped}"
    puts "  Failed: #{result.failed}"
    puts '=' * 40

    if result.errors.any?
      puts ''
      puts 'Errors:'
      result.errors.first(20).each do |error|
        puts "  - Organization ##{error[:organization_id]} (#{error[:name]}): #{error[:error]}"
      end
      puts '  ...' if result.errors.size > 20
    end

    return unless dry_run

    puts ''
    puts 'This was a dry run. Run without DRY_RUN=1 to apply changes.'
  end
end
