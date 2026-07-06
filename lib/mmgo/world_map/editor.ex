defmodule MMGO.WorldMap.Editor do
  @moduledoc """
  Filesystem helpers for `MMGOWeb.MapEditorLive`: sprite storage and the
  `manifest.json` catalog.

  Kept separate from `MMGO.WorldMap` (which only knows about the hex/terrain
  JSON file) so the read-only map loader isn't coupled to editor-only
  concerns like file uploads.
  """

  @manifest_filename "manifest.json"

  @doc """
  Returns the directory the editor reads/writes sprite images and
  `manifest.json` from.

  Uses the `:mmgo, :sprites_path` config when set (dev/test point this at the
  project source tree), falling back to the priv dir bundled with the
  compiled release.
  """
  def sprites_dir do
    case Application.get_env(:mmgo, :sprites_path) do
      path when is_binary(path) -> path
      _ -> Application.app_dir(:mmgo, "priv/static/sprites")
    end
  end

  # Directory Plug.Static actually serves `/sprites/*` from.
  #
  # When `:sprites_path` is explicitly configured (dev, test), it already
  # points at the project's source `priv/` tree, and `Application.app_dir/2`
  # resolves to the *same* physical directory there (priv is symlinked into
  # `_build/<env>/lib/mmgo`) — so no copy is needed, and we must not treat
  # `app_dir` as a distinct "served" directory in that case (doing so would
  # make every write also land in the real project priv dir, which is
  # exactly what config/test.exs's tmp `:sprites_path` is meant to avoid).
  #
  # In a compiled release there's no `:sprites_path` override, `sprites_dir/0`
  # falls back to `app_dir` itself, and this function is never consulted
  # (see `maybe_copy_to_served_dir/2`), so the copy is skipped there too —
  # there's nothing else to copy to.
  defp served_dir do
    if Application.get_env(:mmgo, :sprites_path) do
      nil
    else
      Application.app_dir(:mmgo, "priv/static/sprites")
    end
  end

  defp manifest_path(dir \\ sprites_dir()) do
    Path.join(dir, @manifest_filename)
  end

  @doc "Loads and decodes `manifest.json`, defaulting to `%{\"sprites\" => []}` if missing/invalid."
  def load_sprite_manifest do
    path = manifest_path()

    with true <- File.exists?(path),
         {:ok, contents} <- File.read(path),
         {:ok, json} <- Jason.decode(contents) do
      Map.put_new(json, "sprites", [])
    else
      _ -> %{"sprites" => []}
    end
  end

  @doc """
  Copies the uploaded sprite file at `tmp_path` into the sprites source
  directory (and the served static directory, if different) under
  `filename`.
  """
  def store_sprite(tmp_path, filename) do
    dest = Path.join(sprites_dir(), filename)

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.cp(tmp_path, dest) do
      maybe_copy_to_served_dir(dest, filename)
      :ok
    end
  end

  defp maybe_copy_to_served_dir(source_dest, filename) do
    case served_dir() do
      nil ->
        :ok

      dir ->
        served = Path.join(dir, filename)

        if Path.expand(served) != Path.expand(source_dest) do
          case File.mkdir_p(Path.dirname(served)) do
            :ok -> File.cp(source_dest, served)
            _ -> :ok
          end
        end

        :ok
    end
  end

  @doc """
  Adds or updates an entry in `manifest.json` for `sprite_id`, atomically
  (write to a temp file, then rename), and returns the updated manifest.
  """
  def upsert_sprite_manifest(sprite_id, filename, terrain) do
    manifest = load_sprite_manifest()
    sprites = manifest["sprites"] || []

    entry = %{"id" => sprite_id, "file" => filename, "terrain" => terrain}

    sprites =
      case Enum.find_index(sprites, &(&1["id"] == sprite_id)) do
        nil -> sprites ++ [entry]
        index -> List.replace_at(sprites, index, entry)
      end

    updated = Map.put(manifest, "sprites", sprites)

    with :ok <- write_manifest(updated) do
      {:ok, updated}
    end
  end

  defp write_manifest(manifest) do
    path = manifest_path()
    tmp_path = path <> ".tmp"
    contents = Jason.encode!(manifest, pretty: true)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, contents <> "\n"),
         :ok <- File.rename(tmp_path, path) do
      maybe_copy_manifest_to_served_dir(path)
      :ok
    end
  end

  defp maybe_copy_manifest_to_served_dir(source_path) do
    case served_dir() do
      nil ->
        :ok

      dir ->
        served = manifest_path(dir)

        if Path.expand(served) != Path.expand(source_path) do
          case File.mkdir_p(Path.dirname(served)) do
            :ok -> File.cp(source_path, served)
            _ -> :ok
          end
        end

        :ok
    end
  end
end
