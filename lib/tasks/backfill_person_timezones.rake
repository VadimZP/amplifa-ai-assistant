# frozen_string_literal: true

# Rake task to backfill timezone for existing people with locations.

namespace :people do
  desc 'Backfill timezone for people with location but no cached timezone'
  task backfill_timezones: :environment do
    puts '=' * 60
    puts 'Backfill Person Timezones'
    puts '=' * 60
    puts ''

    batch_size = ENV.fetch('BATCH_SIZE', 100).to_i
    dry_run = ENV['DRY_RUN'] == '1'

    # Find people with location but no timezone
    scope = Person.where.not(location: [nil, ''])
                  .where(timezone: nil)

    total = scope.count
    puts "Found #{total} people with location but no timezone"
    puts "Batch size: #{batch_size}"
    puts "Mode: #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
    puts ''

    if total == 0
      puts 'Nothing to do!'
      exit 0
    end

    resolved = 0
    failed = 0
    skipped = 0

    scope.find_each(batch_size: batch_size).with_index do |person, index|
      if dry_run
        timezone = LocationTimezoneResolver.resolve(person.location)
        if timezone
          puts "  [DRY RUN] Person ##{person.id}: #{person.location} -> #{timezone}"
          resolved += 1
        else
          skipped += 1
        end
      else
        begin
          person.resolve_timezone!

          if person.timezone.present?
            resolved += 1
            puts "  ✅ Person ##{person.id}: #{person.location} -> #{person.timezone}" if ENV['VERBOSE'] == '1'
          else
            skipped += 1
            puts "  ⏭️  Person ##{person.id}: #{person.location} -> (no match)" if ENV['VERBOSE'] == '1'
          end
        rescue StandardError => e
          failed += 1
          puts "  ❌ Person ##{person.id}: #{e.message}"
        end
      end

      # Progress indicator every 100 records
      puts "  Progress: #{index + 1}/#{total}" if (index + 1) % 100 == 0
    end

    puts ''
    puts '=' * 40
    puts 'Results:'
    puts "  Resolved: #{resolved}"
    puts "  Skipped (no match): #{skipped}"
    puts "  Failed: #{failed}"
    puts "  Total processed: #{resolved + skipped + failed}"
    puts '=' * 40

    if dry_run
      puts ''
      puts 'This was a dry run. Run without DRY_RUN=1 to apply changes.'
    end
  end

  desc 'Show timezone resolution statistics'
  task timezone_stats: :environment do
    puts '=' * 60
    puts 'Person Timezone Statistics'
    puts '=' * 60
    puts ''

    total = Person.count
    with_location = Person.where.not(location: [nil, '']).count
    with_timezone = Person.where.not(timezone: nil).count
    needs_backfill = Person.where.not(location: [nil, ''])
                           .where(timezone: nil).count

    puts "Total people: #{total}"
    puts "  With location: #{with_location}"
    puts "  With timezone: #{with_timezone}"
    puts "  Needs backfill: #{needs_backfill}"
    puts ''

    if with_timezone > 0
      puts 'Timezone distribution:'
      Person.where.not(timezone: nil)
            .group(:timezone)
            .order(Arel.sql('COUNT(*) DESC'))
            .limit(15)
            .count
            .each do |tz, count|
              puts "  #{tz.ljust(30)} #{count}"
      end

      remaining = Person.where.not(timezone: nil)
                        .group(:timezone)
                        .count
                        .length - 15
      puts "  ... and #{remaining} more" if remaining > 0
    end

    puts ''
    puts 'Source distribution:'
    Person.where.not(timezone_source: nil)
          .group(:timezone_source)
          .count
          .each do |source, count|
            puts "  #{source.ljust(30)} #{count}"
    end
  end
end
