defmodule Blurber.Consumer do
  use Nostrum.Consumer

  alias Nostrum.Api

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    Blurber.InteractionHandler.handle_interaction(interaction)
  end

  def handle_event({:READY, data, _ws_state}) do
    IO.puts("Logged in under user #{data.user.username}##{data.user.discriminator}")
    Api.update_status(:online, "Planetside 2", 0)

    SlashCommand.init_commands()
  end

  def handle_event({event, reg_ack, _ws_state})
      when event in [:APPLICATION_COMMAND_CREATE, :APPLICATION_COMMAND_UPDATE] do
    SlashCommand.put_register(reg_ack.name, reg_ack)
  end

  # Catch all
  def handle_event(_event) do
    :noop
  end
end
