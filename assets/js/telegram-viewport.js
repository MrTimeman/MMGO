// Telegram fullscreen (Bot API 8.0) draws the Mini App under the status bar and
// under Telegram's own floating close/menu controls. The browser's
// env(safe-area-inset-*) does not describe that overlap, so publish Telegram's
// reported insets as CSS custom properties and let the stylesheets take
// whichever value is larger.
const SIDES = ["top", "right", "bottom", "left"]
const VIEWPORT_EVENTS = [
  "safeAreaChanged",
  "contentSafeAreaChanged",
  "viewportChanged",
  "fullscreenChanged"
]

function readInset(inset) {
  const measured = {top: 0, right: 0, bottom: 0, left: 0}
  if (!inset || typeof inset !== "object") return measured

  for (const side of SIDES) {
    const value = Number(inset[side])
    if (Number.isFinite(value) && value > 0) measured[side] = value
  }

  return measured
}

export function publishTelegramInsets(webApp) {
  if (!webApp || !document.documentElement) return

  const root = document.documentElement
  // Telegram reports the content inset relative to the device safe area, so the
  // usable offset is the sum of the two.
  const safeArea = readInset(webApp.safeAreaInset)
  const contentSafeArea = readInset(webApp.contentSafeAreaInset)

  for (const side of SIDES) {
    root.style.setProperty(`--tg-inset-${side}`, `${safeArea[side] + contentSafeArea[side]}px`)
  }

  root.classList.toggle("tg-fullscreen", webApp.isFullscreen === true)
}

export function watchTelegramViewport(webApp) {
  if (!webApp) return

  publishTelegramInsets(webApp)

  if (typeof webApp.onEvent !== "function") return

  for (const event of VIEWPORT_EVENTS) {
    try {
      webApp.onEvent(event, () => publishTelegramInsets(webApp))
    } catch (_error) {
      // An older Telegram client rejects unknown events. The static fallback
      // values remain correct, so the interface must still render.
    }
  }
}
