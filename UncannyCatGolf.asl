state("UncannyCatGolfPlaytest2") 
{ 
    double TotalTime : "UncannyCatGolfPlaytest2.exe", 0x04146330, 0x948, 0x70, 0x58, 0x38;
    byte isWorldFinished : "UncannyCatGolfPlaytest2.exe", 0x04146448, 0xC08, 0x18, 0x498, 0x2B4; // 1 - playing, 0 - transition screen
}
state("UCG")
{
    double TotalTime : "UCG.exe", 0x057DF9C4, 0x24C, 0x44, 0x38, 0x38;
    byte isWorldFinished : "UCG.exe", 0x057D1688, 0xBB4, 0xC, 0x24; // 1 - playing, 0 - transition screen
}

update
{
}

gameTime
{
    return TimeSpan.FromSeconds(current.TotalTime);
}

start
{
    return current.TotalTime != old.TotalTime && old.TotalTime == 0;
}

split
{
    
    return current.isWorldFinished != old.isWorldFinished && current.isWorldFinished == 0;
    
}

reset
{
    return current.TotalTime == 0;
}

isLoading
{
    return true;
}