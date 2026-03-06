function createCursorNode(sessionId, meta) {
  const node = document.createElement("div")
  node.id = `cursor-${sessionId}`
  node.className = "absolute z-30 pointer-events-none"

  const color = /^#[0-9a-fA-F]{6}$/.test(meta.color || "") ? meta.color : "#3b82f6"
  const name = meta.display_name || "Guest"

  const wrap = document.createElement("div")
  wrap.style.transform = "translate(-2px, -2px)"

  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
  svg.setAttribute("width", "14")
  svg.setAttribute("height", "18")
  svg.setAttribute("viewBox", "0 0 14 18")
  svg.setAttribute("fill", "none")

  const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
  path.setAttribute("d", "M1 1L12 12L7 13.5L5 17L1 1Z")
  path.setAttribute("fill", color)
  path.setAttribute("stroke", "white")
  path.setAttribute("stroke-width", "1")
  svg.appendChild(path)

  const label = document.createElement("span")
  label.style.background = color
  label.style.color = "white"
  label.style.fontSize = "11px"
  label.style.lineHeight = "1"
  label.style.padding = "3px 6px"
  label.style.borderRadius = "999px"
  label.style.display = "inline-block"
  label.style.transform = "translateY(-2px)"
  label.textContent = name

  wrap.appendChild(svg)
  wrap.appendChild(label)
  node.appendChild(wrap)

  return node
}

const RemoteCursors = {
  mounted() {
    this.handleEvent("presence_state", ({ presences, me }) => {
      const existing = Array.from(this.el.querySelectorAll("[id^='cursor-']"))
      existing.forEach((node) => node.remove())

      Object.entries(presences || {}).forEach(([sessionId, presence]) => {
        if (sessionId === me) {
          return
        }

        const meta = presence.metas && presence.metas[0]
        if (!meta || !meta.cursor) {
          return
        }

        const x = Number(meta.cursor.x)
        const y = Number(meta.cursor.y)
        if (!Number.isFinite(x) || !Number.isFinite(y)) {
          return
        }

        const clampedX = Math.max(0, Math.min(x, this.el.clientWidth || x))
        const clampedY = Math.max(0, Math.min(y, this.el.clientHeight || y))

        const cursor = createCursorNode(sessionId, meta)
        cursor.style.left = `${Math.round(clampedX)}px`
        cursor.style.top = `${Math.round(clampedY)}px`
        this.el.appendChild(cursor)
      })
    })
  }
}

export default RemoteCursors
