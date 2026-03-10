// Ruby2JS-on-Rails Micro Framework - Browser Target
// Extends base module with DOM-based routing and form handling

import {
  RouterBase,
  ApplicationBase,
  createFlash,
  truncate,
  pluralize,
  dom_id
} from 'juntos/rails_base.js';

// Re-export base helpers
// Note: createContext is defined in this file with browser-specific logic
export { createFlash, truncate, pluralize, dom_id };

// Browser no-ops for layout helpers (CSS/JS handled by Vite, no CSRF needed)
export function stylesheetLinkTag() { return ''; }
export function javascriptImportmapTags() { return ''; }
export function getAssetPath(name) { return `/assets/${name}`; }

// Create a fresh request context for browser navigation
// Each navigation gets its own context with isolated state
export function createContext(params = {}) {
  const cookieHeader = document.cookie || '';

  // Parse cookies into a hash for view access (Rails: cookies[:key])
  const cookies = {};
  cookieHeader.split(';').forEach(c => {
    const eq = c.indexOf('=');
    if (eq > 0) {
      const key = c.substring(0, eq).trim();
      cookies[key] = decodeURIComponent(c.substring(eq + 1).trim());
    }
  });

  return {
    // Content for layout (like Rails content_for)
    contentFor: {},

    // Flash messages - parsed from cookie
    flash: createFlash(cookieHeader),

    // Parsed cookies hash (Rails: cookies[:key])
    cookies: cookies,

    // Request parameters
    params: params,

    // Request info (browser-specific)
    request: {
      path: location.pathname,
      method: 'GET',
      url: location.href,
      headers: null  // Browser doesn't expose request headers
    }
  };
}

// Merge route match params (id, parent_id) into context.params
function mergeRouteParams(context, route, match) {
  if (route.nested) {
    const parentParamName = route.parentName.replace(/s$/, '') + '_id';
    context.params[parentParamName] = parseInt(match[1]);
    if (match[2]) context.params.id = parseInt(match[2]);
  } else if (match[1]) {
    context.params.id = parseInt(match[1]);
  }
}

// Browser Router with DOM-based dispatch
export class Router extends RouterBase {
  // Render a route to a full HTML document string (for Turbo to process)
  // Returns the layout-wrapped HTML, or null if the route wasn't found
  static async renderPage(path, context = null) {
    // Normalize path to string (handle URL objects from Turbo)
    if (path && typeof path !== 'string') {
      path = path.pathname || path.toString();
    }
    console.log(`Started GET "${path}"`);

    if (!context) {
      context = createContext();
    }

    // Parse query parameters into context.params (Rails: params[:key] includes query string)
    try {
      const url = new URL(path, 'http://localhost');
      for (const [key, value] of url.searchParams.entries()) {
        context.params[key] = value;
      }
      path = url.pathname;
    } catch (e) {
      // path doesn't contain query string, no-op
    }

    const result = this.match(path, 'GET');

    if (!result) {
      console.warn('  No route matched');
      return Application.wrapInLayout(context, '<h1>404 Not Found</h1>');
    }

    const { route, match } = result;

    if (route.redirect) {
      // Return null to signal redirect — caller handles it
      return { redirect: route.redirect };
    }

    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`Processing ${controller.name || controllerName}#${action}`);

    try {
      mergeRouteParams(context, route, match);
      let html = await controller[actionMethod](context);

      console.log(`  Rendering ${controllerName}/${action}`);
      context.flash.writeToCookie();
      return Application.wrapInLayout(context, html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      return Application.wrapInLayout(context, '<h1>Not Found</h1>');
    }
  }

  // Dispatch a path to the appropriate controller action
  // Used for non-Turbo rendering (no layout fallback, React elements)
  static async dispatch(path, context = null) {
    if (path && typeof path !== 'string') {
      path = path.pathname || path.toString();
    }
    console.log(`Started GET "${path}"`);

    if (!context) {
      context = createContext();
    }

    const result = this.match(path, 'GET');

    if (!result) {
      console.warn('  No route matched');
      await this.renderContent(context, '<h1>404 Not Found</h1>');
      return;
    }

    const { route, match } = result;

    if (route.redirect) {
      await this.navigate(route.redirect);
      return;
    }

    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`Processing ${controller.name || controllerName}#${action}`);

