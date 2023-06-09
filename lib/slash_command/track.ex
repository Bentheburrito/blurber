defmodule Blurber.ApplicationCommands.Track do
  @behaviour Nosedrum.ApplicationCommand

  require Logger

  import PS2.API.QueryBuilder

  alias Blurber.ESS.Session
  alias PS2.API.QueryResult
  alias Nostrum.Struct.{Interaction, Guild}
  alias Nostrum.Cache.GuildCache
  alias PS2.API.Query

  @none_voicepack_dirs ["README.md", "TEMPLATE"]
  @max_retries 4

  @impl Nosedrum.ApplicationCommand
  def description do
    "Track a character."
  end

  @impl Nosedrum.ApplicationCommand
  def type do
    :slash
  end

  @impl Nosedrum.ApplicationCommand
  def options do
    voicepack_choices =
      with {:ok, files} <- File.ls("#{File.cwd!()}/voicepacks") do
        for file <- files, file not in @none_voicepack_dirs do
          %{name: file, value: file}
        end
      else
        e -> raise e
      end

    [
      %{
        type: :string,
        name: "character_name",
        description: "Specify the character name you would like to track",
        min_length: 3,
        required: true
      },
      %{
        type: :string,
        name: "voicepack",
        description: "Specify the voicepack you would like to use",
        choices: voicepack_choices,
        required: true
      }
    ]
  end

  @impl Nosedrum.ApplicationCommand
  def command(%Interaction{guild_id: guild_id} = interaction) do
    with options <- Blurber.get_options(interaction),
         {:ok, character_name} <- Map.fetch(options, "character_name"),
         {:ok, voicepack} <- Map.fetch(options, "voicepack"),
         {:ok, %Guild{voice_states: voice_states}} <- GuildCache.get(guild_id),
         %{channel_id: vc_id} <- Enum.find(voice_states, &(&1.user_id == interaction.user.id)) do
      # Run the rest of the command after deferring the full response with Discord.
      # The Census query can take more than 5 seconds to run (and even randomly fail...)
      [
        type:
          {:deferred_channel_message_with_source,
           {&do_command/4, [interaction, character_name, voicepack, vc_id]}}
      ]
    else
      :error ->
        Logger.error("Could not fetch required /track parameters.")
        [content: "Please provide a character name and voicepack."]

      nil ->
        [content: "Please join a voice channel."]

      {:error, guild_fetch_reason} ->
        # when guild_fetch_reason in [:id_not_found, :id_not_found_on_guild_lookup] ->
        Logger.error("Could not get guild from guild_id: #{inspect(guild_fetch_reason)}")

        [
          content:
            "Unable to get server info, please make sure you're connected to a voice channel and try again."
        ]
    end
  end

  defp do_command(interaction, character_name, voicepack, vc_id, remaining_tries \\ @max_retries)

  defp do_command(interaction, character_name, _voicepack, _vc_id, 0) do
    content =
      "Could not get #{character_name}'s ID, please double check the spelling and try again."

    Nostrum.Api.edit_interaction_response(interaction, %{content: content})
  end

  defp do_command(interaction, character_name, voicepack, vc_id, remaining_tries) do
    %Interaction{guild_id: guild_id, channel_id: channel_id} = interaction

    content =
      with {:ok, %QueryResult{data: %{"character_id" => character_id}}} <- query(character_name),
           :ok <- PS2.Socket.subscribe!(Blurber.Socket, Blurber.ESS.subscription(character_id)),
           {:error, :not_found} <- Blurber.ESS.session_pid(character_id),
           :ok <- Blurber.ESS.new_session(character_id, voicepack, guild_id, channel_id),
           :ok <- Nostrum.Voice.join_channel(guild_id, vc_id) do
        """
        Successfully joined voice channel.
        Listening to events from #{character_name} (ID #{character_id}), using voicepack '#{voicepack}'
        """
      else
        {:ok, pid} when is_pid(pid) ->
          """
          It looks like someone else in this server is currently tracking a character - you must wait for them to
          logout or for their tracking session to expire (#{Session.afk_timeout_ms() / (60 * 1000)} minutes of no
          events) before starting a new tracking session in this server.
          """

        {:ok, %QueryResult{}} ->
          "Could not get #{character_name}'s ID, please double check the spelling and try again."

        {:error, error} ->
          Logger.error("Could not fetch character_id in /track: #{inspect(error)}")
          do_command(interaction, character_name, voicepack, vc_id, remaining_tries - 1)[:content]

        e ->
          Logger.error("Could not create a new session and join the voice channel: #{inspect(e)}")

          "Could not join the voice channel, please try again soon."
      end

    [content: content]
  end

  defp query(character_name) do
    Query.new(collection: "character")
    |> term("name.first_lower", String.downcase(character_name))
    |> limit(1)
    |> show("character_id")
    |> PS2.API.query_one(Blurber.service_id())
  end
end
