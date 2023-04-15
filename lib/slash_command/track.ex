defmodule SlashCommand.Track do
  require Logger

  import PS2.API.QueryBuilder

  alias PS2.API.QueryResult
  alias Nostrum.Struct.{Interaction, Guild}
  alias Nostrum.Cache.GuildCache
  alias PS2.API.Query

  @behaviour SlashCommand

  @none_voicepack_dirs ["README.md", "TEMPLATE"]
  @scope if System.get_env("MIX_ENV") == "prod", do: :global, else: :application_guilds
  @timeout_mins 5

  @impl SlashCommand
  def command_definition() do
    voicepack_choices =
      with {:ok, files} <- File.ls("#{File.cwd!()}/voicepacks") do
        for file <- files, file not in @none_voicepack_dirs do
          %{name: file, value: file}
        end
      else
        e -> raise e
      end

    %{
      name: "track",
      description: "Track a character.",
      options: [
        %{
          # ApplicationCommandType::STRING
          type: 3,
          name: "character_name",
          description: "Specify the character name you would like to track",
          min_length: 3,
          required: true
        },
        %{
          # ApplicationCommandType::STRING
          type: 3,
          name: "voicepack",
          description: "Specify the voicepack you would like to use",
          min_length: 3,
          choices: voicepack_choices,
          required: true
        }
      ]
    }
  end

  @impl SlashCommand
  def command_scope() do
    case @scope do
      :application_guilds -> {:guild, Application.get_env(:blurber, :guilds, [])}
      :global -> :global
    end
  end

  @impl SlashCommand
  def ephemeral?, do: true

  @impl SlashCommand
  def run(%Interaction{} = interaction) do
    content =
      with options <- SlashCommand.get_options(interaction),
           {:ok, character_name} <- Map.fetch(options, "character_name"),
           {:ok, voicepack} <- Map.fetch(options, "voicepack"),
           {:cur_vc, nil} <- {:cur_vc, Nostrum.Voice.get_channel_id(interaction.guild_id)},
           {:ok, %Guild{voice_states: voice_states}} <- GuildCache.get(interaction.guild_id),
           %{channel_id: vc_id} <- Enum.find(voice_states, &(&1.user_id == interaction.user.id)) do
        Query.new(collection: "character")
        |> term("name.first_lower", String.downcase(character_name))
        |> limit(1)
        |> show("character_id")
        |> PS2.API.query_one(Blurber.service_id())
        |> case do
          {:ok, %QueryResult{data: %{"character_id" => character_id}}} ->
            PS2.Socket.subscribe!(Blurber.Socket, Blurber.ESS.subscription(character_id))

            with :ok <- Blurber.ESS.new_session(character_id, voicepack, interaction.guild_id),
                 :ok <- Nostrum.Voice.join_channel(interaction.guild_id, vc_id) do
              """
              Successfully joined voice channel.
              Listening to events from #{character_name} (ID #{character_id}), using voicepack '#{voicepack}'
              """
            else
              e ->
                Logger.error(
                  "Could not create a new session and join the voice channel: #{inspect(e)}"
                )

                "Could not join the voice channel, please try again soon."
            end

          {:ok, %QueryResult{data: nil}} ->
            "Could not get that character's ID, please double check the spelling and try again."

          {:error, error} ->
            Logger.error("Could not fetch character_id in /track: #{inspect(error)}")
            "Could not get that character's ID, please double check the spelling and try again."
        end
      else
        :error ->
          Logger.error("Could not fetch required /track parameters.")
          "Please provide a character name and voicepack."

        nil ->
          "Please join a voice channel."

        {:error, guild_fetch_reason} ->
          Logger.error(
            "Could not get guild from interaction.guild_id: #{inspect(guild_fetch_reason)}"
          )

          "Unable to get server info, please make sure you're connected to a voice channel and try again."

        {:cur_vc, _channel_id} ->
          """
          It looks like someone else in this server is currently tracking a character - you must wait for them to
          logout or for their tracking session to expire (#{@timeout_mins} minutes of no events) before starting a new
          tracking session in this server.
          """
      end

    {:response,
     [
       content: content
     ]}
  end
end