    try {
      mergeRouteParams(context, route, match);
      let html = await controller[actionMethod](context);

      console.log(`  Rendering ${controllerName}/${action}`);
      await this.renderContent(context, html);
    } catch (e) {
      console.error('  Error:', e.message || e);
      await this.renderContent(context, '<h1>Not Found</h1>');
    }
  }

  // Render content directly to the DOM (used when Turbo isn't handling the response)
  // For validation re-renders, React elements, and no-layout fallback
  static async renderContent(context, content) {
    const resolved = await Promise.resolve(content);

    if (resolved && typeof resolved === 'object' && resolved.$$typeof) {
      // React element - use ReactDOM to render
      const container = document.getElementById('content');
      const wrappedContent = Application.wrapInLayout(context, resolved);

      const { createRoot } = await import('react-dom/client');
      if (container._reactRoot) {
        container._reactRoot.unmount();
      }
      const root = createRoot(container);
      container._reactRoot = root;
      root.render(wrappedContent);
    } else if (Application.layoutFn) {
      // Has layout — render full document and morph body
      const fullHtml = Application.wrapInLayout(context, resolved);
      const parser = new DOMParser();
      const doc = parser.parseFromString(fullHtml, 'text/html');
      if (typeof Turbo !== 'undefined' && Turbo.morphBodyElements) {
        Turbo.morphBodyElements(document.body, doc.body);
      } else {
        document.body.innerHTML = doc.body.innerHTML;
      }
    } else {
      const container = document.getElementById('content');
      container.innerHTML = resolved;
    }

    context.flash.writeToCookie();
  }

  // Navigate to a new path via Turbo (or fallback to manual dispatch)
  static async navigate(path, options = {}) {
    if (options.notice || options.alert) {
      const context = createContext();
      if (options.notice) context.flash.set('notice', options.notice);
      if (options.alert) context.flash.set('alert', options.alert);
      context.flash.writeToCookie();
    }

    if (Application.layoutFn && typeof Turbo !== 'undefined') {
      Turbo.visit(path);
    } else {
      history.pushState({}, '', path);
      await this.dispatch(path);
    }
  }

  // Client-side hydration entry point
  // Called by generated client.js to hydrate server-rendered React content
  // This attaches React event handlers to existing DOM without re-rendering
  static async hydrateAt(rootElement, path, initialProps = {}) {
    console.log(`[juntos] Hydrating at ${path}`);

    // Create context with initial props from server
    const context = createContext(initialProps.params || {});

    // Match the route for this path
    const result = this.match(path, 'GET');

    if (!result) {
      console.warn('[juntos] No route matched for hydration:', path);
      return;
    }

    const { route, match } = result;
    const { controller, controllerName, action } = route;
    const actionMethod = action === 'new' ? '$new' : action;

    console.log(`[juntos] Hydrating ${controllerName}#${action}`);

    try {
      mergeRouteParams(context, route, match);
      let content = await controller[actionMethod](context);

      // Await if content is a promise
      const resolved = await Promise.resolve(content);

      // Check if content is a React element (has $$typeof Symbol)
      if (resolved && typeof resolved === 'object' && resolved.$$typeof) {
        // React element - use hydrateRoot for initial hydration
        const wrappedContent = Application.wrapInLayout(context, resolved);
        const { hydrateRoot } = await import('react-dom/client');

        // Clear any existing React root from previous renders
        if (rootElement._reactRoot) {
          rootElement._reactRoot.unmount();
        }

        // Hydrate the server-rendered content
        const root = hydrateRoot(rootElement, wrappedContent);
        rootElement._reactRoot = root;

        console.log(`[juntos] Hydration complete for ${controllerName}#${action}`);
      } else {
        // HTML string - can't hydrate, just set innerHTML
        console.warn('[juntos] Cannot hydrate HTML string content, using innerHTML');
        const fullHtml = Application.wrapInLayout(context, resolved);
        rootElement.innerHTML = fullHtml;
      }

      // Clear flash cookie after hydration
      context.flash.writeToCookie();
    } catch (e) {
      console.error('[juntos] Hydration error:', e);
      // Fall back to normal client-side rendering
      await this.dispatch(path);
    }
  }
}

// Form submission handlers
export class FormHandler {
  // Handle resource creation
  static async create(controllerName, event) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    // Create context with form params
    const context = createContext(params);

    console.log(`Processing ${controller.name}#create`);
    console.log('  Parameters:', params);

