defmodule GamesTutorWeb.SkillProfileController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Skill
  alias GamesTutor.Guardian

  def index(conn, _params) do
    profiles = Skill.list_profiles(Guardian.Plug.current_resource(conn))
    json(conn, %{skill_profiles: Enum.map(profiles, &GamesTutorWeb.GameJSON.skill_profile/1)})
  end
end
