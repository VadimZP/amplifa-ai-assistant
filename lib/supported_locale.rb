module SupportedLocale
  ALL = %w[en de es pt-BR fr pl cs it].freeze

  AI_LANGUAGE_NAMES = {
    'en' => 'English',
    'de' => 'German',
    'es' => 'Spanish (Spain)',
    'pt-BR' => 'Portuguese (Brazil)',
    'fr' => 'French',
    'pl' => 'Polish',
    'cs' => 'Czech',
    'it' => 'Italian'
  }.freeze

  def self.include?(locale)
    ALL.include?(locale)
  end

  def self.ai_language_name(locale)
    AI_LANGUAGE_NAMES.fetch(locale, AI_LANGUAGE_NAMES['en'])
  end
end
