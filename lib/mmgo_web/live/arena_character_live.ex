defmodule MMGOWeb.ArenaCharacterLive do
  use MMGOWeb, :live_view

  alias MMGO.Arena

  @schools [
    %{value: "fire", name: "Огонь", icon: "hero-fire", promise: "напор и горение"},
    %{value: "water", name: "Вода", icon: "hero-beaker", promise: "потоки и контроль"},
    %{value: "earth", name: "Земля", icon: "hero-cube", promise: "стойкость и преграды"},
    %{value: "air", name: "Воздух", icon: "hero-cloud", promise: "скорость и отбрасывание"},
    %{value: "life", name: "Жизнь", icon: "hero-heart", promise: "исцеление и рост"},
    %{value: "death", name: "Смерть", icon: "hero-moon", promise: "истощение и духи"},
    %{value: "chaos", name: "Хаос", icon: "hero-sparkles", promise: "риск и превращения"},
    %{value: "order", name: "Порядок", icon: "hero-shield-check", promise: "печати и защита"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    account = socket.assigns.current_scope.account

    if Arena.get_profile_for_account(account.id) do
      {:ok, push_navigate(socket, to: ~p"/mode")}
    else
      form = to_form(%{"name" => account.display_name, "schools" => []}, as: :arena_profile)

      {:ok,
       socket
       |> assign(:page_title, "Создать бойца Арены")
       |> assign(:schools, @schools)
       |> assign(:selected_schools, [])
       |> assign(:form, form)}
    end
  end

  @impl true
  def handle_event("validate", %{"arena_profile" => params}, socket) do
    selected_schools = normalize_schools(params["schools"])
    params = Map.put(params, "schools", selected_schools)

    {:noreply,
     socket
     |> assign(:selected_schools, selected_schools)
     |> assign(:form, to_form(params, as: :arena_profile))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} public={true}>
      <main id="arena-character-screen" class="arena-forge">
        <div class="arena-forge__paper">
          <.link id="arena-character-back" navigate={~p"/mode"} class="arena-forge__back">
            <.icon name="hero-arrow-left" /> К выбору режима
          </.link>

          <header class="arena-forge__mast">
            <p>Реестр дуэлянтов</p>
            <h1>Соберите свою магию</h1>
            <span>
              Выберите ровно три школы. Противоположности разрешены — стиль боя принадлежит вам.
            </span>
          </header>

          <.form
            for={@form}
            id="arena-character-form"
            action={~p"/arena/profiles"}
            method="post"
            phx-change="validate"
            class="arena-forge__form"
          >
            <.input
              field={@form[:name]}
              id="arena-character-name"
              type="text"
              label="Имя бойца"
              minlength="3"
              maxlength="40"
              required
              autocomplete="off"
              class="arena-forge__name"
            />

            <fieldset id="arena-school-picker" class="arena-schools">
              <legend>
                <span>Три школы</span>
                <strong class={if(length(@selected_schools) == 3, do: "is-ready", else: nil)}>
                  {length(@selected_schools)} / 3
                </strong>
              </legend>

              <p id="arena-school-picker-help">
                Они определят доступные заклинания этого персонажа. Изменить набор после создания нельзя.
              </p>

              <div class="arena-schools__grid">
                <label
                  :for={school <- @schools}
                  id={"arena-school-#{school.value}"}
                  class={[
                    "arena-school",
                    school.value in @selected_schools && "arena-school--selected",
                    length(@selected_schools) >= 3 && school.value not in @selected_schools &&
                      "arena-school--locked"
                  ]}
                >
                  <input
                    type="checkbox"
                    name="arena_profile[schools][]"
                    value={school.value}
                    checked={school.value in @selected_schools}
                    disabled={
                      length(@selected_schools) >= 3 and school.value not in @selected_schools
                    }
                    aria-describedby="arena-school-picker-help"
                  />
                  <span class="arena-school__icon"><.icon name={school.icon} /></span>
                  <strong>{school.name}</strong>
                  <small>{school.promise}</small>
                  <span class="arena-school__check"><.icon name="hero-check" /></span>
                </label>
              </div>
            </fieldset>

            <div class="arena-forge__promise">
              <.icon name="hero-book-open" />
              <p>
                Вы начнёте с бесплатными гримуарами максимальной ёмкости. Здесь побеждают идеи, а не инвентарь.
              </p>
            </div>

            <button
              id="create-arena-character"
              type="submit"
              disabled={length(@selected_schools) != 3}
              class="arena-forge__submit"
            >
              Поставить печать <.icon name="hero-sparkles" />
            </button>
          </.form>
        </div>
      </main>
    </Layouts.app>
    """
  end

  defp normalize_schools(schools) do
    schools
    |> List.wrap()
    |> Enum.filter(&Enum.any?(@schools, fn school -> school.value == &1 end))
    |> Enum.uniq()
    |> Enum.take(3)
  end
end
