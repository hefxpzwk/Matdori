function graphemeIndexAt(text, codeUnitIndex) {
  const segmenter = new Intl.Segmenter("und", { granularity: "grapheme" })
  let index = 0

  for (const segment of segmenter.segment(text)) {
    if (segment.index >= codeUnitIndex) {
      return index
    }

    index += 1
  }

  return index
}

function codeUnitOffsetWithin(container, targetNode, targetOffset) {
  const range = document.createRange()
  range.setStart(container, 0)
  range.setEnd(targetNode, targetOffset)
  return range.toString().length
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max)
}

function isTextInputTarget(target) {
  if (!(target instanceof HTMLElement)) {
    return false
  }

  if (target.isContentEditable) {
    return true
  }

  return Boolean(target.closest("input, textarea, select, [contenteditable='true']"))
}

function normalizeHexColor(value, fallback = "#3b82f6") {
  return /^#[0-9a-fA-F]{6}$/.test(value || "") ? value : fallback
}

const SnapshotCanvas = {
  mounted() {
    this.readonly = this.el.dataset.readonly === "true"

    if (this.readonly) {
      return
    }

    this.snapshotText = this.el.querySelector("#snapshot-text")
    this.lastPush = 0
    this.lastPointer = { x: 0, y: 0 }
    this.noteInput = null
    this.noteFinalizeTimer = null
    this.noteClearTimer = null
    this.noteLastPushAt = 0
    this.cursorColor = normalizeHexColor(this.el.dataset.cursorColor)

    this.positionNoteInput = () => {
      if (!this.noteInput) {
        return
      }

      const inputWidth = this.noteInput.offsetWidth || 220
      const inputHeight = this.noteInput.offsetHeight || 34
      const stageWidth = this.el.clientWidth || inputWidth
      const stageHeight = this.el.clientHeight || inputHeight

      const left = clamp(this.lastPointer.x + 14, 0, Math.max(0, stageWidth - inputWidth - 4))
      const top = clamp(this.lastPointer.y + 10, 0, Math.max(0, stageHeight - inputHeight - 4))

      this.noteInput.style.left = `${Math.round(left)}px`
      this.noteInput.style.top = `${Math.round(top)}px`
    }

    this.pushCursorNote = (mode, text) => {
      const now = Date.now()
      if (mode === "typing" && now - this.noteLastPushAt < 80) {
        return
      }

      this.noteLastPushAt = now

      this.pushEvent("cursor_note", {
        mode,
        text,
        x: Math.round(this.lastPointer.x),
        y: Math.round(this.lastPointer.y),
      })
    }

    this.clearNoteFinalizeTimer = () => {
      if (this.noteFinalizeTimer) {
        window.clearTimeout(this.noteFinalizeTimer)
        this.noteFinalizeTimer = null
      }
    }

    this.clearNoteClearTimer = () => {
      if (this.noteClearTimer) {
        window.clearTimeout(this.noteClearTimer)
        this.noteClearTimer = null
      }
    }

    this.closeNoteInput = ({ animateDown = false, onClosed = null } = {}) => {
      this.clearNoteFinalizeTimer()

      if (!this.noteInput) {
        return
      }

      const input = this.noteInput
      this.noteInput = null

      const finishClose = () => {
        input.remove()

        if (typeof onClosed === "function") {
          onClosed()
        }
      }

      if (animateDown) {
        input.style.pointerEvents = "none"
        input.style.transition =
          "transform 300ms cubic-bezier(0.2, 0.85, 0.28, 1), opacity 300ms ease, filter 300ms ease"
        input.style.transform = "translateY(18px) scale(0.97)"
        input.style.opacity = "0"
        input.style.filter = "blur(1px)"

        let closed = false

        const cleanup = () => {
          if (closed) {
            return
          }

          closed = true
          input.removeEventListener("transitionend", onTransitionEnd)
          finishClose()
        }

        const onTransitionEnd = () => {
          cleanup()
        }

        input.addEventListener("transitionend", onTransitionEnd, { once: true })
        window.setTimeout(cleanup, 340)

        return
      }

      finishClose()
    }

    this.finalizeNoteInput = (origin = "blur") => {
      if (!this.noteInput) {
        return
      }

      const text = this.noteInput.value.trim()
      if (text === "") {
        this.clearNoteClearTimer()
        this.pushCursorNote("clear", "")
      } else {
        this.clearNoteClearTimer()
        this.pushCursorNote("final", text)

        this.noteClearTimer = window.setTimeout(() => {
          this.noteClearTimer = null
          this.pushCursorNote("clear", "")
        }, 420)
      }

      this.closeNoteInput({
        animateDown: origin == "enter",
        onClosed:
          origin === "enter"
            ? () => {
                if (this.el.isConnected) {
                  this.openNoteInput()
                }
              }
            : null,
      })
    }

    this.scheduleNoteFinalize = () => {
      this.clearNoteFinalizeTimer()

      this.noteFinalizeTimer = window.setTimeout(() => {
        this.finalizeNoteInput()
      }, 1400)
    }

    this.openNoteInput = () => {
      if (this.noteInput) {
        this.noteInput.focus()
        return
      }

      const input = document.createElement("input")
      input.id = "cursor-note-input"
      input.type = "text"
      input.maxLength = 80
      input.placeholder = "메시지 입력 후 Enter"
      input.className =
        "absolute z-40 w-60 rounded-full px-3 py-1.5 text-sm shadow-sm outline-none"
      input.style.transform = "translateY(6px) scale(0.985)"
      input.style.opacity = "0"
      input.style.background = this.cursorColor
      input.style.color = "#ffffff"
      input.style.border = "1px solid rgba(255,255,255,0.6)"
      input.style.boxShadow = "0 8px 24px rgba(15, 23, 42, 0.24)"
      input.style.backdropFilter = "blur(4px)"
      input.style.transition = "transform 280ms cubic-bezier(0.22, 1, 0.36, 1), opacity 280ms ease"

      input.addEventListener("input", () => {
        const value = input.value.slice(0, 80)
        if (value !== input.value) {
          input.value = value
        }

        if (value.trim() === "") {
          this.pushCursorNote("clear", "")
          this.clearNoteClearTimer()
          this.clearNoteFinalizeTimer()
        } else {
          this.clearNoteClearTimer()
          this.pushCursorNote("typing", value)
          this.scheduleNoteFinalize()
        }
      })

      input.addEventListener("keydown", (event) => {
        if (event.key === "Enter") {
          event.preventDefault()
          this.finalizeNoteInput("enter")
          return
        }

        if (event.key === "Escape") {
          event.preventDefault()
          this.pushCursorNote("clear", "")
          this.clearNoteClearTimer()
          this.closeNoteInput()
        }
      })

      input.addEventListener("blur", () => {
        this.finalizeNoteInput("blur")
      })

      this.noteInput = input
      this.el.appendChild(input)
      this.positionNoteInput()
      window.requestAnimationFrame(() => {
        if (!this.noteInput || this.noteInput !== input) {
          return
        }

        input.style.transform = "translateY(0) scale(1)"
        input.style.opacity = "1"
      })
      input.focus()
    }

    this.onMouseMove = (event) => {
      const rect = this.el.getBoundingClientRect()
      const x = Math.max(0, Math.round(event.clientX - rect.left))
      const y = Math.max(0, Math.round(event.clientY - rect.top))
      this.lastPointer = { x, y }
      this.positionNoteInput()

      const now = Date.now()
      if (now - this.lastPush < 50) {
        return
      }

      this.lastPush = now

      this.pushEvent("cursor_move", { x, y })
    }

    this.onKeyDown = (event) => {
      const slashPressed = event.key === "/" || event.code === "Slash"
      if (!slashPressed || event.repeat) {
        return
      }

      if (isTextInputTarget(event.target) || this.noteInput) {
        return
      }

      event.preventDefault()
      this.openNoteInput()
    }

    this.onMouseUp = () => {
      if (!this.snapshotText) {
        return
      }

      const selection = window.getSelection()
      if (!selection || selection.rangeCount === 0 || selection.isCollapsed) {
        return
      }

      const range = selection.getRangeAt(0)
      if (!this.snapshotText.contains(range.startContainer) || !this.snapshotText.contains(range.endContainer)) {
        return
      }

      const text = this.snapshotText.textContent || ""
      const startOffset = codeUnitOffsetWithin(this.snapshotText, range.startContainer, range.startOffset)
      const endOffset = codeUnitOffsetWithin(this.snapshotText, range.endContainer, range.endOffset)

      const rawStartG = graphemeIndexAt(text, startOffset)
      const rawEndG = graphemeIndexAt(text, endOffset)
      const graphemes = Array.from(new Intl.Segmenter("und", { granularity: "grapheme" }).segment(text), (s) => s.segment)

      let startG = rawStartG
      let endG = rawEndG

      while (startG < endG && /^\s$/u.test(graphemes[startG])) {
        startG += 1
      }

      while (endG > startG && /^\s$/u.test(graphemes[endG - 1])) {
        endG -= 1
      }

      const selected = graphemes.slice(startG, endG).join("")
      if (!selected) {
        selection.removeAllRanges()
        return
      }

      const prefixStart = Math.max(0, startG - 16)
      const suffixEnd = Math.min(graphemes.length, endG + 16)

      const quotePrefix = graphemes.slice(prefixStart, startG).join("")
      const quoteSuffix = graphemes.slice(endG, suffixEnd).join("")

      this.pushEvent("create_highlight", {
        quote_exact: selected,
        quote_prefix: quotePrefix,
        quote_suffix: quoteSuffix,
        start_g: startG,
        end_g: endG
      })

      selection.removeAllRanges()
    }

    this.el.addEventListener("mousemove", this.onMouseMove)
    this.el.addEventListener("mouseup", this.onMouseUp)
    window.addEventListener("keydown", this.onKeyDown)
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMouseMove)
    this.el.removeEventListener("mouseup", this.onMouseUp)
    window.removeEventListener("keydown", this.onKeyDown)

    if (this.noteInput) {
      this.noteInput.remove()
      this.noteInput = null
    }

    if (this.noteFinalizeTimer) {
      window.clearTimeout(this.noteFinalizeTimer)
      this.noteFinalizeTimer = null
    }

    if (this.noteClearTimer) {
      window.clearTimeout(this.noteClearTimer)
      this.noteClearTimer = null
    }

  }
}

export default SnapshotCanvas
