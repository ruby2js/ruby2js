// Ink Runtime - Base classes for Ruby-transpiled Ink components
//
// This provides the base Ink.Component class that Ruby components extend.
// The actual Ink rendering is handled by the ink package.

import React from 'react';
import { useInput, useApp } from 'ink';

/**
 * Base class for Ink components written in Ruby.
 *
 * Ruby usage:
 *   class MyComponent < Ink::Component
 *     keys return: :submit, up: :previous
 *
 *     def view_template
 *       Box { Text { "Hello" } }
 *     end
 *   end
 *
 * This base class provides:
 * - Key binding support via useInput hook
 * - App exit via exit_app method
 * - Component lifecycle
 */
export class Component {
  constructor(props = {}) {
    this.props = props;
  }

  // Override in subclass
  render() {
    return null;
  }
}

/**
 * Hook to handle key bindings defined in Ruby components.
 *
 * @param {Object} bindings - Map of key names to handler functions
 * @param {Object} options - useInput options (e.g., isActive)
 */
export function useKeyBindings(bindings, options = {}) {
  useInput((input, key) => {
    // Check for special keys
    if (key.return && bindings.return) {
      bindings.return();
      return;
    }
    if (key.upArrow && bindings.up) {
      bindings.up();
      return;
    }
    if (key.downArrow && bindings.down) {
      bindings.down();
      return;
    }
    if (key.leftArrow && bindings.left) {
      bindings.left();
      return;
    }
    if (key.rightArrow && bindings.right) {
      bindings.right();
      return;
    }
    if (key.tab && bindings.tab) {
      bindings.tab();
      return;
    }
    if (key.escape && bindings.escape) {
      bindings.escape();
      return;
    }
    if (key.backspace && bindings.backspace) {
      bindings.backspace();
      return;
    }
    if (key.delete && bindings.delete) {
      bindings.delete();
      return;
    }

    // Check for ctrl combinations
    if (key.ctrl) {
      const ctrlKey = `ctrl_${input}`;
      if (bindings[ctrlKey]) {
        bindings[ctrlKey]();
        return;
      }
    }

    // Check for character bindings
    if (input && bindings[input]) {
      bindings[input]();
      return;
    }
  }, options);
}

/**
 * Hook to get the exit function for quitting the app.
 */
export function useExit() {
  const { exit } = useApp();
  return exit;
}

// Export Ink namespace for Ruby compatibility
export const Ink = {
  Component
};

export default Ink;
