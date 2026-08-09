#!/usr/bin/env ruby
# frozen_string_literal: true

require 'csv'
require 'optparse'

options = {
  organization_id: nil,
  batch_size: 100
}

parser = OptionParser.new do |opts|
  opts.banner = <<~BANNER
    Usage: ruby script/list_auto_assigned_reply_mismatches.rb [options]

    Replays the unassigned reply backfill in dry-run mode and prints only the
    mismatch replies that would be auto-assigned.
  BANNER

  opts.on(
    '--organization-id ID',
    Integer,
    'Filter to a single organization ID'
  ) do |organization_id|
    options[:organization_id] = organization_id
  end

  opts.on(
    '--batch-size SIZE',
    Integer,
    'Batch size for scanning replies (default: 100)'
  ) do |batch_size|
    options[:batch_size] = batch_size
  end

  opts.on('-h', '--help', 'Show this help') do
    puts opts
    exit 0
  end
end

parser.parse!

require_relative '../config/environment'

scope = Reply.needs_assignment.includes(:mailbox)

if options[:organization_id]
  scope = scope.joins(:mailbox).where(mailboxes: { organization_id: options[:organization_id] })
end

service = UnassignedReplyBackfillService.new(scope: Reply.none, dry_run: true, batch_size: options[:batch_size])

csv = CSV.generate do |rows|
  rows << %w[incoming_reply_email matched_lead_email matched_lead_id]

  scope.find_each(batch_size: options[:batch_size]) do |reply|
    next unless reply.human?

    message_data, message_content = service.send(:message_payload_for, reply)
    result = InboundReplyMatcher.new(
      mailbox: reply.mailbox,
      from_address: reply.from_address,
      message_data: message_data,
      message_content: message_content
    ).call

    next if result.failure?
    next unless result.matched? && result.high_confidence? && result.sender_mismatch_on_match

    rows << [reply.from_address, result.lead.email, result.lead.id]
  rescue StandardError => e
    warn "Reply ##{reply.id}: #{e.class}: #{e.message}"
  end
end

puts csv
