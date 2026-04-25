state("BJ2") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/unity-help")).CreateInstance("Unity");
}

init
{
    vars.allWorksDone = vars.Helper.Make<bool>("PlayerStart", 0, "all_works_done");
    vars.isCutscenePlaying = vars.Helper.Make<bool>("PlayerMovement", 0, "active_controller", "player", "can_be_controlled");
    vars.isPlaying = vars.Helper.Make<bool>("PlayerMovement", 0, "active_controller", "player", "gui", "text_stat_time", 0x10, 0x39);
    vars.isPaused = vars.Helper.Make<bool>("PlayerMovement", 0, "active_controller", "player", "pause", "is_paused");
}

update
{
    current.activeScene = vars.Helper.SceneManager.Current.Name ?? old.activeScene;
    print("IsPlaying: " + vars.isPlaying.Current.ToString());
    print("IsPaused: " + vars.isPaused.Current.ToString());
    print("isCutscenePlaying: " + vars.isCutscenePlaying.Current.ToString());
}
start
{
    if (current.activeScene == "E1L-1" && vars.isPlaying.Current == true && vars.isPlaying.Current != vars.isPlaying.Old)
    {
        return true;
    }
}

split
{
    if (current.activeScene != old.activeScene && old.activeScene == "UI_Scene_Loading")
    {
        return true;
    }
}
isLoading
{
    if(vars.isPlaying.Current == false && vars.isPaused.Current == false && vars.isCutscenePlaying.Current == true)
    {
        return true;
    }
    if(vars.isPaused.Current == true || vars.isPlaying.Current == true || vars.isCutscenePlaying.Current == false)
    {
        return false;
    }
}
reset
{
    return current.activeScene == "UI_Scene_MainMenu";
}