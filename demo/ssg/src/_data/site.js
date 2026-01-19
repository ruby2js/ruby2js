/**
 * 11ty Data File: Content Collections
 *
 * Scans content/ directory, parses markdown with front matter,
 * and returns queryable collections using the content adapter.
 */

import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';
import { createCollection } from '@ruby2js/content-adapter';

const contentDir = path.resolve(process.cwd(), 'content');

/**
 * Singularize a plural word.
 */
function singularize(word) {
  if (word.endsWith('ies')) return word.slice(0, -3) + 'y';
  if (word.endsWith('es')) return word.slice(0, -2);
  if (word.endsWith('s')) return word.slice(0, -1);
  return word;
}

/**
 * Convert to PascalCase.
 */
function toPascalCase(str) {
  return singularize(str)
    .split(/[-_]/)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join('');
}

/**
 * Extract slug from filename.
 */
function extractSlug(filename) {
  const basename = path.basename(filename, path.extname(filename));
  return basename.replace(/^\d{4}-\d{2}-\d{2}-/, '');
}

/**
 * Parse a content file.
 */
function parseContentFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const { data, content: body } = matter(content);
  const slug = data.slug || extractSlug(filePath);
  const renderedBody = marked(body);

  return {
    ...data,
    slug,
    body: renderedBody
  };
}

/**
 * Scan a directory for markdown files.
 */
function scanDirectory(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true })
    .filter(entry => entry.isFile() && (entry.name.endsWith('.md') || entry.name.endsWith('.markdown')))
    .map(entry => path.join(dir, entry.name));
}

/**
 * Load all collections from content directory.
 */
export default function() {
  const collections = {};

  if (!fs.existsSync(contentDir)) {
    return collections;
  }

  // Scan each subdirectory as a collection
  for (const entry of fs.readdirSync(contentDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;

    const collectionName = entry.name;
    const collectionDir = path.join(contentDir, collectionName);
    const files = scanDirectory(collectionDir);
    const records = files.map(parseContentFile);

    // Create queryable collection
    const collection = createCollection(collectionName, records);

    // Export both as array and as queryable collection
    // - posts: array for simple iteration
    // - Post: queryable collection for advanced queries
    collections[collectionName] = records;
    collections[toPascalCase(collectionName)] = collection;
  }

  // Wire up relationships between collections
  const collectionNames = Object.keys(collections).filter(k => k === k.toLowerCase());

  for (const name of collectionNames) {
    const className = toPascalCase(name);
    const collection = collections[className];
    if (!collection || collection.toArray().length === 0) continue;

    const sample = collection.toArray()[0];

    for (const [attr, value] of Object.entries(sample)) {
      if (attr === 'slug' || attr === 'body') continue;

      // Check for belongsTo (singular attr → plural collection)
      const pluralAttr = attr + 's';
      if (collectionNames.includes(pluralAttr)) {
        collection.belongsTo(attr, collections[toPascalCase(pluralAttr)]);
      }

      // Check for hasMany (array attr → collection)
      if (Array.isArray(value) && collectionNames.includes(attr)) {
        collection.hasMany(attr, collections[toPascalCase(attr)]);
      }
    }
  }

  return collections;
}
