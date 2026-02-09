# frozen_string_literal: true

# Rails-compatible inflector for singularize/pluralize
# Based on ActiveSupport::Inflector rules
#
# This module is designed to work both in Ruby and when transpiled to JavaScript.
# Key compatibility notes:
# - Replacement strings use '$1' syntax (works in JS directly, converted for Ruby)
# - Methods avoid assignment-in-condition patterns
# - capitalize is implemented inline for JS compatibility

module Ruby2JS
  module Inflector
    # Plural -> Singular mapping
    IRREGULARS_SINGULAR = {
      'people' => 'person',
      'men' => 'man',
      'women' => 'woman',
      'children' => 'child',
      'sexes' => 'sex',
      'moves' => 'move',
      'zombies' => 'zombie',
      'octopi' => 'octopus',
      'viri' => 'virus',
      'aliases' => 'alias',
      'statuses' => 'status',
      'axes' => 'axis',
      'crises' => 'crisis',
      'testes' => 'testis',
      'oxen' => 'ox',
      'quizzes' => 'quiz',
    }.freeze

    # Singular -> Plural mapping
    IRREGULARS_PLURAL = {
      'person' => 'people',
      'man' => 'men',
      'woman' => 'women',
      'child' => 'children',
      'sex' => 'sexes',
      'move' => 'moves',
      'zombie' => 'zombies',
      'octopus' => 'octopi',
      'virus' => 'viri',
      'alias' => 'aliases',
      'status' => 'statuses',
      'axis' => 'axes',
      'crisis' => 'crises',
      'testis' => 'testes',
      'ox' => 'oxen',
      'quiz' => 'quizzes',
    }.freeze

    UNCOUNTABLES = %w[
      equipment information rice money species series fish sheep jeans police
    ].freeze

    # Order matters - first match wins (more specific rules first)
    # Replacement strings use $1/$2 syntax for JS compatibility
    SINGULARS = [
      [/(ss)$/i, '$1'],
      [/(database)s$/i, '$1'],
      [/(quiz)zes$/i, '$1'],
      [/(matr)ices$/i, '$1ix'],
      [/(vert|ind)ices$/i, '$1ex'],
      [/^(ox)en/i, '$1'],
      [/(alias|status)(es)?$/i, '$1'],
      [/(octop|vir)(us|i)$/i, '$1us'],
      [/^(a)x[ie]s$/i, '$1xis'],
      [/(cris|test)(is|es)$/i, '$1is'],
      [/(shoe)s$/i, '$1'],
      [/(o)es$/i, '$1'],
      [/(bus)(es)?$/i, '$1'],
      [/^(m|l)ice$/i, '$1ouse'],
      [/(x|ch|ss|sh)es$/i, '$1'],
      [/(m)ovies$/i, '$1ovie'],
      [/(s)eries$/i, '$1eries'],
      [/([^aeiouy]|qu)ies$/i, '$1y'],
      [/([lr])ves$/i, '$1f'],
      [/(tive)s$/i, '$1'],
      [/(hive)s$/i, '$1'],
      [/([^f])ves$/i, '$1fe'],
      [/((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)(sis|ses)$/i, '$1sis'],
      [/(^analy)(sis|ses)$/i, '$1sis'],
      [/([ti])a$/i, '$1um'],
      [/(n)ews$/i, '$1ews'],
      [/s$/i, ''],
    ].freeze

    # Order matters - first match wins (more specific rules first)
    PLURALS = [
      [/(quiz)$/i, '$1zes'],
      [/^(oxen)$/i, '$1'],
      [/^(ox)$/i, '$1en'],
      [/^(m|l)ice$/i, '$1ice'],
      [/^(m|l)ouse$/i, '$1ice'],
      [/(matr|vert|ind)(?:ix|ex)$/i, '$1ices'],
      [/(x|ch|ss|sh)$/i, '$1es'],
      [/([^aeiouy]|qu)y$/i, '$1ies'],
      [/(hive)$/i, '$1s'],
      [/(?:([^f])fe|([lr])f)$/i, '$1$2ves'],
      [/sis$/i, 'ses'],
      [/([ti])a$/i, '$1a'],
      [/([ti])um$/i, '$1a'],
      [/(buffal|tomat)o$/i, '$1oes'],
      [/(bu)s$/i, '$1ses'],
      [/(alias|status)$/i, '$1es'],
      [/(octop|vir)i$/i, '$1i'],
      [/(octop|vir)us$/i, '$1i'],
      [/^(ax|test)is$/i, '$1es'],
      [/s$/i, 's'],
      [/$/, 's'],
    ].freeze

    # Convert $1/$2 style replacements to Ruby's \1/\2 style
    # In JS, $1 works directly with String.replace()
    def self.convert_replacement(str)
      str.gsub(/\$(\d+)/, '\\\\\1')
    end

    # Apply regex replacement, converting $1 to \1 for Ruby
    # In JS, $1 works directly with String.replace()
    def self.apply_replacement(word, rule, replacement)
      # rubocop:disable Lint/Env
      if defined?(RUBY_ENGINE)
        # Ruby: convert $1 to \1
        word.sub(rule, replacement.gsub(/\$(\d+)/, '\\\\\1'))
      else
        # JS: use $1 directly
        word.sub(rule, replacement)
      end
      # rubocop:enable Lint/Env
    end

    def self.singularize(word)
      lower = word.downcase
      return word if UNCOUNTABLES.include?(lower)

      irregular = IRREGULARS_SINGULAR[lower]
      if irregular
        # Preserve original capitalization (inline capitalize for JS compatibility)
        if word[0] == word[0].upcase
          return irregular[0].upcase + irregular[1..-1]
        else
          return irregular
        end
      end

      SINGULARS.each do |(rule, replacement)|
        if word =~ rule
          return apply_replacement(word, rule, replacement)
        end
      end

      word
    end

    # Convert underscored string to PascalCase class name
    # 'access_token' -> 'AccessToken', 'article' -> 'Article'
    def self.classify(word)
      word.split('_').map { |s| s.empty? ? '' : s[0].upcase + s[1..-1] }.join
    end

    # Convert CamelCase to snake_case
    # 'NotNow' -> 'not_now', 'AccessToken' -> 'access_token'
    # Uses character-by-character loop for JS transpilation compatibility
    def self.underscore(word)
      result = ''
      i = 0
      while i < word.length
        ch = word[i]
        if ch == ch.upcase && ch != ch.downcase
          result += '_' if i > 0
          result += ch.downcase
        else
          result += ch
        end
        i += 1
      end
      result
    end

    def self.pluralize(word)
      lower = word.downcase
      return word if UNCOUNTABLES.include?(lower)

      irregular = IRREGULARS_PLURAL[lower]
      if irregular
        # Preserve original capitalization (inline capitalize for JS compatibility)
        if word[0] == word[0].upcase
          return irregular[0].upcase + irregular[1..-1]
        else
          return irregular
        end
      end

      PLURALS.each do |(rule, replacement)|
        if word =~ rule
          return apply_replacement(word, rule, replacement)
        end
      end

      word
    end
  end
end
