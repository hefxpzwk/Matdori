import { expect, test } from "@playwright/test"

async function embedSelectorFor(page: import("@playwright/test").Page) {
  if ((await page.locator("#tweet-embed").count()) > 0) {
    return "#tweet-embed"
  }

  if ((await page.locator("#youtube-embed").count()) > 0) {
    return "#youtube-embed"
  }

  return "#link-preview-card"
}

test("two participants can open shared room", async ({ browser }) => {
  const contextA = await browser.newContext()
  const contextB = await browser.newContext()
  const pageA = await contextA.newPage()
  const pageB = await contextB.newPage()

  await Promise.all([pageA.goto("/rooms"), pageB.goto("/rooms")])

  await Promise.all([
    pageA.locator('[id^="room-item-"]').first().click(),
    pageB.locator('[id^="room-item-"]').first().click()
  ])

  await expect(pageA.locator("#tweet-link")).toBeVisible()
  await expect(pageB.locator("#tweet-link")).toBeVisible()
  await expect(pageA.locator("#room-embed-status")).toBeVisible()
  await expect(pageB.locator("#room-embed-status")).toBeVisible()
  await expect(pageA.locator("#room-presence-count")).toContainText("현재 접속 2명")
  await expect(pageB.locator("#room-presence-count")).toContainText("현재 접속 2명")
  await expect(pageA.locator("#room-view-count")).toContainText("조회수 2")
  await expect(pageB.locator("#room-view-count")).toContainText("조회수 2")

  await expect(pageA.locator("#like-count")).toHaveText("0")
  await expect(pageB.locator("#like-count")).toHaveText("0")
  await expect(pageA.locator("#dislike-count")).toHaveText("0")
  await expect(pageB.locator("#dislike-count")).toHaveText("0")

  const embedSelectorA = await embedSelectorFor(pageA)
  const embedSelectorB = await embedSelectorFor(pageB)

  await pageA.locator(embedSelectorA).evaluate((node) => {
    ;(window as { __embedNode?: Element }).__embedNode = node
  })

  await pageB.locator(embedSelectorB).evaluate((node) => {
    ;(window as { __embedNode?: Element }).__embedNode = node
  })

  await pageA.locator("#like-button").click()
  await expect(pageA.locator("#like-count")).toHaveText("1")
  await expect(pageB.locator("#like-count")).toHaveText("1")

  expect(
    await pageA.locator(embedSelectorA).evaluate((node) => {
      return (window as { __embedNode?: Element }).__embedNode === node
    })
  ).toBe(true)

  expect(
    await pageB.locator(embedSelectorB).evaluate((node) => {
      return (window as { __embedNode?: Element }).__embedNode === node
    })
  ).toBe(true)

  await pageB.locator("#dislike-button").click()
  await expect(pageA.locator("#dislike-count")).toHaveText("1")
  await expect(pageB.locator("#dislike-count")).toHaveText("1")

  await pageA.reload()
  await expect(pageA.locator("#tweet-link")).toBeVisible()

  expect(
    await pageB.locator(embedSelectorB).evaluate((node) => {
      return (window as { __embedNode?: Element }).__embedNode === node
    })
  ).toBe(true)

  const presenceDotStyles = await pageA
    .locator("#room-presence-list [id^='room-presence-user-'] > span:first-child")
    .evaluateAll((nodes) => nodes.map((node) => node.getAttribute("style") ?? ""))
  expect(new Set(presenceDotStyles).size).toBeGreaterThan(1)

  const stage = pageA.locator("#room-collab-stage")
  await expect(stage).toBeVisible()

  const box = await stage.boundingBox()
  if (!box) {
    throw new Error("Missing room collaboration stage bounds")
  }

  await pageA.mouse.move(box.x + box.width * 0.55, box.y + box.height * 0.45)
  await expect(pageB.locator("#room-remote-cursors [id^='cursor-']")).toBeVisible()

  await pageA.keyboard.press("/")
  const noteInput = pageA.locator("#cursor-note-input")
  await expect(noteInput).toBeVisible()
  await noteInput.fill("실시간 메모 테스트")
  await noteInput.press("Enter")

  const remoteNote = pageB
    .locator("#room-remote-cursors .cursor-note-bubble")
    .filter({ hasText: "실시간 메모 테스트" })
    .first()

  await expect(remoteNote).toBeVisible()
  await expect(remoteNote).toBeHidden({ timeout: 9000 })

  await contextA.close()
  await contextB.close()
})

test("embed failure fallback keeps room usable", async ({ browser }) => {
  const context = await browser.newContext()
  await context.route("**/platform.twitter.com/**", (route) => route.abort())
  await context.route("**/syndication.twitter.com/**", (route) => route.abort())

  const page = await context.newPage()
  await page.goto("/rooms")
  await page.locator('[id^="room-item-"]').first().click()

  await expect(page.locator("#tweet-link")).toBeVisible()
  await expect(page.locator("#room-embed-status")).toBeVisible()

  await context.close()
})
