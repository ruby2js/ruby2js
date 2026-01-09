// Model Loader - Discovers and loads models from dist/models/
//
// Scans the models directory and dynamically imports all model classes,
// making them available for the query evaluator.

import { readdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath, pathToFileURL } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

/**
 * Load all models from the dist/models directory.
 *
 * @param {string} modelsDir - Path to the models directory
 * @returns {Promise<Object>} - Object mapping model names to model classes
 *
 * @example
 *   const models = await loadModels('./dist/models');
 *   // { Post: [class Post], User: [class User], ... }
 */
export async function loadModels(modelsDir = null) {
  if (!modelsDir) {
    modelsDir = join(__dirname, '../dist/models');
  }

  const models = {};

  if (!existsSync(modelsDir)) {
    console.warn(`Models directory not found: ${modelsDir}`);
    return models;
  }

  const files = readdirSync(modelsDir).filter(f =>
    f.endsWith('.js') &&
    f !== 'application_record.js' &&
    f !== 'index.js'
  );

  for (const file of files) {
    const filePath = join(modelsDir, file);
    const fileUrl = pathToFileURL(filePath).href;

    try {
      const module = await import(fileUrl);

      // Get the model class - either default export or named export
      const modelName = fileToClassName(file);
      const ModelClass = module.default || module[modelName];

      if (ModelClass) {
        models[modelName] = ModelClass;
      }
    } catch (error) {
      console.warn(`Failed to load model ${file}: ${error.message}`);
    }
  }

  return models;
}

/**
 * Convert a filename to a class name.
 * post.js -> Post
 * blog_post.js -> BlogPost
 *
 * @param {string} filename - The filename
 * @returns {string} - The class name
 */
function fileToClassName(filename) {
  const name = filename.replace(/\.js$/, '');
  return name
    .split('_')
    .map(part => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}

/**
 * Get model names from the loaded models.
 *
 * @param {Object} models - The loaded models object
 * @returns {string[]} - Array of model names
 */
export function getModelNames(models) {
  return Object.keys(models).sort();
}

/**
 * Get record count for a model.
 *
 * @param {Function} ModelClass - The model class
 * @returns {Promise<number>} - The record count
 */
export async function getRecordCount(ModelClass) {
  try {
    if (typeof ModelClass.count === 'function') {
      return await ModelClass.count();
    }
    const all = await ModelClass.all();
    return all.length;
  } catch (error) {
    return 0;
  }
}

/**
 * Get schema info for all models.
 *
 * @param {Object} models - The loaded models object
 * @returns {Promise<Array>} - Array of { name, count } objects
 */
export async function getModelsInfo(models) {
  const info = [];

  for (const [name, ModelClass] of Object.entries(models)) {
    const count = await getRecordCount(ModelClass);
    info.push({ name, count });
  }

  return info.sort((a, b) => a.name.localeCompare(b.name));
}

export default {
  loadModels,
  getModelNames,
  getRecordCount,
  getModelsInfo
};
