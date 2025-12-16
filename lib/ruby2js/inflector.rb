# frozen_string_literal: true

# Rails-compatible inflector for singularize/pluralize
# Based on ActiveSupport::Inflector rules

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
    SINGULARS = [
      [/(ss)$/i, '\1'],
      [/(database)s$/i, '\1'],
      [/(quiz)zes$/i, '\1'],
      [/(matr)ices$/i, '\1ix'],
      [/(vert|ind)ices$/i, '\1ex'],
      [/^(ox)en/i, '\1'],
      [/(alias|status)(es)?$/i, '\1'],
      [/(octop|vir)(us|i)$/i, '\1us'],
      [/^(a)x[ie]s$/i, '\1xis'],
      [/(cris|test)(is|es)$/i, '\1is'],
      [/(shoe)s$/i, '\1'],
      [/(o)es$/i, '\1'],
      [/(bus)(es)?$/i, '\1'],
      [/^(m|l)ice$/i, '\1ouse'],
      [/(x|ch|ss|sh)es$/i, '\1'],
      [/(m)ovies$/i, '\1ovie'],
      [/(s)eries$/i, '\1eries'],
      [/([^aeiouy]|qu)ies$/i, '\1y'],
      [/([lr])ves$/i, '\1f'],
      [/(tive)s$/i, '\1'],
      [/(hive)s$/i, '\1'],
      [/([^f])ves$/i, '\1fe'],
      [/((a)naly|(b)a|(d)iagno|(p)arenthe|(p)rogno|(s)ynop|(t)he)(sis|ses)$/i, '\1sis'],
      [/(^analy)(sis|ses)$/i, '\1sis'],
      [/([ti])a$/i, '\1um'],
      [/(n)ews$/i, '\1ews'],
      [/s$/i, ''],
    ].freeze

    # Order matters - first match wins (more specific rules first)
    PLURALS = [
      [/(quiz)$/i, '\1zes'],
      [/^(oxen)$/i, '\1'],
      [/^(ox)$/i, '\1en'],
      [/^(m|l)ice$/i, '\1ice'],
      [/^(m|l)ouse$/i, '\1ice'],
      [/(matr|vert|ind)(?:ix|ex)$/i, '\1ices'],
      [/(x|ch|ss|sh)$/i, '\1es'],
      [/([^aeiouy]|qu)y$/i, '\1ies'],
      [/(hive)$/i, '\1s'],
      [/(?:([^f])fe|([lr])f)$/i, '\1\2ves'],
      [/sis$/i, 'ses'],
      [/([ti])a$/i, '\1a'],
      [/([ti])um$/i, '\1a'],
      [/(buffal|tomat)o$/i, '\1oes'],
      [/(bu)s$/i, '\1ses'],
      [/(alias|status)$/i, '\1es'],
      [/(octop|vir)i$/i, '\1i'],
      [/(octop|vir)us$/i, '\1i'],
      [/^(ax|test)is$/i, '\1es'],
      [/s$/i, 's'],
      [/$/, 's'],
    ].freeze

    def self.singularize(word)
      lower = word.downcase
      return word if UNCOUNTABLES.include?(lower)

      if irregular = IRREGULARS_SINGULAR[lower]
        # Preserve original capitalization
        return word[0] == word[0].upcase ? irregular.capitalize : irregular
      end

      SINGULARS.each do |(rule, replacement)|
        if word.match?(rule)
          return word.sub(rule, replacement)
        end
      end

      word
    end

    def self.pluralize(word)
      lower = word.downcase
      return word if UNCOUNTABLES.include?(lower)

      if irregular = IRREGULARS_PLURAL[lower]
        # Preserve original capitalization
        return word[0] == word[0].upcase ? irregular.capitalize : irregular
      end

      PLURALS.each do |(rule, replacement)|
        if word.match?(rule)
          return word.sub(rule, replacement)
        end
      end

      word
    end
  end
end
