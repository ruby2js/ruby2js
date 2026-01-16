// React testing utilities for RBX component integration tests
// Provides helpers for rendering React components in tests

import { render, screen, waitFor, act } from '@testing-library/react';
import React from 'react';

/**
 * Render a React component and return testing utilities
 * @param {React.ComponentType} Component - The component to render
 * @param {Object} props - Props to pass to the component
 * @returns {Object} - Testing utilities from @testing-library/react
 */
export function renderComponent(Component, props = {}) {
  return render(React.createElement(Component, props));
}

/**
 * Render a component that's exported as default from a view module
 * @param {Object} viewModule - The imported view module (e.g., from Index.js)
 * @param {Object} props - Props to pass to the component
 * @returns {Object} - Testing utilities from @testing-library/react
 */
export function renderView(viewModule, props = {}) {
  const Component = viewModule.default || viewModule;
  return render(React.createElement(Component, props));
}

/**
 * Create a mock context object for controller tests
 * @param {Object} overrides - Properties to override in the context
 * @returns {Object} - Mock context object
 */
export function createMockContext(overrides = {}) {
  return {
    params: {},
    flash: {
      get: () => '',
      set: () => {},
      consumeNotice: () => ({ present: false }),
      consumeAlert: () => ''
    },
    contentFor: {},
    request: {
      headers: { accept: 'text/html' }
    },
    ...overrides
  };
}

/**
 * Create a mock context requesting JSON
 * @param {Object} overrides - Properties to override in the context
 * @returns {Object} - Mock context object with JSON accept header
 */
export function createJsonContext(overrides = {}) {
  return createMockContext({
    request: {
      headers: { accept: 'application/json' }
    },
    ...overrides
  });
}

// Re-export testing library utilities for convenience
export { render, screen, waitFor, act };
export { cleanup, fireEvent } from '@testing-library/react';
