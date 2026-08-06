defmodule GamesTutor.Voice.ToolsTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Voice.Tools

  test "schema defines all six plan-required tools, no make_move tool" do
    names = Enum.map(Tools.schema(), & &1.name)

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

  test "every tool has a valid OpenAI function-calling shape" do
    Enum.each(Tools.schema(), fn tool ->
      assert tool.type == "function"
      assert is_binary(tool.name)
      assert is_binary(tool.description)
      assert tool.parameters.type == "object"
      assert is_map(tool.parameters.properties)
      assert is_list(tool.parameters.required)
    end)
  end

  test "calibration_proctor instructions explicitly frame silence and refusal" do
    text = Tools.instructions("calibration_proctor")
    assert text =~ "quiet"
    assert text =~ "decline"
  end

  test "tutoring instructions differ from calibration_proctor" do
    assert Tools.instructions("tutoring") != Tools.instructions("calibration_proctor")
  end
end
