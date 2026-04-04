<script lang="ts">
  import { onMount } from "svelte";
  import EntryGate from "./components/EntryGate.svelte";
  import WorldShell from "./components/WorldShell.svelte";
  import { loadSession } from "./lib/api.ts";
  import { buildMockSession } from "./lib/mock-data.ts";
  import { initTelegramMiniApp } from "./lib/telegram.ts";
  import type { ClientSession } from "./lib/types";

  let session: ClientSession | null = null;

  const previewModes = [
    ["resume", "Resume"],
    ["first_open", "First Open"],
    ["deep_link", "Deep Link"],
    ["invalid_target", "Invalid Target"],
    ["recovery", "Recovery"]
  ] as const;

  onMount(async () => {
    initTelegramMiniApp();
    session = await loadSession();
  });

  function enterWorld(): void {
    if (!session?.shell) {
      return;
    }

    session = {
      ...session,
      view: "shell"
    };
  }

  function setPreview(mode: string): void {
    session = buildMockSession(mode);
  }
</script>

{#if !session}
  <main class="boot">
    <div class="boot-rune">MMGO</div>
    <p>Loading...</p>
  </main>
{:else if session.view === "entry" && session.entry}
  <EntryGate entry={session.entry} source={session.source} onEnter={enterWorld} />
{:else if session.shell}
  <WorldShell shell={session.shell} />
{/if}

{#if import.meta.env.DEV}
  <details class="preview-switcher">
    <summary>Preview</summary>

    <div class="preview-switcher-body" aria-label="Preview modes">
      {#each previewModes as [mode, label]}
        <button type="button" on:click={() => setPreview(mode)}>{label}</button>
      {/each}
    </div>
  </details>
{/if}

<style>
  .boot {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    gap: 1rem;
    text-align: center;
    padding: 2rem;
  }

  .boot-rune {
    width: 6.5rem;
    height: 6.5rem;
    display: grid;
    place-items: center;
    border-radius: 1.75rem;
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.96), rgba(180, 83, 9, 0.96));
    color: #160f0a;
    font-family: var(--font-sans);
    font-weight: 700;
    letter-spacing: 0.18em;
  }

  .boot p {
    margin: 0;
  }

  .preview-switcher {
    position: fixed;
    top: 1rem;
    right: 1rem;
    z-index: 40;
    width: 9.5rem;
    border: 1px solid rgba(245, 222, 179, 0.12);
    background: rgba(12, 10, 9, 0.66);
    backdrop-filter: blur(12px);
    border-radius: 1rem;
    overflow: hidden;
  }

  .preview-switcher summary {
    list-style: none;
    cursor: pointer;
    padding: 0.72rem 0.8rem;
    font-family: var(--font-sans);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.14em;
    color: rgba(231, 225, 216, 0.68);
  }

  .preview-switcher summary::-webkit-details-marker {
    display: none;
  }

  .preview-switcher-body {
    display: grid;
    gap: 0.4rem;
    padding: 0 0.75rem 0.75rem;
  }

  .preview-switcher button {
    min-height: 2.2rem;
    border: 1px solid rgba(245, 222, 179, 0.08);
    border-radius: 0.8rem;
    background: rgba(255, 255, 255, 0.03);
    color: rgba(249, 241, 231, 0.82);
    font-family: var(--font-sans);
    cursor: pointer;
  }

  .preview-switcher button:hover {
    border-color: rgba(245, 158, 11, 0.3);
  }

  @media (max-width: 700px) {
    .preview-switcher {
      inset: 1rem 1rem auto auto;
    }
  }
</style>
