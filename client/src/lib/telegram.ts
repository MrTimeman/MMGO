export function initTelegramMiniApp(): void {
  if (typeof window === "undefined") {
    return;
  }

  const webApp = window.Telegram?.WebApp;

  if (!webApp) {
    return;
  }

  webApp.ready?.();
  webApp.expand?.();
  webApp.setHeaderColor?.("#120f0d");
  webApp.setBackgroundColor?.("#120f0d");
}
