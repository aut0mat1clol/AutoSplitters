state("AVIAO3GAME") {}
state("FLESHCANCER") {}

startup
{
    settings.Add("split_level_end", true, "Split on level screen (isFinished)");
    
    vars.realMapWatcher = null; 
    vars.candidateWatchers = new List<StringWatcher>(); 
    
    vars.timerWatcher = null;
    vars.isFinishedWatcher = null;
    
    vars.initFailed = true;
    vars.scanAttempts = 0;

    vars.totalGameTime = 0f;    
    vars.hasSplitThisLevel = false;
    vars.completedLevels = new List<string>();

    // --- Level Name Fixation/Latching ---
    vars.latchedLevelName = "";
    vars.pendingLevelName = "";
    vars.levelNameStableCount = 0;
    vars.LEVEL_NAME_STABLE_FRAMES = 8;
    vars.lastLatchedLevel = "";
    vars.levelJustChanged = false;

    // --- Map Pointer Debouncing ---
    vars.candidateStableCounts = new Dictionary<StringWatcher, int>();
    vars.candidateLastValues = new Dictionary<StringWatcher, string>();
    vars.CANDIDATE_STABLE_REQUIRED = 120;

    // --- isFinished Fixation/Debouncing ---
    vars.latchedIsFinished = 0;
    vars.prevLatchedIsFinished = 0;
    vars.finishedHighStableCount = 0;
    vars.finishedLowStableCount = 0;
    vars.FINISHED_STABLE_RISE = 3;
    vars.FINISHED_STABLE_FALL = 30;

    // --- Post-load grace period (blocks splits/isFinished after any load) ---
    vars.loadGraceFrames = 0;
    vars.LOAD_GRACE_DURATION = 90;

    // --- False-reset protection (detect when we are leaving start to load another level) ---
    vars.leavingStart = false;

    // --- Run state ---
    vars.inRun = false;
}

init
{
    vars.module = modules.First();
    vars.initFailed = true;
    vars.scanAttempts = 0;
    
    vars.realMapWatcher = null;
    vars.candidateWatchers.Clear();
    vars.timerWatcher = null;
    vars.isFinishedWatcher = null;

    vars.latchedLevelName = "";
    vars.pendingLevelName = "";
    vars.levelNameStableCount = 0;
    vars.lastLatchedLevel = "";
    vars.levelJustChanged = false;
    vars.latchedIsFinished = 0;
    vars.prevLatchedIsFinished = 0;
    vars.finishedHighStableCount = 0;
    vars.finishedLowStableCount = 0;
    vars.loadGraceFrames = 0;
    vars.leavingStart = false;

    vars.candidateStableCounts.Clear();
    vars.candidateLastValues.Clear();

    vars.inRun = false;

    vars.isFleshcancer = game.ProcessName.ToLower().Contains("fleshcancer");
    
    if (vars.isFleshcancer) {
        print("[BDD Engine] Detected Fleshcancer — auto-reset on start.bsp disabled.");
    } else {
        print("[BDD Engine] Detected BDD3 — auto-reset on start.bsp enabled.");
    }
}

