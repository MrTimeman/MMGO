defmodule MMGO.Events do
  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias MMGO.Accounts.Character
  alias MMGO.Bases
  alias MMGO.Events.{Instance, Option, Template}
  alias MMGO.Repo
  alias MMGO.Worlds.Location

  @default_templates %{
    city_arrival: %{
      location_kind: :city,
      title: "City Arrival",
      body:
        "You arrive in a city and can decide what kind of civic or economic activity to pursue.",
      options: [
        %{
          code: "shops",
          label: "Visit shops",
          action_key: "npc_shops",
          result_text: "Use /npc shops to see the merchants here."
        },
        %{
          code: "academy",
          label: "Visit academy",
          action_key: "academy",
          result_text: "Use /academy status or /academy start ... to work with the Academy."
        },
        %{
          code: "tavern",
          label: "Visit tavern",
          action_key: "party_hub",
          result_text: "Use /party, /club, or /org commands to organize socially."
        },
        %{
          code: "housing",
          label: "Check housing",
          action_key: "base",
          result_text: "Use /base buy or /base status to work with city property."
        }
      ]
    },
    tower_arrival: %{
      location_kind: :tower,
      title: "Tower Arrival",
      body:
        "The Tower hums with magical pressure. Delvers, duelists, and scholars cluster around the entrance.",
      options: [
        %{
          code: "party",
          label: "Form party",
          action_key: "party",
          result_text: "Use /party create or /expedition start to prepare a run."
        },
        %{
          code: "dungeon",
          label: "Approach dungeon",
          action_key: "dungeon",
          result_text: "Use /dungeon enter when your expedition is ready."
        },
        %{
          code: "library",
          label: "Visit library",
          action_key: "spells",
          result_text: "Use /spells or /academia commands to work with magical knowledge."
        }
      ]
    },
    base_arrival: %{
      location_kind: :base,
      title: "Base Arrival",
      body:
        "You are home. Storage, workshops, and recovery routines are all available from here.",
      options: [
        %{
          code: "storage",
          label: "Manage storage",
          action_key: "base_storage",
          result_text: "Use /base storage, /base deposit, and /base withdraw to manage items."
        },
        %{
          code: "craft",
          label: "Craft tools",
          action_key: "craft",
          result_text: "Use /craft workspace or /craft build ... to craft equipment."
        },
        %{
          code: "alchemy",
          label: "Brew potions",
          action_key: "alchemy",
          result_text: "Use /alchemy workspace or /alchemy brew ... to brew potions."
        },
        %{
          code: "rest",
          label: "Rest",
          action_key: "rest",
          result_text:
            "Rest is currently abstracted; this is where recovery systems can later connect."
        }
      ]
    },
    wilderness_arrival: %{
      location_kind: :wilderness,
      title: "Roadside Pause",
      body:
        "The road is dangerous. Other travelers might approach, and the terrain offers limited scavenging options.",
      options: [
        %{
          code: "scavenge",
          label: "Scavenge area",
          action_key: "scavenge",
          result_text: "Use /scavenge <resource> to search the local area."
        },
        %{
          code: "watch",
          label: "Stay alert",
          action_key: "road",
          result_text: "Use /road status or /road encounter <handle> to handle road interactions."
        },
        %{
          code: "move",
          label: "Continue travel",
          action_key: "routes",
          result_text: "Use /routes and /travel <slug> to continue on the road."
        }
      ]
    }
  }

  def current_event(%Character{} = character) do
    character = Repo.preload(character, :current_location)

    case active_instance_for_character(character.id) do
      %Instance{} = instance when instance.location_id == character.current_location_id ->
        preload_instance(instance)

      _other ->
        create_current_event(character)
    end
  end

  def resolve_option(%Instance{} = instance, option_code) when is_binary(option_code) do
    Repo.transaction(fn ->
      instance =
        Instance
        |> where([instance], instance.id == ^instance.id)
        |> lock("FOR UPDATE")
        |> Repo.one!()
        |> preload_instance()

      if instance.status != :active do
        Repo.rollback(event_changeset("event is not active"))
      end

      option = Enum.find(instance.template.options, &(&1.code == option_code))

      if is_nil(option) do
        Repo.rollback(event_changeset("option could not be found for this event"))
      end

      instance
      |> Instance.changeset(%{
        status: :resolved,
        selected_option_code: option.code,
        resolved_at: DateTime.utc_now(),
        metadata: Map.put(instance.metadata || %{}, "action_key", option.action_key)
      })
      |> Repo.update!()
      |> preload_instance()
      |> then(fn updated_instance -> %{instance: updated_instance, option: option} end)
    end)
    |> normalize_transaction_result()
  end

  def list_templates(realm_id \\ nil) do
    query =
      case realm_id do
        nil ->
          Template

        realm_id ->
          from template in Template,
            where: template.realm_id == ^realm_id or is_nil(template.realm_id)
      end

    Repo.all(from template in query, order_by: [asc: template.inserted_at], preload: [:options])
  end

  def ensure_defaults_for_realm(realm_id) when is_binary(realm_id) do
    Enum.map(@default_templates, fn {code, attrs} ->
      case Repo.get_by(Template, realm_id: realm_id, code: Atom.to_string(code)) do
        nil ->
          %Template{}
          |> Template.changeset(%{
            realm_id: realm_id,
            code: Atom.to_string(code),
            location_kind: attrs.location_kind,
            title: attrs.title,
            body: attrs.body,
            status: :active,
            metadata: %{}
          })
          |> Repo.insert!()
          |> then(fn template ->
            Enum.each(attrs.options, fn option_attrs ->
              %Option{}
              |> Option.changeset(Map.merge(option_attrs, %{template_id: template.id}))
              |> Repo.insert!()
            end)

            Repo.preload(template, :options)
          end)

        template ->
          Repo.preload(template, :options)
      end
    end)
  end

  defp create_current_event(%Character{} = character) do
    if is_nil(character.current_location_id) do
      nil
    else
      location = Repo.get!(Location, character.current_location_id)
      realm_id = character.realm_id
      _ = ensure_defaults_for_realm(realm_id)

      template_code = current_template_code(character, location)

      template =
        Repo.get_by(Template, realm_id: realm_id, code: template_code)
        |> Repo.preload(:options)

      %Instance{}
      |> Instance.changeset(%{
        character_id: character.id,
        realm_id: realm_id,
        location_id: location.id,
        template_id: template.id,
        status: :active,
        started_at: DateTime.utc_now(),
        metadata: %{}
      })
      |> Repo.insert!()
      |> preload_instance()
    end
  end

  defp current_template_code(%Character{} = character, %Location{} = location) do
    cond do
      not is_nil(Bases.active_base_at_location(character.id, location.id)) -> "base_arrival"
      location.kind == :tower -> "tower_arrival"
      location.kind == :city -> "city_arrival"
      true -> "wilderness_arrival"
    end
  end

  defp active_instance_for_character(character_id) do
    Repo.get_by(Instance, character_id: character_id, status: :active)
  end

  defp preload_instance(%Instance{} = instance) do
    Repo.preload(instance, template: [:options])
  end

  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, %Changeset{} = changeset}), do: {:error, changeset}

  defp normalize_transaction_result({:error, _step, %Changeset{} = changeset, _changes}),
    do: {:error, changeset}

  defp event_changeset(message) do
    %Instance{}
    |> Changeset.change()
    |> Changeset.add_error(:status, message)
  end
end
