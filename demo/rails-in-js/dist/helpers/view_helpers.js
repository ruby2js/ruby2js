// View helpers for HTML generation
// Mimics Rails view helpers
export const ViewHelpers = (() => {
  function link_to(text, path, options={}) {
    let onclick = options.onclick ?? `navigate('${path}')`;
    let style = options.style ? ` style="${options.style}"` : "";
    let css_class = options.class ? ` class="${options.class}"` : "";
    return `<a onclick="${onclick}"${css_class}${style}>${text}</a>`
  };

  function button_to(text, path, options={}) {
    let method = options.method ?? "post";
    let css_class = options.class ?? "";
    let onclick = options.onclick ?? `${method}Action('${path}')`;
    return `<button class="${css_class}" onclick="${onclick}">${text}</button>`
  };

  return {link_to, button_to}
})()
//# sourceMappingURL=view_helpers.js.map