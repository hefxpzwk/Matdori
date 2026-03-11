const NOTE_FADE_DELAY_MS = 0
const NOTE_FADE_DURATION_MS = 300

function normalizeColor(value, fallback = "#3b82f6") {
  return /^#[0-9a-fA-F]{6}$/.test(value || "") ? value : fallback
}

function normalizeName(value) {
  if (typeof value !== "string") {
    return "Guest"
  }

  const trimmed = value.trim()
  return trimmed === "" ? "Guest" : trimmed.slice(0, 30)
}

function normalizeMode(value) {
  if (value === "typing" || value === "final" || value === "clear") {
    return value
  }

  return "clear"
}

function normalizeNoteText(value) {
  if (typeof value !== "string") {
    return ""
  }

  return value.trim().slice(0, 80)
}

function normalizeTimestamp(value) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? Math.max(0, Math.round(parsed)) : 0
}

function readMeta(presence) {
  if (!presence || !Array.isArray(presence.metas) || presence.metas.length === 0) {
    return null
  }

  return presence.metas[0]
}

function buildCursorNode(sessionId) {
  const container = document.createElement("div")
  container.id = `cursor-${sessionId}`
  container.className = "absolute z-30 pointer-events-none"
  container.dataset.sessionId = sessionId

  const wrap = document.createElement("div")
  wrap.style.transform = "translate(-2px, -2px)"

  const pointerRow = document.createElement("div")
  pointerRow.style.display = "flex"
  pointerRow.style.alignItems = "center"
  pointerRow.style.gap = "4px"

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("width", "14")
  svg.setAttribute("height", "18")
  svg.setAttribute("viewBox", "0 0 14 18")
  svg.setAttribute("fill", "none")

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
  path.setAttribute("d", "M1 1L12 12L7 13.5L5 17L1 1Z")
  path.setAttribute("stroke", "white")
  path.setAttribute("stroke-width", "1")
  svg.appendChild(path)

  const nameLabel = document.createElement("span")
  nameLabel.className = "cursor-name-tag"
  nameLabel.style.color = "white"
  nameLabel.style.fontSize = "11px"
  nameLabel.style.lineHeight = "1"
  nameLabel.style.padding = "3px 6px"
  nameLabel.style.borderRadius = "999px"
  nameLabel.style.display = "inline-block"
  nameLabel.style.transform = "translateY(-2px)"

  pointerRow.appendChild(svg)
  pointerRow.appendChild(nameLabel)

  const noteBubble = document.createElement("span")
  noteBubble.className = "cursor-note-bubble"
  noteBubble.style.display = "none"
  noteBubble.style.marginTop = "4px"
  noteBubble.style.maxWidth = "240px"
  noteBubble.style.whiteSpace = "nowrap"
  noteBubble.style.overflow = "hidden"
  noteBubble.style.textOverflow = "ellipsis"
  noteBubble.style.borderRadius = "999px"
  noteBubble.style.padding = "6px 12px"
  noteBubble.style.fontSize = "13px"
  noteBubble.style.lineHeight = "1.2"
  noteBubble.style.letterSpacing = "0.01em"
  noteBubble.style.color = "#ffffff"
  noteBubble.style.background = "#3b82f6"
  noteBubble.style.border = "1px solid rgba(255,255,255,0.6)"
  noteBubble.style.boxShadow = "0 8px 24px rgba(15, 23, 42, 0.24)"
  noteBubble.style.backdropFilter = "blur(4px)"
  noteBubble.style.opacity = "1"
  noteBubble.style.transform = "translateY(0px)"
  noteBubble.style.filter = "blur(0px)"
  noteBubble.style.transition = "none"

  wrap.appendChild(pointerRow)
  wrap.appendChild(noteBubble)
  container.appendChild(wrap)

  return {
    container,
    pointerRow,
    path,
    nameLabel,
    noteBubble,
    noteMode: "clear",
    noteUpdatedAtMs: 0,
    noteText: "",
    noteFadeStartTimer: null,
    noteFadeEndTimer: null,
  }
}

