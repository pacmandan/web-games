defmodule GamePlatform.Player do
  @callback generate_id() :: String.t()
  @callback get_id(player :: term()) :: String.t()
  @callback new(opts :: term()) :: term()

  defmacro __using__(_opts) do
    quote do
      @behaviour GamePlatform.Player

      defdelegate generate_id(), to: GamePlatform.Player
      defoverridable(GamePlatform.Player)
    end
  end

  def generate_id() do
    for _ <- 1..20, into: "", do: <<Enum.random(?a..?z)>>
  end
end

defmodule GamePlatform.Player.Simple do
  defmacro __using__(_opts) do
    quote do
      use GamePlatform.Player
      def new(_), do: __MODULE__.generate_id()
      def get_id(id), do: id
    end
  end
end
