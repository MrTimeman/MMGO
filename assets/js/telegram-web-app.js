let telegramWebAppPromise

export function loadTelegramWebApp() {
  if (window.Telegram?.WebApp) return Promise.resolve(window.Telegram.WebApp)
  if (telegramWebAppPromise) return telegramWebAppPromise

  telegramWebAppPromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "https://telegram.org/js/telegram-web-app.js?62"
    script.async = true
    script.onload = () => resolve(window.Telegram?.WebApp)
    script.onerror = () => reject(new Error("Telegram WebApp bridge did not load"))
    document.head.appendChild(script)
  })

  return telegramWebAppPromise
}
