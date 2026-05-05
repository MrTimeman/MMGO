defmodule MMGOWeb.PlayController do
  use MMGOWeb, :controller

  def show(conn, _params) do
    conn
    |> put_root_layout(false)
    |> render(:hub, csrf_token: get_csrf_token())
  end

  def editor(conn, _params) do
    serve_prototype(conn, "window.__EDITOR_MODE = true;")
  end

  defp serve_prototype(conn, extra_script) do
    path = Path.join(:code.priv_dir(:mmgo), "static/mmgo-ui/MMGO.html")

    csrf_token = get_csrf_token()

    prototype_html =
      case File.read(path) do
        {:ok, content} ->
          content
          |> String.replace(
            "<head>",
            "<head>\n<meta name=\"csrf-token\" content=\"#{csrf_token}\">"
          )
          |> then(fn html ->
            if extra_script do
              String.replace(html, "<body>", "<body>\n<script>#{extra_script}</script>")
            else
              html
            end
          end)

        {:error, _reason} ->
          "<!DOCTYPE html><html><body><h1>MMGO prototype not found</h1><pre>#{path}</pre></body></html>"
      end

    conn
    |> put_root_layout(false)
    |> render(:show, page_title: "MMGO", prototype_html: prototype_html)
  end
end
