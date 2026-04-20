defmodule MMGOWeb.PlaySession do
  import Plug.Conn

  alias MMGO.Play

  @session_key :play_character_id

  def fetch_current_character(conn) do
    case get_session(conn, @session_key) do
      character_id when is_binary(character_id) ->
        case Play.get_character(character_id) do
          nil -> create_browser_character(conn)
          character -> {:ok, conn, character}
        end

      _other ->
        create_browser_character(conn)
    end
  end

  defp create_browser_character(conn) do
    with {:ok, character} <- Play.ensure_browser_character() do
      {:ok, put_session(conn, @session_key, character.id), character}
    end
  end
end
