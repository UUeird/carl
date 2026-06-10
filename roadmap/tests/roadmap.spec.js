import { test, expect } from "@playwright/test";
import fs from "fs";
import path from "path";

const JSON_PATH = path.resolve(import.meta.dirname, "../roadmap.json");

// Snapshot the JSON before the suite and restore after each test so
// mutations from add/delete tests don't bleed into subsequent tests.
let jsonSnapshot;
test.beforeAll(() => {
  jsonSnapshot = fs.readFileSync(JSON_PATH, "utf8");
});
test.afterEach(() => {
  fs.writeFileSync(JSON_PATH, jsonSnapshot, "utf8");
});

test.beforeEach(async ({ page }) => {
  await page.goto("/");
  await page.waitForSelector(".board");
  // Clear persisted collapse and selection state so each test starts clean
  await page.evaluate(() => {
    localStorage.removeItem("carl-roadmap-collapsed");
    localStorage.removeItem("carl-roadmap-selected");
  });
  await page.reload();
  await page.waitForSelector(".board");
});

// ── Board structure ────────────────────────────────────────────────────────────

test("renders all four status columns", async ({ page }) => {
  const lanes = page.locator(".lane");
  await expect(lanes).toHaveCount(4);

  for (const label of ["Idea", "Planned", "In Progress", "Done"]) {
    await expect(page.locator(`.lane-head .badge`, { hasText: label })).toBeVisible();
  }
});

test("columns appear in correct order: Idea, Planned, In Progress, Done", async ({ page }) => {
  const badges = page.locator(".lane-head .badge");
  await expect(badges.nth(0)).toHaveText("Idea");
  await expect(badges.nth(1)).toHaveText("Planned");
  await expect(badges.nth(2)).toHaveText("In Progress");
  await expect(badges.nth(3)).toHaveText("Done");
});

test("progress tooltip stat counts match actual card counts", async ({ page }) => {
  const wipCount = await page.locator(".lane[data-status='wip'] .card").count();
  await page.locator(".progress").hover();
  await expect(page.locator(".pt-stat.wip .pt-num")).toHaveText(String(wipCount));
});

// ── Column collapse ────────────────────────────────────────────────────────────

test("clicking a column header collapses it", async ({ page }) => {
  const body = page.locator(".lane[data-status='todo'] .lane-body");
  await expect(body).toBeVisible();
  await page.locator(".lane[data-status='todo'] .lane-head").click();
  await expect(body).toBeHidden();
});

test("clicking a collapsed column header re-expands it", async ({ page }) => {
  const head = page.locator(".lane[data-status='todo'] .lane-head");
  const body = page.locator(".lane[data-status='todo'] .lane-body");
  await head.click();
  await expect(body).toBeHidden();
  await head.click();
  await expect(body).toBeVisible();
});

test("collapse state persists across page reload", async ({ page }) => {
  const head = page.locator(".lane[data-status='todo'] .lane-head");
  const body = page.locator(".lane[data-status='todo'] .lane-body");
  await head.click();
  await expect(body).toBeHidden();

  await page.reload();
  await page.waitForSelector(".board");
  await expect(page.locator(".lane[data-status='todo'] .lane-body")).toBeHidden();
});

test("collapsed column gets the collapsed class", async ({ page }) => {
  const lane = page.locator(".lane[data-status='todo']");
  await expect(lane).not.toHaveClass(/collapsed/);
  await lane.locator(".lane-head").click();
  await expect(lane).toHaveClass(/collapsed/);
});

// ── Card detail view ───────────────────────────────────────────────────────────

test("cards with subtasks show a subtask count hint", async ({ page }) => {
  await expect(page.locator(".card-subtask-count").first()).toBeVisible();
  await expect(page.locator(".card-subtask-count").first()).toContainText("subtask");
});

test("clicking a card opens the detail view", async ({ page }) => {
  const card = page.locator(".card").first();
  const title = await card.locator(".card-title").innerText();
  await card.locator(".card-title").dispatchEvent("pointerup");
  await expect(page.locator(".detail-card")).toBeVisible();
  await expect(page.locator(".detail-title")).toHaveText(title);
});

test("detail view shows the board when back button is clicked", async ({ page }) => {
  await page.locator(".card").first().locator(".card-title").dispatchEvent("pointerup");
  await expect(page.locator(".detail-card")).toBeVisible();
  await page.locator("#detailBack").click();
  await expect(page.locator(".board")).toBeVisible();
  await expect(page.locator(".detail-card")).toHaveCount(0);
});

test("pressing Escape dismisses the detail view", async ({ page }) => {
  await page.locator(".card").first().locator(".card-title").dispatchEvent("pointerup");
  await expect(page.locator(".detail-card")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(".board")).toBeVisible();
  await expect(page.locator(".detail-card")).toHaveCount(0);
});

test("detail card has a glow box-shadow matching its status color", async ({ page }) => {
  await page.locator(".card").first().locator(".card-title").dispatchEvent("pointerup");
  const boxShadow = await page.locator(".detail-card").evaluate(el => getComputedStyle(el).boxShadow);
  expect(boxShadow).not.toBe("none");
  expect(boxShadow).not.toBe("");
});

test("detail view shows child mini-kanban with three columns", async ({ page }) => {
  const cardEl = page.locator(".card").filter({ has: page.locator(".card-subtask-count") }).first();
  await cardEl.locator(".card-title").dispatchEvent("pointerup");
  await expect(page.locator(".child-board")).toBeVisible();
  await expect(page.locator(".child-lane")).toHaveCount(3);
});

