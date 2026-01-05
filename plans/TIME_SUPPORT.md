# Time Support Plan

## Status: Planning

This plan adds proper time/date handling to Ruby2JS and Juntos, replacing the temporary `String.prototype.strftime` hack with a proper `TimeWithZone` class that mirrors Rails' ActiveSupport behavior.

## Current State

### The Problem

1. **strftime on String.prototype** - `packages/ruby2js-rails/rails_base.js` defines `String.prototype.strftime` because database values come back as strings (especially SQLite)
2. **Not Rails-specific** - Despite being in the Rails package, strftime is a general Ruby feature
3. **Inconsistent types** - Different database adapters return different types:
   - SQLite: strings (`"2026-01-04 15:30:00"`)
   - PostgreSQL/MySQL: `Date` objects

### Current Implementation

```javascript
// rails_base.js - temporary hack
String.prototype.strftime = function(format) {
  const d = new Date(this);
  const pad = n => n.toString().padStart(2, '0');
  return format
    .replace(/%Y/g, d.getFullYear())
    .replace(/%m/g, pad(d.getMonth() + 1))
    .replace(/%d/g, pad(d.getDate()))
    .replace(/%H/g, pad(d.getHours()))
    .replace(/%M/g, pad(d.getMinutes()))
    .replace(/%S/g, pad(d.getSeconds()));
};
```

## Proposed Solution

### Architecture

```
Database (various formats)
    ↓
ActiveRecord Adapter (normalizes to TimeWithZone)
    ↓
TimeWithZone instance
    ↓
Ruby-like API (.year, .month, .strftime, etc.)
```

### Component 1: TimeWithZone Class

A JavaScript class that wraps `Date` and provides Ruby's Time API.

**Location:** `packages/ruby2js-rails/rails_base.js`

**API:**

```javascript
class TimeWithZone {
  constructor(value, zone = null) {
    // Accept: Date, string, number (timestamp), or another TimeWithZone
    if (value instanceof TimeWithZone) {
      this._date = new Date(value._date);
      this._zone = value._zone;
    } else {
      this._date = value instanceof Date ? value : new Date(value);
      this._zone = zone;
    }
  }

  // Getters (Ruby Time API)
  get year() { return this._date.getFullYear(); }
  get month() { return this._date.getMonth() + 1; }  // Ruby is 1-indexed
  get day() { return this._date.getDate(); }
  get mday() { return this._date.getDate(); }        // Alias
  get hour() { return this._date.getHours(); }
  get min() { return this._date.getMinutes(); }
  get sec() { return this._date.getSeconds(); }
  get wday() { return this._date.getDay(); }         // 0=Sunday
  get yday() { /* day of year calculation */ }

  // Predicates
  get sunday() { return this._date.getDay() === 0; }
  get monday() { return this._date.getDay() === 1; }
  get tuesday() { return this._date.getDay() === 2; }
  get wednesday() { return this._date.getDay() === 3; }
  get thursday() { return this._date.getDay() === 4; }
  get friday() { return this._date.getDay() === 5; }
  get saturday() { return this._date.getDay() === 6; }

  // Conversions
  to_i() { return Math.floor(this._date.getTime() / 1000); }
  to_f() { return this._date.getTime() / 1000; }
  to_s() { return this._date.toISOString(); }
  iso8601() { return this._date.toISOString(); }

  // Formatting
  strftime(format) { /* full implementation */ }

  // Interop
  toJSON() { return this._date.toISOString(); }
  valueOf() { return this._date.valueOf(); }
  toString() { return this._date.toString(); }

  // For use with native Date APIs
  get native() { return this._date; }
}
```

### Component 2: strftime Implementation

Support common format codes:

