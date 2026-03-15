// React view renderer for juntos:view-renderer virtual module
// Server-side rendering via react-dom/server, client-side via react-dom/client

import ReactDOMServer from 'react-dom/server';
import { createRoot, hydrateRoot } from 'react-dom/client';

export function renderElement(element) {
  return ReactDOMServer.renderToString(element);
}

export function clientRenderElement(element, container) {
  if (container._reactRoot) {
    container._reactRoot.unmount();
  }
  const root = createRoot(container);
  container._reactRoot = root;
  root.render(element);
}

export function clientHydrateElement(element, container) {
  if (container._reactRoot) {
    container._reactRoot.unmount();
  }
  const root = hydrateRoot(container, element);
  container._reactRoot = root;
}

export function isFrameworkElement(value) {
  return value && typeof value === 'object' && value.$$typeof;
}
