// ActiveRecord adapter for Supabase (Serverless Postgres)
// This file is copied to dist/lib/active_record.mjs at build time
// Supabase uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { createClient } from '@supabase/supabase-js';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';

// Re-export shared utilities
export { attr_accessor };

// Configuration injected at build time
const DB_CONFIG = {};

let supabase = null;

// Initialize the database connection
export async function initDatabase(options = {}) {
  // Priority: runtime env vars > options > build-time config
  const supabaseUrl = process.env.SUPABASE_URL || options.url || DB_CONFIG.url;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY ||
                      process.env.SUPABASE_ANON_KEY ||
                      options.key ||
                      DB_CONFIG.key;

  if (!supabaseUrl || !supabaseKey) {
    throw new Error('Supabase requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY) environment variables');
  }

  supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });

  // Time polyfill for Ruby compatibility
  initTimePolyfill(globalThis);

  // Extract project ref from URL for logging
  const projectRef = supabaseUrl.match(/https:\/\/([^.]+)/)?.[1] || 'supabase';
  console.log(`Connected to Supabase: ${projectRef}`);

  return supabase;
}

// Execute raw SQL (for schema creation)
// Uses Supabase's postgres connection via rpc or direct query
export async function execSQL(sqlString) {
  // For DDL operations, we need to use the SQL editor API or migrations
  // This is a limitation - Supabase PostgREST doesn't support arbitrary SQL
  // For now, throw an error directing users to use migrations
  throw new Error(
    'Supabase adapter: execSQL not supported. Use Supabase migrations for schema changes:\n' +
    '  supabase migration new <name>\n' +
    '  supabase db push'
  );
}

// PostgreSQL type mapping from abstract Rails types
const PG_TYPE_MAP = {
  string: 'VARCHAR(255)',
  text: 'TEXT',
  integer: 'INTEGER',
  bigint: 'BIGINT',
  float: 'DOUBLE PRECISION',
  decimal: 'DECIMAL',
  boolean: 'BOOLEAN',
  date: 'DATE',
  datetime: 'TIMESTAMP WITH TIME ZONE',
  time: 'TIME',
  timestamp: 'TIMESTAMP WITH TIME ZONE',
  binary: 'BYTEA',
  json: 'JSON',
  jsonb: 'JSONB'
};

// Schema operations - these generate SQL for migrations
// Users should run these via `supabase migration new` and copy the output
export async function createTable(tableName, columns, options = {}) {
  // Generate the SQL that would create this table
  const columnDefs = columns.map(col => {
    let def;

    if (col.primaryKey && col.autoIncrement) {
      def = `${col.name} SERIAL PRIMARY KEY`;
    } else {
      const sqlType = getPgType(col);
      def = `${col.name} ${sqlType}`;

      if (col.primaryKey) def += ' PRIMARY KEY';
      if (col.null === false) def += ' NOT NULL';
      if (col.default !== undefined) {
        def += ` DEFAULT ${formatDefaultValue(col.default, col.type)}`;
      }
    }

    return def;
  });

  if (options.foreignKeys) {
    for (const fk of options.foreignKeys) {
      columnDefs.push(
        `FOREIGN KEY (${fk.column}) REFERENCES ${fk.references}(${fk.primaryKey})`
      );
    }
  }

  const ddl = `CREATE TABLE IF NOT EXISTS ${tableName} (${columnDefs.join(', ')})`;

  // Log the SQL for migration purposes
  console.log(`-- Supabase Migration SQL:\n${ddl};`);

  // For development convenience, try to execute via RPC if a helper function exists
  // This requires creating a `exec_sql` function in Supabase with SECURITY DEFINER
  try {
    const { error } = await supabase.rpc('exec_sql', { query: ddl });
    if (error && !error.message.includes('already exists')) {
      console.warn(`Note: To run DDL, create an exec_sql function or use migrations`);
    }
  } catch (e) {
    console.warn(`Schema change requires migration: ${ddl}`);
  }
}

export async function addIndex(tableName, columns, options = {}) {
  const unique = options.unique ? 'UNIQUE ' : '';
  const indexName = options.name || `idx_${tableName}_${columns.join('_')}`;
  const columnList = Array.isArray(columns) ? columns.join(', ') : columns;

  const ddl = `CREATE ${unique}INDEX IF NOT EXISTS ${indexName} ON ${tableName}(${columnList})`;
  console.log(`-- Supabase Migration SQL:\n${ddl};`);

  try {
    await supabase.rpc('exec_sql', { query: ddl });
  } catch (e) {
    console.warn(`Index creation requires migration: ${ddl}`);
  }
}

export async function addColumn(tableName, columnName, columnType) {
  const sqlType = PG_TYPE_MAP[columnType] || 'TEXT';
  const ddl = `ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${sqlType}`;
  console.log(`-- Supabase Migration SQL:\n${ddl};`);
}

export async function removeColumn(tableName, columnName) {
  const ddl = `ALTER TABLE ${tableName} DROP COLUMN ${columnName}`;
  console.log(`-- Supabase Migration SQL:\n${ddl};`);
}

export async function dropTable(tableName) {
  const ddl = `DROP TABLE IF EXISTS ${tableName}`;
  console.log(`-- Supabase Migration SQL:\n${ddl};`);
}

function getPgType(col) {
  let baseType = PG_TYPE_MAP[col.type] || 'TEXT';

  if (col.type === 'decimal' && (col.precision || col.scale)) {
    const precision = col.precision || 10;
    const scale = col.scale || 0;
    baseType = `DECIMAL(${precision}, ${scale})`;
  }

  if (col.type === 'string' && col.limit) {
    baseType = `VARCHAR(${col.limit})`;
  }

  return baseType;
}

