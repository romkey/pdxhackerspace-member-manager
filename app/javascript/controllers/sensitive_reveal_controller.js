import { Controller } from "@hotwired/stimulus"

// Toggles .sensitive-reveal--shown on the root to show/hide blurred [data-sensitive-reveal-target="blurred"] fields.
export default class extends Controller {
  static targets = ["label"]

  connect() {
    this._shown = false
  }

  toggle() {
    this._shown = !this._shown
    this.element.classList.toggle("sensitive-reveal--shown", this._shown)
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this._shown ? "Hide contact details" : "Show contact details"
    }
  }
}
