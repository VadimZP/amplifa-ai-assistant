# frozen_string_literal: true

class MailPollingBatchCallback
  def on_complete(status, options)
    organization_id = options["organization_id"] || options[:organization_id]
    organization = Organization.find_by(id: organization_id)
    return unless organization

    failure_count = status.failures rescue 0
    total = status.total rescue 0

    MailPollingChannel.broadcast_to(
      organization,
      event: "complete",
      mailbox_count: total,
      failure_count: failure_count
    )
  end
end
