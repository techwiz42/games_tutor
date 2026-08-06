defmodule GamesTutor.Voice.Tools do
  @moduledoc """
  OpenAI Realtime function-calling tool schema and mode-specific system
  instructions. `make_move`-by-voice is explicitly out of scope (the board
  UI is the sole authoritative move input) -- these tools are all
  read/narrate, never write game state.

  Both `schema/1` and `instructions/2` take `game_type` ("chess" | "go")
  so wording matches what the player is actually looking at (chess pieces
  dragged on a board vs. Go stones clicked into place; a chess rating vs.
  a kyu/dan Go rating) -- otherwise a Go session would get instructions
  that talk about castling and dragging pieces.

  None of the tool parameter schemas carry a `game_id`: the browser already
  knows which game the voice session is for (it started the session), so
  it injects that itself when dispatching -- the model never gets to pick
  an arbitrary game_id (ownership is still enforced server-side regardless,
  but there's no reason to hand the model a knob it doesn't need).
  """

  def schema(game_type) do
    [
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
          properties: %{
            ply: %{type: "integer", description: "The move number to explain, if a specific one was asked about."}
          },
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
        description: "Get the player's current estimated #{game_type} rating and how many calibration games it's based on.",
        parameters: %{type: "object", properties: %{}, required: []}
      }
    ]
  end

  @doc "mode is \"calibration_proctor\" or \"tutoring\" (a string, matching VoiceSession.modes/0)."
  def instructions("calibration_proctor", game_type) do
    """
    You are proctoring a "rate my play" calibration game for games_tutor, a #{game_type} tutoring app.
    Your job right now is to measure the player's true skill level, not to teach.

    Say ONE brief line at the very start: that you'll stay quiet and they should just play their
    best, and you'll talk more after the game. During play, only: confirm moves briefly if asked,
    and answer pure rules-legality questions (e.g. "#{legality_example(game_type)}"). Do NOT comment
    on move quality, do NOT offer encouragement or criticism, and do NOT volunteer opinions about
    the position -- any of that would change how the player plays and contaminate the measurement.

    If asked for a hint or any help choosing a move, politely decline and remind them this is a
    silent calibration game -- call request_hint if you want the mechanism to enforce this for you,
    it will refuse. When the game ends, give one honest, hedged spoken summary using
    get_skill_profile -- make clear this is an early/approximate estimate that improves with more
    games, not a precise verdict.
    """
  end

  def instructions("tutoring", game_type) do
    """
    You are a #{game_type} tutor for games_tutor, giving a single spoken explanation in response to
    the player explicitly asking about one of their moves. This is not an open-ended conversation:
    give one complete, self-contained answer and stop -- the session ends automatically once you
    finish speaking, so don't end on a question expecting a spoken reply, and don't volunteer
    commentary on other moves or anything else the player didn't ask about.

    Ground everything you say in real engine output, never invented chess analysis. Call
    explain_move (or get_last_move_analysis for the most recent move) and base your explanation
    strictly on what it returns: eval_before, eval_after, loss, engine_best_move, and
    classification. If you name a better move, it must be that exact engine_best_move -- never a
    move or line you reasoned out yourself. If the tool call fails or a field you'd need is nil,
    say so plainly rather than guessing or inventing a plausible-sounding answer. Use
    get_board_state for current position context and get_skill_profile if the player's overall
    rating is relevant; use request_hint or adjust_explanation_depth only if explicitly asked.

    Keep it conversational and concise -- a sentence or two, not a lecture -- while staying
    concrete: cite the actual centipawn loss and the actual engine_best_move from the tool data,
    not vague praise or criticism.
    """
  end

  defp legality_example("go"), do: "is it legal for me to play here?"
  defp legality_example(_chess), do: "can I castle here?"
end
