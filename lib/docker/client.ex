defmodule Docker.Client do
  @moduledoc """
    This module handles formatting the HTTP requests/raw tcp connection
  """
  use HTTPoison.Base

  def send_request(url, method, body \\ "", headers \\ [], opts \\ []) do
    json_body = Jason.encode!(body)
    json_headers = headers ++ [{"Content-Type", "application/json"}]
    merged_opts = opts ++ default_options()
    request!(method, url, json_body, json_headers, merged_opts)
  end

  def process_response_body(body) do
    case Jason.decode(body) do
      {:ok, json} -> json
      _ -> body
    end
  end

  # returns {:ok, connRef} if successful
  def start_persistent_connection(url, receiving_pid) do
    body = ""
    headers = [{"Content-Type", "application/json"}]
    method = :post
    opts = [:async, connect_timeout: :infinity, recv_timeout: :infinity, active: true, stream_to: receiving_pid]
    ssl_opts = Application.get_env(:docker_elixir, :ssl_options)
    all_opts = opts ++ [ssl_options: ssl_opts]
    :hackney.request(method, url, headers, body, all_opts)
  end

  def send_via_raw_tcp(data, connRef) do
    socket = connRef |> :hackney.request_info |> Keyword.get(:socket)
    case socket do
      {:sslsocket, _tcp, _pid} -> :hackney_ssl.send(socket, data)
      _ -> :hackney_tcp.send(socket, data)
    end
  end

  def close_persistent_connection(connRef) do
    socket = connRef |> :hackney.request_info |> Keyword.get(:socket)
    case socket do
      {:sslsocket, _tcp, _pid} -> :hackney_ssl.close(socket)
      _ -> :hackney_tcp.close(socket)
    end
  end

  def add_query_params(url, params) do
    "#{url}?#{URI.encode_query(params)}"
  end

  def default_options do
    [hackney:
     [ssl_options:
       Application.get_env(:docker_elixir, :ssl_options)
     ],
    connect_timeout: 5000,
    recv_timeout: 30000,
    timeout: 30000
   ]
  end
end

