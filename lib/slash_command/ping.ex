defmodule Blurber.ApplicationCommands.Ping do
  @behaviour Nosedrum.ApplicationCommand

  @impl Nosedrum.ApplicationCommand
  def description do
    "Pings the bot"
  end

  @impl Nosedrum.ApplicationCommand
  def type do
    :slash
  end

  @impl Nosedrum.ApplicationCommand
  def command(_interaction) do
    [
      content: "pong!",
      ephemeral?: true
    ]
  end
end
