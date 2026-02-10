import { Controller } from "@hotwired/stimulus"

// Polls for recent access controller logs and updates the table in place.
// Also shows ephemeral inline command results below the controller that ran them.
export default class extends Controller {
  static targets = ["logsBody", "inlineResult"]
  static values = {
    url: String,
    interval: { type: Number, default: 3000 }
  }

  connect() {
    this.knownLogIds = new Set()
    this.inlineResults = {} // controller_id -> log_id being shown
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.poll()
    this.timer = setInterval(() => this.poll(), this.intervalValue)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  async poll() {
    try {
      const since = new Date(Date.now() - 3600000).toISOString()
      const response = await fetch(`${this.urlValue}?since=${encodeURIComponent(since)}`, {
        headers: { "Accept": "application/json" }
      })
      if (!response.ok) return
      const logs = await response.json()
      this.updateLogsTable(logs)
      this.updateInlineResults(logs)
    } catch (e) {
      // Silently retry on next interval
    }
  }

  updateLogsTable(logs) {
    if (!this.hasLogsBodyTarget) return
    const tbody = this.logsBodyTarget
    
    // Build new tbody content
    if (logs.length === 0) {
      tbody.innerHTML = `<tr><td colspan="7" class="text-center text-muted py-4">No recent logs.</td></tr>`
      return
    }

    tbody.innerHTML = logs.map(log => this.buildLogRow(log)).join('')
    
    // Reinitialize tooltips for new content
    const tooltips = tbody.querySelectorAll('[data-bs-toggle="tooltip"]')
    tooltips.forEach(el => new bootstrap.Tooltip(el))
  }

  updateInlineResults(logs) {
    // For each controller that has inline result targets, find the most recent log
    this.inlineResultTargets.forEach(el => {
      const controllerId = parseInt(el.dataset.controllerId)
      const recentLog = logs.find(l => l.controller_id === controllerId)
      
      if (!recentLog) {
        el.innerHTML = ''
        el.style.display = 'none'
        return
      }

      // Only show if the log is recent (within last 5 minutes) or still running
      const logTime = new Date(recentLog.created_at.replace(' ', 'T'))
      const fiveMinAgo = new Date(Date.now() - 300000)
      
      if (recentLog.status === 'running' || logTime > fiveMinAgo) {
        el.style.display = 'block'
        el.innerHTML = this.buildInlineResult(recentLog)
      } else {
        el.innerHTML = ''
        el.style.display = 'none'
      }
    })
  }

  buildInlineResult(log) {
    let statusClass, statusIcon, statusText
    if (log.status === 'running') {
      statusClass = 'info'
      statusIcon = '<span class="spinner-border spinner-border-sm me-1"></span>'
      statusText = 'Running...'
    } else if (log.status === 'success') {
      statusClass = 'success'
      statusIcon = '<i class="bi bi-check-circle-fill me-1"></i>'
      statusText = 'Success'
    } else {
      statusClass = 'danger'
      statusIcon = '<i class="bi bi-x-circle-fill me-1"></i>'
      statusText = 'Failed'
    }

    let outputHtml = ''
    if (log.output) {
      outputHtml = `<pre class="bg-dark text-light p-2 rounded small mb-0 mt-2" style="max-height: 200px; overflow: auto;">${this.escapeHtml(log.output)}</pre>`
    } else if (log.status === 'running') {
      outputHtml = '<p class="text-muted small mb-0 mt-1">Waiting for output...</p>'
    }

    return `
      <div class="alert alert-${statusClass} py-2 px-3 mb-0 small">
        <div class="d-flex align-items-center justify-content-between">
          <span>${statusIcon}<code>${this.escapeHtml(log.action)}</code> ${statusText}</span>
          <span class="text-muted">${log.created_at}${log.exit_code !== null && log.exit_code !== undefined ? ` · exit ${log.exit_code}` : ''}${log.duration ? ` · ${log.duration}s` : ''}</span>
        </div>
        ${outputHtml}
      </div>
    `
  }

  buildLogRow(log) {
    let rowClass = ''
    if (log.status === 'failed') rowClass = 'table-danger'
    else if (log.status === 'running') rowClass = 'table-warning'

    const durationHtml = log.duration ? `<br><small class="text-muted">${log.duration}s</small>` : ''
    const exitCodeHtml = log.exit_code !== null && log.exit_code !== undefined ? `<code>${log.exit_code}</code>` : '<span class="text-muted">—</span>'
    
    let commandHtml = '<span class="text-muted">—</span>'
    if (log.command_line) {
      const truncated = log.command_line.length > 50 ? log.command_line.substring(0, 50) + '...' : log.command_line
      commandHtml = `<code class="small" style="max-width:300px;display:inline-block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" data-bs-toggle="tooltip" data-bs-title="${this.escapeAttr(log.command_line)}">${this.escapeHtml(truncated)}</code>`
    }

    let outputHtml
    if (!log.output && log.status === 'success') {
      outputHtml = '<i class="bi bi-check-circle-fill text-success"></i>'
    } else if (log.status === 'running') {
      outputHtml = '<span class="spinner-border spinner-border-sm text-warning"></span>'
    } else {
      const modalId = `logModal${log.id}`
      outputHtml = `
        <button type="button" class="btn btn-sm btn-outline-secondary" data-bs-toggle="modal" data-bs-target="#${modalId}">View</button>
        <div class="modal fade" id="${modalId}" tabindex="-1" aria-hidden="true">
          <div class="modal-dialog modal-lg">
            <div class="modal-content">
              <div class="modal-header">
                <h5 class="modal-title">Log Output: ${this.escapeHtml(log.controller_name)} - ${this.escapeHtml(log.action)}</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
              </div>
              <div class="modal-body">
                <p class="text-muted small mb-2">
                  <strong>Time:</strong> ${log.created_at}<br>
                  <strong>Command:</strong> <code>${this.escapeHtml(log.command_line || 'N/A')}</code><br>
                  <strong>Exit Code:</strong> ${log.exit_code !== null && log.exit_code !== undefined ? log.exit_code : 'N/A'}
                </p>
                ${log.output ? `<pre class="bg-dark text-light p-3 rounded" style="max-height:400px;overflow:auto;">${this.escapeHtml(log.output)}</pre>` : '<p class="text-muted fst-italic">No output produced.</p>'}
              </div>
              <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
              </div>
            </div>
          </div>
        </div>
      `
    }

    let statusBadgeClass = 'secondary'
    if (log.status === 'success') statusBadgeClass = 'success'
    else if (log.status === 'failed') statusBadgeClass = 'danger'
    else if (log.status === 'running') statusBadgeClass = 'warning'

    return `
      <tr class="${rowClass}">
        <td class="text-nowrap">
          <small>${log.created_at}</small>
          ${durationHtml}
        </td>
        <td><strong>${this.escapeHtml(log.controller_name)}</strong></td>
        <td><code>${this.escapeHtml(log.action)}</code></td>
        <td><span class="badge text-bg-${statusBadgeClass}">${log.status.charAt(0).toUpperCase() + log.status.slice(1)}</span></td>
        <td>${exitCodeHtml}</td>
        <td>${commandHtml}</td>
        <td>${outputHtml}</td>
      </tr>
    `
  }

  escapeHtml(text) {
    if (!text) return ''
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }

  escapeAttr(text) {
    if (!text) return ''
    return text.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/'/g, '&#39;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  }
}
