// Ruby2JS-on-Rails Micro Framework - Base Module
// Shared routing and helper functionality for all targets

// Base Router class with route registration and matching
export class RouterBase {
  static routes = [];
  static controllers = {};

  // Register RESTful routes for a resource
  static resources(name, controller, options = {}) {
    this.controllers[name] = controller;
    const nested = options.nested || [];
    const only = options.only;

    const actions = [
      { method: 'GET', path: `/${name}`, action: 'index' },
      { method: 'GET', path: `/${name}/new`, action: 'new' },
      { method: 'GET', path: `/${name}/:id`, action: 'show' },
      { method: 'GET', path: `/${name}/:id/edit`, action: 'edit' },
      { method: 'POST', path: `/${name}`, action: 'create' },
      { method: 'PATCH', path: `/${name}/:id`, action: 'update' },
      { method: 'DELETE', path: `/${name}/:id`, action: 'destroy' }
    ];

    actions.forEach(route => {
      if (only && !only.includes(route.action)) return;

      // Convert path to regex pattern
      const pattern = new RegExp('^' + route.path.replace(/:id/g, '(\\d+)') + '$');

      this.routes.push({
        method: route.method,
        pattern,
        controller,
        controllerName: name,
        action: route.action
      });
    });

    // Handle nested resources
    nested.forEach(nestedConfig => {
      this.nestedResources(name, nestedConfig.name, nestedConfig.controller, nestedConfig.only);
    });
  }

  // Register nested RESTful routes
  static nestedResources(parentName, name, controller, only) {
    this.controllers[name] = controller;

    const actions = [
      { method: 'GET', path: `/${parentName}/:parent_id/${name}`, action: 'index' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/new`, action: 'new' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/:id`, action: 'show' },
      { method: 'GET', path: `/${parentName}/:parent_id/${name}/:id/edit`, action: 'edit' },
      { method: 'POST', path: `/${parentName}/:parent_id/${name}`, action: 'create' },
      { method: 'PATCH', path: `/${parentName}/:parent_id/${name}/:id`, action: 'update' },
      { method: 'DELETE', path: `/${parentName}/:parent_id/${name}/:id`, action: 'destroy' }
    ];

    actions.forEach(route => {
      if (only && !only.includes(route.action)) return;

      const pattern = new RegExp('^' + route.path
        .replace(/:parent_id/g, '(\\d+)')
        .replace(/:id/g, '(\\d+)') + '$');

      this.routes.push({
        method: route.method,
        pattern,
        controller,
        controllerName: name,
        parentName,
        action: route.action,
        nested: true
      });
    });
  }

  // Add a simple redirect route
  static root(path) {
    this.routes.unshift({
      method: 'GET',
      pattern: /^\/$/,
      redirect: path
    });
  }

  // Find matching route for a path
  static match(path, method = 'GET') {
    for (const route of this.routes) {
      if (route.method !== method) continue;
      const match = path.match(route.pattern);
      if (match) {
        return { route, match };
      }
    }
    return null;
  }
}

// Base Application class with shared configuration
export class ApplicationBase {
  static schema = null;
  static seeds = null;
  static migrations = null;
  static activeRecordModule = null;
  static layoutFn = null;

  // Configure the application
  static configure(options) {
    if (options.schema) this.schema = options.schema;
    if (options.seeds) this.seeds = options.seeds;
    if (options.migrations) this.migrations = options.migrations;
    if (options.layout) this.layoutFn = options.layout;
  }

  // Wrap content in HTML layout
  // Context is passed to layout for access to flash, contentFor, etc.
  static wrapInLayout(context, content) {
    if (this.layoutFn) {
      return this.layoutFn(context, content);
    }
    return content;
  }

  // Initialize the database using the adapter
  static async initDatabase(options = {}) {
    // Import the adapter (selected at build time)
    const adapter = await import('./active_record.mjs');
    this.activeRecordModule = adapter;

    // Initialize database connection
    await adapter.initDatabase(options);

    // Run migrations and check if this is a fresh database
    const { wasFresh } = await this.runMigrations();

    // Run seeds only on fresh database (seeds also guard themselves)
    if (this.seeds && wasFresh) {
      await this.seeds.run();
    }
  }

