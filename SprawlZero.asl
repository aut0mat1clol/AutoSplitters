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

    // ============ GWORLD ============
    var gworldSig = new SigScanTarget(3,
        "48 8B 1D ?? ?? ?? ?? 48 85 DB 74 ?? 41 B0 01 33 D2 48 8B CB"
    );
    gworldSig.OnFound = (p, s, ptr) => ptr + 0x4 + p.ReadValue<int>(ptr);

    vars.gworldPtr = scanner.Scan(gworldSig);
    if (vars.gworldPtr == IntPtr.Zero)
        throw new Exception("GWorld not found");
    print("[ASL] GWorld @ 0x" + ((long)vars.gworldPtr).ToString("X"));

    // ============ GNAMES via AOB (robust) ============
    var gnamesSig = new SigScanTarget(3,
        "48 8D 0D ?? ?? ?? ?? E8 ?? ?? ?? ?? 4C 8B F8 C6"
    );
    gnamesSig.OnFound = (p, s, ptr) => ptr + 0x4 + p.ReadValue<int>(ptr);

    vars.gnamesPtr = scanner.Scan(gnamesSig);

    if (vars.gnamesPtr == IntPtr.Zero) {
        print("[ASL] ⚠️ GNames AOB not found, trying fallback offset");
        vars.gnamesPtr = (IntPtr)((long)module.BaseAddress + 0x9152FC0L);
    }
    print("[ASL] GNames @ 0x" + ((long)vars.gnamesPtr).ToString("X"));

    // ============ DECODE FNAME ============
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

    // ============ VALIDATE GNAMES (sanity check) ============
    bool gnamesValid = false;
    string[] knownNames = { "None", "ByteProperty", "IntProperty", "BoolProperty",
                            "Object", "Class", "FloatProperty" };
    for (int i = 0; i < 200 && !gnamesValid; i++) {
        string s = vars.DecodeFName(i);
        if (!string.IsNullOrEmpty(s)) {
            foreach (var known in knownNames) {
                if (s == known) { gnamesValid = true; break; }
            }
        }
    }

    if (!gnamesValid) {
        print("[ASL] ⚠️ GNames validation failed, trying fallback offset");
        vars.gnamesPtr = (IntPtr)((long)module.BaseAddress + 0x9152FC0L);
        for (int i = 0; i < 200 && !gnamesValid; i++) {
            string s = vars.DecodeFName(i);
            foreach (var known in knownNames) {
                if (s == known) { gnamesValid = true; break; }
            }
        }
        if (!gnamesValid) {
            throw new Exception("GNames not found via AOB or fallback");
        }
    }
    print("[ASL] ✅ GNames validated");

    // ============ GET MAP ============
    vars.GetMap = (Func<string>)(() =>
    {
        IntPtr uworld = game.ReadValue<IntPtr>((IntPtr)vars.gworldPtr);
        if (uworld == IntPtr.Zero) return "";
        int nameId = game.ReadValue<int>((IntPtr)((long)uworld + 0x18));
        return vars.DecodeFName(nameId);
    });

    // ============ IS LOADING ============
    //     may be useful later
    //     IntPtr snapshot = game.ReadValue<IntPtr>((IntPtr)((long)gi + 0x220)); // SilasSnapshotSaveGame
    //     if (snapshot != IntPtr.Zero) return true;
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
    if (current.map != old.map)
    {
        print(old.map + " -> " + current.map);
    }
    
}

start
{
    if (!((IDictionary<string, object>)old).ContainsKey("map")) return false;

    string oldMap = old.map ?? "";
    string curMap = current.map ?? "";
    timer.IsGameTimePaused = true;
    
    if (settings["ilmode"])
        return oldMap.EndsWith("_Briefing") && oldMap != curMap;

    return oldMap != curMap && curMap == "E1M1";
}

split
{
    if (!((IDictionary<string, object>)old).ContainsKey("map")) return false;

    string oldMap = old.map ?? "";
    string curMap = current.map ?? "";

    if (curMap == oldMap) return false;
    if (string.IsNullOrEmpty(curMap) || curMap == "None") return false;

    return (curMap.EndsWith("_Briefing") && curMap != oldMap) || curMap == "DemoFinish";
}

reset
{
    if (!((IDictionary<string, object>)old).ContainsKey("map")) return false;

    string oldMap = old.map ?? "";
    string curMap = current.map ?? "";

    return curMap == "MainMenu" && oldMap != "" && !string.IsNullOrEmpty(oldMap);
}

isLoading
{
    if (!settings["loadRemoval"]) return false;
    if (!((IDictionary<string, object>)current).ContainsKey("loading")) return false;
    return current.loading;
}
