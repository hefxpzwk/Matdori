const DRAFT_PUSH_INTERVAL_MS = 60
const CURSOR_PUSH_INTERVAL_MS = 70
const MAX_COMMENT_LENGTH = 240
const COMMENT_PANEL_GAP_PX = 12
const COMMENT_PANEL_PADDING_PX = 8
const HORIZONTAL_OVERFLOW_EPSILON_PX = 12

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

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

function normalizeComment(value) {
  if (typeof value !== "string") {
    return ""
  }

  return value.trim().slice(0, MAX_COMMENT_LENGTH)
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

function fallbackHighlightId(left, top, width, height) {
  const key = `${left.toFixed(4)}:${top.toFixed(4)}:${width.toFixed(4)}:${height.toFixed(4)}`
  let hash = 0

  for (let index = 0; index < key.length; index += 1) {
    hash = (hash * 31 + key.charCodeAt(index)) >>> 0
  }

  return `hl-${hash.toString(16).padStart(8, "0")}`
}

function createLocalHighlightId() {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return `hl-${crypto.randomUUID()}`
  }

  return `hl-${Date.now()}-${Math.floor(Math.random() * 1_000_000)}`
}

function normalizeZone(zone, options = {}) {
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

  const idRaw = typeof zone.id === "string" ? zone.id.trim().slice(0, 80) : ""
  const id =
    idRaw === ""
      ? fallbackHighlightId(normalizedLeft, normalizedTop, safeWidth, safeHeight)
      : idRaw

  return {
    left: Number(normalizedLeft.toFixed(4)),
    top: Number(normalizedTop.toFixed(4)),
    width: Number(safeWidth.toFixed(4)),
    height: Number(safeHeight.toFixed(4)),
    id,
    comment: normalizeComment(zone.comment),
    draft: options.draft === true,
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
    left: zone.left * rect.width,
    top: zone.top * rect.height,
    width: zone.width * rect.width,
    height: zone.height * rect.height,
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

function createHighlightNode(color, isMine, isSelected) {
  const style = highlightStyle(color, isMine)
  const el = document.createElement("div")
  el.className = "absolute rounded-md transition-opacity"
  el.style.pointerEvents = "auto"
  el.style.cursor = "pointer"
  el.style.border = `${isMine ? 2 : 1}px solid ${style.border}`
  el.style.background = style.background
  el.style.boxShadow = style.shadow

  if (isSelected) {
    el.style.outline = `2px solid ${style.border}`
    el.style.outlineOffset = "2px"
  }

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

function buildStateKey(highlightsBySession, draftsBySession, selectedHighlight) {
  const keys = []

  Array.from(highlightsBySession.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .forEach(([sessionId, payload]) => {
      const zoneKey = payload.zones
        .map((zone) => `${zone.id},${zone.left},${zone.top},${zone.width},${zone.height},${zone.comment}`)
        .join(";")

      keys.push(`h|${sessionId}|${payload.color}|${payload.name}|${zoneKey}`)
    })

  Array.from(draftsBySession.entries())
    .sort(([a], [b]) => a.localeCompare(b))
    .forEach(([sessionId, payload]) => {
      const zone = payload.zone
      keys.push(`d|${sessionId}|${payload.color}|${zone.left},${zone.top},${zone.width},${zone.height}`)
    })

  if (selectedHighlight) {
    keys.push(`s|${selectedHighlight.sessionId}|${selectedHighlight.highlightId}`)
  }

  return keys.join("||")
}

const EmbedHighlightOverlay = {
  mounted() {
    this.readonly = this.el.dataset.readonly === "true"

    if (this.readonly) {
      return
    }

    this.stage = this.el.closest(this.el.dataset.stageSelector || "#room-embed-stage")
    this.stageViewport = this.stage ? this.stage.closest("#room-embed-stage") : null
    this.cursorStage = this.el.closest("#room-collab-stage") || this.stage
    this.toggleButton = document.querySelector(this.el.dataset.toggleSelector || "")
    this.clearButton = document.querySelector(this.el.dataset.clearSelector || "")
    this.countLabel = document.querySelector(this.el.dataset.countSelector || "")

    if (!this.stage || !this.toggleButton || !this.clearButton || !this.countLabel) {
      return
    }

    this.commentPanel = document.querySelector(this.el.dataset.commentPanelSelector || "")
    this.commentMeta = document.querySelector(this.el.dataset.commentMetaSelector || "")
    this.commentReadonly = document.querySelector(this.el.dataset.commentReadonlySelector || "")
    this.commentEditor = document.querySelector(this.el.dataset.commentEditorSelector || "")
    this.commentInput = document.querySelector(this.el.dataset.commentInputSelector || "")
    this.commentSaveButton = document.querySelector(this.el.dataset.commentSaveSelector || "")
    this.commentCloseButton = document.querySelector(this.el.dataset.commentCloseSelector || "")
    this.commentPointer = document.querySelector(this.el.dataset.commentPointerSelector || "")

    this.mySessionId = this.el.dataset.sessionId || ""
    this.myColor = normalizeColor(this.el.dataset.userColor, "#3b82f6")

    this.highlightsBySession = new Map()
    this.draftsBySession = new Map()
    this.highlightNodes = new Map()
    this.draftNodes = new Map()
    this.selectedHighlight = null
    this.stateKey = ""
    this.lastPanelKey = ""

    this.enabled = false
    this.dragging = false
    this.dragPointerId = null
    this.dragStart = null
    this.currentDraftZone = null

    this.lastDraftPushAtMs = 0
    this.lastCursorPushAtMs = 0
    this.pendingDraftZone = undefined
    this.draftPushTimer = null
    this.stageResizeObserver = null

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

    this.getHighlightEntry = (sessionId, highlightId) => {
      const payload = this.highlightsBySession.get(sessionId)
      if (!payload) {
        return null
      }

      const zone = payload.zones.find((item) => item.id === highlightId)
      if (!zone) {
        return null
      }

      return {
        sessionId,
        payload,
        zone,
        isMine: sessionId === this.mySessionId,
      }
    }

    this.currentSelectionEntry = () => {
      if (!this.selectedHighlight) {
        return null
      }

      return this.getHighlightEntry(this.selectedHighlight.sessionId, this.selectedHighlight.highlightId)
    }

    this.clearSelection = () => {
      this.selectedHighlight = null
      this.lastPanelKey = ""
      this.syncStateAndRender()
    }

    this.setSelection = (sessionId, highlightId) => {
      this.selectedHighlight = { sessionId, highlightId }
      this.syncStateAndRender()
    }

    this.positionCommentPanel = (entry) => {
      if (!this.commentPanel) {
        return
      }

      const overlayRect = this.el.getBoundingClientRect()
      const zonePixels = normalizeToPixels(overlayRect, entry.zone)
      const panelWidth = this.commentPanel.offsetWidth || 288
      const panelHeight = this.commentPanel.offsetHeight || 180

      const zoneCenterY = zonePixels.top + zonePixels.height / 2
      const rightSideLeft = zonePixels.left + zonePixels.width + COMMENT_PANEL_GAP_PX
      const canPlaceRight = rightSideLeft + panelWidth + COMMENT_PANEL_PADDING_PX <= overlayRect.width

      let left = canPlaceRight
        ? rightSideLeft
        : zonePixels.left - panelWidth - COMMENT_PANEL_GAP_PX

      left = clamp(left, COMMENT_PANEL_PADDING_PX, Math.max(COMMENT_PANEL_PADDING_PX, overlayRect.width - panelWidth - COMMENT_PANEL_PADDING_PX))

      let top = zoneCenterY - panelHeight / 2
      top = clamp(top, COMMENT_PANEL_PADDING_PX, Math.max(COMMENT_PANEL_PADDING_PX, overlayRect.height - panelHeight - COMMENT_PANEL_PADDING_PX))

      this.commentPanel.style.left = `${Math.round(left)}px`
      this.commentPanel.style.top = `${Math.round(top)}px`

      if (!this.commentPointer) {
        return
      }

      const pointerTop = clamp(zoneCenterY - top - 6, 10, Math.max(10, panelHeight - 16))

      this.commentPointer.style.top = `${Math.round(pointerTop)}px`
      this.commentPointer.style.left = canPlaceRight ? "-6px" : ""
      this.commentPointer.style.right = canPlaceRight ? "" : "-6px"
    }

    this.updateCommentPanel = () => {
      if (!this.commentPanel) {
        return
      }

      const entry = this.currentSelectionEntry()

      if (!entry) {
        this.commentPanel.classList.add("hidden")
        this.commentPanel.style.left = ""
        this.commentPanel.style.top = ""
        if (this.commentInput) {
          this.commentInput.value = ""
        }
        this.lastPanelKey = ""
        return
      }

      const panelKey = `${entry.sessionId}|${entry.zone.id}|${entry.zone.comment}`
      this.commentPanel.classList.remove("hidden")

      if (this.commentMeta) {
        this.commentMeta.textContent = `${entry.payload.name}님의 하이라이트`
      }

      if (this.commentReadonly) {
        this.commentReadonly.textContent =
          entry.zone.comment === "" ? "아직 댓글이 없습니다." : entry.zone.comment
      }

      if (this.commentEditor) {
        this.commentEditor.classList.toggle("hidden", !entry.isMine)
      }

      if (this.commentInput && entry.isMine && panelKey !== this.lastPanelKey) {
        this.commentInput.value = entry.zone.comment
      }

      if (this.commentInput) {
        this.commentInput.readOnly = !entry.isMine
      }

      if (this.commentSaveButton) {
        this.commentSaveButton.disabled = !entry.isMine
      }

      this.positionCommentPanel(entry)

      this.lastPanelKey = panelKey
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
          const isSelected =
            this.selectedHighlight &&
            this.selectedHighlight.sessionId === sessionId &&
            this.selectedHighlight.highlightId === zone.id

          const node = createHighlightNode(payload.color, isMine, Boolean(isSelected))
          const px = normalizeToPixels(rect, zone)
          node.style.left = `${px.left}px`
          node.style.top = `${px.top}px`
          node.style.width = `${px.width}px`
          node.style.height = `${px.height}px`
          node.dataset.overlayHighlightNode = "true"
          node.dataset.sessionId = sessionId
          node.dataset.highlightId = zone.id
          node.addEventListener("click", this.onHighlightNodeClick)
          this.el.appendChild(node)
          nodes.push(node)
        })

        this.highlightNodes.set(sessionId, nodes)
      })

      this.updateCount()
      this.updateCommentPanel()
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
      this.stateKey = buildStateKey(this.highlightsBySession, this.draftsBySession, this.selectedHighlight)
    }

    this.syncStateAndRender = () => {
      const nextKey = buildStateKey(this.highlightsBySession, this.draftsBySession, this.selectedHighlight)

      if (nextKey === this.stateKey) {
        this.updateCount()
        this.updateCommentPanel()
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
      const current = this.highlightsBySession.get(this.mySessionId)
      const displayName = current ? current.name : "나"

      if (normalized.length === 0) {
        this.highlightsBySession.delete(this.mySessionId)
      } else {
        this.highlightsBySession.set(this.mySessionId, {
          color: this.myColor,
          name: displayName,
          zones: normalized,
        })
      }

      const selectedEntry = this.currentSelectionEntry()
      if (!selectedEntry) {
        this.selectedHighlight = null
      }

      this.syncStateAndRender()

      if (options.push !== false) {
        this.pushMyHighlights()
      }
    }

    this.updateMyHighlightComment = (highlightId, comment) => {
      if (!this.mySessionId) {
        return
      }

      const mine = this.highlightsBySession.get(this.mySessionId)
      if (!mine) {
        return
      }

      const normalizedComment = normalizeComment(comment)
      const updatedZones = mine.zones.map((zone) =>
        zone.id === highlightId ? { ...zone, comment: normalizedComment } : zone
      )

      this.setMyHighlights(updatedZones)
      this.setSelection(this.mySessionId, highlightId)
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

    this.setLocalDraftZone = (zone, options = {}) => {
      if (options.push !== false) {
        this.scheduleDraftPush(zone, options.immediate === true)
      }
    }

    this.applyOverlayHighlightsState = ({ highlights }) => {
      const nextHighlightsBySession = new Map()

      ;(Array.isArray(highlights) ? highlights : []).forEach((zone) => {
        if (!zone || typeof zone !== "object") {
          return
        }

        const sessionIdRaw = typeof zone.session_id === "string" ? zone.session_id.trim() : ""
        if (sessionIdRaw === "") {
          return
        }

        const normalized = normalizeZone(zone)
        if (!normalized) {
          return
        }

        const color = normalizeColor(zone.color, sessionIdRaw === this.mySessionId ? this.myColor : "#64748b")
        const name = normalizeName(zone.display_name)

        if (sessionIdRaw === this.mySessionId) {
          this.myColor = color
        }

        const existing = nextHighlightsBySession.get(sessionIdRaw)
        if (!existing) {
          nextHighlightsBySession.set(sessionIdRaw, { color, name, zones: [normalized] })
          return
        }

        if (existing.zones.length < 40) {
          existing.zones.push(normalized)
        }
      })

      this.highlightsBySession = nextHighlightsBySession
      this.updateDraftNodeStyle()

      if (!this.currentSelectionEntry()) {
        this.selectedHighlight = null
      }

      this.syncStateAndRender()
    }

    this.applyPresenceHighlights = ({ presences, me }) => {
      if (typeof me === "string" && me !== "") {
        this.mySessionId = me
      }

      const nextDraftsBySession = new Map()

      Object.entries(presences || {}).forEach(([sessionId, presence]) => {
        const meta = readMeta(presence)
        if (!meta) {
          return
        }

        const color = normalizeColor(meta.color, sessionId === this.mySessionId ? this.myColor : "#64748b")
        const draft = normalizeZone(meta.overlay_highlight_draft, { draft: true })

        if (draft) {
          nextDraftsBySession.set(sessionId, { color, zone: draft })
        }

        if (sessionId === this.mySessionId) {
          this.myColor = color
          this.updateDraftNodeStyle()
        }
      })

      this.draftsBySession = nextDraftsBySession
      this.syncStateAndRender()
    }

    this.handleEvent("overlay_highlights_state", this.applyOverlayHighlightsState)
    this.handleEvent("presence_state", this.applyPresenceHighlights)

    this.beginDraft = (x, y) => {
      this.dragStart = { x, y }
      this.dragging = true
      this.currentDraftZone = null
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
        this.currentDraftZone = null
        this.setLocalDraftZone(null, { push: true, immediate: false })
        return
      }

      const zone = normalizeZone(
        {
          left: left / rect.width,
          top: top / rect.height,
          width: width / rect.width,
          height: height / rect.height,
        },
        { draft: true }
      )

      this.currentDraftZone = zone
      this.setLocalDraftZone(zone, { push: true, immediate: false })
    }

    this.cancelDraft = (options = {}) => {
      this.dragging = false
      this.dragPointerId = null
      this.dragStart = null
      this.currentDraftZone = null
      this.draftNode.classList.add("hidden")
      this.draftNode.style.width = "0px"
      this.draftNode.style.height = "0px"

      if (options.push !== false) {
        this.setLocalDraftZone(null, { push: true, immediate: options.immediate !== false })
      }
    }

    this.commitDraft = () => {
      if (!this.dragging || !this.dragStart) {
        this.cancelDraft({ push: true, immediate: true })
        return
      }

      const rect = this.el.getBoundingClientRect()
      const draftZone = this.currentDraftZone

      this.cancelDraft({ push: false })

      if (!draftZone || rect.width <= 0 || rect.height <= 0) {
        this.setLocalDraftZone(null, { push: true, immediate: true })
        return
      }

      const pixelWidth = draftZone.width * rect.width
      const pixelHeight = draftZone.height * rect.height

      if (pixelWidth < 8 || pixelHeight < 8) {
        this.setLocalDraftZone(null, { push: true, immediate: true })
        return
      }

      const normalized = normalizeZone({
        left: draftZone.left,
        top: draftZone.top,
        width: draftZone.width,
        height: draftZone.height,
        id: createLocalHighlightId(),
        comment: "",
      })

      if (!normalized) {
        this.setLocalDraftZone(null, { push: true, immediate: true })
        return
      }

      const myZones = [...this.myHighlights(), normalized]
      this.setMyHighlights(myZones)
      this.setSelection(this.mySessionId, normalized.id)
      this.setLocalDraftZone(null, { push: true, immediate: true })
    }

    this.clearHighlights = () => {
      this.cancelDraft({ push: true, immediate: true })
      this.clearSelection()
      this.setMyHighlights([])
    }

    this.relativePoint = (event) => {
      const rect = this.el.getBoundingClientRect()
      return {
        x: clamp(event.clientX - rect.left, 0, rect.width),
        y: clamp(event.clientY - rect.top, 0, rect.height),
      }
    }

    this.onHighlightNodeClick = (event) => {
      event.preventDefault()
      event.stopPropagation()

      const node = event.currentTarget
      const sessionId = node.dataset.sessionId || ""
      const highlightId = node.dataset.highlightId || ""

      if (sessionId !== "" && highlightId !== "") {
        this.setSelection(sessionId, highlightId)
      }
    }

    this.onCommentSaveClick = (event) => {
      event.preventDefault()
      const entry = this.currentSelectionEntry()

      if (!entry || !entry.isMine || !this.commentInput) {
        return
      }

      this.updateMyHighlightComment(entry.zone.id, this.commentInput.value)
    }

    this.onCommentCloseClick = (event) => {
      event.preventDefault()
      this.clearSelection()
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

      if (event.target instanceof HTMLElement && event.target.closest("[data-overlay-highlight-node='true']")) {
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
      this.onStageResize()
    }

    this.alignStageToCenter = (force = false) => {
      if (!this.stageViewport || !this.stage) {
        return
      }

      const viewportRect = this.stageViewport.getBoundingClientRect()
      const contentRect = this.stage.getBoundingClientRect()
      const hiddenOnLeft = contentRect.left < viewportRect.left - HORIZONTAL_OVERFLOW_EPSILON_PX
      const hiddenOnRight = contentRect.right > viewportRect.right + HORIZONTAL_OVERFLOW_EPSILON_PX
      const hasOverflow = hiddenOnLeft || hiddenOnRight

      this.stageViewport.style.overflowX = hasOverflow ? "auto" : "hidden"

      if (!hasOverflow) {
        this.stageViewport.scrollLeft = 0
        return
      }

      const scrollLeft = this.stageViewport.scrollLeft
      const maxScrollLeft = Math.max(0, this.stageViewport.scrollWidth - this.stageViewport.clientWidth)
      const outOfRange = scrollLeft < 0 || scrollLeft > maxScrollLeft

      if (force || outOfRange) {
        this.stageViewport.scrollLeft = 0
      }
    }

    this.onStageResize = () => {
      this.renderOverlayState()
      this.syncStateKey()
      this.alignStageToCenter()
    }

    this.onKeyDown = (event) => {
      if (event.key !== "Escape") {
        return
      }

      if (this.selectedHighlight) {
        this.clearSelection()
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

    if (this.commentSaveButton) {
      this.commentSaveButton.addEventListener("click", this.onCommentSaveClick)
    }

    if (this.commentCloseButton) {
      this.commentCloseButton.addEventListener("click", this.onCommentCloseClick)
    }

    if (typeof ResizeObserver === "function") {
      this.stageResizeObserver = new ResizeObserver(() => {
        this.onStageResize()
      })
      this.stageResizeObserver.observe(this.stageViewport)

      if (this.stage !== this.stageViewport) {
        this.stageResizeObserver.observe(this.stage)
      }
    }

    this.alignStageToCenter(true)

    window.addEventListener("resize", this.onWindowResize)
    window.addEventListener("keydown", this.onKeyDown)

    this.updateDraftNodeStyle()
    this.syncModeUi()
    this.syncStateKey()
    this.updateCount()
    this.updateCommentPanel()
  },

  destroyed() {
    if (this.toggleButton && this.onToggleClick) {
      this.toggleButton.removeEventListener("click", this.onToggleClick)
    }

    if (this.clearButton && this.onClearClick) {
      this.clearButton.removeEventListener("click", this.onClearClick)
    }

    if (this.commentSaveButton && this.onCommentSaveClick) {
      this.commentSaveButton.removeEventListener("click", this.onCommentSaveClick)
    }

    if (this.commentCloseButton && this.onCommentCloseClick) {
      this.commentCloseButton.removeEventListener("click", this.onCommentCloseClick)
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

    if (this.stageResizeObserver) {
      this.stageResizeObserver.disconnect()
      this.stageResizeObserver = null
    }

    if (this.stageViewport) {
      this.stageViewport.scrollLeft = 0
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
