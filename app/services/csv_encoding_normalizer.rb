# frozen_string_literal: true

# Converts uploaded CSV bytes to UTF-8 before Ruby's CSV parser sees them.
class CsvEncodingNormalizer
  UTF_8_BOM = "\xEF\xBB\xBF".b

  class << self
    def normalize(content)
      bytes = content.to_s.b
      bytes = bytes.delete_prefix(UTF_8_BOM)

      utf8_content = bytes.dup.force_encoding(Encoding::UTF_8)
      return utf8_content if utf8_content.valid_encoding?

      bytes.force_encoding(Encoding::Windows_1252).encode(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: ''
      )
    end
  end
end
