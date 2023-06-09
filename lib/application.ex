defmodule Blurber.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    clients = [Blurber.ESS]

    ess_opts = [
      subscriptions: [events: [], worlds: [], characters: []],
      clients: clients,
      service_id: Blurber.service_id(),
      name: Blurber.Socket
    ]

    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Blurber.ESS.DynamicSupervisor},
      Blurber.ESS.GuildSessionCache,
      {Blurber.ESS, []},
      {PS2.Socket, ess_opts},
      {Nosedrum.Storage.Dispatcher, name: Blurber.ACDispatcher},
      {Blurber.Consumer, name: Blurber.Consumer}
    ]

    opts = [strategy: :one_for_one, name: Blurber.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
