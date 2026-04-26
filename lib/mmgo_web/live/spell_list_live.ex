defmodule MMGOWeb.SpellListLive do
  use MMGOWeb, :live_view

  alias MMGO.Spells
  alias MMGOWeb.GameLiveHelpers

  def mount(_params, session, socket) do
    socket = GameLiveHelpers.assign_current_character(socket, session)
    spells = Spells.list_spells_for_character(socket.assigns.current_character.id)
    {:ok, assign(socket, page_title: "Заклинания", spells: spells)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} variant={:game}>
      <main id="spell-list-screen" class="zip-screen">
        <.zip_header
          title="Заклинания"
          subtitle="Личная библиотека и подготовка"
        />

        <section class="zip-content">
          <.link id="spell-new-link" navigate={~p"/spells/new"} class="zip-gold-button">
            Сотворить новое заклинание
          </.link>

          <div class="zip-panel-list">
            <div :if={@spells == []} id="spell-list-empty" class="zip-note">
              Личных заклинаний пока нет. Создайте первую формулу в круге инкантаций.
            </div>

            <article :for={spell <- @spells} id={"spell-card-#{spell.id}"} class="spell-library-card">
              <div>
                <h2>{spell.name}</h2>
                <p>{school_label(spell.school)} · {type_label(spell.spell_type)}</p>
                <small>{spell.description || spell.formula}</small>
              </div>
              <span>ур. {spell.level_requirement}</span>
            </article>
          </div>
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

  defp school_label(:fire), do: "Огонь"
  defp school_label(:water), do: "Вода"
  defp school_label(:earth), do: "Земля"
  defp school_label(:air), do: "Воздух"
  defp school_label(:life), do: "Жизнь"
  defp school_label(:death), do: "Смерть"
  defp school_label(:chaos), do: "Хаос"
  defp school_label(:order), do: "Порядок"
  defp school_label(other), do: to_string(other)

  defp type_label(:active), do: "боевое"
  defp type_label(:passive), do: "пассивное"
  defp type_label(:utility), do: "утилитарное"
  defp type_label(other), do: to_string(other)
end