function formatDefaultValue(value, type) {
  if (value === null) return 'NULL';
  if (typeof value === 'string') return `'${value.replace(/'/g, "''")}'`;
  if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
  return String(value);
}

// Get the raw Supabase client
export function getDatabase() {
  return supabase;
}

// Query interface for rails_base.js migration system
export async function query(sqlString, params = []) {
  // Use RPC for raw queries if available
  const { data, error } = await supabase.rpc('exec_sql', {
    query: sqlString,
    params: params
  });
  if (error) throw error;
  return data || [];
}

// Execute interface for rails_base.js migration system
export async function execute(sqlString, params = []) {
  const { error } = await supabase.rpc('exec_sql', {
    query: sqlString,
    params: params
  });
  if (error) throw error;
  return { changes: 0 };
}

// Insert a row using PostgREST
export async function insert(tableName, data) {
  const { error } = await supabase
    .from(tableName)
    .insert(data);
  if (error) throw error;
}

// Close the connection (no-op for HTTP-based Supabase)
export async function closeDatabase() {
  supabase = null;
}

// Supabase-specific ActiveRecord implementation
// Uses PostgREST query builder for efficient data operations
export class ActiveRecord extends ActiveRecordBase {
  // --- Class Methods (finders) ---

  static async all() {
    const { data, error } = await supabase
      .from(this.tableName)
      .select('*');
    if (error) throw error;
    return data.map(row => new this(row));
  }

  // Eager loading hint - Supabase handles this via PostgREST select syntax
  // For now, returns the class itself for method chaining (no-op)
  static includes(...associations) {
    return this;
  }

  static async find(id) {
    const { data, error } = await supabase
      .from(this.tableName)
      .select('*')
      .eq('id', id)
      .single();

    if (error) {
      if (error.code === 'PGRST116') {
        throw new Error(`${this.name} not found with id=${id}`);
      }
      throw error;
    }
    return new this(data);
  }

  static async findBy(conditions) {
    let query = supabase.from(this.tableName).select('*');

    for (const [key, value] of Object.entries(conditions)) {
      query = query.eq(key, value);
    }

    const { data, error } = await query.limit(1).maybeSingle();
    if (error) throw error;
    return data ? new this(data) : null;
  }

  static async where(conditions) {
    let query = supabase.from(this.tableName).select('*');

    for (const [key, value] of Object.entries(conditions)) {
      query = query.eq(key, value);
    }

    const { data, error } = await query;
    if (error) throw error;
    return data.map(row => new this(row));
  }

  static async count() {
    const { count, error } = await supabase
      .from(this.tableName)
      .select('*', { count: 'exact', head: true });
    if (error) throw error;
    return count;
  }

  static async first() {
    const { data, error } = await supabase
      .from(this.tableName)
      .select('*')
      .order('id', { ascending: true })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    return data ? new this(data) : null;
  }

  static async last() {
    const { data, error } = await supabase
      .from(this.tableName)
      .select('*')
      .order('id', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (error) throw error;
    return data ? new this(data) : null;
  }

  // Order records by column - returns array of models
  // Usage: Message.order({created_at: 'asc'}) or Message.order('created_at')
  static async order(options) {
    let column, ascending;
    if (typeof options === 'string') {
      column = options;
      ascending = true;
    } else {
      column = Object.keys(options)[0];
      const dir = options[column];
      ascending = !(dir === 'desc' || dir === ':desc');
    }

    const { data, error } = await supabase
      .from(this.tableName)
      .select('*')
      .order(column, { ascending });
    if (error) throw error;
    return data.map(row => new this(row));
  }

  // --- Instance Methods ---

  async destroy() {
    if (!this._persisted) return false;

    const { error } = await supabase
      .from(this.constructor.tableName)
      .delete()
      .eq('id', this.id);

    if (error) throw error;

    this._persisted = false;
    console.log(`  ${this.constructor.name} Destroy (id: ${this.id})`);
    await this._runCallbacks('after_destroy_commit');
    return true;
  }

  async reload() {
    if (!this.id) return this;
    const fresh = await this.constructor.find(this.id);
    this.attributes = fresh.attributes;
    for (const [key, value] of Object.entries(this.attributes)) {
      if (key !== 'id') {
        this[key] = value;
      }
    }
    return this;
  }

  // --- Private helpers ---

  async _insert() {
    const data = {};
    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      data[key] = value;
    }

    console.debug(`  ${this.constructor.name} Create`, data);

    const { data: result, error } = await supabase
      .from(this.constructor.tableName)
      .insert(data)
      .select('id')
      .single();

    if (error) throw error;

    this.id = result.id;
    this.attributes.id = this.id;
    this._persisted = true;
    console.log(`  ${this.constructor.name} Create (id: ${this.id})`);
    return true;
  }

  async _update() {
    const data = {};
    for (const [key, value] of Object.entries(this.attributes)) {
      if (key === 'id') continue;
      data[key] = value;
    }

    console.debug(`  ${this.constructor.name} Update (id: ${this.id})`, data);

    const { error } = await supabase
      .from(this.constructor.tableName)
      .update(data)
      .eq('id', this.id);

    if (error) throw error;

    console.log(`  ${this.constructor.name} Update (id: ${this.id})`);
    return true;
  }

  static _buildWhere(conditions) {
    // For PostgREST, we return the conditions object directly
    // This is only used as fallback
    const clauses = [];
    const values = [];
    let paramIndex = 1;
    for (const [key, value] of Object.entries(conditions)) {
      clauses.push(`${key} = $${paramIndex++}`);
      values.push(value);
    }
    return { where: clauses.join(' AND '), values };
  }

  static _resultToModels(rows) {
    return rows.map(row => new this(row));
  }
}
