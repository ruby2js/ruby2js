export class Dialog extends Phlex.HTML {
  render({ attrs, description, title }) {
    let _phlex_out = "";
    _phlex_out += `<div data-controller="dialog"><button class="btn btn-primary" data-action="click->dialog#open">Open Dialog</button><div class="dialog-overlay hidden" data-dialog-target="overlay" data-action="click->dialog#backdropClick"><div class="dialog-content" role="dialog" aria-modal="true" data-action="click->dialog#stopPropagation">${title || description ? _phlex_out += `<div class="dialog-header">${title ? _phlex_out += `<h2 class="dialog-title">${String(title)}</h2>` : null}${description ? _phlex_out += `<p class="dialog-description">${String(description)}</p>` : null}</div>` : null}<div class="dialog-body"></div><button class="dialog-close" data-action="click->dialog#close" aria-label="Close">×</button></div></div></div>`;
    return _phlex_out
  }
}