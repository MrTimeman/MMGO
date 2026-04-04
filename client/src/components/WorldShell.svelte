<script lang="ts">
  import AtlasMap from "./AtlasMap.svelte";
  import PlaceConsole from "./PlaceConsole.svelte";
  import type { MapMarker, ShellState } from "../lib/types";

  export let shell: ShellState;

  let selectedLocationId = shell.selectedLocationId;
  let showRoutes = true;
  let viewMode: "map" | "place" = "map";
  let transientNotice = shell.notice;

  $: selectedLocation =
    shell.map.markers.find((marker) => marker.id === selectedLocationId) ??
    shell.map.markers.find((marker) => marker.id === shell.currentLocationId) ??
    shell.map.markers[0];

  $: currentLocation =
    shell.map.markers.find((marker) => marker.id === shell.currentLocationId) ?? selectedLocation;

  $: selectedIsCurrent = selectedLocation.id === shell.currentLocationId;

  $: primaryActionLabel = selectedIsCurrent ? "Enter" : "Plot course";

  function handleSelect(marker: MapMarker): void {
    selectedLocationId = marker.id;
    transientNotice = undefined;

    if (viewMode === "place") {
      viewMode = "map";
    }
  }

  function enterPlace(): void {
    viewMode = "place";
  }

  function returnToAtlas(): void {
    viewMode = "map";
  }

  function centerOnSelf(): void {
    selectedLocationId = shell.currentLocationId;
    transientNotice = undefined;
  }

  function toggleRoutes(): void {
    showRoutes = !showRoutes;
  }

  function handlePrimaryAction(): void {
    if (selectedIsCurrent) {
      enterPlace();
      return;
    }

    transientNotice = "[Travel notice placeholder]";
  }
</script>

