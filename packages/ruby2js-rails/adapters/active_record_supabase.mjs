// ActiveRecord adapter for Supabase (Serverless Postgres)
// This file is copied to dist/lib/active_record.mjs at build time
// Supabase uses HTTP/WebSocket, works in browser, Node.js, and edge runtimes

import { createClient } from '@supabase/supabase-js';

import { ActiveRecordBase, attr_accessor, initTimePolyfill } from 'ruby2js-rails/adapters/active_record_base.mjs';
import { Relation } from 'ruby2js-rails/adapters/relation.mjs';
import { CollectionProxy } from 'ruby2js-rails/adapters/collection_proxy.mjs';
import { singularize } from 'ruby2js-rails/adapters/inflector.mjs';

// Re-export shared utilities
export { attr_accessor, CollectionProxy };

// Model registry for association resolution (populated by Application.registerModels)
export const modelRegistry = {};

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
  // --- Class Methods (chainable - return Relation) ---

  // Returns a Relation that can be chained or awaited
  static all() {
    return new Relation(this);
  }

  // Returns a Relation with conditions
  static where(conditionOrSql, ...values) {
    return new Relation(this).where(conditionOrSql, ...values);
  }

  // Returns a Relation with ordering
  static order(options) {
    return new Relation(this).order(options);
  }

  // Returns a Relation with limit
  static limit(n) {
    return new Relation(this).limit(n);
  }

  // Returns a Relation with offset
  static offset(n) {
    return new Relation(this).offset(n);
  }

  // Returns a Relation with eager-loaded associations
  static includes(...associations) {
    return new Relation(this).includes(...associations);
  }

  // --- Class Methods (terminal - execute immediately) ---

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

  // Convenience methods that delegate to Relation
  static async first() {
    return new Relation(this).first();
  }

  static async last() {
    return new Relation(this).last();
  }

  static async count() {
    return new Relation(this).count();
  }

  // Check if any records exist
  static async exists() {
    return new Relation(this).exists();
  }

  // Return values instead of model instances
  static async pluck(...columns) {
    return new Relation(this).pluck(...columns);
  }

  // --- Relation Execution (called by Relation class) ---

  // Execute a Relation and return model instances
  static async _executeRelation(rel) {
    let query = supabase.from(this.tableName).select('*');

    // Apply hash conditions
    for (const cond of rel._conditions) {
      for (const [key, value] of Object.entries(cond)) {
        if (Array.isArray(value)) {
          query = query.in(key, value);
        } else if (value === null) {
          query = query.is(key, null);
        } else {
          query = query.eq(key, value);
        }
      }
    }

    // Apply raw SQL conditions (limited support - basic comparisons)
    // Supabase PostgREST doesn't support arbitrary SQL, so we handle common patterns
    for (const raw of rel._rawConditions || []) {
      // Parse simple patterns like "column > ?" or "column = ?"
      const match = raw.sql.match(/^(\w+)\s*(=|>|<|>=|<=|<>|!=)\s*\?$/);
      if (match && raw.values.length === 1) {
        const [, col, op] = match;
        const val = raw.values[0];
        switch (op) {
          case '=': query = query.eq(col, val); break;
          case '>': query = query.gt(col, val); break;
          case '<': query = query.lt(col, val); break;
          case '>=': query = query.gte(col, val); break;
          case '<=': query = query.lte(col, val); break;
          case '<>':
          case '!=': query = query.neq(col, val); break;
        }
      }
    }

    // Apply ordering
    if (rel._order) {
      const [col, dir] = this._parseOrder(rel._order);
      query = query.order(col, { ascending: dir === 'asc' });
    }

    // Apply offset
    if (rel._offset != null) {
      query = query.range(rel._offset, rel._offset + (rel._limit || 1000) - 1);
    } else if (rel._limit != null) {
      query = query.limit(rel._limit);
    }

    const { data, error } = await query;
    if (error) throw error;

    const records = data.map(row => new this(row));

    // Load included associations if any
    if (rel._includes && rel._includes.length > 0) {
      await this._loadAssociations(records, rel._includes);
    }

    return records;
  }

  // Execute a COUNT query for a Relation
  static async _executeCount(rel) {
    let query = supabase.from(this.tableName).select('*', { count: 'exact', head: true });

    // Apply conditions
    for (const cond of rel._conditions) {
      for (const [key, value] of Object.entries(cond)) {
        if (Array.isArray(value)) {
          query = query.in(key, value);
        } else if (value === null) {
          query = query.is(key, null);
        } else {
          query = query.eq(key, value);
        }
      }
    }

    const { count, error } = await query;
    if (error) throw error;
    return count;
  }

  // Execute an EXISTS query for a Relation
  static async _executeExists(rel) {
    const limitedRel = Object.create(rel);
    limitedRel._limit = 1;
    const records = await this._executeRelation(limitedRel);
    return records.length > 0;
  }

  // Execute a PLUCK query for a Relation (returns values, not models)
  static async _executePluck(rel, columns) {
    let query = supabase.from(this.tableName).select(columns.join(', '));

    // Apply conditions
    for (const cond of rel._conditions) {
      for (const [key, value] of Object.entries(cond)) {
        if (Array.isArray(value)) {
          query = query.in(key, value);
        } else {
          query = query.eq(key, value);
        }
      }
    }

    const { data, error } = await query;
    if (error) throw error;

    // Single column: return flat array of values
    if (columns.length === 1) {
      return data.map(row => row[columns[0]]);
    }
    // Multiple columns: return array of arrays
    return data.map(row => columns.map(col => row[col]));
  }

  // Parse order option into [column, direction]
  static _parseOrder(order) {
    if (typeof order === 'string') {
      return [order, 'asc'];
    }
    const col = Object.keys(order)[0];
    const dir = (order[col] === 'desc' || order[col] === ':desc') ? 'desc' : 'asc';
    return [col, dir];
  }

  // --- Association Loading ---

  // Resolve a model name or class to a model class
  static _resolveModel(modelOrName) {
    if (typeof modelOrName === 'string') {
      const model = modelRegistry[modelOrName];
      if (!model) {
        throw new Error(`Model '${modelOrName}' not found in registry. Did you forget to call Application.registerModels()?`);
      }
      return model;
    }
    return modelOrName;
  }

  // Load associations for a set of records
  static async _loadAssociations(records, includes) {
    if (records.length === 0) return;

    for (const include of includes) {
      if (typeof include === 'string') {
        await this._loadAssociation(records, include);
      } else if (typeof include === 'object') {
        // Nested include: { posts: 'comments' }
        for (const assocName of Object.keys(include)) {
          await this._loadAssociation(records, assocName);
          // TODO: nested loading
        }
      }
    }
  }

  // Load a single association for a set of records
  static async _loadAssociation(records, assocName) {
    const associations = this.associations || {};
    const assoc = associations[assocName];

    if (!assoc) {
      console.warn(`Association '${assocName}' not defined on ${this.name}`);
      return;
    }

    const AssocModel = this._resolveModel(assoc.model);
    if (!AssocModel) {
      console.warn(`Could not resolve model for association '${assocName}'`);
      return;
    }

    if (assoc.type === 'has_many') {
      await this._loadHasMany(records, assocName, assoc, AssocModel);
    } else if (assoc.type === 'belongs_to') {
      await this._loadBelongsTo(records, assocName, assoc, AssocModel);
    } else if (assoc.type === 'has_one') {
      await this._loadHasOne(records, assocName, assoc, AssocModel);
    }
  }

  // Load has_many association
  static async _loadHasMany(records, assocName, assoc, AssocModel) {
    const pkValues = records.map(r => r.id).filter(v => v != null);

    // Determine foreign key (e.g., article_id for Article has_many comments)
    const foreignKey = assoc.foreignKey || `${singularize(this.name).toLowerCase()}_id`;

    if (pkValues.length === 0) {
      // No parent records, still set empty CollectionProxy
      for (const record of records) {
        const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey }, AssocModel);
        proxy.load([]);
        record[`_${assocName}`] = proxy;
      }
      return;
    }

    // Fetch all related records in one query using Supabase
    const { data: related, error } = await supabase
      .from(AssocModel.tableName)
      .select('*')
      .in(foreignKey, pkValues);

    if (error) throw error;

    // Group by foreign key
    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, []);
      }
      relatedByFk.get(fk).push(new AssocModel(r));
    }

    // Attach to parent records as CollectionProxy
    for (const record of records) {
      const related = relatedByFk.get(record.id) || [];
      const proxy = new CollectionProxy(record, { name: assocName, type: 'has_many', foreignKey }, AssocModel);
      proxy.load(related);
      record[`_${assocName}`] = proxy;
    }
  }

  // Load belongs_to association
  static async _loadBelongsTo(records, assocName, assoc, AssocModel) {
    const foreignKey = assoc.foreignKey || `${assocName}_id`;
    const fkValues = [...new Set(
      records.map(r => r[foreignKey] || r.attributes?.[foreignKey]).filter(v => v != null)
    )];

    if (fkValues.length === 0) {
      for (const record of records) {
        record[assocName] = null;
      }
      return;
    }

    // Fetch all related records
    const { data: related, error } = await supabase
      .from(AssocModel.tableName)
      .select('*')
      .in('id', fkValues);

    if (error) throw error;

    const relatedById = new Map(related.map(r => [r.id, new AssocModel(r)]));

    for (const record of records) {
      const fk = record[foreignKey] || record.attributes?.[foreignKey];
      record[assocName] = relatedById.get(fk) || null;
    }
  }

  // Load has_one association
  static async _loadHasOne(records, assocName, assoc, AssocModel) {
    const pkValues = records.map(r => r.id).filter(v => v != null);
    if (pkValues.length === 0) return;

    const foreignKey = assoc.foreignKey || `${singularize(this.name).toLowerCase()}_id`;

    const { data: related, error } = await supabase
      .from(AssocModel.tableName)
      .select('*')
      .in(foreignKey, pkValues);

    if (error) throw error;

    const relatedByFk = new Map();
    for (const r of related) {
      const fk = r[foreignKey];
      if (!relatedByFk.has(fk)) {
        relatedByFk.set(fk, new AssocModel(r));
      }
    }

    for (const record of records) {
      record[assocName] = relatedByFk.get(record.id) || null;
    }
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