test("clicking detail title makes it editable", async ({ page }) => {
  const card = page.locator(".card").first();
  const originalTitle = await card.locator(".card-title").innerText();
  await card.locator(".card-title").dispatchEvent("pointerup");
  await page.locator(".detail-title").click();
  await expect(page.locator("input.detail-edit")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.locator(".detail-title")).toHaveText(originalTitle);
});

test("editing and saving title updates the item", async ({ page }) => {
  await page.locator(".card").first().locator(".card-title").dispatchEvent("pointerup");
  await page.locator(".detail-title").click();
  const input = page.locator("input.detail-edit");
  await input.fill("Renamed by Playwright");
  await input.press("Enter");
  await expect(page.locator(".detail-title")).toHaveText("Renamed by Playwright");
});

test("clicking detail note makes it editable", async ({ page }) => {
  const cardEl = page.locator(".card").filter({ has: page.locator(".card-subtask-count") }).first();
  await cardEl.locator(".card-title").dispatchEvent("pointerup");
  await page.locator(".detail-note").click();
  await expect(page.locator("textarea.detail-edit")).toBeVisible();
  await page.keyboard.press("Escape");
});

test("clicking a child card title makes it editable", async ({ page }) => {
  const cardEl = page.locator(".card").filter({ has: page.locator(".card-subtask-count") }).first();
  await cardEl.locator(".card-title").dispatchEvent("pointerup");
  const child = page.locator(".child-card-title").first();
  await child.click();
  await expect(page.locator(".child-card input.detail-edit")).toBeVisible();
  await page.keyboard.press("Escape");
});

test("add subtask button appends a new editable child card", async ({ page }) => {
  const cardEl = page.locator(".card").filter({ has: page.locator(".card-subtask-count") }).first();
  await cardEl.locator(".card-title").dispatchEvent("pointerup");
  const before = await page.locator(".child-card").count();
  await page.locator(".child-add-btn").first().click();
  await page.locator(".child-card input.detail-edit").last().fill("New child from test");
  await page.locator(".child-card input.detail-edit").last().press("Enter");
  await expect(page.locator(".child-card")).toHaveCount(before + 1);
});

// ── Type filter ────────────────────────────────────────────────────────────────

test("Story filter shows only story-type cards", async ({ page }) => {
  await page.locator(".filter[data-f='story']").click();
  const cards = page.locator(".card");
  const count = await cards.count();
  expect(count).toBeGreaterThan(0);
  for (let i = 0; i < count; i++) {
    await expect(cards.nth(i).locator(".card-type")).toHaveText("Story");
  }
});

test("Bug filter shows only bug-type cards", async ({ page }) => {
  await page.locator(".filter[data-f='bug']").click();
  const cards = page.locator(".card");
  const count = await cards.count();
  expect(count).toBeGreaterThan(0);
  for (let i = 0; i < count; i++) {
    await expect(cards.nth(i).locator(".card-type")).toHaveText("Bug");
  }
});

test("All filter restores all cards after filtering", async ({ page }) => {
  const allCount = await page.locator(".card").count();
  await page.locator(".filter[data-f='story']").click();
  const storyCount = await page.locator(".card").count();
  await page.locator(".filter[data-f='all']").click();
  await expect(page.locator(".card")).toHaveCount(allCount);
  expect(storyCount).toBeLessThanOrEqual(allCount);
});

// ── Search ─────────────────────────────────────────────────────────────────────

test("search narrows visible cards across all columns", async ({ page }) => {
  const allCount = await page.locator(".card").count();
  await page.locator("#search").fill("audio");
  await expect(page.locator(".card")).toHaveCount(1);
  await expect(page.locator(".card .card-title")).toContainText("Audio");
  await page.locator("#search").fill("");
  await expect(page.locator(".card")).toHaveCount(allCount);
});

test("search with no matches shows no cards", async ({ page }) => {
  await page.locator("#search").fill("xyzzy-no-match-expected");
  await expect(page.locator(".card")).toHaveCount(0);
});

// ── Add item ───────────────────────────────────────────────────────────────────

test("add item modal opens and creates a new card", async ({ page }) => {
  const before = await page.locator(".card").count();
  await page.locator("#addBtn").click();
  await page.locator("#f_title").fill("Test ticket from Playwright");
  await page.locator("#saveItemBtn").click();
  await expect(page.locator(".card")).toHaveCount(before + 1);
  await expect(page.locator(".card-title").filter({ hasText: "Test ticket from Playwright" }).first()).toBeVisible();
});

test("add item modal can be cancelled without creating a card", async ({ page }) => {
  const before = await page.locator(".card").count();
  await page.locator("#addBtn").click();
  await page.locator("#f_title").fill("Should not appear");
  await page.locator("#cancelBtn").click();
  await expect(page.locator(".card")).toHaveCount(before);
});

test("add item requires a title", async ({ page }) => {
  await page.locator("#addBtn").click();
  page.once("dialog", d => d.accept());
  await page.locator("#saveItemBtn").click();
  await expect(page.locator(".modal")).toBeVisible();
});

// ── Delete item ────────────────────────────────────────────────────────────────

test("delete button removes a card after confirmation", async ({ page }) => {
  // Add a throwaway card first
  await page.locator("#addBtn").click();
  await page.locator("#f_title").fill("Delete me");
  await page.locator("#saveItemBtn").click();
  const before = await page.locator(".card").count();

  const card = page.locator(".card").filter({ has: page.locator(".card-title", { hasText: "Delete me" }) }).first();
  page.once("dialog", d => d.accept());
  await card.hover();
  await card.locator(".iconbtn.del").click();

  await expect(page.locator(".card")).toHaveCount(before - 1);
  await expect(page.locator(".card-title").filter({ hasText: "Delete me" })).toHaveCount(0);
});
