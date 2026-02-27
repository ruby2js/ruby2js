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

  const form = button.closest('form');
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
