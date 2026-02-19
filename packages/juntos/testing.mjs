// Juntos/Rails testing harness for Vitest
//
// Provides Rails-like integration testing helpers that work with
// transpiled controllers and models.
//
// Usage:
//   import { get, post, loadFixture, setupTestApp } from 'juntos/testing';
//
//   describe('ArticlesController', () => {
//     beforeAll(async () => {
//       await setupTestApp({ models: { Article, Comment }, migrations });
//     });
//
//     beforeEach(async () => {
//       await resetDatabase();
//     });
//
//     test('should get index', async () => {
//       const response = await get(articles_path());
//       expect(response.status).toBe(200);
//     });
//   });

import { readFileSync, existsSync } from 'fs';
import { join } from 'path';
import jsYaml from 'js-yaml';

// Global test state
let _controllers = {};
let _models = {};
let _router = null;
let _initDatabase = null;
let _runMigrations = null;
let _fixtures = {};
let _fixturesDir = null;
let _context = null;

/**
 * Set up the test application with controllers, models, and database.
 *
 * @param {Object} options
 * @param {Object} options.controllers - Controller modules { ArticlesController, ... }
 * @param {Object} options.models - Model classes { Article, Comment, ... }
 * @param {Function} options.initDatabase - Database initialization function
 * @param {Function} options.runMigrations - Migration runner function
 * @param {string} options.fixturesDir - Path to fixtures directory (default: test/fixtures)
 */
export async function setupTestApp(options = {}) {
  _controllers = options.controllers || {};
  _models = options.models || {};
  _initDatabase = options.initDatabase;
  _runMigrations = options.runMigrations;
  _fixturesDir = options.fixturesDir || 'test/fixtures';

  // Build router from controllers
  _router = buildRouter(_controllers);
}

/**
 * Reset database to clean state for each test.
 * Initializes fresh in-memory database and runs migrations.
 */
export async function resetDatabase() {
  if (_initDatabase) {
    await _initDatabase({ database: ':memory:' });
  }
  if (_runMigrations) {
    await _runMigrations();
  }
  // Clear fixture cache
  _fixtures = {};
  // Reset context
  _context = createContext();
}

/**
 * Create a fresh test context.
 */
export function createContext() {
  const flash = new Map();
  return {
    params: {},
    flash: {
      get: (key) => flash.get(key) || '',
      set: (key, value) => flash.set(key, value),
      consumeNotice: () => {
        const notice = flash.get('notice');
        flash.delete('notice');
        return { present: !!notice, toString: () => notice || '' };
      },
      consumeAlert: () => {
        const alert = flash.get('alert');
        flash.delete('alert');
        return alert || '';
      }
    },
    contentFor: {},
    request: {
      headers: {
        accept: 'text/html'
      }
    }
  };
}

/**
 * Get the current test context.
 */
export function getContext() {
  if (!_context) {
    _context = createContext();
  }
  return _context;
}

/**
 * Build a simple router from controllers.
 * Maps paths to controller actions.
 */
function buildRouter(controllers) {
  const routes = [];

  for (const [name, controller] of Object.entries(controllers)) {
    // Extract resource name from controller name (ArticlesController -> articles)
    const match = name.match(/^(\w+)Controller$/);
    if (!match) continue;

    const resourceName = match[1].toLowerCase();
    const pluralName = resourceName.endsWith('s') ? resourceName : resourceName + 's';

    // RESTful routes
    routes.push({
      method: 'GET',
      pattern: new RegExp(`^/${pluralName}/?$`),
      controller,
      action: 'index',
      params: () => ({})
    });

    routes.push({
      method: 'GET',
      pattern: new RegExp(`^/${pluralName}/new/?$`),
      controller,
      action: '$new',  // 'new' is reserved in JS
      params: () => ({})
    });

    routes.push({
      method: 'POST',
      pattern: new RegExp(`^/${pluralName}/?$`),
      controller,
      action: 'create',
      params: () => ({})
    });

    routes.push({
      method: 'GET',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/?$`),
      controller,
      action: 'show',
      params: (match) => ({ id: parseInt(match[1]) })
    });

    routes.push({
      method: 'GET',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/edit/?$`),
      controller,
      action: 'edit',
      params: (match) => ({ id: parseInt(match[1]) })
    });

    routes.push({
      method: 'PATCH',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/?$`),
      controller,
      action: 'update',
      params: (match) => ({ id: parseInt(match[1]) })
    });

    routes.push({
      method: 'PUT',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/?$`),
      controller,
      action: 'update',
      params: (match) => ({ id: parseInt(match[1]) })
    });

    routes.push({
      method: 'DELETE',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/?$`),
      controller,
      action: 'destroy',
      params: (match) => ({ id: parseInt(match[1]) })
    });

    // Nested routes (e.g., /articles/1/comments)
    routes.push({
      method: 'POST',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/comments/?$`),
      controller: controllers.CommentsController,
      action: 'create',
      params: (match) => ({ article_id: parseInt(match[1]) })
    });

    routes.push({
      method: 'DELETE',
      pattern: new RegExp(`^/${pluralName}/(\\d+)/comments/(\\d+)/?$`),
      controller: controllers.CommentsController,
      action: 'destroy',
      params: (match) => ({ article_id: parseInt(match[1]), id: parseInt(match[2]) })
    });
  }

  return routes;
}

/**
 * Find a route matching the given method and path.
 */
