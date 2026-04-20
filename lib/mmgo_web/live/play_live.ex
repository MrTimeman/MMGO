defmodule MMGOWeb.PlayLive do
  use MMGOWeb, :live_view

  @screens ["map", "location", "base", "magic", "grimoire", "combat", "academy"]
  @academy_tabs ["yard", "schedule", "clubs", "enrollment"]

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "MMGO")
     |> assign(:active_screen, "map")
     |> assign(:academy_tab, "yard")
     |> assign(:map_night, false)
     |> assign(:grimoire_layout, "shelves")
     |> assign(:selected_word_family, "actio")
     |> assign(:combat_action_id, "spell")
     |> assign(:combat_target_id, "reaper")
     |> assign(:combat_plan_id, "cast")
     |> assign(:telegram_context, default_telegram_context())
     |> assign(:clubs, clubs())
     |> assign(:selected_spellbook, "red")}
  end

  def handle_event("switch_screen", %{"screen" => screen}, socket) when screen in @screens do
    {:noreply, assign(socket, :active_screen, screen)}
  end

  def handle_event("set_academy_tab", %{"tab" => tab}, socket) when tab in @academy_tabs do
    {:noreply, assign(socket, :academy_tab, tab)}
  end

  def handle_event("toggle_map_night", _params, socket) do
    {:noreply, update(socket, :map_night, &(!&1))}
  end

  def handle_event("set_grimoire_layout", %{"layout" => layout}, socket)
      when layout in ["shelves", "catalog"] do
    {:noreply, assign(socket, :grimoire_layout, layout)}
  end

  def handle_event("select_word_family", %{"family" => family}, socket) do
    {:noreply, assign(socket, :selected_word_family, family)}
  end

  def handle_event("select_combat_action", %{"action" => action}, socket) do
    if Enum.any?(combat_actions(), &(&1.id == action)) do
      {:noreply, assign(socket, :combat_action_id, action)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_combat_target", %{"target" => target}, socket) do
    if Enum.any?(combat_targets(), &(&1.id == target)) do
      {:noreply, assign(socket, :combat_target_id, target)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_combat_plan", %{"plan" => plan}, socket) do
    if Enum.any?(combat_plans(), &(&1.id == plan)) do
      {:noreply, assign(socket, :combat_plan_id, plan)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_spellbook", %{"book" => book}, socket) do
    {:noreply, assign(socket, :selected_spellbook, book)}
  end

  def handle_event("toggle_club", %{"club" => club_id}, socket) do
    clubs =
      Enum.map(socket.assigns.clubs, fn club ->
        if club.id == club_id, do: %{club | joined?: !club.joined?}, else: club
      end)

    {:noreply, assign(socket, :clubs, clubs)}
  end

  def handle_event("telegram_ready", params, socket) do
    telegram_context = %{
      mode: :telegram,
      platform: Map.get(params, "platform", "telegram"),
      color_scheme: Map.get(params, "color_scheme", "dark"),
      viewport_height: parse_integer(Map.get(params, "viewport_height")),
      expanded?: truthy?(Map.get(params, "is_expanded"))
    }

    {:noreply, assign(socket, :telegram_context, telegram_context)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <section
        id="play-shell"
        class="min-h-screen bg-[#1d1a16] px-4 py-6 text-[#2e241d] sm:px-6"
        data-client-mode={client_mode(@telegram_context)}
        data-color-scheme={@telegram_context.color_scheme}
        data-platform={@telegram_context.platform}
        phx-hook=".TelegramShell"
      >
        <script :type={Phoenix.LiveView.ColocatedHook} name=".TelegramShell">
          const viewportHeight = webApp => {
            const raw = webApp?.viewportStableHeight ?? webApp?.viewportHeight ?? window.innerHeight

            if (typeof raw === "number" && Number.isFinite(raw)) {
              return `${raw}px`
            }

            return `${window.innerHeight}px`
          }

          const applyViewport = (el, webApp) => {
            el.style.setProperty("--tg-viewport-height", viewportHeight(webApp))
          }

          export default {
            mounted() {
              this.handleResize = () => applyViewport(this.el, window.Telegram?.WebApp)
              window.addEventListener("resize", this.handleResize)
              this.handleResize()

              const telegram = window.Telegram?.WebApp
              this.el.dataset.clientMode = telegram ? "telegram" : "browser"

              if (!telegram) {
                return
              }

              telegram.ready?.()
              telegram.expand?.()
              telegram.disableVerticalSwipes?.()
              telegram.setBackgroundColor?.("#1d1a16")
              telegram.setHeaderColor?.("#1d1a16")

              this.handleThemeChange = () => {
                this.el.dataset.colorScheme = telegram.colorScheme || "dark"
                applyViewport(this.el, telegram)
              }

              this.handleViewportChange = () => applyViewport(this.el, telegram)

              telegram.onEvent?.("themeChanged", this.handleThemeChange)
              telegram.onEvent?.("viewportChanged", this.handleViewportChange)

              this.handleThemeChange()

              this.pushEvent("telegram_ready", {
                platform: telegram.platform || "telegram",
                color_scheme: telegram.colorScheme || "dark",
                viewport_height: Math.round(parseFloat(viewportHeight(telegram))),
                is_expanded: Boolean(telegram.isExpanded)
              })
            },

            destroyed() {
              window.removeEventListener("resize", this.handleResize)

              const telegram = window.Telegram?.WebApp

              if (!telegram) {
                return
              }

              telegram.offEvent?.("themeChanged", this.handleThemeChange)
              telegram.offEvent?.("viewportChanged", this.handleViewportChange)
            }
          }
        </script>

        <%= if @active_screen == "map" do %>
          <div class="mx-auto grid max-w-[1280px] gap-4 xl:grid-cols-[minmax(0,1fr)_430px] xl:gap-6">
            <section class="relative overflow-hidden rounded-[2.25rem] bg-[#27211b] shadow-[0_40px_120px_rgba(0,0,0,0.45)]">
              <div class="relative h-[31rem] overflow-hidden rounded-[2rem] border border-white/10 sm:h-[38rem] xl:h-[72vh] xl:min-h-[42rem]">
                <div class="absolute inset-0 bg-[radial-gradient(circle_at_top,_rgba(255,255,255,0.08),_transparent_35%),linear-gradient(180deg,_rgba(255,255,255,0.02),_rgba(0,0,0,0.22))]">
                </div>
                <div id="play-hub-root-wrap" class="relative h-full">
                  <div
                    id="play-hub-root"
                    phx-hook="PlayHub"
                    class="h-full"
                    data-play-hub-root
                    data-state-path={~p"/api/play/state"}
                    data-journeys-path={~p"/api/play/journeys"}
                    data-utility-spells-path={~p"/api/play/utility-spells"}
                    data-demo-reset-path={~p"/api/play/demo/reset"}
                    data-home-path={~p"/"}
                  >
                  </div>
                  <%= if @map_night do %>
                    <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_center,_transparent_20%,_rgba(10,16,38,0.45)_100%)]">
                    </div>
                  <% end %>
                  <div class={[
                    "pointer-events-none absolute right-4 top-4 flex size-14 items-center justify-center rounded-full border text-base shadow-[0_10px_30px_rgba(0,0,0,0.35)] sm:right-6 sm:top-6 sm:size-16 xl:right-8 xl:top-8 xl:size-20 xl:text-lg",
                    if(@map_night,
                      do: "border-[#9c95c8] bg-[#2e3054]/90 text-[#f4e6c2]",
                      else: "border-[#d4b27a] bg-[#f0dfba]/92 text-[#94352b]"
                    )
                  ]}>
                    ✦
                  </div>
                </div>
              </div>
            </section>

            <aside class="rounded-[2rem] border border-[#5a4a3d] bg-[#241d18] p-5 text-[#efe3c9] shadow-[0_30px_100px_rgba(0,0,0,0.34)] sm:p-6 xl:p-7">
              <h2 class="font-['Cormorant_Garamond'] text-3xl font-semibold leading-none sm:text-4xl xl:text-5xl">
                Tweaks
              </h2>
              <div class="my-4 h-px bg-[#6a5849] xl:my-6"></div>

              <div class="space-y-6">
                <div class="space-y-3">
                  <div class="flex items-center justify-between">
                    <p class="font-['Cormorant_Garamond'] text-2xl font-semibold leading-none sm:text-[2rem] xl:text-[2.2rem]">
                      Ночь на карте
                    </p>
                    <button
                      id="map-night-toggle"
                      type="button"
                      phx-click="toggle_map_night"
                      class={[
                        "flex h-8 w-8 items-center justify-center rounded-md border text-sm transition",
                        if(@map_night,
                          do: "border-[#7ba1ff] bg-[#2b5ebd] text-white",
                          else: "border-[#8a7868] bg-[#f6ecd6] text-[#2e241d]"
                        )
                      ]}
                    >
                      <%= if @map_night do %>
                        ✓
                      <% end %>
                    </button>
                  </div>
                </div>

                <div class="my-4 h-px bg-[#6a5849] xl:my-6"></div>

                <div class="space-y-3">
                  <p class="text-lg font-semibold text-[#d8c7aa] sm:text-xl">Вид гримуаров</p>
                  <div class="grid grid-cols-2 gap-3">
                    <.toggle_button
                      id="grimoire-shelves"
                      active={@grimoire_layout == "shelves"}
                      label="Полки"
                      click="set_grimoire_layout"
                      value="shelves"
                    />
                    <.toggle_button
                      id="grimoire-catalog"
                      active={@grimoire_layout == "catalog"}
                      label="Каталог"
                      click="set_grimoire_layout"
                      value="catalog"
                    />
                  </div>
                </div>

                <div class="my-4 h-px bg-[#6a5849] xl:my-6"></div>

                <div class="space-y-4">
                  <p class="text-lg italic text-[#d8c7aa] sm:text-xl">
                    Быстрая навигация для проверки дизайна:
                  </p>
                  <div class="grid grid-cols-2 gap-3">
                    <.screen_button
                      id="play-nav-map"
                      active={@active_screen == "map"}
                      label="Карта"
                      screen="map"
                    />
                    <.screen_button
                      id="play-nav-location"
                      active={false}
                      label="Событие"
                      screen="location"
                    />
                    <.screen_button id="play-nav-base" active={false} label="База" screen="base" />
                    <.screen_button
                      id="play-nav-magic"
                      active={false}
                      label="Круг"
                      screen="magic"
                    />
                    <.screen_button
                      id="play-nav-grimoire"
                      active={false}
                      label="Гримуар"
                      screen="grimoire"
                    />
                    <.screen_button
                      id="play-nav-combat"
                      active={false}
                      label="Бой"
                      screen="combat"
                    />
                    <.screen_button
                      id="play-nav-academy"
                      active={false}
                      label="Академия"
                      screen="academy"
                    />
                  </div>
                </div>
              </div>
            </aside>
          </div>
        <% else %>
          <div class="mx-auto max-w-[860px]">
            <div class="rounded-[2.5rem] bg-[#f3e6cd] p-4 shadow-[0_40px_120px_rgba(0,0,0,0.35)]">
              <div class="min-h-[78vh] rounded-[2.2rem] border border-[#d7c4a4] bg-[radial-gradient(circle_at_top,_rgba(255,255,255,0.5),_transparent_18%),linear-gradient(180deg,_#f8eedb,_#eadabf)] px-7 pb-12 pt-6 shadow-[inset_0_2px_10px_rgba(255,255,255,0.35)]">
                <%= case @active_screen do %>
                  <% "location" -> %>
                    <.location_screen />
                  <% "base" -> %>
                    <.base_screen />
                  <% "magic" -> %>
                    <.magic_screen selected_word_family={@selected_word_family} />
                  <% "grimoire" -> %>
                    <.grimoire_screen
                      grimoire_layout={@grimoire_layout}
                      selected_spellbook={@selected_spellbook}
                    />
                  <% "combat" -> %>
                    <.combat_screen
                      combat_action_id={@combat_action_id}
                      combat_target_id={@combat_target_id}
                      combat_plan_id={@combat_plan_id}
                    />
                  <% "academy" -> %>
                    <.academy_screen academy_tab={@academy_tab} clubs={@clubs} />
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :screen, :string, required: true

  defp screen_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="switch_screen"
      phx-value-screen={@screen}
      class={[
        "rounded-2xl border px-4 py-3 text-base font-semibold transition sm:px-5 sm:py-4 sm:text-lg xl:text-xl",
        if(@active,
          do: "border-[#d26c57] bg-[#9f2f2c] text-[#f9e9db]",
          else: "border-[#6d5d4d] bg-[#342c25] text-[#f0e1c7] hover:bg-[#41362e]"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :click, :string, required: true
  attr :value, :string, required: true

  defp toggle_button(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click={@click}
      phx-value-layout={@value}
      class={[
        "rounded-2xl border px-4 py-3 text-lg font-semibold transition sm:px-5 sm:text-2xl",
        if(@active,
          do: "border-[#d26c57] bg-[#9f2f2c] text-[#f9e9db]",
          else: "border-[#85705b] bg-[#43382f] text-[#e8d9bc]"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp parchment_heading(assigns) do
    ~H"""
    <div class="mb-5 text-center">
      <div class="flex items-center gap-5">
        <div class="h-px flex-1 bg-[#b7a68d]"></div>
        <h1 class="font-['Cormorant_Garamond'] text-6xl font-semibold leading-none tracking-[0.01em] text-[#2d241d]">
          {@title}
        </h1>
        <div class="h-px flex-1 bg-[#b7a68d]"></div>
      </div>
      <%= if @subtitle do %>
        <p class="mt-2 font-['Cormorant_Garamond'] text-4xl italic text-[#7d7164]">{@subtitle}</p>
      <% end %>
    </div>
    """
  end

  defp location_screen(assigns) do
    ~H"""
    <.parchment_heading title="Хутор" subtitle="Ваша база" />
    <div class="overflow-hidden rounded-[1.7rem] border border-[#ae8f76] bg-[repeating-linear-gradient(45deg,_rgba(140,92,62,0.18),_rgba(140,92,62,0.18)_14px,_rgba(250,241,228,0)_14px,_rgba(250,241,228,0)_28px)] shadow-[inset_0_0_0_1px_rgba(90,50,30,0.12),0_8px_24px_rgba(80,50,20,0.15)]">
      <div class="flex h-52 items-end p-6">
        <p class="font-['Cormorant_Garamond'] text-5xl uppercase tracking-[0.15em] text-[#f4ead8]">
          Дом
        </p>
      </div>
    </div>

    <div class="mx-auto mt-8 max-w-[690px] text-center">
      <p class="text-left font-['Cormorant_Garamond'] text-[3.35rem] leading-[1.34] text-[#2a2019]">
        <span class="float-left mr-3 text-[5.4rem] leading-none text-[#9c2a24]">С</span>
        крипит калитка. Пёс без одного уха привычно не гавкает. На крыльце
        чей-то оставленный вчера свёрток; запах трав подсказывает, что это,
        скорее всего, от аптекаря.
      </p>
    </div>

    <div class="my-8 flex items-center gap-4">
      <div class="h-px flex-1 bg-[#d5c6ae]"></div>
      <div class="text-xl text-[#a89880]">◆</div>
      <div class="h-px flex-1 bg-[#d5c6ae]"></div>
    </div>

    <div class="space-y-5">
      <.parchment_action
        id="location-enter-home"
        primary={true}
        label="Войти в дом"
        screen="base"
      />
      <.parchment_action id="location-workshop" label="В мастерскую" screen="base" />
      <.parchment_action id="location-garden" label="Огород и запасы" screen="base" />
      <.parchment_action id="location-back-map" label="Обратно на карту" screen="map" />
    </div>
    """
  end

  defp base_screen(assigns) do
    ~H"""
    <.parchment_heading
      title="Дом на хуторе"
      subtitle="У вас 3 дн. припасов · вес 8/20"
    />
    <div class="space-y-5">
      <.base_tile
        id="base-circle"
        title="Круг призыва"
        subtitle="Создание заклинаний"
        icon="△"
        accent={true}
        screen="magic"
      />
      <.base_tile
        id="base-shelves"
        title="Полки с гримуарами"
        subtitle="3 книги · 24 заклинания"
        icon="📚"
        screen="grimoire"
      />
      <.base_tile
        id="base-chest"
        title="Сундук"
        subtitle="42 предмета · 8/20 кг"
        icon="▣"
        screen="base"
      />
      <.base_tile
        id="base-alchemy"
        title="Алхимический стол"
        subtitle="Варка · зельеварение"
        icon="⚗"
        screen="academy"
      />
      <.base_tile
        id="base-workshop"
        title="Мастерская"
        subtitle="Починка · ремёсла"
        icon="⌁"
        screen="academy"
      />
      <.base_tile
        id="base-bed"
        title="Кровать"
        subtitle="Отдохнуть до рассвета"
        icon="⌂"
        screen="location"
      />
    </div>
    <div class="mt-8 flex items-center gap-4">
      <div class="h-px flex-1 bg-[#d5c6ae]"></div>
      <div class="text-xl text-[#a89880]">◆</div>
      <div class="h-px flex-1 bg-[#d5c6ae]"></div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :screen, :string, required: true
  attr :primary, :boolean, default: false

  defp parchment_action(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="switch_screen"
      phx-value-screen={@screen}
      class={[
        "w-full rounded-[1.55rem] border px-7 py-6 text-left font-['Cormorant_Garamond'] text-5xl shadow-[0_6px_18px_rgba(80,50,20,0.12)] transition",
        if(@primary,
          do: "border-[#7b211d] bg-[linear-gradient(180deg,_#aa332d,_#8f1f1e)] text-[#f8ece1]",
          else:
            "border-[#b9a78c] bg-[linear-gradient(180deg,_#f6ebd8,_#ecdcc0)] text-[#30241d] hover:bg-[linear-gradient(180deg,_#faf0df,_#eeddc2)]"
        )
      ]}
    >
      {@label}
    </button>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :icon, :string, required: true
  attr :screen, :string, required: true
  attr :accent, :boolean, default: false

  defp base_tile(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="switch_screen"
      phx-value-screen={@screen}
      class={[
        "flex w-full items-center gap-6 rounded-[1.65rem] border px-6 py-6 text-left shadow-[0_8px_24px_rgba(80,50,20,0.12)] transition",
        if(@accent,
          do:
            "border-[#b59ce4] bg-[linear-gradient(180deg,_#efe7f7,_#ede3f5)] shadow-[0_0_0_1px_rgba(174,145,235,0.6)]",
          else:
            "border-[#b9a78c] bg-[linear-gradient(180deg,_#f5ead7,_#ead9bc)] hover:bg-[linear-gradient(180deg,_#f8eedf,_#ecddc4)]"
        )
      ]}
    >
      <div class="flex size-28 shrink-0 items-center justify-center rounded-[1.45rem] border border-[#aa9070] bg-[linear-gradient(180deg,_#d8c19e,_#ccb18a)] text-5xl text-[#3a2b20] shadow-[inset_0_1px_2px_rgba(255,255,255,0.3)]">
        {@icon}
      </div>
      <div class="min-w-0 flex-1">
        <p class="font-['Cormorant_Garamond'] text-6xl font-semibold leading-none text-[#231b15]">
          {@title}
        </p>
        <p class="mt-2 font-['Cormorant_Garamond'] text-4xl italic text-[#5f5045]">{@subtitle}</p>
      </div>
      <div class="text-6xl text-[#8a7868]">›</div>
    </button>
    """
  end

  attr :selected_word_family, :string, required: true

  defp magic_screen(assigns) do
    ~H"""
    <.parchment_heading
      title="Круг призыва"
      subtitle="«Слова — это сосуды. Сосуды держат намерение»."
    />

    <div class="relative mx-auto aspect-square max-w-[640px]">
      <div class="absolute inset-[8%] rounded-full border border-[#bbb09d]"></div>
      <div class="absolute inset-[18%] rounded-full border-4 border-dashed border-[#d98976]"></div>
      <div class="absolute inset-[32%] flex items-center justify-center">
        <div class="relative flex size-full items-center justify-center">
          <div class="absolute h-[54%] w-[54%] border-[3px] border-[#de8c74] [clip-path:polygon(50%_0%,0%_100%,100%_100%)]">
          </div>
          <div class="flex size-[34%] items-center justify-center rounded-full border-[3px] border-[#de8c74] text-6xl text-[#b93c1d]">
            △
          </div>
        </div>
      </div>

      <div
        :for={slot <- circle_slots()}
        class="absolute flex size-32 -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-full border-[4px] bg-[linear-gradient(180deg,_#f7efdf,_#e8ddcb)] text-center shadow-[0_6px_18px_rgba(80,50,20,0.18)]"
        style={"top: #{slot.top}; left: #{slot.left}; border-color: #{slot.border};"}
      >
        <p class="text-xl uppercase tracking-[0.16em] text-[#6a635d]">{slot.name}</p>
        <p class="text-6xl text-[#9c9084]">{slot.index}</p>
      </div>

      <div class="absolute bottom-[4%] left-1/2 flex -translate-x-1/2 gap-4">
        <button
          :for={family <- word_families()}
          id={"word-family-#{family.id}"}
          type="button"
          phx-click="select_word_family"
          phx-value-family={family.id}
          class={[
            "flex size-16 items-center justify-center rounded-full border text-2xl shadow-[0_4px_12px_rgba(80,50,20,0.12)]",
            if(@selected_word_family == family.id,
              do:
                "border-[#d45f47] bg-[#cb4a2a] text-[#fff3e8] shadow-[0_0_18px_rgba(210,89,59,0.5)]",
              else: "border-[#b4a289] bg-[linear-gradient(180deg,_#f9efdf,_#eadfc8)] text-[#7d6756]"
            )
          ]}
        >
          {family.icon}
        </button>
      </div>
    </div>

    <div class="mt-8 rounded-[1.7rem] border border-[#b8a68c] bg-[linear-gradient(180deg,_#f7efdf,_#ebddc5)] p-6 shadow-[0_8px_24px_rgba(80,50,20,0.12)]">
      <div class="flex items-center justify-between gap-4">
        <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Слог I. Действие</p>
        <p class="font-['Cormorant_Garamond'] text-4xl italic text-[#7d7164]">что делает</p>
      </div>
      <div class="mt-4 rounded-[1.2rem] border border-[#bea98a] bg-[#f8f1e5] px-5 py-4 font-mono text-4xl text-[#8f8a81]">
        Ictus
      </div>
      <div class="mt-4 flex flex-wrap gap-3">
        <span
          :for={word <- ["Ictus", "Captio", "Scutum", "Sanatio", "Vocatio"]}
          class="rounded-full border border-[#baa689] bg-[#f7efe0] px-4 py-2 font-mono text-3xl text-[#4c4238]"
        >
          {word}
        </span>
      </div>
    </div>
    """
  end

  attr :grimoire_layout, :string, required: true
  attr :selected_spellbook, :string, required: true

  defp grimoire_screen(assigns) do
    ~H"""
    <.parchment_heading title="Гримуары" />
    <div class="mb-8 flex justify-center gap-4">
      <button
        id="grimoires-shelves"
        type="button"
        phx-click="set_grimoire_layout"
        phx-value-layout="shelves"
        class={[
          "rounded-2xl border px-8 py-3 font-['Cormorant_Garamond'] text-4xl shadow-[0_5px_14px_rgba(80,50,20,0.12)]",
          if(@grimoire_layout == "shelves",
            do: "border-[#7b211d] bg-[linear-gradient(180deg,_#aa332d,_#8f1f1e)] text-[#f8ece1]",
            else: "border-[#b7a487] bg-[linear-gradient(180deg,_#f8efdf,_#eadfc7)] text-[#3a2b20]"
          )
        ]}
      >
        Полки
      </button>
      <button
        id="grimoires-catalog"
        type="button"
        phx-click="set_grimoire_layout"
        phx-value-layout="catalog"
        class={[
          "rounded-2xl border px-8 py-3 font-['Cormorant_Garamond'] text-4xl shadow-[0_5px_14px_rgba(80,50,20,0.12)]",
          if(@grimoire_layout == "catalog",
            do: "border-[#7b211d] bg-[linear-gradient(180deg,_#aa332d,_#8f1f1e)] text-[#f8ece1]",
            else: "border-[#b7a487] bg-[linear-gradient(180deg,_#f8efdf,_#eadfc7)] text-[#3a2b20]"
          )
        ]}
      >
        Каталог
      </button>
    </div>

    <%= if @grimoire_layout == "shelves" do %>
      <div class="space-y-7">
        <div :for={shelf <- shelf_rows()} class="space-y-2 rounded-[1.4rem] bg-[#efe2c9]/50 p-4">
          <div class="grid grid-cols-4 gap-4">
            <button
              :for={book <- shelf}
              id={"book-#{book.id}"}
              type="button"
              phx-click="select_spellbook"
              phx-value-book={book.id}
              class={"h-64 rounded-t-md border border-[#4a3d33] bg-gradient-to-b #{book.color} pt-4 shadow-[0_4px_12px_rgba(0,0,0,0.25)]"}
            >
              <div class="mx-auto h-[3px] w-[92%] bg-[#d8ba73]"></div>
              <div class="flex h-[calc(100%-24px)] items-center justify-center">
                <span class="rotate-180 whitespace-nowrap font-['Cormorant_Garamond'] text-4xl text-[#f5efe8] [writing-mode:vertical-rl]">
                  {book.title}
                </span>
              </div>
              <div class="mx-auto h-[3px] w-[92%] bg-[#d8ba73]"></div>
            </button>
          </div>
          <div class="h-7 rounded-sm bg-[linear-gradient(180deg,_#8b6752,_#6b4d3d)] shadow-[0_6px_10px_rgba(0,0,0,0.25)]">
          </div>
        </div>
      </div>
    <% else %>
      <div class="rounded-[1.8rem] border border-[#7f6657] bg-[linear-gradient(180deg,_#8f715f,_#6d5040)] p-6 shadow-[0_12px_24px_rgba(80,50,20,0.18)]">
        <div class="rounded-[1.4rem] border border-[#ceb995] bg-[linear-gradient(180deg,_#f8f0e0,_#ede2cc)] p-3">
          <div
            :for={spell <- spell_catalog()}
            class="mb-2 flex items-center gap-5 rounded-xl border border-[#e3d5bd] bg-[#f8f2e6] px-4 py-4 last:mb-0"
          >
            <div class="h-12 w-2 rounded-full" style={"background: #{spell.color};"}></div>
            <div class="min-w-0 flex-1 font-mono text-[2rem] text-[#2a241f]">{spell.name}</div>
            <div class="font-['Cormorant_Garamond'] text-4xl italic text-[#7b6e61]">{spell.ru}</div>
            <div class="font-['Cormorant_Garamond'] text-4xl text-[#7b6e61]">тир {spell.tier}</div>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  attr :combat_action_id, :string, required: true
  attr :combat_target_id, :string, required: true
  attr :combat_plan_id, :string, required: true

  defp combat_screen(assigns) do
    action = combat_action(assigns.combat_action_id)
    target = combat_target(assigns.combat_target_id)
    plan = combat_plan(assigns.combat_plan_id)

    assigns =
      assign(assigns,
        action: action,
        target: target,
        plan: plan
      )

    ~H"""
    <div class="space-y-5">
      <div class="flex items-center justify-between">
        <span class="rounded-full border border-[#d47b6e] bg-[#f7dbd6] px-5 py-2 font-['Cormorant_Garamond'] text-4xl">
          Ход 3
        </span>
        <span class="font-mono text-4xl text-[#483c33]">⌛ 0:38</span>
        <span class="rounded-full border border-[#b9a78c] bg-[#f5ead7] px-5 py-2 font-['Cormorant_Garamond'] text-4xl">
          Дуэль · 3v2
        </span>
      </div>

      <div class="space-y-2">
        <div class="flex items-center gap-4">
          <span class="w-24 text-3xl tracking-[0.14em] text-[#5b5048]">ОТРЯД</span>
          <div class="h-5 flex-1 overflow-hidden rounded-full border border-[#b7a68d] bg-[#f4ebdb]">
            <div class="h-full w-[72%] bg-[linear-gradient(90deg,_#648c7d,_#488379)]"></div>
          </div>
          <span class="w-28 text-right font-mono text-3xl">72/100</span>
        </div>
        <div class="flex items-center gap-4">
          <span class="w-24 text-3xl tracking-[0.14em] text-[#5b5048]">ВРАГИ</span>
          <div class="h-5 flex-1 overflow-hidden rounded-full border border-[#b7a68d] bg-[#f4ebdb]">
            <div class="h-full w-[83%] bg-[linear-gradient(90deg,_#8d1b20,_#b12b2e)]"></div>
          </div>
          <span class="w-28 text-right font-mono text-3xl">83/100</span>
        </div>
      </div>

      <div class="rounded-[1.8rem] border-2 border-dashed border-[#cfbea4] p-4">
        <p class="mb-3 text-3xl uppercase tracking-[0.14em] text-[#6a5f55]">Противники</p>
        <div class="grid gap-3 sm:grid-cols-2">
          <div class="rounded-[1.3rem] border border-[#c4b297] bg-[#f6ecdb] p-4">
            <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Гоблин-вор</p>
            <span class="mt-2 inline-block rounded-full border border-[#b59ce4] bg-[#eee6f7] px-4 py-1 font-mono text-2xl text-[#5f43a0]">
              exposed
            </span>
          </div>
          <div class="rounded-[1.3rem] border border-[#cb6457] bg-[#f7d4ca] p-4">
            <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Пещерный жнец</p>
            <span class="mt-2 inline-block rounded-full border border-[#b59ce4] bg-[#eee6f7] px-4 py-1 font-mono text-2xl text-[#5f43a0]">
              shielded
            </span>
          </div>
        </div>

        <p class="mb-3 mt-6 text-3xl uppercase tracking-[0.14em] text-[#6a5f55]">Отряд</p>
        <div class="grid gap-3 sm:grid-cols-3">
          <div class="rounded-[1.3rem] border-2 border-[#a48de2] bg-[#f7eedf] p-4">
            <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Вы</p>
            <p class="font-['Cormorant_Garamond'] text-4xl text-[#7b6e61]">Маг</p>
          </div>
          <div class="rounded-[1.3rem] border border-[#c4b297] bg-[#f7eedf] p-4">
            <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Торвальд</p>
            <p class="font-['Cormorant_Garamond'] text-4xl text-[#7b6e61]">Воин</p>
          </div>
          <div class="rounded-[1.3rem] border border-[#c4b297] bg-[#f7eedf] p-4">
            <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">Льенн</p>
            <p class="font-['Cormorant_Garamond'] text-4xl text-[#7b6e61]">Алхимик</p>
          </div>
        </div>
      </div>

      <div class="rounded-[1.7rem] border border-[#b9a78c] bg-[#faf3e6] p-5 shadow-[0_8px_24px_rgba(80,50,20,0.12)]">
        <p class="font-mono text-[2rem] text-[#5f554d]">
          ▶ Ход 2. Торвальд бьёт мечом: Жнец оглушён на 1 ход.
        </p>
        <p class="mt-5 font-['Cormorant_Garamond'] text-5xl italic leading-[1.25] text-[#241c16]">
          Пещера пахнет серой. Где-то сзади капает вода — ровно, как метроном.
        </p>
      </div>

      <div class="space-y-4">
        <div class="grid gap-3 lg:grid-cols-[minmax(0,1fr)_minmax(260px,0.9fr)]">
          <div class="space-y-4">
            <div class="grid gap-3 sm:grid-cols-3">
              <button
                :for={action <- combat_actions()}
                id={"combat-action-#{action.id}"}
                type="button"
                phx-click="select_combat_action"
                phx-value-action={action.id}
                class={[
                  "rounded-[1.2rem] border px-4 py-3 text-left shadow-[0_4px_12px_rgba(80,50,20,0.08)] transition",
                  if(@combat_action_id == action.id,
                    do: "border-[#d45f47] bg-[#f7d4ca]",
                    else: "border-[#b9a78c] bg-[#f8efdf]"
                  )
                ]}
              >
                <p class="font-mono text-[1.55rem] text-[#2f241d]">{action.label}</p>
                <p class="mt-1 text-sm leading-5 text-[#6b6057]">{action.detail}</p>
              </button>
            </div>

            <div class="rounded-[1.5rem] border border-[#b9a78c] bg-[#f8f0e0] p-4">
              <div class="flex items-center justify-between gap-4">
                <div class="min-w-0 flex-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-[#8a7c70]">
                    Active incantation
                  </p>
                  <div class="mt-2 font-mono text-[2rem] text-[#2d241d]">
                    {@action.incantation}
                  </div>
                </div>
                <button
                  id="combat-commit-action"
                  type="button"
                  class="rounded-[1.2rem] border border-[#7b211d] bg-[linear-gradient(180deg,_#aa332d,_#8f1f1e)] px-6 py-3 font-['Cormorant_Garamond'] text-4xl text-[#f8ece1] shadow-[0_8px_18px_rgba(120,30,20,0.25)]"
                >
                  {@plan.cta}
                </button>
              </div>

              <div class="mt-4 grid gap-3 sm:grid-cols-2">
                <div class="rounded-[1rem] border border-[#d7c6aa] bg-[#fdf7ed] px-4 py-3">
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-[#8a7c70]">
                    Target
                  </p>
                  <p
                    id="combat-selected-target"
                    class="mt-2 font-['Cormorant_Garamond'] text-4xl text-[#2d241d]"
                  >
                    {@target.name}
                  </p>
                  <p class="text-sm leading-5 text-[#6b6057]">{@target.note}</p>
                </div>

                <div class="rounded-[1rem] border border-[#d7c6aa] bg-[#fdf7ed] px-4 py-3">
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-[#8a7c70]">
                    Plan
                  </p>
                  <p
                    id="combat-selected-plan"
                    class="mt-2 font-['Cormorant_Garamond'] text-4xl text-[#2d241d]"
                  >
                    {@plan.label}
                  </p>
                  <p class="text-sm leading-5 text-[#6b6057]">{@plan.detail}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-4">
            <div class="rounded-[1.5rem] border border-[#b9a78c] bg-[#f8efdf] p-4">
              <p class="mb-3 text-3xl uppercase tracking-[0.14em] text-[#6a5f55]">Targets</p>
              <div class="space-y-3">
                <button
                  :for={target <- combat_targets()}
                  id={"combat-target-#{target.id}"}
                  type="button"
                  phx-click="select_combat_target"
                  phx-value-target={target.id}
                  class={[
                    "w-full rounded-[1.1rem] border px-4 py-4 text-left transition",
                    if(@combat_target_id == target.id,
                      do: "border-[#8f1f1e] bg-[#f7d4ca]",
                      else: "border-[#ccbba0] bg-[#fcf6ea]"
                    )
                  ]}
                >
                  <div class="flex items-center justify-between gap-3">
                    <p class="font-['Cormorant_Garamond'] text-4xl text-[#2d241d]">{target.name}</p>
                    <span class="rounded-full border border-[#b59ce4] bg-[#eee6f7] px-3 py-1 font-mono text-[1rem] text-[#5f43a0]">
                      {target.tag}
                    </span>
                  </div>
                  <p class="mt-2 text-sm leading-5 text-[#6b6057]">{target.note}</p>
                </button>
              </div>
            </div>

            <div class="rounded-[1.5rem] border border-[#b9a78c] bg-[#f8efdf] p-4">
              <p class="mb-3 text-3xl uppercase tracking-[0.14em] text-[#6a5f55]">Plan mode</p>
              <div class="grid gap-3">
                <button
                  :for={plan <- combat_plans()}
                  id={"combat-plan-#{plan.id}"}
                  type="button"
                  phx-click="select_combat_plan"
                  phx-value-plan={plan.id}
                  class={[
                    "rounded-[1.1rem] border px-4 py-4 text-left transition",
                    if(@combat_plan_id == plan.id,
                      do: "border-[#4f6d60] bg-[#dde9e3]",
                      else: "border-[#ccbba0] bg-[#fcf6ea]"
                    )
                  ]}
                >
                  <p class="font-['Cormorant_Garamond'] text-4xl text-[#2d241d]">{plan.label}</p>
                  <p class="mt-2 text-sm leading-5 text-[#6b6057]">{plan.detail}</p>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :academy_tab, :string, required: true
  attr :clubs, :list, required: true

  defp academy_screen(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="flex items-start justify-between gap-4">
        <div class="flex items-center gap-5">
          <div class="flex size-24 items-center justify-center rounded-full border-[3px] border-[#7f6446] bg-[radial-gradient(circle_at_top,_#f8e8c4,_#d3ae6c)] text-5xl text-[#8f1f1e] shadow-[0_8px_20px_rgba(80,50,20,0.2)]">
            ✦
          </div>
          <div>
            <h1 class="font-['Cormorant_Garamond'] text-7xl font-semibold leading-none">
              Княжеская Академия
            </h1>
            <p class="mt-1 font-['Cormorant_Garamond'] text-5xl italic text-[#7c6f62]">
              Scientia ante potentiam — знание прежде силы
            </p>
          </div>
        </div>
        <button
          id="academy-exit"
          type="button"
          phx-click="switch_screen"
          phx-value-screen="map"
          class="rounded-full border border-[#baa78a] bg-[#f5ead7] px-7 py-3 font-['Cormorant_Garamond'] text-4xl text-[#3a2b20]"
        >
          Выйти
        </button>
      </div>

      <div class="flex gap-3 border-b border-[#baa88f]">
        <button
          :for={tab <- academy_tab_defs()}
          id={"academy-tab-#{tab.id}"}
          type="button"
          phx-click="set_academy_tab"
          phx-value-tab={tab.id}
          class={[
            "rounded-t-[1.2rem] border border-b-0 px-8 py-4 font-['Cormorant_Garamond'] text-4xl",
            if(@academy_tab == tab.id,
              do: "border-[#baa88f] bg-[#f6eddc] text-[#2f241d]",
              else: "border-[#cbbb9f] bg-[#efe3cc] text-[#85786c]"
            )
          ]}
        >
          {tab.label}
        </button>
      </div>

      <%= case @academy_tab do %>
        <% "yard" -> %>
          <.parchment_heading title="Двор" />
          <div class="rounded-[1.6rem] border border-[#8e7059] bg-[linear-gradient(180deg,_#deccae,_#dcc7a7)] p-4 shadow-[0_8px_20px_rgba(80,50,20,0.15)]">
            <div class="relative h-[28rem] overflow-hidden rounded-[1.2rem] bg-[linear-gradient(180deg,_#dbc7a8,_#d8c19f)]">
              <div class="absolute left-1/2 top-1/2 h-72 w-[26rem] -translate-x-1/2 -translate-y-1/2 rounded-[50%] bg-[radial-gradient(circle_at_center,_#83ad73,_#6f985d)] shadow-[0_10px_20px_rgba(0,0,0,0.15)]">
              </div>
              <div class="absolute left-1/2 top-1/2 size-28 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle_at_center,_#8ed0ef,_#5da6ca)] shadow-[0_0_0_6px_rgba(102,77,53,0.55)]">
              </div>
              <div class="absolute left-1/2 top-1/2 size-16 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[#6d513d]">
              </div>
              <div class="absolute left-1/2 top-0 h-full w-6 -translate-x-1/2 bg-[#d7c3a4]/70"></div>
              <div class="absolute left-0 top-1/2 h-6 w-full -translate-y-1/2 bg-[#d7c3a4]/70"></div>
              <div class="absolute left-1/2 top-4 h-20 w-[56%] -translate-x-1/2 rounded-lg border border-[#64463a] bg-[linear-gradient(180deg,_#caaea4,_#a78378)]">
              </div>
              <div class="absolute bottom-4 left-1/2 h-20 w-[56%] -translate-x-1/2 rounded-lg border border-[#64463a] bg-[linear-gradient(180deg,_#caaea4,_#a78378)]">
              </div>
              <div class="absolute left-4 top-1/2 h-[58%] w-32 -translate-y-1/2 rounded-lg border border-[#64463a] bg-[linear-gradient(180deg,_#caaea4,_#a78378)]">
              </div>
              <div class="absolute right-4 top-1/2 h-[58%] w-32 -translate-y-1/2 rounded-lg border border-[#64463a] bg-[linear-gradient(180deg,_#caaea4,_#a78378)]">
              </div>
            </div>
          </div>
          <p class="px-4 text-center font-['Cormorant_Garamond'] text-5xl italic text-[#5b4f45]">
            Из окон факультета алхимии тянет лавандой и серой одновременно.
          </p>
          <div class="flex items-center gap-4">
            <div class="h-px flex-1 bg-[#d5c6ae]"></div>
            <div class="text-xl text-[#a89880]">◆</div>
            <div class="h-px flex-1 bg-[#d5c6ae]"></div>
          </div>
          <div class="space-y-4">
            <.base_tile
              id="academy-faculty-magic"
              title="Факультет Чародейства"
              subtitle="Две школы на выбор"
              icon="✦"
              screen="academy"
            />
            <.base_tile
              id="academy-faculty-alchemy"
              title="Факультет Алхимии"
              subtitle="Варка, травы, перегонка"
              icon="⚗"
              screen="academy"
            />
          </div>
        <% "schedule" -> %>
          <.parchment_heading title="РАСПИСАНИЕ · ОСЕННИЙ ТРИМЕСТР" />
          <div class="rounded-[1.7rem] border border-[#b7a487] bg-[#f8efdf] p-2 shadow-[0_8px_22px_rgba(80,50,20,0.12)]">
            <div
              :for={row <- schedule_rows()}
              class={[
                "grid grid-cols-[5rem_3rem_minmax(0,1fr)_9rem] items-center gap-4 border-b border-dashed border-[#d2c1a7] px-4 py-5 last:border-b-0",
                row.tint
              ]}
            >
              <div class="text-4xl font-semibold text-[#493d34]">{row.day}</div>
              <div class="text-4xl text-[#8b7d71]">{row.slot}</div>
              <div>
                <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">{row.title}</p>
                <p class="font-['Cormorant_Garamond'] text-4xl italic text-[#7b6e61]">{row.meta}</p>
              </div>
              <%= if row.badge do %>
                <div class={[
                  "rounded-full border px-4 py-2 text-center font-mono text-3xl",
                  row.badge_class
                ]}>
                  {row.badge}
                </div>
              <% else %>
                <div></div>
              <% end %>
            </div>
          </div>

          <div class="mt-6 flex flex-wrap justify-between gap-3">
            <div class="rounded-full border border-[#b7a487] bg-[#f3e8d4] px-5 py-2 font-mono text-3xl text-[#41352d]">
              Сессия через 18 дн.
            </div>
            <div class="rounded-full border border-[#9bb18b] bg-[#dce9d6] px-5 py-2 font-mono text-3xl text-[#2a5f51]">
              Средний балл 4.2
            </div>
            <div class="rounded-full border border-[#b59ce4] bg-[#efe6fb] px-5 py-2 font-mono text-3xl text-[#5d3d98]">
              3/7 сдано
            </div>
          </div>
        <% "clubs" -> %>
          <.parchment_heading title="ДОСКА ОБЪЯВЛЕНИЙ" />
          <div class="rounded-[1.7rem] border border-[#5d3c2e] bg-[linear-gradient(180deg,_#6f4335,_#5f392d)] p-5 shadow-[0_10px_24px_rgba(80,50,20,0.18)]">
            <div class="grid gap-4 sm:grid-cols-2">
              <button
                :for={club <- @clubs}
                id={"club-toggle-#{club.id}"}
                type="button"
                phx-click="toggle_club"
                phx-value-club={club.id}
                class="relative min-h-52 rotate-[-1deg] rounded-sm border border-[#d9ccb6] bg-[#fcf4e5] p-5 text-left shadow-[0_6px_14px_rgba(0,0,0,0.18)] even:rotate-[1deg]"
              >
                <div class="absolute left-1/2 top-0 size-6 -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle_at_top,_#ff776d,_#c14139)] shadow-[0_3px_8px_rgba(160,30,20,0.35)]">
                </div>
                <p class="font-['Cormorant_Garamond'] text-5xl font-semibold leading-none">
                  {club.name}
                </p>
                <p class="mt-3 font-mono text-[2rem] text-[#3a2c22]">
                  {club.members} чел. · {club.short}
                </p>
                <p class="mt-4 font-['Cormorant_Garamond'] text-4xl italic text-[#46362b]">
                  {club.note}
                </p>
                <p class="mt-5 text-right font-mono text-[1.7rem] text-[#7a3e2f]">
                  {if club.joined?, do: "вы уже внутри", else: "идёт набор"}
                </p>
              </button>
            </div>
          </div>
          <p class="px-4 text-center font-['Cormorant_Garamond'] text-5xl italic text-[#5b4f45]">
            В клубе находят тех, с кем потом идут в подземелье.
          </p>
        <% "enrollment" -> %>
          <.parchment_heading title="ВАШ ПУТЬ" />
          <div class="space-y-5">
            <div class="rounded-[1.7rem] border border-[#b7a487] bg-[#f7eedf] p-6 shadow-[0_8px_22px_rgba(80,50,20,0.12)]">
              <p class="font-['Cormorant_Garamond'] text-6xl font-semibold">Факультет Чародейства</p>
              <p class="font-['Cormorant_Garamond'] text-4xl italic text-[#6f6155]">
                2-й курс бакалавриата · 1 семестр
              </p>
              <div class="mt-5 flex flex-wrap gap-4">
                <div
                  :for={school <- school_icons()}
                  class={[
                    "flex size-20 items-center justify-center rounded-full border text-3xl",
                    school.class
                  ]}
                >
                  {school.icon}
                </div>
              </div>
              <p class="mt-4 font-mono text-[2rem] text-[#51463d]">
                Огонь и Вода — выбрано. Смена возможна, одна школа может остаться.
              </p>
            </div>

            <div class="rounded-[1.7rem] border border-[#b7a487] bg-[#f7eedf] p-6 shadow-[0_8px_22px_rgba(80,50,20,0.12)]">
              <div class="flex justify-between font-mono text-[1.9rem] text-[#51463d]">
                <span>Базовое обр.</span>
                <span>Бакалавриат</span>
                <span>Магистратура</span>
                <span>Аспирантура</span>
              </div>
              <div class="mt-3 h-6 overflow-hidden rounded-full border border-[#baa88f] bg-[#f3ead7]">
                <div class="h-full w-[38%] bg-[linear-gradient(90deg,_#c69228,_#c28d24,_#9f2730)]">
                </div>
              </div>
              <p class="mt-4 font-['Cormorant_Garamond'] text-4xl italic text-[#4b4037]">
                «На защиту дипломной работы нужно ещё 2 года игрового времени».
              </p>
            </div>

            <div class="relative rounded-[1.7rem] border border-[#aab089] bg-[linear-gradient(180deg,_#eef2d9,_#dde5c6)] p-6 shadow-[0_8px_22px_rgba(80,50,20,0.12)]">
              <div class="absolute -right-3 top-1/2 flex size-20 -translate-y-1/2 items-center justify-center rounded-full bg-[radial-gradient(circle_at_top,_#c74b43,_#89241f)] text-4xl text-[#fff2e6] shadow-[0_10px_24px_rgba(140,30,20,0.25)]">
                ✦
              </div>
              <p class="font-['Cormorant_Garamond'] text-5xl font-semibold">
                Стипендия от благотворительного фонда
              </p>
              <p class="mt-3 font-['Cormorant_Garamond'] text-5xl leading-[1.2] text-[#4c4339]">
                Ваша успеваемость позволяет сохранять грант. Оплата обучения:
                <span class="font-mono text-[#5b907d]"> 0 монет.</span>
              </p>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp academy_tab_defs do
    [
      %{id: "yard", label: "Двор"},
      %{id: "schedule", label: "Расписание"},
      %{id: "clubs", label: "Клубы"},
      %{id: "enrollment", label: "Зачисление"}
    ]
  end

  defp circle_slots do
    [
      %{name: "ДЕЙСТВИЕ", index: 1, top: "8%", left: "50%", border: "#ae3a33"},
      %{name: "ФОРМА", index: 2, top: "28%", left: "86%", border: "#9a938d"},
      %{name: "СИЛА", index: 3, top: "72%", left: "86%", border: "#9a938d"},
      %{name: "ВРЕМЯ", index: 4, top: "92%", left: "50%", border: "#9a938d"},
      %{name: "МУТАЦИЯ", index: 5, top: "72%", left: "14%", border: "#9a938d"},
      %{name: "ЦЕНА", index: 6, top: "28%", left: "14%", border: "#9a938d"}
    ]
  end

  defp word_families do
    [
      %{id: "actio", icon: "△"},
      %{id: "aqua", icon: "◉"},
      %{id: "terra", icon: "⬢"},
      %{id: "aer", icon: "≋"},
      %{id: "lux", icon: "✧"},
      %{id: "ordo", icon: "✦"},
      %{id: "vita", icon: "✳"},
      %{id: "mors", icon: "⬟"}
    ]
  end

  defp combat_actions do
    [
      %{
        id: "spell",
        label: "△ Conus Magnus",
        detail: "Cast a prepared spell with an explicit target and a committed line.",
        incantation: "Conus Magnus"
      },
      %{
        id: "tool",
        label: "◉ Pilum Ferrum",
        detail: "Use a weapon or consumable with deterministic tool-user actions.",
        incantation: "Pilum Ferrum"
      },
      %{
        id: "guard",
        label: "⬢ Scutum Minor",
        detail: "Stall tempo, brace the line, and punish the next opening.",
        incantation: "Scutum Minor"
      }
    ]
  end

  defp combat_action(id) do
    Enum.find(combat_actions(), &(&1.id == id)) || hd(combat_actions())
  end

  defp combat_targets do
    [
      %{
        id: "goblin",
        name: "Гоблин-вор",
        tag: "exposed",
        note: "Low guard. Best target for a quick finish."
      },
      %{
        id: "reaper",
        name: "Пещерный жнец",
        tag: "shielded",
        note: "Highest threat. Better when the turn must redirect pressure."
      },
      %{
        id: "self",
        name: "Вы",
        tag: "tempo",
        note: "Self-targeting line for guard states, wards, and resets."
      }
    ]
  end

  defp combat_target(id) do
    Enum.find(combat_targets(), &(&1.id == id)) || hd(combat_targets())
  end

  defp combat_plans do
    [
      %{
        id: "cast",
        label: "Ready plan",
        cta: "Commit plan",
        detail: "Use the authored line with the current target."
      },
      %{
        id: "skip",
        label: "Skip turn",
        cta: "Skip",
        detail: "Bank tempo and let allies bait a cleaner opening."
      },
      %{
        id: "retreat",
        label: "Retreat",
        cta: "Retreat",
        detail: "Abandon board control and preserve the party."
      }
    ]
  end

  defp combat_plan(id) do
    Enum.find(combat_plans(), &(&1.id == id)) || hd(combat_plans())
  end

  defp shelf_rows do
    [
      [
        %{id: "red", title: "Ignis Parvus", color: "from-[#d54b1d] to-[#ba2808]"},
        %{id: "magna", title: "Ignis Magna", color: "from-[#d54b1d] to-[#ba2808]"},
        %{id: "blue", title: "Aqua Scutum", color: "from-[#1276b0] to-[#0c5b8c]"},
        %{id: "nexus", title: "Aqua Nexus", color: "from-[#1276b0] to-[#0c5b8c]"}
      ],
      [
        %{id: "terra_mure", title: "Terra Mure", color: "from-[#897406] to-[#716000]"},
        %{id: "terra_vocatio", title: "Terra Vocatio", color: "from-[#897406] to-[#716000]"},
        %{id: "aer_velox", title: "Aer Velox", color: "from-[#95c7ea] to-[#5799c4]"},
        %{id: "aer_conus", title: "Aer Conus", color: "from-[#95c7ea] to-[#5799c4]"}
      ],
      [
        %{id: "vita", title: "Vita Sanatio", color: "from-[#2e9a3f] to-[#15742a]"},
        %{id: "mors", title: "Mors Tactus", color: "from-[#49305e] to-[#2e1c3e]"},
        %{id: "ordo", title: "Ordo Catena", color: "from-[#6678d7] to-[#4050a5]"},
        %{id: "chaos", title: "Chaos Scintilla", color: "from-[#db23aa] to-[#aa007d]"}
      ]
    ]
  end

  defp spell_catalog do
    [
      %{name: "Ignis Parvus", ru: "Малый огонь", tier: 1, color: "#d75328"},
      %{name: "Ignis Magna", ru: "Пламя великое", tier: 3, color: "#d75328"},
      %{name: "Aqua Scutum", ru: "Водный щит", tier: 2, color: "#1280c0"},
      %{name: "Aqua Nexus", ru: "Водная связь", tier: 2, color: "#1280c0"},
      %{name: "Terra Mure", ru: "Стена земли", tier: 2, color: "#8a7a0b"},
      %{name: "Terra Vocatio", ru: "Зов камня", tier: 3, color: "#8a7a0b"},
      %{name: "Aer Velox", ru: "Быстрый ветер", tier: 1, color: "#94cdef"},
      %{name: "Aer Conus", ru: "Конус ветра", tier: 2, color: "#94cdef"},
      %{name: "Vita Sanatio", ru: "Исцеление", tier: 2, color: "#2f9b47"},
      %{name: "Mors Tactus", ru: "Касание смерти", tier: 3, color: "#48305d"},
      %{name: "Ordo Catena", ru: "Цепь порядка", tier: 3, color: "#6678d7"},
      %{name: "Chaos Scintilla", ru: "Искра хаоса", tier: 1, color: "#db23aa"}
    ]
  end

  defp schedule_rows do
    [
      %{
        day: "Пн",
        slot: "I",
        title: "Латынь и инкантации",
        meta: "ауд. 3 · маг. Лиен Тар",
        badge: nil,
        badge_class: nil,
        tint: ""
      },
      %{
        day: "Пн",
        slot: "II",
        title: "Теория элементов",
        meta: "ауд. 5 · маг. Гэвин",
        badge: nil,
        badge_class: nil,
        tint: ""
      },
      %{
        day: "Вт",
        slot: "I",
        title: "Практика: Малый огонь",
        meta: "лаб. №1 · маг. Ортис",
        badge: "сдано",
        badge_class: "border-[#9bb18b] bg-[#dce9d6] text-[#2a5f51]",
        tint: "bg-[#eef0df]"
      },
      %{
        day: "Вт",
        slot: "II",
        title: "Этика боевой магии",
        meta: "ауд. 2 · маг. Морвиль",
        badge: nil,
        badge_class: nil,
        tint: ""
      },
      %{
        day: "Ср",
        slot: "I",
        title: "Травник и реагенты",
        meta: "теплица · мастер Кайе",
        badge: nil,
        badge_class: nil,
        tint: ""
      },
      %{
        day: "Чт",
        slot: "I",
        title: "Дуэльный клуб",
        meta: "полигон · капитан Борн",
        badge: "клуб",
        badge_class: "border-[#d8a2a0] bg-[#f4dfdc] text-[#7d3c38]",
        tint: "bg-[#f8e6db]"
      },
      %{
        day: "Пт",
        slot: "I",
        title: "История княжества",
        meta: "ауд. 1 · проф. Веттен",
        badge: nil,
        badge_class: nil,
        tint: ""
      }
    ]
  end

  defp school_icons do
    [
      %{
        icon: "△",
        class:
          "border-[#efb0a4] bg-[#f7ebe0] text-[#d35d47] shadow-[0_0_18px_rgba(211,93,71,0.28)]"
      },
      %{
        icon: "◉",
        class:
          "border-[#9fd7ef] bg-[#edf8fc] text-[#5eb7dd] shadow-[0_0_18px_rgba(94,183,221,0.28)]"
      },
      %{icon: "⬢", class: "border-[#b1a789] bg-[#f7eedf] text-[#7e7305]"},
      %{icon: "≋", class: "border-[#b1a789] bg-[#f7eedf] text-[#82b8d4]"},
      %{icon: "✧", class: "border-[#b1a789] bg-[#f7eedf] text-[#dc4faf]"},
      %{icon: "✦", class: "border-[#b1a789] bg-[#f7eedf] text-[#6578d0]"},
      %{icon: "✳", class: "border-[#b1a789] bg-[#f7eedf] text-[#46a54c]"},
      %{icon: "⬟", class: "border-[#b1a789] bg-[#f7eedf] text-[#46315c]"}
    ]
  end

  defp clubs do
    [
      %{
        id: "duel",
        name: "Дуэльный клуб",
        members: 24,
        short: "спорт",
        note: "еженед. спарринги",
        joined?: false
      },
      %{
        id: "translation",
        name: "Круг переводов",
        members: 11,
        short: "яз.",
        note: "читаем «De Elementis»",
        joined?: false
      },
      %{
        id: "expedition",
        name: "Экспедиционный",
        members: 18,
        short: "иссл.",
        note: "идёт запись в поход",
        joined?: false
      },
      %{
        id: "herbs",
        name: "Общество трав",
        members: 9,
        short: "алх.",
        note: "обмен семенами",
        joined?: false
      }
    ]
  end

  defp client_mode(%{mode: :telegram}), do: "telegram"
  defp client_mode(_context), do: "browser"

  defp default_telegram_context do
    %{
      mode: :browser,
      platform: "web",
      color_scheme: "dark",
      viewport_height: nil,
      expanded?: false
    }
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, _rest} -> parsed
      :error -> nil
    end
  end

  defp parse_integer(_value), do: nil

  defp truthy?(value) when value in [true, "true", 1, "1"], do: true
  defp truthy?(_value), do: false
end
