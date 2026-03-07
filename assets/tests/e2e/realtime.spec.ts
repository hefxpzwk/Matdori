import { expect, test } from "@playwright/test"

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
