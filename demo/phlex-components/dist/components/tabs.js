export class Tabs extends Phlex.HTML {
  render({ attrs, default_index, tabs }) {
    let _phlex_out = "";

    _phlex_out += `<div data-controller="tabs" data-tabs-index-value="${default_index}" class="tabs"><div class="tabs-list" role="tablist">${tabs.forEach((tab, i) => (
      _phlex_out += `<button data-tabs-target="tab" data-action="click->tabs#select" data-index="${i}" role="tab" class="tabs-trigger" aria-selected="${(i === default_index).toString()}">${String(tab.label)}</button>`
    ))}</div>${tabs.forEach((tab, i) => (
      _phlex_out += `<div data-tabs-target="panel" role="tabpanel" class="${`tabs-content${i === default_index ? "" : " hidden"}`}">${String(tab.content)}</div>`
    ))}</div>`;

    return _phlex_out
  }
}