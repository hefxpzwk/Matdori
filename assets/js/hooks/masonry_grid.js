const MasonryGrid = {
  mounted() {
    this.rafId = null
    this.onResize = () => this.scheduleLayout()

    this.resizeObserver = new ResizeObserver(() => {
      this.scheduleLayout()
    })

    this.resizeObserver.observe(this.el)
    window.addEventListener("resize", this.onResize)

    this.observeItems()
    this.scheduleLayout()
  },

  updated() {
    this.observeItems()
    this.scheduleLayout()
  },

  destroyed() {
    window.removeEventListener("resize", this.onResize)

    if (this.resizeObserver) {
      this.resizeObserver.disconnect()
    }

    if (this.rafId) {
      window.cancelAnimationFrame(this.rafId)
    }
  },

  observeItems() {
    const cards = this.el.querySelectorAll(".x-media-card")

    cards.forEach((card) => {
      if (card.dataset.masonryObserved === "true") {
        return
      }

      card.dataset.masonryObserved = "true"
      this.resizeObserver.observe(card)

      const media = card.querySelectorAll("img, iframe")
      media.forEach((node) => {
        node.addEventListener("load", () => this.scheduleLayout(), { once: true })
      })
    })
  },

  scheduleLayout() {
    if (this.rafId) {
      window.cancelAnimationFrame(this.rafId)
    }

    this.rafId = window.requestAnimationFrame(() => this.layout())
  },

  layout() {
    const style = window.getComputedStyle(this.el)
    const autoRows = Number.parseFloat(style.getPropertyValue("grid-auto-rows"))
    const rowGapRaw = Number.parseFloat(style.getPropertyValue("row-gap"))
    const rowGap = Number.isFinite(rowGapRaw) ? rowGapRaw : 0

    if (!Number.isFinite(autoRows) || autoRows <= 0) {
      return
    }

    const cards = this.el.querySelectorAll(".x-media-card")

    cards.forEach((card) => {
      card.style.gridRowEnd = "auto"
    })

    cards.forEach((card) => {
      const height = card.getBoundingClientRect().height
      const span = Math.max(1, Math.ceil((height + rowGap) / (autoRows + rowGap)))
      card.style.gridRowEnd = `span ${span}`
    })
  },
}

export default MasonryGrid
