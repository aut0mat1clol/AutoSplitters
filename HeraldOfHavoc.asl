state("HeraldOfHavoc") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    vars.Helper.LoadSceneManager = true;

    // Add setting 'mission1', enabled by default, with 'First Mission' being displayed in the GUI
    settings.Add("iemod", true, "Individual Episodes Start");
}

init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
        vars.Helper["EnterLevelScreenShown"] = mono.Make<bool>("ScreenEnteringLevel", 1, "_instance", "isShown", "_currentValue");
        vars.Helper["EndScreenShown"] = mono.Make<bool>("EndScreenManager", 1, "_instance", "isShown", "_currentValue");

        return true;
    });
}

update
{
    // Get the current active scene's name and set it to `current.activeScene`
    // Sometimes, it is null, so fallback to old value
    current.activeScene = vars.Helper.Scenes.Active.Name ?? current.activeScene;
    // Usually the scene that's loading, a bit jank in this version of asl-help
    current.loadingScene = vars.Helper.Scenes.Loaded[0].Name ?? current.loadingScene;
        // Log changes to the active scene
    if (old.activeScene != current.activeScene) {
        vars.Log("activeScene: " + old.activeScene + " -> " + current.activeScene);
    }
    if (old.loadingScene != current.loadingScene) {
        vars.Log("loadingScene: " + old.loadingScene + " -> " + current.loadingScene);
    }
}


start
{
    if (current.activeScene == "Scene_Demo")
    {
        return true;
    }
    
    if (current.activeScene == "Scene_E2M1_Snowy" && settings["iemod"] == true)
    {
        return true;
    }
    
    if (current.activeScene == "Scene_E3M1_Intrusion" && settings["iemod"] == true)
    {
        return true;
    }
}

isLoading
{
    return current.EnterLevelScreenShown
        || current.EndScreenShown;
}

split
{
    if (current.activeScene == "Scene_Gameplay" && old.loadingScene != current.loadingScene){
        return true;
    }
    if (old.activeScene == "Scene_E3M5_HeraldOfHavoc" && old.loadingScene != current.loadingScene){
        return true;
    }
}