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

// Some clients report both insets as zero even while fullscreen is active, which
// leaves the first row of the interface underneath the status bar and Telegram's
// own controls. When that happens, reserve enough room for both rather than
// trusting the report: a status bar plus Telegram's control row.
const FULLSCREEN_MIN_TOP = 92

// `isFullscreen` is not trustworthy on every client: some leave it false while
// the app is plainly drawn under the status bar, which is exactly the case the
// floor above exists for. So the request itself is the signal, and Telegram
// tells us when it refuses.
let fullscreenRequested = false
let fullscreenDenied = false

export function markFullscreenRequested() {
  fullscreenRequested = true
  fullscreenDenied = false
}

function fullscreenActive(webApp) {
  if (webApp.isFullscreen === true) return true
  return fullscreenRequested && !fullscreenDenied
}

function readInset(inset) {
  const measured = {top: 0, right: 0, bottom: 0, left: 0}
  if (!inset || typeof inset !== "object") return measured

  for (const side of SIDES) {
    const value = Number(inset[side])
    if (Number.isFinite(value) && value > 0) measured[side] = value
  }

  return measured
}

// Recent Telegram clients also publish their own CSS variables. They are a
// second opinion on the same numbers and are present on some builds where the
// JS properties are not.
function readTelegramVariable(name) {
  const raw = getComputedStyle(document.documentElement).getPropertyValue(name)
  const value = Number.parseFloat(raw)
  return Number.isFinite(value) && value > 0 ? value : 0
}

function reportedTop(webApp) {
  const safeArea = readInset(webApp.safeAreaInset)
  const contentSafeArea = readInset(webApp.contentSafeAreaInset)

  return Math.max(
    safeArea.top + contentSafeArea.top,
    readTelegramVariable("--tg-safe-area-inset-top") +
      readTelegramVariable("--tg-content-safe-area-inset-top")
  )
}

export function publishTelegramInsets(webApp) {
  if (!webApp || !document.documentElement) return

  const root = document.documentElement
  // Telegram reports the content inset relative to the device safe area, so the
  // usable offset is the sum of the two.
  const safeArea = readInset(webApp.safeAreaInset)
  const contentSafeArea = readInset(webApp.contentSafeAreaInset)
  const fullscreen = fullscreenActive(webApp)

  const top = fullscreen
    ? Math.max(reportedTop(webApp), FULLSCREEN_MIN_TOP)
    : reportedTop(webApp)

  for (const side of SIDES) {
    const value = side === "top" ? top : safeArea[side] + contentSafeArea[side]
    root.style.setProperty(`--tg-inset-${side}`, `${value}px`)
  }

  root.classList.toggle("tg-fullscreen", fullscreen)
}

// A screen pinned with `position: fixed; inset: 0` does not shrink when the
// soft keyboard opens: the layout viewport stays the full height of the device
// while only the visual viewport shrinks, so whatever sits at the bottom of
// that screen — the line you are typing into — ends up behind the keyboard.
// Publishing the difference lets those screens reserve room for it.
export function publishKeyboardInset() {
  const viewport = window.visualViewport
  if (!viewport || !document.documentElement) return

  const hidden = Math.max(0, Math.round(window.innerHeight - viewport.height - viewport.offsetTop))

  document.documentElement.style.setProperty("--kb-inset", `${hidden}px`)
}

export function watchKeyboard() {
  const viewport = window.visualViewport
  if (!viewport) return

  publishKeyboardInset()

  for (const event of ["resize", "scroll"]) {
    viewport.addEventListener(event, publishKeyboardInset)
  }
}

export function watchTelegramViewport(webApp) {
  if (!webApp) return

  publishTelegramInsets(webApp)

  if (typeof webApp.onEvent !== "function") return

  try {
    webApp.onEvent("fullscreenFailed", () => {
      fullscreenDenied = true
      publishTelegramInsets(webApp)
    })
  } catch (_error) {
    // An older client without the event simply never refuses.
  }

  for (const event of VIEWPORT_EVENTS) {
    try {
      webApp.onEvent(event, () => publishTelegramInsets(webApp))
    } catch (_error) {
      // An older Telegram client rejects unknown events. The static fallback
      // values remain correct, so the interface must still render.
    }
  }

  // Fullscreen is granted asynchronously, and a client that reports nothing at
  // that moment may report real numbers a beat later. Re-publish a few times so
  // the interface settles without waiting on an event that may never arrive.
  for (const delay of [100, 400, 1200]) {
    setTimeout(() => publishTelegramInsets(webApp), delay)
  }
}
