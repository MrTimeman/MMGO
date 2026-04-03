<script lang="ts">
  import type { MapMarker, MapRoute, MapState } from "../lib/types";

  export let map: MapState;
  export let selectedMarkerId: string | null = null;
  export let showRoutes = true;
  export let onSelect: ((marker: MapMarker) => void) | undefined = undefined;
  export let onCenterSelf: (() => void) | undefined = undefined;

  let zoom = 1;
  let offsetX = 0;
  let offsetY = 0;
  let dragging = false;
  let pointerId: number | null = null;
  let dragStartX = 0;
  let dragStartY = 0;

  const accentPalette: Record<string, string> = {
    amber: "#f59e0b",
    ivory: "#f2d9b6",
    cyan: "#8bc7c6",
    sage: "#8ca96f",
    red: "#d97856",
    rose: "#cf8a7a"
  };

  $: markers = map?.markers ?? [];
  $: routes = map?.routes ?? [];
  $: playerMarkerId = map?.playerMarkerId ?? null;

  $: selectedMarker =
    markers.find((marker) => marker.id === selectedMarkerId) ??
    markers.find((marker) => marker.id === playerMarkerId) ??
    markers[0] ??
    null;

  $: markerById = new Map(markers.map((marker) => [marker.id, marker]));

  $: routeSegments = routes
    .map((route) => buildRoute(route, markerById))
    .filter((route): route is RouteSegment => route !== null);

  type RouteSegment = {
    id: string;
    kind: MapRoute["kind"];
    fromX: number;
    fromY: number;
    toX: number;
    toY: number;
    focused: boolean;
  };

  function buildRoute(route: MapRoute, markers: Map<string, MapMarker>): RouteSegment | null {
    const from = markers.get(route.from);
    const to = markers.get(route.to);

    if (!from || !to) {
      return null;
    }

    const focused =
      selectedMarker?.id != null &&
      selectedMarker.id !== playerMarkerId &&
      ((route.from === playerMarkerId && route.to === selectedMarker.id) ||
        (route.to === playerMarkerId && route.from === selectedMarker.id));

    return {
      id: route.id,
      kind: route.kind,
      fromX: from.x,
      fromY: from.y,
      toX: to.x,
      toY: to.y,
      focused
    };
  }

  function isInteractiveTarget(target: EventTarget | null): boolean {
    return target instanceof HTMLElement && Boolean(target.closest("button, a, input, textarea, select"));
  }

  function startDrag(event: PointerEvent): void {
    if (isInteractiveTarget(event.target)) {
      return;
    }

    const viewport = event.currentTarget as HTMLDivElement;

    pointerId = event.pointerId;
    dragging = true;
    dragStartX = event.clientX - offsetX;
    dragStartY = event.clientY - offsetY;
    viewport.setPointerCapture(event.pointerId);
  }

  function continueDrag(event: PointerEvent): void {
    if (!dragging || pointerId !== event.pointerId) {
      return;
    }

    offsetX = event.clientX - dragStartX;
    offsetY = event.clientY - dragStartY;
  }

  function stopDrag(event?: PointerEvent): void {
    if (event && pointerId !== event.pointerId) {
      return;
    }

    dragging = false;
    pointerId = null;
  }

  function onWheel(event: WheelEvent): void {
    event.preventDefault();
    const next = zoom - event.deltaY * 0.0012;
    zoom = Math.min(2.4, Math.max(0.88, next));
  }

  function adjustZoom(direction: 1 | -1): void {
    const next = zoom + direction * 0.14;
    zoom = Math.min(2.4, Math.max(0.88, next));
  }
</script>