const RemoteCursors = {
  mounted() {
    this.cursorNodes = new Map()
    this.toggleButton = document.querySelector(this.el.dataset.toggleSelector || "")
    this.toggleStateLabel = document.querySelector(this.el.dataset.toggleStateSelector || "")
    this.remoteVisible = true

    this.syncToggleUi = () => {
      if (!(this.toggleButton instanceof HTMLElement)) {
        return
      }
      this.toggleButton.setAttribute("aria-pressed", this.remoteVisible ? "true" : "false")

      if (this.toggleStateLabel instanceof HTMLElement) {
        this.toggleStateLabel.textContent = this.remoteVisible ? "ON" : "OFF"
      }
    }

    this.clearAllRemoteCursors = () => {
      this.cursorNodes.forEach((parts) => {
        this.clearNoteTimers(parts)
        parts.container.remove()
      })

      this.cursorNodes.clear()
    }

    this.clearNoteTimers = (parts) => {
      if (parts.noteFadeStartTimer) {
        window.clearTimeout(parts.noteFadeStartTimer)
        parts.noteFadeStartTimer = null
      }

      if (parts.noteFadeEndTimer) {
        window.clearTimeout(parts.noteFadeEndTimer)
        parts.noteFadeEndTimer = null
      }
    }

    this.hideNoteBubble = (parts) => {
      this.clearNoteTimers(parts)
      parts.noteBubble.style.display = "none"
      parts.noteBubble.style.opacity = "1"
      parts.noteBubble.style.transform = "translateY(0px)"
      parts.noteBubble.style.filter = "blur(0px)"
      parts.noteBubble.style.transition = "none"
      parts.noteBubble.textContent = ""
      parts.noteMode = "clear"
      parts.noteUpdatedAtMs = 0
      parts.noteText = ""
      parts.pointerRow.style.display = "flex"
    }

    this.showTypingBubble = (parts, text, updatedAtMs) => {
      this.clearNoteTimers(parts)
      parts.noteMode = "typing"
      parts.noteUpdatedAtMs = updatedAtMs
      parts.noteText = text
      parts.pointerRow.style.display = "none"
      parts.noteBubble.style.display = "inline-block"
      parts.noteBubble.style.transition = "none"
      parts.noteBubble.textContent = text
      parts.noteBubble.style.opacity = "1"
      parts.noteBubble.style.transform = "translateY(0px)"
      parts.noteBubble.style.filter = "blur(0px)"
    }

    this.showFinalBubble = (parts, text, updatedAtMs) => {
      const sameFinalState =
        parts.noteMode === "final" && parts.noteUpdatedAtMs === updatedAtMs && parts.noteText === text

      if (sameFinalState) {
        return
      }

      this.clearNoteTimers(parts)
      parts.noteMode = "final"
      parts.noteUpdatedAtMs = updatedAtMs
      parts.noteText = text
      parts.pointerRow.style.display = "none"
      parts.noteBubble.style.display = "inline-block"
      parts.noteBubble.textContent = text
      parts.noteBubble.style.transition = "none"
      parts.noteBubble.style.opacity = "1"
      parts.noteBubble.style.transform = "translateY(0px)"

      parts.noteFadeStartTimer = window.setTimeout(() => {
        parts.noteFadeStartTimer = null

        if (parts.noteMode !== "final" || parts.noteUpdatedAtMs !== updatedAtMs) {
          return
        }

        parts.noteBubble.style.transition =
          "opacity 300ms cubic-bezier(0.2, 0.85, 0.28, 1), transform 300ms cubic-bezier(0.2, 0.85, 0.28, 1), filter 300ms ease"

        window.requestAnimationFrame(() => {
          if (parts.noteMode !== "final" || parts.noteUpdatedAtMs !== updatedAtMs) {
            return
          }

          parts.noteBubble.style.opacity = "0"
          parts.noteBubble.style.transform = "translateY(18px) scale(0.97)"
          parts.noteBubble.style.filter = "blur(1px)"
        })
      }, NOTE_FADE_DELAY_MS)

      parts.noteFadeEndTimer = window.setTimeout(() => {
        parts.noteFadeEndTimer = null

        if (parts.noteMode === "final" && parts.noteUpdatedAtMs === updatedAtMs) {
          this.hideNoteBubble(parts)
        }
      }, NOTE_FADE_DELAY_MS + NOTE_FADE_DURATION_MS + 20)
    }

    this.onToggleClick = (event) => {
      event.preventDefault()
      this.remoteVisible = !this.remoteVisible
      this.syncToggleUi()

      if (!this.remoteVisible) {
        this.clearAllRemoteCursors()
      }
    }

    this.handleEvent("presence_state", ({ presences, me }) => {
      if (!this.remoteVisible) {
        this.clearAllRemoteCursors()
        return
      }

      const nextIds = new Set()

      Object.entries(presences || {}).forEach(([sessionId, presence]) => {
        if (sessionId === me) {
          return
        }

        const meta = readMeta(presence)
        if (!meta || !meta.cursor) {
          return
        }

        const x = Number(meta.cursor.x)
        const y = Number(meta.cursor.y)
        if (!Number.isFinite(x) || !Number.isFinite(y)) {
          return
        }

        nextIds.add(sessionId)

        let parts = this.cursorNodes.get(sessionId)
        if (!parts) {
          parts = buildCursorNode(sessionId)
          this.cursorNodes.set(sessionId, parts)
          this.el.appendChild(parts.container)
        }

        const color = normalizeColor(meta.color)
        const name = normalizeName(meta.display_name)

        parts.path.setAttribute("fill", color)
        parts.nameLabel.style.background = color
        parts.nameLabel.textContent = name
        parts.noteBubble.style.background = color
        parts.noteBubble.style.color = "#ffffff"
        parts.noteBubble.style.border = "1px solid rgba(255,255,255,0.55)"

        const clampedX = Math.max(0, Math.min(x, this.el.clientWidth || x))
        const clampedY = Math.max(0, Math.min(y, this.el.clientHeight || y))
        parts.container.style.left = `${Math.round(clampedX)}px`
        parts.container.style.top = `${Math.round(clampedY)}px`

        const text = normalizeNoteText(meta.cursor_note_text)
        const mode = normalizeMode(meta.cursor_note_mode)
        const safeUpdatedAt = normalizeTimestamp(meta.cursor_note_updated_at_ms) || Date.now()

        if (text === "" || mode === "clear") {
          this.hideNoteBubble(parts)
          return
        }

        if (mode === "typing") {
          this.showTypingBubble(parts, text, safeUpdatedAt)
        } else {
          this.showFinalBubble(parts, text, safeUpdatedAt)
        }
      })

      this.cursorNodes.forEach((parts, sessionId) => {
        if (nextIds.has(sessionId)) {
          return
        }

        this.clearNoteTimers(parts)
        parts.container.remove()
        this.cursorNodes.delete(sessionId)
      })
    })

    if (this.toggleButton) {
      this.toggleButton.addEventListener("click", this.onToggleClick)
    }

    this.syncToggleUi()
  },

  destroyed() {
    if (this.toggleButton && this.onToggleClick) {
      this.toggleButton.removeEventListener("click", this.onToggleClick)
    }

    if (this.cursorNodes) {
      this.clearAllRemoteCursors()
    }
  },
}

export default RemoteCursors
