defmodule Docker.ContainerRegistry do
  use GenServer
  alias Docker.Container

  def start_link(name) do
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  def register_worker(worker_pid, container_id) do
    GenServer.cast(
                   __MODULE__,
                   {:register_worker, worker_pid, container_id}
                 )
  end

  def list_workers do
    GenServer.call(__MODULE__, {:list_workers})
  end

  def init(:ok) do
    case Docker.Container.list(host()) do
      {:error, _reason} ->
        {:ok, %{}}
      ids ->
        Enum.each(ids, &Docker.Container.kill(host(), &1))
        {:ok, %{}}
    end
  end

  def handle_cast({:register_worker, worker_pid, container_id}, state) do
    ref = Process.monitor(worker_pid)
    new_state = state |> Map.put(worker_pid, { container_id, ref })
    {:noreply, new_state}
  end

  def handle_call({:list_workers}, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_info({:DOWN, ref, _type, pid, _reason}, state) do
    case Map.get(state, pid) do
      {container_id,  ^ref} ->
        try do
          Container.kill(host, container_id)
        rescue
          reason ->
            IO.puts "Error Killing Container"
            IO.inspect reason
        end
        Process.demonitor(ref)
        new_state = state |> Map.delete(pid)
        {:noreply, new_state}
      _ -> 
        {:noreply, state}
    end
  end

  defp host do
    "127.0.0.1:2375"
  end
end
