defmodule Blurber.ESS do
  @moduledoc """
  Handles events received from ESS, persisting them to the DB, and broadcasting them.
  """

  use GenServer

  @behaviour PS2.SocketClient

  require Logger

  alias Blurber.ESS
  alias Blurber.ESS.Session

  @killing_spree_interval_seconds 12

  defstruct patterns: %{}, weapon_ids: :unfetched

  ### API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def new_session(character_id, voicepack, guild_id) do
    GenServer.call(__MODULE__, {:new_session, character_id, voicepack, guild_id})
  end

  def get_weapon_ids() do
    GenServer.call(__MODULE__, :get_weapon_ids)
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
  def handle_call({:new_session, character_id, voicepack, guild_id}, _from, %ESS{} = state) do
    patterns =
      Map.put(state.patterns, character_id, %Session{voicepack: voicepack, guild_id: guild_id})

    {:reply, :ok, %ESS{state | patterns: patterns}}
  end

  @impl GenServer
  def handle_cast({:handle_event, character_ids, event_name, payload}, %ESS{} = state) do
    id_mappings =
      Stream.map(character_ids, fn {_field_name, id} ->
        {id, Map.fetch(state.patterns, id)}
      end)

    state =
      for {character_id, {:ok, %Session{} = session}} <- id_mappings, reduce: state do
        state ->
          case fetch_category(event_name, payload, character_id, state)
               |> IO.inspect(label: "got category") do
            {:ok, category, weapon_ids} ->
              play_random_sound(category, session)
              %ESS{state | weapon_ids: weapon_ids}

            {:ok, category} ->
              play_random_sound(category, session)
              state

            :none ->
              state
          end
      end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:set_killing_spree, character_id, count, timestamp}, %ESS{} = state) do
    if is_map_key(state.patterns, character_id) do
      updated_patterns =
        Map.update!(state.patterns, character_id, fn %Session{} = session ->
          %Session{
            session
            | killing_spree_count: count,
              last_kill_timestamp: timestamp
          }
        end)

      {:noreply, %ESS{state | patterns: updated_patterns}}
    else
      {:noreply, state}
    end
  end

  defp fetch_category("GainExperience", ge, character_id, _state) do
    if ge["experience_id"] in ["7", "53"] do
      cond do
        ge["character_id"] == character_id -> {:ok, "revive_teammate"}
        ge["other_id"] == character_id -> {:ok, "get_revived"}
        :else -> :none
      end
    else
      :none
    end
  end

  defp fetch_category("Death", death, character_id, state) do
    cond do
      death["character_id"] == character_id ->
        if death["character_id"] == death["attacker_character_id"] do
          {:ok, "suicide"}
        else
          {:ok, "death"}
        end

      death["attacker_character_id"] == character_id ->
        timestamp = String.to_integer(death["timestamp"])

        %Session{killing_spree_count: spree_count, last_kill_timestamp: spree_timestamp} =
          Map.get(state.patterns, character_id)

        kill_category =
          if spree_timestamp > timestamp - @killing_spree_interval_seconds do
            GenServer.cast(
              __MODULE__,
              {:set_killing_spree, character_id, spree_count + 1, timestamp}
            )

            case {spree_count + 1, death["is_headshot"]} do
              {1, true} -> "kill_headshot"
              {1, _} -> "kill"
              {2, _} -> "kill_double"
              {3, _} -> "kill_triple"
              {4, _} -> "kill_quad"
              _ -> "kill_penta"
            end
          else
            GenServer.cast(
              __MODULE__,
              {:set_killing_spree, character_id, 1, timestamp}
            )

            if death["is_headshot"] do
              "kill_headshot"
            else
              "kill"
            end
          end

        {:ok, kill_category}

      :else ->
        :none
    end
  end

  defp fetch_category("VehicleDestroy", vd, character_id, _state) do
    cond do
      vd["character_id"] == character_id and vd["character_id"] == vd["attacker_character_id"] ->
        {:ok, "destroy_own_vehicle"}

      vd["attacker_character_id"] == character_id ->
        {:ok, "destroy_vehicle"}

      :else ->
        :none
    end
  end

  defp fetch_category("PlayerLogin", login, character_id, _state) do
    if login["character_id"] == character_id do
      {:ok, "login"}
    else
      :none
    end
  end

  defp fetch_category("PlayerLogout", logout, character_id, _state) do
    if logout["character_id"] == character_id do
      {:ok, "logout"}
    else
      :none
    end
  end

  defp fetch_category("ItemAdded", ia, character_id, state) do
    if ia["character_id"] == character_id do
      weapon_ids =
        case state.weapon_ids do
          :unfetched -> Blurber.query_weapon_ids()
          weapon_ids when is_list(weapon_ids) -> weapon_ids
          _ -> []
        end

      category =
        cond do
          ia["context"] == "CaptureTheFlag.TakeFlag" ->
            "ctf_flag_take"

          ia.context == "GuildBankWithdrawal" && ia.item_id == 6_008_913 ->
            "bastion_pull"

          ia["item_id"] in weapon_ids ->
            "unlock_weapon"

          :else ->
            "unlock_any"
        end

      {:ok, category, weapon_ids}
    else
      :none
    end
  end

  defp fetch_category(_event_name, _payload, _character_id, _state) do
    :none
  end

  defp play_random_sound(category, %Session{} = session) do
    cwd = File.cwd!()

    with {:ok, content} <- File.read("#{cwd}/voicepacks/#{session.voicepack}/#{category}.txt"),
         [_ | _] = filenames <- String.split(content, "\n"),
         file_path <-
           "#{cwd}/voicepacks/#{session.voicepack}/tracks/#{Enum.random(filenames)}",
         :ok <- Nostrum.Voice.play(session.guild_id, file_path) do
      :ok
    else
      uhoh ->
        Logger.error("Unable to play sound: #{inspect(uhoh)}")
        :error
    end
  end
end
