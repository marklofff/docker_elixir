defmodule Docker.ContainerManager do
  use Supervisor
  
  def start_link do
    Supervisor.start_link(__MODULE__, :ok, name: :container_manager)
  end

  def start_container(image_name) do
    Supervisor.start_child(:container_manager, [%{"Image" => image_name}])
  end

  def start_container do
    Supervisor.start_child(:container_manager, [])
  end

  def init(:ok) do
    children = [
      worker(Docker.ContainerWorker, [], restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end
end
