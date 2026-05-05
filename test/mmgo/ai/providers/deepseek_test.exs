defmodule MMGO.AI.Providers.DeepSeekTest do
  use ExUnit.Case, async: false

  alias MMGO.AI.Providers.DeepSeek

  setup do
    bypass = Bypass.open()
    original = Application.get_env(:mmgo, MMGO.AI.Providers.DeepSeek)

    Application.put_env(:mmgo, MMGO.AI.Providers.DeepSeek,
      api_base_url: "http://localhost:#{bypass.port}",
      api_key: "deepseek-test-key",
      max_tokens: 2048,
      thinking: nil,
      reasoning_effort: nil
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.AI.Providers.DeepSeek, original)
      else
        Application.delete_env(:mmgo, MMGO.AI.Providers.DeepSeek)
      end
    end)

    %{bypass: bypass}
  end

  test "compile_spell/2 posts OpenAI-compatible JSON-mode requests to DeepSeek", %{
    bypass: bypass
  } do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer deepseek-test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["model"] == "deepseek-v4-flash-test"
      assert decoded["response_format"] == %{"type" => "json_object"}
      assert decoded["stream"] == false
      assert decoded["max_tokens"] == 2048

      assert [%{"role" => "system", "content" => system}, %{"role" => "user"}] =
               decoded["messages"]

      assert system =~ "Output JSON only"
      assert system =~ "JSON Schema"

      Plug.Conn.resp(
        conn,
        200,
        ~s({"choices":[{"message":{"content":"{\\"name\\":\\"Ignis Sphaera\\",\\"formula\\":\\"Ignis Sphaera\\",\\"school\\":\\"fire\\",\\"targeting\\":\\"enemy\\",\\"delivery_form\\":\\"sphere\\",\\"effects\\":[{\\"applies_to\\":\\"target\\",\\"state\\":\\"impact\\",\\"intensity\\":12,\\"duration\\":0}],\\"failure_profile\\":{\\"difficulty\\":10,\\"base_success_rate\\":85,\\"partial_success_rate\\":10,\\"backlash_damage\\":0}}"}}]})
      )
    end)

    prompt_payload = %{
      system_prompt: "Compile the spell. Output JSON only.",
      user_prompt: "{}",
      schema: %{type: "object", properties: %{name: %{type: "string"}}}
    }

    assert {:ok, %{"name" => "Ignis Sphaera", "school" => "fire"}} =
             DeepSeek.compile_spell(prompt_payload, model: "deepseek-v4-flash-test")
  end

  test "narrate_turn/2 returns plain text narration", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      refute Map.has_key?(decoded, "response_format")
      assert decoded["temperature"] == 0.7

      Plug.Conn.resp(
        conn,
        200,
        ~s({"choices":[{"message":{"content":"Огонь срывается с камня и оставляет врага открытым."}}]})
      )
    end)

    prompt_payload = %{system_prompt: "Narrate the turn.", user_prompt: "{}"}

    assert {:ok, "Огонь срывается с камня и оставляет врага открытым."} =
             DeepSeek.narrate_turn(prompt_payload, model: "deepseek-v4-flash-test")
  end

  test "orchestrate_combat/2 decodes JSON-mode content", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["response_format"] == %{"type" => "json_object"}
      assert decoded["temperature"] == 0.4

      Plug.Conn.resp(
        conn,
        200,
        ~s({"choices":[{"message":{"content":"{\\"picks\\":[{\\"resolution_id\\":\\"r-1\\",\\"outcome\\":\\"success\\",\\"chosen_roll\\":40,\\"effect_picks\\":[{\\"effect_index\\":0,\\"intensity\\":14}]}]}"}}]})
      )
    end)

    prompt_payload = %{
      system_prompt: "Orchestrate combat. Output JSON only.",
      user_prompt: ~s({"resolution_id":"r-1"}),
      schema: %{type: "object", properties: %{picks: %{type: "array"}}}
    }

    assert {:ok, %{"picks" => [%{"resolution_id" => "r-1", "outcome" => "success"}]}} =
             DeepSeek.orchestrate_combat(prompt_payload, model: "deepseek-v4-flash-test")
  end

  test "tick_dungeon/2 decodes JSON-mode content", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      decoded = Jason.decode!(body)

      assert decoded["response_format"] == %{"type" => "json_object"}
      assert decoded["temperature"] == 0.5

      Plug.Conn.resp(
        conn,
        200,
        ~s({"choices":[{"message":{"content":"{\\"floor_directives\\":[{\\"floor_id\\":\\"floor-1\\",\\"threat_delta\\":2,\\"resource_delta\\":-1,\\"connection_shift\\":\\"stabilize\\",\\"anomaly_tag\\":\\"none\\"}],\\"summary\\":\\"steady\\"}"}}]})
      )
    end)

    prompt_payload = %{
      system_prompt: "Tick the dungeon. Output JSON only.",
      user_prompt: ~s({"floors":[{"id":"floor-1"}]}),
      schema: %{type: "object", properties: %{floor_directives: %{type: "array"}}}
    }

    assert {:ok, %{"floor_directives" => [%{"floor_id" => "floor-1"}]}} =
             DeepSeek.tick_dungeon(prompt_payload, model: "deepseek-v4-flash-test")
  end

  test "compile_spell/2 fails without an API key" do
    original = Application.get_env(:mmgo, MMGO.AI.Providers.DeepSeek)

    Application.put_env(:mmgo, MMGO.AI.Providers.DeepSeek,
      api_base_url: "https://example.test",
      api_key: nil
    )

    on_exit(fn ->
      if original do
        Application.put_env(:mmgo, MMGO.AI.Providers.DeepSeek, original)
      else
        Application.delete_env(:mmgo, MMGO.AI.Providers.DeepSeek)
      end
    end)

    assert {:error, :missing_api_key} =
             DeepSeek.compile_spell(%{system_prompt: "", user_prompt: "", schema: %{}},
               model: "deepseek-v4-flash-test"
             )
  end

  test "non-2xx responses include decoded API error payload", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/chat/completions", fn conn ->
      Plug.Conn.resp(conn, 401, ~s({"error":{"message":"bad key"}}))
    end)

    assert {:error, {:deepseek_api, 401, %{"error" => %{"message" => "bad key"}}}} =
             DeepSeek.narrate_turn(%{system_prompt: "", user_prompt: ""},
               model: "deepseek-v4-flash-test"
             )
  end
end
