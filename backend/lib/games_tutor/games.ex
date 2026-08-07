defmodule GamesTutor.Games do
  @moduledoc """
  Games against the engine (chess vs. Stockfish, Go vs. KataGo). Human is
  always White in chess, always Black in Go (see
  `GamesTutor.Chess.GameServer`/`GamesTutor.Go.GameServer`'s moduledocs)
  -- `result` stores the literal board-color winner, so anything
  displaying it must check `game_type` to know which color the human is.

  "Rate my play" (`is_calibration: true`) opponent strength resolution
  follows the plan's documented order for both game types: (1) an
  explicit override, (2) the user's existing `SkillProfile` for this
  game_type if one exists, (3) a platform default (seeded from an
  optional `self_reported_elo` on first-ever calibration, else a wide
  blind prior).
  """
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Games.{Game, Move}
  alias GamesTutor.Chess.PostGameAnalysis
  alias GamesTutor.Skill

  # Below Stockfish's UCI_Elo floor (1320, confirmed in Phase 0) on purpose:
  # a calibration game needs to run long enough to sample many moves, and a
  # full-strength opponent would end games (via losses) too quickly for
  # that. Not scientifically tuned -- a documented v1 default, not a
  # constant silently duplicated elsewhere.
  @default_calibration_elo 1200

  # KataGo's maxVisits knob has no natural default the way Stockfish's Elo
  # does -- picked for the same reason (long enough game to be informative,
  # not scientifically tuned).
  @default_calibration_visits 20

  @starting_fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  # Matches GamesTutor.Go.GameServer's @default_size.
  @go_board_size 9

  @doc "Current position, derived from stored moves -- no live engine process needed just to view a game."
  def current_fen(%Game{moves: moves}) when is_list(moves) and moves != [] do
    List.last(moves).fen_after
  end

  def current_fen(%Game{game_type: "go"}) do
    Jason.encode!(%{size: @go_board_size, grid: GamesTutor.Go.Board.to_grid(GamesTutor.Go.Board.new(@go_board_size))})
  end

  def current_fen(%Game{}), do: @starting_fen

  @doc "Which board color the human plays in this game (a real per-game choice, see create_game/2)."
  def human_color(%Game{human_color: color}), do: color

  def list_games(user) do
    Game
    |> where([g], g.user_id == ^user.id)
    |> order_by([g], desc: g.inserted_at)
    |> Repo.all()
  end

  def get_game(user, id) do
    case Repo.get_by(Game, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      game -> {:ok, Repo.preload(game, moves: from(m in Move, order_by: m.ply))}
    end
  end

  def create_game(user, attrs) do
    game_type = Map.get(attrs, "game_type", "chess")
    opponent_config = resolve_opponent_config(user, game_type, attrs)
    human_color = resolve_human_color(game_type, attrs)

    game_attrs = %{
      user_id: user.id,
      game_type: game_type,
      is_calibration: !!Map.get(attrs, "is_calibration", false),
      opponent_engine_config: opponent_config,
      human_color: human_color,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    with {:ok, game} <- %Game{} |> Game.create_changeset(game_attrs) |> Repo.insert() do
      {:ok, _pid} = game_server(game_type).ensure_started(game.id, opponent_config, [], human_color)

      # When the human plays second (Black in chess, White in Go), the
      # engine's opening move happens synchronously here, right after the
      # process starts, so it's never operationally "missing" from a freshly
      # created game -- it's persisted as ply 1 same as any other move.
      opening_moves =
        case game_server(game_type).maybe_play_opening_move(game.id) do
          {:ok, %{engine_move: attrs}} -> [insert_move!(game, attrs)]
          {:ok, :not_applicable} -> []
        end

      {:ok, %{game | moves: opening_moves}}
    end
  end

  @doc """
  Applies the human's move. Returns `{:ok, %{game:, human_move:, engine_move:}}`,
  `{:error, :illegal_move}`, `{:error, :game_over}`, or `{:error, :not_found}`.
  """
  def submit_move(user, game_id, move_str) do
    with {:ok, game} <- get_game(user, game_id),
         :ok <- ensure_in_progress(game) do
      {:ok, _pid} = ensure_engine_started(game)

      case game_server(game.game_type).submit_human_move(game.id, move_str) do
        {:error, {:illegal_move, _reason}} -> {:error, :illegal_move}
        {:error, {:engine_unavailable, _reason}} -> {:error, :engine_unavailable}
        {:ok, result} -> persist_result(game, result)
      end
    end
  end

  def resign(user, game_id) do
    with {:ok, game} <- get_game(user, game_id),
         :ok <- ensure_in_progress(game) do
      {:ok, _pid} = ensure_engine_started(game)
      {:ok, status} = game_server(game.game_type).resign(game.id)
      {game, skill_profile} = finish_game(game, status)
      {:ok, %{game: game, skill_profile: skill_profile}}
    end
  end

  @doc "For the get_board_state voice tool."
  def board_state(user, game_id) do
    with {:ok, game} <- get_game(user, game_id) do
      to_move = if game.status == "in_progress", do: side_to_move(game), else: nil

      {:ok,
       %{
         game_type: game.game_type,
         fen: current_fen(game),
         status: game.status,
         result: game.result,
         to_move: to_move,
         is_calibration: game.is_calibration
       }}
    end
  end

  @doc "For the get_last_move_analysis / explain_move voice tools. `ply` nil means the most recent move."
  def move_analysis(user, game_id, ply \\ nil) do
    with {:ok, game} <- get_game(user, game_id) do
      move = if ply, do: Enum.find(game.moves, &(&1.ply == ply)), else: List.last(game.moves)
      if move, do: {:ok, move}, else: {:error, :not_found}
    end
  end

  @doc """
  Takes back the human's last move together with the engine's automatic reply to it
  (always restores "your turn" -- this app has no standalone "let the engine move now"
  path, so a bare single-ply rewind would leave the game stuck). If the human's last
  move ended the game outright (checkmate/scored win, no engine reply exists), only
  that one move is dropped and the game is reopened to `"in_progress"`.

  Refused for calibration games (same reasoning as `hint/2` -- undoing a mistake would
  contaminate the skill measurement) and for games with nothing to undo yet.
  """
  def undo_move(user, game_id) do
    with {:ok, game} <- get_game(user, game_id),
         :ok <- ensure_undoable(game) do
      {:ok, _pid} = ensure_engine_started(game)
      {dropped, kept} = split_for_undo(game.moves)

      Repo.transaction(fn ->
        Enum.each(dropped, &Repo.delete!/1)

        game =
          if game.status == "in_progress" do
            game
          else
            game |> Game.reopen_changeset() |> Repo.update!()
          end

        game = %{game | moves: kept}

        case game_server(game.game_type).undo(game.id, replay_list(game)) do
          :ok -> game
          {:error, {:engine_unavailable, _reason}} -> Repo.rollback(:engine_unavailable)
        end
      end)
    end
  end

  @doc """
  For the request_hint voice tool. Hard-refused for calibration games --
  enforced here in code (not just in the voice agent's prompted behavior),
  since hinting would contaminate the skill measurement.
  """
  def hint(user, game_id) do
    with {:ok, game} <- get_game(user, game_id) do
      cond do
        game.is_calibration ->
          {:error, :hint_refused_calibration}

        game.status != "in_progress" ->
          {:error, :game_over}

        true ->
          {:ok, _pid} = ensure_engine_started(game)
          game_server(game.game_type).hint(game.id)
      end
    end
  end

  ## Internal

  defp game_server("chess"), do: GamesTutor.Chess.GameServer
  defp game_server("go"), do: GamesTutor.Go.GameServer

  defp ensure_engine_started(%Game{game_type: "chess"} = game) do
    GamesTutor.Chess.GameServer.ensure_started(game.id, game.opponent_engine_config, move_ucis(game), game.human_color)
  end

  defp ensure_engine_started(%Game{game_type: "go"} = game) do
    GamesTutor.Go.GameServer.ensure_started(game.id, game.opponent_engine_config, go_history(game), game.human_color)
  end

  # The mover who moves first is either the human (the traditional default
  # in both game types) or the engine, when the human chose to play second
  # -- see create_game/2's synchronous opening-move handling.
  defp side_to_move(%Game{moves: moves} = game) do
    first_mover = if engine_moves_first?(game.game_type, game.human_color), do: "engine", else: "human"
    if rem(length(moves), 2) == 0, do: first_mover, else: other_player(first_mover)
  end

  defp other_player("human"), do: "engine"
  defp other_player("engine"), do: "human"

  # White always moves first in chess, Black always moves first in Go (the
  # conventional "student" role games_tutor gives the human by default) --
  # so the engine only ever opens when the human chose the *other* color.
  defp engine_moves_first?("chess", "black"), do: true
  defp engine_moves_first?("go", "white"), do: true
  defp engine_moves_first?(_game_type, _human_color), do: false

  defp resolve_human_color(game_type, attrs) do
    case Map.get(attrs, "human_color") do
      color when color in ["white", "black"] -> color
      _ -> default_human_color(game_type)
    end
  end

  defp default_human_color("go"), do: "black"
  defp default_human_color(_chess), do: "white"

  defp resolve_opponent_config(_user, "chess", %{"opponent_elo" => elo}) when is_integer(elo),
    do: %{"elo" => elo}

  defp resolve_opponent_config(_user, "go", %{"opponent_max_visits" => v}) when is_integer(v),
    do: %{"max_visits" => v}

  defp resolve_opponent_config(user, game_type, %{"is_calibration" => true} = attrs) do
    self_reported = Map.get(attrs, "self_reported_elo")
    opts = if is_integer(self_reported), do: [self_reported_elo: self_reported], else: []
    profile = Skill.get_or_init_profile(user, game_type, opts)
    calibration_config(game_type, profile.estimated_rating)
  end

  defp resolve_opponent_config(_user, "chess", _attrs), do: %{"elo" => @default_calibration_elo}
  defp resolve_opponent_config(_user, "go", _attrs), do: %{"max_visits" => @default_calibration_visits}

  defp calibration_config("chess", rating), do: %{"elo" => round(rating)}
  defp calibration_config("go", rating), do: %{"max_visits" => rating_to_max_visits(rating)}

  # No natural rating<->maxVisits table exists for KataGo the way chess has
  # UCI_Elo -- approximate v1 linear map from the shared rating scale
  # (~400-2600, same range chess Elo and Go kyu/dan both map onto, see
  # GamesTutor.Skill.GoRatingAnchorTable) to a visit count.
  @min_visits 5
  @max_visits 400
  defp rating_to_max_visits(rating) do
    clamped = rating |> max(400) |> min(2600)
    round(@min_visits + (clamped - 400) / (2600 - 400) * (@max_visits - @min_visits))
  end

  defp ensure_in_progress(%Game{status: "in_progress"}), do: :ok
  defp ensure_in_progress(%Game{}), do: {:error, :game_over}

  # "resigned"/"aborted" aren't caused by a stored move (resign/2 inserts no Move
  # row), so there's nothing for undo to meaningfully take back in those states.
  @undoable_statuses ~w(in_progress checkmate stalemate draw scored)

  defp ensure_undoable(%Game{is_calibration: true}), do: {:error, :undo_refused_calibration}
  defp ensure_undoable(%Game{moves: []}), do: {:error, :no_moves_to_undo}
  defp ensure_undoable(%Game{status: status}) when status in @undoable_statuses, do: :ok
  defp ensure_undoable(%Game{}), do: {:error, :cannot_undo}

  # Drops the engine's reply plus the human move that prompted it (the normal case --
  # always restores "your turn"), unless the very last move was the human's own and
  # ended the game outright (no engine reply exists to drop alongside it).
  defp split_for_undo(moves) do
    n = if List.last(moves).player == "engine", do: 2, else: 1
    {kept, dropped} = Enum.split(moves, length(moves) - n)
    {dropped, kept}
  end

  defp replay_list(%Game{game_type: "chess"} = game), do: move_ucis(game)
  defp replay_list(%Game{game_type: "go"} = game), do: go_history(game)

  defp move_ucis(%Game{moves: moves}) when is_list(moves), do: Enum.map(moves, & &1.uci)
  defp move_ucis(%Game{}), do: []

  defp go_history(%Game{moves: moves, human_color: human_color}) when is_list(moves) do
    human_tag = if human_color == "black", do: "B", else: "W"
    engine_tag = if human_tag == "B", do: "W", else: "B"
    Enum.map(moves, fn m -> [if(m.player == "human", do: human_tag, else: engine_tag), m.uci] end)
  end

  defp go_history(%Game{}), do: []

  defp persist_result(game, %{status: status, human_move: human_attrs, engine_move: engine_attrs}) do
    Repo.transaction(fn ->
      {:ok, human_move} = insert_move(game, human_attrs)
      engine_move = engine_attrs && insert_move!(game, engine_attrs)

      {game, skill_profile} =
        case status do
          :continue -> {game, nil}
          terminal -> finish_game(game, terminal)
        end

      %{game: game, human_move: human_move, engine_move: engine_move, skill_profile: skill_profile}
    end)
  end

  defp insert_move(game, attrs) do
    %Move{} |> Move.create_changeset(Map.put(attrs, :game_id, game.id)) |> Repo.insert()
  end

  defp insert_move!(game, attrs) do
    {:ok, move} = insert_move(game, attrs)
    move
  end

  # Returns `{game, skill_profile_or_nil}` -- the profile is only non-nil
  # when this was a calibration game with analyzable moves (see
  # `Skill.record_calibration_result/1`).
  defp finish_game(game, status) do
    {db_status, result} = translate_status(status)

    game =
      game
      |> Game.finish_changeset(%{
        status: db_status,
        result: result,
        ended_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

    if game.game_type == "chess" do
      {:ok, _pid} = PostGameAnalysis.enqueue(game.id)
    end

    skill_profile =
      if game.is_calibration do
        {:ok, profile} = Skill.record_calibration_result(game)
        profile
      end

    {game, skill_profile}
  end

  defp translate_status({:checkmate, :white_wins}), do: {"checkmate", "white_wins"}
  defp translate_status({:checkmate, :black_wins}), do: {"checkmate", "black_wins"}
  defp translate_status({:draw, :stalemate}), do: {"stalemate", "draw"}
  defp translate_status({:draw, _reason}), do: {"draw", "draw"}
  defp translate_status({:scored, :white_wins}), do: {"scored", "white_wins"}
  defp translate_status({:scored, :black_wins}), do: {"scored", "black_wins"}
  defp translate_status({:scored, :draw}), do: {"scored", "draw"}
  defp translate_status({:winner, color, {:manual, :human_resigned}}), do: {"resigned", "#{color}_wins"}
  defp translate_status({:winner, :white, _reason}), do: {"aborted", "white_wins"}
end
