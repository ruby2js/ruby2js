#!/usr/bin/env node
// Test that transpiled Ink components render correctly

import { render, Box, Text } from 'ink';
import Spinner from 'ink-spinner';
import React from 'react';

// Import transpiled component
import { Greeting } from './dist/components/greeting.js';

// Make Ink elements available globally (as they would be in the runtime)
globalThis.Box = Box;
globalThis.Text = Text;
globalThis.Spinner = Spinner;
globalThis.React = React;

console.log('=== Testing transpiled Greeting component ===\n');

console.log('Test 1: loading=false');
const { unmount: unmount1 } = render(
  React.createElement(Greeting, { name: 'Developer', loading: false })
);

setTimeout(() => {
  unmount1();

  console.log('\n\nTest 2: loading=true (with Spinner)');
  const { unmount: unmount2 } = render(
    React.createElement(Greeting, { name: 'Developer', loading: true })
  );

  setTimeout(() => {
    unmount2();
    console.log('\n\n=== All tests passed! ===');
    process.exit(0);
  }, 1500);  // Give spinner time to animate
}, 500);