    const result = await controller.create(context, params);
    await this.handleResult(context, result, controllerName, 'new', controller);
    return false;
  }

  // Handle resource update
  static async update(controllerName, event, id) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    // Create context with form params
    const context = createContext(params);

    console.log(`Processing ${controller.name}#update (id: ${id})`);
    console.log('  Parameters:', params);

    const result = await controller.update(context, id, params);
    await this.handleResult(context, result, controllerName, 'edit', controller, id);
    return false;
  }

  // Handle resource deletion
  static async destroy(controllerName, id, confirmMsg = 'Are you sure?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    const context = createContext();

    console.log(`Processing ${controller.name}#destroy (id: ${id})`);

    await controller.destroy(context, id);
    console.log(`  Redirected to /${controllerName}`);
    await Router.navigate(`/${controllerName}`);
  }

  // Handle nested resource creation
  static async createNested(controllerName, parentName, event, parentId) {
    event.preventDefault();
    const controller = Router.controllers[controllerName];
    const form = event.target;
    const params = this.extractParams(form);

    // Create context with form params and route params
    const context = createContext(params);
    const parentParamName = parentName.replace(/s$/, '') + '_id';
    context.params[parentParamName] = parentId;

    console.log(`Processing ${controller.name}#create (${parentParamName}: ${parentId})`);
    console.log('  Parameters:', params);

    const response = await controller.create(context, params);
    // Use controller's redirect path (includes base path from path helpers)
    await this.handleResult(context, response, controllerName, 'create', controller);
    return false;
  }

  // Handle nested resource deletion
  static async destroyNested(controllerName, parentName, parentId, id, confirmMsg = 'Delete this item?') {
    if (!confirm(confirmMsg)) return;

    const controller = Router.controllers[controllerName];
    const context = createContext();
    const parentParamName = parentName.replace(/s$/, '') + '_id';
    context.params[parentParamName] = parentId;
    context.params.id = id;

    console.log(`Processing ${controller.name}#destroy (${parentParamName}: ${parentId}, id: ${id})`);

    const response = await controller.destroy(context);
    // Use controller's redirect path (includes base path from path helpers)
    await this.handleResult(context, response, controllerName, 'destroy', controller, id);
  }

  // Extract form parameters
  // Handles Rails-style nested params: article[title] -> params.article.title
  static extractParams(form) {
    const params = {};
    const inputs = form.querySelectorAll('input, textarea, select');
    inputs.forEach(input => {
      if (input.name && input.type !== 'submit') {
        // Parse nested param names: article[title] -> {article: {title: value}}
        const match = input.name.match(/^([^\[]+)\[([^\]]+)\]$/);
        if (match) {
          const [, model, key] = match;
          if (!params[model]) params[model] = {};
          params[model][key] = input.value;
        } else {
          params[input.name] = input.value;
        }
      } else if (input.id && input.type !== 'submit') {
        params[input.id] = input.value;
      }
    });
    return params;
  }

  // Handle controller result (redirect, render, or turbo_stream)
  static async handleResult(context, result, controllerName, action, controller, id = null) {
    if (result.turbo_stream) {
      // Turbo Stream response - apply partial page update via Turbo
      console.log(`  Rendering turbo_stream response`);
      if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(result.turbo_stream);
      } else {
        console.warn('Turbo.renderStreamMessage not available');
      }
    } else if (result.redirect) {
      // Set flash messages before redirect
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      context.flash.writeToCookie();

      console.log(`  Redirected to ${result.redirect}`);
      await Router.navigate(result.redirect);
    } else if (result.render) {
      console.log(`  Rendering ${controllerName}/${action} (validation failed)`);
      await Router.renderContent(context, result.render);
    }
  }
}

// Browser Application
export class Application extends ApplicationBase {
  static sqlJsPath = '/node_modules/sql.js/dist';

  // Configure the application
  static configure(options) {
    super.configure(options);
    if (options.sqlJsPath) this.sqlJsPath = options.sqlJsPath;
  }

