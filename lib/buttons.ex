defmodule Buttons do
  alias Nostrum.Struct.Interaction

  require Logger

  def handle_interaction(%Interaction{} = _interaction) do
    nil
  end
end
