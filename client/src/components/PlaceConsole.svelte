<script lang="ts">
  import TextBubble from "./TextBubble.svelte";
  import type { MapMarker, ShellState } from "../lib/types";

  export let marker: MapMarker;
  export let shell: ShellState;
  export let onBack: (() => void) | undefined = undefined;

  let feedWidth = 360;
</script>

<section class="place-console">
  <div class="place-console-head">
    <button type="button" class="place-console-back" on:click={() => onBack?.()}>
      Back to atlas
    </button>
    <div class="place-console-meta">
      <span>{marker.region}</span>
      <span>{marker.kind.replace("_", " ")}</span>
    </div>
  </div>

  <div class="place-console-body">
    <div class="place-console-copy">
      <p class="place-console-kicker">Entered location</p>
      <h2>{marker.name}</h2>
      <p class="place-console-intro">{marker.entryBody}</p>
    </div>

    <div class="place-console-section">
      <p class="place-console-label">Command surface</p>
      <div class="place-console-options">
        {#each marker.localActions as action, index}
          <button
            type="button"
            class="place-console-option"
            class:place-console-option--primary={action.emphasis === "primary" || index === 0}
          >
            <span>0{index + 1}</span>
            <div>
              <strong>{action.label}</strong>
              <small>{action.detail}</small>
            </div>
          </button>
        {/each}
      </div>
    </div>

    <div class="place-console-section">
      <p class="place-console-label">Local text feed</p>
      <div class="place-console-feed" bind:clientWidth={feedWidth}>
        {#each marker.localFeed as event}
          <TextBubble event={event} maxWidth={Math.max(240, feedWidth - 8)} />
        {/each}
      </div>
    </div>

    <div class="place-console-grid">
      <div class="place-console-column">
        <p class="place-console-label">Current traveler state</p>
        <ul>
          <li>{shell.timerLabel}</li>
          <li>{shell.supplyLabel}</li>
          <li>{shell.weightLabel}</li>
        </ul>
      </div>

      <div class="place-console-column">
        <p class="place-console-label">Why this place matters</p>
        <ul>
          {#each marker.intel as note}
            <li>{note}</li>
          {/each}
        </ul>
      </div>
    </div>
  </div>
</section>

<style>
  .place-console {
    position: absolute;
    inset: 0.9rem;
    z-index: 6;
    border: 1px solid rgba(244, 229, 202, 0.18);
    background:
      radial-gradient(circle at top, rgba(245, 158, 11, 0.08), transparent 18rem),
      linear-gradient(180deg, rgba(17, 14, 12, 0.96), rgba(10, 9, 8, 0.98));
    backdrop-filter: blur(10px);
    border-radius: 1.55rem;
    padding: 1.1rem 1.15rem;
    overflow: auto;
  }

  .place-console-head {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: center;
  }

  .place-console-back {
    border: 1px solid rgba(244, 229, 202, 0.12);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.04);
    color: rgba(247, 239, 214, 0.88);
    padding: 0.65rem 0.95rem;
    cursor: pointer;
    font-family: var(--font-sans);
  }

  .place-console-meta {
    display: flex;
    gap: 0.6rem;
    flex-wrap: wrap;
    font-family: var(--font-sans);
    font-size: 0.72rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: rgba(240, 233, 214, 0.48);
  }

  .place-console-body {
    margin-top: 1.1rem;
    display: grid;
    gap: 1.3rem;
  }

  .place-console-kicker,
  .place-console-label {
    margin: 0;
    font-family: var(--font-sans);
    font-size: 0.68rem;
    text-transform: uppercase;
    letter-spacing: 0.16em;
    color: rgba(240, 233, 214, 0.46);
  }

  .place-console-copy h2,
  .place-console-intro {
    margin: 0;
  }

  .place-console-copy h2 {
    margin-top: 0.45rem;
    font-size: clamp(2rem, 4vw, 3.25rem);
    line-height: 0.96;
  }

  .place-console-intro {
    margin-top: 0.9rem;
    max-width: 58rem;
    color: rgba(247, 239, 214, 0.8);
    line-height: 1.7;
    font-size: 1.02rem;
  }

  .place-console-options {
    margin-top: 0.65rem;
    display: grid;
    gap: 0.55rem;
    max-width: 48rem;
  }

  .place-console-option {
    border: 1px solid rgba(244, 229, 202, 0.09);
    border-radius: 1rem;
    background: rgba(255, 255, 255, 0.025);
    color: rgba(247, 239, 214, 0.88);
    padding: 0.8rem 0.9rem;
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 0.75rem;
    text-align: left;
    cursor: pointer;
  }

  .place-console-option--primary {
    background: linear-gradient(145deg, rgba(98, 49, 18, 0.92), rgba(59, 31, 13, 0.92));
    border-color: rgba(183, 96, 35, 0.42);
  }

  .place-console-option span {
    font-family: var(--font-sans);
    font-size: 0.74rem;
    color: rgba(240, 233, 214, 0.42);
    padding-top: 0.15rem;
  }

  .place-console-option strong,
  .place-console-option small {
    display: block;
  }

  .place-console-option small {
    margin-top: 0.18rem;
    color: rgba(240, 233, 214, 0.68);
    line-height: 1.45;
  }

  .place-console-feed {
    margin-top: 0.65rem;
    display: grid;
    gap: 0.65rem;
    justify-items: start;
  }

  .place-console-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 1rem;
  }

  .place-console-column ul {
    margin: 0.65rem 0 0;
    padding-left: 1rem;
    color: rgba(240, 233, 214, 0.74);
    line-height: 1.55;
  }

  @media (max-width: 820px) {
    .place-console {
      inset: 0.65rem;
    }

    .place-console-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
