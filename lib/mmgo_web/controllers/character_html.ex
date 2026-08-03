defmodule MMGOWeb.CharacterHTML do
  use MMGOWeb, :html

  embed_templates "character_html/*"

  def sealed_spirit?(character),
    do: MMGO.Accounts.CharacterProfiles.sealed_spirit?(character)

  def playable?(character, blocked_character_ids) do
    character.status in [:active, :frozen, :new] and
      not MapSet.member?(blocked_character_ids, character.id)
  end

  def status_label(:active), do: "В мире"
  def status_label(:frozen), do: "Заморожен"
  def status_label(:new), do: "Ожидает посвящения"
  def status_label(:retired), do: "Архив"
  def status_label(_status), do: "Неизвестно"

  def unavailable_label(%{status: :retired}), do: "Дело передано в архив"
  def unavailable_label(%{status: :frozen}), do: "Профиль запечатан до завершения перехода"
  def unavailable_label(_character), do: "Профиль пока недоступен"
end