  // Initialize the database using the adapter
  static async initDatabase() {
    // Import the adapter (resolved via virtual module at build time)
    const adapter = await import('juntos:active-record');
    this.activeRecordModule = adapter;

    // Populate model registry for association resolution (avoids circular dependencies)
    if (adapter.modelRegistry && this.models) {
      Object.assign(adapter.modelRegistry, this.models);
    }

    // Initialize with config (DB_CONFIG is injected by the virtual module at build time)
    await adapter.initDatabase({ ...adapter.DB_CONFIG, sqlJsPath: this.sqlJsPath });

    // For Dexie adapter: define schema and open database
    if (adapter.defineSchema) {
      // Always register schema_migrations table for tracking
      adapter.registerSchema('schema_migrations', '&version');

      if (this.schema && this.schema.tableSchemas) {
        for (const [table, schema] of Object.entries(this.schema.tableSchemas)) {
          adapter.registerSchema(table, schema);
        }
      } else if (this.migrations) {
        // Collect table schemas from all migrations
        // Each migration may have a tableSchemas property with Dexie schema strings
        for (const migration of this.migrations) {
          if (migration.tableSchemas) {
            for (const [table, schema] of Object.entries(migration.tableSchemas)) {
              adapter.registerSchema(table, schema);
            }
          }
        }
      }
      adapter.defineSchema(1);
      await adapter.openDatabase();
    }

    // Make DB available globally for sql.js compatibility
    window.DB = adapter.getDatabase();

    // Initialize Active Storage if available (must happen before views render
    // so that attachment checks like clip.audio.attached?() can load from IndexedDB)
    try {
      const storage = await import('juntos:active-storage');
      if (storage.initActiveStorage) {
        await storage.initActiveStorage();
      }
    } catch (e) {
      // Active Storage not available - no-op
    }

    // Run migrations and check if this is a fresh database
    const { wasFresh } = await this.runMigrations(adapter);

    // Run seeds only on fresh database (seeds also guard themselves)
    if (this.seeds && wasFresh) {
      await this.seeds.run();
    }
  }

  // Run pending migrations and track them in schema_migrations
  // Returns { ran: number, wasFresh: boolean }
  // Supports both Dexie (IndexedDB) and SQL adapters (sql.js, pglite, better-sqlite3)
  static async runMigrations(adapter) {
    if (!this.migrations || this.migrations.length === 0) {
      // Fall back to schema if no migrations
      if (this.schema && this.schema.create_tables) {
        this.schema.create_tables();
      }
      return { ran: 0, wasFresh: true };
    }

    // Detect adapter type: SQL adapters have query/execute, Dexie doesn't
    const isSqlAdapter = typeof adapter.query === 'function' && typeof adapter.execute === 'function';
    let appliedVersions = new Set();

    if (isSqlAdapter) {
      // SQL adapter path (sql.js, pglite, better-sqlite3)
      try {
        await adapter.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)');
        const applied = await adapter.query('SELECT version FROM schema_migrations');
        appliedVersions = new Set(applied.map(r => r.version));
      } catch (e) {
        console.log('First database initialization');
      }
    } else {
      // Dexie (IndexedDB) path
      const db = adapter.getDatabase();
      try {
        const applied = await db.table('schema_migrations').toArray();
        appliedVersions = new Set(applied.map(r => r.version));
      } catch (e) {
        console.log('First database initialization');
      }
    }

    // Track if database was fresh (no prior migrations)
    const wasFresh = appliedVersions.size === 0;

    // Run pending migrations in order
    let ran = 0;
    for (const migration of this.migrations) {
      if (appliedVersions.has(migration.version)) {
        continue;
      }

      console.debug(`Running migration ${migration.version}...`);
      try {
        await migration.up(adapter);
        // Record that this migration ran
        if (isSqlAdapter) {
          await adapter.execute('INSERT INTO schema_migrations (version) VALUES (?)', [migration.version]);
        } else {
          await adapter.getDatabase().table('schema_migrations').add({ version: migration.version });
        }
        ran++;
      } catch (e) {
        console.error(`Migration ${migration.version} failed:`, e);
        throw e;
      }
    }

    if (ran > 0) {
      console.debug(`Ran ${ran} migration(s)`);
    }

