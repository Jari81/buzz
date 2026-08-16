import { expect, test, type Page } from "@playwright/test";

import { installMockBridge } from "../helpers/bridge";
import { waitForAnimations } from "../helpers/animations";

const SHOTS = "test-results/sidebar-offcanvas-rail";
const THEME_STORAGE_KEY = "buzz-theme";
const RELAY_URL = "ws://localhost:3000";

const COMMUNITY_A = {
  id: "ws-a",
  name: "Alpha",
  relayUrl: RELAY_URL,
  addedAt: "2026-01-01T00:00:00.000Z",
};
const COMMUNITY_B = {
  id: "ws-b",
  name: "Bravo",
  relayUrl: "ws://localhost:3001",
  addedAt: "2026-01-02T00:00:00.000Z",
};

async function setup(page: Page, theme: string) {
  await page.setViewportSize({ width: 960, height: 540 });
  await page.addInitScript(
    ({ key, value }) => {
      window.localStorage.setItem(key, value);
    },
    { key: THEME_STORAGE_KEY, value: theme },
  );
  await installMockBridge(page, undefined, { skipCommunitySeed: true });
  await page.addInitScript(
    ({ list, active }) => {
      window.localStorage.setItem("buzz-communities", JSON.stringify(list));
      window.localStorage.setItem("buzz-active-community-id", active);
    },
    { list: [COMMUNITY_A, COMMUNITY_B], active: COMMUNITY_A.id },
  );
  await page.goto("/", { waitUntil: "domcontentloaded" });
  await expect(page.getByTestId("community-rail")).toBeVisible();
  await expect(page.getByTestId("app-sidebar")).toBeVisible();
}

/**
 * Regression: the app-sidebar layer is overflow-visible (huddle drawer), so
 * the offcanvas-collapsed sidebar slides out of its container but kept
 * painting over the community rail — opaquely on flat themes, as ghost
 * fragments on the transparent Buzz chrome. The collapsed sidebar must be
 * invisible and non-interactive, leaving the rail clean in every theme.
 */
for (const theme of ["buzz", "buzz-dark", "vesper"]) {
  test(`collapsed sidebar leaves the community rail clean — ${theme}`, async ({
    page,
  }) => {
    await setup(page, theme);
    await waitForAnimations(page);
    await page.screenshot({ path: `${SHOTS}/${theme}-expanded.png` });

    const communityRail = page.getByTestId("community-rail");
    const communityButton = page.getByTestId(
      `community-rail-button-${COMMUNITY_B.id}`,
    );
    const railBoxBeforeCollapse = await communityRail.boundingBox();
    expect(railBoxBeforeCollapse).not.toBeNull();

    await page.locator('[data-sidebar="trigger"]').first().click();

    // Sample every rendered frame while the sidebar crosses the rail. The
    // community list must remain the painted hit target without moving or
    // fading at any point in the transition, while the sidebar content visibly
    // recedes in place before the shell finishes closing.
    const transitionFrames = await communityButton.evaluate(async (button) => {
      const rail = button.closest('[data-testid="community-rail"]');
      const sidebarContent = document.querySelector<HTMLElement>(
        "[data-sidebar-transition-content]",
      );
      if (!(rail instanceof HTMLElement) || !sidebarContent) return [];

      const frames: Array<{
        elapsed: number;
        hitRail: boolean;
        opacity: string;
        sidebarOpacity: number;
        sidebarScale: string;
        sidebarTranslateX: number;
        visibility: string;
        x: number;
        y: number;
      }> = [];
      const startedAt = performance.now();
      while (performance.now() - startedAt < 250) {
        await new Promise<void>((resolve) =>
          requestAnimationFrame(() => resolve()),
        );
        const buttonBox = button.getBoundingClientRect();
        const railBox = rail.getBoundingClientRect();
        const hit = document.elementFromPoint(
          buttonBox.x + buttonBox.width / 2,
          buttonBox.y + buttonBox.height / 2,
        );
        const style = getComputedStyle(rail);
        const sidebarStyle = getComputedStyle(sidebarContent);
        frames.push({
          elapsed: performance.now() - startedAt,
          hitRail: hit === rail || rail.contains(hit),
          opacity: style.opacity,
          sidebarOpacity: Number.parseFloat(sidebarStyle.opacity),
          sidebarScale: sidebarStyle.scale,
          sidebarTranslateX: Number.parseFloat(sidebarStyle.translate),
          visibility: style.visibility,
          x: railBox.x,
          y: railBox.y,
        });
      }
      return frames;
    });
    expect(transitionFrames.length).toBeGreaterThan(1);
    const shell = page.locator(
      '[data-state="collapsed"][data-collapsible="offcanvas"]',
    );
    await expect(shell).toHaveCount(1);
    expect(
      transitionFrames.every(
        (frame) =>
          frame.hitRail &&
          frame.opacity === "1" &&
          frame.visibility === "visible" &&
          frame.x === railBoxBeforeCollapse?.x &&
          frame.y === railBoxBeforeCollapse?.y,
      ),
    ).toBe(true);
    const midTransitionFrames = transitionFrames.filter(
      (frame) =>
        frame.sidebarOpacity > 0 &&
        frame.sidebarOpacity < 1 &&
        frame.sidebarScale !== "none" &&
        frame.sidebarScale !== "0.95" &&
        frame.sidebarTranslateX > 0 &&
        frame.sidebarTranslateX < 24,
    );
    expect(midTransitionFrames.length).toBeGreaterThan(1);
    expect(
      transitionFrames.some(
        (frame) => frame.elapsed >= 100 && frame.sidebarOpacity > 0.05,
      ),
    ).toBe(true);

    // Let the 200ms slide finish; visibility flips at the transition's end.
    await page.waitForTimeout(250);

    // Second direct child = the sliding sidebar container (first is the gap).
    const offscreenSidebar = shell.locator("> div").nth(1);
    await expect(offscreenSidebar).toHaveCSS("visibility", "hidden");
    await expect(offscreenSidebar).toHaveCSS("pointer-events", "none");

    // The community rail stays visible and interactive beneath it.
    await expect(page.getByTestId("community-rail")).toBeVisible();
    await expect(
      page.getByTestId(`community-rail-button-${COMMUNITY_B.id}`),
    ).toBeVisible();
    await waitForAnimations(page);
    await page.screenshot({ path: `${SHOTS}/${theme}-collapsed.png` });
  });
}
