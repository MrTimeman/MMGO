import L from "leaflet"

// MapHook — Leaflet-powered world map
//
// Usage in a LiveView template:
//   <div id="world-map" phx-hook="Map" phx-update="ignore" class="..."></div>
//
// The server pushes events to control the map:
//   push_event(socket, "map_init", %{width: 4096, height: 4096, image_url: "..."})
//   push_event(socket, "map_marker_add", %{id: "city_1", lat: 512, lng: 256, label: "Ironhold"})
//   push_event(socket, "map_marker_remove", %{id: "city_1"})
//   push_event(socket, "map_player_move", %{lat: 512, lng: 256})
//
// The hook pushes clicks back to the server:
//   handle_event("map_click", %{"lat" => lat, "lng" => lng}, socket)

export const MapHook = {
  mounted() {
    const map = L.map(this.el, {
      crs: L.CRS.Simple,       // game coordinate system — no geographic projection
      minZoom: -2,
      maxZoom: 4,
      zoomControl: true,
      attributionControl: false,
    })

    this._map = map
    this._markers = {}
    this._playerMarker = null

    this.pushEvent('hook_mounted', { hook: 'Map' })

    // Server → client: initialize the map with a world image
    this.handleEvent("map_init", ({ width, height, image_url }) => {
      const bounds = [[0, 0], [height, width]]
      L.imageOverlay(image_url, bounds).addTo(map)
      map.fitBounds(bounds)
    })

    // Server → client: add or update a named marker (location, NPC, etc.)
    this.handleEvent("map_marker_add", ({ id, lat, lng, label, icon_class }) => {
      if (this._markers[id]) this._markers[id].remove()
      const marker = L.marker([lat, lng], { title: label })
      if (label) marker.bindTooltip(label, { permanent: false, direction: "top" })
      marker.addTo(map)
      this._markers[id] = marker
    })

    // Server → client: remove a named marker
    this.handleEvent("map_marker_remove", ({ id }) => {
      if (this._markers[id]) {
        this._markers[id].remove()
        delete this._markers[id]
      }
    })

    // Server → client: move the player marker
    this.handleEvent("map_player_move", ({ lat, lng }) => {
      if (this._playerMarker) {
        this._playerMarker.setLatLng([lat, lng])
      } else {
        this._playerMarker = L.circleMarker([lat, lng], {
          radius: 8,
          fillColor: "#f59e0b",
          color: "#92400e",
          weight: 2,
          fillOpacity: 1,
        }).addTo(map)
      }
      map.panTo([lat, lng])
    })

    // Client → server: player clicked a map coordinate
    map.on("click", (e) => {
      this.pushEvent("map_click", { lat: e.latlng.lat, lng: e.latlng.lng })
    })
  },

  destroyed() {
    if (this._map) {
      this._map.remove()
      this._map = null
    }
  },
}
