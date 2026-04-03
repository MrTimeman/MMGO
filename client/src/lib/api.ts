import { buildMockSession } from "./mock-data";
import type { ClientSession } from "./types";

const DEFAULT_BOOTSTRAP_ENDPOINT = "/api/mini-app/bootstrap";

function mockModeFromLocation(): string | null {
  if (typeof window === "undefined") {
    return "resume";
  }

  return new URL(window.location.href).searchParams.get("mode");
}

function buildUnavailableSession(): ClientSession {
  return {
    source: "mock",
    view: "entry",
    entry: {
      mode: "recovery",
      realm: {
        slug: "canonical",
        name: "Canonical Realm",
        description: "Fallback realm bootstrap."
      },
      account: null,
      character: null,
      recovery: {
        title: "The gate is present, but the session feed is not.",
        body: "The Svelte client is ready, but Phoenix is not exposing a bootstrap endpoint yet."
      }
    },
    shell: null
  };
}

export async function loadSession(): Promise<ClientSession> {
  const endpoint =
    import.meta.env.VITE_MMGO_BOOTSTRAP_ENDPOINT ?? DEFAULT_BOOTSTRAP_ENDPOINT;

  try {
    const response = await fetch(endpoint, {
      credentials: "include",
      headers: {
        accept: "application/json"
      }
    });

    if (!response.ok) {
      throw new Error(`Bootstrap request failed with status ${response.status}.`);
    }

    return {
      ...(await response.json()),
      source: "api"
    } as ClientSession;
  } catch (_error) {
    if (import.meta.env.DEV) {
      return buildMockSession(mockModeFromLocation());
    }

    return buildUnavailableSession();
  }
}
