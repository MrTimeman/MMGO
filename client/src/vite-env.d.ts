/// <reference types="vite/client" />
/// <reference types="svelte" />

interface TelegramWebApp {
  ready?: () => void;
  expand?: () => void;
  setHeaderColor?: (color: string) => void;
  setBackgroundColor?: (color: string) => void;
}

interface TelegramNamespace {
  WebApp?: TelegramWebApp;
}

interface Window {
  Telegram?: TelegramNamespace;
}