| Code | Meaning | Example |
|------|---------|---------|
| `%Y` | 4-digit year | 2026 |
| `%y` | 2-digit year | 26 |
| `%m` | Month (01-12) | 01 |
| `%-m` | Month (1-12) | 1 |
| `%B` | Full month name | January |
| `%b` | Abbrev month | Jan |
| `%d` | Day (01-31) | 04 |
| `%-d` | Day (1-31) | 4 |
| `%e` | Day with space padding | " 4" |
| `%H` | Hour 24h (00-23) | 14 |
| `%I` | Hour 12h (01-12) | 02 |
| `%M` | Minute (00-59) | 30 |
| `%S` | Second (00-59) | 45 |
| `%p` | AM/PM | PM |
| `%P` | am/pm | pm |
| `%A` | Full weekday | Saturday |
| `%a` | Abbrev weekday | Sat |
| `%Z` | Timezone name | EST |
| `%z` | Timezone offset | -0500 |
| `%%` | Literal % | % |

**Implementation:**

```javascript
strftime(format) {
  const d = this._date;
  const pad = (n, len = 2) => n.toString().padStart(len, '0');

  const months = ['January', 'February', 'March', 'April', 'May', 'June',
                  'July', 'August', 'September', 'October', 'November', 'December'];
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  return format
    .replace(/%%/g, '\0')  // Escape %%
    .replace(/%Y/g, d.getFullYear())
    .replace(/%y/g, pad(d.getFullYear() % 100))
    .replace(/%m/g, pad(d.getMonth() + 1))
    .replace(/%-m/g, d.getMonth() + 1)
    .replace(/%B/g, months[d.getMonth()])
    .replace(/%b/g, months[d.getMonth()].slice(0, 3))
    .replace(/%d/g, pad(d.getDate()))
    .replace(/%-d/g, d.getDate())
    .replace(/%e/g, d.getDate().toString().padStart(2, ' '))
    .replace(/%H/g, pad(d.getHours()))
    .replace(/%I/g, pad(d.getHours() % 12 || 12))
    .replace(/%M/g, pad(d.getMinutes()))
    .replace(/%S/g, pad(d.getSeconds()))
    .replace(/%p/g, d.getHours() < 12 ? 'AM' : 'PM')
    .replace(/%P/g, d.getHours() < 12 ? 'am' : 'pm')
    .replace(/%A/g, days[d.getDay()])
    .replace(/%a/g, days[d.getDay()].slice(0, 3))
    .replace(/%Z/g, d.toLocaleTimeString('en', { timeZoneName: 'short' }).split(' ').pop())
    .replace(/%z/g, () => {
      const offset = -d.getTimezoneOffset();
      const sign = offset >= 0 ? '+' : '-';
      return sign + pad(Math.floor(Math.abs(offset) / 60)) + pad(Math.abs(offset) % 60);
    })
    .replace(/\0/g, '%');  // Restore %%
}
```

### Component 3: Adapter Normalization

Each ActiveRecord adapter normalizes datetime columns on read.

**Schema tracking:**

```javascript
// Track column types from CREATE TABLE
class Adapter {
  static columnTypes = new Map();  // tableName -> { columnName: type }

  static registerSchema(tableName, columns) {
    this.columnTypes.set(tableName, columns);
  }
}
```

**Normalization on read:**

```javascript
// In each adapter's query/find methods
function normalizeRow(tableName, row) {
  const columns = Adapter.columnTypes.get(tableName);
  if (!columns) return row;

  for (const [name, type] of Object.entries(columns)) {
    if ((type === 'datetime' || type === 'timestamp') && row[name] != null) {
      row[name] = new TimeWithZone(row[name]);
    }
  }
  return row;
}
```

**Adapters to update:**

| Adapter | Location | Input Format |
|---------|----------|--------------|
| sql.js (SQLite in browser) | `packages/ruby2js-rails/adapters/sqljs.mjs` | String |
| better-sqlite3 | `packages/ruby2js-rails/adapters/better-sqlite3.mjs` | String |
| PostgreSQL (pg) | `packages/ruby2js-rails/adapters/pg.mjs` | Date object |
| MySQL (mysql2) | `packages/ruby2js-rails/adapters/mysql2.mjs` | Date object |

