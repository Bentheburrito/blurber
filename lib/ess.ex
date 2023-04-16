defmodule Blurber.ESS do
  @moduledoc """
  Handles events received from ESS, persisting them to the DB, and broadcasting them.
  """

  use GenServer

  @behaviour PS2.SocketClient

  require Logger

  alias Blurber.ESS
  alias Blurber.ESS.Session

  defstruct patterns: %{}, weapon_ids: :unfetched

  ### API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def new_session(character_id, voicepack, guild_id) do
    child_spec = {Session, {character_id, voicepack, guild_id}}

    case DynamicSupervisor.start_child(Blurber.ESS.DynamicSupervisor, child_spec) do
      {:ok, pid} ->
        GenServer.call(__MODULE__, {:new_session, character_id, pid})

      e ->
        Logger.error("Could not start session process: #{inspect(e)}")
        :error
    end
  end

  def weapon_id?(weapon_id) do
    GenServer.call(__MODULE__, {:weapon_id?, weapon_id})
  end

  def subscription(character_id) do
    [
      events: [
        PS2.player_login(),
        PS2.player_logout(),
        PS2.death(),
        PS2.vehicle_destroy(),
        # Revive
        PS2.gain_experience(7),
        # Squad Revive
        PS2.gain_experience(53)
      ],
      worlds: [],
      characters: [character_id]
    ]
  end

  ### Impl

  @impl GenServer
  def init(_init_state) do
    {:ok, %ESS{patterns: %{}}}
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
  def handle_call({:weapon_id?, weapon_id}, _from, %ESS{} = state) do
    {:reply, weapon_id in get_weapon_ids(state), state}
  end

  @impl GenServer
  def handle_cast({:handle_event, character_ids, event_name, payload}, %ESS{} = state) do
    id_mappings =
      Stream.map(character_ids, fn {_field_name, id} ->
        Map.fetch(state.patterns, id)
      end)
      |> Stream.dedup()

    for {:ok, session_pid} <- id_mappings do
      Session.handle_event(session_pid, event_name, payload)
    end

    {:noreply, state}
  end

  defp get_weapon_ids(%ESS{} = state) do
    case state.weapon_ids do
      :unfetched -> Blurber.query_weapon_ids()
      weapon_ids when is_list(weapon_ids) -> weapon_ids
      _ -> []
    end
  end
end
