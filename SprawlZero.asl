state("Silas-Win64-Test") { }
state("Silas-Win64-Shipping") { }

startup
{
    settings.Add("loadRemoval", true, "Enable Load Removal");
    settings.Add("ilmode", true, "Individual Level mode");
    settings.SetToolTip("ilmode", "Start timer when loading any level from menu");
}

init
{
    var module = modules.First();
    var scanner = new SignatureScanner(game, module.BaseAddress, module.ModuleMemorySize);

    // ---------- GWorld ----------
    var gworldSig = new SigScanTarget(3,
        "48 8B 1D ?? ?? ?? ?? 48 85 DB 74 ?? 41 B0 01 33 D2 48 8B CB"
    );
    gworldSig.OnFound = (p, s, ptr) => ptr + 0x4 + p.ReadValue<int>(ptr);

    vars.gworldPtr = scanner.Scan(gworldSig);
    if (vars.gworldPtr == IntPtr.Zero)
        throw new Exception("GWorld not found");

    // ---------- GNames ----------
    var gnamesSig = new SigScanTarget(3,
        "48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 4C 8B F8 C6"
    );
    gnamesSig.OnFound = (p, s, ptr) => ptr + 0x4 + p.ReadValue<int>(ptr);

    vars.gnamesPtr = scanner.Scan(gnamesSig);
    if (vars.gnamesPtr == IntPtr.Zero)
        vars.gnamesPtr = (IntPtr)((long)module.BaseAddress + 0x9152FC0L);

    // ---------- FName decode ----------
    vars.DecodeFName = (Func<int, string>)((id) =>
    {
        if (id == 0) return "";
        int block = id >> 16;
        int offset = (id & 0xFFFF) * 2;
        IntPtr blockPtr = game.ReadValue<IntPtr>(
            (IntPtr)((long)vars.gnamesPtr + 0x10 + block * 8)
        );
        if (blockPtr == IntPtr.Zero) return "";
        IntPtr entry = (IntPtr)((long)blockPtr + offset);
        short header = game.ReadValue<short>(entry);
        int len = header >> 6;
        if (len <= 0 || len > 1024) return "";
        bool wide = (header & 1) == 1;
        IntPtr str = (IntPtr)((long)entry + 2);
        return wide
            ? game.ReadString(str, ReadStringType.UTF16, len * 2)
            : game.ReadString(str, ReadStringType.ASCII, len);
    });

    // ---------- GNames validation ----------
    vars.CheckGNames = (Func<bool>)(() =>
    {
        string[] knownNames = { "None", "ByteProperty", "IntProperty", "BoolProperty",
                                "Object", "Class", "FloatProperty" };
        for (int i = 0; i < 200; i++) {
            string s = vars.DecodeFName(i);
            if (string.IsNullOrEmpty(s)) continue;
            foreach (var known in knownNames) {
                if (s == known) return true;
            }
        }
        return false;
    });

    if (!vars.CheckGNames()) {
        vars.gnamesPtr = (IntPtr)((long)module.BaseAddress + 0x9152FC0L);
        if (!vars.CheckGNames())
            throw new Exception("GNames not found via AOB or fallback");
    }

    // ---------- Offsets ----------
    // UWorld -> OwningGameInstance -> LocalPlayers[0] -> PlayerController -> Pawn
    vars.OFF_UWorld_GameInstance = 0x228;
    vars.OFF_GI_LocalPlayers     = 0x38;
    vars.OFF_LP_PlayerController = 0x30;
    vars.OFF_PC_Pawn             = 0x2F0;

    // ---------- Object chain ----------
    vars.GetGameInstance = (Func<IntPtr>)(() =>
    {
        try {
            IntPtr uworld = game.ReadValue<IntPtr>((IntPtr)vars.gworldPtr);
            if (uworld == IntPtr.Zero) return IntPtr.Zero;
            return game.ReadValue<IntPtr>((IntPtr)((long)uworld + (int)vars.OFF_UWorld_GameInstance));
        } catch { return IntPtr.Zero; }
    });

    vars.GetLocalPlayer = (Func<IntPtr>)(() =>
    {
        try {
            IntPtr gi = vars.GetGameInstance();
            if (gi == IntPtr.Zero) return IntPtr.Zero;
            // TArray = { Data*: +0x0, Num: +0x8 }
            IntPtr data = game.ReadValue<IntPtr>((IntPtr)((long)gi + (int)vars.OFF_GI_LocalPlayers));
            int num = game.ReadValue<int>((IntPtr)((long)gi + (int)vars.OFF_GI_LocalPlayers + 0x8));
            if (data == IntPtr.Zero || num <= 0) return IntPtr.Zero;
            return game.ReadValue<IntPtr>(data); // [0]
        } catch { return IntPtr.Zero; }
    });

    vars.GetPlayerController = (Func<IntPtr>)(() =>
    {
        try {
            IntPtr lp = vars.GetLocalPlayer();
            if (lp == IntPtr.Zero) return IntPtr.Zero;
            return game.ReadValue<IntPtr>((IntPtr)((long)lp + (int)vars.OFF_LP_PlayerController));
        } catch { return IntPtr.Zero; }
    });

    vars.GetPawn = (Func<IntPtr>)(() =>
    {
        try {
            IntPtr pc = vars.GetPlayerController();
            if (pc == IntPtr.Zero) return IntPtr.Zero;
            return game.ReadValue<IntPtr>((IntPtr)((long)pc + (int)vars.OFF_PC_Pawn));
        } catch { return IntPtr.Zero; }
    });

    // UObject +0x10 ClassPrivate -> UClass +0x18 FName
    vars.GetObjectClassName = (Func<IntPtr, string>)((obj) =>
    {
        try {
            if (obj == IntPtr.Zero) return "";
            IntPtr cls = game.ReadValue<IntPtr>((IntPtr)((long)obj + 0x10));
            if (cls == IntPtr.Zero) return "";
            int id = game.ReadValue<int>((IntPtr)((long)cls + 0x18));
            return vars.DecodeFName(id) ?? "";
        } catch { return ""; }
    });

    vars.GetPawnClassName = (Func<string>)(() =>
    {
        try { return vars.GetObjectClassName(vars.GetPawn()); }
        catch { return ""; }
    });

    // ---------- Map ----------
    vars.GetMap = (Func<string>)(() =>
    {
        IntPtr uworld = game.ReadValue<IntPtr>((IntPtr)vars.gworldPtr);
        if (uworld == IntPtr.Zero) return "";
        int nameId = game.ReadValue<int>((IntPtr)((long)uworld + 0x18));
        return vars.DecodeFName(nameId);
    });

    // ---------- Loading ----------
    vars.IsLoading = (Func<bool>)(() =>
    {
        try {
            IntPtr uworld = game.ReadValue<IntPtr>((IntPtr)vars.gworldPtr);
            if (uworld == IntPtr.Zero) return true;
            IntPtr gi = game.ReadValue<IntPtr>((IntPtr)((long)uworld + 0x228));
            if (gi == IntPtr.Zero) return true;
            IntPtr loadingWidget = game.ReadValue<IntPtr>((IntPtr)((long)gi + 0x210));
            if (loadingWidget != IntPtr.Zero) return true;
            long tail = game.ReadValue<long>((IntPtr)((long)uworld + 0x190));
            return (tail >> 32) != 0;
        } catch { return false; }
    });
}

