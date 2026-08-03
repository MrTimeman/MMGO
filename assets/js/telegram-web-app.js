let telegramWebAppPromise

export function loadTelegramWebApp() {
  if (window.Telegram?.WebApp) return Promise.resolve(window.Telegram.WebApp)
  if (!isTelegramLaunch()) return Promise.resolve(undefined)
  if (telegramWebAppPromise) return telegramWebAppPromise

  telegramWebAppPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://telegram.org/js/telegram-web-app.js?62"
    script.async = true
    script.onload = () => resolve(window.Telegram?.WebApp)
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
