defmodule SlashCommand.Ping do
  alias Nostrum.Struct.Interaction

  @behaviour SlashCommand

  @impl SlashCommand
  def command_definition() do
    %{
      name: "ping",
      description: "Pings the bot"
    }
  end

  @impl SlashCommand
  def command_scope() do
    {:guild, Application.get_env(:blurber, :guilds, [])}
  end

  @impl SlashCommand
  def ephemeral?, do: true

  @impl SlashCommand
  def run(%Interaction{} = _interaction) do
    {:response, [content: "pong!"]}
  end
end
