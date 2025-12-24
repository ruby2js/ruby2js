import * as Stimulus from "@hotwired/stimulus";

export class DialogController extends Stimulus.Controller {
  static targets = ["overlay"];

  get connect() {
    return document.addEventListener(
      "keydown",
      e => this.handleKeydown(e)
    )
  };

  get disconnect() {
    return document.removeEventListener(
      "keydown",
      e => this.handleKeydown(e)
    )
  };

  get open() {
    this.overlayTarget.classList.remove("hidden");
    return document.body.classList.add("overflow-hidden")
  };

  get close() {
    this.overlayTarget.classList.add("hidden");
    return document.body.classList.remove("overflow-hidden")
  };

  backdropClick(event) {
    if (event.target === this.overlayTarget) this.close
  };

  stopPropagation(event) {
    event.stopPropagation
  };

  handleKeydown(event) {
    if (event.key === "Escape" && !this.overlayTarget.classList.contains("hidden")) {
      this.close
    }
  }
}