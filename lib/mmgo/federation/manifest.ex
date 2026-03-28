defmodule MMGO.Federation.Manifest do
  alias Ecto.Changeset
  alias MMGO.Federation
  alias MMGO.Worlds
  alias MMGO.Worlds.Realm

  def read_file(path) when is_binary(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents),
         {:ok, manifest} <- Federation.validate_manifest(decoded) do
      {:ok, manifest}
    else
      {:error, %Jason.DecodeError{} = error} ->
        {:error,
         manifest_changeset("manifest file is not valid JSON: #{Exception.message(error)}")}

      {:error, reason} when is_binary(reason) ->
        {:error, manifest_changeset(reason)}

      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, manifest_changeset("manifest could not be read: #{inspect(reason)}")}
    end
  end

  def write_file(path, manifest) when is_binary(path) and is_map(manifest) do
    with {:ok, validated_manifest} <- Federation.validate_manifest(manifest),
         {:ok, json} <- Jason.encode(validated_manifest, pretty: true),
         :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, json <> "\n") do
      {:ok, path}
    else
      {:error, %Changeset{} = changeset} ->
        {:error, changeset}

      {:error, reason} ->
        {:error, manifest_changeset("manifest could not be written: #{inspect(reason)}")}
    end
  end

  def export_realm(realm_identifier, path) when is_binary(path) do
    with {:ok, realm} <- load_realm(realm_identifier) do
      write_file(path, Federation.export_realm_manifest(realm))
    end
  end

  def apply_local_manifest(path, opts \\ []) when is_binary(path) do
    with {:ok, manifest} <- read_file(path) do
      apply_local_manifest_map(manifest, opts)
    end
  end

  def apply_local_manifest_map(manifest, opts \\ []) when is_map(manifest) do
    with {:ok, manifest} <- Federation.validate_manifest(manifest) do
      slug = manifest["slug"]
      is_default = Keyword.get(opts, :set_default, false)
      status = normalize_realm_status(manifest["status"])

      with {:ok, entry_location_id} <- resolve_entry_location_id(manifest["entry_location_slug"]) do
        case Worlds.get_realm_by_slug(slug) do
          nil ->
            create_realm_from_manifest(manifest, status, is_default, entry_location_id)

          %Realm{} = realm ->
            update_realm_from_manifest(realm, manifest, status, is_default, entry_location_id)
        end
      end
    end
  end

  defp create_realm_from_manifest(manifest, status, is_default, entry_location_id) do
    attrs = manifest_to_realm_attrs(manifest, status, is_default, entry_location_id)

    %Realm{}
    |> Realm.changeset(attrs)
    |> MMGO.Repo.insert()
  end

  defp update_realm_from_manifest(
         %Realm{} = realm,
         manifest,
         status,
         is_default,
         entry_location_id
       ) do
    attrs = manifest_to_realm_attrs(manifest, status, is_default, entry_location_id)

    realm
    |> Realm.changeset(attrs)
    |> MMGO.Repo.update()
  end

  defp manifest_to_realm_attrs(manifest, status, is_default, entry_location_id) do
    %{
      slug: manifest["slug"],
      name: manifest["name"],
      status: status,
      ruleset_version: manifest["ruleset_version"] || 1,
      is_default: is_default,
      currency_code: manifest["currency_code"],
      public_endpoint: manifest["public_endpoint"],
      public_description: manifest["public_description"],
      operator_name: manifest["operator_name"],
      allow_migration: manifest["allow_migration"],
      population_hint: manifest["population_hint"],
      ruleset: manifest["ruleset"],
      metadata: manifest["metadata"] || %{},
      entry_location_id: entry_location_id
    }
  end

  defp resolve_entry_location_id(nil), do: {:ok, nil}

  defp resolve_entry_location_id(slug) when is_binary(slug) do
    case MMGO.Repo.get_by(MMGO.Worlds.Location, slug: slug) do
      nil -> {:error, manifest_changeset("entry location slug #{slug} was not found locally")}
      location -> {:ok, location.id}
    end
  end

  defp load_realm(%Realm{} = realm), do: {:ok, realm}

  defp load_realm(realm_id) when is_binary(realm_id) do
    case Worlds.get_realm_by_slug(realm_id) do
      %Realm{} = realm -> {:ok, realm}
      nil -> {:error, manifest_changeset("realm could not be found")}
    end
  end

  defp normalize_realm_status("active"), do: :active
  defp normalize_realm_status("maintenance"), do: :maintenance
  defp normalize_realm_status("archived"), do: :archived
  defp normalize_realm_status(_status), do: :active

  defp manifest_changeset(message) do
    {%{}, %{slug: :string}}
    |> Changeset.cast(%{}, [])
    |> Changeset.add_error(:slug, message)
  end
end
