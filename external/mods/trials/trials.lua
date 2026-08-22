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
	-- loadIni yields a table for a comma-separated value, and searchFile raises on a
	-- non-string argument, so a list-valued key would abort module load outright.
	if type(path) ~= 'string' or path == '' then
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

	-- Config.TrainingStage is likewise gated on gameMode('training') (start.lua:492).
	-- With one configured we skip the stage-select screen and fight.lua passes it to
	-- launchFight; with none, the player picks.
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

	-- Trials runs its own match launcher instead of external/script/default.lua, so
	-- Config.TrainingStage can be passed to launchFight. See fight.lua for why no
	-- hook-based approach works.
	main.luaPath = trials.dir .. 'fight.lua'

	textImgSetText(motif.select_info.title.TextSpriteData, motif.select_info.title.text.trials)
	remapInput(1, getLastInputController())
	remapInput(getLastInputController(), 1)
	setGameMode('trials')
	setHomeTeam(1)
	hook.run("main.t_itemname", t, item)
	return start.f_selectMode
end
end

-- Injects the module's [Common] files for the duration of a Trials match only.
--
-- The engine reads Common.States from sys.cfg at compile time and has no discovery of
-- module config.ini files, so the only way in is to mutate the `common` table the
-- launchFight hook is handed. updateCommon() adds these right after this hook and
-- removes them once the match ends, which is what keeps installing trials free of any
-- save/config.ini edit. Key case matters: updateCommon builds the option name as
-- 'Common.' .. k:gsub('^%l', string.upper), so the key must be lowercase here.
hook.add("launchFight", "trials", function(common, t, data)
	if not gameMode('trials') or type(trials.config.Common) ~= 'table' then
		return
	end
	for section, values in pairs(trials.config.Common) do
		local key = section:lower()
		-- updateCommon looks the key up with gameOption(), which raises on an unknown
		-- name rather than returning nil, so a stray or mistyped key here would kill
		-- the match after character select. Only pass through names the engine defines.
		local known = pcall(gameOption, 'Common.' .. key:gsub('^%l', string.upper))
		if not known then
			print('Trials: ignoring unknown [Common] key in config.ini: ' .. tostring(section))
		else
			if common[key] == nil then
				common[key] = {}
			end
			local existing = {}
			for _, v in ipairs(common[key]) do
				existing[v] = true
			end
			-- loadIni yields a bare string for a single value and a table for a list.
			if type(values) ~= 'table' then
				values = {values}
			end
			for _, v in ipairs(values) do
				if v ~= '' and not existing[v] then
					table.insert(common[key], v)
					existing[v] = true
				end
			end
		end
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
	local ok, err = pcall(function() main.f_printTable({
		dir = trials.dir,
		enabled = trials.enabled,
		config = trials.config,
		system = trials.system,
		menuItemname = systemValue('trials_mode', 'menu', 'itemname', 'trials'),
		-- Which extension points the module actually registered. Cheaper to assert
		-- than to infer from behaviour, and it catches a hook silently not attaching.
		hooks = {
			launchFight = hook.lists['launchFight'] ~= nil
				and hook.lists['launchFight']['trials'] ~= nil,
			launchFightSelected = hook.lists['start.launchFight.selected'] ~= nil
				and hook.lists['start.launchFight.selected']['trials'] ~= nil,
		},
		-- Resolved on disk, so a mistyped path in config.ini shows up here rather
		-- than as a silently absent state file at match start.
		zssPath = normalizePath((trials.config.Common or {}).States or ''),
	}, 'debug/t_trials.txt') end)
	if not ok then
		print('Trials: could not write debug dump (' .. tostring(err) .. ')')
	end
end

trials.f_dumpState()

return trials
