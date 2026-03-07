const DRAFT_PUSH_INTERVAL_MS = 60
const CURSOR_PUSH_INTERVAL_MS = 70

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function normalizeColor(value, fallback = "#3b82f6") {
  return /^#[0-9a-fA-F]{6}$/.test(value || "") ? value : fallback
}

function readMeta(presence) {
  if (!presence || !Array.isArray(presence.metas) || presence.metas.length === 0) {
    return null
  }

  return presence.metas[0]
}

function parseFiniteNumber(value) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeZone(zone) {
  if (!zone || typeof zone !== "object") {
    return null
  }

  const left = parseFiniteNumber(zone.left)
  const top = parseFiniteNumber(zone.top)
  const width = parseFiniteNumber(zone.width)
  const height = parseFiniteNumber(zone.height)

  if (left === null || top === null || width === null || height === null) {
    return null
  }

  const normalizedLeft = clamp(left, 0, 1)
  const normalizedTop = clamp(top, 0, 1)
  const normalizedWidth = clamp(width, 0, 1)
  const normalizedHeight = clamp(height, 0, 1)

  const safeWidth = clamp(normalizedWidth, 0, Math.max(0, 1 - normalizedLeft))
  const safeHeight = clamp(normalizedHeight, 0, Math.max(0, 1 - normalizedTop))

  if (safeWidth <= 0 || safeHeight <= 0) {
    return null
  }

  return {
    left: Number(normalizedLeft.toFixed(4)),
    top: Number(normalizedTop.toFixed(4)),
    width: Number(safeWidth.toFixed(4)),
    height: Number(safeHeight.toFixed(4)),
  }
}

function normalizeZones(zones, limit = 40) {
  if (!Array.isArray(zones)) {
    return []
  }

  const normalized = []

  zones.forEach((zone) => {
    if (normalized.length >= limit) {
      return
    }

    const safe = normalizeZone(zone)
    if (safe) {
      normalized.push(safe)
    }
  })

  return normalized
}

function normalizeToPixels(rect, zone) {
  return {
    left: Math.round(zone.left * rect.width),
    top: Math.round(zone.top * rect.height),
    width: Math.round(zone.width * rect.width),
    height: Math.round(zone.height * rect.height),
  }
}

function hexToRgb(hex) {
  return {
    r: Number.parseInt(hex.slice(1, 3), 16),
    g: Number.parseInt(hex.slice(3, 5), 16),
    b: Number.parseInt(hex.slice(5, 7), 16),
  }
}

function highlightStyle(color, isMine) {
  const { r, g, b } = hexToRgb(color)

  return {
    border: `rgba(${r}, ${g}, ${b}, ${isMine ? 0.95 : 0.75})`,
    background: `rgba(${r}, ${g}, ${b}, ${isMine ? 0.28 : 0.18})`,
    shadow: `0 10px 28px rgba(${r}, ${g}, ${b}, ${isMine ? 0.28 : 0.18})`,
  }
}

function createHighlightNode(color, isMine) {
  const style = highlightStyle(color, isMine)
  const el = document.createElement("div")
  el.className = "absolute rounded-md transition-opacity"
  el.style.pointerEvents = "none"
  el.style.border = `${isMine ? 2 : 1}px solid ${style.border}`
  el.style.background = style.background
  el.style.boxShadow = style.shadow
  return el
}

function createDraftNode(color) {
  const style = highlightStyle(color, false)
  const el = document.createElement("div")
  el.className = "absolute rounded-md"
  el.style.pointerEvents = "none"
  el.style.border = `1px dashed ${style.border}`
  el.style.background = style.background
  el.style.boxShadow = style.shadow
  return el
}

