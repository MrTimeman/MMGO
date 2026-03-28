defmodule Mix.Tasks.Mmgo.Realm.Apply do
  use Mix.Task

  @shortdoc "Applies a realm manifest JSON file to the local database"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, positional_args, _invalid} =
      OptionParser.parse(args, switches: [set_default: :boolean])

    case positional_args do
      [path] ->
        case MMGO.Federation.Manifest.apply_local_manifest(path,
               set_default: opts[:set_default] || false
             ) do
          {:ok, realm} ->
            Mix.shell().info("Realm manifest applied: #{realm.slug}")

          {:error, changeset} ->
            Mix.raise("Could not apply realm manifest: #{format_changeset(changeset)}")
        end

      _other ->
        Mix.raise("Usage: mix mmgo.realm.apply <path> [--set-default]")
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
