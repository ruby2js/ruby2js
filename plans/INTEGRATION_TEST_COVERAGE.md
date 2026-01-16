# Integration Test Coverage Plan

## Current Status

The integration test suite covers all five demo applications with comprehensive model, controller, and view tests.

### Coverage Summary

| Demo | Models | Controllers | Views | Real-time | Stimulus |
|------|--------|-------------|-------|-----------|----------|
| blog | complete | complete | ERB index/show | - | - |
| chat | complete | complete | ERB index | - | - |
| workflow | complete | complete | ERB index only | - | - |
| photo_gallery | complete | complete | ERB index | - | - |
| notes | complete | complete | RBX Show (React) | - | - |

### Completed Work

- Model CRUD operations and validations
- Controller actions (index, show, create, update, destroy)
- ERB view rendering via controller tests
- RBX/React component rendering via React Testing Library (notes Show view)
- Path helper validation
- Query interface (where, order, limit, first, count)
- JSON API responses

## Deferred Work

### 1. Workflow Show View (RBX/React Flow)

**Complexity: High**

The workflow Show view uses React Flow for the canvas editor. Testing requires:
- Mocking React Flow components (`ReactFlow`, `Background`, `Controls`)
- Mocking `JsonStreamProvider` for real-time updates
- Handling canvas interactions (node dragging, edge creation)

**Approach:**
```javascript
vi.mock('@xyflow/react', () => ({
  ReactFlow: ({ children }) => <div data-testid="react-flow">{children}</div>,
  Background: () => null,
  Controls: () => null,
  useNodesState: vi.fn(() => [[], vi.fn(), vi.fn()]),
  useEdgesState: vi.fn(() => [[], vi.fn(), vi.fn()]),
}));
```

**What to test:**
- Component renders without errors
- Initial nodes/edges from workflow are displayed
- Node position updates trigger save handler

### 2. Real-time Features (Turbo Streams)

**Complexity: High**

Several demos use Turbo Streams for real-time updates:
- blog: Article/comment broadcasts
- chat: Message broadcasts
- workflow: Node/edge position updates via JsonStreamProvider

**Requirements:**
- Mock ActionCable/WebSocket connections
- Mock BroadcastChannel for browser target
- Simulate stream events

**Approach:**
```javascript
// Mock Turbo Stream processing
global.Turbo = {
  StreamActions: {
    append: vi.fn(),
    prepend: vi.fn(),
    replace: vi.fn(),
    remove: vi.fn(),
  }
};
```

**What to test:**
- Stream actions update DOM correctly
- Broadcasts are received and processed
- Connection lifecycle (connect, disconnect, reconnect)

### 3. Stimulus Controllers

**Complexity: Medium**

Some demos may include Stimulus controllers for JavaScript behavior.

**Requirements:**
- Load Stimulus application
- Register controllers
- Simulate DOM events (click, input, submit)

**Approach:**
```javascript
import { Application } from '@hotwired/stimulus';
import { screen, fireEvent } from '@testing-library/dom';

const application = Application.start();
application.register('controller-name', ControllerClass);
```

**What to test:**
- Controller connects to DOM element
- Actions respond to events
- Targets are accessible
- Values update correctly

## Implementation Priority

1. **Workflow Show View** - Validates RBX/React Flow integration
2. **Turbo Streams** - Core feature for real-time apps
3. **Stimulus** - Lower priority, smaller scope

## Notes

- All ERB view tests are complete (verified via controller action tests)
- RBX components that don't make API calls work with React Testing Library
- RBX components that call path helper RPC methods need API mocking
- The notes Index view was intentionally not tested because it requires path helper RPC infrastructure

## Related Files

- `test/integration/*.test.mjs` - Integration test files
- `test/integration/vitest.config.mjs` - Vitest configuration with React alias
- `test/integration/react-test-utils.mjs` - React testing utilities
