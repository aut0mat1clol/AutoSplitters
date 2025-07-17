state("BloodyTrapland2") { }

startup
{
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");
    
    settings.Add("levelSplit", true, "Split on every Level change");
    settings.Add("worldSplit", true, "Split on every World change");
}
init
{
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
        vars.Helper["LevelID"] = mono.Make<int>("StoryModeHandler", "levelId");
        vars.Helper["WorldID"] = mono.Make<int>("StoryModeHandler", "worldId");
        vars.Helper["LevelLoaded"] = mono.Make<int>("MainGame", "LevelLoaded");
        vars.Helper["levelCompletedName"] = mono.MakeString("MainGame", "levelCompletedName");
        return true;
    });

    vars.doneLevels = new List<string>();
}
update
{
    vars.Log("LevelID - " + current.LevelID);
    vars.Log("WorldID - " + current.WorldID);
    vars.Log("LevelLoaded - " + current.LevelLoaded);
    vars.Log("levelCompletedName - " + current.levelCompletedName);
}
start
{
    if (current.LevelID == 0 && current.WorldID == 0 && current.LevelLoaded == 0 && old.LevelLoaded != 0)
    {
        return true;
    }
}
split
{
    if (current.levelCompletedName != old.levelCompletedName && current.levelCompletedName != "" && settings["levelSplit"] == true)
    {
        vars.doneLevels.Add(current.levelCompletedName);
        return true;
    }
    if (current.WorldID != old.WorldID && settings["worldSplit"] == true)
    {
        vars.doneLevels.Add(current.WorldID);
        return true;
    }
}
onReset
{
    vars.doneLevels.Clear(); 
}