### Component 4: Compile-time Optimizations (Optional)

For known strftime patterns, the Ruby2JS functions filter could emit optimized code.

**In `lib/ruby2js/filter/functions.rb`:**

```ruby
STRFTIME_OPTIMIZATIONS = {
  '%Y-%m-%d' => ->(target) {
    s(:send, s(:send, process(target), :toISOString), :slice, s(:int, 0), s(:int, 10))
  },
  '%Y-%m-%dT%H:%M:%SZ' => ->(target) {
    s(:send, process(target), :toISOString)
  }
}

def on_send(node)
  target, method, *args = node.children

  if method == :strftime && args.length == 1 && args.first.type == :str
    format = args.first.children.first
    if optimization = STRFTIME_OPTIMIZATIONS[format]
      return optimization.call(target)
    end
  end

  super
end
```

**Or map to Intl.DateTimeFormat for locale-aware patterns:**

| strftime | Intl.DateTimeFormat |
|----------|---------------------|
| `%B %d, %Y` | `{ dateStyle: 'long' }` |
| `%b %d, %Y` | `{ dateStyle: 'medium' }` |
| `%m/%d/%y` | `{ dateStyle: 'short' }` |

```ruby
STRFTIME_TO_INTL = {
  '%B %d, %Y' => { dateStyle: 'long' },
  '%B %-d, %Y' => { dateStyle: 'long' },
  # etc.
}
```

### Component 5: Time.now Transpilation

Add `Time.now` → `new TimeWithZone()` or `new Date()` to the functions filter.

**In `lib/ruby2js/filter/functions.rb`:**

```ruby
def on_send(node)
  target, method, *args = node.children

  # Time.now => new Date()
  if target == s(:const, nil, :Time) && method == :now && args.empty?
    return s(:send, s(:const, nil, :Date), :new)
  end

  # Date.today => new Date() (time portion ignored by usage)
  if target == s(:const, nil, :Date) && method == :today && args.empty?
    return s(:send, s(:const, nil, :Date), :new)
  end

  super
end
```

**Note:** If TimeWithZone is available (Juntos context), could emit `new TimeWithZone()` instead via a configuration option.

## Implementation Stages

### Stage 1: TimeWithZone Class

1. Create `TimeWithZone` class in `rails_base.js`
2. Implement all getters (year, month, day, etc.)
3. Implement full strftime with common format codes
4. Add comprehensive tests
5. Export from rails_base.js

**Acceptance criteria:**
- `new TimeWithZone('2026-01-04 15:30:00').year` → `2026`
- `new TimeWithZone('2026-01-04 15:30:00').strftime('%B %d, %Y')` → `"January 04, 2026"`
- Works with Date objects, strings, and timestamps

### Stage 2: Adapter Integration

1. Update sql.js adapter to normalize datetime columns
2. Update better-sqlite3 adapter
3. Update PostgreSQL adapter (may already return Date, just wrap)
4. Update MySQL adapter (may already return Date, just wrap)
5. Track column types from schema/migrations

**Acceptance criteria:**
- `Article.find(1).created_at` returns `TimeWithZone` instance
- `article.created_at.strftime('%Y-%m-%d')` works without prototype hacks

### Stage 3: Remove String.prototype.strftime

1. Remove `String.prototype.strftime` from rails_base.js
2. Update any code that relies on string dates
3. Update documentation

**Acceptance criteria:**
- No prototype pollution
- All existing demos still work

### Stage 4: Compile-time Optimizations (Optional)

1. Add `Time.now` → `new Date()` to functions filter
2. Add strftime pattern optimizations for common patterns
3. Consider Intl.DateTimeFormat mappings for locale-aware patterns

**Acceptance criteria:**
- `Time.now` transpiles to `new Date()`
- `date.strftime('%Y-%m-%d')` transpiles to optimized `.toISOString().slice(0, 10)`

### Stage 5: Polyfill Filter Integration (Optional)

For non-Juntos users who want strftime on Date objects, add to the polyfill filter.

