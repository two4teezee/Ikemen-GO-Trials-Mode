-- ikemenversion: 1.0
--;===========================================================
--; TRIALS MODE
--;===========================================================
-- Universal trials module for Ikemen GO.
--
-- All module state lives in the local `trials` table below. Globals are touched only
-- at documented extension points: main.t_itemname.trials, and the loop#trials,
-- start.f_selectScreen, launchFight and main.f_addChar.files hooks. Nothing is
-- installed onto `start` or `menu` — that coupling is what made the previous version
-- unrecoverable across an engine update.
--
-- Configuration model: docs/adr/0001. Dummy namespace: docs/adr/0002.
-- Vocabulary (Trial / Step / Part / Trial Definition / Trials Config): CONTEXT.md

local trials = {}

trials.dir = 'external/mods/trials/'

--;===========================================================
--; PATHS AND CONFIGURATION
--;===========================================================

-- Resolves a path against the module directory, the active motif and data/.
local function normalizePath(path)
	if path == nil or path == '' then
		return ''
	end
	return searchFile(path, {'', trials.dir, motif.def, 'data/'})
end

-- loadIni raises a Lua error on a missing file, which for a module installed by
-- copying a folder means an incomplete copy takes the whole game down with a raw
-- stack trace before the menu ever appears. Degrade with a message naming the file
-- instead: trials then disables itself and the rest of the game still runs.
local function safeLoadIni(path, normalizeSections, keepMeta)
	if path == nil or path == '' then
		return nil, 'no path configured'
	end
	local resolved = normalizePath(path)
	if resolved == '' or not main.f_fileExists(resolved) then
		return nil, 'file not found: ' .. path
	end
	local ok, result = pcall(loadIni, resolved, normalizeSections, keepMeta)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

trials.configPath = trials.dir .. 'config.ini'
trials.enabled = true

local configErr, systemErr
trials.config, configErr = safeLoadIni(trials.configPath, false)
if trials.config == nil then
	print('Trials: cannot read ' .. trials.configPath .. ' (' .. configErr .. '). Mode disabled.')
	trials.enabled = false
	trials.config = {}
end

-- The module's trials-specific motif defaults. Deliberately a different file from
-- +system.def: the engine parses that one and warns per unassignable key, so trials
-- sections there would print a warning per key on every boot. See docs/adr/0001.
local defaultsPath = (trials.config.Files or {}).defaults or (trials.dir .. 'system.def')
trials.system, systemErr = safeLoadIni(defaultsPath, true, true)
if trials.system == nil then
	print('Trials: cannot read ' .. tostring(defaultsPath) .. ' (' .. systemErr .. '). Mode disabled.')
	trials.enabled = false
	trials.system = {}
end

-- Reads a value out of the module's own defaults, tolerating an absent section so a
-- damaged install degrades rather than crashing at load.
local function systemValue(section, ...)
	local cur = trials.system[section]
	for _, key in ipairs({...}) do
		if type(cur) ~= 'table' then
			return nil
		end
		cur = cur[key]
	end
	if type(cur) == 'table' then
		return cur.__value
	end
	return cur
end

--;===========================================================
--; MAIN MENU ENTRY
--;===========================================================
-- Appended at runtime rather than declared in +system.def. The engine concatenates
-- module system.defs *after* the screenpack's, so an itemname declared there would
-- sort to the end of the menu, below EXIT. f_appendItemname returns false when the
-- name already exists, so a screenpack that declares its own menu.itemname.trials
-- keeps full control of both label and position.
-- itemname_order is a flat array of keys, but a screenpack with submenus stores
-- composite keys ('menuwatch_watch') and the engine suppresses the bare leaf, so an
-- anchor like 'watch' exists in the default motif and not in ikemen1. Anchoring on a
-- key that is not there makes f_appendItemname fall through to a plain append, which
-- puts TRIALS below EXIT. Pick the first anchor actually present instead.
local function firstPresentAnchor(menu, candidates)
	local order = menu and menu.itemname_order
	if type(order) ~= 'table' then
		return nil
	end
	local present = {}
	for _, key in ipairs(order) do
		present[key] = true
	end
	for _, candidate in ipairs(candidates) do
		if present[candidate] then
			return candidate
		end
	end
	return nil
