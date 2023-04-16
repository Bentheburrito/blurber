defmodule Blurber.ESS.Session do
  @doc """
  A GenServer that represents a tracking session. Spawned and supervised by Blurber.ESS
  """

  use GenServer

  alias Blurber.ESS
  alias Blurber.ESS.Session

  require Logger

  @killing_spree_interval_seconds 12

  @enforce_keys [:voicepack, :guild_id, :character_id]
  defstruct killing_spree_count: 0,
            last_kill_timestamp: 0,
            voicepack: nil,
            guild_id: nil,
            character_id: nil

  ### API

  def start_link({character_id, voicepack, guild_id}) do
    GenServer.start_link(__MODULE__, %Session{
      voicepack: voicepack,
      guild_id: guild_id,
      character_id: character_id
    })
  end

  def handle_event(session_pid, event_name, payload) do
    GenServer.cast(session_pid, {:handle_event, event_name, payload})
  end

  ### Impl

  @impl GenServer
  def init(%Session{} = session) do
    {:ok, session}
  end

  @impl GenServer
  def handle_cast({:handle_event, event_name, payload}, %Session{} = state) do
    case fetch_category(event_name, payload, state.character_id, state) do
      {:ok, category, state} ->
        IO.inspect(category, label: "about to play sound with category")
        play_random_sound(category, state)
        {:noreply, state}

      :none ->
        {:noreply, state}
    end
  end

  defp fetch_category("GainExperience", %{"experience_id" => xp_id} = ge, char_id, state)
       when xp_id in ["7", "53"] do
    cond do
      ge["character_id"] == char_id -> {:ok, "revive_teammate", state}
      ge["other_id"] == char_id -> {:ok, "get_revived", state}
      :else -> :none
    end
  end

  defp fetch_category("Death", %{"character_id" => char_id} = death, char_id, state) do
    if char_id == death["attacker_character_id"] do
      {:ok, "suicide", state}
    else
      {:ok, "death", state}
    end
  end

  defp fetch_category("Death", %{"attacker_character_id" => char_id} = death, char_id, state) do
    timestamp = String.to_integer(death["timestamp"])

    %Session{killing_spree_count: spree_count, last_kill_timestamp: spree_timestamp} = state

    continued_spree? = spree_timestamp > timestamp - @killing_spree_interval_seconds

    {category, new_spree_count} =
      case {spree_count + 1, death["is_headshot"], continued_spree?} do
        {_, "1", false} -> {"kill_headshot", 1}
        {_, "0", false} -> {"kill", 1}
        {2, _, true} -> {"kill_double", spree_count + 1}
        {3, _, true} -> {"kill_triple", spree_count + 1}
        {4, _, true} -> {"kill_quad", spree_count + 1}
        {5, _, true} -> {"kill_penta", spree_count + 1}
      end

    new_session = %Session{
      state
      | killing_spree_count: new_spree_count,
        last_kill_timestamp: timestamp
    }

    {:ok, category, new_session}
  end

  defp fetch_category("VehicleDestroy", vd, char_id, state) do
    cond do
      vd["character_id"] == char_id and vd["character_id"] == vd["attacker_character_id"] ->
        {:ok, "destroy_own_vehicle", state}

      vd["attacker_character_id"] == char_id ->
        {:ok, "destroy_vehicle", state}

      :else ->
        :none
    end
  end

  defp fetch_category("PlayerLogin", %{"character_id" => char_id}, char_id, state) do
    {:ok, "login", state}
  end

  defp fetch_category("PlayerLogout", %{"character_id" => char_id}, char_id, state) do
    {:ok, "logout", state}
  end

  defp fetch_category("ItemAdded", %{"character_id" => char_id} = ia, char_id, state) do
    cond do
      ia["context"] == "CaptureTheFlag.TakeFlag" ->
        {:ok, "ctf_flag_take", state}

      ia.context == "GuildBankWithdrawal" && ia.item_id == 6_008_913 ->
        {:ok, "bastion_pull", state}

      ESS.weapon_id?(ia["item_id"]) ->
        {:ok, "unlock_weapon", state}

      :else ->
        {:ok, "unlock_any", state}
    end
  end

  defp fetch_category(_event_name, _payload, _char_id, _state) do
    :none
  end

  defp play_random_sound(category, %Session{} = session) do
    cwd = File.cwd!()

    with {:ok, content} <- File.read("#{cwd}/voicepacks/#{session.voicepack}/#{category}.txt"),
         [_ | _] = filenames <- String.split(content, "\n", trim: true),
         file_path <-
           "#{cwd}/voicepacks/#{session.voicepack}/tracks/#{Enum.random(filenames)}",
         :ok <- Nostrum.Voice.play(session.guild_id, file_path) do
      Task.await(Task.async(fn -> sleep_until_not_playing(session.guild_id) end), :infinity)
    else
      uhoh ->
        Logger.error("Unable to play sound: #{inspect(uhoh)}")
        :error
    end
  end

  # this is a very hacky way to "queue" audio - would be nice if there was a way to hook into updates from Nostrum.Voice
  defp sleep_until_not_playing(guild_id, check_next_ms \\ 1000) do
    if Nostrum.Voice.playing?(guild_id) do
      Process.sleep(check_next_ms)
      sleep_until_not_playing(guild_id, check_next_ms)
    else
      false
    end
  end
end