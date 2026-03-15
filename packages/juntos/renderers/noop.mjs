// No-op view renderer for juntos:view-renderer virtual module
// Used when no framework views are detected — tree-shakes to nothing

export function renderElement(element) {
  return String(element);
}

export function clientRenderElement(element, container) {
  container.innerHTML = typeof element === 'string' ? element : String(element);
}

export function clientHydrateElement(element, container) {
  clientRenderElement(element, container);
}

export function isFrameworkElement() {
  return false;
}
