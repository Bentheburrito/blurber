defmodule Blurber.Consumer do
  use Nostrum.Consumer

  alias Blurber.ApplicationCommands.{Ping, Track}
  alias Blurber.ACDispatcher
  alias Nosedrum.Interactor.Dispatcher
  alias Nostrum.Api

  require Logger

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    Nosedrum.Interactor.Dispatcher.handle_interaction(interaction, ACDispatcher)
  end

  def handle_event({:READY, data, _ws_state}) do
    IO.puts("Logged in under user #{data.user.username}##{data.user.discriminator}")
    Api.update_status(:online, "Planetside 2", 0)

    command_scope =
      if System.get_env("MIX_ENV") == "prod" do
        :global
      else
        "TEST_GUILD"
        |> System.fetch_env!()
        |> String.to_integer()
      end

    # Register commands
    # TODO (nosedrum, issue #21): bulk add commands?
    with {:ok, _} <- Dispatcher.add_command("ping", Ping, command_scope, ACDispatcher),
         {:ok, _} <- Dispatcher.add_command("track", Track, command_scope, ACDispatcher) do
      Logger.info("Successfully added application commands.")
    else
      error ->
        Logger.error("An error occurred registering application commands: #{inspect(error)}")
    end
  end

  # Catch all
  def handle_event(_event) do
    :noop
  end
end