end

if trials.enabled then
	main.f_appendItemname(
		motif.title_info.menu,
		'',
		'trials',
		systemValue('trials_mode', 'menu', 'itemname', 'trials') or 'TRIALS',
		firstPresentAnchor(motif.title_info.menu, {'options', 'exit'})
	)
end

--;===========================================================
--; main.lua — GAME MODE REGISTRATION
--;===========================================================
-- main.t_itemname holds one function per game mode, run when the mode is chosen from
-- the title menu. It configures character select and hands off to start.f_selectMode.
if trials.enabled then
main.t_itemname.trials = function(t, item)
	-- Force the training character as the Dummy, matching training mode's convenience.
	if main.t_charDef[gameOption('Config.TrainingChar'):lower()] ~= nil then
		main.forceChar[2] = {main.t_charDef[gameOption('Config.TrainingChar'):lower()]}
	end

	-- The engine hardcodes gameMode('training') when deciding whether P2 is AI-driven
	-- (start.lua:277); that check does not extend to new mode names. Clearing cpuSide
	-- reaches the same setCom(side, 0) through the branch above it.
	main.cpuSide[2] = false

	main.roundTime = -1
	main.selectMenu[2] = true

	-- Config.TrainingStage is likewise gated on gameMode('training') (start.lua:492),
	-- so trials applies it itself in the launchFight hook below.
	if gameOption('Config.TrainingStage') == '' then
		main.stageMenu = true
	end

	-- One character per side. Trials verify against a single player's state.
	main.teamMenu[1].single = true
	main.teamMenu[2].single = true

	-- Endless: a Trials match is never won or lost.
	main.matchWins.draw = {0, 0}
	main.matchWins.simul = {0, 0}
	main.matchWins.single = {0, 0}
	main.matchWins.tag = {0, 0}

	textImgSetText(motif.select_info.title.TextSpriteData, motif.select_info.title.text.trials)
	remapInput(1, getLastInputController())
	remapInput(getLastInputController(), 1)
	setGameMode('trials')
	setHomeTeam(1)
	hook.run("main.t_itemname", t, item)
	return start.f_selectMode
end
end

--;===========================================================
--; start.lua — MATCH LAUNCH
--;===========================================================
-- Config.TrainingStage is gated on gameMode('training') inside f_setStage
-- (start.lua:492), so trials applies it itself.
--
-- This must happen before f_setStage runs, because f_setStage ends by calling
-- selectStage() — by the time the "launchFight" hook fires the stage is already
-- committed, and mutating t.stageNo there does nothing. "start.launchFight.selected"
-- fires at start.lua:2222 for explicitly selected characters, which is the trials
-- path, and setting stageAssigned makes f_setStage use our value verbatim.
hook.add("start.launchFight.selected", "trials", function(side, member, selected, teamData, t)
	if t == nil or not gameMode('trials') then
		return
	end
	-- main.stageMenu is on when no training stage is configured; leave the player's
	-- own choice alone in that case.
	if main.stageMenu then
		return
	end
	local stage = gameOption('Config.TrainingStage')
	if stage ~= '' then
		t.stageNo = start.f_getStageRef(stage)
		t.stageAssigned = true
	end
end)

--;===========================================================
--; DEBUG
--;===========================================================
-- The module's single test seam: one artifact describing its fully resolved state.
-- Every non-visual assertion reads this file. See the umbrella spec for why there is
-- exactly one of these and not one per concern.
--
-- main.f_fileWrite panicErrors when the target directory is missing, which would kill
-- the game rather than skip a debug dump, so the write is guarded.
function trials.f_dumpState()
	if not gameOption('Debug.DumpLuaTables') then
		return
	end
	local ok, err = pcall(main.f_printTable, {
		dir = trials.dir,
		config = trials.config,
		system = trials.system,
		menuItemname = systemValue('trials_mode', 'menu', 'itemname', 'trials'),
	}, 'debug/t_trials.txt')
	if not ok then
		print('Trials: could not write debug dump (' .. tostring(err) .. ')')
	end
end

trials.f_dumpState()

return trials
