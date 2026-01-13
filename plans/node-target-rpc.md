# Plan: Node Target Support for Ruby2JS-Rails

## Goal

Enable the same source code to work on both browser and Node targets without changes. The workflow builder demo should work identically whether running purely in-browser (Dexie/IndexedDB) or against a Node.js server (SQLite/PostgreSQL).

**Future direction**: Align with React Server Components pattern (`"use server"` / `"use client"` directives).

## Architecture: Unified RPC Transport

```
┌─────────────────────────────────────────────────────┐
│                  RPC Transport Layer                │
│  - Single endpoint (/__rpc)                         │
│  - Header-based action routing (X-RPC-Action)       │
│  - CSRF protection (X-Authenticity-Token)           │
│  - JSON serialization                               │
└─────────────────────────────────────────────────────┘
        ▲              ▲              ▲
        │              │              │
   ┌────┴────┐   ┌─────┴─────┐   ┌───┴────┐
   │  Model  │   │   App     │   │ "use   │
   │ Adapter │   │   RPCs    │   │server" │
   │ (now)   │   │  (now)    │   │(future)│
   └─────────┘   └───────────┘   └────────┘
```

### Key Design Decisions

- **Single endpoint** (`/__rpc`) - not REST routes per model
- **Header-based routing** - matches RSC pattern (Next.js uses similar approach)
- **CSRF tokens** - Rails-style authenticity protection
- **Transport is public API** - apps can use it directly for custom RPCs
- **Progressive path to RSC** - foundation laid for `"use server"` later

## How It Works

### Client Request
```
POST /__rpc
Headers:
  X-RPC-Action: Node.find
  X-Authenticity-Token: abc123...
  Content-Type: application/json
Body: { "args": [1] }
```

### Server Response
```json
{ "result": { "id": 1, "label": "Start", "position_x": 100, ... } }
```

### Client Code (unchanged)
```ruby
Node.find(1)
# Browser target → direct Dexie call
# Node target → RPC call to server
```

## Same Source, Two Modes

| | Browser Target | Node Target |
|---|---------------|-------------|
| **Models run** | In browser | In browser (via RPC to server) |
| **Data stored** | IndexedDB (Dexie) | SQLite/Postgres |
| **Transport** | Direct adapter calls | RPC over HTTP |
| **Same .rbx source** | ✓ | ✓ |

## Implementation Plan

### Phase 1: RPC Transport Layer

**Client** (`packages/ruby2js-rails/rpc/client.mjs`):
```javascript
export function createRPCClient(options = {}) {
  const endpoint = options.endpoint || '/__rpc';
  const getToken = options.getToken ||
    () => document.querySelector('meta[name="csrf-token"]')?.content;

  return async function rpc(action, args = []) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-RPC-Action': action,
        'X-Authenticity-Token': getToken()
      },
      body: JSON.stringify({ args })
    });

    if (!response.ok) throw new RPCError(response);
    const { result, error } = await response.json();
    if (error) throw new RPCError(error);
    return result;
  };
}
```

**Server** (`packages/ruby2js-rails/rpc/server.mjs`):
```javascript
export function createRPCHandler(registry, options = {}) {
  return async function handleRPC(request, session) {
    const action = request.headers['x-rpc-action'];
    if (!action) return null; // Not an RPC request

    // CSRF validation
    const token = request.headers['x-authenticity-token'];
    if (!validToken(token, session)) {
      return Response.json({ error: 'Invalid authenticity token' }, { status: 422 });
    }

    // Dispatch
    const handler = registry.get(action);
    if (!handler) {
      return Response.json({ error: `Unknown action: ${action}` }, { status: 404 });
    }

    const { args } = await request.json();
    const result = await handler(...args);
    return Response.json({ result });
  };
}
```

### Phase 2: Model RPC Adapter

**File**: `packages/ruby2js-rails/adapters/active_record_rpc.mjs`

Same interface as `active_record_dexie.mjs`, but methods call RPC:

```javascript
import { rpc } from '../rpc/client.mjs';

export class ActiveRecord extends ActiveRecordBase {
  static async find(id) {
    const data = await rpc(`${this.name}.find`, [id]);
    return new this(data);
  }

  static async where(conditions) {
    const rows = await rpc(`${this.name}.where`, [conditions]);
    return rows.map(row => new this(row));
  }

  static async create(attributes) {
    const data = await rpc(`${this.name}.create`, [attributes]);
    return new this(data);
  }

  async save() {
    const data = await rpc(`${this.constructor.name}.save`, [this.id, this.attributes]);
    Object.assign(this.attributes, data);
    return true;
  }

  async destroy() {
    await rpc(`${this.constructor.name}.destroy`, [this.id]);
    return true;
  }
}
```

### Phase 3: Server Integration

**Modify**: `packages/ruby2js-rails/targets/node/rails.js`

Add RPC handling before regular route dispatch:

```javascript
import { createRPCHandler } from '../rpc/server.mjs';
import { modelRegistry } from './active_record.mjs';

// Build registry from models
const rpcRegistry = new Map();
for (const [name, Model] of Object.entries(modelRegistry)) {
  rpcRegistry.set(`${name}.find`, (id) => Model.find(id));
  rpcRegistry.set(`${name}.where`, (conditions) => Model.where(conditions));
  rpcRegistry.set(`${name}.create`, (attrs) => Model.create(attrs));
  rpcRegistry.set(`${name}.save`, (id, attrs) => /* ... */);
  rpcRegistry.set(`${name}.destroy`, (id) => /* ... */);
}

const handleRPC = createRPCHandler(rpcRegistry);

// In request handler:
const rpcResponse = await handleRPC(request, session);
if (rpcResponse) return rpcResponse;
// ... continue with normal routing
```

### Phase 4: Build Configuration

**Modify**: `lib/ruby2js/rails/builder.rb`

```ruby
# For Node target, client gets RPC adapter
if @target == 'node'
  copy_file('adapters/active_record_rpc.mjs', 'lib/active_record.mjs')
  # Server keeps SQL adapter
  copy_file("adapters/active_record_#{@database}.mjs", 'lib/active_record_server.mjs')
end
```

**Modify**: `packages/ruby2js-rails/vite.mjs`

- Embed CSRF token in HTML template
- Configure RPC endpoint

### Phase 5: Testing

1. Start workflow builder with `JUNTOS_TARGET=browser` - works as now
2. Start workflow builder with `JUNTOS_TARGET=node` - same UI, data in SQLite
3. Verify CSRF protection works
4. Test error handling (network failures, validation errors)

## File Changes Summary

| File | Change |
|------|--------|
| `packages/ruby2js-rails/rpc/client.mjs` | NEW - RPC client with token handling |
| `packages/ruby2js-rails/rpc/server.mjs` | NEW - RPC server handler |
| `packages/ruby2js-rails/adapters/active_record_rpc.mjs` | NEW - Model adapter using RPC |
| `packages/ruby2js-rails/targets/node/rails.js` | Add RPC dispatch before routing |
| `lib/ruby2js/rails/builder.rb` | Select RPC adapter for Node target |
| `packages/ruby2js-rails/vite.mjs` | CSRF token embedding |

## Future: `"use server"` Directive

Once RPC transport is working, add support for React Server Components pattern:

```ruby
"use server"
def save_positions(workflow_id, positions)
  positions.each do |pos|
    Node.find(pos.id).update(position_x: pos.x, position_y: pos.y)
  end
end
```

**Implementation**:
1. Parse `"use server"` directive in transpiler
2. Register function in RPC registry automatically
3. Generate client stub that calls `rpc('save_positions', [workflow_id, positions])`
4. Same transport, just syntactic sugar

## Why This Approach?

1. **Novel**: No React framework currently offers same-source, build-time backend selection
2. **Aligned with React direction**: Header-based RPC matches RSC Server Actions pattern
3. **Rails-familiar**: CSRF tokens, ActiveRecord API
4. **Progressive**: Works today, path to `"use server"` later
5. **Reusable transport**: Apps can use RPC directly for custom calls