    return { ran, wasFresh };
  }

  // Start the application
  static async start() {
    try {
      await this.initDatabase();

      if (!this.layoutFn) {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('app').style.display = 'block';
      }

      // Intercept Turbo fetch requests for client-side handling
      document.addEventListener('turbo:before-fetch-request', async (event) => {
        const fetchOptions = event.detail.fetchOptions;
        let method = fetchOptions.method?.toUpperCase() || 'GET';
        const url = new URL(event.detail.url);

        // Only intercept same-origin requests
        if (url.origin !== location.origin) {
          return; // Let Turbo handle external URLs
        }

        // Check for Rails _method override (e.g., DELETE via POST form)
        const body = fetchOptions.body;
        if (body instanceof URLSearchParams) {
          const override = body.get('_method');
          if (override) method = override.toUpperCase();
        } else if (body instanceof FormData) {
          const override = body.get('_method');
          if (override) method = override.toUpperCase();
        }

        // Strip format extension (.json, .html, .turbo_stream) for route matching
        let path = url.pathname;
        let format = null;
        const formatMatch = path.match(/\.(json|html|turbo_stream)$/);
        if (formatMatch) {
          format = formatMatch[1];
          path = path.slice(0, -formatMatch[0].length);
        }

        const result = Router.match(path, method);

        if (!result) {
          return; // No matching route, let Turbo handle it
        }

        // All matched requests: preventDefault + async render + resume
        // Turbo dispatches the event synchronously, so we must pause it
        event.preventDefault();

        const { route, match } = result;
        const context = createContext();

        // GET HTML: render page, return as synthetic Response
        if (method === 'GET' && format !== 'json' && this.layoutFn) {
          const rendered = await Router.renderPage(path);

          if (rendered && rendered.redirect) {
            Turbo.visit(rendered.redirect);
            return;
          }

          const html = rendered || Application.wrapInLayout(context, '<h1>Not Found</h1>');
          event.detail.fetchRequest = {
            response: Promise.resolve(new Response(html, {
              status: 200,
              headers: { 'Content-Type': 'text/html; charset=utf-8' }
            }))
          };
          event.detail.resume();
          return;
        }

        // GET JSON: render data as JSON Response
        if (method === 'GET' && format === 'json') {
          const { controller, action } = route;
          const actionMethod = action === 'new' ? '$new' : action;

          try {
            mergeRouteParams(context, route, match);
            let data = await controller[actionMethod](context);

            let jsonData = data;
            if (data && typeof data === 'object' && 'json' in data) {
              jsonData = data.json;
            }

            event.detail.fetchRequest = {
              response: Promise.resolve(new Response(JSON.stringify(jsonData), {
                status: 200,
                headers: { 'Content-Type': 'application/json' }
              }))
            };
          } catch (e) {
            console.error(`[juntos] JSON API error for ${path}:`, e);
            event.detail.fetchRequest = {
              response: Promise.resolve(new Response(JSON.stringify({ error: e.message }), {
                status: 500,
                headers: { 'Content-Type': 'application/json' }
              }))
            };
          }
          event.detail.resume();
          return;
        }

        // Form submissions (POST/PATCH/PUT/DELETE): run controller, return Response
        if (method === 'POST' || method === 'PATCH' || method === 'PUT' || method === 'DELETE') {
          context.request.headers = { accept: 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml' };

          // Extract params from request body
          let params = {};
          if (method !== 'DELETE') {
            const setNestedParam = (key, value) => {
              if (key === '_method') return;
              const paramMatch = key.match(/^([^\[]+)\[([^\]]+)\]$/);
              if (paramMatch) {
                const [, model, field] = paramMatch;
                if (!params[model]) params[model] = {};
                params[model][field] = value;
              } else {
                params[key] = value;
              }
            };

            if (body instanceof FormData) {
              for (const [key, value] of body.entries()) setNestedParam(key, value);
            } else if (body instanceof URLSearchParams) {
              for (const [key, value] of body.entries()) setNestedParam(key, value);
            } else if (typeof body === 'string') {
              for (const [key, value] of new URLSearchParams(body).entries()) setNestedParam(key, value);
            }
            context.params = params;
            console.log('  Parameters:', params);
          }

          // Merge route params into context
          mergeRouteParams(context, route, match);

          // Run controller action
          let controllerResult;
          if (method === 'DELETE') {
            controllerResult = await route.controller.destroy(context);
          } else {
            const controllerAction = route.controller[route.action];
            if (controllerAction) {
              controllerResult = await controllerAction.call(route.controller, context, params);
            }
          }

          // Translate controller result to HTTP Response for Turbo
          if (controllerResult?.turbo_stream) {
            console.log(`  Rendering turbo_stream response`);
            event.detail.fetchRequest = {
              response: Promise.resolve(new Response(controllerResult.turbo_stream, {
                status: 200,
                headers: { 'Content-Type': 'text/vnd.turbo-stream.html; charset=utf-8' }
              }))
            };
            event.detail.resume();
          } else if (controllerResult?.redirect) {
            if (controllerResult.notice) context.flash.set('notice', controllerResult.notice);
            if (controllerResult.alert) context.flash.set('alert', controllerResult.alert);
            context.flash.writeToCookie();
            console.log(`  Redirected to ${controllerResult.redirect}`);
            // Use Turbo.visit for redirects — Response.redirect doesn't work
            // with synthetic responses (response.redirected is false)
            Turbo.visit(controllerResult.redirect);
          } else if (controllerResult?.render) {
            console.log(`  Rendering form (validation failed)`);
            const html = this.layoutFn
              ? Application.wrapInLayout(context, controllerResult.render)
              : controllerResult.render;
            event.detail.fetchRequest = {
              response: Promise.resolve(new Response(html, {
                status: 422,
                headers: { 'Content-Type': 'text/html; charset=utf-8' }
              }))
            };
            event.detail.resume();
          }
          return;
        }
      });

      if (!this.layoutFn) {
        // No layout: use manual popstate + dispatch (legacy behavior)
        window.addEventListener('popstate', async () => {
          await Router.dispatch(location.pathname);
        });

        // Intercept Turbo link clicks for client-side routing
        document.addEventListener('turbo:before-visit', async (event) => {
          event.preventDefault();
          const url = new URL(event.detail.url);
          history.pushState({}, '', url.pathname);
          await Router.dispatch(url.pathname);
        });
      }

      // Initial route - check for GitHub Pages SPA redirect first
      let initialPath = location.pathname || '/';
      const redirectPath = sessionStorage.getItem('spa-redirect-path');
      if (redirectPath) {
        sessionStorage.removeItem('spa-redirect-path');
        initialPath = redirectPath;
        history.replaceState({}, '', initialPath);
      }

      if (this.layoutFn && typeof Turbo !== 'undefined') {
        // Let Turbo handle the initial visit — triggers turbo:before-fetch-request
        // which renders the page and provides a synthetic response
        Turbo.visit(initialPath, { action: 'replace' });
      } else {
        await Router.dispatch(initialPath);
      }
    } catch (e) {
      const loadingEl = document.getElementById('loading');
      if (loadingEl) {
        loadingEl.innerHTML =
          `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      } else {
        document.body.innerHTML =
          `<p style="color: red;">Error: ${e.message}</p><pre>${e.stack}</pre>`;
      }
      console.error(e);
    }
  }
}

// Navigation helper - prevents default, catches errors
export async function navigate(event, path) {
  event?.preventDefault?.();
  try {
    history.pushState({}, '', path);
    await Router.dispatch(path);
  } catch (e) {
    console.error('Navigation error:', e);
  }
  return false;
}

// Form submission helper - prevents default, catches errors
export async function submitForm(event, handler) {
  event?.preventDefault?.();
  try {
    // Create context for form submission
    const context = createContext(FormHandler.extractParams(event?.target));
    const result = await handler(context, event);

    if (result?.turbo_stream) {
      // Turbo Stream response - apply partial page update via Turbo
      console.log(`  Rendering turbo_stream response`);
      if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(result.turbo_stream);
      }
    } else if (result?.redirect) {
      // Set flash messages before redirect
      if (result.notice) {
        context.flash.set('notice', result.notice);
      }
      if (result.alert) {
        context.flash.set('alert', result.alert);
      }
      context.flash.writeToCookie();

      console.log(`  Redirected to ${result.redirect}`);
      history.pushState({}, '', result.redirect);
      await Router.dispatch(result.redirect);
    } else if (result?.render) {
      console.log(`  Re-rendering form (validation failed)`);
      await Router.renderContent(context, result.render);
    }
    return result;
  } catch (e) {
    console.error('Form submission error:', e);
  }
  return false;
}

// Extract form data from a submit event
export function formData(event) {
  event?.preventDefault?.();
  const form = event?.target;
  if (!form) return {};
  return FormHandler.extractParams(form);
}

// Handle form submission result (context-aware)
export async function handleFormResult(context, result, rerenderFn = null) {
  if (result?.turbo_stream) {
    // Turbo Stream response - apply partial page update via Turbo
    console.log(`  Rendering turbo_stream response`);
    if (typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
      Turbo.renderStreamMessage(result.turbo_stream);
    }
  } else if (result?.redirect) {
    // Set flash messages before redirect
    if (result.notice) {
      context.flash.set('notice', result.notice);
    }
    if (result.alert) {
      context.flash.set('alert', result.alert);
    }
    context.flash.writeToCookie();

    console.log(`  Redirected to ${result.redirect}`);
    await Router.navigate(result.redirect);
  } else if (result?.render) {
    console.log(`  Re-rendering form (validation failed)`);
    await Router.renderContent(context, result.render);
  }
  return false;
}

// Set up form handlers on window
export function setupFormHandlers(config) {
  config.forEach(({ resource, handlerName, parent, confirmDelete }) => {
    if (parent) {
      window[`create${handlerName}`] = function(event, parentId) {
        event.preventDefault();
        try {
          FormHandler.createNested(resource, parent, event, parentId);
        } catch(e) {
          console.error(`Error in create${handlerName}:`, e);
        }
        return false;
      };
      window[`delete${handlerName}`] = (parentId, id) =>
        FormHandler.destroyNested(resource, parent, parentId, id, confirmDelete);
    } else {
      window[`create${handlerName}`] = function(event) {
        event.preventDefault();
        try {
          FormHandler.create(resource, event);
        } catch(e) {
          console.error(`Error in create${handlerName}:`, e);
        }
        return false;
      };
      window[`update${handlerName}`] = function(event, id) {
        event.preventDefault();
        try {
          FormHandler.update(resource, event, id);
        } catch(e) {
          console.error(`Error in update${handlerName}:`, e);
        }
        return false;
      };
      window[`delete${handlerName}`] = (id) =>
        FormHandler.destroy(resource, id, confirmDelete);
    }
  });
}

// Turbo Streams Broadcasting via BroadcastChannel API
// Used for real-time updates between browser windows/tabs
export class TurboBroadcast {
  // Cache of BroadcastChannel instances by name
  static channels = new Map();

  // Get or create a BroadcastChannel for the given name
  static getChannel(name) {
    if (!this.channels.has(name)) {
      const channel = new globalThis.BroadcastChannel(name);
      this.channels.set(name, channel);
    }
    return this.channels.get(name);
  }

  // Broadcast a message to all subscribers
  // Called by model broadcast_*_to and broadcast_json_to methods
  static broadcast(channelName, html) {
    console.log(`  [Broadcast] ${channelName}:`, html.substring(0, 100) + (html.length > 100 ? '...' : ''));
    const channel = this.getChannel(channelName);
    channel.postMessage(html);
    // Only render via Turbo for Turbo Stream content (not JSON broadcasts)
    if (html.startsWith('<turbo-stream') && typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
      Turbo.renderStreamMessage(html);
    }
  }

  // Subscribe to turbo-stream messages on a channel
  // Used by turbo_stream_from helper in views
  // Returns empty string for ERB interpolation compatibility
  static subscribe(channelName, callback) {
    console.log(`  [Subscribe] ${channelName}`);
    const channel = this.getChannel(channelName);
    channel.onmessage = (event) => {
      console.log(`  [Received] ${channelName}:`, event.data.substring(0, 100) + (event.data.length > 100 ? '...' : ''));
      // Only render via Turbo for Turbo Stream content (not JSON broadcasts)
      if (event.data.startsWith('<turbo-stream') && typeof Turbo !== 'undefined' && Turbo.renderStreamMessage) {
        Turbo.renderStreamMessage(event.data);
      }
      // Also call custom callback if provided
      if (callback) {
        callback(event.data);
      }
    };
    return '';
  }

  // Unsubscribe and close a channel
  static unsubscribe(channelName) {
    const channel = this.channels.get(channelName);
    if (channel) {
      channel.close();
      this.channels.delete(channelName);
    }
  }
}

// Export BroadcastChannel as alias for model broadcast methods
// Models call: BroadcastChannel.broadcast("channel", html)
export { TurboBroadcast as BroadcastChannel };

// Set on globalThis for instance methods in active_record_base.mjs
// (Can't shadow native BroadcastChannel since we use it internally)
globalThis.TurboBroadcast = TurboBroadcast;

// Helper function for views to subscribe to turbo streams
// Usage in ERB: <%= turbo_stream_from "chat_room" %>
export function turbo_stream_from(channelName) {
  TurboBroadcast.subscribe(channelName);
  // Return empty string - subscription is a side effect
  return '';
}
