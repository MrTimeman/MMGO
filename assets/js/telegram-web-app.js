import {watchTelegramViewport} from "./telegram-viewport"

let telegramWebAppPromise
let preparedTelegramWebApp

export function prepareTelegramWebApp(webApp) {
  if (!webApp || preparedTelegramWebApp === webApp) return webApp

  preparedTelegramWebApp = webApp

  safelyInvoke(() => webApp.ready?.())
  safelyInvoke(() => webApp.expand?.())

  // Telegram uses this colour for its own header and for choosing contrasting
  // status-bar controls.
  safelyInvoke(() => webApp.setHeaderColor?.("#0c0a09"))

  // Fullscreen is off. Clients report both safe-area insets as zero while
  // still drawing the page under the status bar and under Telegram's own
  // floating controls, so the first row of the interface is unreadable and
  // nothing the page can measure tells it how much room to reserve. Telegram
  // remembers the mode per app, so an app that entered fullscreen on an
  // earlier visit has to be told to leave it.
  if (webApp.isFullscreen === true) {
    safelyInvoke(() => webApp.exitFullscreen?.())
  }

  // The insets still matter outside fullscreen: a notched device reports a real
  // bottom inset, and the layout reads the same tokens either way.
  safelyInvoke(() => watchTelegramViewport(webApp))

  return webApp
}

export function loadTelegramWebApp() {
  if (window.Telegram?.WebApp) {
    return Promise.resolve(prepareTelegramWebApp(window.Telegram.WebApp))
  }

  if (!isTelegramLaunch()) return Promise.resolve(undefined)
  if (telegramWebAppPromise) return telegramWebAppPromise

  telegramWebAppPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://telegram.org/js/telegram-web-app.js?63"
    script.async = true
    script.onload = () => resolve(prepareTelegramWebApp(window.Telegram?.WebApp))
    script.onerror = () => reject(new Error("Не удалось загрузить мост веб-приложения Telegram"))
    document.head.appendChild(script)
  })

  return telegramWebAppPromise
}

function isTelegramLaunch() {
  const query = new URLSearchParams(window.location.search)
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""))

  return (
    query.has("tgWebAppVersion") ||
    hash.has("tgWebAppVersion") ||
    navigator.userAgent.includes("Telegram")
  )
}

function safelyInvoke(callback) {
  try {
    callback()
  } catch (_error) {
    // Fullscreen is progressive enhancement. Authentication must continue
    // even when a Telegram client rejects or does not implement a UI method.
  }
}