function buildStateKey(highlightsBySession, draftsBySession) {
  const keys = []

  Array.from(highlightsBySession.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .forEach(([sessionId, payload]) => {
      const zoneKey = payload.zones
        .map((zone) => `${zone.left},${zone.top},${zone.width},${zone.height}`)
        .join(";")

      keys.push(`h|${sessionId}|${payload.color}|${zoneKey}`)
    })

  Array.from(draftsBySession.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .forEach(([sessionId, payload]) => {
      const zone = payload.zone
      keys.push(`d|${sessionId}|${payload.color}|${zone.left},${zone.top},${zone.width},${zone.height}`)
    })

  return keys.join("||")
}

const EmbedHighlightOverlay = {
  mounted() {
    this.stage = this.el.closest(this.el.dataset.stageSelector || "#room-embed-stage")
    this.cursorStage = this.el.closest("#room-collab-stage") || this.stage
    this.toggleButton = document.querySelector(this.el.dataset.toggleSelector || "")
    this.clearButton = document.querySelector(this.el.dataset.clearSelector || "")
    this.countLabel = document.querySelector(this.el.dataset.countSelector || "")

    if (!this.stage || !this.toggleButton || !this.clearButton || !this.countLabel) {
      return
    }

    this.mySessionId = this.el.dataset.sessionId || ""
    this.myColor = normalizeColor(this.el.dataset.userColor, "#3b82f6")

    this.highlightsBySession = new Map()
    this.draftsBySession = new Map()
    this.highlightNodes = new Map()
    this.draftNodes = new Map()
    this.localDraftZone = null
    this.stateKey = ""

    this.enabled = false
    this.dragging = false
    this.dragPointerId = null
    this.dragStart = null

    this.lastDraftPushAtMs = 0
    this.lastCursorPushAtMs = 0
    this.pendingDraftZone = undefined
    this.draftPushTimer = null

    this.draftNode = document.createElement("div")
    this.draftNode.className = "absolute hidden rounded-md"
    this.draftNode.style.pointerEvents = "none"
    this.draftNode.style.transition = "none"
    this.el.appendChild(this.draftNode)

    this.updateDraftNodeStyle = () => {
      const style = highlightStyle(this.myColor, true)
      this.draftNode.style.border = `2px dashed ${style.border}`
      this.draftNode.style.background = style.background
      this.draftNode.style.boxShadow = style.shadow
    }

    this.syncModeUi = () => {
      this.el.style.pointerEvents = this.enabled ? "auto" : "none"
      this.el.style.cursor = this.enabled ? "crosshair" : "default"
      this.el.style.touchAction = this.enabled ? "none" : "auto"

      this.toggleButton.classList.toggle("border-amber-400", this.enabled)
      this.toggleButton.classList.toggle("bg-amber-100", this.enabled)
      this.toggleButton.classList.toggle("text-amber-800", this.enabled)
      this.toggleButton.classList.toggle("border-zinc-300", !this.enabled)
      this.toggleButton.classList.toggle("bg-white", !this.enabled)
      this.toggleButton.classList.toggle("text-zinc-700", !this.enabled)
    }

    this.myHighlights = () => {
      if (!this.mySessionId) {
        return []
      }

      const mine = this.highlightsBySession.get(this.mySessionId)
      return mine ? mine.zones : []
    }

    this.updateCount = () => {
      const ownCount = this.myHighlights().length
      const totalCount = Array.from(this.highlightsBySession.values()).reduce(
        (sum, payload) => sum + payload.zones.length,
        0
      )

      this.countLabel.textContent =
        totalCount > ownCount ? `${ownCount}개 선택됨 · 전체 ${totalCount}개` : `${ownCount}개 선택됨`
    }

    this.clearHighlightNodes = () => {
      this.highlightNodes.forEach((nodes) => {
        nodes.forEach((node) => node.remove())
      })

      this.highlightNodes.clear()
    }

    this.clearDraftNodes = () => {
      this.draftNodes.forEach((node) => node.remove())
      this.draftNodes.clear()
    }

    this.renderHighlights = () => {
      const rect = this.el.getBoundingClientRect()
      this.clearHighlightNodes()

      const entries = Array.from(this.highlightsBySession.entries()).sort(([a], [b]) => {
        if (a === this.mySessionId) {
          return 1
        }

        if (b === this.mySessionId) {
          return -1
        }

        return a.localeCompare(b)
      })

      entries.forEach(([sessionId, payload]) => {
        const isMine = sessionId === this.mySessionId
        const nodes = []

        payload.zones.forEach((zone) => {
          const node = createHighlightNode(payload.color, isMine)
          const px = normalizeToPixels(rect, zone)
          node.style.left = `${px.left}px`
          node.style.top = `${px.top}px`
          node.style.width = `${px.width}px`
          node.style.height = `${px.height}px`
          this.el.appendChild(node)
          nodes.push(node)
        })

        this.highlightNodes.set(sessionId, nodes)
      })

      this.updateCount()
    }

    this.renderDrafts = () => {
      const rect = this.el.getBoundingClientRect()
      this.clearDraftNodes()

      Array.from(this.draftsBySession.entries())
        .sort(([a], [b]) => a.localeCompare(b))
        .forEach(([sessionId, payload]) => {
          if (sessionId === this.mySessionId) {
            return
          }

          const node = createDraftNode(payload.color)
          const px = normalizeToPixels(rect, payload.zone)
          node.style.left = `${px.left}px`
          node.style.top = `${px.top}px`
          node.style.width = `${px.width}px`
          node.style.height = `${px.height}px`
          this.el.appendChild(node)
          this.draftNodes.set(sessionId, node)
        })
    }

    this.renderOverlayState = () => {
      this.renderHighlights()
      this.renderDrafts()
    }

    this.syncStateKey = () => {
      this.stateKey = buildStateKey(this.highlightsBySession, this.draftsBySession)
    }

    this.syncStateAndRender = () => {
      const nextKey = buildStateKey(this.highlightsBySession, this.draftsBySession)

      if (nextKey === this.stateKey) {
        this.updateCount()
        return
      }

      this.stateKey = nextKey
      this.renderOverlayState()
    }

    this.pushMyHighlights = () => {
      this.pushEvent("overlay_highlights_sync", {
        highlights: this.myHighlights(),
      })
    }

    this.setMyHighlights = (zones, options = {}) => {
      if (!this.mySessionId) {
        return
      }

      const normalized = normalizeZones(zones)

      if (normalized.length === 0) {
        this.highlightsBySession.delete(this.mySessionId)
      } else {
        this.highlightsBySession.set(this.mySessionId, {
          color: this.myColor,
          zones: normalized,
        })
      }

      this.syncStateAndRender()

      if (options.push !== false) {
        this.pushMyHighlights()
      }
    }

    this.pushDraftNow = (zone) => {
      this.lastDraftPushAtMs = Date.now()
      this.pushEvent("overlay_highlight_draft", { zone })
    }

    this.clearPendingDraftPush = () => {
      if (this.draftPushTimer) {
        window.clearTimeout(this.draftPushTimer)
        this.draftPushTimer = null
      }

      this.pendingDraftZone = undefined
    }

    this.scheduleDraftPush = (zone, immediate = false) => {
      if (immediate) {
        this.clearPendingDraftPush()
        this.pushDraftNow(zone)
        return
      }

      const now = Date.now()
      const elapsed = now - this.lastDraftPushAtMs

      if (!this.draftPushTimer && elapsed >= DRAFT_PUSH_INTERVAL_MS) {
        this.pushDraftNow(zone)
        return
      }

      this.pendingDraftZone = zone

      if (this.draftPushTimer) {
        return
      }

      const wait = Math.max(DRAFT_PUSH_INTERVAL_MS - elapsed, 0)

      this.draftPushTimer = window.setTimeout(() => {
        this.draftPushTimer = null
        const nextZone = this.pendingDraftZone === undefined ? null : this.pendingDraftZone
        this.pendingDraftZone = undefined
        this.pushDraftNow(nextZone)
      }, wait)
    }

    this.setLocalDraftZone = (zone, options = {}) => {
      this.localDraftZone = zone

      if (options.push !== false) {
        this.scheduleDraftPush(zone, options.immediate === true)
      }
    }

    this.applyPresenceHighlights = ({ presences, me }) => {
      if (typeof me === "string" && me !== "") {
        this.mySessionId = me
      }

      const nextHighlightsBySession = new Map()
      const nextDraftsBySession = new Map()

      Object.entries(presences || {}).forEach(([sessionId, presence]) => {
        const meta = readMeta(presence)
        if (!meta) {
          return
        }

        const color = normalizeColor(meta.color, sessionId === this.mySessionId ? this.myColor : "#64748b")
        const zones = normalizeZones(meta.overlay_highlights)

        if (zones.length > 0) {
          nextHighlightsBySession.set(sessionId, { color, zones })
        }

        const draft = normalizeZone(meta.overlay_highlight_draft)
        if (draft) {
          nextDraftsBySession.set(sessionId, { color, zone: draft })
        }

        if (sessionId === this.mySessionId) {
          this.myColor = color
          this.updateDraftNodeStyle()
        }
      })

      if (this.mySessionId && !nextHighlightsBySession.has(this.mySessionId)) {
        const optimisticMine = this.highlightsBySession.get(this.mySessionId)
        if (optimisticMine && optimisticMine.zones.length > 0) {
          nextHighlightsBySession.set(this.mySessionId, optimisticMine)
        }
      }

      this.highlightsBySession = nextHighlightsBySession
      this.draftsBySession = nextDraftsBySession
      this.syncStateAndRender()
    }

    this.handleEvent("presence_state", this.applyPresenceHighlights)

    this.beginDraft = (x, y) => {
      this.dragStart = { x, y }
      this.dragging = true
      this.localDraftZone = null
      this.el.appendChild(this.draftNode)
      this.draftNode.classList.remove("hidden")
      this.draftNode.style.left = `${Math.round(x)}px`
      this.draftNode.style.top = `${Math.round(y)}px`
      this.draftNode.style.width = "0px"
      this.draftNode.style.height = "0px"
    }

    this.updateDraft = (x, y) => {
      if (!this.dragging || !this.dragStart) {
        return
      }

      const left = Math.min(this.dragStart.x, x)
      const top = Math.min(this.dragStart.y, y)
      const width = Math.abs(x - this.dragStart.x)
      const height = Math.abs(y - this.dragStart.y)

      this.draftNode.style.left = `${Math.round(left)}px`
      this.draftNode.style.top = `${Math.round(top)}px`
      this.draftNode.style.width = `${Math.round(width)}px`
      this.draftNode.style.height = `${Math.round(height)}px`

      const rect = this.el.getBoundingClientRect()
      if (rect.width <= 0 || rect.height <= 0 || width < 1 || height < 1) {
        this.setLocalDraftZone(null, { push: true, immediate: false })
        return
      }

      const zone = normalizeZone({
        left: left / rect.width,
        top: top / rect.height,
        width: width / rect.width,
        height: height / rect.height,
      })

      this.setLocalDraftZone(zone, { push: true, immediate: false })
    }

    this.cancelDraft = (options = {}) => {
      this.dragging = false
      this.dragPointerId = null
      this.dragStart = null
      this.draftNode.classList.add("hidden")
      this.draftNode.style.width = "0px"
      this.draftNode.style.height = "0px"

      if (options.push !== false) {
        this.setLocalDraftZone(null, { push: true, immediate: options.immediate !== false })
      } else {
        this.localDraftZone = null
      }
    }

    this.commitDraft = () => {
      if (!this.dragging || !this.dragStart) {
        this.cancelDraft({ push: true, immediate: true })
        return
      }

      const rect = this.el.getBoundingClientRect()
      const left = Number.parseFloat(this.draftNode.style.left || "0")
      const top = Number.parseFloat(this.draftNode.style.top || "0")
      const width = Number.parseFloat(this.draftNode.style.width || "0")
      const height = Number.parseFloat(this.draftNode.style.height || "0")

      this.cancelDraft({ push: false })

      if (width < 8 || height < 8 || rect.width <= 0 || rect.height <= 0) {
        this.setLocalDraftZone(null, { push: true, immediate: true })
        return
      }

      const normalized = normalizeZone({
        left: left / rect.width,
        top: top / rect.height,
        width: width / rect.width,
        height: height / rect.height,
      })

      if (!normalized) {
        this.setLocalDraftZone(null, { push: true, immediate: true })
        return
      }

      const myZones = [...this.myHighlights(), normalized]
      this.setMyHighlights(myZones)
      this.setLocalDraftZone(null, { push: true, immediate: true })
    }

    this.clearHighlights = () => {
      this.cancelDraft({ push: true, immediate: true })
      this.setMyHighlights([])
    }

    this.relativePoint = (event) => {
      const rect = this.el.getBoundingClientRect()
      return {
        x: clamp(event.clientX - rect.left, 0, rect.width),
        y: clamp(event.clientY - rect.top, 0, rect.height),
      }
    }

    this.pushCursorMoveFromEvent = (event, options = {}) => {
      if (!this.cursorStage) {
        return
      }

      const force = options.force === true
      const now = Date.now()

      if (!force && now - this.lastCursorPushAtMs < CURSOR_PUSH_INTERVAL_MS) {
        return
      }

      const rect = this.cursorStage.getBoundingClientRect()
      const x = clamp(event.clientX - rect.left, 0, rect.width)
      const y = clamp(event.clientY - rect.top, 0, rect.height)

      this.lastCursorPushAtMs = now
      this.pushEvent("cursor_move", {
        x: Math.round(x),
        y: Math.round(y),
      })
    }

    this.onToggleClick = (event) => {
      event.preventDefault()
      this.enabled = !this.enabled

      if (!this.enabled) {
        this.cancelDraft({ push: true, immediate: true })
      }

      this.syncModeUi()
    }

    this.onClearClick = (event) => {
      event.preventDefault()
      this.clearHighlights()
    }

    this.onPointerDown = (event) => {
      if (!this.enabled || event.button !== 0) {
        return
      }

      event.preventDefault()
      this.pushCursorMoveFromEvent(event, { force: true })
      const point = this.relativePoint(event)
      this.dragPointerId = event.pointerId
      this.beginDraft(point.x, point.y)
      this.el.setPointerCapture(event.pointerId)
    }

    this.onPointerMove = (event) => {
      if (!this.enabled) {
        return
      }

      this.pushCursorMoveFromEvent(event)

      if (!this.dragging || this.dragPointerId !== event.pointerId) {
        return
      }

      event.preventDefault()
      const point = this.relativePoint(event)
      this.updateDraft(point.x, point.y)
    }

    this.releasePointerCaptureIfNeeded = (pointerId) => {
      if (typeof pointerId !== "number") {
        return
      }

      if (typeof this.el.hasPointerCapture === "function" && this.el.hasPointerCapture(pointerId)) {
        this.el.releasePointerCapture(pointerId)
      }
    }

    this.onPointerUp = (event) => {
      if (!this.dragging || this.dragPointerId !== event.pointerId) {
        return
      }

      event.preventDefault()
      this.pushCursorMoveFromEvent(event, { force: true })
      this.commitDraft()
      this.releasePointerCaptureIfNeeded(event.pointerId)
    }

    this.onPointerCancel = (event) => {
      if (!this.dragging || this.dragPointerId !== event.pointerId) {
        return
      }

      event.preventDefault()
      this.pushCursorMoveFromEvent(event, { force: true })
      this.cancelDraft({ push: true, immediate: true })
      this.releasePointerCaptureIfNeeded(event.pointerId)
    }

    this.onWindowResize = () => {
      this.renderOverlayState()
      this.syncStateKey()
    }

    this.onKeyDown = (event) => {
      if (event.key !== "Escape") {
        return
      }

      this.cancelDraft({ push: true, immediate: true })
    }

    this.toggleButton.addEventListener("click", this.onToggleClick)
    this.clearButton.addEventListener("click", this.onClearClick)
    this.el.addEventListener("pointerdown", this.onPointerDown)
    this.el.addEventListener("pointermove", this.onPointerMove)
    this.el.addEventListener("pointerup", this.onPointerUp)
    this.el.addEventListener("pointercancel", this.onPointerCancel)
    window.addEventListener("resize", this.onWindowResize)
    window.addEventListener("keydown", this.onKeyDown)

    this.updateDraftNodeStyle()
    this.syncModeUi()
    this.syncStateKey()
    this.updateCount()
  },

  destroyed() {
    if (this.toggleButton && this.onToggleClick) {
      this.toggleButton.removeEventListener("click", this.onToggleClick)
    }

    if (this.clearButton && this.onClearClick) {
      this.clearButton.removeEventListener("click", this.onClearClick)
    }

    if (this.el && this.onPointerDown) {
      this.el.removeEventListener("pointerdown", this.onPointerDown)
      this.el.removeEventListener("pointermove", this.onPointerMove)
      this.el.removeEventListener("pointerup", this.onPointerUp)
      this.el.removeEventListener("pointercancel", this.onPointerCancel)
    }

    if (this.onWindowResize) {
      window.removeEventListener("resize", this.onWindowResize)
    }

    if (this.onKeyDown) {
      window.removeEventListener("keydown", this.onKeyDown)
    }

    if (this.clearHighlightNodes) {
      this.clearHighlightNodes()
    }

    if (this.clearDraftNodes) {
      this.clearDraftNodes()
    }

    if (this.clearPendingDraftPush) {
      this.clearPendingDraftPush()
    }
  },
}

export default EmbedHighlightOverlay
