state("HYPERFATAL") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    vars.Helper.LoadSceneManager = true;

    // Add setting 'mission1', enabled by default, with 'First Mission' being displayed in the GUI
    settings.Add("democat", false, "Select Demo Category");
    settings.Add("demmaincamp", false, "Main Campaign", "democat");
    settings.Add("demtutor", false, "Tutorials", "democat");
    settings.Add("demmovcour", false, "Movement Courses", "democat");
}

init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
        vars.Helper["IGT"] = mono.Make<float>("UISpeedrunTimer", "_currentTime");
        vars.Helper["EndScreen"] = mono.Make<bool>("UIPlayerEndScreen", "Instance", "_isHasPlayedAnimOnce");
        return true;
    });

    vars.TotalGameTime = 0;
}


onStart
{
    vars.TotalGameTime = 0;
}

update
{
    // Get the current active scene's name and set it to `current.activeScene`
    // Sometimes, it is null, so fallback to old value
    current.activeScene = vars.Helper.Scenes.Active.Name ?? current.activeScene;
    // Usually the scene that's loading, a bit jank in this version of asl-help
    current.loadingScene = vars.Helper.Scenes.Loaded[0].Name ?? current.loadingScene;

    print(current.activeScene);
    print("Loading - " + current.loadingScene);
}
isLoading
{
    return true;
}

start
{
    if (settings["demmaincamp"] && current.activeScene == "1 2" && old.IGT == 0 && current.IGT > 0)
    {
        return true;
    }
    if (settings["demtutor"] && current.activeScene == "TutFastFall1" && old.IGT == 0 && current.IGT > 0)
    {
        return true;
    }
    if (settings["demmovcour"] && current.activeScene == "ParkourCourse1" && old.IGT == 0 && current.IGT > 0)
    {
        return true;
    }
}

split
{
    return current.EndScreen == true && old.EndScreen != current.EndScreen;
}
reset
{
    if (current.activeScene == "Hub")
    {
        return true;        
    }
}

gameTime
{
    if (current.IGT < old.IGT){
        vars.TotalGameTime += old.IGT;
    }

    return TimeSpan.FromSeconds(vars.TotalGameTime + current.IGT);
}