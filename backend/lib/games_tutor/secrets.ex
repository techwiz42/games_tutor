defmodule GamesTutor.Secrets do
  @moduledoc """
  Read a secret from an env var, or a Docker-secrets-style file path in
  `"\#{env_var}_FILE"` -- mirrors the same `_read_secret` pattern used across
  this user's other projects (agent_framework, memchat): direct env var first,
  then a file path env var, then fail loudly (no silent fallback).
  """

  def read(env_var, opts \\ []) do
    file_env_var = Keyword.get(opts, :file_env_var, "#{env_var}_FILE")
    default = Keyword.get(opts, :default)

    case System.get_env(env_var) do
      value when is_binary(value) and value != "" ->
        value

      _ ->
        case System.get_env(file_env_var) do
          path when is_binary(path) and path != "" ->
            path |> File.read!() |> String.trim()

          _ ->
            default || raise "Secret not configured: set #{env_var} or #{file_env_var}"
        end
    end
  end
end
