defmodule Mix.Tasks.Mmgo.Realm.Validate do
  use Mix.Task

  @shortdoc "Validates a realm manifest JSON file"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [path] ->
        case MMGO.Federation.Manifest.read_file(path) do
          {:ok, manifest} ->
            Mix.shell().info("Realm manifest is valid: #{manifest["slug"]}")

          {:error, changeset} ->
            Mix.raise("Manifest validation failed: #{format_changeset(changeset)}")
        end

      _other ->
        Mix.raise("Usage: mix mmgo.realm.validate <path>")
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
