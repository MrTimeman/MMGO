import { loadTelegramWebApp } from "../telegram-web-app"

export const TelegramAuthHook = {
  mounted() {
    this.submitTelegramInitData()
  },

  reconnected() {
    this.submitTelegramInitData()
  },

  async submitTelegramInitData() {
    if (this.el.dataset.submitted === "true") return

    try {
      const webApp = await loadTelegramWebApp()
      const initData = webApp?.initData

      if (!initData) return

      webApp.ready?.()

      const input = this.el.querySelector("#telegram-auth-init-data")
      const loading = this.el.querySelector("#telegram-auth-loading")
      const browserState = this.el.querySelector("#telegram-auth-normal-browser")

      if (!input || !loading || !browserState) return

      input.value = initData
      loading.hidden = false
      browserState.hidden = true
      this.el.dataset.submitted = "true"
      this.el.requestSubmit()
    } catch (_error) {
      // Keep the server-rendered normal-browser state visible. Authentication
      // is never bypassed when the Telegram bridge cannot be loaded.
    }
  },
}