update
{
    if (vars.initFailed)
    {
        vars.scanAttempts++;
        if (vars.scanAttempts % 100 != 0) return false;

        print("[BDD Engine] Attempting memory scan (Engine warmup)...");

        var scanner = new SignatureScanner(game, vars.module.BaseAddress, vars.module.ModuleMemorySize);

        var finishedTarget = new SigScanTarget(2, "39 1D ?? ?? ?? ?? 75 ?? 0F 2F");
        finishedTarget.OnFound = (proc, s, ptr) => {
            int offset = proc.ReadValue<int>(ptr);
            return ptr + 4 + offset; 
        };
        IntPtr finishedPtr = scanner.Scan(finishedTarget);

        var mapTarget = new SigScanTarget(8, "00 00 00 00 00 00 00 00 6D 61 70 73 2F");
        
        IntPtr ptrMap = scanner.Scan(mapTarget);
        int mapCount = 0;
        long endOfModule = vars.module.BaseAddress.ToInt64() + vars.module.ModuleMemorySize;
        
        vars.candidateWatchers.Clear();
        vars.candidateStableCounts.Clear();
        vars.candidateLastValues.Clear();

        while (ptrMap != IntPtr.Zero)
        {
            var newCandidate = new StringWatcher(ptrMap, ReadStringType.ASCII, 64);
            vars.candidateWatchers.Add(newCandidate);
            vars.candidateStableCounts[newCandidate] = 0;
            vars.candidateLastValues[newCandidate] = "";
            mapCount++;
            
            IntPtr nextStart = ptrMap + 1;
            long remainingSize = endOfModule - nextStart.ToInt64();
            if (remainingSize <= 0) break;
            
            var nextScanner = new SignatureScanner(game, nextStart, (int)remainingSize);
            ptrMap = nextScanner.Scan(mapTarget);
            
            if (mapCount > 100) break; 
        }

        if (finishedPtr != IntPtr.Zero && mapCount > 0)
        {
            print("[BDD Engine] WARMUP SUCCESSFUL!");
            print("[BDD Engine] isFinished found at: 0x" + finishedPtr.ToString("X"));
            
            IntPtr timerPtr = finishedPtr - 0x1188;
            print("[BDD Engine] Timer calculated at: 0x" + timerPtr.ToString("X"));
            
            vars.isFinishedWatcher = new MemoryWatcher<int>(finishedPtr);
            vars.timerWatcher = new MemoryWatcher<float>(timerPtr);
            
            print("[BDD Engine] Found " + mapCount + " potential map addresses.");
            
            vars.initFailed = false; 
        }
        else
        {
            print("[BDD Engine] Warmup failed. Retrying later...");
            return false; 
        }
    }

    vars.timerWatcher.Update(game);
    vars.isFinishedWatcher.Update(game);

    if (vars.realMapWatcher != null)
    {
        vars.realMapWatcher.Update(game);
    }
    else
    {
        foreach (var watcher in vars.candidateWatchers)
        {
            watcher.Update(game);
            string newVal = watcher.Current;

            bool isValid = !string.IsNullOrEmpty(newVal) 
                && newVal.StartsWith("maps/") 
                && newVal.EndsWith(".bsp") 
                && newVal.Length > 9
                && !newVal.StartsWith("maps/b_"); // ignore background/scenery maps (b_bh, b_rock0, ...)

            if (isValid)
            {
                string lastVal = vars.candidateLastValues[watcher];
                if (newVal == lastVal)
                {
                    vars.candidateStableCounts[watcher]++;
                }
                else
                {
                    vars.candidateStableCounts[watcher] = 1;
                    vars.candidateLastValues[watcher] = newVal;
                }

                if (vars.candidateStableCounts[watcher] >= vars.CANDIDATE_STABLE_REQUIRED)
                {
                    print("[BDD Engine] BINGO! Found the real map variable!");
                    print("[BDD Engine] Confirmed stable map value: " + newVal);
                    
                    vars.realMapWatcher = watcher;
                    vars.latchedLevelName = newVal;
                    vars.pendingLevelName = newVal;
                    vars.levelNameStableCount = vars.LEVEL_NAME_STABLE_FRAMES;
                    vars.lastLatchedLevel = newVal;

                    vars.latchedIsFinished = 0;
                    vars.prevLatchedIsFinished = 0;
                    vars.finishedHighStableCount = 0;
                    vars.finishedLowStableCount = 0;
                    vars.loadGraceFrames = vars.LOAD_GRACE_DURATION;
                    vars.leavingStart = false;
                    vars.levelJustChanged = false;

                    vars.candidateWatchers.Clear();
                    vars.candidateStableCounts.Clear();
                    vars.candidateLastValues.Clear();
                    break;
                }
            }
            else
            {
                vars.candidateStableCounts[watcher] = 0;
                if (watcher.Changed && !string.IsNullOrEmpty(newVal) && newVal.StartsWith("maps/b_"))
                {
                    print("[BDD Engine] Ignored background map: " + newVal);
                }
            }
        }
    }
    
    if (vars.timerWatcher == null || vars.isFinishedWatcher == null) return false;

    float currentTimer = vars.timerWatcher.Current;
    float oldTimer = vars.timerWatcher.Old;
    int currentFinished = vars.isFinishedWatcher.Current;

    vars.prevLatchedIsFinished = vars.latchedIsFinished;
    vars.levelJustChanged = false;

    // --- Debounce isFinished flag ---
    if (currentFinished > 0)
    {
        vars.finishedHighStableCount++;
        vars.finishedLowStableCount = 0;
        if (vars.finishedHighStableCount >= vars.FINISHED_STABLE_RISE)
            vars.latchedIsFinished = 1;
    }
    else
    {
        vars.finishedLowStableCount++;
        vars.finishedHighStableCount = 0;
        if (vars.finishedLowStableCount >= vars.FINISHED_STABLE_FALL)
            vars.latchedIsFinished = 0;
    }

    // --- Latch level name ---
    if (vars.realMapWatcher != null)
    {
        string rawMapValue = vars.realMapWatcher.Current;

        bool rawIsValid = !string.IsNullOrEmpty(rawMapValue)
            && rawMapValue.StartsWith("maps/")
            && rawMapValue.EndsWith(".bsp")
            && rawMapValue.Length > 9
            && !rawMapValue.StartsWith("maps/b_"); // ignore background/scenery maps (b_bh, b_rock0, ...)

        if (rawIsValid)
        {
            if (rawMapValue == vars.pendingLevelName)
            {
                vars.levelNameStableCount++;
            }
            else
            {
                vars.pendingLevelName = rawMapValue;
                vars.levelNameStableCount = 1;
            }

            if (vars.levelNameStableCount >= vars.LEVEL_NAME_STABLE_FRAMES)
            {
                if (vars.latchedLevelName != vars.pendingLevelName)
                {
                    print("[BDD Engine] Latched new level: " + vars.pendingLevelName);
                    vars.lastLatchedLevel = vars.latchedLevelName;
                    vars.latchedLevelName = vars.pendingLevelName;
                    vars.hasSplitThisLevel = false;
                    vars.levelJustChanged = true;
                }
                vars.levelNameStableCount = vars.LEVEL_NAME_STABLE_FRAMES;
            }
        }
        else
        {
            vars.levelNameStableCount = 0;
        }
    }
    else
    {
        vars.latchedLevelName = "";
        vars.pendingLevelName = "";
        vars.levelNameStableCount = 0;
        vars.lastLatchedLevel = "";
    }

    // --- Post-load grace + reset isFinished on ANY level change (including start) ---
    if (vars.levelJustChanged)
    {
        vars.latchedIsFinished = 0;
        vars.prevLatchedIsFinished = 0;
        vars.finishedHighStableCount = 0;
        vars.finishedLowStableCount = 0;
        vars.loadGraceFrames = vars.LOAD_GRACE_DURATION;
        // If we arrived at a non-start level, we are no longer leaving start
        if (vars.latchedLevelName != "maps/start.bsp")
        {
            vars.leavingStart = false;
        }
    }
    else if (vars.loadGraceFrames > 0)
    {
        vars.loadGraceFrames--;
        if (vars.latchedIsFinished != 0)
        {
            vars.latchedIsFinished = 0;
            vars.finishedHighStableCount = 0;
        }
    }

    // --- Detect ALL in-game timer resets (load start / level restart) ---
    float delta = currentTimer - oldTimer;
    if (oldTimer > 1.0f && currentTimer < 0.5f && vars.loadGraceFrames == 0)
    {
        bool wasOnStart = (vars.latchedLevelName == "maps/start.bsp");
        if (wasOnStart)
        {
            // Timer reset while on start = we are LEAVING start to load another level (or reload start).
            // Block reset until we confirm where we end up.
            vars.leavingStart = true;
            print("[BDD Engine] Timer reset on start hub — load in progress, blocking reset until load completes.");
        }
        else
        {
            print("[BDD Engine] In-game timer reset (level restart), resetting split state.");
        }
        vars.hasSplitThisLevel = false;
        vars.latchedIsFinished = 0;
        vars.prevLatchedIsFinished = 0;
        vars.finishedHighStableCount = 0;
        vars.finishedLowStableCount = 0;
        vars.loadGraceFrames = vars.LOAD_GRACE_DURATION;
    }

    // --- Clear leavingStart when load completes on start (we reloaded start = legitimate reset) ---
    if (vars.leavingStart 
        && vars.latchedLevelName == "maps/start.bsp" 
        && currentTimer > 0f 
        && delta > 0f 
        && delta < 1.0f)
    {
        // IGT is now counting up, load is finished, and we are still on start = map start command executed.
        vars.leavingStart = false;
        vars.latchedIsFinished = 0;
        vars.prevLatchedIsFinished = 0;
        vars.finishedHighStableCount = 0;
        vars.finishedLowStableCount = 0;
        vars.loadGraceFrames = vars.LOAD_GRACE_DURATION;
        print("[BDD Engine] Start hub load completed, reset allowed.");
    }

    // Accumulate IGT
    if (oldTimer > 0 && currentTimer > 0 && vars.latchedIsFinished == 0)
    {
        bool isHubMap = (vars.latchedLevelName == "maps/start.bsp");
        bool blockTimer = (vars.isFleshcancer && isHubMap);

        if (!blockTimer)
        {
            if (delta > 0 && delta < 1.0f)
            {
                vars.totalGameTime += delta;
            }
        }
    }

    return true;
}

