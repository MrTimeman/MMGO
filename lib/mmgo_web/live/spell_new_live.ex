defmodule MMGOWeb.SpellNewLive do
  use MMGOWeb, :live_view

  alias MMGO.Spells
  alias MMGOWeb.GameLiveHelpers

  @slots [
    %{key: "school", label: "Schola", required: true},
    %{key: "base", label: "Basis", required: true},
    %{key: "vox_1", label: "Vox I", required: true},
    %{key: "vox_2", label: "Vox II", required: true},
    %{key: "vox_3", label: "Vox III", required: true},
    %{key: "vox_4", label: "Vox IV", required: true},
    %{key: "vox_5", label: "Vox V", required: true},
    %{key: "vox_6", label: "Vox VI", required: true}
  ]

  def mount(_params, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)
    {:ok, assign(socket, page_title: "Создание заклинания", notice: nil)}
  end

  def handle_event("hook_mounted", %{"hook" => "SpellCircle"}, socket) do
    {:noreply, push_event(socket, "spell_circle_init", %{slots: @slots})}
  end

  def handle_event("spell_compile", params, socket) do
    formula =
      @slots
      |> Enum.map(&Map.fetch!(params, &1.key))
      |> Enum.join(" ")

    school = normalize_school(params["school"])

    attrs = %{
      name: blank_to_default(params["name"], "Novum Incantum"),
      formula: formula,
      school: school,
      spell_type: :active,
      targeting: :enemy,
      delivery_form: :single_target,
      fatigue_cost: 2,
      cooldown_turns: 1,
      description: "Заклинание, собранное в круге латинской инкантации.",
      effects: [%{state: "impact", intensity: 30, duration: 0, applies_to: :target}],
      failure_profile: %{
        difficulty: 8,
        base_success_rate: 82,
        partial_success_rate: 10,
        backlash_damage: 1
      }
    }

    case Spells.create_spell(socket.assigns.current_character, attrs) do
      {:ok, spell} ->
        {:noreply,
         socket
         |> put_flash(:info, "Заклинание создано: #{spell.name}")
         |> push_navigate(to: ~p"/spells")}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :notice, "Не удалось собрать заклинание: #{inspect(changeset.errors)}")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main
        id="spell-circle-screen"
        class="zip-screen"
      >
        <.zip_header
          title="Создание заклинания"
          subtitle="Огонь · 0/6 слов"
        />
        <section class="zip-content spell-create-content">
          <.link navigate={~p"/spells"} class="zip-sub-link">← Библиотека</.link>
          <p
            :if={@notice}
            id="spell-create-error"
            class="zip-note is-error"
          >
            {@notice}
          </p>
          <div id="spell-circle-hook" phx-hook="SpellCircle" phx-update="ignore"></div>
        </section>
      </main>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil

  defp zip_header(assigns) do
    ~H"""
    <header class="zip-telegram-header">
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
    </header>
    """
  end

  defp normalize_school(value) do
    value
    |> to_string()
    |> String.downcase()
    |> case do
      school when school in ~w(fire water earth air life death chaos order) ->
        String.to_existing_atom(school)

      _other ->
        :fire
    end
  end

  defp blank_to_default(nil, default), do: default
  defp blank_to_default("", default), do: default
  defp blank_to_default(value, _default), do: value
end
