import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "subject",
    "bodyHtml",
    "bodyText",
    "syncBodyText",
    "rewriteButton",
    "undoButton",
    "spinner",
    "status"
  ]
  static values = { url: String }

  connect() {
    this.previousState = null
    this.loading = false
  }

  async rewrite(event) {
    event.preventDefault()
    if (this.loading) return

    this.previousState = {
      subject: this.subjectTarget.value,
      bodyHtml: this.currentHtmlBody(),
      bodyText: this.bodyTextTarget.value
    }
    this.toggleUndo(true)
    this.setStatus("", "")
    this.setLoading(true)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": this.csrfToken()
        },
        body: JSON.stringify({
          rewrite: {
            subject: this.subjectTarget.value,
            body_html: this.currentHtmlBody(),
            body_text: this.bodyTextTarget.value
          }
        })
      })

      const payload = await response.json()
      if (!response.ok) {
        this.setStatus(payload.error || "Rewrite failed.", "danger")
        return
      }

      this.subjectTarget.value = payload.subject || ""
      this.setHtmlBody(payload.body_html || "")
      if (this.shouldSyncBodyText()) {
        this.syncBodyTextFromHtml()
      } else {
        this.bodyTextTarget.value = payload.body_text || ""
      }
      this.setStatus(payload.message || "Template rewritten.", "success")
    } catch (_error) {
      this.setStatus("Rewrite failed. Please try again.", "danger")
    } finally {
      this.setLoading(false)
    }
  }

  undo(event) {
    event.preventDefault()
    if (!this.previousState) return

    this.subjectTarget.value = this.previousState.subject
    this.setHtmlBody(this.previousState.bodyHtml)
    if (this.shouldSyncBodyText()) {
      this.syncBodyTextFromHtml()
    } else {
      this.bodyTextTarget.value = this.previousState.bodyText
    }
    this.previousState = null
    this.toggleUndo(false)
    this.setStatus("Restored previous template text.", "secondary")
  }

  syncBodyText() {
    this.syncBodyTextFromHtml()
  }

  syncBodyTextBeforeSubmit() {
    this.syncBodyTextFromHtml()
  }

  setLoading(isLoading) {
    this.loading = isLoading
    this.rewriteButtonTarget.disabled = isLoading
    this.spinnerTarget.classList.toggle("d-none", !isLoading)
  }

  setStatus(message, variant) {
    this.statusTarget.textContent = message
    this.statusTarget.className = "small"
    if (message && variant) {
      this.statusTarget.classList.add(`text-${variant}`)
    } else {
      this.statusTarget.classList.add("text-muted")
    }
  }

  toggleUndo(show) {
    this.undoButtonTarget.classList.toggle("d-none", !show)
    this.undoButtonTarget.disabled = !show
  }

  currentHtmlBody() {
    const editor = this.editorInstance()
    return editor ? editor.getContent() : this.bodyHtmlTarget.value
  }

  setHtmlBody(value) {
    const editor = this.editorInstance()
    this.bodyHtmlTarget.value = value
    if (editor) {
      editor.setContent(value)
      editor.save()
    }
  }

  editorInstance() {
    if (typeof tinymce === "undefined") return null
    return tinymce.get(this.bodyHtmlTarget.id)
  }

  syncBodyTextFromHtml() {
    if (!this.shouldSyncBodyText()) return

    this.bodyTextTarget.value = this.htmlToPlainText(this.currentHtmlBody())
  }

  shouldSyncBodyText() {
    return !this.hasSyncBodyTextTarget || this.syncBodyTextTarget.checked
  }

  htmlToPlainText(html) {
    const container = document.createElement("div")
    container.innerHTML = html || ""

    container.querySelectorAll("br").forEach((element) => {
      element.replaceWith("\n")
    })

    container.querySelectorAll("p, div, h1, h2, h3, h4, h5, h6, li, tr").forEach((element) => {
      element.append("\n")
    })

    container.querySelectorAll("td, th").forEach((element) => {
      element.append(" ")
    })

    return container.textContent
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim()
  }

  csrfToken() {
    const tag = document.querySelector("meta[name='csrf-token']")
    return tag ? tag.content : ""
  }
}
