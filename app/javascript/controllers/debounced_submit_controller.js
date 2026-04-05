import { Controller } from "@hotwired/stimulus"

// Debounced GET form submit (e.g. Turbo Frame list updates while typing).
export default class extends Controller {
  static targets = ["input", "clearButton"]
  static values = { delay: { type: Number, default: 350 } }

  connect() {
    this._timer = null
    this._updateClearButton()
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  schedule() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => {
      this._updateClearButton()
      this.element.requestSubmit()
    }, this.delayValue)
  }

  clear() {
    clearTimeout(this._timer)
    if (this.hasInputTarget) this.inputTarget.value = ""
    this._updateClearButton()
    this.element.requestSubmit()
    if (this.hasInputTarget) this.inputTarget.focus()
  }

  _updateClearButton() {
    if (!this.hasClearButtonTarget || !this.hasInputTarget) return
    const term = this.inputTarget.value.trim()
    this.clearButtonTarget.classList.toggle("d-none", term === "")
  }
}
