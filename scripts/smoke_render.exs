# Smoke-render routes without touching the normal dev server.
#
#   mix run --no-start scripts/smoke_render.exs /trade /inventory
#
# Starts the endpoint on SMOKE_PORT (default 4909), GETs each route,
# prints the status code, and on any 4xx/5xx dumps the error text and
# exits 1. Use a unique SMOKE_PORT if running concurrently.

routes = System.argv()

if routes == [] do
  IO.puts("usage: mix run --no-start scripts/smoke_render.exs /route [/route ...]")
  System.halt(2)
end

port = String.to_integer(System.get_env("SMOKE_PORT") || "4909")

Application.load(:mmgo)

endpoint_config =
  Application.get_env(:mmgo, MMGOWeb.Endpoint)
  |> Keyword.merge(http: [ip: {127, 0, 0, 1}, port: port], server: true, watchers: [])

Application.put_env(:mmgo, MMGOWeb.Endpoint, endpoint_config)

{:ok, _} = Application.ensure_all_started(:mmgo)
{:ok, _} = Application.ensure_all_started(:inets)

results =
  for route <- routes do
    url = ~c"http://127.0.0.1:#{port}#{route}"

    case :httpc.request(:get, {url, []}, [{:timeout, 15_000}], []) do
      {:ok, {{_, code, _}, _, body}} ->
        IO.puts("#{code}  #{route}")
        {route, code, to_string(body)}

      {:error, reason} ->
        IO.puts("ERR  #{route}  #{inspect(reason)}")
        {route, 599, inspect(reason)}
    end
  end

failures = Enum.filter(results, fn {_, code, _} -> code >= 400 end)

for {route, code, body} <- failures do
  IO.puts("\n=== #{route} → #{code} ===")

  body
  |> String.replace(~r/<[^>]+>/, " ")
  |> String.replace(~r/\s+/, " ")
  |> String.slice(0, 1500)
  |> IO.puts()
end

if failures != [], do: System.halt(1)
IO.puts("all #{length(results)} routes ok")
