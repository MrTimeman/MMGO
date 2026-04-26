defmodule MMGOWeb.GameLiveHelpers do
  import Phoenix.Component

  alias MMGO.Play

  def assign_current_character(socket, session) do
    character =
      case session["play_character_id"] || session[:play_character_id] do
        character_id when is_binary(character_id) -> Play.get_character(character_id)
        _other -> nil
      end

    character =
      case character do
        nil ->
          {:ok, character} = Play.ensure_browser_character()
          character

        character ->
          {:ok, character} = Play.prepare_character(character)
          character
      end

    assign(socket, :current_character, character)
  end
end
