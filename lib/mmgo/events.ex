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
      title: "Прибытие в город",
      body:
        "Городские стены дают передышку: здесь можно учиться, готовиться к пути и искать полезные связи.",
      options: [
        %{
          code: "shops",
          label: "Осмотреть лавки",
          action_key: "npc_shops",
          result_text: "Торговая книга открыта: сравните предложения и выставьте свой товар."
        },
        %{
          code: "academy",
          label: "Посетить Академию",
          action_key: "academy",
          result_text: "Академия ждёт вас."
        },
        %{
          code: "tavern",
          label: "Найти спутников",
          action_key: "party_hub",
          result_text: "В таверне уже собирают группы: найдите или создайте отряд."
        },
        %{
          code: "housing",
          label: "Проверить жильё",
          action_key: "base",
          result_text: "Проверьте владение, припасы и доступные работы базы."
        }
      ]
    },
    tower_arrival: %{
      location_kind: :tower,
      title: "У подножия Башни",
      body:
        "Башня гудит от магического давления. У входа собираются исследователи, дуэлянты и искатели глубин.",
      options: [
        %{
          code: "party",
          label: "Собрать отряд",
          action_key: "party",
          result_text: "Соберите отряд, пригласите спутников и согласуйте маршрут."
        },
        %{
          code: "dungeon",
          label: "Подойти к глубинам",
          action_key: "dungeon",
          result_text: "Для спуска нужен подготовленный отряд."
        },
        %{
          code: "library",
          label: "Открыть гримуар",
          action_key: "spells",
          result_text: "Магические знания доступны в гримуаре."
        }
      ]
    },
    base_arrival: %{
      location_kind: :base,
      title: "Возвращение на базу",
      body:
        "Вы дома. Здесь хранят припасы, готовят инструменты и восстанавливаются после дороги.",
      options: [
        %{
          code: "storage",
          label: "Открыть хранилище",
          action_key: "base_storage",
          result_text: "Склад базы открыт: здесь лежат припасы и снаряжение."
        },
        %{
          code: "craft",
          label: "Работать в мастерской",
          action_key: "craft",
          result_text: "Верстак готов: создавайте и чините снаряжение."
        },
        %{
          code: "alchemy",
          label: "Заняться алхимией",
          action_key: "alchemy",
          result_text: "Лаборатория готова: выбирайте доступные рецепты."
        },
        %{
          code: "rest",
          label: "Отдохнуть",
          action_key: "rest",
          result_text: "Отдохните у запасов базы и восстановите силы."
        }
      ]
    },
    wilderness_arrival: %{
      location_kind: :wilderness,
      title: "Остановка в глуши",
      body:
        "Дорога опасна. Здесь могут встретиться другие путники, а местность иногда отдаёт скудные ресурсы.",
      options: [
        %{
          code: "scavenge",
          label: "Обыскать местность",
          action_key: "scavenge",
          result_text: "Осмотрите доступные ниже источники ресурсов."
        },
        %{
          code: "watch",
          label: "Следить за дорогой",
          action_key: "road",
          result_text: "Следите за путниками поблизости."
        },
        %{
          code: "move",
          label: "Продолжить путь",
          action_key: "routes",
          result_text: "Проложите следующий маршрут на карте."
        }
      ]
    },
    dungeon_arrival: %{
      location_kind: :dungeon_entrance,
      title: "Перед вратами подземелья",
      body:
        "За древними вратами начинается опасная глубина. Спускаться туда в одиночку неразумно — сначала подготовьте отряд и припасы.",
      options: [
        %{
          code: "dungeon",
          label: "Готовиться к спуску",
          action_key: "dungeon",
          result_text: "Для спуска нужен подготовленный отряд."
        },
        %{
          code: "party",
          label: "Искать спутников",
          action_key: "party",
          result_text: "Соберите отряд и подготовьте его к спуску."
        },
        %{
          code: "move",
          label: "Вернуться на карту",
          action_key: "routes",
          result_text: "Проложите следующий маршрут на карте."
        }
      ]
    }
  }

  # These strings shipped with the seeded templates before the corresponding
  # browser routes existed. They are only used to refresh exact old defaults;
  # custom realm writing is deliberately left untouched.
  @stale_default_result_texts %{
    "city_arrival" => %{
      "shops" => "Торговая книга этой локации ещё готовится.",
      "tavern" => "Здесь скоро появится сбор отрядов.",
      "housing" => "Дела базы доступны после обустройства владения."
    },
    "tower_arrival" => %{
      "party" => "Сбор отрядов скоро станет доступен здесь."
    },
    "base_arrival" => %{
      "storage" => "Хранилище базы ещё готовится к работе.",
      "craft" => "Мастерская откроется после обустройства базы.",
      "alchemy" => "Алхимическая лаборатория ещё закрыта.",
      "rest" => "Здесь можно передохнуть, когда появится отдых базы."
    },
    "dungeon_arrival" => %{
      "party" => "Сбор отрядов скоро станет доступен здесь."
    }
  }

  def current_event(%Character{} = character) do
    Repo.transaction(fn ->
      character = character |> lock_character!() |> Repo.preload(:current_location)

      case active_instance_for_character(character.id) do
        %Instance{} = instance when instance.location_id == character.current_location_id ->
          preload_instance(instance)

        %Instance{} = stale_instance ->
          stale_instance
          |> Instance.changeset(%{
            status: :resolved,
            selected_option_code: "departed",
            resolved_at: DateTime.utc_now()
          })
          |> Repo.update!()

          create_current_event(character)

        nil ->
          create_current_event(character)
      end
    end)
    |> case do
      {:ok, event} -> event
      {:error, reason} -> raise "could not load current event: #{inspect(reason)}"
    end
  end

  def get_instance(id) when is_binary(id) do
    Instance
    |> Repo.get(id)
    |> case do
      nil -> nil
      instance -> preload_instance(instance)
    end
  end

  def get_instance(_id), do: nil

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
          template
          |> Repo.preload(:options)
          |> refresh_stale_default_options!(attrs.options)
      end
    end)
  end

  defp refresh_stale_default_options!(%Template{} = template, option_attrs) do
    Enum.each(option_attrs, fn attrs ->
      stale_result_text = get_in(@stale_default_result_texts, [template.code, attrs.code])

      case Enum.find(template.options, &(&1.code == attrs.code)) do
        %Option{} = option ->
          if option.action_key == attrs.action_key and option.result_text == stale_result_text do
            option
            |> Option.changeset(%{result_text: attrs.result_text})
            |> Repo.update!()
          end

        nil ->
          :ok
      end
    end)

    Repo.preload(template, :options, force: true)
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
      location.kind == :dungeon_entrance -> "dungeon_arrival"
      location.kind == :city -> "city_arrival"
      true -> "wilderness_arrival"
    end
  end

  defp active_instance_for_character(character_id) do
    Repo.one(
      from instance in Instance,
        where: instance.character_id == ^character_id and instance.status == :active,
        order_by: [desc: instance.inserted_at],
        limit: 1
    )
  end

  defp lock_character!(%Character{id: character_id}) do
    Character
    |> where([character], character.id == ^character_id)
    |> lock("FOR UPDATE")
    |> Repo.one!()
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
