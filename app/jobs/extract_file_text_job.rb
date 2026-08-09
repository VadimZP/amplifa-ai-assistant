class ExtractFileTextJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(playbook_attachment_id)
    attachment = PlaybookAttachment.find(playbook_attachment_id)
    extractor = FileTextExtractor.new

    result = nil
    attachment.file.blob.open do |tempfile|
      result = extractor.extract(tempfile, content_type: attachment.content_type)
    end

    if result[:error].present?
      attachment.update!(extraction_status: 'failed', extraction_error: result[:error])
    else
      attachment.update!(extracted_text: result[:text], extraction_status: 'completed', extraction_error: nil)
    end
  rescue StandardError => e
    attachment&.update_columns(extraction_status: 'failed', extraction_error: e.message.to_s.truncate(500))
    raise
  end
end
