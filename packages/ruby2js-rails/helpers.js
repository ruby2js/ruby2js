// Ruby2JS-on-Rails - View Helpers
// Pure utility functions for views (no framework dependencies)

import { pluralize as inflectPlural } from 'ruby2js-rails/adapters/inflector.mjs';

// Text truncation helper (Rails view helper equivalent)
export function truncate(text, options = {}) {
  const length = options.length || 30;
  const omission = options.omission || '...';
  if (!text || text.length <= length) return text || '';
  return text.slice(0, length - omission.length) + omission;
}

// Pluralize helper (Rails view helper equivalent)
// pluralize(1, 'error') => '1 error'
// pluralize(2, 'error') => '2 errors'
// pluralize(2, 'person') => '2 people' (uses inflector for irregular words)
// pluralize(2, 'error', 'mistakes') => '2 mistakes'
export function pluralize(count, singular, plural = null) {
  const word = count === 1 ? singular : (plural || inflectPlural(singular));
  return `${count} ${word}`;
}

// strftime polyfill for date strings (ISO 8601 format)
// Handles common format codes: %Y, %m, %d, %H, %M, %S, %b, %B, %e, %I, %p
// Uses local time to match typical Rails app behavior
String.prototype.strftime = function(format) {
  const d = new Date(this);
  const pad = n => n.toString().padStart(2, '0');
  const months = ['January', 'February', 'March', 'April', 'May', 'June',
                  'July', 'August', 'September', 'October', 'November', 'December'];
  const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                       'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return format
    .replace(/%Y/g, d.getFullYear())
    .replace(/%m/g, pad(d.getMonth() + 1))
    .replace(/%d/g, pad(d.getDate()))
    .replace(/%e/g, d.getDate().toString().padStart(2, ' '))
    .replace(/%H/g, pad(d.getHours()))
    .replace(/%I/g, pad(d.getHours() % 12 || 12))
    .replace(/%M/g, pad(d.getMinutes()))
    .replace(/%S/g, pad(d.getSeconds()))
    .replace(/%B/g, months[d.getMonth()])
    .replace(/%b/g, monthsShort[d.getMonth()])
    .replace(/%p/g, d.getHours() < 12 ? 'AM' : 'PM');
};

// DOM ID helper (Rails view helper equivalent)
// dom_id(article) => 'article_1'
// dom_id(article, 'edit') => 'edit_article_1'
// dom_id(new Article()) => 'new_article'
export function dom_id(record, prefix = null) {
  const modelName = (record.constructor?.modelName || record.constructor?.name || 'record').toLowerCase();

  if (record.id) {
    return prefix ? `${prefix}_${modelName}_${record.id}` : `${modelName}_${record.id}`;
  } else {
    return prefix ? `${prefix}_new_${modelName}` : `new_${modelName}`;
  }
}
