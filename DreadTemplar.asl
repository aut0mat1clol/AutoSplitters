state("DreadTemplar") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    vars.Helper.LoadSceneManager = true;
}

init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
        vars.Helper["Menu"] = mono.Make<int>("MenuController", "instance", "curMenu");
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

    print(current.activeScene);
    print("Loading - " + current.loadingScene);
    print(current.Menu.ToString());
    // IntroScene 

}

start
{
    return current.activeScene == "TutorialScene" && current.activeScene != old.activeScene; 
}

isLoading
{
    return current.activeScene != current.loadingScene || current.Menu == 5;
}

split
{   
    if(current.activeScene != "IntroScene")
    {
        return current.activeScene != old.activeScene;
    }
}

reset
{
    return current.activeScene == "MainScene";
}