  // Run pending migrations and track them in schema_migrations
  // For SQL-based databases, check schema_migrations table
  // Returns { ran: number, wasFresh: boolean }
  static async runMigrations() {
    // Fall back to schema if no migrations (legacy support)
    if (!this.migrations || this.migrations.length === 0) {
      if (this.schema && this.schema.create_tables) {
        await this.schema.create_tables();
      }
      return { ran: 0, wasFresh: true };
    }

    const adapter = this.activeRecordModule;
    if (!adapter) return { ran: 0, wasFresh: true };

    // Get already-run migrations from schema_migrations table
    let appliedVersions = new Set();
    try {
      const applied = await adapter.query('SELECT version FROM schema_migrations');
      appliedVersions = new Set(applied.map(r => r.version));
    } catch (e) {
      // Table might not exist on first run - create it
      try {
        await adapter.execute('CREATE TABLE IF NOT EXISTS schema_migrations (version TEXT PRIMARY KEY)');
      } catch (createErr) {
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

      console.log(`Running migration ${migration.version}...`);
      try {
        await migration.up();
        // Record that this migration ran
        await adapter.execute('INSERT INTO schema_migrations (version) VALUES (?)', [migration.version]);
        ran++;
      } catch (e) {
        console.error(`Migration ${migration.version} failed:`, e);
        throw e;
      }
    }

    if (ran > 0) {
      console.log(`Ran ${ran} migration(s)`);
    }

    return { ran, wasFresh };
  }
}

// --- Flash and Context ---

// Create a flash object from a cookie header string
// Shared by all targets - browser uses document.cookie, server uses request headers
export function createFlash(cookieHeader = '') {
  const flash = {
    _pending: {},   // Messages to be set in cookie for next navigation
    _current: {},   // Messages read from cookie (consumed on read)

    // Set a flash message (will be written to cookie)
    set(key, value) {
      this._pending[key] = value;
    },

    // Get and consume a flash message
    get(key) {
      const msg = this._current[key];
      delete this._current[key];
      return msg || '';
    },

    // Convenience methods
    consumeNotice() { return this.get('notice'); },
    consumeAlert() { return this.get('alert'); },

    // Get cookie string for pending messages (for Set-Cookie header or document.cookie)
    getResponseCookie() {
      if (Object.keys(this._pending).length === 0) {
        // Clear the flash cookie if no pending messages but we had current ones
        if (Object.keys(this._current).length > 0) {
          return '_flash=; Path=/; Max-Age=0';
        }
        return null;
      }

      const value = encodeURIComponent(JSON.stringify(this._pending));
      return `_flash=${value}; Path=/`;
    },

    // Check if there are pending messages
    hasPending() {
      return Object.keys(this._pending).length > 0;
    },

    // Write pending flash to document.cookie (browser only)
    writeToCookie() {
      const cookie = this.getResponseCookie();
      if (cookie && typeof document !== 'undefined') {
        document.cookie = cookie;
      }
    }
  };

  // Parse flash from cookie header
  const cookies = cookieHeader.split(';').map(c => c.trim());
  for (const cookie of cookies) {
    if (cookie.startsWith('_flash=')) {
      try {
        const value = cookie.substring(7);
        if (value) {
          flash._current = JSON.parse(decodeURIComponent(value));
        }
      } catch (e) {
        // Invalid flash cookie, ignore
      }
      break;
    }
  }

  return flash;
}

// --- Helper Functions ---

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
// pluralize(2, 'error', 'mistakes') => '2 mistakes'
export function pluralize(count, singular, plural = null) {
  const word = count === 1 ? singular : (plural || singular + 's');
  return `${count} ${word}`;
}

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

// --- Stub functions for API compatibility ---
// These are overridden by browser target but provide no-ops for server targets

export function navigate(event, path) {
  // Server targets handle navigation via HTTP redirects
  return path;
}

export function submitForm(event, handler) {
  // Server targets handle forms via HTTP POST
  return false;
}

export function formData(event) {
  // Server targets parse form data from request body
  return {};
}

export function handleFormResult(result, rerenderFn = null) {
  // Server targets handle results in Router.handleResult
  return false;
}

export function setupFormHandlers(config) {
  // Server targets handle forms via HTTP, no client-side handlers needed
}
