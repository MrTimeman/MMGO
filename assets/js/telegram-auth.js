const STORAGE_KEY = "mmgo_telegram_auth";

export async function initTelegramAuth() {
  if (typeof window === "undefined") return;

  const tg = window.Telegram?.WebApp;
  if (!tg || !tg.initData) return;

  // Skip if we already tried auth this session
  if (sessionStorage.getItem(STORAGE_KEY)) return;

  tg.ready();

  try {
    const resp = await fetch("/api/auth/telegram", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
      },
      body: JSON.stringify({ initData: tg.initData }),
    });

    if (resp.ok) {
      sessionStorage.setItem(STORAGE_KEY, "ok");
      window.location.reload();
    } else {
      sessionStorage.setItem(STORAGE_KEY, "failed");
      console.warn("Telegram auth failed, continuing as guest");
    }
  } catch (_err) {
    sessionStorage.setItem(STORAGE_KEY, "network_error");
    console.warn("Telegram auth network error, continuing as guest");
  }
}

function csrfToken() {
  const meta = document.querySelector("meta[name='csrf-token']");
  return meta ? meta.getAttribute("content") : "";
}
