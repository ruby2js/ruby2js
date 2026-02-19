// Rails-compatible inflector for singularize/pluralize
// Based on ActiveSupport::Inflector rules
//
// Usage:
//   import { singularize, pluralize } from './inflector.mjs';
//   singularize('posts') => 'post'
//   pluralize('person') => 'people'

// Plural -> Singular mapping (irregular words)
const IRREGULARS_SINGULAR = {
  people: 'person',
  men: 'man',
  women: 'woman',
  children: 'child',
  sexes: 'sex',
  moves: 'move',
  zombies: 'zombie',
  octopi: 'octopus',
  viri: 'virus',
  aliases: 'alias',
  statuses: 'status',
  axes: 'axis',
  crises: 'crisis',
  testes: 'testis',
  oxen: 'ox',
  quizzes: 'quiz'
};

// Singular -> Plural mapping (irregular words)
const IRREGULARS_PLURAL = {
  person: 'people',
  man: 'men',
  woman: 'women',
  child: 'children',
  sex: 'sexes',
  move: 'moves',
  zombie: 'zombies',
  octopus: 'octopi',
  virus: 'viri',
  alias: 'aliases',
  status: 'statuses',
  axis: 'axes',
  crisis: 'crises',
  testis: 'testes',
  ox: 'oxen',
  quiz: 'quizzes'
};

// Words that are the same in singular and plural
const UNCOUNTABLES = new Set([
  'equipment', 'information', 'rice', 'money', 'species',
  'series', 'fish', 'sheep', 'jeans', 'police'
]);

// Singularization rules - order matters, first match wins
const SINGULARS = [
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
  [/s$/i, '']
];

// Pluralization rules - order matters, first match wins
const PLURALS = [
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
  [/$/, 's']
];

/**
 * Convert a plural word to its singular form
 * @param {string} word - The word to singularize
 * @returns {string} The singular form
 */
export function singularize(word) {
  const lower = word.toLowerCase();

  // Check uncountables
  if (UNCOUNTABLES.has(lower)) {
    return word;
  }

  // Check irregular words
  const irregular = IRREGULARS_SINGULAR[lower];
  if (irregular) {
    // Preserve original capitalization
    if (word[0] === word[0].toUpperCase()) {
      return irregular[0].toUpperCase() + irregular.slice(1);
    }
    return irregular;
  }

  // Apply rules
  for (const [rule, replacement] of SINGULARS) {
    if (rule.test(word)) {
      return word.replace(rule, replacement);
    }
  }

  return word;
}

/**
 * Convert a singular word to its plural form
 * @param {string} word - The word to pluralize
 * @returns {string} The plural form
 */
export function pluralize(word) {
  const lower = word.toLowerCase();

  // Check uncountables
  if (UNCOUNTABLES.has(lower)) {
    return word;
  }

  // Check irregular words
  const irregular = IRREGULARS_PLURAL[lower];
  if (irregular) {
    // Preserve original capitalization
    if (word[0] === word[0].toUpperCase()) {
      return irregular[0].toUpperCase() + irregular.slice(1);
    }
    return irregular;
  }

  // Apply rules
  for (const [rule, replacement] of PLURALS) {
    if (rule.test(word)) {
      return word.replace(rule, replacement);
    }
  }

  return word;
}

/**
 * Convert a CamelCase or PascalCase string to snake_case
 * @param {string} word - The word to convert
 * @returns {string} The snake_case form
 */
export function underscore(word) {
  return word
    .replace(/([A-Z]+)([A-Z][a-z])/g, '$1_$2')
    .replace(/([a-z\d])([A-Z])/g, '$1_$2')
    .toLowerCase();
}

/**
 * Convert a snake_case string to CamelCase
 * @param {string} word - The word to convert
 * @returns {string} The CamelCase form
 */
export function camelize(word) {
  return word
    .replace(/^([a-z])/, (_, c) => c.toUpperCase())
    .replace(/_([a-z])/g, (_, c) => c.toUpperCase());
}
