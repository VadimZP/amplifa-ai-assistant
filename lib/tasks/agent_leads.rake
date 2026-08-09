# frozen_string_literal: true

namespace :agent_leads do
  desc 'Reconcile stale delivery progression for leads with already-sent messages'
  task reconcile_sent_progression: :environment do
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV['DRY_RUN'])
    batch_size = ENV.fetch('BATCH_SIZE', 200).to_i
    scope = AgentLead.stale_sent_progression
    scope = scope.where(id: ENV['AGENT_LEAD_ID']) if ENV['AGENT_LEAD_ID'].present?

    puts '=' * 60
    puts 'AgentLead Delivery Reconciliation Backfill'
    puts '=' * 60
    puts "Scope: #{scope.count} stale agent leads"
    puts "Batch size: #{batch_size}"
    puts "Mode: #{dry_run ? 'DRY RUN (no changes)' : 'LIVE'}"
    puts ''

    result = AgentLeadDeliveryReconciliationBackfill.new(
      scope: scope,
      dry_run: dry_run,
      batch_size: batch_size
    ).run

    puts '=' * 40
    puts 'Results:'
    puts "  Total scanned: #{result.total_scanned}"
    puts "  Reconciled: #{result.reconciled}"
    puts "  Already aligned: #{result.already_aligned}"
    puts "  Failed: #{result.failed}"
    puts '=' * 40

    if result.errors.any?
      puts ''
      puts 'Errors:'
      result.errors.first(20).each do |error|
        puts "  - AgentLead ##{error[:agent_lead_id]}: #{error[:error]}"
      end
      puts '  ...' if result.errors.size > 20
    end

    return unless dry_run

    puts ''
    puts 'This was a dry run. Run without DRY_RUN=1 to apply changes.'
  end
end
