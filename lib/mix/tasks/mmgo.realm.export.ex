defmodule Mix.Tasks.Mmgo.Realm.Export do
  use Mix.Task

  @shortdoc "Exports a realm manifest to JSON"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [realm_slug, path] ->
        case MMGO.Federation.Manifest.export_realm(realm_slug, path) do
          {:ok, _path} ->
            Mix.shell().info("Realm manifest exported to #{path}")

          {:error, changeset} ->
            Mix.raise("Could not export realm manifest: #{format_changeset(changeset)}")
        end

      _other ->
        Mix.raise("Usage: mix mmgo.realm.export <realm-slug> <path>")
    end
  end

  defp format_changeset(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, messages} -> "#{field}: #{Enum.join(messages, ", ")}" end)
    |> Enum.join("; ")
  end
end
