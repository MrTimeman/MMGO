<script lang="ts">
  import AtlasMap from "./AtlasMap.svelte";
  import PlaceConsole from "./PlaceConsole.svelte";
  import type { DataSource, MapMarker, ShellState } from "../lib/types";

  export let shell: ShellState;
  export let source: DataSource = "mock";

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

  $: routeHelperCopy = selectedIsCurrent
    ? "[Current location helper placeholder]"
    : "[Travel helper placeholder]";

  $: primaryActionLabel = selectedIsCurrent
    ? `Enter ${selectedLocation.name}`
    : `Plot trip to ${selectedLocation.name}`;

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
        <p class="shell-kicker">{shell.map.title}</p>
        <h1>{shell.character.name}</h1>
        <p class="shell-location">
          {shell.realm.name} · {currentLocation.name} · {shell.character.title}
        </p>

        <div class="shell-readout">
          <span>{shell.timerLabel}</span>
          <span>{shell.supplyLabel}</span>
          <span>{shell.weightLabel}</span>
          {#if source === "mock"}
            <span>Mock session</span>
          {/if}
        </div>
      </header>

      <div class="shell-tools">
        <button type="button" class="shell-tool" on:click={centerOnSelf}>Current</button>
        <button type="button" class="shell-tool" on:click={() => (showRoutes = !showRoutes)}>
          {showRoutes ? "Hide routes" : "Show routes"}
        </button>
      </div>

      <section class="selection-strip">
        <div class="selection-copy">
          <p class="selection-kicker">{selectedIsCurrent ? "Current location" : "Selected destination"}</p>
          <h2>{selectedLocation.name}</h2>
          <p class="selection-summary">{selectedLocation.summary}</p>
        </div>

        <div class="selection-context">
          <span>{selectedLocation.travelLabel}</span>
          <p>{routeHelperCopy}</p>
          {#if transientNotice}
            <div class="selection-notice">
              <p>{transientNotice}</p>
              <button type="button" on:click={() => (transientNotice = undefined)}>Dismiss</button>
            </div>
          {/if}
        </div>

        <div class="selection-actions">
          <button type="button" class="selection-action selection-action--primary" on:click={handlePrimaryAction}>
            {primaryActionLabel}
          </button>

          {#if selectedIsCurrent}
            <button
              type="button"
              class="selection-action selection-action--secondary"
              on:click={() => (showRoutes = !showRoutes)}
            >
              {showRoutes ? "Hide route grid" : "Show route grid"}
            </button>
          {:else}
            <button
              type="button"
              class="selection-action selection-action--secondary"
              on:click={centerOnSelf}
            >
              Snap back to {currentLocation.name}
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
  .selection-strip {
    position: absolute;
    z-index: 5;
    border: 1px solid rgba(244, 229, 202, 0.12);
    background: rgba(16, 13, 11, 0.7);
    backdrop-filter: blur(14px);
  }

  .shell-hud {
    top: 1.1rem;
    left: 1.1rem;
    width: min(28rem, calc(100% - 7.4rem));
    padding: 0.95rem 1rem;
    border-radius: 1.35rem;
    display: grid;
    gap: 0.55rem;
  }

  .shell-kicker,
  .shell-location,
  .selection-kicker {
    margin: 0;
    font-family: var(--font-sans);
    text-transform: uppercase;
    letter-spacing: 0.14em;
  }

  .shell-kicker {
    font-size: 0.68rem;
    color: rgba(245, 200, 116, 0.92);
  }

  .shell-hud h1,
  .shell-location,
  .selection-strip h2,
  .selection-summary,
  .selection-context p,
  .selection-notice p {
    margin: 0;
  }

  .shell-hud h1 {
    font-size: clamp(1.3rem, 2vw, 1.7rem);
  }

  .shell-location {
    font-size: 0.68rem;
    color: rgba(240, 233, 214, 0.58);
  }

  .shell-readout {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem 0.7rem;
    font-family: var(--font-sans);
    font-size: 0.76rem;
    color: rgba(240, 233, 214, 0.64);
  }

  .shell-tools {
    top: 1.1rem;
    right: 1.1rem;
    padding: 0.45rem;
    border-radius: 999px;
    display: flex;
    gap: 0.45rem;
  }

  .shell-tool {
    min-height: 2.3rem;
    padding: 0.55rem 0.9rem;
    border: 1px solid rgba(244, 229, 202, 0.12);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.045);
    color: rgba(247, 239, 214, 0.82);
    font-family: var(--font-sans);
    font-size: 0.76rem;
    cursor: pointer;
  }

  .selection-strip {
    left: 1.1rem;
    bottom: 1.1rem;
    width: min(40rem, calc(100% - 7.4rem));
    padding: 1rem 1.05rem;
    border-radius: 1.45rem;
    display: grid;
    gap: 0.8rem;
  }

  .selection-kicker {
    font-size: 0.68rem;
    color: rgba(240, 233, 214, 0.5);
  }

  .selection-strip h2 {
    margin-top: 0.32rem;
    font-size: clamp(1.45rem, 2.8vw, 2rem);
    line-height: 0.96;
  }

  .selection-summary {
    margin-top: 0.45rem;
    color: rgba(247, 239, 214, 0.78);
    line-height: 1.5;
    line-clamp: 2;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .selection-context {
    display: grid;
    gap: 0.35rem;
  }

  .selection-context span {
    font-family: var(--font-sans);
    font-size: 0.72rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: rgba(245, 200, 116, 0.82);
  }

  .selection-context p {
    color: rgba(240, 233, 214, 0.7);
    line-height: 1.55;
  }

  .selection-notice {
    display: grid;
    gap: 0.45rem;
    padding-top: 0.1rem;
  }

  .selection-notice button {
    justify-self: start;
    border: none;
    background: transparent;
    color: rgba(245, 200, 116, 0.86);
    font-family: var(--font-sans);
    font-size: 0.76rem;
    cursor: pointer;
    padding: 0;
  }

  .selection-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.55rem;
  }

  .selection-action {
    min-height: 2.9rem;
    padding: 0.72rem 1rem;
    border: 1px solid rgba(244, 229, 202, 0.08);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.03);
    color: rgba(247, 239, 214, 0.84);
    font-family: var(--font-sans);
    cursor: pointer;
  }

  .selection-action--primary {
    background: linear-gradient(145deg, rgba(98, 49, 18, 0.96), rgba(59, 31, 13, 0.96));
    border-color: rgba(183, 96, 35, 0.44);
    color: rgba(251, 244, 227, 0.94);
  }

  @media (max-width: 700px) {
    .shell-stage {
      padding: 0.6rem;
    }

    :global(.shell-stage > .atlas) {
      inset: 0.6rem;
    }

    .shell-hud {
      top: 1.1rem;
      left: 1.1rem;
      width: calc(100% - 7rem);
      padding: 0.85rem 0.9rem;
    }

    .shell-hud h1 {
      font-size: 1.15rem;
    }

    .shell-readout {
      gap: 0.35rem 0.55rem;
      font-size: 0.69rem;
    }

    .shell-tools {
      top: auto;
      right: 1.1rem;
      bottom: calc(1.1rem + env(safe-area-inset-bottom));
      flex-direction: column;
      border-radius: 1.2rem;
    }

    .shell-tool {
      min-width: 4.75rem;
      justify-content: center;
    }

    .selection-strip {
      left: 1.1rem;
      right: 1.1rem;
      width: auto;
      bottom: calc(1.1rem + env(safe-area-inset-bottom));
      padding: 0.9rem;
      padding-right: 6.2rem;
      gap: 0.7rem;
    }

    .selection-strip h2 {
      font-size: 1.3rem;
    }

    .selection-summary,
    .selection-context p {
      font-size: 0.92rem;
    }

    .selection-actions {
      flex-direction: column;
      align-items: stretch;
    }

    .selection-action {
      width: 100%;
      min-height: 2.7rem;
    }

    .selection-action--secondary {
      background: rgba(255, 255, 255, 0.045);
    }
  }
</style>
