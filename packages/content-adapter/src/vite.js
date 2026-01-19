/**
 * @ruby2js/content-adapter/vite
 *
 * Vite plugin that scans content directories, parses markdown with front matter,
 * and generates a virtual:content module with queryable collections.
 */

import fs from 'fs';
import path from 'path';
import matter from 'gray-matter';
import { marked } from 'marked';

const VIRTUAL_MODULE_ID = 'virtual:content';
const RESOLVED_VIRTUAL_MODULE_ID = '\0' + VIRTUAL_MODULE_ID;

/**
 * Singularize a plural word (simple English rules).
 * posts -> Post, authors -> Author, categories -> Category
 */
function singularize(word) {
  if (word.endsWith('ies')) {
    return word.slice(0, -3) + 'y';
  }
  if (word.endsWith('es')) {
    return word.slice(0, -2);
  }
  if (word.endsWith('s')) {
    return word.slice(0, -1);
  }
  return word;
}

/**
 * Convert to PascalCase class name.
 * posts -> Post, blog-posts -> BlogPost
 */
function toClassName(dirName) {
  const singular = singularize(dirName);
  return singular
    .split(/[-_]/)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join('');
}

/**
 * Extract slug from filename.
 * 2024-01-01-hello-world.md -> hello-world
 * alice.md -> alice
 */
function extractSlug(filename) {
  const basename = path.basename(filename, path.extname(filename));
  // Remove date prefix if present (YYYY-MM-DD-)
  return basename.replace(/^\d{4}-\d{2}-\d{2}-/, '');
}

/**
 * Scan a directory for content files.
 */
function scanDirectory(dir) {
  const files = [];
  if (!fs.existsSync(dir)) return files;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isFile() && (entry.name.endsWith('.md') || entry.name.endsWith('.markdown'))) {
      files.push(path.join(dir, entry.name));
    }
  }
  return files;
}

/**
 * Parse a content file and extract front matter + body.
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
 * Detect collections in content directory.
 * content/posts/ -> posts collection
 * content/authors/ -> authors collection
 */
function detectCollections(contentDir) {
  const collections = {};

  if (!fs.existsSync(contentDir)) return collections;

  for (const entry of fs.readdirSync(contentDir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const collectionName = entry.name;
      const collectionDir = path.join(contentDir, collectionName);
      const files = scanDirectory(collectionDir);
      const records = files.map(parseContentFile);

      collections[collectionName] = {
        name: collectionName,
        className: toClassName(collectionName),
        records
      };
    }
  }

  return collections;
}

/**
 * Infer relationships between collections.
 * If a record has 'author: alice' and there's an 'authors' collection,
 * infer a belongsTo relationship.
 */
function inferRelationships(collections) {
  const relationships = [];
  const collectionNames = Object.keys(collections);

  for (const [name, collection] of Object.entries(collections)) {
    if (collection.records.length === 0) continue;

    // Sample first record to detect potential foreign keys
    const sample = collection.records[0];

    for (const [attr, value] of Object.entries(sample)) {
      if (attr === 'slug' || attr === 'body') continue;

      // Check for singular attribute matching a plural collection
      // author -> authors, category -> categories
      const pluralAttr = attr + 's';
      const pluralAttrIes = attr.slice(0, -1) + 'ies'; // category -> categories

      if (collectionNames.includes(pluralAttr)) {
        relationships.push({
          from: collection.className,
          type: 'belongsTo',
          attr,
          to: collections[pluralAttr].className
        });
      } else if (collectionNames.includes(pluralAttrIes)) {
        relationships.push({
          from: collection.className,
          type: 'belongsTo',
          attr,
          to: collections[pluralAttrIes].className
        });
      }

      // Check for plural attribute (array) matching a collection
      // tags: [a, b] -> tags collection
      if (Array.isArray(value) && collectionNames.includes(attr)) {
        relationships.push({
          from: collection.className,
          type: 'hasMany',
          attr,
          to: collections[attr].className
        });
      }
    }
  }

  return relationships;
}

/**
 * Generate the virtual module code.
 */
function generateVirtualModule(collections, relationships) {
  const lines = [
    `import { createCollection } from '@ruby2js/content-adapter';`,
    ''
  ];

  // Generate collection exports
  for (const collection of Object.values(collections)) {
    const recordsJson = JSON.stringify(collection.records, null, 2);
    lines.push(`export const ${collection.className} = createCollection('${collection.name}', ${recordsJson});`);
    lines.push('');
  }

  // Generate relationship wiring
  if (relationships.length > 0) {
    lines.push('// Relationship wiring');
    for (const rel of relationships) {
      lines.push(`${rel.from}.${rel.type}('${rel.attr}', ${rel.to});`);
    }
  }

  return lines.join('\n');
}

/**
 * Vite plugin for content collections.
 *
 * @param {Object} options
 * @param {string} [options.dir='content'] - Content directory path
 * @returns {import('vite').Plugin}
 */
export default function contentAdapter(options = {}) {
  const contentDir = options.dir || 'content';
  let resolvedContentDir;
  let collections = {};
  let relationships = [];

  return {
    name: 'ruby2js-content-adapter',

    configResolved(config) {
      resolvedContentDir = path.resolve(config.root, contentDir);
    },

    resolveId(id) {
      if (id === VIRTUAL_MODULE_ID) {
        return RESOLVED_VIRTUAL_MODULE_ID;
      }
    },

    load(id) {
      if (id === RESOLVED_VIRTUAL_MODULE_ID) {
        collections = detectCollections(resolvedContentDir);
        relationships = inferRelationships(collections);
        return generateVirtualModule(collections, relationships);
      }
    },

    configureServer(server) {
      // Watch content directory for changes
      server.watcher.add(resolvedContentDir);

      server.watcher.on('change', (file) => {
        if (file.startsWith(resolvedContentDir)) {
          // Invalidate the virtual module
          const mod = server.moduleGraph.getModuleById(RESOLVED_VIRTUAL_MODULE_ID);
          if (mod) {
            server.moduleGraph.invalidateModule(mod);
            server.ws.send({ type: 'full-reload' });
          }
        }
      });

      server.watcher.on('add', (file) => {
        if (file.startsWith(resolvedContentDir)) {
          const mod = server.moduleGraph.getModuleById(RESOLVED_VIRTUAL_MODULE_ID);
          if (mod) {
            server.moduleGraph.invalidateModule(mod);
            server.ws.send({ type: 'full-reload' });
          }
        }
      });
    }
  };
}
