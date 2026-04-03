<script lang="ts">
  import type { DataSource, EntryState } from "../lib/types";

  export let entry: EntryState;
  export let source: DataSource = "mock";
  export let onEnter: (() => void) | undefined = undefined;

  let soundEnabled = true;
  let language = "EN";
  let helpOpen = false;

  const headings = {
    first_open: "[First-open heading placeholder]",
    resume: "[Resume heading placeholder]",
    deep_link: "[Deep-link heading placeholder]",
    recovery: "[Recovery heading placeholder]"
  } as const;

  const bodies = {
    first_open: "[First-open body placeholder]",
    resume: "[Resume body placeholder]",
    deep_link: "[Deep-link body placeholder]",
    recovery: "[Recovery body placeholder]"
  } as const;

  $: primaryLabel = entry.mode === "resume" ? "Resume Journey" : "Enter World";
</script>

<section class="entry-screen">
  <div class="entry-atmosphere"></div>

  <div class="entry-card">
    <div class="entry-copy">
      <div class="entry-brand">
        <div class="entry-crest">M</div>
        <div>
          <p class="entry-realm">{entry.realm.name}</p>
          <p class="entry-source">{source === "mock" ? "Client preview bootstrap" : "Live bootstrap"}</p>
        </div>
      </div>

      <div class="entry-text">
        <h1>{headings[entry.mode]}</h1>
        <p>{bodies[entry.mode]}</p>
      </div>

      {#if entry.mode === "recovery"}
        <section class="entry-recovery">
          <h2>{entry.recovery?.title}</h2>
          <p>{entry.recovery?.body}</p>

          <div class="entry-actions">
            <button type="button" class="entry-primary" on:click={() => window.location.reload()}>
              Try Telegram Again
            </button>
            <a class="entry-secondary" href="https://t.me/mmgo_bot" target="_blank" rel="noreferrer">
              Open Bot Fallback
            </a>
          </div>
        </section>
      {:else}
        <section class="entry-preview">
          <div class="entry-preview-card">
            <div>
              <p class="entry-preview-label">
                {entry.mode === "first_open" ? "Character Preview" : "Returning Adventurer"}
              </p>
              <h2>{entry.character?.name}</h2>
              <p>{entry.account?.displayName}</p>
            </div>

            <div class="entry-preview-meta">
              <span>Lv.{entry.character?.level}</span>
              <span>{entry.character?.title}</span>
            </div>
          </div>

          {#if entry.mode === "deep_link"}
            <p class="entry-inline-note">Direct target: {entry.targetLabel}</p>
          {/if}

          <button type="button" class="entry-primary" on:click={() => onEnter?.()}>
            {primaryLabel}
          </button>
        </section>
      {/if}
    </div>

    <aside class="entry-settings">
      <p class="entry-settings-label">Settings</p>

      <button type="button" class="entry-setting" on:click={() => (soundEnabled = !soundEnabled)}>
        <span>Sound</span>
        <strong>{soundEnabled ? "On" : "Off"}</strong>
      </button>

      <button
        type="button"
        class="entry-setting"
        on:click={() => (language = language === "EN" ? "RU" : "EN")}
      >
        <span>Language</span>
        <strong>{language}</strong>
      </button>

      <button type="button" class="entry-setting" on:click={() => (helpOpen = !helpOpen)}>
        <span>Help</span>
        <strong>{helpOpen ? "Hide" : "Show"}</strong>
      </button>

      {#if helpOpen}
        <div class="entry-help">
          [Help text placeholder]
        </div>
      {/if}
    </aside>
  </div>
</section>

<style>
  .entry-screen {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    padding: clamp(1.5rem, 4vw, 3rem);
    position: relative;
    overflow: hidden;
  }

  .entry-atmosphere {
    position: absolute;
    inset: 0;
    background:
      radial-gradient(circle at 15% 20%, rgba(245, 158, 11, 0.26), transparent 22rem),
      radial-gradient(circle at 85% 22%, rgba(231, 214, 169, 0.14), transparent 18rem),
      radial-gradient(circle at 50% 88%, rgba(146, 64, 14, 0.22), transparent 24rem);
    pointer-events: none;
  }

  .entry-card {
    position: relative;
    z-index: 1;
    width: min(72rem, 100%);
    display: grid;
    gap: 1.5rem;
    grid-template-columns: minmax(0, 1.55fr) minmax(18rem, 0.85fr);
    padding: clamp(1.25rem, 3vw, 2rem);
    border-radius: 2rem;
    border: 1px solid rgba(245, 222, 179, 0.12);
    background:
      linear-gradient(180deg, rgba(28, 25, 23, 0.94), rgba(18, 15, 13, 0.98)),
      radial-gradient(circle at top, rgba(245, 158, 11, 0.1), transparent 18rem);
    box-shadow: 0 2rem 5rem rgba(0, 0, 0, 0.35);
    backdrop-filter: blur(18px);
  }

  .entry-copy {
    display: grid;
    gap: 1.5rem;
  }

  .entry-brand {
    display: flex;
    align-items: center;
    gap: 0.9rem;
  }

  .entry-crest {
    width: 3.25rem;
    height: 3.25rem;
    border-radius: 1.1rem;
    display: grid;
    place-items: center;
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.95), rgba(180, 83, 9, 0.95));
    color: #140f0a;
    font-family: var(--font-sans);
    font-weight: 700;
    letter-spacing: 0.24em;
  }

  .entry-realm,
  .entry-settings-label,
  .entry-preview-label,
  .entry-source,
  .entry-inline-note {
    margin: 0;
    font-family: var(--font-sans);
  }

  .entry-realm {
    text-transform: uppercase;
    letter-spacing: 0.24em;
    font-size: 0.74rem;
    color: rgba(245, 200, 116, 0.92);
  }

  .entry-source {
    margin-top: 0.25rem;
    color: rgba(222, 214, 202, 0.58);
    font-size: 0.76rem;
  }

  .entry-text h1,
  .entry-text p,
  .entry-preview-card h2,
  .entry-preview-card p,
  .entry-recovery h2,
  .entry-recovery p {
    margin: 0;
  }

  .entry-text h1 {
    font-size: clamp(2.25rem, 5vw, 4.5rem);
    line-height: 0.95;
    max-width: 12ch;
  }

  .entry-text p {
    margin-top: 1rem;
    max-width: 40rem;
    color: rgba(231, 225, 216, 0.76);
  }

  .entry-preview,
  .entry-recovery {
    display: grid;
    gap: 1rem;
  }

  .entry-preview-card,
  .entry-recovery,
  .entry-help,
  .entry-setting {
    border-radius: 1.5rem;
    border: 1px solid rgba(245, 222, 179, 0.1);
    background: rgba(255, 248, 237, 0.045);
  }

  .entry-preview-card {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: flex-end;
    padding: 1.25rem;
  }

  .entry-preview-label {
    font-size: 0.76rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: rgba(245, 200, 116, 0.82);
  }

  .entry-preview-card h2 {
    margin-top: 0.5rem;
    font-size: clamp(1.55rem, 3vw, 2.4rem);
  }

  .entry-preview-card p {
    margin-top: 0.35rem;
    color: rgba(231, 225, 216, 0.72);
  }

  .entry-preview-meta {
    display: grid;
    gap: 0.35rem;
    text-align: right;
    color: rgba(231, 225, 216, 0.68);
    font-family: var(--font-sans);
    font-size: 0.85rem;
  }

  .entry-inline-note {
    color: rgba(245, 200, 116, 0.86);
    font-size: 0.84rem;
  }

  .entry-recovery {
    padding: 1.25rem;
  }

  .entry-recovery h2 {
    font-size: 1.35rem;
  }

  .entry-recovery p {
    margin-top: 0.6rem;
    color: rgba(231, 225, 216, 0.72);
  }

  .entry-actions {
    display: flex;
    gap: 0.75rem;
    flex-wrap: wrap;
    margin-top: 1rem;
  }

  .entry-primary,
  .entry-secondary {
    min-height: 3.5rem;
    border-radius: 999px;
    padding: 0.9rem 1.35rem;
    font-family: var(--font-sans);
    font-weight: 700;
    letter-spacing: 0.02em;
    transition:
      transform 160ms ease,
      box-shadow 180ms ease,
      background 180ms ease,
      border-color 180ms ease;
  }

  .entry-primary {
    border: none;
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.98), rgba(217, 119, 6, 0.98));
    color: #1a120b;
    box-shadow: 0 1rem 2.5rem rgba(180, 83, 9, 0.26);
  }

  .entry-primary:hover,
  .entry-secondary:hover,
  .entry-setting:hover {
    transform: translateY(-1px);
  }

  .entry-secondary {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    text-decoration: none;
    border: 1px solid rgba(245, 222, 179, 0.18);
    background: rgba(255, 255, 255, 0.04);
    color: #f6efe3;
  }

  .entry-settings {
    display: grid;
    align-content: start;
    gap: 0.75rem;
  }

  .entry-settings-label {
    font-size: 0.78rem;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    color: rgba(222, 214, 202, 0.62);
  }

  .entry-setting {
    width: 100%;
    padding: 1rem 1.1rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: #f6efe3;
    cursor: pointer;
  }

  .entry-setting span,
  .entry-setting strong {
    font-size: 0.95rem;
  }

  .entry-help {
    padding: 1rem 1.1rem;
    color: rgba(231, 225, 216, 0.68);
    font-size: 0.92rem;
  }

  @media (max-width: 900px) {
    .entry-card {
      grid-template-columns: 1fr;
    }

    .entry-settings {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .entry-help {
      grid-column: 1 / -1;
    }
  }

  @media (max-width: 640px) {
    .entry-screen {
      padding: 1rem;
    }

    .entry-card {
      border-radius: 1.5rem;
      padding: 1rem;
    }

    .entry-settings {
      grid-template-columns: 1fr;
    }

    .entry-actions {
      flex-direction: column;
    }

    .entry-preview-card {
      flex-direction: column;
      align-items: flex-start;
    }

    .entry-preview-meta {
      text-align: left;
    }
  }
</style>
