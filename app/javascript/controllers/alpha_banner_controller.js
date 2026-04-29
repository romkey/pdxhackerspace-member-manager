import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    storageKey: { type: String, default: "alphaBannerDismissed" }
  }

  connect() {
    if (this.dismissed()) this.hide()
  }

  dismiss() {
    try {
      localStorage.setItem(this.storageKeyValue, "1")
    } catch (_error) {
      // Dismiss for this page even if browser storage is unavailable.
    }

    this.hide()
  }

  dismissed() {
    try {
      return localStorage.getItem(this.storageKeyValue) === "1"
    } catch (_error) {
      return false
    }
  }

  hide() {
    this.element.classList.add("d-none")
  }
}
