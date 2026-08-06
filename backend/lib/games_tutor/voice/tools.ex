defmodule GamesTutor.Voice.Tools do
  @moduledoc """
  OpenAI Realtime function-calling tool schema and mode-specific system
  instructions. `make_move`-by-voice is explicitly out of scope (the board
  UI is the sole authoritative move input) -- these tools are all
  read/narrate, never write game state.

  None of the tool parameter schemas carry a `game_id`: the browser already
  knows which game the voice session is for (it started the session), so
  it injects that itself when dispatching -- the model never gets to pick
  an arbitrary game_id (ownership is still enforced server-side regardless,
  but there's no reason to hand the model a knob it doesn't need).
  """

  @schema [
    %{
      type: "function",
      name: "get_board_state",
      description: "Get the current board position, whose turn it is, and whether the game has ended.",
      parameters: %{type: "object", properties: %{}, required: []}
    },
    %{
      type: "function",
      name: "get_last_move_analysis",
      description:
        "Get the engine's quality assessment (best/good/inaccuracy/mistake/blunder) of the most " <>
          "recently played move. Cheap -- pre-computed when the move was made, not a live engine call.",
      parameters: %{type: "object", properties: %{}, required: []}
    },
    %{
      type: "function",
      name: "explain_move",
      description:
        "Get the engine's quality assessment of a specific past move by its move number (ply), so you " <>
          "can explain why a particular move was good or bad. Omit ply to explain the most recent move.",
      parameters: %{
        type: "object",
        properties: %{ply: %{type: "integer", description: "The move number to explain, if a specific one was asked about."}},
        required: []
      }
    },
    %{
      type: "function",
      name: "request_hint",
      description:
        "Get a suggested move for the human's current turn. Only available in tutoring games -- " <>
          "always refused during a \"rate my play\" calibration game, even if asked, since hinting " <>
          "would contaminate the skill measurement.",
      parameters: %{type: "object", properties: %{}, required: []}
    },
    %{
      type: "function",
      name: "adjust_explanation_depth",
      description: "Change how detailed the player wants explanations to be going forward.",
      parameters: %{
        type: "object",
        properties: %{depth: %{type: "string", enum: ["brief", "detailed"]}},
        required: ["depth"]
      }
    },
    %{
      type: "function",
      name: "get_skill_profile",
      description: "Get the player's current estimated chess rating and how many calibration games it's based on.",
      parameters: %{type: "object", properties: %{}, required: []}
    }
  ]

  def schema, do: @schema

  @doc "mode is \"calibration_proctor\" or \"tutoring\" (a string, matching VoiceSession.modes/0 -- avoids String.to_existing_atom's module-load-order fragility for no benefit)."
  def instructions("calibration_proctor") do
    """
    You are proctoring a "rate my play" calibration game for games_tutor, a chess tutoring app.
    Your job right now is to measure the player's true skill level, not to teach.

    Say ONE brief line at the very start: that you'll stay quiet and they should just play their
    best, and you'll talk more after the game. During play, only: confirm moves briefly if asked,
    and answer pure rules-legality questions (e.g. "can I castle here?"). Do NOT comment on move
    quality, do NOT offer encouragement or criticism, and do NOT volunteer opinions about the
    position -- any of that would change how the player plays and contaminate the measurement.

    If asked for a hint or any help choosing a move, politely decline and remind them this is a
    silent calibration game -- call request_hint if you want the mechanism to enforce this for you,
    it will refuse. When the game ends, give one honest, hedged spoken summary using
    get_skill_profile -- make clear this is an early/approximate estimate that improves with more
    games, not a precise verdict.
    """
  end

  def instructions("tutoring") do
    """
    You are a friendly, encouraging chess tutor for games_tutor. The player is looking at the
    board themselves and makes moves by dragging pieces -- you never make moves, you narrate and
    teach. Use get_board_state and get_last_move_analysis to stay aware of what's happening;
    use explain_move when asked about a specific past move; use request_hint if they're stuck and
    want a suggestion; use adjust_explanation_depth if they ask for more or less detail; use
    get_skill_profile if they ask how they're doing overall.

    Keep it conversational and concise by default -- a sentence or two, not a lecture, unless the
    player has asked for more depth. Be honest about uncertainty in the skill estimate rather than
    overstating precision.
    """
  end
end
