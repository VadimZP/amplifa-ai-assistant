require 'pdf/reader'
require 'docx'

class FileTextExtractor
  PDF_CONTENT_TYPE = 'application/pdf'.freeze
  OCR_PROMPT = 'Extract all text from this image'.freeze
  OCR_MODEL = 'anthropic/claude-opus-4.6'.freeze
  DOCX_CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'.freeze
  TEXT_CONTENT_TYPES = %w[text/plain text/csv application/csv].freeze

  def extract(file_path_or_io, content_type:)
    text = with_file_path(file_path_or_io, content_type:) { |file_path| extract_text(file_path, content_type) }
    { text: normalize_text(text), error: nil }
  rescue RubyLLM::Error => e
    { text: '', error: e.message.presence || e.class.name }
  rescue StandardError => e
    { text: '', error: e.message.presence || e.class.name }
  end

  private

  def extract_text(file_path, content_type)
    case content_type
    when PDF_CONTENT_TYPE
      extract_pdf_text(file_path)
    when DOCX_CONTENT_TYPE
      extract_docx_text(file_path)
    when *TEXT_CONTENT_TYPES
      extract_plain_text(file_path)
    when %r{\Aimage/}
      extract_image_text(file_path)
    else
      raise ArgumentError, "Unsupported content type: #{content_type}"
    end
  end

  def extract_pdf_text(file_path)
    PDF::Reader.new(file_path).pages.map(&:text).join("\n")
  end

  def extract_docx_text(file_path)
    Docx::Document.open(file_path).text
  end

  def extract_plain_text(file_path)
    File.read(file_path)
  end

  def extract_image_text(file_path)
    response = RubyLLM.chat(model: OCR_MODEL, provider: :openrouter)
                      .with_instructions(OCR_PROMPT)
                      .ask(RubyLLM::Content.new(OCR_PROMPT, [file_path]))

    response.content.to_s
  end

  def normalize_text(text)
    text.to_s.gsub(/\r\n?/, "\n").strip
  end

  def with_file_path(file_path_or_io, content_type:)
    if file_path?(file_path_or_io)
      yield file_path_or_io.to_s
    elsif reusable_path?(file_path_or_io)
      yield file_path_or_io.path
    else
      with_tempfile(file_path_or_io, content_type:) { |tempfile| yield tempfile.path }
    end
  end

  def file_path?(value)
    value.is_a?(String) || value.is_a?(Pathname)
  end

  def reusable_path?(value)
    value.respond_to?(:path) && value.path.present? && File.exist?(value.path)
  end

  def extension_for(content_type)
    Rack::Mime::MIME_TYPES.invert[content_type] || '.bin'
  end

  def with_tempfile(file_path_or_io, content_type:)
    tempfile = Tempfile.new(['file-text-extractor', extension_for(content_type)], binmode: true)

    begin
      file_path_or_io.rewind if file_path_or_io.respond_to?(:rewind)
      tempfile.write(file_path_or_io.read)
      tempfile.rewind
      yield tempfile
    ensure
      tempfile.close!
    end
  end
end
