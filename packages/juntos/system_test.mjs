// Capybara-style system test helpers for Juntos
//
// Provides visit(), fillIn(), clickButton(), findField(), findButton(),
// and cleanup() for writing Rails-style system tests that run in jsdom
// without a browser or network. Uses the fetch interceptor to route
// requests through RouterBase.match().
//
// Usage:
//   import { visit, fillIn, clickButton, findField, cleanup } from 'juntos/system_test.mjs';
//   import { registerController } from 'juntos/system_test.mjs';
//
//   registerController('chat', ChatController);
//
//   test('clears input after sending', async () => {
//     await visit(messages_path());
//     await fillIn('Type a message...', 'Hello!');
//     await clickButton('Send');
//     expect(findField('Type a message...').value).toBe('');
//   });

// Stub jsdom-missing DOM methods that Stimulus controllers commonly use
if (typeof window !== 'undefined' && typeof window.Element !== 'undefined') {
  if (!window.Element.prototype.scrollIntoView) {
    window.Element.prototype.scrollIntoView = function() {};
  }
}

// Stub Turbo so Stimulus controllers that call Turbo.visit() or
// Turbo.renderStreamMessage() work in jsdom without the full Turbo library.
// _pendingVisit tracks in-flight Turbo.visit() calls so drag_to can await them.
let _pendingVisit = null;
if (typeof globalThis !== 'undefined' && !globalThis.Turbo) {
  globalThis.Turbo = {
    visit(url) {
      // Re-render the page using the system test visit() helper.
      // Imported lazily to avoid circular dependency at module load time.
      _pendingVisit = import('juntos/system_test.mjs').then(m => m.visit(url));
      return _pendingVisit;
    },
    renderStreamMessage(html) {
      // Process turbo stream actions (replace, update, append, etc.)
      const template = document.createElement('template');
      template.innerHTML = html;
      for (const stream of template.content.querySelectorAll('turbo-stream')) {
        const action = stream.getAttribute('action');
        const target = document.getElementById(stream.getAttribute('target'));
        const content = stream.querySelector('template')?.content;
        if (!target) continue;
        switch (action) {
          case 'replace': target.replaceWith(content.cloneNode(true)); break;
          case 'update': target.innerHTML = ''; target.appendChild(content.cloneNode(true)); break;
          case 'append': target.appendChild(content.cloneNode(true)); break;
          case 'prepend': target.prepend(content.cloneNode(true)); break;
          case 'remove': target.remove(); break;
        }
      }
    }
  };
}

// Controller registry — populated by test setup
let _controllers = {};
let _stimulusApp = null;

/**
 * Register a Stimulus controller for auto-connection during visit().
 */
export function registerController(name, klass) {
  _controllers[name] = klass;
}

/**
 * Navigate to a page — fetch HTML, render into document, connect Stimulus.
 * @param {string|object} path - URL path or path helper result
 */
export async function visit(path) {
  const url = path.toString();

  // Update window.location so controllers that read window.location.href
  // (e.g., drop_controller calling Turbo.visit(window.location.href)) see the current page.
  try {
    const fullUrl = new URL(url, window.location.origin).href;
    window.history.pushState({}, '', fullUrl);
  } catch (e) { /* ignore if pushState unavailable */ }

  const response = await fetch(url, {
    method: 'GET',
    headers: { accept: 'text/html' }
  });

  // Handle redirects
  if (response.status >= 300 && response.status < 400) {
    const location = response.headers.get('Location');
    if (location) return visit(location);
  }

  const html = await response.text();
  document.body.innerHTML = html;

  // Auto-discover data-controller attributes and start Stimulus
  const names = new Set();
  document.querySelectorAll('[data-controller]').forEach(el =>
    el.dataset.controller.split(' ').forEach(n => names.add(n.trim()))
  );

  if (names.size > 0) {
    const { Application } = await import('@hotwired/stimulus');
    if (_stimulusApp) _stimulusApp.stop();
    _stimulusApp = Application.start();
    for (const name of names) {
      if (_controllers[name]) {
        _stimulusApp.register(name, _controllers[name]);
      }
    }
    // Let Stimulus connect controllers
    await new Promise(r => setTimeout(r, 0));
  }
}

/**
 * Fill a form field by placeholder text, label text, or name attribute.
 * @param {string} locator - Placeholder, label text, or name
 * @param {string} value - Value to fill in
 */
