-- ikemenversion: 1.0
--
-- Trials Mode match launcher. Replaces external/script/default.lua for Trials matches,
-- selected by setting main.luaPath in main.t_itemname.trials, and executed by
-- start.lua's assert(loadFile(path))().
--
-- It exists for one reason. Config.TrainingStage is gated on gameMode('training')
-- inside f_setStage (start.lua:492), and that gate does not extend to new mode names.
-- The stage cannot be forced afterwards either: f_setStage ends by calling
-- selectStage(), so the launchFight hook runs too late, and the per-character
-- start.launchFight.selected hooks never fire for this mode — default.lua calls
-- launchFight{} with no arguments, leaving t.p1char/t.p2char empty, and the remaining
-- call site is gated on main.cpuSide[2], which trials clears.
--
-- Passing `stage` to launchFight sets t.stageAssigned (start.lua:2198), which makes
-- f_setStage use the value verbatim instead of falling through to the P2 character's
-- own stage param or a random pick.

local stage = gameOption('Config.TrainingStage')
if stage ~= '' then
	launchFight{stage = stage}
else
	launchFight{}
end
setMatchNo(-1)
