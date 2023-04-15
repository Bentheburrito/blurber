import Config

if Config.config_env() == :dev do
  DotenvParser.load_file(".env")
end

config :nostrum,
  token: System.get_env("BOT_TOKEN"),
  gateway_intents: [
    :guilds,
    :guild_voice_states,
    :message_content
  ]

config :blurber,
  guilds: [381_258_048_527_794_197]
