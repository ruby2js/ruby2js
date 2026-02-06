// URL Helpers for Ruby2JS-Rails
//
// Provides polymorphic_path and polymorphic_url, which resolve model instances
// to URL paths based on their table names — matching Rails' polymorphic routing.
//
// Usage:
//   polymorphic_path(card)            → "/cards/42"
//   polymorphic_path([board, card])   → "/boards/1/cards/2"
//   polymorphic_url(card, { host: "https://example.com" }) → "https://example.com/cards/42"

import { createPathHelper } from 'ruby2js-rails/path_helper.mjs';

function modelToPathSegment(record) {
  const tableName = record.constructor.tableName || record.constructor.table_name;
  return `/${tableName}/${record.id}`;
}

export function polymorphic_path(record_or_array, options = {}) {
  if (Array.isArray(record_or_array)) {
    let path = '';
    for (const item of record_or_array) {
      if (typeof item === 'string') {
        path += `/${item}`;
      } else if (item && typeof item === 'object') {
        path += modelToPathSegment(item);
      }
    }
    return createPathHelper(path);
  }
  return createPathHelper(modelToPathSegment(record_or_array));
}

export function polymorphic_url(record_or_array, options = {}) {
  const path = polymorphic_path(record_or_array, options);
  const host = options.host || '';
  const scriptName = options.script_name || '';
  return host + scriptName + path.toString();
}
