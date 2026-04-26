defmodule MMGOWeb.OperatorMapLive do
  use MMGOWeb, :live_view

  alias MMGO.Worlds

  def mount(_params, _session, socket) do
    realm = Worlds.get_default_realm()
    locations = if realm, do: Worlds.list_locations_for_realm(realm.id), else: []
    routes = if realm, do: Worlds.list_routes_for_realm(realm.id), else: []

    {:ok,
     assign(socket,
       page_title: "Редактор карты",
       realm: realm,
       locations: locations,
       routes: routes
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main
        id="operator-map-editor"
        phx-hook="OperatorMapEditor"
        class="zip-screen operator-zip"
      >
        <div class="mx-auto grid max-w-7xl gap-5 lg:grid-cols-[1fr_24rem]">
          <section class="operator-panel rounded-lg border p-4">
            <div class="flex items-center justify-between">
              <div>
                <p class="operator-kicker text-xs uppercase tracking-[0.24em]">Оператор</p>
                <h1 class="text-3xl font-bold">Редактор карты мира</h1>
              </div>
              <span class="operator-pill rounded-full border px-3 py-1 text-sm">
                {length(@locations)} точек · {length(@routes)} дорог
              </span>
            </div>
            <div id="operator-map-tools" class="operator-tool-row">
              <button type="button" data-editor-mode="pin" class="is-active">Точки</button>
              <button type="button" data-editor-mode="route">Дороги</button>
              <button type="button" data-clear-route>Очистить линию</button>
            </div>
            <p id="operator-map-message" class="mt-3 min-h-5 text-sm text-red-200"></p>
            <div
              id="operator-map-canvas"
              class="relative mt-5 aspect-square max-h-[72vh] overflow-hidden rounded-md border bg-[url('/images/mmgo2-map.png')] bg-cover bg-center"
            >
              <svg
                id="operator-route-preview"
                class="operator-route-preview"
                viewBox="0 0 2000 2000"
                preserveAspectRatio="none"
              >
                <line
                  :for={route <- @routes}
                  x1={route.origin_location.x}
                  y1={route.origin_location.y}
                  x2={route.destination_location.x}
                  y2={route.destination_location.y}
                >
                </line>
                <polyline id="operator-draft-route"></polyline>
              </svg>
              <div
                :for={location <- @locations}
                id={"operator-pin-#{location.id}"}
                class="operator-map-pin"
                style={"left: #{location.x / 20}%; top: #{location.y / 20}%"}
                data-location-id={location.id}
                data-location-name={location.name}
                data-location-x={location.x}
                data-location-y={location.y}
                title={location.name}
              >
                <span>{location.name}</span>
              </div>
            </div>
          </section>

          <aside class="space-y-4">
            <section class="operator-panel rounded-lg border p-4">
              <h2 class="font-semibold">Создать точку</h2>
              <form
                id="operator-location-form"
                class="mt-3 grid gap-2"
                data-api-path={~p"/api/operator/map/locations"}
              >
                <input name="name" placeholder="Название" class="operator-input" />
                <input name="slug" placeholder="slug" class="operator-input" />
                <select name="kind" class="operator-input">
                  <option value="city">city</option>
                  <option value="tower">tower</option>
                  <option value="wilderness">wilderness</option>
                  <option value="base">base</option>
                  <option value="dungeon_entrance">dungeon entrance</option>
                </select>
                <div class="grid grid-cols-2 gap-2">
                  <input name="x" placeholder="x" class="operator-input" data-location-x />
                  <input name="y" placeholder="y" class="operator-input" data-location-y />
                </div>
                <input
                  name="event_template_code"
                  placeholder="шаблон события"
                  class="operator-input"
                />
                <button type="submit" class="operator-button">Сохранить точку</button>
              </form>
            </section>

            <section class="operator-panel rounded-lg border p-4">
              <h2 class="font-semibold">Создать дорогу</h2>
              <form
                id="operator-route-form"
                class="mt-3 grid gap-2"
                data-api-path={~p"/api/operator/map/routes"}
              >
                <input name="name" placeholder="Название" class="operator-input" />
                <select name="origin_location_id" class="operator-input">
                  <option value="">начало дороги</option>
                  <option :for={location <- @locations} value={location.id}>{location.name}</option>
                </select>
                <select name="destination_location_id" class="operator-input">
                  <option value="">конец дороги</option>
                  <option :for={location <- @locations} value={location.id}>{location.name}</option>
                </select>
                <div class="grid grid-cols-2 gap-2">
                  <input name="travel_days" placeholder="дни" class="operator-input" />
                  <input name="risk_level" placeholder="риск" class="operator-input" />
                </div>
                <select name="road_type" class="operator-input">
                  <option value="major">major</option>
                  <option value="minor">minor</option>
                  <option value="secret">secret</option>
                  <option value="organization">organization</option>
                </select>
                <select name="visibility" class="operator-input">
                  <option value="public">public</option>
                  <option value="secret">secret</option>
                  <option value="organization">organization</option>
                </select>
                <input
                  name="organization_id"
                  placeholder="id организации"
                  class="operator-input"
                />
                <input type="hidden" name="visual_points" data-route-points />
                <button type="submit" class="operator-button">Сохранить дорогу</button>
              </form>
            </section>
          </aside>
        </div>
      </main>
    </Layouts.app>
    """
  end
end
