defmodule Blurber.ESS do
  @moduledoc """
  Handles events received from ESS, persisting them to the DB, and broadcasting them.
  """

  use GenServer

  @behaviour PS2.SocketClient

  require Logger

  alias Blurber.ESS
  alias Blurber.ESS.Session

  @restart_after_ms 60 * 1000

  @enforce_keys [:restart_timer]
  defstruct patterns: %{}, weapon_ids: :unfetched, restart_timer: nil

  ### API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def new_session(character_id, voicepack, guild_id, channel_id) do
    child_spec = {Session, {character_id, voicepack, guild_id, channel_id}}

    case DynamicSupervisor.start_child(Blurber.ESS.DynamicSupervisor, child_spec) do
      {:ok, pid} ->
        Blurber.ESS.GuildSessionCache.put(guild_id, pid)
        GenServer.call(__MODULE__, {:new_session, character_id, pid})

      e ->
        Logger.error("Could not start session process: #{inspect(e)}")
        :error
    end
  end

  def close_session(character_id, guild_id) do
    GenServer.call(__MODULE__, {:close_session, character_id, guild_id})
  end

  @spec session_pid(character_id :: String.t()) :: {:ok, pid()} | {:error, :not_found}
  def session_pid(character_id) do
    GenServer.call(__MODULE__, {:session_pid, character_id})
  end

  def weapon_id?(weapon_id) do
    GenServer.call(__MODULE__, {:weapon_id?, weapon_id})
  end

  def subscription(character_id_list) when is_list(character_id_list) do
    [
      events: [
        PS2.player_login(),
        PS2.player_logout(),
        PS2.death(),
        PS2.vehicle_destroy(),
        # Revive
        PS2.gain_experience(7),
        # Squad Revive
        PS2.gain_experience(53),
        PS2.item_added()
      ],
      worlds: [],
      characters: character_id_list
    ]
  end

  def subscription(character_id) do
    subscription([character_id])
  end

  ### Impl

  @impl GenServer
  def init(_init_state) do
    restart_timer = Process.send_after(self(), :restart_socket, @restart_after_ms)
    {:ok, %ESS{patterns: %{}, restart_timer: restart_timer}}
  end

  @server_health_update PS2.server_health_update()
  @impl PS2.SocketClient
  def handle_event({@server_health_update, _payload}) do
    GenServer.cast(__MODULE__, :ess_heartbeat)
  end

  @impl PS2.SocketClient
  def handle_event({event_name, payload}) do
    Logger.debug("Got #{event_name}")

    character_ids = Map.take(payload, ["character_id", "attacker_character_id", "other_id"])

    GenServer.cast(__MODULE__, {:handle_event, character_ids, event_name, payload})
  end

  @impl PS2.SocketClient
  def handle_event(_event), do: nil

  @impl GenServer
  def handle_call({:new_session, character_id, pid}, _from, %ESS{} = state) do
    patterns = Map.put(state.patterns, character_id, pid)

    {:reply, :ok, %ESS{state | patterns: patterns}}
  end

  @impl GenServer
  def handle_call({:close_session, character_id, guild_id}, _from, %ESS{} = state) do
    case Map.pop(state.patterns, character_id, :no_session) do
      {:no_session, _} ->
        {:reply, {:error, :not_found}, state}

      {pid, new_patterns} ->
        Blurber.ESS.GuildSessionCache.delete(guild_id)
        result = DynamicSupervisor.terminate_child(Blurber.ESS.DynamicSupervisor, pid)
        {:reply, result, %ESS{state | patterns: new_patterns}}
    end
  end

  def handle_call({:session_pid, character_id}, _from, %ESS{} = state) do
    reply =
      case Map.fetch(state.patterns, character_id) do
        {:ok, pid} -> {:ok, pid}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  @impl GenServer
  def handle_call({:weapon_id?, weapon_id}, _from, %ESS{} = state) do
    {:reply, weapon_id in get_weapon_ids(state), state}
  end

  @impl GenServer
  def handle_cast({:handle_event, character_ids, event_name, payload}, %ESS{} = state) do
    id_mappings =
      character_ids
      |> Stream.map(fn {_field_name, id} ->
        Map.fetch(state.patterns, id)
      end)
      |> Stream.dedup()

    for {:ok, session_pid} <- id_mappings do
      Session.handle_event(session_pid, event_name, payload)
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast(:ess_heartbeat, %ESS{} = state) do
    Process.cancel_timer(state.restart_timer)
    restart_timer = Process.send_after(self(), :restart_socket, @restart_after_ms)
    {:noreply, %ESS{state | restart_timer: restart_timer}}
  end

  @impl GenServer
  def handle_info(:restart_socket, %ESS{} = state) do
    Logger.debug("restarting socket")

    case Supervisor.terminate_child(Blurber.Supervisor, PS2.Socket) do
      :ok ->
        Supervisor.restart_child(Blurber.Supervisor, PS2.Socket)
        |> IO.inspect(label: "restart_child call")

      {:error, :not_found} ->
        raise "Tried to restart the ESS socket, but Blurber.Supervisor could not find it"
    end

    Process.cancel_timer(state.restart_timer)
    restart_timer = Process.send_after(self(), :restart_socket, @restart_after_ms)
    {:noreply, %ESS{state | restart_timer: restart_timer}}
  end

  defp get_weapon_ids(%ESS{} = state) do
    case state.weapon_ids do
      :unfetched -> Blurber.query_weapon_ids()
      weapon_ids when is_list(weapon_ids) -> weapon_ids
      _ -> []
    end
  end
end
