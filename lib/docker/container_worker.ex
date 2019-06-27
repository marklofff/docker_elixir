defmodule Docker.ContainerWorker do 
  alias Docker.ContainerRegistry
  alias Docker.Container
  use GenServer

  @default_timeout 300_000
  @default_container_opts %{
    "NetworkDisabled" => true,
    "HostConfig" => %{
      "Memory" => 50_000_000,
      "MemorySwap" => 50_000_000,
      "KernelMemory" => 50_000_000,
      "CpuQuota" => 5_000
    }
  }

  def start_link(opts \\ %{}) do
    GenServer.start_link(__MODULE__, opts)
  end

  def exec(pid, commands) do
    GenServer.call(pid, {:exec, commands}, 15_000)
  end

  def stdin(pid, stdin) do
    GenServer.cast(pid, {:stdin, stdin})
  end

  def send_files(pid, blobs) when is_list(blobs) do
    Enum.each(blobs, fn blob ->
      send_file(pid, blob.name, blob.contents)
    end)
  end

  def send_file(pid, filename, file_contents) do
    commands = save_file_commands(filename, file_contents)
    GenServer.cast(pid, {:exec_detached, commands})
  end

  def stop(pid) do
    GenServer.stop(pid, :shutdown)
  end

  ### Server Callbacks
  def init(opts \\ %{}) do
    {:ok, timer_ref} = set_keep_alive_timer()
    case create_container(opts) do
      {:ok, container_id} ->
        {:ok, %{timer: timer_ref, container_id: container_id}}
      {:error, _reason} ->
        {:stop, :error_creating_container}
    end
  end
  
  def handle_call({:exec, commands}, _from, state) do
    try do
      container_id = Map.get(state, :container_id)
      json = Container.exec_stream(host(), container_id,
                                   %{
                                     "Cmd" => commands,
                                     "AttachStdout" => true,
                                     "AttachStderr" => true
                                   }
                                  )
      {:reply, {:ok, json}, reset_timer(state)}
    rescue
      reason ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_cast({:exec_detached, commands}, state) do
    container_id = Map.get(state, :container_id)
    Container.exec_detached(host(), container_id,
                            %{
                              "Cmd" => commands
                             }
                            )
    {:noreply, reset_timer(state)}
  end

  def handle_cast({:stdin, stdin}, state) do
    case state do
      %{persistent_conn: connRef} ->
        Container.stream_stdin(stdin, connRef)
        {:noreply, reset_timer(state)}
      %{container_id: container_id} ->
        {:ok, %{connRef: connRef}} = Container.attach(host(), container_id, self())
        Container.stream_stdin(stdin, connRef)
        new_state = Map.put(state, :persistent_conn, connRef)
        {:noreply, reset_timer(new_state)}
    end
  end

  def terminate(:shutdown, state), do: kill_container(state)
  def terminate({:shutdown, _exit_reason}, state), do: kill_container(state)


  def handle_info({:hackney_response, _conn, message}, state) when is_binary(message) do
    Docker.RequestMap.whereis_request(self())
    |> send({:stdout, message})
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp reset_timer(state = %{timer: timer_ref}) do
    :timer.cancel(timer_ref)
    {:ok, new_timer_ref} = set_keep_alive_timer()
    %{state | timer: new_timer_ref}
  end

  defp set_keep_alive_timer do
    :timer.apply_after(@default_timeout, GenServer, :stop, [self(), {:shutdown, :timeout}])
  end

  defp host do
    "127.0.0.1:2375"
  end

  defp create_container(opts \\ %{}) do
    try do
      merged_opts = Map.merge(@default_container_opts, opts)
      {:ok, %{id: container_id}} = Container.run host(), merged_opts
      ContainerRegistry.register_worker(self(), container_id)
      {:ok, container_id}
    rescue
      reason ->
        IO.puts "Error creating container"
        {:error, reason}
    end
  end

   defp save_file_commands(filename, file_contents) do
      ["bash", "-c", ~s(cat << 'EOF' > #{filename}\n#{file_contents}\nEOF)]
   end

   defp kill_container(%{container_id: container_id}) do
     case Container.kill(host(), container_id) do
       {:ok, _ } ->
         IO.puts "Container #{container_id} shutdown"
        %{"message" => message} ->
          IO.puts message
        {:error, reason} ->
          IO.puts "Error killing container"
          IO.inspect reason
     end
   end
end