function findRoute(method, path) {
  // Strip base path if present
  const cleanPath = path.replace(/^\/[^/]+\/[^/]+/, '') || path;

  for (const route of _router || []) {
    if (route.method !== method) continue;
    const match = cleanPath.match(route.pattern);
    if (match) {
      return { route, match };
    }
  }
  return null;
}

/**
 * Execute an HTTP request and return a response object.
 */
async function executeRequest(method, path, params = null) {
  const found = findRoute(method, path);

  if (!found) {
    return {
      status: 404,
      body: `No route matches ${method} ${path}`,
      redirect: undefined
    };
  }

  const { route, match } = found;
  const routeParams = route.params(match);
  const context = getContext();

  try {
    // Build action arguments
    const actionArgs = [context];

    // Add route params (like article_id for nested routes)
    if (routeParams.article_id) {
      actionArgs.push(routeParams.article_id);
    }

    // Add id for show/edit/update/destroy
    if (routeParams.id) {
      actionArgs.push(routeParams.id);
    }

    // Add params for create/update
    if (params && (route.action === 'create' || route.action === 'update')) {
      actionArgs.push(params);
    }

    // Call the controller action
    const action = route.controller[route.action];
    if (!action) {
      return {
        status: 500,
        body: `Action ${route.action} not found on controller`,
        redirect: undefined
      };
    }

    const result = await action(...actionArgs);

    // Parse the result
    if (typeof result === 'string') {
      // HTML response
      return {
        status: 200,
        body: result,
        redirect: undefined
      };
    } else if (result && typeof result === 'object') {
      if (result.redirect) {
        return {
          status: 302,
          body: '',
          redirect: String(result.redirect)
        };
      } else if (result.render) {
        return {
          status: 200,
          body: result.render,
          redirect: undefined
        };
      } else if (result.json) {
        return {
          status: 200,
          body: JSON.stringify(result.json),
          redirect: undefined,
          json: result.json
        };
      }
    }

    return {
      status: 200,
      body: result || '',
      redirect: undefined
    };
  } catch (error) {
    return {
      status: 500,
      body: error.message,
      redirect: undefined,
      error
    };
  }
}

/**
 * Perform a GET request.
 */
export async function get(path) {
  return executeRequest('GET', String(path));
}

/**
 * Perform a POST request.
 */
export async function post(path, params = null) {
  return executeRequest('POST', String(path), params);
}

/**
 * Perform a PATCH request.
 */
export async function patch(path, params = null) {
  return executeRequest('PATCH', String(path), params);
}

/**
 * Perform a PUT request.
 */
export async function put(path, params = null) {
  return executeRequest('PUT', String(path), params);
}

/**
 * Perform a DELETE request.
 */
export async function del(path) {
  return executeRequest('DELETE', String(path));
}

// Alias for delete (reserved word)
export { del as delete_ };

/**
 * Load a fixture by model name and key.
 *
 * Fixtures are loaded from YAML files in the fixtures directory:
 *   test/fixtures/articles.yml
 *
 * Example fixture file:
 *   one:
 *     title: First Article
 *     body: This is the first article.
 *
 *   two:
 *     title: Second Article
 *     body: This is the second article.
 *
 * @param {string} modelName - Plural model name (e.g., 'articles')
 * @param {string} key - Fixture key (e.g., 'one')
 * @returns {Object} The created model instance
 */
export async function loadFixture(modelName, key) {
  // Check cache first
  const cacheKey = `${modelName}:${key}`;
  if (_fixtures[cacheKey]) {
    return _fixtures[cacheKey];
  }

  // Load fixture file
  const fixturePath = join(_fixturesDir, `${modelName}.yml`);
  if (!existsSync(fixturePath)) {
    throw new Error(`Fixture file not found: ${fixturePath}`);
  }

  const content = readFileSync(fixturePath, 'utf-8');
  const fixtures = jsYaml.load(content);

  if (!fixtures[key]) {
    throw new Error(`Fixture '${key}' not found in ${fixturePath}`);
  }

  // Find the model class
  // Convert plural to singular and capitalize
  const singular = modelName.endsWith('s') ? modelName.slice(0, -1) : modelName;
  const className = singular.charAt(0).toUpperCase() + singular.slice(1);
  const Model = _models[className];

  if (!Model) {
    throw new Error(`Model '${className}' not found. Available: ${Object.keys(_models).join(', ')}`);
  }

  // Create the model instance
  const data = fixtures[key];

  // Handle foreign key references (e.g., article: one)
  for (const [field, value] of Object.entries(data)) {
    if (typeof value === 'string' && !field.endsWith('_id')) {
      // Check if this is a reference to another fixture
      const refModel = field + 's'; // article -> articles
      const refPath = join(_fixturesDir, `${refModel}.yml`);
      if (existsSync(refPath)) {
        // Load the referenced fixture
        const ref = await loadFixture(refModel, value);
        data[field + '_id'] = ref.id;
        delete data[field];
      }
    }
  }

  const instance = await Model.create(data);
  _fixtures[cacheKey] = instance;
  return instance;
}

/**
 * Load all fixtures for a model.
 *
 * @param {string} modelName - Plural model name (e.g., 'articles')
 * @returns {Object} Map of key -> model instance
 */
export async function loadFixtures(modelName) {
  const fixturePath = join(_fixturesDir, `${modelName}.yml`);
  if (!existsSync(fixturePath)) {
    throw new Error(`Fixture file not found: ${fixturePath}`);
  }

  const content = readFileSync(fixturePath, 'utf-8');
  const fixtures = jsYaml.load(content);

  const result = {};
  for (const key of Object.keys(fixtures)) {
    result[key] = await loadFixture(modelName, key);
  }
  return result;
}
