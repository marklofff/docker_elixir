defmodule Docker.RequestMap do
  def start_link do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def register(request_pid, worker_pid) do
    Agent.update(__MODULE__, fn(current) ->
      Map.put( current, worker_pid, %{ request: request_pid })
    end)
  end

  def unregister(worker_pid) do
    Agent.update(__MODULE__, fn(current) ->
      Map.drop(current, [worker_pid])
    end)
  end

  def whereis_request(worker_pid) do
    Agent.get(__MODULE__, fn(current) ->
      current
      |> Map.get(worker_pid)
      |> Map.get(:request)
    end)
  end

  def find_by_request_pid(request_pid) do
    Agent.get(__MODULE__, fn(current) ->
      current
      |> Enum.find(fn {_key, val} -> val == %{request: request_pid} end)
      |> case do
          {worker_pid, _val} -> worker_pid
          nil -> nil
         end
      end)
  end

  def list_all do
    Agent.get(__MODULE__, fn(current) ->
      current
    end)
  end
end
