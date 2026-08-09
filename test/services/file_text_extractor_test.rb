require 'test_helper'

class FileTextExtractorTest < ActiveSupport::TestCase
  test 'extracts text from pdf' do
    result = FileTextExtractor.new.extract(file_fixture('sample.pdf'), content_type: 'application/pdf')

    assert_nil result[:error]
    assert_includes result[:text], 'Amplifa PDF fixture text for extraction.'
    assert_includes result[:text], 'Second line for PDF reader.'
  end

  test 'extracts text from docx' do
    result = FileTextExtractor.new.extract(
      file_fixture('sample.docx'),
      content_type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )

    assert_nil result[:error]
    assert_includes result[:text], 'Amplifa DOCX fixture text for extraction.'
    assert_includes result[:text], 'Second paragraph in DOCX.'
  end

  test 'extracts text from image with ocr' do
    extractor = FileTextExtractor.new
    fake_chat = FakeChat.new('Amplifa OCR fixture text')

    RubyLLM.stub :chat, fake_chat do
      result = extractor.extract(file_fixture('sample.png'), content_type: 'image/png')

      assert_nil result[:error]
      assert_equal 'Amplifa OCR fixture text', result[:text]
      assert_equal 'anthropic/claude-opus-4.6', fake_chat.model
      assert_equal :openrouter, fake_chat.provider
      assert_equal 'Extract all text from this image', fake_chat.instructions
      assert_kind_of RubyLLM::Content, fake_chat.prompt
      assert_equal 'Extract all text from this image', fake_chat.prompt.text
      assert_equal 1, fake_chat.prompt.attachments.size
      assert_equal :image, fake_chat.prompt.attachments.first.type
    end
  end

  test 'returns empty text for blank pdf' do
    result = FileTextExtractor.new.extract(file_fixture('empty.pdf'), content_type: 'application/pdf')

    assert_nil result[:error]
    assert_equal '', result[:text]
  end

  test 'preserves full extracted text without truncation' do
    long_text = 'a' * 6000
    fake_document = Struct.new(:text).new(long_text)
    content_type = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'

    Docx::Document.stub :open, fake_document do
      result = FileTextExtractor.new.extract(file_fixture('sample.docx'), content_type: content_type)

      assert_nil result[:error]
      assert_equal 6000, result[:text].length
      assert_equal long_text, result[:text]
    end
  end

  test 'handles corrupt file' do
    Tempfile.create(['corrupt', '.pdf']) do |file|
      file.write('not actually a pdf')
      file.rewind

      result = FileTextExtractor.new.extract(file.path, content_type: 'application/pdf')

      assert_equal '', result[:text]
      assert_match(/PDF|extract/i, result[:error])
    end
  end

  class FakeChat
    attr_reader :model, :provider, :instructions, :prompt

    def initialize(response_text)
      @response_text = response_text
    end

    def self.call(model:)
      new(nil).tap { |chat| chat.instance_variable_set(:@model, model) }
    end

    def call(model:, provider:)
      @model = model
      @provider = provider
      self
    end

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def ask(prompt)
      @prompt = prompt
      Struct.new(:content).new(@response_text)
    end
  end
end
