defmodule MMGO.AI.Providers.GeminiTest do
  use ExUnit.Case, async: false

  alias MMGO.AI.Providers.Gemini

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, MMGO.AI.Providers.Gemini)

    Application.put_env(:mmgo, MMGO.AI.Providers.Gemini,
      api_base_url: "http://localhost:#{bypass.port}",
      api_key: "gemini-test-key"
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.AI.Providers.Gemini, original)
      else
        Application.delete_env(:mmgo, MMGO.AI.Providers.Gemini)
      end
    end)

    %{bypass: bypass}
  end

  test "compile_spell/2 posts JSON schema requests to Gemini", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/models/gemini-3-flash-test:generateContent", fn conn ->
      assert Plug.Conn.get_req_header(conn, "x-goog-api-key") == ["gemini-test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s("responseMimeType":"application/json")

      Plug.Conn.resp(
        conn,
        200,
        ~s({"candidates":[{"content":{"parts":[{"text":"{\\"name\\":\\"Ignis Sphaera\\",\\"formula\\":\\"Ignis Sphaera\\",\\"school\\":\\"fire\\",\\"targeting\\":\\"enemy\\",\\"delivery_form\\":\\"sphere\\",\\"effects\\":[{\\"applies_to\\":\\"target\\",\\"state\\":\\"impact\\",\\"intensity\\":12,\\"duration\\":0}],\\"failure_profile\\":{\\"difficulty\\":10,\\"base_success_rate\\":85,\\"partial_success_rate\\":10,\\"backlash_damage\\":0}}"}]}}]})
      )
    end)

    prompt_payload = %{
      system_prompt: "Compile the spell.",
      user_prompt: "{}",
      schema: %{type: "object", properties: %{name: %{type: "string"}}}
    }

    assert {:ok, %{"name" => "Ignis Sphaera", "school" => "fire"}} =
             Gemini.compile_spell(prompt_payload, model: "gemini-3-flash-test")
  end

  test "narrate_turn/2 returns plain text narration", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/models/g3f-lite-test:generateContent", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s("responseMimeType":"text/plain")

      Plug.Conn.resp(
        conn,
        200,
        ~s({"candidates":[{"content":{"parts":[{"text":"A wall of fire shudders through the chamber."}]}}]})
      )
    end)

    prompt_payload = %{system_prompt: "Narrate the turn.", user_prompt: "{}"}

    assert {:ok, "A wall of fire shudders through the chamber."} =
             Gemini.narrate_turn(prompt_payload, model: "g3f-lite-test")
  end

  test "orchestrate_combat/2 posts JSON schema requests to Gemini", %{bypass: bypass} do
    Bypass.expect_once(
      bypass,
      "POST",
      "/models/g3f-orchestrator-test:generateContent",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ ~s("responseMimeType":"application/json")
        assert body =~ ~s(\\"resolution_id\\":\\"r-1\\")

        Plug.Conn.resp(
          conn,
          200,
          ~s({"candidates":[{"content":{"parts":[{"text":"{\\"picks\\":[{\\"resolution_id\\":\\"r-1\\",\\"outcome\\":\\"success\\",\\"chosen_roll\\":40,\\"effect_picks\\":[{\\"effect_index\\":0,\\"intensity\\":14}]}]}"}]}}]})
        )
      end
    )

    prompt_payload = %{
      system_prompt: "Orchestrate combat.",
      user_prompt: ~s({"resolution_id":"r-1"}),
      schema: %{type: "object", properties: %{picks: %{type: "array"}}}
    }

    assert {:ok, %{"picks" => [%{"resolution_id" => "r-1", "outcome" => "success"}]}} =
             Gemini.orchestrate_combat(prompt_payload, model: "g3f-orchestrator-test")
  end

  test "tick_dungeon/2 posts JSON schema requests to Gemini", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/models/g3f-dungeon-test:generateContent", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ ~s("responseMimeType":"application/json")
      assert body =~ ~s("floor_directives")

      Plug.Conn.resp(
        conn,
        200,
        ~s({"candidates":[{"content":{"parts":[{"text":"{\\"floor_directives\\":[{\\"floor_id\\":\\"floor-1\\",\\"threat_delta\\":2,\\"resource_delta\\":-1,\\"connection_shift\\":\\"stabilize\\",\\"anomaly_tag\\":\\"none\\"}],\\"summary\\":\\"steady\\"}"}]}}]})
      )
    end)

    prompt_payload = %{
      system_prompt: "Tick the dungeon.",
      user_prompt: ~s({"floors":[{"id":"floor-1"}]}),
      schema: %{type: "object", properties: %{floor_directives: %{type: "array"}}}
    }

    assert {:ok, %{"floor_directives" => [%{"floor_id" => "floor-1"}]}} =
             Gemini.tick_dungeon(prompt_payload, model: "g3f-dungeon-test")
  end

  test "compile_spell/2 fails without an API key" do
    original = Application.get_env(:mmgo, MMGO.AI.Providers.Gemini)

    Application.put_env(:mmgo, MMGO.AI.Providers.Gemini,
      api_base_url: "https://example.test",
      api_key: nil
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.AI.Providers.Gemini, original)
      else
        Application.delete_env(:mmgo, MMGO.AI.Providers.Gemini)
      end
    end)

    assert {:error, :missing_api_key} =
             Gemini.compile_spell(%{system_prompt: "", user_prompt: "", schema: %{}},
               model: "gemini-3-flash-test"
             )
  end
end
