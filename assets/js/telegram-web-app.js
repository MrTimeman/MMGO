import {watchTelegramViewport} from "./telegram-viewport"

let telegramWebAppPromise
let preparedTelegramWebApp

export function prepareTelegramWebApp(webApp) {
  if (!webApp || preparedTelegramWebApp === webApp) return webApp

  preparedTelegramWebApp = webApp

  safelyInvoke(() => webApp.ready?.())
  safelyInvoke(() => webApp.expand?.())

  if (supportsFullscreen(webApp) && webApp.isFullscreen !== true) {
    // Telegram uses this colour to choose contrasting status-bar controls
    // while its own header is transparent in fullscreen mode.
    safelyInvoke(() => webApp.setHeaderColor?.("#0c0a09"))
    safelyInvoke(() => webApp.requestFullscreen())
  }

  // Must follow the fullscreen request so the first inset publish reflects it.
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

function supportsFullscreen(webApp) {
  try {
    return (
      typeof webApp.isVersionAtLeast === "function" &&
      webApp.isVersionAtLeast("8.0") &&
      typeof webApp.requestFullscreen === "function"
    )
  } catch (_error) {
    return false
  }
}

function safelyInvoke(callback) {
  try {
    callback()
  } catch (_error) {
    // Fullscreen is progressive enhancement. Authentication must continue
    // even when a Telegram client rejects or does not implement a UI method.
  }
}