<section class="atlas">
  <div
    class="atlas-viewport"
    role="application"
    aria-label="Realm atlas"
    on:wheel={onWheel}
    on:pointerdown={startDrag}
    on:pointermove={continueDrag}
    on:pointerup={stopDrag}
    on:pointercancel={stopDrag}
    on:pointerleave={stopDrag}
  >
    <div
      class="atlas-surface"
      class:atlas-surface--image={Boolean(map.imageUrl)}
      style={`--atlas-zoom:${zoom}; --atlas-offset-x:${offsetX}px; --atlas-offset-y:${offsetY}px; ${map.imageUrl ? `background-image:url(${map.imageUrl});` : ""}`}
    >
      {#if showRoutes}
        <svg class="atlas-routes" viewBox="0 0 100 100" aria-hidden="true">
          {#each routeSegments as route}
            <path
              d={`M ${route.fromX} ${route.fromY} L ${route.toX} ${route.toY}`}
              class:atlas-route--focused={route.focused}
              class:atlas-route--wilds={route.kind === "wilds"}
              class:atlas-route--expedition={route.kind === "expedition"}
            />
          {/each}
        </svg>
      {/if}

      {#each markers as marker}
        <button
          type="button"
          class="atlas-marker"
          class:atlas-marker--player={marker.id === playerMarkerId}
          class:atlas-marker--selected={selectedMarker?.id === marker.id}
          style={`left:${marker.x}%; top:${marker.y}%; --marker-accent:${accentPalette[marker.accent] ?? "#f59e0b"};`}
          aria-pressed={selectedMarker?.id === marker.id}
          on:click|stopPropagation={() => onSelect?.(marker)}
        >
          <span class="atlas-marker-core"></span>
          <span class="atlas-marker-name">
            <strong>{marker.name}</strong>
            <small>{marker.region}</small>
          </span>
        </button>
      {/each}
    </div>

    <div class="atlas-controls">
      <button type="button" aria-label="Zoom out" on:click={() => adjustZoom(-1)}>-</button>
      <span>{Math.round(zoom * 100)}%</span>
      <button type="button" aria-label="Zoom in" on:click={() => adjustZoom(1)}>+</button>
      <button type="button" class="atlas-controls-reset" on:click={() => onCenterSelf?.()}>
        Reset
      </button>
    </div>
  </div>
</section>

<style>
  .atlas {
    width: 100%;
    height: 100%;
  }

  .atlas-viewport {
    position: relative;
    width: 100%;
    height: 100%;
    overflow: hidden;
    border-radius: 1.8rem;
    border: 1px solid rgba(244, 229, 202, 0.14);
    background:
      radial-gradient(circle at top, rgba(245, 158, 11, 0.08), transparent 28rem),
      linear-gradient(180deg, #16120f, #0d0b0a);
    cursor: grab;
    touch-action: none;
    box-shadow:
      inset 0 0 0 1px rgba(255, 255, 255, 0.02),
      0 1.2rem 3rem rgba(0, 0, 0, 0.22);
  }

  .atlas-viewport:active {
    cursor: grabbing;
  }

  .atlas-surface {
    position: absolute;
    inset: 50% auto auto 50%;
    width: min(96rem, calc(100dvw - 1.6rem), calc(100dvh - 1.6rem));
    aspect-ratio: 1;
    transform: translate(calc(-50% + var(--atlas-offset-x)), calc(-50% + var(--atlas-offset-y)))
      scale(var(--atlas-zoom));
    transform-origin: center;
    background:
      radial-gradient(circle at 78% 18%, rgba(109, 177, 184, 0.75), rgba(53, 97, 103, 0.92) 30%, transparent 31%),
      radial-gradient(circle at 84% 78%, rgba(65, 107, 52, 0.86), transparent 22%),
      radial-gradient(circle at 26% 28%, rgba(98, 88, 61, 0.8), transparent 18%),
      linear-gradient(180deg, rgba(98, 157, 160, 0.92) 0 17%, rgba(95, 143, 81, 0.96) 17% 100%);
    background-size: cover;
    background-position: center;
    box-shadow:
      0 0 0 1px rgba(245, 222, 179, 0.12),
      0 1rem 2.2rem rgba(0, 0, 0, 0.22);
  }

  .atlas-surface--image {
    background-repeat: no-repeat;
  }

  .atlas-surface::before,
  .atlas-surface::after {
    content: "";
    position: absolute;
    inset: 0;
    pointer-events: none;
  }

  .atlas-surface::before {
    background: radial-gradient(circle at center, transparent 64%, rgba(10, 8, 7, 0.08) 100%);
  }

  .atlas-surface::after {
    background:
      linear-gradient(180deg, rgba(7, 10, 10, 0.03), rgba(7, 10, 10, 0.16)),
      radial-gradient(circle at center, rgba(255, 247, 224, 0.04), transparent 48%);
  }

  .atlas-routes {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }

  .atlas-routes path {
    fill: none;
    stroke: rgba(247, 239, 214, 0.34);
    stroke-width: 0.28;
    stroke-linecap: round;
    stroke-dasharray: 0.7 1.1;
  }

  .atlas-route--wilds {
    stroke-opacity: 0.75;
  }

  .atlas-route--expedition {
    stroke-opacity: 0.5;
  }

  .atlas-route--focused {
    stroke: rgba(245, 198, 118, 0.94);
    stroke-width: 0.42;
    stroke-dasharray: none;
    filter: drop-shadow(0 0 0.35rem rgba(245, 158, 11, 0.42));
  }

  .atlas-marker {
    position: absolute;
    transform: translate(-50%, -50%);
    border: none;
    background: transparent;
    color: #f6efe0;
    display: grid;
    gap: 0.35rem;
    justify-items: start;
    cursor: pointer;
    padding: 0;
  }

  .atlas-marker-core {
    width: 1.15rem;
    height: 1.15rem;
    border-radius: 999px;
    border: 2px solid rgba(251, 244, 227, 0.92);
    background: color-mix(in srgb, var(--marker-accent) 62%, #2a1e16);
    box-shadow:
      0 0 0 0.18rem rgba(15, 13, 12, 0.4),
      0 0 0 rgba(245, 158, 11, 0);
    transition:
      transform 160ms ease,
      box-shadow 160ms ease,
      background 160ms ease;
  }

  .atlas-marker-name {
    display: grid;
    gap: 0.1rem;
    padding: 0.38rem 0.58rem 0.42rem;
    border-radius: 0.9rem;
    background: rgba(20, 16, 13, 0.82);
    border: 1px solid rgba(244, 229, 202, 0.14);
    backdrop-filter: blur(8px);
    opacity: 0;
    transform: translateY(0.25rem);
    transition:
      opacity 140ms ease,
      transform 140ms ease;
    pointer-events: none;
    white-space: nowrap;
  }

  .atlas-marker-name strong,
  .atlas-marker-name small {
    display: block;
  }

  .atlas-marker-name strong {
    font-family: var(--font-display);
    font-size: 0.9rem;
    line-height: 1;
  }

  .atlas-marker-name small {
    font-family: var(--font-sans);
    font-size: 0.63rem;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    color: rgba(240, 233, 214, 0.56);
  }

  .atlas-marker:hover .atlas-marker-core,
  .atlas-marker--selected .atlas-marker-core {
    transform: scale(1.05);
    box-shadow:
      0 0 0 0.18rem rgba(15, 13, 12, 0.4),
      0 0 1.1rem color-mix(in srgb, var(--marker-accent) 36%, transparent);
  }

  .atlas-marker:hover .atlas-marker-name,
  .atlas-marker--selected .atlas-marker-name,
  .atlas-marker--player .atlas-marker-name {
    opacity: 1;
    transform: translateY(0);
  }

  .atlas-marker--player .atlas-marker-core {
    background: linear-gradient(145deg, rgba(245, 158, 11, 0.98), rgba(180, 83, 9, 0.98));
    box-shadow:
      0 0 0 0.2rem rgba(15, 13, 12, 0.48),
      0 0 1.25rem rgba(245, 158, 11, 0.3);
  }

  .atlas-controls {
    position: absolute;
    z-index: 2;
    right: 1rem;
    bottom: 1rem;
    display: flex;
    align-items: center;
    gap: 0.45rem;
    padding: 0.45rem;
    border-radius: 999px;
    border: 1px solid rgba(244, 229, 202, 0.12);
    background: rgba(16, 13, 11, 0.72);
    backdrop-filter: blur(12px);
    color: rgba(240, 233, 214, 0.74);
    font-family: var(--font-sans);
    font-size: 0.74rem;
  }

  .atlas-controls button {
    min-width: 2.1rem;
    min-height: 2.1rem;
    border: 1px solid rgba(244, 229, 202, 0.12);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.05);
    color: inherit;
    cursor: pointer;
  }

  .atlas-controls-reset {
    padding-inline: 0.85rem;
  }

  @media (hover: none) and (pointer: coarse) {
    .atlas-marker:hover .atlas-marker-name {
      opacity: 0;
      transform: translateY(0.25rem);
    }
  }

  @media (max-width: 700px) {
    .atlas-viewport {
      border-radius: 1.2rem;
    }

    .atlas-surface {
      width: min(calc(100dvw - 0.7rem), calc(100dvh - 0.7rem), 92rem);
    }

    .atlas-marker-core {
      width: 1rem;
      height: 1rem;
    }

    .atlas-controls {
      right: 0.7rem;
      bottom: 0.7rem;
      gap: 0.35rem;
      padding: 0.35rem;
    }

    .atlas-controls span {
      display: none;
    }

    .atlas-controls button {
      min-width: 1.95rem;
      min-height: 1.95rem;
    }

    .atlas-controls-reset {
      padding-inline: 0.7rem;
    }
  }
</style>
