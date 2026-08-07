defmodule GamesTutor.Go.Engine.Supervisor do
  @moduledoc """
  Isolates `GamesTutor.Go.Engine`'s restart budget from the rest of the app
  supervision tree -- a wedged/crash-looping KataGo process should keep
  getting retried on its own schedule, not exhaust the top-level
  `GamesTutor.Supervisor`'s restart intensity and take the whole app down
  with it.
  """
  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Supervisor.init([GamesTutor.Go.Engine], strategy: :one_for_one, max_restarts: 10, max_seconds: 30)
  end
end
