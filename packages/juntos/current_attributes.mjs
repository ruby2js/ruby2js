// ActiveSupport::CurrentAttributes implementation for Juntos
// Provides thread-local (request-scoped) attributes via static class properties.
// In Node.js, "thread-local" means per-request since each request is handled
// sequentially within an async context.

export class CurrentAttributes {
  static _attributes = {};
  static _pending = [];

  static attribute(...names) {
    for (const name of names) {
      if (!(name in this)) {
        Object.defineProperty(this, name, {
          get() { return this._attributes[name]; },
          set(v) {
            // Detect async values (Promises from setter chains like find_by)
            if (v && typeof v === 'object' && typeof v.then === 'function') {
              this._pending.push(v.then(resolved => {
                this._attributes[name] = resolved;
              }));
            }
            this._attributes[name] = v;
          },
          configurable: true
        });
      }
    }
  }

  static reset() { this._attributes = {}; this._pending = []; }

  // Await all async operations triggered by setter chains
  static async settle() {
    if (this._pending.length > 0) {
      await Promise.all(this._pending);
      this._pending = [];
    }
  }

  static $with(attrs, fn) {
    const prev = { ...this._attributes };
    Object.assign(this._attributes, attrs);
    try { return fn?.(); } finally { this._attributes = prev; }
  }

  // Promote instance methods/setters to static on subclasses
  static _promoteInstanceMethods() {
    const proto = this.prototype;
    const parentProto = Object.getPrototypeOf(proto);
    for (const name of Object.getOwnPropertyNames(proto)) {
      if (name === 'constructor') continue;
      const desc = Object.getOwnPropertyDescriptor(proto, name);
      if (desc?.set) {
        // Custom setter (e.g., session=) — integrate with attribute() setter
        const customSetter = desc.set;
        const existingDesc = Object.getOwnPropertyDescriptor(this, name);
        if (existingDesc?.set) {
          const origGetter = existingDesc.get;
          const origSetter = existingDesc.set;
          // Define stub on parent prototype so super.name(v) doesn't crash
          if (!parentProto[name]) parentProto[name] = function(v) {};
          Object.defineProperty(this, name, {
            get: origGetter,
            set(v) {
              origSetter.call(this, v);  // Store in _attributes first
              customSetter.call(this, v); // Then run custom chain
            },
            configurable: true
          });
        }
      } else if (desc && typeof desc.value === 'function' && !(name in this)) {
        this[name] = desc.value.bind(this);
      }
    }
  }
}
