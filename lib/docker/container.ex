defmodule Docker.Container do
  alias Docker.Client
  alias Docker.Client.Response
  @moduledoc """
    This is the Container module for all interactions with Docker containers.
  """

  def all(host, opts \\ %{}) do
    "#{host}/containers/json"
    |> Client.add_query_params(opts)
    |> Client.send_request(:get)
    |> Response.parse(:all)
  end

  def list(host, opts \\ %{}) do
    case all(host, opts) do
      {:ok, results} -> Enum.map(results, &(&1["Id"]))
      {:error, reason} -> {:error, reason}
    end
  end

  @default_creation_params %{
      "Image"        => "nextacademy/ruby",
      "Tty"          => true,
      "OpenStdIn"    => true,
      "AttachStdin"  => true,
      "AttachStdout" => true,
      "AttachStderr" => true,
      "Cmd"          => ["sh"],
      "HostConfig" => %{
        "CapDrop": ["ALL"]
      }
  }

  # refer to https://docs.docker.com/engine/reference/api/docker_remote_api_v1.24/#/create-a-container
  def create(host, opts, params \\ []) do
    "#{host}/containers/create"
    |> Client.send_request(:post, Map.merge(@default_creation_params, opts), [], [params: params])
    |> Response.parse(:create)
  end

  def start(host, container_id, opts \\ %{}) do
    "#{host}/containers/#{container_id}/start"
    |> Client.send_request(:post, opts)
    |> Response.parse(:start)
  end

  def run(host, opts, params) do
    case create(host, opts, params) do
      {:ok, %{id: id}} ->
        case start(host, id) do
          {:ok, _} -> {:ok, %{id: id}}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  def stop(host, container_id, opts \\ %{}) do
    "#{host}/containers/#{container_id}/stop"
    |> Client.add_query_params(opts)
    |> Client.send_request(:post, opts)
    |> Response.parse(:stop)
  end

  def remove(host, container_id, opts \\ %{}) do
    "#{host}/containers/#{container_id}"
    |> Client.add_query_params(opts)
    |> Client.send_request(:delete)
    |> Response.parse(:remove)
  end

  def kill(host, container_id, stop_opts \\ %{}, remove_opts \\ %{}) do
    case stop(host, container_id, stop_opts) do
      {:ok, _} -> remove(host, container_id, remove_opts)
      {:error, :container_already_stopped} ->
        remove(host, container_id, remove_opts)
      error_message -> error_message
    end
  end

  def exec_create(host, container_id, opts \\ %{}) do
    "#{host}/containers/#{container_id}/exec"
    |> Client.send_request(:post, opts)
    |> Response.parse(:exec_create)
  end

  # bash is not required to be prepended
  # Docker.Container.exec_stream host, id, %{"Cmd" => ["rspec", "test.rb"], "AttachStdout" => true, "AttachStderr" => true}
  def exec_start(host, exec_id, %{"Detach" => true}) do
    "#{host}/exec/#{exec_id}/start"
    |> Client.send_request(:post, %{"Detach" => true})
    |> Response.parse(:exec_start)
  end

  def exec_start(host, exec_id, opts) do
    "#{host}/exec/#{exec_id}/start"
    |> Client.send_request(:post, opts, [], [stream_to: self()])
    |> Response.parse(:exec_start)
  end

  def exec_detached(host, container_id, create_opts \\ %{}) do
    case exec_create(host, container_id, create_opts) do
      {:ok, %{id: exec_id}} ->
        exec_start(host, exec_id, %{"Detach" => true})
      {:error, reason} -> {:error, reason}
    end
  end

  def exec_stream(host, container_id, create_opts \\ %{}) do
    case exec_create(host, container_id, create_opts) do
      {:ok, %{id: exec_id}} ->
        case exec_start(host, exec_id, %{}) do
          {:ok, _} -> stream_response()
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  def logs(host, container_id, opts \\ %{stdout: 1, stderr: 1}) do
    "#{host}/containers/#{container_id}/logs"
    |> Client.add_query_params(opts)
    |> Client.send_request(:get)
    |> parse_logs_response
  end

  def parse_logs_response(response), do: response

  def logs_stream(host, container_id, opts  \\ %{}) do
    "#{host}/containers/#{container_id}/logs"
    |> Client.add_query_params(opts)
    |> Client.send_request(:get, [], [stream_to: self()])
    |> parse_logs_stream_response
  end

  defp parse_logs_stream_response(%HTTPoison.AsyncResponse{id: _ref}), do: stream_response()

  @default_attach_params %{
    stream: 1,
    stdin: 1,
    stdout: 1,
    stderr: 1
  }

  # after executing this will open persistent tcp connection to stream stdin/stdout into/from container
  # receving pid will receive stdout/stderr the the form of
  # {:hackney_response, _conn, message} when is_binary(message)
  def attach(host, container_id, receiving_pid, opts \\ @default_attach_params) do
    "#{host}/containers/#{container_id}/attach"
    |> Client.add_query_params(opts)
    |> Client.start_persistent_connection(receiving_pid)
    |> parse_attach_response
  end

  defp parse_attach_response({:ok, connRef}), do: {:ok, %{connRef: connRef}}
  defp parse_attach_response(result), do: {:error, result}

  # obtain socket from attach function
  def stream_stdin(stdin, connRef) do
    Client.send_via_raw_tcp(stdin, connRef)
  end

  def stop_attach(connRef) do
    Client.close_persistent_connection(connRef)
  end

  defp stream_response(output \\ []) do
    receive do
      %HTTPoison.AsyncChunk{chunk: new_output} ->
        total_output = output ++ [new_output]
        stream_response(total_output)
      %HTTPoison.AsyncEnd{id: _ref} ->
        Enum.map(output, fn(chunk) ->
          if String.printable?(chunk) do
            chunk
          else
            chunk |> String.split_at(8) |> elem(1)
          end
        end)
      _ ->
        stream_response(output)
    end
  end

end