<section class="shell">
  <div class="shell-stage">
    <AtlasMap
      map={shell.map}
      selectedMarkerId={selectedLocationId}
      {showRoutes}
      onSelect={handleSelect}
      onCenterSelf={centerOnSelf}
    />

    {#if viewMode === "map"}
      <header class="shell-hud">
        <div class="shell-sigil">{shell.character.name.slice(0, 1)}</div>

        <div class="shell-hud-copy">
          <strong>{shell.character.name}</strong>
          <span>{currentLocation.name}</span>
        </div>
      </header>

      <div class="shell-tools">
        <button type="button" class="shell-tool" on:click={centerOnSelf}>Self</button>
        <button type="button" class="shell-tool" on:click={toggleRoutes}>
          {showRoutes ? "Routes on" : "Routes off"}
        </button>
      </div>

      {#if transientNotice}
        <div class="shell-toast">
          <span>{transientNotice}</span>
          <button type="button" on:click={() => (transientNotice = undefined)}>Dismiss</button>
        </div>
      {/if}

      <section class="selection-strip">
        <div class="selection-copy">
          <p class="selection-kicker">{selectedIsCurrent ? "Current" : "Selected"}</p>

          <div class="selection-heading">
            <h2>{selectedLocation.name}</h2>
            <span>{selectedLocation.region}</span>
          </div>
        </div>

        <div class="selection-actions">
          <button
            type="button"
            class="selection-action selection-action--primary"
            on:click={handlePrimaryAction}
          >
            {primaryActionLabel}
          </button>

          {#if selectedIsCurrent}
            <button
              type="button"
              class="selection-action selection-action--secondary"
              on:click={toggleRoutes}
            >
              {showRoutes ? "Hide routes" : "Show routes"}
            </button>
          {:else}
            <button
              type="button"
              class="selection-action selection-action--secondary"
              on:click={centerOnSelf}
            >
              Back to self
            </button>
          {/if}
        </div>
      </section>
    {:else}
      <PlaceConsole
        marker={selectedLocation}
        shell={shell}
        onBack={returnToAtlas}
      />
    {/if}
  </div>
</section>

<style>
  .shell {
    min-height: 100dvh;
    padding: 0;
  }

  .shell-stage {
    position: relative;
    min-height: 100dvh;
    padding: 0.6rem;
  }

  :global(.shell-stage > .atlas) {
    position: absolute;
    inset: 0.6rem;
  }

  .shell-hud,
  .shell-tools,
  .shell-toast,
  .selection-strip {
    position: absolute;
    z-index: 5;
    border: 1px solid rgba(244, 229, 202, 0.12);
    background: rgba(16, 13, 11, 0.68);
    backdrop-filter: blur(12px);
  }

  .shell-hud {
    top: 1.05rem;
    left: 1.05rem;
    display: flex;
    align-items: center;
    gap: 0.65rem;
    padding: 0.5rem 0.75rem 0.5rem 0.55rem;
    border-radius: 999px;
  }

  .shell-sigil {
    width: 2rem;
    height: 2rem;
    display: grid;
    place-items: center;
    border-radius: 999px;
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.94), rgba(180, 83, 9, 0.94));
    color: #140f0a;
    font-family: var(--font-sans);
    font-size: 0.82rem;
    font-weight: 700;
  }

  .shell-hud-copy {
    display: grid;
    gap: 0.08rem;
  }

  .shell-hud-copy strong,
  .shell-hud-copy span,
  .selection-kicker,
  .selection-heading span,
  .shell-tool,
  .shell-toast span,
  .shell-toast button,
  .selection-action {
    font-family: var(--font-sans);
  }

  .shell-hud-copy strong {
    font-size: 0.88rem;
    line-height: 1;
    color: rgba(249, 241, 231, 0.9);
  }

  .shell-hud-copy span {
    font-size: 0.66rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: rgba(240, 233, 214, 0.5);
  }

  .shell-tools {
    top: 1.05rem;
    right: 1.05rem;
    display: flex;
    gap: 0.35rem;
    padding: 0.35rem;
    border-radius: 999px;
  }

  .shell-tool {
    min-height: 2rem;
    padding: 0.45rem 0.72rem;
    border: 1px solid rgba(244, 229, 202, 0.1);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.04);
    color: rgba(247, 239, 214, 0.78);
    font-size: 0.72rem;
    cursor: pointer;
  }

  .shell-toast {
    top: 1.05rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 0.7rem;
    max-width: min(24rem, calc(100% - 8rem));
    padding: 0.55rem 0.7rem;
    border-radius: 999px;
  }

  .shell-toast span {
    min-width: 0;
    font-size: 0.72rem;
    color: rgba(249, 241, 231, 0.86);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .shell-toast button {
    border: none;
    background: transparent;
    color: rgba(245, 200, 116, 0.88);
    font-size: 0.72rem;
    cursor: pointer;
    padding: 0;
  }

  .selection-strip {
    left: 50%;
    bottom: 1.05rem;
    transform: translateX(-50%);
    width: min(34rem, calc(100% - 2.1rem));
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    align-items: center;
    gap: 0.8rem;
    padding: 0.7rem 0.82rem;
    border-radius: 1.2rem;
  }

  .selection-copy {
    min-width: 0;
    display: grid;
    gap: 0.22rem;
  }

  .selection-kicker,
  .selection-heading span {
    margin: 0;
    font-size: 0.64rem;
    letter-spacing: 0.14em;
    text-transform: uppercase;
    color: rgba(240, 233, 214, 0.48);
  }

  .selection-heading {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    gap: 0.45rem;
    min-width: 0;
  }

  .selection-heading h2 {
    margin: 0;
    min-width: 0;
    font-size: clamp(1.2rem, 2.2vw, 1.65rem);
    line-height: 0.95;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .selection-actions {
    display: flex;
    gap: 0.45rem;
    flex-shrink: 0;
  }

  .selection-action {
    min-height: 2.45rem;
    padding: 0.58rem 0.88rem;
    border: 1px solid rgba(244, 229, 202, 0.1);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.04);
    color: rgba(247, 239, 214, 0.82);
    font-size: 0.78rem;
    cursor: pointer;
  }

  .selection-action--primary {
    background: linear-gradient(145deg, rgba(98, 49, 18, 0.95), rgba(59, 31, 13, 0.95));
    border-color: rgba(183, 96, 35, 0.44);
    color: rgba(251, 244, 227, 0.94);
  }

  @media (max-width: 820px) {
    .shell-toast {
      top: 4.3rem;
      max-width: calc(100% - 2.2rem);
    }
  }

  @media (max-width: 700px) {
    .shell-stage {
      padding: 0.45rem;
    }

    :global(.shell-stage > .atlas) {
      inset: 0.45rem;
    }

    .shell-hud {
      top: 0.8rem;
      left: 0.8rem;
      padding: 0.42rem 0.62rem 0.42rem 0.46rem;
    }

    .shell-sigil {
      width: 1.8rem;
      height: 1.8rem;
      font-size: 0.76rem;
    }

    .shell-tools {
      top: 0.8rem;
      right: 0.8rem;
      gap: 0.3rem;
      padding: 0.3rem;
    }

    .shell-tool {
      min-height: 1.9rem;
      padding: 0.42rem 0.58rem;
      font-size: 0.66rem;
    }

    .shell-toast {
      top: 3.8rem;
      left: 0.8rem;
      right: 0.8rem;
      transform: none;
      max-width: none;
    }

    .selection-strip {
      left: 0.8rem;
      right: 0.8rem;
      bottom: calc(0.8rem + env(safe-area-inset-bottom));
      transform: none;
      width: auto;
      grid-template-columns: 1fr;
      gap: 0.6rem;
      padding: 0.68rem 0.72rem;
    }

    .selection-heading h2 {
      font-size: 1.15rem;
    }

    .selection-actions {
      width: 100%;
    }

    .selection-action {
      flex: 1 1 0;
      min-width: 0;
      min-height: 2.35rem;
      padding-inline: 0.72rem;
      font-size: 0.74rem;
    }
  }
</style>
