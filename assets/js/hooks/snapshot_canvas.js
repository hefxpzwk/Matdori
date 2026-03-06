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

const SnapshotCanvas = {
  mounted() {
    this.snapshotText = this.el.querySelector("#snapshot-text")
    this.lastPush = 0

    this.onMouseMove = (event) => {
      const now = Date.now()
      if (now - this.lastPush < 50) {
        return
      }

      this.lastPush = now
      const rect = this.el.getBoundingClientRect()
      const x = Math.max(0, Math.round(event.clientX - rect.left))
      const y = Math.max(0, Math.round(event.clientY - rect.top))

      this.pushEvent("cursor_move", { x, y })
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
  },

  destroyed() {
    this.el.removeEventListener("mousemove", this.onMouseMove)
    this.el.removeEventListener("mouseup", this.onMouseUp)
  }
}

export default SnapshotCanvas
