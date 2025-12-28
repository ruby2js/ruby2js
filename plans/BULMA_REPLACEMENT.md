# Bulma CSS Framework Replacement Plan

## Problem Statement

The docs site uses Bulma CSS framework (v0.9.1), which generates 297 Sass deprecation warnings during builds:

- `@import` rules deprecated (should use `@use`)
- Color functions (`darken()`, `red()`, `green()`, `blue()`, `lightness()`) deprecated
- Global built-in functions deprecated

These warnings will become errors in Dart Sass 3.0.0, expected no sooner than 2 years from Dart Sass 1.80.0 (released late 2024).

### Upstream Status

- [Issue #3948](https://github.com/jgthms/bulma/issues/3948) - Closed Jan 2024, no fix
- [Issue #3942](https://github.com/jgthms/bulma/issues/3942) - Closed, affects Bulma 1.0.2+
- [Issue #3980](https://github.com/jgthms/bulma/issues/3980) - Open, tracking deprecations

Bulma has not migrated to the Sass module system. Even upgrading to Bulma 1.0.4 does not resolve the warnings.

---

## Options

### Option 1: Wait and Monitor (Status Quo)

**Effort:** None
**Risk:** Unknown - depends on Bulma maintainers and Dart Sass timeline

Do nothing. The warnings don't prevent deployment. Continue monitoring:
- Bulma releases for Sass module system migration
- Dart Sass 3.0 release timeline

**Pros:**
- Zero effort now
- Bulma may fix the issue upstream
- Dart Sass 3.0 timeline may slip

**Cons:**
- 297 warnings clutter deploy logs
- Technical debt accumulates
- May require urgent action if Dart Sass 3.0 releases unexpectedly
- Bulma issues closed without fixes suggest low maintainer priority

---

### Option 2: Replace with Minimal Custom CSS

**Effort:** 2-3 hours
**Risk:** Low - site styling is simple

The site uses only a tiny subset of Bulma:

#### Current Bulma Usage (22 references total)

**Buttons:**
- `button`, `is-primary`, `is-info`, `is-warning`, `is-large`

**Typography:**
- `title`, `is-size-4`, `is-size-6`, `is-1`

**Layout:**
- `is-centered`, `has-text-centered`, `has-text-brown`, `has-mixed-case`
- `buttons` (button group)

**Variables used in index.scss:**
- Color variables ($grey, $primary, $info, $warning, etc.)
- Typography variables ($family-sans-serif, $body-size, etc.)
- Component variables ($navbar-*, $footer-*, $card-shadow, etc.)

#### Implementation Steps

1. **Create replacement CSS file** (`frontend/styles/base.scss`)
   - Define CSS custom properties for colors
   - Add button styles (~30 lines)
   - Add typography styles (~20 lines)
   - Add layout helpers (~15 lines)

2. **Update index.scss**
   - Remove `@import "~bulma/bulma";`
   - Import new base.scss
   - Convert Sass variables to CSS custom properties where used

3. **Update HTML/ERB files**
   - Replace Bulma classes with new class names, OR
   - Keep same class names in custom CSS for minimal changes

4. **Remove Bulma dependency**
   - Remove from package.json
   - Run `yarn install`

5. **Test locally and deploy**

#### Files to Modify

- `docs/frontend/styles/index.scss` - Remove Bulma import, add base styles
- `docs/frontend/styles/base.scss` - New file with replacement styles
- `docs/package.json` - Remove bulma dependency
- Possibly: `docs/src/demo/index.erb`, layout files (if class names change)

---

### Option 3: Switch to Lightweight Modern Framework

**Effort:** 1-2 hours
**Risk:** Low-Medium - need to verify compatibility

Replace Bulma with a minimal, modern CSS framework:

**Candidates:**

| Framework                               | Size  | Sass?    | Notes                              |
| --------------------------------------- | ----- | -------- | ---------------------------------- |
| [Pico CSS](https://picocss.com/)        | ~10KB | No (CSS) | Classless, semantic HTML           |
| [Simple.css](https://simplecss.org/)    | ~4KB  | No (CSS) | Classless, minimal                 |
| [Open Props](https://open-props.style/) | ~2KB  | No (CSS) | Just custom properties             |
| [Milligram](https://milligram.io/)      | ~2KB  | Yes      | Minimal, may have same Sass issues |

**Implementation Steps:**

1. Choose framework based on styling needs
2. Install via npm/yarn
3. Update index.scss to import new framework
4. Update HTML classes to match new framework conventions
5. Remove Bulma dependency
6. Test and deploy

**Pros:**
- Modern, maintained frameworks
- Smaller bundle size
- CSS-only options avoid Sass issues entirely

**Cons:**
- Still a dependency (though smaller/simpler)
- May require more HTML changes than Option 2
- Learning curve for new class conventions

---

## Recommendation

**Short term:** Option 1 (Status Quo) - warnings don't block deployment

**Medium term:** Option 2 (Custom CSS) - eliminates dependency entirely, site is simple enough that a custom solution is maintainable and won't grow into its own maintenance burden

Option 3 is viable but trades one dependency for another. Given the light CSS needs of the docs site, custom CSS is more appropriate than adopting another framework.

---

## Timeline Triggers

Consider acting on this plan if:

1. **Dart Sass 3.0 release announced** - Will need to act before upgrading Sass
2. **Bulma announces end-of-life** - Would need replacement regardless
3. **Warnings increase significantly** - May indicate deeper compatibility issues
4. **Major docs site redesign** - Good opportunity to replace CSS foundation

---

## References

- [Sass @import deprecation announcement](https://sass-lang.com/blog/import-is-deprecated/)
- [Sass breaking changes documentation](https://sass-lang.com/documentation/breaking-changes/import/)
- [Bulma GitHub issues](https://github.com/jgthms/bulma/issues?q=sass+deprecation)
