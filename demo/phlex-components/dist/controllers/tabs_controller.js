import * as Stimulus from "@hotwired/stimulus";

export class TabsController extends Stimulus.Controller {
  static targets = ["tab", "panel"];
  static values = {index: String};

  get connect() {
    return this.showTab(this.indexValue ?? 0)
  };

  select(event) {
    let index = parseInt(event.currentTarget.dataset.index, 10);
    this.showTab(index)
  };

  showTab(index) {
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.add("active");
        tab.setAttribute("aria-selected", "true")
      } else {
        tab.classList.remove("active");
        tab.setAttribute("aria-selected", "false")
      }
    });

    this.panelTargets.forEach((panel, i) => (
      i === index ? panel.classList.remove("hidden") : panel.classList.add("hidden")
    ))
  }
}