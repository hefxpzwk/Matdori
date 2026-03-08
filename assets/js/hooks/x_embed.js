const SCRIPT_ID = "x-widgets-js"
const SCRIPT_SRC = "https://platform.twitter.com/widgets.js"
const SCRIPT_TIMEOUT_MS = 10_000

function extractTweetId(url) {
  if (typeof url !== "string") {
    return null
  }

  const matched = url.match(/\/status\/(\d+)/)
  return matched ? matched[1] : null
}

function fallbackMarkup(url) {
  return `
    <blockquote class="twitter-tweet">
      <a href="${url}">X 게시글</a>
    </blockquote>
  `
}

function withTimeout(promise, timeoutMs) {
  return new Promise((resolve, reject) => {
    const timer = window.setTimeout(() => {
      reject(new Error(`X widgets load timed out after ${timeoutMs}ms`))
    }, timeoutMs)

    promise
      .then((value) => {
        window.clearTimeout(timer)
        resolve(value)
      })
      .catch((error) => {
        window.clearTimeout(timer)
        reject(error)
      })
  })
}

function ensureWidgetsScript() {
  return new Promise((resolve, reject) => {
    if (window.twttr && window.twttr.widgets) {
      resolve(window.twttr)
      return
    }

    const existing = document.getElementById(SCRIPT_ID)
    if (existing) {
      existing.addEventListener("load", () => resolve(window.twttr), { once: true })
      existing.addEventListener("error", () => reject(new Error("X widgets script failed to load")), {
        once: true,
      })
      return
    }

    const script = document.createElement("script")
    script.id = SCRIPT_ID
    script.async = true
    script.src = SCRIPT_SRC
    script.addEventListener("load", () => resolve(window.twttr), { once: true })
    script.addEventListener("error", () => reject(new Error("X widgets script failed to load")), {
      once: true,
    })
    document.head.appendChild(script)
  })
}

const XEmbed = {
  async mounted() {
    this.lastRenderKey = null
    this.isRendering = false
    await this.renderEmbedIfNeeded()
  },

  async updated() {
    await this.renderEmbedIfNeeded()
  },

  async renderEmbedIfNeeded() {
    const tweetUrl = this.el.dataset.tweetUrl || ""
    const tweetId = extractTweetId(tweetUrl)
    const renderKey = `${tweetId || "invalid"}|${tweetUrl}`

    if (this.isRendering || this.lastRenderKey === renderKey) {
      return
    }

    this.isRendering = true
    this.lastRenderKey = renderKey

    try {
      await this.renderEmbed(tweetUrl, tweetId)
    } finally {
      this.isRendering = false
    }
  },

  async renderEmbed(tweetUrl, tweetId) {

    if (!tweetId) {
      this.el.innerHTML = fallbackMarkup(tweetUrl || "")
      this.el.dataset.embedStatus = "invalid-url"
      return
    }

    this.el.innerHTML = fallbackMarkup(tweetUrl)
    this.el.dataset.embedStatus = "loading"

    try {
      await withTimeout(ensureWidgetsScript(), SCRIPT_TIMEOUT_MS)

      if (window.twttr && window.twttr.widgets) {
        this.el.innerHTML = ""
        await window.twttr.widgets.createTweet(tweetId, this.el, {
          dnt: true,
          align: "center",
          theme: "dark",
        })
        this.el.dataset.embedStatus = "ready"
      } else {
        this.el.dataset.embedStatus = "widgets-unavailable"
        console.error("[XEmbed] widgets API unavailable after script load")
      }
    } catch (error) {
      this.el.dataset.embedStatus = "failed"
      console.error("[XEmbed] failed to render embed", error)
    }
  },
}

export default XEmbed