start
{
    if (vars.realMapWatcher == null) return false;
    if (vars.inRun) return false;

    string curMap = vars.latchedLevelName;
    
    // Start fires only when IGT is actively running on start (>=0.5s = you have control, load complete)
    if (curMap == "maps/start.bsp" && vars.timerWatcher.Current >= 0.5f)
    {
        vars.totalGameTime = 0f;
        vars.hasSplitThisLevel = false;
        vars.completedLevels.Clear();
        vars.latchedIsFinished = 0;
        vars.prevLatchedIsFinished = 0;
        vars.finishedHighStableCount = 0;
        vars.finishedLowStableCount = 0;
        vars.loadGraceFrames = 0;
        vars.leavingStart = false;
        vars.lastLatchedLevel = curMap;
        vars.inRun = true;
        print("[BDD Engine] Run started! IGT and completed levels reset.");
        return true;
    }
}

split
{
    if (!vars.inRun) return false;
    if (vars.realMapWatcher == null || vars.isFinishedWatcher == null) return false;

    string currentLevel = vars.latchedLevelName;

    if (settings["split_level_end"])
    {
        // --- MODE A: Split on isFinished (level finish screen) ---
        bool finishedRisingEdge = (vars.prevLatchedIsFinished == 0 && vars.latchedIsFinished == 1);

        if (finishedRisingEdge && vars.loadGraceFrames == 0)
        {
            if (!vars.hasSplitThisLevel && currentLevel != "")
            {
                if (!vars.completedLevels.Contains(currentLevel))
                {
                    print("[BDD Engine] Splitting (isFinished)! Level finished: " + currentLevel);
                    vars.completedLevels.Add(currentLevel);
                    vars.hasSplitThisLevel = true; 
                    return true;
                }
                else
                {
                    print("[BDD Engine] Ignored split for " + currentLevel + " (Already completed)");
                }
            }
        }
    }
    else
    {
        // --- MODE B: Split on level change (new map loaded = previous level completed) ---
        if (vars.levelJustChanged)
        {
            if (currentLevel != "" && currentLevel != "maps/start.bsp")
            {
                string levelJustCompleted = vars.lastLatchedLevel;
                string levelToCredit = (levelJustCompleted == "maps/start.bsp") ? "maps/start.bsp" : levelJustCompleted;

                if (!vars.completedLevels.Contains(levelToCredit) && levelToCredit != "")
                {
                    print("[BDD Engine] Splitting (level change)! Completed: " + levelToCredit + " -> " + currentLevel);
                    vars.completedLevels.Add(levelToCredit);
                    vars.hasSplitThisLevel = true;
                    return true;
                }
                else
                {
                    print("[BDD Engine] Ignored split for " + levelToCredit + " (Already completed)");
                }
            }
        }
    }
}

isLoading
{
    return true;
}

gameTime
{
    return TimeSpan.FromSeconds(vars.totalGameTime);
}

reset
{
    if (vars.isFleshcancer) return false;
    if (!vars.inRun) return false;
    if (vars.realMapWatcher == null) return false;
    if (vars.leavingStart) return false; // Never reset while actively loading away from start

    // Reset fires when we are solidly on start.bsp with IGT near 0 (just ran "map start")
    if (vars.latchedLevelName == "maps/start.bsp" 
        && vars.timerWatcher.Current < 0.5f 
        && vars.latchedIsFinished != 1)
    {
        vars.completedLevels.Clear();
        vars.hasSplitThisLevel = false;
        vars.totalGameTime = 0f;
        vars.latchedIsFinished = 0;
        vars.prevLatchedIsFinished = 0;
        vars.finishedHighStableCount = 0;
        vars.finishedLowStableCount = 0;
        vars.loadGraceFrames = 0;
        vars.leavingStart = false;
        vars.inRun = false;
        print("[BDD Engine] Reset detected on start hub, cleared run state.");
        return true;
    }
}
