import { Controller } from "@hotwired/stimulus"

// Provides client-side live filtering for tables (Pattern A) and panel lists
// (Pattern B). Controlled entirely by data attributes — no per-page JavaScript.
//
// Pattern A — table row filter (no minimum chars, has clear button):
//   <div data-controller="live-filter">
//     <input data-live-filter-target="input" data-action="input->live-filter#filter">
//     <button data-live-filter-target="clearButton"
//             data-action="click->live-filter#clear" class="d-none">Clear</button>
//     <tbody>
//       <tr data-live-filter-target="item" data-search-text="...">...</tr>
//     </tbody>
//   </div>
//
// Pattern B — panel filter with minimum character threshold:
//   <div data-controller="live-filter" data-live-filter-min-length-value="2">
//     <input data-live-filter-target="input" data-action="input->live-filter#filter">
//     <div data-live-filter-target="resultsContainer" class="d-none">
//       <a data-live-filter-target="item" class="d-none" data-search-text="...">...</a>
//     </div>
//     <div data-live-filter-target="noResults" class="d-none">No members found.</div>
//   </div>

export default class extends Controller {
  static targets = ["input", "item", "clearButton", "resultsContainer", "noResults"]
  static values  = {
    minLength: { type: Number, default: 0 },
    server: { type: Boolean, default: false },
    delay: { type: Number, default: 300 }
  }

  filter() {
    const term = this.inputTarget.value.toLowerCase().trim()

    if (this.serverValue) {
      this._updateClearButton(term)
      this._scheduleServerSearch(term)
      return
    }

    // Pattern B: below minimum length — hide everything
    if (term.length < this.minLengthValue) {
      if (this.hasResultsContainerTarget) {
        this.resultsContainerTarget.classList.add("d-none")
      }
      if (this.hasNoResultsTarget) {
        this.noResultsTarget.classList.add("d-none")
      }
      this.itemTargets.forEach(item => item.classList.add("d-none"))
      this._updateClearButton(term)
      return
    }

    let visibleCount = 0

    this.itemTargets.forEach(item => {
      const text = (item.dataset.searchText || "").toLowerCase()
      const visible = text.includes(term)

      if (this.hasResultsContainerTarget) {
        // Pattern B: toggle via d-none class
        item.classList.toggle("d-none", !visible)
      } else {
        // Pattern A: toggle via d-none class
        item.classList.toggle("d-none", !visible)
      }

      if (visible) visibleCount++
    })

    // Pattern B: show/hide results container and no-results message
    if (this.hasResultsContainerTarget) {
      this.resultsContainerTarget.classList.toggle("d-none", visibleCount === 0)
    }
    if (this.hasNoResultsTarget) {
      this.noResultsTarget.classList.toggle("d-none", visibleCount > 0)
    }

    this._updateClearButton(term)
  }

  clear() {
    this.inputTarget.value = ""
    if (this.serverValue) {
      this._updateClearButton("")
      this._submitServerSearch()
      this.inputTarget.focus()
      return
    }

    this.filter()
    this.inputTarget.focus()
  }

  // Run the filter on connect so a pre-filled search value (e.g. from params)
  // is applied immediately on page load.
  connect() {
    if (this.serverValue) {
      this._updateClearButton(this.inputTarget.value.toLowerCase().trim())
      return
    }

    if (this.inputTarget.value) {
      this.filter()
    }
  }

  _updateClearButton(term) {
    if (!this.hasClearButtonTarget) return
    this.clearButtonTarget.classList.toggle("d-none", term === "")
  }

  _scheduleServerSearch(term) {
    clearTimeout(this.searchTimeout)
    this.searchTimeout = setTimeout(() => this._submitServerSearch(), this.delayValue)
  }

  _submitServerSearch() {
    const form = this.inputTarget.form || this.element.closest("form")
    if (!form) return

    form.requestSubmit()
  }
}
