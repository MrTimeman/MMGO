<script lang="ts">
  import { onMount } from "svelte";
  import { bubbleTypography, measureBubble } from "../lib/pretext.ts";
  import type { LogEvent } from "../lib/types";

  export let event: LogEvent;
  export let maxWidth = 320;

  let metrics = measureBubble(event.text, maxWidth);
  let fontsReady = false;

  const typography = bubbleTypography();

  $: metrics = measureBubble(event.text, maxWidth);

  onMount(() => {
    if (!("fonts" in document) || fontsReady) {
      return;
    }

    document.fonts.ready.then(() => {
      fontsReady = true;
      metrics = measureBubble(event.text, maxWidth);
    });
  });
</script>

<article
  class="bubble bubble--{event.kind}"
  style={`--bubble-width:${metrics.width}px; --bubble-height:${metrics.height}px; --bubble-line-height:${typography.lineHeight}px;`}
>
  <p class="bubble-kind">{event.kind}</p>
  <p class="bubble-text">{event.text}</p>
  <p class="bubble-meta">{metrics.lineCount} line{metrics.lineCount === 1 ? "" : "s"}</p>
</article>

<style>
  .bubble {
    width: min(100%, var(--bubble-width));
    min-height: var(--bubble-height);
    padding: 0.95rem 1rem 0.85rem;
    border-radius: 1.25rem;
    border: 1px solid rgba(245, 222, 179, 0.08);
    background: rgba(255, 248, 237, 0.035);
    display: grid;
    gap: 0.55rem;
  }

  .bubble-kind,
  .bubble-meta {
    margin: 0;
    font-family: var(--font-sans);
    text-transform: uppercase;
    letter-spacing: 0.14em;
    font-size: 0.67rem;
  }

  .bubble-kind {
    color: rgba(231, 225, 216, 0.5);
  }

  .bubble-text {
    margin: 0;
    line-height: var(--bubble-line-height);
    color: rgba(249, 241, 231, 0.86);
  }

  .bubble-meta {
    color: rgba(231, 225, 216, 0.42);
  }

  .bubble--encounter {
    background: rgba(127, 29, 29, 0.14);
  }

  .bubble--reward {
    background: rgba(120, 53, 15, 0.18);
  }
</style>