export async function fillIn(locator, value) {
  const field = findField(locator);
  if (!field) {
    throw new Error(`fillIn: could not find field "${locator}"`);
  }

  // Set value and dispatch input event for reactivity
  field.value = value;
  field.dispatchEvent(new Event('input', { bubbles: true }));
  field.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Click a button and submit its form via fetch.
 * Handles Turbo Stream responses (DOM updates) and redirects.
 * @param {string} text - Button text content or value
 */
export async function clickButton(text) {
  const button = findButton(text);
  if (!button) {
    throw new Error(`clickButton: could not find button "${text}"`);
  }

  // Support external submit buttons with form="form-id" attribute
  const formAttr = button.getAttribute('form');
  const form = formAttr ? document.getElementById(formAttr) : button.closest('form');
  if (!form) {
    // Just click the button if it's not in a form
    button.click();
    await new Promise(r => setTimeout(r, 0));
    return;
  }

  const method = (form.getAttribute('method') || 'POST').toUpperCase();
  const action = form.getAttribute('action') || window.location.pathname;

  // Build form data from all inputs
  const formData = new FormData(form);

  const response = await fetch(action, {
    method,
    body: new URLSearchParams(formData).toString(),
    headers: { accept: 'text/vnd.turbo-stream.html, text/html' }
  });

  if (response.status >= 300 && response.status < 400) {
    const location = response.headers.get('Location');
    if (location) await visit(location);
  } else {
    const html = await response.text();
    const contentType = response.headers.get('Content-Type') || '';

    if (contentType.includes('turbo-stream')) {
      // Fire turbo:submit-end before processing (matches Turbo's order)
      form.dispatchEvent(new Event('turbo:submit-end', { bubbles: true }));
      processTurboStream(html);
    } else {
      document.body.innerHTML = html;
    }
  }

  // Let Stimulus settle
  await new Promise(r => setTimeout(r, 0));
}

/**
 * Find a form field by placeholder text, label text, or name attribute.
 * @param {string} locator - Placeholder, label text, or name
 * @returns {HTMLElement|null}
 */
export function findField(locator) {
  // Try placeholder
  let field = document.querySelector(
    `input[placeholder="${locator}"], textarea[placeholder="${locator}"]`
  );
  if (field) return field;

  // Try label text
  const labels = document.querySelectorAll('label');
  for (const label of labels) {
    if (label.textContent.trim() === locator) {
      const forId = label.getAttribute('for');
      if (forId) {
        field = document.getElementById(forId);
        if (field) return field;
      }
      // Label wrapping the input
      field = label.querySelector('input, textarea, select');
      if (field) return field;
    }
  }

  // Try name attribute
  field = document.querySelector(`[name="${locator}"]`);
  if (field) return field;

  return null;
}

/**
 * Find a button by its text content or value.
 * @param {string} text - Button text or value
 * @returns {HTMLElement|null}
 */
export function findButton(text) {
  // Try button elements
  const buttons = document.querySelectorAll('button');
  for (const button of buttons) {
    if (button.textContent.trim() === text) return button;
  }

  // Try input[type=submit]
  const submits = document.querySelectorAll('input[type="submit"]');
  for (const submit of submits) {
    if (submit.value === text) return submit;
  }

  return null;
}

/**
 * Click a link or button by its text content — equivalent to Capybara's click_on.
 * Tries links first, then buttons.
 * @param {string} text - Link or button text
 */
export async function clickOn(text) {
  // Try links first
  const links = document.querySelectorAll('a');
  for (const link of links) {
    if (link.textContent.trim() === text) {
      const href = link.getAttribute('href');
      if (href) return visit(href);
    }
  }

  // Fall back to button behavior
  return clickButton(text);
}

/**
 * Check a checkbox by its label text — equivalent to Capybara's check.
 * @param {string} locator - Label text, name, or id of the checkbox
 */
export async function check(locator) {
  const field = findField(locator);
  if (!field) {
    throw new Error(`check: could not find checkbox "${locator}"`);
  }
  if (!field.checked) {
    field.checked = true;
    field.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

/**
 * Uncheck a checkbox by its label text — equivalent to Capybara's uncheck.
 * @param {string} locator - Label text, name, or id of the checkbox
 */
export async function uncheck(locator) {
  const field = findField(locator);
  if (!field) {
    throw new Error(`uncheck: could not find checkbox "${locator}"`);
  }
  if (field.checked) {
    field.checked = false;
    field.dispatchEvent(new Event('change', { bubbles: true }));
  }
}

/**
 * Select a radio button by its label text — equivalent to Capybara's choose.
 * @param {string} locator - Label text of the radio button
 */
export async function choose(locator) {
  const field = findField(locator);
  if (!field) {
    throw new Error(`choose: could not find radio button "${locator}"`);
  }
  field.checked = true;
  field.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Select an option from a <select> dropdown by its visible text.
 * @param {string} value - The visible text of the option to select
 * @param {object} options - Options hash with `from` key (field locator)
 */
export async function select(value, { from }) {
  const field = findField(from);
  if (!field) {
    throw new Error(`select: could not find select field "${from}"`);
  }

  const option = Array.from(field.options).find(o => o.text.trim() === value);
  if (!option) {
    throw new Error(`select: could not find option "${value}" in "${from}"`);
  }

  field.value = option.value;
  field.dispatchEvent(new Event('change', { bubbles: true }));
}

/**
 * Wrap a DOM element with Capybara-like methods (.find(), .hover(), .text, .drag_to()).
 * @param {HTMLElement} el - The DOM element to wrap
 * @returns {object} Element wrapper
 */
function wrapElement(el) {
  return {
    element: el,
    get text() { return el.textContent; },

    find(selector, options = {}) {
      const match = options.match === 'first'
        ? el.querySelector(selector)
        : el.querySelector(selector);
      if (!match) {
        throw new Error(`find: could not find "${selector}" within element`);
      }
      return wrapElement(match);
    },

    async hover() {
      el.dispatchEvent(new Event('mouseenter', { bubbles: true }));
      el.dispatchEvent(new Event('mouseover', { bubbles: true }));
      await new Promise(r => setTimeout(r, 0));
    },

    async drag_to(targetWrapper) {
      const target = targetWrapper.element || targetWrapper;

      // jsdom lacks DragEvent/DataTransfer; simulate with a shared data store
      const data = {};
      const dataTransfer = {
        data,
        setData(type, val) { data[type] = val; },
        getData(type) { return data[type] || ''; },
        effectAllowed: 'move',
        dropEffect: 'move'
      };

      const mkEvent = (type) => {
        const e = new Event(type, { bubbles: true, cancelable: true });
        e.dataTransfer = dataTransfer;
        return e;
      };

      el.dispatchEvent(mkEvent('dragstart'));
      target.dispatchEvent(mkEvent('dragover'));
      target.dispatchEvent(mkEvent('drop'));
      el.dispatchEvent(mkEvent('dragend'));

      // Wait for any fetch + Turbo.visit chain triggered by the drop handler
      await new Promise(r => setTimeout(r, 0));
      if (_pendingVisit) {
        await _pendingVisit;
        _pendingVisit = null;
      }
    }
  };
}

/**
 * Find an element by CSS selector — equivalent to Capybara's find.
 * Returns a wrapper with .find(), .hover(), .text, .drag_to().
 * @param {string} selector - CSS selector
 * @param {object} options - Options hash (e.g., {match: "first"})
 * @returns {object} Element wrapper
 */
export function find(selector, options = {}) {
  const el = document.querySelector(selector);
  if (!el) {
    throw new Error(`find: could not find element matching "${selector}"`);
  }
  return wrapElement(el);
}

/**
 * Find all elements matching a CSS selector — equivalent to Capybara's all.
 * Returns an array of element wrappers with .find(), .hover(), .text, .drag_to().
 * @param {string} selector - CSS selector
 * @returns {object[]} Array of element wrappers
 */
export function all(selector) {
  return [...document.querySelectorAll(selector)].map(wrapElement);
}

/**
 * Scope subsequent assertions to within a matched element — equivalent to
 * Capybara's within(selector).  In a real browser, hidden elements
 * (display:none via CSS) are excluded.  jsdom does not compute external
 * stylesheets, so we approximate visibility:
 *   1. Skip elements with inline style display:none
 *   2. Skip elements with class "hidden" or aria-hidden="true"
 *   3. Skip elements inside a hidden ancestor
 * If all candidates appear visible, return the last match (content panels
 * typically come after decorative/info elements in DOM order).
 * @param {string} selector - CSS selector
 * @returns {HTMLElement|null}
 */
export function within(selector) {
  const elements = document.querySelectorAll(selector);
  if (elements.length === 0) return null;
  if (elements.length === 1) return elements[0];

  // Filter to "visible" elements
  const visible = [];
  for (const el of elements) {
    if (el.style && el.style.display === 'none') continue;
    if (el.hidden) continue;
    if (el.getAttribute('aria-hidden') === 'true') continue;
    if (el.classList && el.classList.contains('hidden')) continue;
    if (el.closest('[hidden], [aria-hidden="true"], .hidden')) continue;
    visible.push(el);
  }

  // If filtering narrowed to one, use it; otherwise return last match
  if (visible.length === 1) return visible[0];
  if (visible.length > 1) return visible[visible.length - 1];
  return elements[elements.length - 1];
}

/**
 * Accept a confirmation dialog and execute the callback.
 * In jsdom, Turbo confirm dialogs are bypassed (fetch submits directly),
 * so this simply executes the callback.
 * @param {Function} callback - Async function to execute
 */
export async function acceptConfirm(callback) {
  await callback();
}

/**
 * Process Turbo Stream HTML — update DOM based on <turbo-stream> elements.
 * Supports: replace, update, append, prepend, remove.
 */
function processTurboStream(html) {
  const template = document.createElement('template');
  template.innerHTML = html;

  for (const stream of template.content.querySelectorAll('turbo-stream')) {
    const action = stream.getAttribute('action');
    const target = document.getElementById(stream.getAttribute('target'));
    const content = stream.querySelector('template')?.content;

    if (!target) continue;

    switch (action) {
      case 'replace':
        target.replaceWith(content.cloneNode(true));
        break;
      case 'update':
        target.innerHTML = '';
        target.appendChild(content.cloneNode(true));
        break;
      case 'append':
        target.appendChild(content.cloneNode(true));
        break;
      case 'prepend':
        target.prepend(content.cloneNode(true));
        break;
      case 'remove':
        target.remove();
        break;
    }
  }
}

/**
 * Clean up after a test — stop Stimulus and clear the DOM.
 */
export function cleanup() {
  if (_stimulusApp) {
    _stimulusApp.stop();
    _stimulusApp = null;
  }
  document.body.innerHTML = '';
}