1. Add `date_strftime` polyfill to `lib/ruby2js/filter/polyfill.rb`
2. Trigger on `.strftime()` calls
3. Emit minimal strftime implementation

**Acceptance criteria:**
- `date.strftime('%Y-%m-%d')` works with polyfill filter enabled
- Polyfill only added when strftime is used

## Testing Strategy

### Unit Tests

```javascript
describe('TimeWithZone', () => {
  describe('constructor', () => {
    it('accepts ISO string', () => {
      const t = new TimeWithZone('2026-01-04T15:30:00Z');
      expect(t.year).toBe(2026);
    });

    it('accepts Date object', () => {
      const t = new TimeWithZone(new Date(2026, 0, 4, 15, 30));
      expect(t.month).toBe(1);
    });

    it('accepts timestamp', () => {
      const t = new TimeWithZone(1767535800000);
      expect(t.day).toBe(4);
    });
  });

  describe('strftime', () => {
    const t = new TimeWithZone('2026-01-04T15:30:45Z');

    it('formats %Y-%m-%d', () => {
      expect(t.strftime('%Y-%m-%d')).toBe('2026-01-04');
    });

    it('formats %B %d, %Y', () => {
      expect(t.strftime('%B %d, %Y')).toBe('January 04, 2026');
    });

    it('handles %-d (no padding)', () => {
      expect(t.strftime('%-d')).toBe('4');
    });

    it('escapes %%', () => {
      expect(t.strftime('100%%')).toBe('100%');
    });
  });

  describe('predicates', () => {
    it('returns correct day of week', () => {
      const sunday = new TimeWithZone('2026-01-04');  // Sunday
      expect(sunday.sunday).toBe(true);
      expect(sunday.monday).toBe(false);
    });
  });
});
```

### Integration Tests

```javascript
describe('ActiveRecord datetime handling', () => {
  it('returns TimeWithZone for datetime columns', async () => {
    const article = await Article.create({ title: 'Test' });
    expect(article.created_at).toBeInstanceOf(TimeWithZone);
  });

  it('allows strftime on model attributes', async () => {
    const article = await Article.create({ title: 'Test' });
    expect(article.created_at.strftime('%Y-%m-%d')).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
```

## Migration Notes

### For Existing Juntos Apps

If code relies on `String.prototype.strftime`:

```javascript
// Before (worked with string dates)
article.created_at.strftime('%Y-%m-%d')

// After (still works - adapters return TimeWithZone)
article.created_at.strftime('%Y-%m-%d')
```

No code changes needed if using ActiveRecord properly.

### For Direct String Usage

If manually working with date strings:

```javascript
// Before
const dateStr = '2026-01-04';
dateStr.strftime('%B %d, %Y');  // Won't work after migration

// After
const dateStr = '2026-01-04';
new TimeWithZone(dateStr).strftime('%B %d, %Y');  // Works
```

## Future Considerations

### Temporal API

When the Temporal API is widely available (ES2025+), consider:

```javascript
class TimeWithZone {
  constructor(value, zone = null) {
    if (typeof Temporal !== 'undefined') {
      // Use Temporal for better semantics
      this._instant = Temporal.Instant.from(value);
      this._zone = zone || Temporal.Now.timeZoneId();
    } else {
      // Fall back to Date
      this._date = new Date(value);
    }
  }
}
```

### Timezone Support

Full timezone support would require:
- Storing the zone name
- Using Intl.DateTimeFormat for zone-aware formatting
- Handling DST transitions

This is deferred but the architecture supports adding it later.

## References

- [Ruby Time class](https://ruby-doc.org/core/Time.html)
- [Rails TimeWithZone](https://api.rubyonrails.org/classes/ActiveSupport/TimeWithZone.html)
- [strftime format codes](https://ruby-doc.org/core/Time.html#method-i-strftime)
- [Intl.DateTimeFormat](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/DateTimeFormat)
- [Temporal API](https://tc39.es/proposal-temporal/docs/)
