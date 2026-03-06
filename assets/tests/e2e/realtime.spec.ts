import { expect, test } from "@playwright/test"

test("two participants can open latest room", async ({ browser }) => {
  const contextA = await browser.newContext()
  const contextB = await browser.newContext()
  const pageA = await contextA.newPage()
  const pageB = await contextB.newPage()

  await Promise.all([pageA.goto("/rooms/latest"), pageB.goto("/rooms/latest")])

  await expect(pageA.locator("#tweet-link")).toBeVisible()
  await expect(pageB.locator("#tweet-link")).toBeVisible()
  await expect(pageA.locator("#tweet-embed")).toBeVisible()
  await expect(pageB.locator("#tweet-embed")).toBeVisible()

  await contextA.close()
  await contextB.close()
})

test("embed failure fallback keeps room usable", async ({ browser }) => {
  const context = await browser.newContext()
  await context.route("**/platform.twitter.com/**", (route) => route.abort())
  await context.route("**/syndication.twitter.com/**", (route) => route.abort())

  const page = await context.newPage()
  await page.goto("/rooms/latest")

  await expect(page.locator("#tweet-link")).toBeVisible()
  await expect(page.locator("#tweet-embed")).toBeVisible()
  await expect(page.locator("text=임베드가 로드되지 않으면 위의 원문 링크를 이용해 주세요.")).toBeVisible()

  await context.close()
})