update
{
    current.map = vars.GetMap() ?? "";
    current.loading = vars.IsLoading();
    current.pawnClass = vars.GetPawnClassName();
}

start
{
    if (!((IDictionary<string, object>)old).ContainsKey("map")) return false;

    string oldMap = old.map ?? "";
    string curMap = current.map ?? "";
    timer.IsGameTimePaused = true;

    if (settings["ilmode"])
        return current.loading == false && current.loading != old.loading && !curMap.Contains("_Briefing") && !curMap.Contains("_Cinematic");

    return oldMap != curMap && curMap == "E1M1";
}

split
{
    var splitKeys = (IDictionary<string, object>)old;
    if (!splitKeys.ContainsKey("map")) return false;

    // Epilogue Cutscene
    if (splitKeys.ContainsKey("pawnClass"))
    {
        string oldPawn = old.pawnClass ?? "";
        string curPawn = current.pawnClass ?? "";
        if (curPawn != oldPawn && curPawn == "BP_CutscenePawn_Epilogue_C")
            return true;
    }

    string oldMap = old.map ?? "";
    string curMap = current.map ?? "";
    if (curMap == oldMap) return false;
    if (string.IsNullOrEmpty(curMap) || curMap == "None") return false;

    return curMap.Contains("_Briefing") || curMap == "Epilogue" || curMap == "E3M3";
}

reset
{
    if (!((IDictionary<string, object>)old).ContainsKey("map")) return false;

    string curMap = current.map ?? "";
    string oldMap = old.map ?? "";

    return curMap == "MainMenu" && !string.IsNullOrEmpty(oldMap);
}

isLoading
{
    if (!settings["loadRemoval"]) return false;
    if (!((IDictionary<string, object>)current).ContainsKey("loading")) return false;
    return current.loading;
}
