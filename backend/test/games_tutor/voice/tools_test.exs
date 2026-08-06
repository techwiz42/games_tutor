defmodule GamesTutor.Voice.ToolsTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Voice.Tools

  test "schema defines all six plan-required tools, no make_move tool" do
    names = Enum.map(Tools.schema("chess"), & &1.name)

    assert names == [
             "get_board_state",
             "get_last_move_analysis",
             "explain_move",
             "request_hint",
             "adjust_explanation_depth",
             "get_skill_profile"
           ]

    refute "make_move" in names
  end

  test "every tool has a valid OpenAI function-calling shape, for both game types" do
    for game_type <- ~w(chess go) do
      Enum.each(Tools.schema(game_type), fn tool ->
        assert tool.type == "function"
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert tool.parameters.type == "object"
        assert is_map(tool.parameters.properties)
        assert is_list(tool.parameters.required)
      end)
    end
  end

  test "get_skill_profile's description mentions the right game type" do
    chess_tool = Tools.schema("chess") |> Enum.find(&(&1.name == "get_skill_profile"))
    go_tool = Tools.schema("go") |> Enum.find(&(&1.name == "get_skill_profile"))

    assert chess_tool.description =~ "chess"
    assert go_tool.description =~ "go"
  end

  test "calibration_proctor instructions explicitly frame silence and refusal, for both game types" do
    for game_type <- ~w(chess go) do
      text = Tools.instructions("calibration_proctor", game_type)
      assert text =~ "quiet"
      assert text =~ "decline"
      assert text =~ game_type
    end
  end

  test "calibration_proctor's legality example is game-type-appropriate" do
    assert Tools.instructions("calibration_proctor", "chess") =~ "castle"
    refute Tools.instructions("calibration_proctor", "go") =~ "castle"
  end

  test "tutoring instructions differ from calibration_proctor, for both game types" do
    for game_type <- ~w(chess go) do
      assert Tools.instructions("tutoring", game_type) != Tools.instructions("calibration_proctor", game_type)
      assert Tools.instructions("tutoring", game_type) =~ game_type
    end
  end

  test "tutoring instructions require grounding in real engine output, not invented analysis" do
    text = Tools.instructions("tutoring", "chess")
    assert text =~ "engine_best_move"
    assert text =~ "never invented"
  end

  test "tutoring instructions frame this as a single self-contained answer, not open conversation" do
    text = Tools.instructions("tutoring", "chess")
    assert text =~ "not an open-ended conversation"
  end
end
