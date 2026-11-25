-- IKEMEN GO DOJO MODULE --------------------------------------------------
-- Last tested on Ikemen GO v1.0.0-nightly-20260124 - Jan 24, 2026
-- Module developed by two4teezee
-------------------------------------------------------------------------
-- The Dojo: one external module hosting three game modes on a shared core:
--   Trials           - per-character combo trials (`trials = trials.def`)
--   Game Tutorial    - game-wide lessons (config.ini's SystemTutorial)
--   Character Guides - per-character lessons (`tutorial = tutorial.def`)
-- It features full screenpack integration via config.ini, +system.def,
-- dojo.def. Documentation on writing trials and
-- lessons, and on configuring each mode, is in README.md.
--
-- The shared core keeps the names of the Tutorial Mode module it was merged
-- from (the `tutorial` table, `_iksys_tutorial*` maps, `tutorial*` pause
-- menu itemnames), so the two code bases stay easy to compare. What tells
-- the modes apart is a profile (tutorial.t_profiles below), not the code.
-------------------------------------------------------------------------

--;===========================================================
--; Read Configuration Files
--;===========================================================

local modulePath = "external/mods/dojo/"

-- The Dojo replaces both modules it grew out of. Left installed beside it, either one registers the
-- same main menu items and pause menus, and whichever loads last breaks the other.
for _, old in ipairs({'external/mods/trials/trials.lua', 'external/mods/tutorial/tutorial.lua'}) do
	if main.f_fileExists(old) then
		print('Dojo: ' .. old .. ' is still installed; remove its folder, the Dojo replaces it.')
	end
end

local zss = gameOption("Common.States")
table.insert(zss, modulePath .. "dojo.zss")
modifyGameOption("Common.States", zss)

tutorial = {}

tutorial.configPath = modulePath .. 'config.ini'

local cfgok, cfg = pcall(loadIni, tutorial.configPath, false)
if not cfgok then
	print('Dojo: cannot read ' .. tutorial.configPath .. '. Player preferences will not persist.')
end
tutorial.ini = cfgok and cfg or {}
if type(tutorial.ini.Options) ~= 'table' then tutorial.ini.Options = {} end
if type(tutorial.ini.Config) ~= 'table' then tutorial.ini.Config = {} end
if type(tutorial.ini.Modes) ~= 'table' then tutorial.ini.Modes = {} end

local function f_cfgPath(key)
	local v = tutorial.ini.Config[key]
	if type(v) ~= 'string' then
		return ''
	end
	return (v:gsub('\\', '/'):match('^%s*(.-)%s*$'))
end

--;===========================================================
--; Profiles, tracks and mode switches
--;===========================================================
-- A profile is everything that tells one family of modes apart from the other: the game mode the
-- engine runs (which also picks the [<Gamemode> Pause Menu] section and fires the loop#<gamemode>
-- hook), the look (which sections of dojo.def it reads; the art in dojo.sff / .snd / .air is
-- shared), the player preferences, the save file and the char def key its content comes from. Code shared by every mode reads these through
-- tutorial.profile, which f_useProfile sets on entering a mode.
--   uiSections        - the sections of dojo.def that make up its look, as loadIni names
--                       them, each laid over the one before (see f_prepareUI)
--   optsKey           - prefix of its [Options] keys in config.ini (Trials.Layout, ...)
--   timerKey          - the [Options] key that shows the current trial's / lesson's timer
--   bucket            - the key a character's records are kept under in the save file
--   charKey           - the char def [Files] key naming its per-character file
--   dataField         - where that character's parsed file is kept on its t_selChars entry
--   system            - whether game-wide lessons (SystemTutorial) belong to it
tutorial.t_profiles = {
	trials = {
		id = 'trials',
		label = 'Trials',
		gamemode = 'trials',
		title = 'trials',
		uiSections = {'dojo', 'trials_mode'},
		optsKey = 'Trials',
		timerKey = 'TrialTimer',
		progressPath = 'save/trials.json',
		bucket = 'trials',
		pauseSection = 'trials_pause_menu',
		charKey = 'trials',
		dataField = 'trialsdata',
		dummyKey = 'TrialsDummy',
		stageKey = 'TrialsStage',
		system = false,
	},
	tutorial = {
		id = 'tutorial',
		label = 'Tutorial',
		gamemode = 'tutorial',
		title = 'tutorial',
		uiSections = {'dojo', 'tutorial_mode'},
		optsKey = 'Tutorial',
		timerKey = 'LessonTimer',
		progressPath = 'save/tutorial.json',
		bucket = 'lessons',
		pauseSection = 'tutorial_pause_menu',
		charKey = 'tutorial',
		dataField = 'tutorialdata',
		dummyKey = 'TutorialDummy',
		playerKey = 'TutorialPlayerChar',
		stageKey = 'TutorialStage',
		system = true,
	},
}
-- Fixed iteration order, so load-time messages and builds always come out the same way round.
tutorial.t_profileOrder = {'trials', 'tutorial'}

-- What the mode is serving, set by the main menu item that entered it:
--   trials   - `trials`: the picked character's trials file, from the select screen
--   combined - `combinedtutorial`: game-wide lessons first, then the picked character's own lessons
--   game     - `systemtutorial`: the Game Tutorial - game-wide lessons only, launched straight from a lesson list
--   chars    - `characterguides`: Character Guides - the character's own lessons only
-- key is the track's switch under [Modes] in config.ini. legacy is the standalone Tutorial Mode's
-- itemname for the track, still accepted in a screenpack's menus and [Select Info] titles.
tutorial.t_tracks = {
	trials   = {profile = 'trials',   itemname = 'trials',           key = 'Trials'},
	game     = {profile = 'tutorial', itemname = 'systemtutorial',   key = 'SystemTutorial',   legacy = 'tutorialgame'},
	chars    = {profile = 'tutorial', itemname = 'characterguides',  key = 'CharacterGuides',  legacy = 'tutorialchars'},
	combined = {profile = 'tutorial', itemname = 'combinedtutorial', key = 'CombinedTutorial', legacy = 'tutorial'},
}

-- [Modes] switches each track on or off: 0, false, no or off disables it; anything else, or leaving
-- it out, enables it. A disabled track is hidden from every menu (see the end of this file), and a
-- profile none of whose tracks is on never reads its files.
local function f_switchOn(v)
	if v == nil then
		return true
	end
	local s = tostring(v):lower():match('^%s*(.-)%s*$')
	return not (s == '0' or s == 'false' or s == 'no' or s == 'off')
end
for _, t in pairs(tutorial.t_tracks) do
	t.enabled = f_switchOn(tutorial.ini.Modes[t.key])
	if t.enabled then
		tutorial.t_profiles[t.profile].enabled = true
	end
end

for _, p in pairs(tutorial.t_profiles) do
	if type(tutorial.ini.Options[p.optsKey]) ~= 'table' then tutorial.ini.Options[p.optsKey] = {} end
	p.opts = tutorial.ini.Options[p.optsKey]
	-- [Config] <Mode>Dummy / <Mode>Stage: the counterparts of the engine's Config.TrainingChar and
	-- Config.TrainingStage. Blank leaves the dummy / stage to be picked on the select screen.
	-- TutorialPlayerChar is P1 for the Game Tutorial track; blank lets P1 be picked on the select screen.
	p.dummyPath = f_cfgPath(p.dummyKey)
	p.stagePath = f_cfgPath(p.stageKey)
	p.playerCharPath = p.playerKey ~= nil and f_cfgPath(p.playerKey) or ''
end
-- TrialsChar / TutorialChar are TrialsDummy's / TutorialDummy's old names; a config.ini written
-- before the rename still works.
for _, r in ipairs({{'trials', 'TrialsChar'}, {'tutorial', 'TutorialChar'}}) do
	local p, old = tutorial.t_profiles[r[1]], r[2]
	if p.dummyPath == '' and f_cfgPath(old) ~= '' then
		p.dummyPath = f_cfgPath(old)
		print('Dojo: [Config] ' .. old .. ' has been renamed ' .. p.dummyKey .. '; please update config.ini.')
	end
end

-- The profile in force and its player preferences. f_useProfile swaps both; opts is an upvalue every
-- function below shares, so reassigning it is enough.
local opts = tutorial.t_profiles.trials.opts
tutorial.track = 'trials'
tutorial.profile = tutorial.t_profiles.trials
tutorial.dummyPath = tutorial.profile.dummyPath
tutorial.stagePath = tutorial.profile.stagePath
tutorial.playerCharPath = tutorial.profile.playerCharPath

-- True while the engine is running one of this module's modes (select screen, match, pause menu).
function tutorial.f_inMode()
	for _, id in ipairs(tutorial.t_profileOrder) do
		local p = tutorial.t_profiles[id]
		if p.enabled and gameMode(p.gamemode) then
			return true
		end
	end
	return false
end

-- Persists one Player Preference the moment it changes.
function tutorial.f_savePref(key, value)
	opts[key] = value
	local ok, err = pcall(saveIni, tutorial.ini, tutorial.configPath)
	if not ok then
		print('Dojo: could not write ' .. tutorial.configPath .. ' (' .. tostring(err) .. ').')
	end
end

--;===========================================================
--; Progress
--;===========================================================
tutorial.t_difficulty = {'beginner', 'intermediate', 'advanced', 'expert'}
tutorial.t_menuCats = {'all', 'beginner', 'intermediate', 'advanced', 'expert', 'other'}

-- Each profile has a save file of its own, so Trials progress stays where Trials Mode always kept it.
--   save/trials.json   {version, chars = {[def] = {trials = {[key] = rec}, speedrun = rec}}}
--   save/tutorial.json {version, chars = {[def] = {lessons = {[key] = rec}, speedrun = rec}},
--                       system = {[file] = {lessons = {...}}}, game = {speedrun = rec}}
-- The bucket a character's records sit under (trials / lessons) is the profile's `bucket`.
-- System lessons teach the engine, not a character, so one clear counts for every character.
-- game holds the Game Tutorial's speedrun, which is a run of the game-wide lessons rather than of a character.
local function f_emptyProgress(p)
	p = p or tutorial.profile
	if p.system then
		return {version = 1, chars = {}, system = {}, game = {speedrun = {}}}
	end
	return {version = 1, chars = {}}
end

function tutorial.f_loadProgress(p)
	p = p or tutorial.profile
	-- A missing file is the normal first run, not an error; only a malformed one is worth saying.
	if not main.f_fileExists(p.progressPath) then
		return f_emptyProgress(p)
	end
	local ok, t = pcall(jsonDecode, p.progressPath)
	if not ok or type(t) ~= 'table' or type(t.chars) ~= 'table' then
		print('Dojo: could not read ' .. p.progressPath .. '; starting with no progress.')
		return f_emptyProgress(p)
	end
	t.version = 1
	if p.system then
		if type(t.system) ~= 'table' then t.system = {} end
		if type(t.game) ~= 'table' then t.game = {} end
		if type(t.game.speedrun) ~= 'table' then t.game.speedrun = {} end
	end
	return t
end

-- Loaded per profile when the module builds them (f_buildProfile), and swapped in by f_useProfile.
tutorial.progressPath = tutorial.profile.progressPath
tutorial.progress = f_emptyProgress()

local function f_saveProgress()
	-- jsonEncode(table, path) writes the file and creates the directory. Should a build instead
	-- return the encoded string, write it ourselves rather than losing the player's progress.
	local ok, err = pcall(jsonEncode, tutorial.progress, tutorial.progressPath)
	if ok then
		return
	end
	local ok2, str = pcall(jsonEncode, tutorial.progress)
	if ok2 and type(str) == 'string' then
		main.f_fileWrite(tutorial.progressPath, str)
		return
	end
	print('Dojo: could not write ' .. tutorial.progressPath .. ' (' .. tostring(err) .. ').')
end

function tutorial.f_clearProgress()
	tutorial.progress = f_emptyProgress()
	tutorial.profile.progress = tutorial.progress
	f_saveProgress()
	tutorial.selectDirty = true
end

function tutorial.f_clearCharProgress(ref)
	local key = tutorial.f_charKey(ref)
	if key == nil then
		return false
	end
	tutorial.progress.chars[key] = nil
	f_saveProgress()
	tutorial.selectDirty = true
	return true
end

function tutorial.f_warnKey(why)
	if not tutorial.keyWarned then
		tutorial.keyWarned = true
		print('Dojo: ' .. why .. '; progress will not be recorded.')
	end
end

function tutorial.f_charKey(ref)
	-- Nothing is selected yet while the menus are still being built, so every hop is checked.
	if ref == nil then ref = tutorial.p1selref end
	if ref == nil and type(start.p) == 'table' and type(start.p[1]) == 'table'
		and type(start.p[1].t_selected) == 'table' and start.p[1].t_selected[1] ~= nil then
		ref = start.p[1].t_selected[1].ref
	end
	if ref == nil then
		if not tutorial.charKeyWarned then
			tutorial.charKeyWarned = true
			print('Dojo: no character is selected (p1selref is nil); progress will not be recorded.')
		end
		return nil
	end
	local path = nil
	local ok, res = pcall(getCharFileName, ref)
	if ok and type(res) == 'string' and res ~= '' then
		path = res
	else
		local ok2, data = pcall(start.f_getCharData, ref)
		if ok2 and type(data) == 'table' and type(data.def) == 'string' and data.def ~= '' then
			path = data.def
		end
	end
	if path == nil then
		-- Silence here is what makes a broken key look like a mode that simply never saves, so
		-- say it once rather than dropping every clear from here on without a word.
		if not tutorial.charKeyWarned then
			tutorial.charKeyWarned = true
			print('Dojo: could not resolve the def path for character ref ' .. tostring(ref)
				.. '; progress will not be recorded.')
		end
		return nil
	end
	return path:gsub('\\', '/'):lower()
end

local function f_charProgress(create, ref)
	local key = tutorial.f_charKey(ref)
	if key == nil then
		return nil
	end
	local t = tutorial.progress.chars[key]
	if t == nil then
		if not create then
			return nil
		end
		t = {}
		tutorial.progress.chars[key] = t
	end
	local b = tutorial.profile.bucket
	if type(t[b]) ~= 'table' then t[b] = {} end
	if type(t.speedrun) ~= 'table' then t.speedrun = {} end
	return t
end

local function f_systemProgress(create, file)
	local t = tutorial.progress.system[file]
	if t == nil then
		if not create then
			return nil
		end
		t = {}
		tutorial.progress.system[file] = t
	end
	local b = tutorial.profile.bucket
	if type(t[b]) ~= 'table' then t[b] = {} end
	return t
end

-- The table a lesson's record lives in: its file's for a system lesson, the character's otherwise.
local function f_lessonBucket(lesson, create, ref)
	if lesson.track == 'system' and type(lesson.file) == 'string' then
		return f_systemProgress(create, lesson.file)
	end
	return f_charProgress(create, ref)
end

function tutorial.f_lessonKey(index, arr)
	-- Resolved in explicit steps rather than an and/or chain: this runs on every clear, and a nil
	-- from here drops the record without a word, so it is worth being able to see which step failed.
	if arr == nil and tutorial.data ~= nil then
		arr = tutorial.data.lessons
	end
	if type(arr) ~= 'table' or type(arr[index]) ~= 'table' then
		tutorial.f_warnKey('no lesson at index ' .. tostring(index))
		return nil
	end
	if type(arr[index].key) == 'string' and arr[index].key ~= '' then
		return arr[index].key
	end
	local name = arr[index].name
	if type(name) ~= 'string' or name == '' then
		tutorial.f_warnKey('lesson ' .. tostring(index) .. ' has no name')
		return nil
	end
	local dupe = 0
	for i = 1, index, 1 do
		if type(arr[i]) == 'table' and arr[i].name == name then
			dupe = dupe + 1
		end
	end
	if dupe > 1 then
		return name .. ' #' .. dupe
	end
	return name
end

function tutorial.f_lessonRecord(index, arr, ref)
	if arr == nil and tutorial.data ~= nil then
		arr = tutorial.data.lessons
	end
	local key = tutorial.f_lessonKey(index, arr)
	if key == nil then
		return nil
	end
	local t = f_lessonBucket(arr[index], false, ref)
	if t == nil then
		return nil
	end
	return t[tutorial.profile.bucket][key]
end

function tutorial.f_speedrunRecord()
	if tutorial.track == 'game' then
		return tutorial.progress.game.speedrun
	end
	local t = f_charProgress(false)
	if t == nil then
		return nil
	end
	return t.speedrun
end

function tutorial.f_recordClear(index, ticks)
	local key = tutorial.f_lessonKey(index)
	if key == nil then
		return
	end
	local t = f_lessonBucket(tutorial.data.lessons[index], true)
	if t == nil then
		return
	end
	local b = tutorial.profile.bucket
	local rec = t[b][key]
	if rec == nil then
		rec = {}
		t[b][key] = rec
	end
	rec.cleared = true
	if ticks ~= nil and ticks >= 0 and (rec.besttime == nil or ticks < rec.besttime) then
		rec.besttime = ticks
	end
	f_saveProgress()
end

function tutorial.f_recordSpeedrun(ticks)
	local t = tutorial.track == 'game' and tutorial.progress.game or f_charProgress(true)
	if t == nil then
		return
	end
	t.speedrun.cleared = true
	if ticks ~= nil and ticks >= 0 and (t.speedrun.besttime == nil or ticks < t.speedrun.besttime) then
		t.speedrun.besttime = ticks
	end
	f_saveProgress()
end

motif = loadMotif()

-- The engine already loaded and owns the screenpack's sprites, sounds and fonts; reach for
-- those rather than re-parsing the files (motif.Sff / motif.Snd / motif.Fnt, see src/motif.go).
local sff = motif.Sff
local snd = motif.Snd

-- The Dojo's own art, shared by every mode: dojo.sff, dojo.snd and dojo.air beside this file, each
-- optional. Ship none of a kind and that kind falls back to the screenpack's. f_loadAssets fills
-- these once, when the first profile is built.
--   dojoSff   - sprites for every element of dojo.def
--   dojoSnd   - sounds for every "snd" parameter in dojo.def. Sounds the module reads out of the
--               screenpack's own sections (the pause menu's cursor.*, enter and cancel) always stay
--               on motif.Snd, so the menu answers with whatever the screenpack uses everywhere else.
--   dojoAnims - actions for every "anim" parameter, from three files, each overriding the numbers
--               the one before it declared: the screenpack's own def, dojo.air, and dojo.def itself
--               (where the samples drop anims meant for the modes). Whichever file an action was
--               authored in, f_loadAnimData draws it out of dojoSff, so its sprite numbers refer to
--               dojo.sff wherever the module ships one.
tutorial.uiDef = 'dojo.def'
local dojoSff = sff
local dojoSnd = snd
local dojoAnims = {}
local assetsLoaded = false

local function f_loadAssets()
	if assetsLoaded then
		return
	end
	assetsLoaded = true
	local base = modulePath .. 'dojo'
	if main.f_fileExists(base .. '.sff') then
		dojoSff = sffNew(searchFile(base .. '.sff', {motif.def, '', 'data/'}))
	end
	if main.f_fileExists(base .. '.snd') then
		local ok, s = pcall(sndNew, searchFile(base .. '.snd', {motif.def, '', 'data/'}))
		if ok and s ~= nil then
			dojoSnd = s
		else
			print('Dojo: could not read dojo.snd; sounds will come from the screenpack instead.')
		end
	end
	local loaded = false
	for _, v in ipairs({
		{motif.def, sff},
		{base .. '.air', dojoSff},
		{modulePath .. tutorial.uiDef, dojoSff},
	}) do
		local path, animSff = v[1], v[2]
		local found = path == motif.def
		if not found and main.f_fileExists(path) then
			path, found = searchFile(path, {motif.def, '', 'data/'}), true
		end
		if found then
			local ok, t = pcall(loadAnimTable, path, animSff)
			if ok and type(t) == 'table' then
				loaded = true
				for no, act in pairs(t) do
					dojoAnims[no] = act
				end
			else
				print('Dojo: could not read actions from ' .. tostring(path) .. '.')
			end
		end
	end
	if not loaded then
		print('Dojo: no actions could be read; "anim" parameters will be ignored.')
	end
end

--;===========================================================
--; Local Functions
--;===========================================================
-- Helper function to check if all keys in a combination are pressed
local function f_checkKeyCombo(keyCombo)
	if not keyCombo or keyCombo == "" then
		return false
	end
	
	local keys = {}
	for key in string.gmatch(keyCombo, "([^&]+)") do
		table.insert(keys, key)
	end
	
	for _, key in ipairs(keys) do
		if inputTime(key) <= 0 then
			return false
		end
	end
	
	return #keys > 0
end

local function f_timeConvert(value)
	-- converts ticks to time
	local totalSec = value / 60 --used to be framerate
	local h = tostring(math.floor(totalSec / 3600))
	local m = tostring(math.floor((totalSec / 3600 - h) * 60))
	local s = tostring(math.floor(((totalSec / 3600 - h) * 60 - m) * 60))
	local x = tostring(math.floor((((totalSec / 3600 - h) * 60 - m) * 60 - s) *100))
	if string.len(m) < 2 then
		m = 0 .. m
	end
	if string.len(s) < 2 then
		s = 0 .. s
	end
	if string.len(x) < 2 then
		x = 0 .. x
	end
	return m, s, x
end

local function f_trimforchar(line, char, when)
	-- trims a string before or after a specified character.
	-- also trims leading and trailing whitespace
	local x = string.find(line, char)
	if x ~= nil then
		if when == "after" then
			line = string.sub(line, x+1, #line)
		elseif when == "before" then
			line = string.sub(line, 1, x-1)
		end
		line = string.gsub(line, '^%s*(.-)%s*$', '%1')
		line = string.gsub(line, '[ \t]+%f[\r\n%z]', '')
	else
		line = ""
	end
	return line
end

local function f_str2boolean(str)
	-- converts a table of "true" and "false" strings to bool
    local bool = {}
	for x = 1, #str, 1 do
		if string.lower(str[x]) == "true" then
			bool[x] = true
		else
			bool[x] = false
		end
	end
    return bool
end

local function f_str2number(str)
	-- converts a table of strings to numbers
    local array = {}
	for x = 1, #str, 1 do
		array[x] = tonumber(str[x])
	end
    return array
end

local function f_collectCompatKeys(node, path, aliases)
	if type(node) ~= 'table' then
		if #path > 0 then
			aliases[table.concat(path, '.')] = node
			aliases[table.concat(path, '_')] = node
		end
		return
	end
	local hasStringKeys = false
	for k in pairs(node) do
		if type(k) == 'string' then
			hasStringKeys = true
			break
		end
	end
	if not hasStringKeys then
		if #path > 0 then
			aliases[table.concat(path, '.')] = node
			aliases[table.concat(path, '_')] = node
		end
		return
	end
	for k, v in pairs(node) do
		if type(k) == 'string' then
			path[#path + 1] = k
			f_collectCompatKeys(v, path, aliases)
			path[#path] = nil
		end
	end
end

local function f_buildCompatConfig(root)
	if type(root) ~= 'table' then
		return root
	end
	local aliases = {}
	f_collectCompatKeys(root, {}, aliases)
	for k, v in pairs(aliases) do
		if root[k] == nil then
			root[k] = v
		end
	end
	return root
end

-- dojo.def is written with mode-neutral key names (title, steps, counter, menu, ...). The core reads
-- one set of names, so those - and the older spellings, Trials Mode's trialtitle, trialcounter,
-- trialsmenu, ... - are moved onto it before anything else looks at a section. A key already spelled
-- the core's way wins, and the first spelling listed below wins over the ones after it, so a section
-- may use any of them (a trialsmode.def from Trials Mode 1.x, or a [Tutorial Mode] copied out of the
-- old tutorialmode.def, still works).
--   {from, to} at the top of the section, or {parent, from, to} one level down.
tutorial.t_uiAliases = {
	{'localcoord', 'tutoriallocalcoord'},
	{'trialslocalcoord', 'tutoriallocalcoord'},
	{'listdisplay', 'tutoriallistdisplay'},
	{'trialslistdisplay', 'tutoriallistdisplay'},
	{'title', 'lessontitle'},
	{'trialtitle', 'lessontitle'},
	{'steps', 'lessonsteps'},
	{'trialsteps', 'lessonsteps'},
	{'counter', 'lessoncounter'},
	{'trialcounter', 'lessoncounter'},
	{'totaltimer', 'totallessontimer'},
	{'totaltrialtimer', 'totallessontimer'},
	{'currenttimer', 'currentlessontimer'},
	{'currenttrialtimer', 'currentlessontimer'},
	{'reset', 'lessonreset'},
	{'trialreset', 'lessonreset'},
	{'menu', 'tutorialmenu'},
	{'trialsmenu', 'tutorialmenu'},
	{'lessoncounter', 'nodata', 'notutorialdata'},
	{'lessoncounter', 'notrialsdata', 'notutorialdata'},
}

local function f_aliasUI(root, aliases)
	for _, a in ipairs(aliases or {}) do
		local t, from, to = root, a[1], a[2]
		if #a == 3 then
			t, from, to = root[a[1]], a[2], a[3]
		end
		if type(t) == 'table' and t[from] ~= nil then
			if t[to] == nil then
				t[to] = t[from]
			end
			t[from] = nil
		end
	end
	return root
end

-- Lays one section over another. A list value (pos = 1,2) replaces the base's whole, a block
-- (lessontitle.vertical) is merged key by key, so an override section only needs the keys it changes.
local function f_isList(t)
	return type(t) == 'table' and t[1] ~= nil
end
local function f_overlayUI(base, over)
	for k, v in pairs(over) do
		if type(v) == 'table' and not f_isList(v) and type(base[k]) == 'table' and not f_isList(base[k]) then
			f_overlayUI(base[k], v)
		else
			base[k] = v
		end
	end
	return base
end

-- Builds a profile's UI root out of dojo.def and settles what the rest of the build relies on.
-- [Dojo] is the look every mode shares; the profile's own section ([Trials Mode] / [Tutorial Mode])
-- is laid over it with that mode's differences (only its labels, in the shipped file). A def with no
-- [Dojo] section - a trialsmode.def from Trials Mode 1.x, renamed - uses its [Trials Mode] as the
-- shared base instead, which is the look it always gave every mode. The def is read afresh for each profile, because the
-- build hangs each profile's own anims and text objects off its root.
-- The player preferences in config.ini's [Options] are the single source of truth for the
-- behavioural defaults: the shipped file carries the defaults and the pause menu rewrites it as the
-- player changes them. The def carries no layout / reset-on-success default - it only styles.
local function f_prepareUI(p)
	local path = modulePath .. tutorial.uiDef
	local ok, ini = pcall(loadIni, path)
	if not ok or type(ini) ~= 'table' then
		print('Dojo: could not read ' .. path .. '; the ' .. p.label .. ' UI falls back to defaults.')
		ini = {}
	end
	local sections = p.uiSections
	if type(ini[sections[1]]) ~= 'table' and type(ini.trials_mode) == 'table' then
		sections = {'trials_mode'}
		for i = 2, #p.uiSections do
			if p.uiSections[i] ~= 'trials_mode' then
				table.insert(sections, p.uiSections[i])
			end
		end
	end
	local root = {}
	for i, sec in ipairs(sections) do
		if type(ini[sec]) == 'table' then
			f_overlayUI(root, f_aliasUI(ini[sec], tutorial.t_uiAliases))
		elseif i == 1 then
			print('Dojo: ' .. path .. ' has no [' .. sec:gsub('_', ' ') .. '] section; the ' .. p.label .. ' UI falls back to defaults.')
		end
	end
	root = f_buildCompatConfig(root)
	local o = p.opts
	root.tutoriallayout = tostring(o.Layout):lower() == 'horizontal' and 'horizontal' or 'vertical'
	root.tutorialresetonsuccess = o.ResetOnSuccess == true
	if type(root.textbox) ~= 'table' then root.textbox = {} end
	if o.Textboxes ~= nil then
		local visible = tostring(o.Textboxes):lower() ~= 'hide'
		root.textbox_visible = visible
		root.textbox.visible = visible
	end
	if type(root.tutoriallocalcoord) ~= 'table' then
		root.tutoriallocalcoord = {320, 240}
	end
	local lx = tonumber(root.tutoriallocalcoord[1]) or 320
	local ly = tonumber(root.tutoriallocalcoord[2]) or 240
	root.tutoriallocalcoord = {lx, ly}
	return root, lx, ly
end

-- Until a profile is built (f_buildProfile, at the end of this file) the canvas is a plain default.
tutorial.tutorial_mode = {}
tutorial.mtlcx = 320
tutorial.mtlcy = 240

--;===========================================================
--; Aspect ratio
--;===========================================================
-- The UI is authored on a tutoriallocalcoord canvas, but the screen it lands on is whatever aspect
-- the match is running at. With Video.FightAspectWidth/Height set to -1 ("stage"), that is the
-- stage's own aspect, and it changes from stage to stage.
--
-- The engine's animSetLocalcoord/textImgSetLocalcoord/rectSetLocalcoord derive both their scale and
-- their x offset from the localcoord handed to them and never look at the live game width (see
-- anim.go SetLocalcoord, font.go SetLocalcoord, rect.go SetLocalcoord). Passing the authored
-- 1280,720 therefore always maps the canvas to a 16:9 band and lets the renderer centre it, so on a
-- 4:3 stage the band is wider than the screen and hangs off both edges.
--
-- screenWidth()/screenHeight() are the engine's live sys.gameWidth/gameHeight, which already carry
-- the applied fight aspect. Expressed in authored units the screen is
--     vislcx = mtlcy * screenWidth() / screenHeight()
-- wide. Handing (vislcx, mtlcy) to the setters leaves the authored scale untouched - they take it
-- from the 4:3 core height, which vislcx does not move - while pinning authored x=0 to the real
-- left screen edge and x=vislcx to the real right one. Elements are then moved to their own side of
-- that canvas by their anchor, so a UI authored at 16:9 still reads as designed at 4:3: same text
-- size, edges where the edges actually are.
--
-- When aspects match, vislcx == mtlcx and every number below is the authored one.
tutorial.vislcx = tutorial.mtlcx
tutorial.anchordelta = 0

-- The live game aspect, or the authored one while the engine cannot answer yet.
local function f_screenAspect()
	if type(screenWidth) ~= 'function' or type(screenHeight) ~= 'function' then
		return tutorial.mtlcx / tutorial.mtlcy
	end
	local ok, w, h = pcall(function() return screenWidth(), screenHeight() end)
	if not ok or type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 then
		return tutorial.mtlcx / tutorial.mtlcy
	end
	return w / h
end

-- The visible canvas width for an aspect, in authored units. Clamped at 4:3 because the setters cap
-- their scale there (v = min(lx, ly*4/3)): below it the engine cannot place a localcoord without
-- changing its scale, and no stage in practice is narrower than 4:3 anyway.
local function f_vislcx(aspect)
	return math.max(tutorial.mtlcy * 4 / 3, tutorial.mtlcy * aspect)
end

-- The localcoord every tutorial element is drawn in. Always use this in place of mtlcx,mtlcy when
-- calling into the engine's *SetLocalcoord.
function tutorial.f_localcoord()
	return tutorial.vislcx, tutorial.mtlcy
end

-- Font metrics, memoized per font index. motif.Fnt is the engine's loaded font map.
local t_fontDef = {}
local function f_fontDef(n)
	if n == nil or n == -1 then return nil end
	if t_fontDef[n] == nil and motif.Fnt[n] ~= nil then
		t_fontDef[n] = fontGetDef(motif.Fnt[n])
	end
	return t_fontDef[n]
end

-- Legacy MUGEN nudge: left-aligned text sits one pixel further right than the engine places it.
local function f_alignOffset(align)
	if align == -1 then
		return 1
	end
	return 0
end

local text = {}

local function f_newText(node)
	local node = type(node) == 'table' and node or {}
	local font = type(node.font) == 'table' and node.font or {-1}
	local offset = type(node.pos) == 'table' and node.pos or (type(node.offset) == 'table' and node.offset or {0, 0})
	local scale = type(node.scale) == 'table' and node.scale or {1, 1}
	return text:create({
		font =   font[1],
		bank =   font[2],
		align =  font[3],
		text =   node.text,
		x =      offset[1] or 0,
		y =      offset[2] or 0,
		scaleX = scale[1] or 1,
		scaleY = scale[2] or 1,
		r =      font[4],
		g =      font[5],
		b =      font[6],
		a =      font[7],
		xshear = node.xshear or 0,
		angle  = node.angle or 0,
		layerno = node.layerno,
	})
end

local function f_clampLayerno(...)
	for i = 1, select('#', ...) do
		local n = tonumber(select(i, ...))
		if n ~= nil then
			n = math.floor(n)
			if n < -1 then n = -1 elseif n > 2 then n = 2 end
			return n
		end
	end
	return 0
end

--create text
function text:create(t)
	local t = t or {}
	t.font = t.font or -1
	t.bank = t.bank or 0
	t.align = t.align or 0
	t.text = t.text or ''
	t.x = t.x
	t.y = t.y
	if t.pos ~= nil then
	t.x = t.pos[1]
	t.y = t.pos[2]
	end
	t.scaleX = t.scaleX or 1
	t.scaleY = t.scaleY or 1
	if t.scale ~= nil then
	t.scaleX = t.scale[1] or 1
	t.scaleY = t.scale[2] or 1
	end
	t.r = t.r or 255
	t.g = t.g or 255
	t.b = t.b or 255
	t.a = t.a or 255
	t.height = t.height or -1
	if t.window == nil then t.window = {
	0,0,0,0} end
	t.xshear = t.xshear or 0
	t.angle = t.angle or 0
		if t.ti == nil then
	t.ti = textImgNew()
		end
	setmetatable(t, self)
	self.__index = self
	if t.font ~= -1 and motif.Fnt[t.font] ~= nil then
		textImgSetFont(t.ti, motif.Fnt[t.font])
	end
	-- Setter order follows the engine's own SetTextSprite (src/iniutils.go): localcoord first,
	-- because it only stores a scale factor and does not re-derive values already committed.
		textImgSetLocalcoord(t.ti, tutorial.f_localcoord())
	textImgSetBank(t.ti, t.bank)
	textImgSetAlign(t.ti, t.align)
	textImgSetText(t.ti, t.text)
	textImgSetColor(t.ti, t.r, t.g, t.b, t.a)
	textImgSetPos(t.ti, t.x + f_alignOffset(t.align), t.y)
	textImgSetScale(t.ti, t.scaleX, t.scaleY)
	textImgSetWindow(t.ti, t.window[1], t.window[2], t.window[3] - t.window[1], t.window[4] - t.window[2])
	textImgSetLayerno(t.ti, f_clampLayerno(t.layerno))
	textImgSetXShear(t.ti, t.xshear)
	textImgSetAngle(t.ti, t.angle)
	return t
end

text.new = text.create

--update text
function text:update(t)
	if type(t) == "table" then
		local ok = false
		local fontChange = false
		for k, v in pairs(t) do
			if self[k] ~= v then
				if k == 'font' or k == 'height' then
					fontChange = true
				end
				self[k] = v
				ok = true
			end
		end
		if not ok then return end
		if fontChange and self.font ~= -1 and motif.Fnt[self.font] ~= nil then
			textImgSetFont(self.ti, motif.Fnt[self.font])
		end
		textImgSetLocalcoord(self.ti, tutorial.f_localcoord())
		textImgSetBank(self.ti, self.bank)
		textImgSetAlign(self.ti, self.align)
		textImgSetText(self.ti, self.text)
		textImgSetColor(self.ti, self.r, self.g, self.b, self.a)
		textImgSetPos(self.ti, self.x + f_alignOffset(self.align), self.y)
		textImgSetScale(self.ti, self.scaleX, self.scaleY)
		textImgSetWindow(self.ti, self.window[1], self.window[2], self.window[3] - self.window[1], self.window[4] - self.window[2])
		textImgSetXShear(self.ti, self.xshear)
		textImgSetAngle(self.ti, self.angle)
	else
		self.text = t
		textImgSetLocalcoord(self.ti, tutorial.f_localcoord())
		textImgSetText(self.ti, self.text)
	end

	return self
end

-- Re-commit everything the text was built with, in create's order. :update short-circuits when no
-- field changed, so it cannot carry a new localcoord or a moved origin on its own - this is what
-- a relayout calls after the aspect, and with it the canvas the text sits in, has changed.
function text:relayout(x, y)
	if x ~= nil then self.x = x end
	if y ~= nil then self.y = y end
	textImgSetLocalcoord(self.ti, tutorial.f_localcoord())
	textImgSetPos(self.ti, self.x + f_alignOffset(self.align), self.y)
	textImgSetScale(self.ti, self.scaleX, self.scaleY)
	textImgSetWindow(self.ti, self.window[1], self.window[2], self.window[3] - self.window[1], self.window[4] - self.window[2])
	return self
end

--draw text
function text:draw()
	if self.font == -1 then return end
		textImgDraw(self.ti)
	return self
end

-- Commits an anim's placement from its config node and an origin. Split out of f_loadAnimData so a
-- relayout can put an already-built anim back down in the new canvas without rebuilding its
-- sprites. Localcoord goes on first: animSetPos and animSetScale both divide by the scale it
-- stores, so they have to see the current one. animSetPos also rewrites the anim's reset baseline,
-- which is what keeps the animReset calls in the draw loop honest afterwards.
local function f_placeAnim(a, node, x, y)
	local offset = type(node.offset) == 'table' and node.offset or {0, 0}
	local scale = type(node.scale) == 'table' and node.scale or {1.0, 1.0}
	animSetLocalcoord(a, tutorial.f_localcoord())
	animSetPos(a, offset[1] + (x or 0), offset[2] + (y or 0))
	animSetScale(a, scale[1], scale[2])
	animSetFacing(a, node.facing or 1)
	animSetWindow(a, 0, 0, tutorial.vislcx, tutorial.mtlcy)
	animSetLayerno(a, f_clampLayerno(node.layerno))
	animUpdate(a)
	return a
end

local function f_loadAnimData(node, x, y, sffOverride, animsOverride)
	local node = type(node) == 'table' and node or {}
	local sprData = sffOverride or dojoSff
	local animData = animsOverride or dojoAnims
	local offset = type(node.offset) == 'table' and node.offset or {0, 0}
	local scale = type(node.scale) == 'table' and node.scale or {1.0, 1.0}
	local spr = node.spr
	if type(spr) == 'string' then
		if spr == '' then
			spr = nil
		else
			spr = {tonumber(spr:match('^([0-9]+)')), 0}
		end
	elseif type(spr) == 'table' and #spr == 1 then
		if type(spr[1]) == 'string' then
			spr = {tonumber(spr[1]:match('^([0-9]+)')), 0}
		else
			spr = {spr[1], 0}
		end
	end
	local a
	if type(node.anim) == 'number' and node.anim >= 0 and animData[node.anim] ~= nil then
		a = animNew(sprData, animData[node.anim])
	elseif type(spr) == 'table' and #spr > 0 then
		a = animNew(sprData, spr[1] .. ', ' .. spr[2] .. ', 0, 0, -1')
	else
		a = animNew(sprData, '-1,0, 0,0, -1')
	end
	f_placeAnim(a, node, x, y)
	return a
end

local t_glyphAnims = {}
local glyphSffOk = nil
local function f_glyphAnim(sub, key)
	local g = motif.glyphs[key]
	if g == nil then
		return nil
	end
	if type(g.Spr) ~= 'table' or tonumber(g.Spr[1]) == nil or tonumber(g.Spr[1]) < 0 then
		return g.AnimData
	end
	if glyphSffOk == nil then
		-- Only commit to private anims once the motif's glyph sff has been confirmed to reach us
		-- as usable sprite data. An empty one would draw nothing at all, which is a far worse
		-- outcome than a glyph that cannot hold a palfx of its own.
		local ok, info = pcall(function()
			return animGetSpriteInfo(animNew(motif.GlyphsSff, g.Spr[1] .. ', ' .. g.Spr[2] .. ', 0, 0, -1'), g.Spr[1], g.Spr[2])
		end)
		glyphSffOk = ok and info ~= nil
		if not glyphSffOk then
			print('Dojo: motif glyph sprites are unreadable; step palfx will not apply to glyphs.')
		end
	end
	if not glyphSffOk then
		return g.AnimData
	end
	local id = sub .. '|' .. key
	if t_glyphAnims[id] == nil then
		t_glyphAnims[id] = animNew(motif.GlyphsSff, g.Spr[1] .. ', ' .. g.Spr[2] .. ', 0, 0, -1')
	end
	return t_glyphAnims[id]
end

--;===========================================================
--; main.lua
--;===========================================================
-- The ref of a character named in config.ini or a lesson file, adding it to the roster the way the
-- engine adds a TrainingChar that select.def leaves out: excluded, so it never turns up as a random
-- pick or an arcade opponent. Mods load after the roster is built, so this happens on entering the
-- mode rather than at load. nil when path is blank or the character cannot be loaded.
local function f_charRefFor(path, what)
	if path == nil or path == '' then
		return nil
	end
	local key = path:lower()
	if main.t_charDef[key] == nil then
		main.f_addChar(path .. ', order = 0, ordersurvival = 0, exclude = 1', true, false)
	end
	if main.t_charDef[key] == nil then
		print('Dojo: ' .. what .. ' (' .. path .. ') could not be loaded.')
	end
	return main.t_charDef[key]
end
tutorial.f_charRefFor = f_charRefFor

-- Resolves every character the Game Tutorial can force onto P1: [Config] TutorialPlayerChar, and each
-- game-wide lesson's lesson.playerchar. Done on entering the track, for the reason above.
local function f_resolvePlayerChars()
	tutorial.playerRef = f_charRefFor(tutorial.playerCharPath, 'TutorialPlayerChar')
	if tutorial.playerRef == nil then
		tutorial.playerCharPath = ''
		tutorial.profile.playerCharPath = ''
	end
	for _, l in ipairs(tutorial.systemLessons) do
		if l.playerchar ~= nil and l.playerref == nil and not l.playercharFailed then
			l.playerref = f_charRefFor(l.playerchar, 'lesson.playerchar of "' .. l.name .. '"')
			l.playercharFailed = l.playerref == nil
		end
	end
end

-- The select screen's title: [Select Info] title.<itemname>.text for the track (title.trials.text,
-- title.systemtutorial.text, title.characterguides.text, title.combinedtutorial.text), then its
-- legacy itemname's, falling back to the profile's own (title.tutorial.text for every tutorial
-- track), then its label.
local function f_selectTitle(track)
	local t = motif.select_info.title.text or {}
	local tr = tutorial.t_tracks[track]
	for _, k in ipairs({tr.itemname, tr.legacy or tr.itemname, tutorial.profile.title}) do
		if type(t[k]) == 'string' and t[k] ~= '' then
			return t[k]
		end
	end
	return tutorial.profile.label
end

-- Settings every track shares: an endless, single-character match against a dummy. Entering a track
-- puts its profile in force first, so everything below reads that profile's config and look.
local function f_setupMode(track)
	tutorial.f_useProfile(tutorial.t_profiles[tutorial.t_tracks[track].profile])
	tutorial.track = track
	--main.lifebar.p1score = true
	--main.lifebar.p2ailevel = true
	main.motif.dialogue = false
	main.roundTime = -1
	if tutorial.stagePath == '' then
		main.stageMenu = true
	end
	main.teamMenu[1].ratio = false
	main.teamMenu[1].simul = false
	main.teamMenu[1].single = true
	main.teamMenu[1].tag = false
	main.teamMenu[1].turns = false
	main.teamMenu[2].single = true
	main.matchWins.draw = {0, 0}
	main.matchWins.simul = {0, 0}
	main.matchWins.single = {0, 0}
	main.matchWins.tag = {0, 0}
	textImgSetText(motif.select_info.title.TextSpriteData, f_selectTitle(track))
	remapInput(1, getLastInputController())
	remapInput(getLastInputController(), 1)
	setGameMode(tutorial.profile.gamemode)
	setHomeTeam(1)
end

-- Trials, Combined and Character Guides: the select screen picks P1, and P2 unless the profile's
-- TrialsDummy / TutorialDummy forces one.
local function f_selectScreenTrack(track)
	f_setupMode(track)
	tutorial.dummyRef = f_charRefFor(tutorial.dummyPath, tutorial.profile.dummyKey)
	if tutorial.dummyRef ~= nil then
		main.forceChar[2] = {tutorial.dummyRef}
	end
	main.selectMenu[2] = true
	hook.run("main.t_itemname")
	return start.f_selectMode
end

-- Main menu entries, one per track. Registered under each track's itemname at the end of this file,
-- and only while the track is switched on in [Modes].
tutorial.t_tracks.trials.start = function()
	return f_selectScreenTrack('trials')
end

tutorial.t_tracks.combined.start = function()
	return f_selectScreenTrack('combined')
end

tutorial.t_tracks.chars.start = function()
	return f_selectScreenTrack('chars')
end

-- Game Tutorial. Story mode's route past the select screen: with no select menu on either side the
-- engine goes straight to main.luaPath, and gametutorial.lua's lesson list launches each match
-- itself. Whatever config.ini leaves blank is picked on the select screen first instead - P1 when
-- there is no TutorialPlayerChar, the dummy and the stage likewise - and the lesson list follows it.
tutorial.t_tracks.game.start = function()
	f_setupMode('game')
	f_resolvePlayerChars()
	tutorial.dummyRef = f_charRefFor(tutorial.dummyPath, 'TutorialDummy')
	main.selectMenu[1] = tutorial.playerRef == nil
	if main.selectMenu[1] then
		if tutorial.dummyRef ~= nil then
			main.forceChar[2] = {tutorial.dummyRef}
		end
		main.selectMenu[2] = true
	else
		main.selectMenu[2] = false
		-- No select screen means no stage select either; a blank TutorialStage is the engine's pick.
		main.stageMenu = false
	end
	main.luaPath = modulePath .. 'gametutorial.lua'
	hook.run("main.t_itemname")
	return start.f_selectMode
end

-- The profile in force's UI section. Reassigned by f_useProfile; every function below shares it.
local tr_pos = tutorial.tutorial_mode

-- Walks to a dojo.def node, creating empty tables for any level a screenpack left out, so
-- every element the drawer reaches for ends up with at least a blank anim.
local function f_node(t, ...)
	local node = t
	for i = 1, select('#', ...) do
		local k = select(i, ...)
		if type(node[k]) ~= 'table' then node[k] = {} end
		node = node[k]
	end
	return node
end

-- The categories tutorialmenu.item / .header can restyle: the difficulty tiers, all and other,
-- plus any chapter id the def declares a block for (tutorialmenu.item.movement.text.font = ...).
local t_menuStructural = {text = true, bg = true, active = true, selected = true, locked = true,
	overlay = true, value = true, spacing = true, offset = true}
local function f_menuCats(m)
	local t, seen = {}, {}
	for _, c in ipairs(tutorial.t_menuCats) do t[#t + 1] = c; seen[c] = true end
	for _, group in ipairs({'item', 'header'}) do
		if type(m[group]) == 'table' then
			for k, v in pairs(m[group]) do
				if type(k) == 'string' and type(v) == 'table' and not t_menuStructural[k] and not seen[k] then
					t[#t + 1] = k; seen[k] = true
				end
			end
		end
	end
	return t
end

--;===========================================================
--; UI build
--;===========================================================
-- Everything from here to f_uiMenuDraw runs once per profile, from f_buildProfile at the end of this
-- file, with that profile's UI section in tr_pos and its canvas in mtlcx / mtlcy.

-- The Lesson select menu block is newer than the rest of the UI defs, so fill in anything a def
-- predating it would not have declared. Everything else here is authored in the def.
local function f_uiMenuDefaults()
	local m = f_node(tr_pos, 'tutorialmenu')
	if type(m.pos) ~= 'table' then m.pos = {0, 0} end
	if type(m.spacing) ~= 'table' then m.spacing = {0, 20} end
	m.visibleitems = math.max(1, tonumber(m.visibleitems) or 10)
	m.layerno = tonumber(m.layerno) or 2
	m.headerdisplay = tostring(m.headerdisplay or 'default'):lower()
	if m.headerdisplay ~= 'sidebyside' then m.headerdisplay = 'default' end
	if type(f_node(m, 'header').spacing) ~= 'table' then m.header.spacing = {120, 0} end	if f_node(m, 'header', 'value').text == nil then m.header.value.text = '%s' end
	for _, key in ipairs({'text', 'value', 'bg'}) do
		local base, act = f_node(m, 'header', key), f_node(m, 'header', 'active', key)
		for k, v in pairs(base) do
			if act[k] == nil then act[k] = v end
		end
	end
	-- Rows a gated file has not opened yet (tutorial.gated) inherit the plain row unless restyled.
	do
		local base, lk = f_node(m, 'item', 'text'), f_node(m, 'item', 'locked', 'text')
		for k, v in pairs(base) do
			if lk[k] == nil then lk[k] = v end
		end
	end
	for _, path in ipairs({
		{'bg'}, {'front'}, {'cursor'}, {'header'}, {'header', 'bg'}, {'header', 'active', 'bg'},
		{'item', 'bg'}, {'item', 'active', 'bg'},
		{'status', 'cleared'}, {'status', 'uncleared'}, {'status', 'locked'}, {'arrow', 'up'}, {'arrow', 'down'},
	}) do
		local n = f_node(m, unpack(path))
		if type(n.offset) ~= 'table' then n.offset = {0, 0} end
		if n.layerno == nil then n.layerno = m.layerno end
	end
	for _, path in ipairs({
		{'title'}, {'besttime'}, {'header', 'text'}, {'header', 'value'},
		{'header', 'active', 'text'}, {'header', 'active', 'value'},
		{'item', 'text'}, {'item', 'active', 'text'}, {'item', 'selected', 'text'}, {'item', 'locked', 'text'},
		{'status', 'cleared'}, {'status', 'uncleared'}, {'status', 'locked'}, {'arrow', 'up'}, {'arrow', 'down'},
	}) do
		local n = f_node(m, unpack(path))
		if type(n.offset) ~= 'table' then n.offset = {0, 0} end
		if type(n.font) ~= 'table' then n.font = {-1} end
		if type(n.scale) ~= 'table' then n.scale = {1, 1} end
		if n.text == nil then n.text = '' end
		if n.layerno == nil then n.layerno = m.layerno end
	end
	if type(f_node(m, 'status').offset) ~= 'table' then m.status.offset = {0, 0} end
	-- The active row's own overlay: the same kind of rect as tutorialmenu.overlay, but drawn under one
	-- row rather than the whole menu, so it travels with the cursor. Its window is x1,y1,x2,y2 taken
	-- from the row's origin. A zero-size window draws nothing, which is what a def predating this
	-- element leaves behind.
	do
		local ro = f_node(m, 'item', 'active', 'overlay')
		if type(ro.window) ~= 'table' then ro.window = {0, 0, 0, 0} end
		if type(ro.col) ~= 'table' then ro.col = {255, 255, 255} end
		if type(ro.alpha) ~= 'table' then ro.alpha = {32, 255} end
		if ro.visible == nil then ro.visible = true end
		ro.layerno = tonumber(ro.layerno) or m.layerno
	end
	for _, cat in ipairs(f_menuCats(m)) do
		for _, path in ipairs({
			{'item', 'text'}, {'item', 'bg'},
			{'item', 'active', 'text'}, {'item', 'active', 'bg'}, {'item', 'active', 'overlay'},
			{'item', 'selected', 'text'},
			{'header', 'text'}, {'header', 'value'}, {'header', 'bg'},
			{'header', 'active', 'text'}, {'header', 'active', 'value'}, {'header', 'active', 'bg'},
		}) do
			local group = path[1]
			local rest = {}
			for i = 2, #path, 1 do rest[#rest + 1] = path[i] end
			local declared = m[group] ~= nil and m[group][cat] or nil
			for _, k in ipairs(rest) do
				declared = type(declared) == 'table' and declared[k] or nil
			end
			if type(declared) == 'table' then
				local base = f_node(m, unpack(path))
				for k, v in pairs(base) do
					if declared[k] == nil then declared[k] = v end
				end
			end
		end
	end
	local o = f_node(m, 'overlay')
	if type(o.window) ~= 'table' then o.window = {0, 0, tutorial.mtlcx, tutorial.mtlcy} end
	if type(o.col) ~= 'table' then o.col = {0, 0, 0} end
	if type(o.alpha) ~= 'table' then o.alpha = {0, 128} end
	o.layerno = tonumber(o.layerno) or 0
end

local function f_palfxDefaults(fx)
	if type(fx.add) ~= 'table' then fx.add = {0, 0, 0} end
	if type(fx.mul) ~= 'table' then fx.mul = {256, 256, 256} end
	if type(fx.sinadd) ~= 'table' then fx.sinadd = {0, 0, 0, 0} end
	fx.invertall = tonumber(fx.invertall) or 0
	fx.color = tonumber(fx.color) or 256
	return fx
end
local function f_uiStepDefaults()
for _, sub in ipairs({'upcomingstep', 'currentstep', 'completedstep'}) do
	for _, layout in ipairs({'vertical', 'horizontal'}) do
		f_palfxDefaults(f_node(tr_pos, sub, layout, 'bg', 'palfx'))
		f_palfxDefaults(f_node(tr_pos, sub, layout, 'glyphs', 'palfx'))
		local paths = {{'bg'}}
		if layout == 'horizontal' then paths = {{'bg'}, {'bg', 'tail'}, {'bg', 'head'}} end
		for _, path in ipairs(paths) do
			local n = f_node(tr_pos, sub, layout, unpack(path))
			if type(n.offset) ~= 'table' then n.offset = {0, 0} end
			if type(n.scale) ~= 'table' then n.scale = {1, 1} end
			n.offset[1] = tonumber(n.offset[1]) or 0
			n.offset[2] = tonumber(n.offset[2]) or 0
			n.scale[1] = tonumber(n.scale[1]) or 1
			n.scale[2] = tonumber(n.scale[2]) or 1
		end
	end
end
-- Glyph placement is driven entirely off these, on every step of every Lesson.
for _, layout in ipairs({'vertical', 'horizontal'}) do
	local g = f_node(tr_pos, 'glyphs', layout)
	if type(g.offset) ~= 'table' then g.offset = {0, 0} end
	if type(g.scale) ~= 'table' then g.scale = {1, 1} end
	if type(g.spacing) ~= 'table' then g.spacing = {0, 0} end
	g.align = tonumber(g.align) or 1
	if layout == 'horizontal' then g.align = 1 end
end

-- The select screen reads the flat compat aliases, which were copied off the nested node before
-- any of this ran, so hand them the normalized values rather than whatever the def left behind.
do
	local fx = f_palfxDefaults(f_node(tr_pos, 'selscreenpalfx'))
	for _, k in ipairs({'add', 'mul', 'sinadd', 'invertall', 'color'}) do
		tr_pos['selscreenpalfx.' .. k] = fx[k]
		tr_pos['selscreenpalfx_' .. k] = fx[k]
	end
end
end

--;===========================================================
--; Anchors
--;===========================================================
-- Which screen edge an element was authored against. On a screen whose aspect matches the canvas
-- this changes nothing; on a narrower or wider one it decides where the element goes:
--   left   - keeps its authored x, so it stays the same distance from the left edge
--   right  - moves by the whole width difference, so it keeps its distance from the right edge
--   center - moves by half of it, so it stays the same fraction across
-- Screenpacks name it per element as <element>.anchor. Anything that predates the key is inferred
-- from where the element was authored, which is right for the usual corner-pinned HUD but is only a
-- guess: a def that cares should say so. Windows spanning the canvas (the step window, the menu
-- overlay) are not anchored at all - each edge follows its own side, so the window stretches.
local t_anchorFactor = {left = 0, center = 0.5, right = 1}

local function f_inferAnchor(x)
	if x <= tutorial.mtlcx / 3 then
		return 'left'
	elseif x >= tutorial.mtlcx * 2 / 3 then
		return 'right'
	end
	return 'center'
end

-- Reads <node>.anchor, falling back to inference from the authored origin.
local function f_anchorOf(node, x)
	local a = node ~= nil and node.anchor or nil
	if a ~= nil then
		a = tostring(a):lower()
		if t_anchorFactor[a] ~= nil then
			return a
		end
	end
	return f_inferAnchor(x)
end

-- Every authored x the layout owns, paired with how it moves. Each entry holds the pristine value
-- read off the def, so a relayout is always computed from the authored number rather than from the
-- last aspect's result. `t` is the table the value lives in and `i` its index, which is enough to
-- write it back in place - and because f_buildCompatConfig aliased the flat keys onto these very
-- tables, the lessoncounter_pos style lookups elsewhere see the same update.
-- One list per profile; f_useProfile swaps it in with the rest of the profile's UI.
local t_anchored = {}

-- An element origin: one x that moves as a unit with the node's anchor.
local function f_anchorPos(node, key)
	if type(node) ~= 'table' or type(node[key]) ~= 'table' or type(node[key][1]) ~= 'number' then
		return
	end
	local pos = node[key]
	t_anchored[#t_anchored + 1] = {t = pos, i = 1, orig = pos[1], anchor = f_anchorOf(node, pos[1])}
end

-- A window authored in canvas space, as x1,y1,x2,y2: its left edge holds to the left of the screen
-- and its right edge to the right, so it covers the same margins whatever the aspect.
local function f_anchorSpan(node, key)
	if type(node) ~= 'table' or type(node[key]) ~= 'table' or type(node[key][3]) ~= 'number' then
		return
	end
	local w = node[key]
	t_anchored[#t_anchored + 1] = {t = w, i = 1, orig = w[1], anchor = 'left'}
	t_anchored[#t_anchored + 1] = {t = w, i = 3, orig = w[3], anchor = 'right'}
end

local function f_uiAnchors()
	t_anchored = {}
	f_anchorPos(f_node(tr_pos, 'lessoncounter'), 'pos')
	f_anchorPos(f_node(tr_pos, 'totallessontimer'), 'pos')
	f_anchorPos(f_node(tr_pos, 'currentlessontimer'), 'pos')
	f_anchorPos(f_node(tr_pos, 'lessonreset', 'text'), 'pos')
	f_anchorPos(f_node(tr_pos, 'success'), 'pos')
	f_anchorPos(f_node(tr_pos, 'allclear'), 'pos')
	f_anchorPos(f_node(tr_pos, 'textbox'), 'pos')
	f_anchorPos(f_node(tr_pos, 'tutorialmenu'), 'pos')
	for _, layout in ipairs({'vertical', 'horizontal'}) do
		f_anchorPos(f_node(tr_pos, 'lessontitle', layout), 'pos')
		f_anchorPos(f_node(tr_pos, 'lessonsteps', layout), 'pos')
		f_anchorSpan(f_node(tr_pos, 'lessonsteps', layout, 'window'), 'withouttextbox')
		f_anchorSpan(f_node(tr_pos, 'lessonsteps', layout, 'window'), 'withtextbox')
	end
	f_anchorSpan(f_node(tr_pos, 'tutorialmenu', 'overlay'), 'window')
end

-- Writes every anchored x for the current canvas width. Returns whether anything actually moved.
local function f_applyAnchors()
	local delta = tutorial.anchordelta
	local moved = false
	for _, v in ipairs(t_anchored) do
		local x = v.orig + delta * t_anchorFactor[v.anchor]
		if v.t[v.i] ~= x then
			v.t[v.i] = x
			moved = true
		end
	end
	return moved
end

-- f_buildProfile lays each canvas out for the aspect the game is in when it is built, so everything
-- is placed correctly from the start. Loading happens on the motif's aspect; the match relayouts on
-- its own when the stage brings a different one (tutorial.f_syncAspect).

-- Each element caches its Anim on its own config node as .AnimData, the same convention the
-- engine uses for motif elements (and that textbox.overlay.RectData already follows here).
-- p is the pos table the element hangs off, held by reference rather than read now: a relayout
-- rewrites those numbers in place, and every anim has to be put back down at the new ones.
-- f_loadAnimData adds the node's own offset on top of the origin.
local t_elems = {}
local function f_uiElems()
t_elems = {
	{n = f_node(tr_pos, 'lessonsteps', 'vertical', 'bg'),   p = tr_pos.lessonsteps.vertical.pos},
	{n = f_node(tr_pos, 'lessonsteps', 'horizontal', 'bg'), p = tr_pos.lessonsteps.horizontal.pos},
	{n = f_node(tr_pos, 'success', 'bg'),                  p = tr_pos.success.pos},
	{n = f_node(tr_pos, 'success', 'front'),               p = tr_pos.success.pos},
	{n = f_node(tr_pos, 'allclear', 'bg'),                 p = tr_pos.allclear.pos},
	{n = f_node(tr_pos, 'allclear', 'front'),              p = tr_pos.allclear.pos},
	{n = f_node(tr_pos, 'textbox', 'bg'),                  p = tr_pos.textbox.pos},
	{n = f_node(tr_pos, 'textbox', 'front'),               p = tr_pos.textbox.pos},
}
t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'tutorialmenu', 'bg'),    p = tr_pos.tutorialmenu.pos}
t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'tutorialmenu', 'front'), p = tr_pos.tutorialmenu.pos}
for _, path in ipairs({
	{'cursor'}, {'header', 'bg'}, {'item', 'bg'}, {'item', 'active', 'bg'},
	{'status', 'cleared'}, {'status', 'uncleared'}, {'status', 'locked'}, {'arrow', 'up'}, {'arrow', 'down'},
}) do
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'tutorialmenu', unpack(path))}
end
for _, cat in ipairs(f_menuCats(tr_pos.tutorialmenu)) do
	for _, path in ipairs({{'item', 'bg'}, {'item', 'active', 'bg'}, {'header', 'bg'}, {'header', 'active', 'bg'}}) do
		local n = tr_pos.tutorialmenu[path[1]][cat]
		for i = 2, #path, 1 do
			n = type(n) == 'table' and n[path[i]] or nil
		end
		if type(n) == 'table' then
			t_elems[#t_elems + 1] = {n = n}
		end
	end
end
for _, layout in ipairs({'vertical', 'horizontal'}) do
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'lessontitle', layout, 'bg'),    p = tr_pos.lessontitle[layout].pos}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'lessontitle', layout, 'front'), p = tr_pos.lessontitle[layout].pos}
end
for _, sub in ipairs({'upcomingstep', 'currentstep', 'completedstep'}) do
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'vertical', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg', 'tail')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg', 'head')}
end
for _, v in ipairs(t_elems) do
	v.n.AnimData = f_loadAnimData(v.n, v.p ~= nil and v.p[1] or nil, v.p ~= nil and v.p[2] or nil)
	main.f_loadingRefresh()
end
end

-- One text object per visible row per style, the same shape as the step text lines. Built once at
-- load: none of it depends on match state, and the menu shown before the fight needs it early.
local function f_uiMenuDraw()
	local m = tr_pos.tutorialmenu
	local d = {
		title = f_newText(m.title),
		arrowup = f_newText(m.arrow.up),
		arrowdown = f_newText(m.arrow.down),
		rows = {},
		besttime = {},
		cleared = {},
		uncleared = {},
		locked = {},
	}
	for i = 1, m.visibleitems, 1 do
		d.besttime[i] = f_newText(m.besttime)
		d.cleared[i] = f_newText(m.status.cleared)
		d.uncleared[i] = f_newText(m.status.uncleared)
		d.locked[i] = f_newText(m.status.locked)
	end
	tutorial.menuDraw = d
end

-- Glyph runs are laid out once per match from lessonsteps.pos, so an anchor move has to be walked
-- back through them. Every term of the original placement is kept per glyph, so this re-derives the
-- same number rather than nudging the old one, and repeats without drifting.
function tutorial.f_relayoutGlyphs()
	if tutorial.data == nil or type(tutorial.data.lessons) ~= 'table' then
		return
	end
	for _, layout in ipairs({'vertical', 'horizontal'}) do
		local ox = tr_pos.lessonsteps[layout].pos[1] + tr_pos.glyphs[layout].offset[1]
		local oy = tr_pos.lessonsteps[layout].pos[2] + tr_pos.glyphs[layout].offset[2]
		for _, lesson in ipairs(tutorial.data.lessons) do
			for _, step in ipairs(lesson.steps or {}) do
				local gl = type(step.glyphline) == 'table' and step.glyphline[layout] or nil
				if type(gl) == 'table' then
					for m = 1, #gl.glyph, 1 do
						if motif.glyphs[gl.glyph[m]] ~= nil and gl.pos[m] ~= nil then
							gl.pos[m][1] = math.floor(ox + gl.alignOffset[m] + gl.lengthOffset[m])
							gl.pos[m][2] = oy
						end
					end
				end
			end
		end
	end
end

-- Puts the whole layout back down for the aspect the game is in now. Cheap and idempotent when
-- nothing changed, which is every frame but the first of a match on a stage whose aspect differs
-- from the one the module was loaded on. Called from the draw entry points rather than from a hook,
-- because the aspect only ever matters at the point something is about to be drawn.
function tutorial.f_syncAspect()
	local vislcx = f_vislcx(f_screenAspect())
	if vislcx == tutorial.vislcx then
		return false
	end
	tutorial.vislcx = vislcx
	tutorial.anchordelta = vislcx - tutorial.mtlcx
	f_applyAnchors()
	-- Anims hold the localcoord and the origin they were placed with, and animReset in the draw loop
	-- restores them, so each one has to be placed again rather than merely redrawn.
	for _, v in ipairs(t_elems) do
		if v.n.AnimData ~= nil then
			f_placeAnim(v.n.AnimData, v.n, v.p ~= nil and v.p[1] or nil, v.p ~= nil and v.p[2] or nil)
		end
	end
	-- Text sprites hold a localcoord too. The ones drawn from a per-frame :update pick the new one up
	-- on their own, but those built once with their position baked in do not.
	local d = tutorial.menuDraw
	if d ~= nil then
		d.title:relayout()
		d.arrowup:relayout()
		d.arrowdown:relayout()
		for _, pool in ipairs({d.besttime, d.cleared, d.uncleared, d.locked}) do
			for _, obj in ipairs(pool) do
				obj:relayout()
			end
		end
		for _, rows in pairs(d.rows) do
			for _, obj in pairs(rows) do
				obj:relayout()
			end
		end
	end
	if tutorial.notutorialcounter ~= nil then
		tutorial.notutorialcounter:relayout(tr_pos.lessoncounter.pos[1], tr_pos.lessoncounter.pos[2])
	end
	local dr = tutorial.draw
	if dr ~= nil then
		dr.lessoncounter:relayout(tr_pos.lessoncounter.pos[1], tr_pos.lessoncounter.pos[2])
		dr.totallessontimer:relayout(tr_pos.totallessontimer.pos[1], tr_pos.totallessontimer.pos[2])
		dr.currentlessontimer:relayout(tr_pos.currentlessontimer.pos[1], tr_pos.currentlessontimer.pos[2])
		dr.lessonreset_text:relayout(tr_pos.lessonreset.text.pos[1], tr_pos.lessonreset.text.pos[2])
		dr.textbox_text:relayout()
		dr.textbox_title:relayout()
		dr.success_text:relayout()
		dr.allclear_text:relayout()
		for _, layout in ipairs({'vertical', 'horizontal'}) do
			local dl = dr[layout]
			if type(dl) == 'table' then
				local w = tr_pos.lessonsteps[layout].window
				dl.windowXrange = w.withouttextbox[3] - w.withouttextbox[1]
				dl.windowXrangeWtext = w.withtextbox[3] - w.withtextbox[1]
				dl.lessontitle_text:relayout(
					tr_pos.lessontitle[layout].pos[1] + tr_pos.lessontitle[layout].text.offset[1],
					tr_pos.lessontitle[layout].pos[2] + tr_pos.lessontitle[layout].text.offset[2]
				)
				for _, key in ipairs({'upcomingtextline', 'currenttextline', 'completedtextline'}) do
					for _, obj in ipairs(dl[key] or {}) do
						obj:relayout()
					end
				end
			end
		end
	end
	-- Glyph runs are laid out from lessonsteps.pos, which has just moved under them.
	tutorial.f_relayoutGlyphs()
	return true
end

--;===========================================================
--; start.lua
--;===========================================================
tutorial.selectScreenPalMod = 'normal'

-- Current lesson / step / microstep, refreshed by f_tutorialDrawer every frame and read by the
-- checker and the textbox portrait; tutorialExist is latched at round start.
local ct, cts, ctms
local tutorialExist = false

function tutorial.f_inittutorialData()
	tutorial.data = {
		tutorialExist = true,
		tutorialInitialized = false,
		tutorialPaused = false,
		tutorialadvancement = true,
		tutorialRemovalIndex = {},
		active = false,
		allclear = false,
		currentlesson = 1,
		successlesson = nil,
		currentlessonstep = 1,
		currentlessonmicrostep = 1,
		validfortickcount = 0,
		comboCounter = 0,
		-- A step that requires no connect has no hit to key off, so the only thing separating one
		-- of them from the next is the player entering a state again. stateinstance counts those
		-- entries, laststateno/laststatetime spot them, and nohitinstance remembers the one that
		-- satisfied the last no-hit step so the following step cannot take the same one.
		stateinstance = 0,
		laststateno = nil,
		laststatetime = nil,
		nohitinstance = nil,
		projsource = {},
		maxsteps = 0,
		starttick = roundTime(),
		elapsedtime = 0,
		runValid = false,
		-- System lessons this character is admitted to, then its own (fresh copies).
		lessons = tutorial.f_lessonsFor(start.f_getCharData(start.p[1].t_selected[1].ref)),
		bgelemdata = {
			vertical = {},
			horizontal = {},
		},
		draw = {},
		displaytimers = {
			totaltimer = opts.TotalTimer ~= false,
			lessontimer = opts[tutorial.profile.timerKey] ~= false,
		},
	}

	-- Initialize tutorialadvancement from the player's saved preference
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		tutorial.data.tutorialadvancement = true
	else
		tutorial.data.tutorialadvancement = false
	end
end

function tutorial.f_tutorialBuilder()
	local valvarcheck, sumcheck, tempglyphs
	--This function will initialize once to build all the lesson tables based on the motif information and the tutorial information loaded when the char was selected
	--Populate background elements information
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep','upcomingstep','completedstep'}) do
			local bg = tutorial.tutorial_mode[k][v].bg
			tutorial.data.bgelemdata[v][k .. '_bgsize'] = animGetSpriteInfo(bg.AnimData)
			if v == 'horizontal' then
				tutorial.data.bgelemdata[v][k .. '_bgtailwidth'] = animGetSpriteInfo(bg.tail.AnimData)
				tutorial.data.bgelemdata[v][k .. '_bgheadwidth'] = animGetSpriteInfo(bg.head.AnimData)
			end
		end
	end
	
	-- thin out tutorial data according to showforvarvalpairs
	for i = 1, #tutorial.data.lessons, 1 do
		if tutorial.data.lessons[i].showforvar[1] ~= nil then
			valvarcheck = true
			sumcheck = 0
			-- check every var
			for ii = 1, #tutorial.data.lessons[i].showforvar, 1 do
				player(1)
				-- iterate over vals
				for iii = 1, #tutorial.data.lessons[i].showforval[ii], 1 do
					if var(tutorial.data.lessons[i].showforvar[ii]) == tutorial.data.lessons[i].showforval[ii][iii] then
						sumcheck = sumcheck + 1
					end
				end
			end
			-- for every var, there should have been one hit; if not, set valvarcheck to false
			if sumcheck ~= #tutorial.data.lessons[i].showforvar then
				valvarcheck = false
			end
			-- remove tutorial that failed valvarcheck
			if not valvarcheck then
				tutorial.data.tutorialRemovalIndex[#tutorial.data.tutorialRemovalIndex+1] = i
			end
		end
	end
	for i = #tutorial.data.tutorialRemovalIndex, 1, -1 do
		table.remove(tutorial.data.lessons,tutorial.data.tutorialRemovalIndex[i])
	end

	--Obtain all of the tutorial information, to include the offset positions based on whether the display layout is horizontal or vertical
	for i = 1, #tutorial.data.lessons, 1 do
		if #tutorial.data.lessons[i].steps > tutorial.data.maxsteps then
			tutorial.data.maxsteps = #tutorial.data.lessons[i].steps
		end
		for j = 1, #tutorial.data.lessons[i].steps, 1 do
			local movelistline = tutorial.data.lessons[i].steps[j].glyphs
			for kk, v in main.f_sortKeys(motif.glyphs, function(t, a, b) return string.len(a) > string.len(b) end) do
				local s = movelistline
				
				-- Replace glyph tokens with <token> for later lookup in motif.glyphs.
						
				movelistline = s:gsub('()' .. main.f_escapePattern(kk), function(pos)
								-- If the match starts immediately after a '<', it's already inside a tag.
								-- Leave it unchanged to prevent nested replacements.
								if pos > 1 and s:sub(pos - 1, pos - 1) == '<' then
									return kk
								end
								local escaped = kk:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
								return '<' .. escaped .. '>'
							end)
						end
			movelistline = movelistline:gsub('%s+$', '')
			for moves in movelistline:gmatch('(	*[^	]+)') do
				moves = moves .. '<#>'
				tempglyphs = {}
				for m1, m2 in moves:gmatch('(.-)<([^<>%s]+)>') do
		m2 = m2:gsub('&lt;', '<'):gsub('&gt;', '>'):gsub('&amp;', '&')
		if not m2:match('^#[A-Za-z0-9]+$') and not m2:match('^/$') and not m2:match('^#$') then
						tempglyphs[#tempglyphs+1] = m2
					end
				end
				for _, layout in ipairs({'vertical','horizontal'}) do
					if tutorial.tutorial_mode.glyphs[layout].align == -1 then
						for m = #tempglyphs, 1, -1 do
							-- The glyph is appended first, so index off the slot it landed in: reading the
							-- length again afterwards put every other field one slot past its own glyph.
							local n = #tutorial.data.lessons[i].steps[j].glyphline[layout].glyph + 1
							tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[n] = tempglyphs[m]
							tutorial.data.lessons[i].steps[j].glyphline[layout].pos[n] = {0,0}
							tutorial.data.lessons[i].steps[j].glyphline[layout].width[n] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].alignOffset[n] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].lengthOffset[n] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].scale[n] = {1,1}
						end
					else
						for m = 1, #tempglyphs do
							tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[m] = tempglyphs[m]
							tutorial.data.lessons[i].steps[j].glyphline[layout].pos[m] = {0,0}
							tutorial.data.lessons[i].steps[j].glyphline[layout].width[m] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].alignOffset[m] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].lengthOffset[m] = 0
							tutorial.data.lessons[i].steps[j].glyphline[layout].scale[m] = {1,1}
						end
					end
				end
			end
			for _, layout in ipairs({'vertical','horizontal'}) do
				local lengthOffset = 0
				local alignOffset = 0
				local align = 1
				local width = 0
				--Some fonts won't give us the data we need to scale glyphs from, but sometimes that doesn't matter anyway
				local font_def = nil
				if layout == "vertical" and tutorial.tutorial_mode.glyphs.vertical.scalewithtext == "true" then
					font_def = f_fontDef(tutorial.tutorial_mode.currentstep.vertical.text.font[1])
				end
				local glyphalign = tutorial.tutorial_mode.glyphs[layout].align
				for m = 1, #tutorial.data.lessons[i].steps[j].glyphline[layout].glyph, 1 do
					if motif.glyphs[tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[m]] ~= nil then
						if glyphalign == 0 then --center align
							alignOffset = tutorial.tutorial_mode.glyphs[layout].offset[1] * 0.5
						elseif glyphalign == -1 then --right align
							alignOffset = tutorial.tutorial_mode.glyphs[layout].offset[1]
						end
						if glyphalign ~= align then
							lengthOffset = 0
							align = glyphalign
						end
						local scaleX = tutorial.tutorial_mode.glyphs[layout].scale[1]
						local scaleY = tutorial.tutorial_mode.glyphs[layout].scale[2]
						if glyphalign == -1 then
							alignOffset = alignOffset - motif.glyphs[tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[1] * scaleX
						end
						tutorial.data.lessons[i].steps[j].glyphline[layout].alignOffset[m] = alignOffset
						if font_def ~= nil then
							scaleY = font_def.Size[2] * tutorial.tutorial_mode.currentstep.vertical.text.scale[2] / motif.glyphs[tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[2]
							scaleX = scaleY
						end
						tutorial.data.lessons[i].steps[j].glyphline[layout].scale[m] = {scaleX, scaleY}
						tutorial.data.lessons[i].steps[j].glyphline[layout].width[m] = math.floor(motif.glyphs[tutorial.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[1] * scaleX + tutorial.tutorial_mode.glyphs[layout].spacing[1])
						if glyphalign == 1 then
							lengthOffset = lengthOffset + tutorial.data.lessons[i].steps[j].glyphline[layout].width[m]
						elseif glyphalign == -1 then
							lengthOffset = lengthOffset - tutorial.data.lessons[i].steps[j].glyphline[layout].width[m]
						else
							lengthOffset = lengthOffset + tutorial.data.lessons[i].steps[j].glyphline[layout].width[m] / 2
						end
						tutorial.data.lessons[i].steps[j].glyphline[layout].lengthOffset[m] = lengthOffset
						tutorial.data.lessons[i].steps[j].glyphline[layout].pos[m] = {
							math.floor(tutorial.tutorial_mode.lessonsteps[layout].pos[1] + tutorial.tutorial_mode.glyphs[layout].offset[1] + alignOffset + lengthOffset),
							tutorial.tutorial_mode.lessonsteps[layout].pos[2] + tutorial.tutorial_mode.glyphs[layout].offset[2]
						}
					end
				end
			end
		end
		if #tutorial.data.lessons[i].steps > tutorial.data.maxsteps then
			tutorial.data.maxsteps = #tutorial.data.lessons[i].steps
		end
	end
	--Pre-populate the draw table
	tutorial.draw = {
		vertical = {},
		horizontal = {},
		success = 0,
		fade = 0,
		fadein = 0,
		fadeout = 0,
		fadetriggered = false,
		textbox_text = f_newText(tutorial.tutorial_mode.textbox.text),
		textbox_title = f_newText(tutorial.tutorial_mode.textbox.title),
		success_text = f_newText(tutorial.tutorial_mode.success.text),
		allclear = math.max(animGetLength(tutorial.tutorial_mode.allclear.front.AnimData), animGetLength(tutorial.tutorial_mode.allclear.bg.AnimData), tutorial.tutorial_mode.allclear.text.displaytime),
		allclear_text = f_newText(tutorial.tutorial_mode.allclear.text),
		lessoncounter = f_newText(tutorial.tutorial_mode.lessoncounter),
		totallessontimer = f_newText(tutorial.tutorial_mode.totallessontimer),
		currentlessontimer = f_newText(tutorial.tutorial_mode.currentlessontimer),
		lessonreset_text = f_newText(tutorial.tutorial_mode.lessonreset.text),
	}
	for _, v in ipairs({'vertical','horizontal'}) do
		tutorial.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			lessontitle = math.max(animGetLength(tutorial.tutorial_mode.lessontitle[v].front.AnimData), animGetLength(tutorial.tutorial_mode.lessontitle[v].bg.AnimData)),
			--lessontitle = 100,
			lessontitle_text = f_newText(tutorial.tutorial_mode.lessontitle[v].text),
			windowXrange = tutorial.tutorial_mode.lessonsteps[v].window.withouttextbox[3] - tutorial.tutorial_mode.lessonsteps[v].window.withouttextbox[1],
			windowYrange = tutorial.tutorial_mode.lessonsteps[v].window.withouttextbox[4] - tutorial.tutorial_mode.lessonsteps[v].window.withouttextbox[2],
			windowXrangeWtext = tutorial.tutorial_mode.lessonsteps[v].window.withtextbox[3] - tutorial.tutorial_mode.lessonsteps[v].window.withtextbox[1],
			windowYrangeWtext = tutorial.tutorial_mode.lessonsteps[v].window.withtextbox[4] - tutorial.tutorial_mode.lessonsteps[v].window.withtextbox[2],
		}
		tutorial.draw[v].lessontitle_text:update({x = tutorial.tutorial_mode.lessontitle[v].pos[1]+tutorial.tutorial_mode.lessontitle[v].text.offset[1], y = tutorial.tutorial_mode.lessontitle[v].pos[2]+tutorial.tutorial_mode.lessontitle[v].text.offset[2],})
		for i = 1, tutorial.data.maxsteps, 1 do
			tutorial.draw[v].upcomingtextline[i] = f_newText(tutorial.tutorial_mode.upcomingstep[v].text)
			tutorial.draw[v].currenttextline[i] = f_newText(tutorial.tutorial_mode.currentstep[v].text)
			tutorial.draw[v].completedtextline[i] = f_newText(tutorial.tutorial_mode.completedstep[v].text)
		end
	end

	-- Wire up the Lesson select view. The same item list backs both the screen shown when the match
	-- loads and the Pause menu's Tutorial List, so the two can never drift apart.
	tutorial.selectFilter = 'all'
	-- The engine builds one pause menu per [<Gamemode> Pause Menu] section, as menu.<gamemode>.
	tutorial.rootNode = type(menu) == 'table' and menu[tutorial.profile.gamemode] or nil
	local sub = nil
	local stack = {tutorial.rootNode}
	while #stack > 0 do
		local node = table.remove(stack)
		if type(node) == 'table' and type(node.submenu) == 'table' then
			if type(node.submenu.tutoriallist) == 'table' and type(node.submenu.tutoriallist.items) == 'table' then
				sub = node.submenu.tutoriallist
				break
			end
			for _, child in pairs(node.submenu) do
				stack[#stack + 1] = child
			end
		end
	end
	tutorial.listNode = sub
	if sub ~= nil then
		-- Remember what the section itself declared, so round start can put it all back.
		if tutorial.listTail == nil then
			tutorial.listTail = sub.items
		end
		if tutorial.listLoop == nil then
			tutorial.listLoop = sub.loop
		end
		sub.items = tutorial.f_buildSelectItems()
		sub.item = tutorial.f_firstUncleared(sub.items)
		sub.first = 1
		-- The Tutorial List *is* the select view: hand the menu system our loop in place of its own.
		sub.loop = function()
			tutorial.f_selectLoop(sub, false)
		end
	end
	if tutorial.rootNode ~= nil and tutorial.rootItems == nil then
		tutorial.rootItems = tutorial.rootNode.items
	end
	tutorial.select = {
		items = sub ~= nil and sub.items or tutorial.f_buildSelectItems(),
		item = 1,
		first = 1,
		open = false,
	}
	tutorial.select.item = tutorial.f_firstUncleared(tutorial.select.items)

	tutorial.data.tutorialInitialized = true
end

function tutorial.f_tutorialDummySetup()
	--If the tutorial initializer was successful and the round animation is completed, we will start drawing tutorial on the screen
	player(2)
	setAILevel(0)
	if tutorial.data.currentlesson <= #tutorial.data.lessons then
		if tutorial.data.lessons[tutorial.data.currentlesson].p2life > 0 then
			mapSet('_iksys_tutorialSetLife', tutorial.data.lessons[tutorial.data.currentlesson].p2life)
			setLife(tutorial.data.lessons[tutorial.data.currentlesson].p2life)
		elseif map('_iksys_tutorialSetLife') < lifeMax() then
			mapSet('_iksys_tutorialSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_tutorialSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(1)
	if tutorial.data.currentlesson <= #tutorial.data.lessons then
		if tutorial.data.lessons[tutorial.data.currentlesson].p1life > 0 then
			mapSet('_iksys_tutorialSetLife', tutorial.data.lessons[tutorial.data.currentlesson].p1life)
			setLife(tutorial.data.lessons[tutorial.data.currentlesson].p1life)
		elseif map('_iksys_tutorialSetLife') < lifeMax() then
			mapSet('_iksys_tutorialSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_tutorialSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(2)
	mapSet('_iksys_tutorialDummyControl', 0)
	if not tutorial.data.allclear and not tutorial.data.lessons[tutorial.data.currentlesson].active then
		if tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'stand' then
			mapSet('_iksys_tutorialDummyMode', 0)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'crouch' then
			mapSet('_iksys_tutorialDummyMode', 1)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'jump' then
			mapSet('_iksys_tutorialDummyMode', 2)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'wjump' then
			mapSet('_iksys_tutorialDummyMode', 3)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'fjump' then
			mapSet('_iksys_tutorialDummyMode', 4)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'bjump' then
			mapSet('_iksys_tutorialDummyMode', 5)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'fwjump' then
			mapSet('_iksys_tutorialDummyMode', 6)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummymode == 'bwjump' then
			mapSet('_iksys_tutorialDummyMode', 7)
		end
		-- none / auto (blocks everything; 'all' is a synonym) / afterhit (blocks for a moment after
		-- being hit, so a combo can be started but not continued) / random (blocks about half the time).
		mapSet('_iksys_tutorialGuardMode', tutorial.t_guardMode[tutorial.data.lessons[tutorial.data.currentlesson].guardmode] or 0)
		if tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'none' then
			mapSet('_iksys_tutorialButtonJam', 0)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'a' then
			mapSet('_iksys_tutorialButtonJam', 1)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'b' then
			mapSet('_iksys_tutorialButtonJam', 2)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'c' then
			mapSet('_iksys_tutorialButtonJam', 3)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'x' then
			mapSet('_iksys_tutorialButtonJam', 4)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'y' then
			mapSet('_iksys_tutorialButtonJam', 5)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'z' then
			mapSet('_iksys_tutorialButtonJam', 6)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'start' then
			mapSet('_iksys_tutorialButtonJam', 7)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'd' then
			mapSet('_iksys_tutorialButtonJam', 8)
		elseif tutorial.data.lessons[tutorial.data.currentlesson].buttonjam == 'w' then
			mapSet('_iksys_tutorialButtonJam', 9)
		end
		-- Frames the dummy waits between button jam presses - or, in the jump modes, from takeoff to its
		-- one press per jump. Set alongside the jam itself, so a Lesson that leaves it out goes back to
		-- the default for its mode rather than keeping the last one's.
		local jt = tutorial.data.lessons[tutorial.data.currentlesson]
		local jdefault = tutorial.t_jumpModes[jt.dummymode] and tutorial.buttonJamAirDelayDefault or tutorial.buttonJamDelayDefault
		mapSet('_iksys_tutorialButtonJamInterval', jt.buttondelay or jdefault)
		mapSet('_iksys_tutorialAirJamState', 0)
		-- Frames the dummy stays on the ground between jumps in the jump dummy modes, set the same way.
		mapSet('_iksys_tutorialJumpInterval', tutorial.data.lessons[tutorial.data.currentlesson].jumpdelay or tutorial.jumpDelayDefault)
		mapSet('_iksys_tutorialJumpDelay', 0)
		-- A dummy that acts (one of the jump dummymodes, or a button jam) walks back to its dummypos
		-- distance from the player before it does, so the action always starts from the spacing the
		-- Lesson was written for - even after the player has moved or a forward jump has closed it.
		-- Corner placements have no distance to keep, and a dummy that only stands or crouches is left
		-- alone so it never backs away from the player's approach.
		local t = tutorial.data.lessons[tutorial.data.currentlesson]
		local acts = tutorial.t_jumpModes[t.dummymode] or (t.buttonjam ~= nil and t.buttonjam ~= 'none')
		mapSet('_iksys_tutorialDistance', acts and (tutorial.t_dummyDistance[t.dummypos] or 0) or 0)
		mapSet('_iksys_tutorialDirection', 0)
		tutorial.data.lessons[tutorial.data.currentlesson].active = true
	end
	player(1)
end

-- lesson.dummypos values the dummy keeps its distance for, as _iksys_tutorialDistance values.
tutorial.t_dummyDistance = {close = 1, medium = 2, far = 3}
-- lesson.guardmode -> _iksys_tutorialGuardMode (see the legend at the top of dojo.zss)
tutorial.t_guardMode = {none = 0, afterhit = 1, auto = 2, all = 2, random = 3}
-- lesson.dummymode values that count as the dummy acting, for the distance keeping above.
tutorial.t_jumpModes = {jump = true, wjump = true, fjump = true, bjump = true, fwjump = true, bwjump = true}

-- lesson.dummybuttondelay when a Lesson leaves it out: the gap the button jam has always used.
tutorial.buttonJamDelayDefault = 11
-- The same in the jump modes, where it counts from takeoff: attack as soon as the dummy leaves the ground.
tutorial.buttonJamAirDelayDefault = 0
-- lesson.dummyjumpdelay when a Lesson leaves it out: jump again as soon as the dummy lands.
tutorial.jumpDelayDefault = 0

local function f_iconAnimString(step)
	local t = {}
	for _, k in ipairs(step.iconanim) do
		t[#t + 1] = tostring(k)
	end
	return table.concat(t, ',')
end

function tutorial.textboxportrait()
	-- Cached until roundStart clears it, because the selected character can change.
	if tutorial.charPortraitSff == nil then
		local spr = loadText(getCharFileName(tutorial.p1selref)):lower()
		spr = spr:gsub('([^\r\n;]*)%s*;[^\r\n]*', '%1')
		spr = spr:gsub('\n%s*\n', '\n')
		spr = spr:gsub('.*sprite.*=%s*(.*sff).*', '%1')
		tutorial.charPortraitSff = sffNew(getCharFileName(tutorial.p1selref):gsub('(.*)%/.*def.*', '%1/') .. spr)
	end
	local tutorialanim = f_iconAnimString(tutorial.data.lessons[ct].steps[cts])
	tutorial.tutorial_mode.textbox.portrait.anim = animNew(tutorial.charPortraitSff, tutorialanim)
end
	
function tutorial.f_tutorialDrawer()
	if tutorial.data.tutorialInitialized and roundState() == 2 and not tutorial.data.active and tutorial.draw.fade == 0 then
		tutorial.f_tutorialDummySetup()
		tutorial.data.active = true
		-- Demonstrations-only: whether the pair have moved since the lesson was entered. A demo that
		-- restarted the lesson to get here is already under way, so they have.
		tutorial.data.demoOnlyPlayed = tutorial.f_demoActive()
		-- A lesson being entered shows its instruction pages first. A speedrun is against the clock,
		-- so it skips them; the pause menu still opens them on request.
		tutorial.f_startDummyScript(tutorial.data.currentlesson)
		local lesson = tutorial.data.lessons[tutorial.data.currentlesson]
		if lesson ~= nil and not lesson.pagesSeen and not tutorial.f_speedrunEnabled() and not tutorial.f_demoActive() then
			tutorial.f_openPages(tutorial.data.currentlesson)
		end
	end

	if paused() and not tutorial.data.tutorialPaused then
		tutorial.data.tutorialPaused = true
	elseif not paused() then
		tutorial.data.tutorialPaused = false
	end

	local accwidth = 0
	local addrow = 0
	local layout, spacing, sub, windowXrange, windowYrange, animposx, animposy
	local textboxwindow1, textboxwindow2, textboxwindow3, textboxwindow4, textboxtext_offset1, textboxtext_offset2
	local tutorialanim, tutorialanimoffset, tutorialanimscalex, tutorialanimscaley
	local tutorialanimwindow1, tutorialanimwindow2, tutorialanimwindow3, tutorialanimwindow4
	-- Initialize abbreviated values for readability
	ct = tutorial.data.currentlesson
	cts = tutorial.data.currentlessonstep
	ctms = tutorial.data.currentlessonmicrostep
	layout = tutorial.tutorial_mode.tutoriallayout

	if tutorial.data.active then
		if ct <= #tutorial.data.lessons and tutorial.draw.success == 0 then

			--According to motif instructions, draw tutorial counter on screen
			local trtext = tutorial.tutorial_mode.lessoncounter.text
			trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%t', tostring(#tutorial.data.lessons))
			tutorial.draw.lessoncounter:update({text = trtext})
			tutorial.draw.lessoncounter:draw()
			tutorial.f_drawLessonExtras(ct)
			--Logic for the stopwatches: total time spent in lesson, and time spent on this current lesson
			if tutorial.data.displaytimers.totaltimer then
				local totaltimertext = tutorial.tutorial_mode.totallessontimer.text
				tutorial.data.elapsedtime = roundTime() - tutorial.data.starttick
				local m, s, x = f_timeConvert(tutorial.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				tutorial.draw.totallessontimer:update({text = totaltimertext})
				tutorial.draw.totallessontimer:draw()
			else
				--tutorial.draw.totallessontimer:update({text = "Timer Disabled"})
				--tutorial.draw.totallessontimer:draw()
			end
			if tutorial.data.displaytimers.lessontimer then
				local currenttimertext = tutorial.tutorial_mode.currentlessontimer.text
				tutorial.data.lessons[ct].elapsedtime = roundTime() - tutorial.data.lessons[ct].starttick
				local m, s, x = f_timeConvert(tutorial.data.lessons[ct].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				tutorial.draw.currentlessontimer:update({text = currenttimertext})
				tutorial.draw.currentlessontimer:draw()
			else
				--tutorial.draw.currentlessontimer:update({text = "Timer Disabled"})
				--tutorial.draw.currentlessontimer:draw()
			end

			-- Draw lesson reset reminder if enabled
			if tutorial.tutorial_mode.lessonreset.enabled then
				tutorial.draw.lessonreset_text:update({text = tutorial.tutorial_mode.lessonreset.text.text})
				tutorial.draw.lessonreset_text:draw()
			end

			-- Draw lesson step background
			animUpdate(tutorial.tutorial_mode.lessonsteps[layout].bg.AnimData)
			animDraw(tutorial.tutorial_mode.lessonsteps[layout].bg.AnimData)

			-- Draw lesson title
			animUpdate(tutorial.tutorial_mode.lessontitle[layout].bg.AnimData)
			animDraw(tutorial.tutorial_mode.lessontitle[layout].bg.AnimData)
			tutorial.draw[layout].lessontitle_text:update({text = tutorial.data.lessons[ct].name})
			tutorial.draw[layout].lessontitle_text:draw()
			animUpdate(tutorial.tutorial_mode.lessontitle[layout].front.AnimData)
			animDraw(tutorial.tutorial_mode.lessontitle[layout].front.AnimData)

			local startonstep = 1
			local drawtothisstep = #tutorial.data.lessons[ct].steps

			--Determine whether textboxes are being shown and whether the current lesson has a textbox to display, and if so, draw them!
			--Also adjust the window range to account for the textbox as specified in the motif
			if tutorial.tutorial_mode.textbox_visible == true and tutorial.data.lessons[ct].textbox ~= '' then
				windowYrange = tutorial.draw[layout].windowYrangeWtext
				windowXrange = tutorial.draw[layout].windowXrangeWtext

						textboxwindow1 =    tutorial.tutorial_mode.textbox.pos[1]+tutorial.tutorial_mode.textbox.overlay.window[1]
						textboxwindow2 =    tutorial.tutorial_mode.textbox.pos[2]+tutorial.tutorial_mode.textbox.overlay.window[2]
						textboxwindow3 =    tutorial.tutorial_mode.textbox.pos[1]+tutorial.tutorial_mode.textbox.overlay.window[3]
						textboxwindow4 =    tutorial.tutorial_mode.textbox.pos[2]+tutorial.tutorial_mode.textbox.overlay.window[4]
		
	-- An unset overlay window means "the whole canvas", which is as wide as the screen is.
	if textboxwindow3 == 0 then
textboxwindow3 = tutorial.vislcx
	end
	if textboxwindow4 == 0 then
textboxwindow4 = tutorial.mtlcy
	end

		if tutorial.tutorial_mode.textbox.overlay.RectData == nil then
		tutorial.tutorial_mode.textbox.overlay.RectData = rectNew()
				end
		rectSetColor(tutorial.tutorial_mode.textbox.overlay.RectData, 
						tutorial.tutorial_mode.textbox.overlay.col[1],
						tutorial.tutorial_mode.textbox.overlay.col[2],
						tutorial.tutorial_mode.textbox.overlay.col[3])
		rectSetAlpha(tutorial.tutorial_mode.textbox.overlay.RectData, 
						tutorial.tutorial_mode.textbox.overlay.alpha[1],
						tutorial.tutorial_mode.textbox.overlay.alpha[2])
		rectSetLayerno(tutorial.tutorial_mode.textbox.overlay.RectData, 0)
		rectSetWindow(tutorial.tutorial_mode.textbox.overlay.RectData, 
						textboxwindow1,
						textboxwindow2,
						textboxwindow3,
						textboxwindow4)
		rectSetLocalcoord(tutorial.tutorial_mode.textbox.overlay.RectData, tutorial.f_localcoord())
		rectDraw(tutorial.tutorial_mode.textbox.overlay.RectData)

				animSetLocalcoord(tutorial.tutorial_mode.textbox.bg.AnimData, tutorial.f_localcoord())
				animUpdate(tutorial.tutorial_mode.textbox.bg.AnimData)
				animDraw(tutorial.tutorial_mode.textbox.bg.AnimData)

				-- Draw text
				local trtext = tutorial.tutorial_mode.textbox.title.text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', tutorial.data.lessons[ct].name)
				tutorial.draw.textbox_title:update({text = trtext})
				tutorial.draw.textbox_title:draw()

				if not tutorial.draw.draw_textbox_text then
					tutorial.data.lessons[ct].textcnt = tutorial.data.lessons[ct].textcnt + 1
				end
				
		if motif.Fnt[tutorial.draw.textbox_text.font] ~= nil then
			textImgSetFont(tutorial.draw.textbox_text.ti, motif.Fnt[tutorial.draw.textbox_text.font])
		end

	textboxtext_offset1 = textboxwindow1 + tutorial.tutorial_mode.textbox_text_window[1] + tutorial.tutorial_mode.textbox_text_offset[1]
	textboxtext_offset2 = textboxwindow2 + tutorial.tutorial_mode.textbox_text_window[2] + tutorial.tutorial_mode.textbox_text_offset[2]

		textImgSetText(tutorial.draw.textbox_text.ti,string.format(tutorial.data.lessons[ct].textbox, main.f_countSubstring(tutorial.data.lessons[ct].textbox, '_')))
		textImgSetPos(tutorial.draw.textbox_text.ti, math.floor(textboxtext_offset1), math.floor(textboxtext_offset2))
		textImgSetScale(tutorial.draw.textbox_text.ti, tutorial.draw.textbox_text.scaleX, tutorial.draw.textbox_text.scaleY)
		textImgSetLocalcoord(tutorial.draw.textbox_text.ti, tutorial.f_localcoord())
		textImgDraw(tutorial.draw.textbox_text.ti)


				-- Draw portrait depending on desired source. Both sources feed the same draw
				-- below; the anim is rebuilt every frame because iconanim is per lesson step.
				if tutorial.tutorial_mode.textbox_portrait_source == "system" then
					tutorialanim = f_iconAnimString(tutorial.data.lessons[ct].steps[cts])
					tutorial.tutorial_mode.textbox.portrait.anim = animNew(sff, tutorialanim)
				elseif tutorial.tutorial_mode.textbox_portrait_source == "char" then
					tutorial.textboxportrait()
				end

				if tutorial.tutorial_mode.textbox.portrait.anim ~= nil then
					tutorialanimoffset = tutorial.data.lessons[ct].steps[cts].iconanimoffset
					animposx = (textboxwindow1 + tutorial.tutorial_mode.textbox_portrait_offset[1] + tutorialanimoffset[1])
					animposy = (textboxwindow2 + tutorial.tutorial_mode.textbox_portrait_offset[2] + tutorialanimoffset[2])
					tutorialanimscalex = tutorial.tutorial_mode.textbox_portrait_scale[1] * tutorial.data.lessons[ct].steps[cts].iconanimscale[1]
					tutorialanimscaley = tutorial.tutorial_mode.textbox_portrait_scale[2] * tutorial.data.lessons[ct].steps[cts].iconanimscale[2]
					tutorialanimwindow3 = tutorial.tutorial_mode.textbox_portrait_window[3] + tutorial.data.lessons[ct].steps[cts].iconanimwindow[3] + tutorial.vislcx
					tutorialanimwindow4 = tutorial.tutorial_mode.textbox_portrait_window[4] + tutorial.data.lessons[ct].steps[cts].iconanimwindow[4] + tutorial.mtlcy

					tutorialanimwindow1 = animposx + tutorial.tutorial_mode.textbox_portrait_window[1] + tutorial.data.lessons[ct].steps[cts].iconanimwindow[1]
					tutorialanimwindow2 = animposy + tutorial.tutorial_mode.textbox_portrait_window[2] + tutorial.data.lessons[ct].steps[cts].iconanimwindow[2]

					local a = tutorial.tutorial_mode.textbox.portrait.anim
					animSetLocalcoord(a, tutorial.f_localcoord())
					animSetLayerno(a, 0)
					animSetPos(a, math.floor(animposx), math.floor(animposy))
					animSetScale(a, tutorialanimscalex, tutorialanimscaley)
					animSetFacing(a, tutorial.tutorial_mode.textbox_portrait_facing)
					animSetWindow(a, tutorialanimwindow1, tutorialanimwindow2, tutorialanimwindow3, tutorialanimwindow4)
					animUpdate(a)
					animDraw(a)
				end

				-- Draw textbox front
				animUpdate(tutorial.tutorial_mode.textbox.front.AnimData)
				animDraw(tutorial.tutorial_mode.textbox.front.AnimData)
			else
				windowYrange = tutorial.draw[layout].windowYrange
				windowXrange = tutorial.draw[layout].windowXrange
			end

			--For vertical lesson layouts, determine if all assets will be drawn within the tutorial window range, or if scrolling needs to be enabled. For horizontal layouts, we will figure it out
			--when we determine glyph and incrementor widths (see notes below). We do this step outside of the draw loop to speed things up.
			if #tutorial.data.lessons[ct].steps*tutorial.tutorial_mode.lessonsteps[layout].spacing[2] > windowYrange and layout == "vertical" then
				startonstep = math.max(cts-2, 1)
				if (drawtothisstep - startonstep)*tutorial.tutorial_mode.lessonsteps[layout].spacing[2] > windowYrange then
					drawtothisstep = math.min(startonstep+math.floor(windowYrange/tutorial.tutorial_mode.lessonsteps[layout].spacing[2]),#tutorial.data.lessons[ct].steps)
				end
			end

			--This is the draw loop
			for i = startonstep, drawtothisstep, 1 do
				local tempoffset = {tutorial.tutorial_mode.lessonsteps[layout].spacing[1]*(i-startonstep),tutorial.tutorial_mode.lessonsteps[layout].spacing[2]*(i-startonstep)}
				--sub = 'current'
				if i < cts then
					sub = 'completed'
				elseif i == cts then
					sub = 'current'
				else
					sub = 'upcoming'
				end

				local bgtargetscale = {1,1}
				local bgcomponentposX = 0
				local padding = 0
				local totalglyphlength = 0
				local bgtailwidth = 0 --only used for horizontal layouts
				local bgheadwidth = 0 --only used for horizontal layouts


				if layout == "vertical" then
					--Vertical layouts are the simplest - they have a constant width sprite or anim that the text is drawn on top of, and the glyphs are displayed wherever specified.
					--The vertical layouts do NOT support incrementors (see notes below for horizontal layout).
					local stepbg = tutorial.tutorial_mode[sub .. 'step'].vertical.bg
					-- animReset restores pos, scale and window from the values the element was built
					-- with and clears PalFX, so it has to come before this frame's setters rather than
					-- after them - reset last is what stopped palfx from ever reaching the draw.
					animReset(stepbg.AnimData)
					animSetPos(
						stepbg.AnimData,
						tutorial.tutorial_mode.lessonsteps.vertical.pos[1] + stepbg.offset[1] + tempoffset[1],
						tutorial.tutorial_mode.lessonsteps.vertical.pos[2] + stepbg.offset[2] + tempoffset[2]
					)
					tutorial.draw.vertical[sub .. 'textline'][i]:update({
						x = tutorial.tutorial_mode.lessonsteps.vertical.pos[1]+tutorial.tutorial_mode[sub .. 'step'].vertical.text.offset[1]+tutorial.tutorial_mode.lessonsteps.vertical.spacing[1]*(i-startonstep),
						y = tutorial.tutorial_mode.lessonsteps.vertical.pos[2]+tutorial.tutorial_mode[sub .. 'step'].vertical.text.offset[2]+tutorial.tutorial_mode.lessonsteps.vertical.spacing[2]*(i-startonstep),
						text = tutorial.data.lessons[ct].steps[i].text
					})
					animSetPalFX(stepbg.AnimData, {
						time = 1,
						add = stepbg.palfx.add,
						mul = stepbg.palfx.mul,
						sinadd = stepbg.palfx.sinadd,
						invertall = stepbg.palfx.invertall,
						color = stepbg.palfx.color
					})
					animSetScale(stepbg.AnimData, stepbg.scale[1], stepbg.scale[2])
					animUpdate(stepbg.AnimData)
					animDraw(stepbg.AnimData)
					tutorial.draw.vertical[sub .. 'textline'][i]:draw()
				elseif layout == "horizontal" then
					--Horizontal layouts are much more complicated. Text is not drawn in horizontal mode, instead we only display the glyphs. A small sprite is dynamically tiled to the width of the
					--glyphs, and an optional background element called an incrementor (bginc) can be used to link the pieces together (think of an arrow where the body of the arrow is where the
					--glyphs are being drawn and that's the dynamically sized part, and the head of the arrow is the incrementor which is a fixed width sprite). There's quite a bit more work that
					--goes into displaying the horizontal layouts because the code needs to figure out the window size, and determine when it needs to "go to the next line" and create a return so
					--that tutorial can be displayed dynamically. Back to the arrow analogy, you always want an arrow body to have an arrow head, so the incrementor width is added to the glyphs length
					--and the padding factor specified in the motif data, it's all added together until the window width is met or exceeded, then a line return occurs and the next line is drawn.
					local bgsize = {0,0}
					local hbg = tutorial.tutorial_mode[sub .. 'step'].horizontal.bg
					-- animGetSpriteInfo reports the raw sprite, but head and tail are drawn at the scale
					-- their own node asks for. Row widths, line breaks and the body's start all measure
					-- in tutorial localcoord units, so budget the drawn width, not the sprite's.
					if tutorial.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'] ~= nil then bgtailwidth = math.floor(tutorial.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'].Size[1] * hbg.tail.scale[1]) end
					if tutorial.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'] ~= nil then bgheadwidth = math.floor(tutorial.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'].Size[1] * hbg.head.scale[1]) end
					if tutorial.data.bgelemdata.horizontal[sub .. 'step_bgsize'] ~= nil then bgsize = tutorial.data.bgelemdata.horizontal[sub .. 'step_bgsize'].Size end

					totalglyphlength = tutorial.data.lessons[ct].steps[i].glyphline.horizontal.lengthOffset[#tutorial.data.lessons[ct].steps[i].glyphline.horizontal.lengthOffset]
					padding = tutorial.tutorial_mode.lessonsteps_horizontal_padding
					spacing = tutorial.tutorial_mode.lessonsteps_horizontal_spacing[1]

					local tempwidth = spacing + bgtailwidth + padding + totalglyphlength + padding + bgheadwidth + accwidth
					-- Only wrap when something is already on this row. A step wider than the window on its own
					-- has nothing to wrap away from, and breaking there would push the row it starts - the
					-- first row included - down by a spacing it never earned.
					if accwidth > 0 and tempwidth - tutorial.tutorial_mode.lessonsteps_horizontal_spacing[1] > windowXrange then
						accwidth = 0
						addrow = addrow + 1
					end

					tempoffset[2] = tutorial.tutorial_mode.lessonsteps_horizontal_spacing[2]*(addrow)
					-- Rows are placed from the lessonsteps origin, the same origin the vertical layout draws its
					-- steps from. The bg pieces carry only their own bg.offset; glyphs.offset belongs to the
					-- glyphs and is applied once, where they are drawn.
					local rowy = tutorial.tutorial_mode.lessonsteps_horizontal_pos[2] + tempoffset[2]

					-- Calculate initial positions
					if accwidth == 0 then
						bgcomponentposX = tutorial.tutorial_mode.lessonsteps_horizontal_pos[1]
					else
						bgcomponentposX = accwidth + spacing -- + bgheadwidth 
					end

					-- Draw tail. Head and tail are fixed-width caps: they are drawn at exactly the scale
					-- their dojo.def node declares, on both axes. Only the body between them stretches,
					-- and only on x. The anims already carry those scales from f_loadAnimData, but the
					-- draw sets them again so the loop never depends on what the previous step left behind.
					local hpalfx = {
						time = 1,
						add = hbg.palfx.add,
						mul = hbg.palfx.mul,
						sinadd = hbg.palfx.sinadd,
						invertall = hbg.palfx.invertall,
						color = hbg.palfx.color
					}
					local glyphrow = tutorial.data.lessons[ct].steps[i].glyphline.horizontal
					animReset(hbg.tail.AnimData)
					animSetPos(hbg.tail.AnimData,
						bgcomponentposX + hbg.tail.offset[1],
						rowy + hbg.tail.offset[2]
					)
					animSetScale(hbg.tail.AnimData, hbg.tail.scale[1], hbg.tail.scale[2])
					animSetPalFX(hbg.tail.AnimData, hpalfx)
					animUpdate(hbg.tail.AnimData)
					if menu.itemname ~= 'commandlist' then
						animDraw(hbg.tail.AnimData)
					end

					-- Draw BG for Glyphs - stretch to the glyph run on x, start from tail pos. Only x is
					-- derived: y stays at the scale the dojo.def node declares, so the body matches the
					-- height of the head and tail it sits between.
					local bgstretch = hbg.scale[1]
					if bgsize[1] > 0 then bgstretch = (padding + totalglyphlength + padding)/bgsize[1] end
					bgtargetscale = {bgstretch, hbg.scale[2]}
					bgcomponentposX = (bgcomponentposX + bgtailwidth)
					-- Walk the run in order: each glyph starts where the ones before it ended, and the
					-- first starts at the body's left padding.
					for m = 1, #glyphrow.glyph, 1 do
						local gpoffset = 0
						if m > 1 then gpoffset = glyphrow.lengthOffset[m-1] end
						glyphrow.pos[m][1] = bgcomponentposX + padding + gpoffset
					end

					animReset(hbg.AnimData)
					animSetScale(hbg.AnimData, bgtargetscale[1], bgtargetscale[2])
					animSetPos(hbg.AnimData,
						bgcomponentposX + hbg.offset[1],
						rowy + hbg.offset[2]
					)
					animSetPalFX(hbg.AnimData, hpalfx)
					animUpdate(hbg.AnimData)
					animDraw(hbg.AnimData)

					-- Draw head
					bgcomponentposX = bgcomponentposX + (totalglyphlength + 2*padding)
					animReset(hbg.head.AnimData)
					animSetPos(hbg.head.AnimData,
						bgcomponentposX + hbg.head.offset[1] + glyphrow.alignOffset[1],
						rowy + hbg.head.offset[2]
					)
					animSetScale(hbg.head.AnimData, hbg.head.scale[1], hbg.head.scale[2])
					animSetPalFX(hbg.head.AnimData, hpalfx)
					animUpdate(hbg.head.AnimData)
					animDraw(hbg.head.AnimData)
				end
				local glyphline = tutorial.data.lessons[ct].steps[i].glyphline[layout]
				local glyphpalfx = tutorial.tutorial_mode[sub .. 'step'][layout].glyphs.palfx
				for m = 1, #glyphline.glyph, 1 do
					-- One anim per glyph per step category, so this step's palfx cannot bleed into the
					-- draws another category has already queued. Built in the motif's own coordinate
					-- space, so pull it into tutorial space before placing it.
					local g = f_glyphAnim(sub, glyphline.glyph[m])
					-- The movelist can carry tags that are not glyphs; those never got a position.
					if g ~= nil and glyphline.pos[m] ~= nil then
						animReset(g)
						animSetLocalcoord(g, tutorial.f_localcoord())
						animSetLayerno(g, f_clampLayerno(tutorial.tutorial_mode.glyphs[layout].layerno))
						animSetScale(g, glyphline.scale[m][1], glyphline.scale[m][2])
						-- pos already carries lessonsteps.pos plus glyphs.offset from the layout pass, so the row
						-- offset is all that is left to add here - adding glyphs.offset again would count it twice.
						animSetPos(g,
							glyphline.pos[m][1],
							glyphline.pos[m][2] + tempoffset[2]
						)
						animSetPalFX(g, {
							time = 1,
							add = glyphpalfx.add,
							mul = glyphpalfx.mul,
							sinadd = glyphpalfx.sinadd,
							invertall = glyphpalfx.invertall,
							color = glyphpalfx.color
						})
						animUpdate(g)
						if menu.itemname ~= 'commandlist' then
							animDraw(g)
						end
					end
				end
				accwidth = bgcomponentposX
			end
		elseif ct > #tutorial.data.lessons then
			-- All tutorial have been completed, draw the all clear and freeze the timer
			if not tutorial.data.allclear and tutorial.f_speedrunEnabled() and tutorial.data.runValid then
				tutorial.f_recordSpeedrun(roundTime() - tutorial.data.starttick)
				tutorial.data.runValid = false
			end
			if tutorial.draw.allclear ~= 0 then
				tutorial.f_tutorialSuccess('allclear', ct-1)
			end

			tutorial.data.allclear = true
			tutorial.draw.success = 0
			tutorial.draw.lessoncounter:update({text = tutorial.tutorial_mode.lessoncounter.allclear.text})
			tutorial.draw.lessoncounter:draw()

			if tutorial.data.displaytimers.totaltimer then
				local totaltimertext = tutorial.tutorial_mode.totallessontimer.text
				local m, s, x = f_timeConvert(tutorial.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				tutorial.draw.totallessontimer:update({text = totaltimertext})
				tutorial.draw.totallessontimer:draw()
			else
				--tutorial.draw.totallessontimer:update({text = "Timer Disabled"})
				--tutorial.draw.totallessontimer:draw()
			end
			if tutorial.data.displaytimers.lessontimer then
				local currenttimertext = tutorial.tutorial_mode.currentlessontimer.text
				local m, s, x = f_timeConvert(tutorial.data.lessons[ct-1].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				tutorial.draw.currentlessontimer:update({text = currenttimertext})
				tutorial.draw.currentlessontimer:draw()
			else
				--tutorial.draw.currentlessontimer:update({text = "Timer Disabled"})
				--tutorial.draw.currentlessontimer:draw()
			end
		end
	end
end


-- Nothing already in progress counts towards a fresh attempt: whatever state the player is in has
-- been spent, so the first no-hit step of one still needs an entry of its own.
function tutorial.f_spendState()
	if tutorial.data ~= nil then
		tutorial.data.nohitinstance = tutorial.data.stateinstance
	end
end

function tutorial.f_tutorialChecker(CheckIt)
	local nctms
	--This function sets dummy actions according to the character tutorial info and validates tutorial attempts
	--To help follow along, ct = current lesson, cts = current lesson step, ncts = next current lesson step
	-- Count the root's state entries whether or not a Lesson is accepting input, so the count does not
	-- depend on a banner or a fade being up. A move cancelled into itself - the whole point of a custom
	-- combo - keeps its state number, so a fall in state time is what marks that entry. Time stalls
	-- rather than falls while the match is paused, which is why this is a < and not a ~=.
	if CheckIt == 'root' then
		local sn, st = stateNo(), time()
		local newinstance = sn ~= tutorial.data.laststateno or (tutorial.data.laststatetime ~= nil and st < tutorial.data.laststatetime)
		if newinstance then
			tutorial.data.stateinstance = tutorial.data.stateinstance + 1
		end
		tutorial.data.laststateno = sn
		tutorial.data.laststatetime = st
		tutorial.f_trackEvents(newinstance)
	end
	if ct <= #tutorial.data.lessons and tutorial.draw.success == 0 and tutorial.draw.fade == 0 and tutorial.data.active then
	
			if tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == nil then
			tutorial.data.lessons[ct].steps[cts].hitcount[ctms] = -1
		end
	
		local helpercheck = false
		local projcheck = false
		local maincharcheck = false
		local statecheck = false
		local animcheck = true

		local attackerid = 0
		local projid = -1
		local source = 'player'
		local attackerstate = 'nil'
		local attackeranim = 'nil'

		player(2)
		if getHitVar('frame') then
			attackerid = getHitVar('playerId')
			projid = getHitVar('projid')
		player(1)
			if projid >= 0 then
				source = 'proj'
				-- Redirect to the owner before asking it about the projectile: numProjId would
				-- otherwise be answered by whoever the working char happened to be.
				if playerId(attackerid) and numProjId(projid) > 0 then
					attackeranim = projVar(projid, 0, 'anim')
				end
			else
				if playerId(attackerid) then
					attackerstate = stateNo()
					attackeranim = anim()
				end
			end
			-- Can uncomment this sec to debug helper/proj data
			--print("ID: " .. attackerid)
			--print("Source: " .. source)
			--print("ProjID: " .. projid)
			--print("State: " .. attackerstate)
			--print("Anim: " .. attackeranim)
		end
		player(1)
		local step = tutorial.data.lessons[ct].steps[cts]
		local newhit = comboCount() > tutorial.data.comboCounter
		-- A step that requires no connect is satisfied by its state alone, and that is true of every
		-- frame the player spends in it - one move would otherwise be consumed by a whole run of
		-- identical no-hit steps, one per frame. One entry into the state satisfies one of them.
		local newstate = tutorial.data.stateinstance ~= tutorial.data.nohitinstance
		local nohitok = step.hitcount[ctms] == 0 and newstate
		local isprojstep = step.isproj[ctms] or step.projid[ctms] ~= nil
		if CheckIt ~= nil and CheckIt ~= 'root' then
			helperIndex(CheckIt)
		end

		for i = 0, numProj() - 1 do
			local ptime, pid = projVar(-1, i, 'time'), projVar(-1, i, 'projid')
			if ptime ~= nil and pid ~= nil and ptime <= 1 then
				tutorial.data.projsource[pid] = stateNo()
			end
		end

		-- Check states and anims; iterate over 'or' operand if multiple states and/or anims are provided
		local launchstate = projid >= 0 and tutorial.data.projsource[projid] or nil
		local desiredstates = tutorial.data.lessons[ct].steps[cts].stateno[ctms]
		if desiredstates == nil or #desiredstates == 0 then
			statecheck = true
		else
			for k = 1, #desiredstates, 1 do
				if stateNo() == desiredstates[k] or attackerstate == desiredstates[k] or launchstate == desiredstates[k] then
					statecheck = true
					break
				end
			end
		end
		if tutorial.data.lessons[ct].steps[cts].animno[ctms] ~= nil then
			animcheck = false
			local desiredanims = tutorial.data.lessons[ct].steps[cts].animno[ctms]
			for k = 1, #desiredanims, 1 do
				if anim() == desiredanims[k] or attackeranim == desiredanims[k] then
					animcheck = true
					break
				end
			end
		end

		if tutorial.f_isEventStep(step, ctms) then
			-- Blocking, a blocked move or a dummy state: judged on events, not on the combo, so none
			-- of the combo-drop resets below apply.
			if CheckIt == 'root' then
				tutorial.f_checkEventStep(ct, cts, ctms, statecheck, animcheck)
			end
		else
		if (step.ishelper[ctms] and statecheck) and animcheck then
			-- A helper that fires a projectile scores the hit on the root, not on itself, so
			-- neither one's moveHit ever reports it. projid covers that case.
			helpercheck = ((moveHit() > 0 or projid >= 0) and newhit)
				or step.isthrow[ctms] or nohitok
			if tutorial.data.lessons[ct].steps[cts].validforvar ~= nil and helpercheck then
				for i = 1, #tutorial.data.lessons[ct].steps[cts].validforvar, 1 do
					if helpercheck then
						helpercheck = var(tutorial.data.lessons[ct].steps[cts].validforvar[i]) == tutorial.data.lessons[ct].steps[cts].validforval[i]
					end
				end
			end
		end

		if isprojstep then
			local wantids = step.projid[ctms]
			if step.hitcount[ctms] == 0 then
				-- A step that is not required to connect has no hit to key off, so state is all
				-- there is to match on - projid never comes into it.
				projcheck = statecheck and animcheck and newstate
			elseif wantids == nil then
				-- Legacy step with no projid: match stateno as before, but require a real hit.
				projcheck = statecheck and animcheck and projid >= 0 and newhit
			elseif CheckIt == 'root' and projid >= 0 and newhit then
				-- The ID is owner-independent, so match it once per frame in the root pass.
				-- Matching in the helper passes too would advance the same step again this tick.
				for k = 1, #wantids, 1 do
					if projid == wantids[k] then
						-- statecheck is free when the step declares no stateno, and is what
						-- separates two moves that share one ProjID when it does.
						projcheck = statecheck and animcheck
						break
					end
				end
			end
			if tutorial.data.lessons[ct].steps[cts].validforvar ~= nil and projcheck then
				for i = 1, #tutorial.data.lessons[ct].steps[cts].validforvar, 1 do
					if projcheck then
						projcheck = var(tutorial.data.lessons[ct].steps[cts].validforvar[i]) == tutorial.data.lessons[ct].steps[cts].validforval[i]
					end
				end
			end
		end

		maincharcheck = (statecheck and not(isprojstep) and not(step.ishelper[ctms]) and animcheck and ((moveHit() > 0 and newhit) or step.isthrow[ctms] or nohitok))
		if tutorial.data.lessons[ct].steps[cts].validforvar ~= nil and maincharcheck then
			for i = 1, #tutorial.data.lessons[ct].steps[cts].validforvar, 1 do
				if maincharcheck then
					maincharcheck = var(tutorial.data.lessons[ct].steps[cts].validforvar[i]) == tutorial.data.lessons[ct].steps[cts].validforval[i]
				end
			end
		end		

		if (maincharcheck or projcheck or helpercheck) and not tutorial.f_p2StateOk(step, ctms) then
			maincharcheck, projcheck, helpercheck = false, false, false
		end

		if tutorial.data.validfortickcount > 0 and paused() == false and pauseTime() == 0 and CheckIt == 'root' then
			tutorial.data.validfortickcount = tutorial.data.validfortickcount - 1
		end
		
		if maincharcheck or projcheck or helpercheck then
			if tutorial.data.lessons[ct].steps[cts].hitcount[ctms] >= 1 then
				if tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] == 0 then
					tutorial.data.lessons[ct].steps[cts].comboCountonstep[ctms] = comboCount()
				end
				if comboCount() - tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] == tutorial.data.lessons[ct].steps[cts].comboCountonstep[ctms] then
					tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] = tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] + 1
				end
			elseif tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == 0 then
				tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] = 0
				-- Matching is consuming for a no-hit step: 0 == 0 below always passes it. Spend the
				-- entry that satisfied it so the next one has to wait for its own.
				tutorial.data.nohitinstance = tutorial.data.stateinstance
			end

			if tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] then
				nctms = ctms + 1
				-- First, check that the microstep has passed
				if nctms >= 1 and ((comboCount() > 0 and (tutorial.data.lessons[ct].steps[cts].iscounterhit[ctms] and moveCountered() > 0) or not tutorial.data.lessons[ct].steps[cts].iscounterhit[ctms]) or tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == 0) then
					if nctms >= 1 and ((tutorial.data.lessons[ct].steps[cts].hitcount[ctms] > 1 and comboCount() == tutorial.data.lessons[ct].steps[cts].stephitscount[ctms] + tutorial.data.lessons[ct].steps[cts].comboCountonstep[ctms] - 1) or tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == 1 or tutorial.data.lessons[ct].steps[cts].hitcount[ctms] == 0) then
						tutorial.data.currentlessonmicrostep = nctms
						if tutorial.data.lessons[ct].steps[cts].validfortickcount[ctms] ~= nil then
							tutorial.data.validfortickcount = tutorial.data.lessons[ct].steps[cts].validfortickcount[ctms]
						else
							tutorial.data.validfortickcount = 0
						end
						tutorial.data.comboCounter = comboCount()
					elseif ((comboCount() == 0 and tutorial.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0) and tutorial.data.validfortickcount == 0) or (tutorial.data.validfortickcount > 0 and comboCount() > tutorial.data.comboCounter) then
						tutorial.f_resetAttempt(ct, cts, ctms)
					end
				end
				-- Next, if microstep is exceeded, go to next lesson step
				if tutorial.data.currentlessonmicrostep > tutorial.data.lessons[ct].steps[cts].numofmicrosteps then
					tutorial.data.currentlessonmicrostep = 1
					tutorial.data.currentlessonstep = cts + 1
					if tutorial.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0 and comboCount() == 0 and comboCount() == tutorial.data.comboCounter then
						tutorial.data.comboCounter = tutorial.data.comboCounter + 1
					else
						tutorial.data.comboCounter = comboCount()
					end	
					if tutorial.data.lessons[ct].steps[cts].validfortickcount[ctms] ~= nil then
						tutorial.data.validfortickcount = tutorial.data.lessons[ct].steps[cts].validfortickcount[ctms]
					else
						tutorial.data.validfortickcount = 0
					end
					if tutorial.data.currentlessonstep > #tutorial.data.lessons[ct].steps and tutorial.f_countRep(ct) then
						tutorial.f_completeLesson(ct)
					end
				end
			end
		elseif ((comboCount() == 0 and tutorial.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0) and tutorial.data.validfortickcount == 0) or (tutorial.data.validfortickcount > 0 and comboCount() > tutorial.data.comboCounter) then
			if (cts == 1 and ctms == 1) or tutorial.data.validfortickcount > 0 or tutorial.f_comboUnderway(step, ctms, cts) then
				tutorial.f_resetAttempt(ct, cts, ctms)
			else
				-- A hit step after steps that did not hit (block then punish, dash then attack): there is
				-- no combo to lose, so it waits for its hit. In Trials it reset on its first frame.
				tutorial.data.comboCounter = 0
			end
		end
		end -- event step / hit step
	end
	--If the lesson was completed successfully, draw the tutorial success
	if tutorial.draw.success > 0 then
		-- The Lesson the banner is for, not whichever one ct has moved on to.
		tutorial.f_tutorialSuccess('success', tutorial.data.successlesson or ct)
	elseif tutorial.data.tutorialPaused then
		-- Hold the fade and reposition where they are while the pause menu is open.
	elseif tutorial.draw.fade > 0 and (tutorial.tutorial_mode.tutorialresetonsuccess == true or tutorial.draw.fadetriggered) and CheckIt == 'root' then
		if tutorial.draw.fade < tutorial.draw.fadein + tutorial.draw.fadeout then
			tutorial.f_tutorialFade()
		else
			player(2)
			if stateNo() == 0 or tutorial.draw.fadetriggered then
							mapSet('_iksys_tutorialButtonJamDelay',tutorial.draw.fade)
				tutorial.f_tutorialFade()
			end
			player(1)
		end
	elseif f_checkKeyCombo(tutorial.tutorial_mode.lessonreset_buttonpress) and tutorial.draw.fade == 0 and tutorial.tutorial_mode.lessonreset.enabled and tutorial.data.currentlesson <= #tutorial.data.lessons then
		-- A reset starts the Lesson over, so the attempt's clock starts over with it. The run
		-- timer is left alone: a speedrun keeps counting across a reset, it is one run.
		tutorial.f_armTimers(tutorial.data.currentlesson)
		tutorial.draw.fadein = tutorial.tutorial_mode.fadein_time
		tutorial.draw.fadeout = tutorial.tutorial_mode.fadeout_time
		tutorial.draw.fade = tutorial.draw.fadein + tutorial.draw.fadeout
		tutorial.draw.fadetriggered = true
	-- Trials read `not CheckIt == 'root' or ...`, whose first half is always false. Only the
	-- fade test ever mattered - and must: clearing fadetriggered on a helper pass would cut a
	-- running reset fade short.
	elseif tutorial.draw.fade == 0 then
		tutorial.draw.fadetriggered = false
	end
		player(1)
end

-- A lesson's last step has passed and its repetitions are all made: record the clear, put the
-- banner up and move on. Shared by hit steps and event steps.
function tutorial.f_completeLesson(ct)
	tutorial.f_stopScript(2)
	-- A take that clears the lesson is complete: end it here rather than making the author pause.
	-- Only a take that has started counts; one still armed or waiting holds nothing yet.
	if tutorial.f_recording() and tutorial.rec.phase == 'recording' then
		tutorial.f_finishRecording(false)
	end
	-- Record the clear here, not from f_tutorialSuccess: that runs every frame the
	-- banner is up, by which point the drawer has already moved ct on to the next
	-- Lesson, so it would credit the clear to the wrong one. This block runs once.
	tutorial.f_recordClear(ct, roundTime() - tutorial.data.lessons[ct].starttick)
	tutorial.selectDirty = true
	-- The banner belongs to the Lesson that was just cleared, for as long as it is up.
	-- ct is not that Lesson after this frame, and the banner is what arms the next
	-- Lesson's clock, so remember which one earned it rather than reading ct again.
	tutorial.data.successlesson = ct
	-- If lesson step was last, go to next lesson and display success banner
	if tutorial.data.tutorialadvancement then
		tutorial.data.currentlesson = ct + 1
	end
	tutorial.f_spendState()
	tutorial.data.currentlessonstep = 1
	tutorial.data.comboCounter = 0
	if ct < #tutorial.data.lessons or (not tutorial.data.tutorialadvancement and ct == #tutorial.data.lessons) then
		if (tutorial.tutorial_mode.success_front_displaytime == -1) and (tutorial.tutorial_mode.success_bg_displaytime == -1) then
			tutorial.draw.success = math.max(animGetLength(tutorial.tutorial_mode.success.front.AnimData), animGetLength(tutorial.tutorial_mode.success.bg.AnimData), tutorial.tutorial_mode.success_text_displaytime)
		else
			tutorial.draw.success = math.max(tutorial.tutorial_mode.success_front_displaytime, tutorial.tutorial_mode.success_bg_displaytime, tutorial.tutorial_mode.success_text_displaytime)
		end
		if tutorial.tutorial_mode.tutorialresetonsuccess == true then
			tutorial.draw.fadein = tutorial.tutorial_mode.fadein_time
			tutorial.draw.fadeout = tutorial.tutorial_mode.fadeout_time
			tutorial.draw.fade = tutorial.draw.fadein + tutorial.draw.fadeout
		end
	end
	-- The banner is what normally releases the latch f_tutorialDummySetup keeps, so a motif that
	-- displays none has to release it here or the next Lesson runs on the previous one's dummy
	-- settings. The last Lesson is the All Clear's business: it leaves currentlesson past the end
	-- of the table, which f_tutorialDummySetup only survives once allclear is set.
	if tutorial.draw.success == 0 and tutorial.data.currentlesson <= #tutorial.data.lessons then
		tutorial.data.lessons[ct].active = false
		tutorial.data.active = false
	end
end

function tutorial.f_tutorialSuccess(successstring, index)
	-- This function is responsible for drawing the Success or All Clear banners after a lesson is completed successfully.
	player(2)
	mapSet('_iksys_tutorialDummyMode', 0)
	mapSet('_iksys_tutorialGuardMode', 0)
	mapSet('_iksys_tutorialButtonJam', 0)
	mapSet('_iksys_tutorialDistance', 0)
	mapSet('_iksys_tutorialDirection', 0)
	player(1)
	if not tutorial.data.lessons[index].complete or (successstring == "allclear" and not tutorial.data.allclear) then
		-- Play sound only once
		sndPlay(dojoSnd, tutorial.tutorial_mode[successstring .. '_snd'][1], tutorial.tutorial_mode[successstring .. '_snd'][2])
	end
	-- The banner text is centred on its element's pos rather than its own offset.
	local banner = tutorial.tutorial_mode[successstring]
	tutorial.draw[successstring .. '_text']:update({
		text = banner.text.text,
		x = banner.pos[1],
		y = banner.pos[2],
	})
	animUpdate(banner.bg.AnimData)
	animDraw(banner.bg.AnimData)
	tutorial.draw[successstring .. '_text']:draw()
	animUpdate(banner.front.AnimData)
	animDraw(banner.front.AnimData)
	tutorial.draw[successstring] = tutorial.draw[successstring] - 1
	tutorial.data.lessons[index].complete = true
	-- Only hand the frame back once the banner is done. Dropping active while it is still up lets
	-- f_tutorialDrawer run f_tutorialDummySetup for the Lesson that has already been advanced to, which
	-- latches that Lesson's active flag - and then the mapSets at the top of this function wipe the
	-- dummy mode, guard mode and button jam it just applied, with the latch spent so nothing applies
	-- them again. The dummy would stay parked in stand for the whole of the next Lesson.
	if tutorial.draw[successstring] <= 0 then
		tutorial.data.lessons[index].active = false
		tutorial.data.active = false
	end
	if not tutorial.data.tutorialadvancement then
		tutorial.data.lessons[index].starttick = roundTime()
	end
	if index ~= #tutorial.data.lessons then
		tutorial.data.lessons[index+1].starttick = roundTime()
	end
end

function tutorial.f_tutorialFade()
	local stagelocalcoordX = stageVar("stageinfo.localcoord.x")
	local stageboundleft = stageVar("bound.screenleft")
	local stageboundright = stageVar("bound.screenright")
	local dummyposx = stageVar("playerinfo.p2startx") / (stagelocalcoordX/320)
	local dummyposy = stageVar("playerinfo.p2starty") / (stagelocalcoordX/320)
	local playerposx = stageVar("playerinfo.p1startx") / (stagelocalcoordX/320)
	local playerposy = stageVar("playerinfo.p1starty") / (stagelocalcoordX/320)
	local leftbound = stageVar("camera.boundleft")
	local rightbound = stageVar("camera.boundright")
	local cameraPosX = 0
	local posx = 0
	local oppx = 0

	if tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[1] == nil then
	tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[1] = 0
	end
	if tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[2] == nil then
	tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[2] = 0
	end
	if tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[1] == nil then
	tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[1] = 0
	end
	if tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[2] == nil then
	tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[2] = 0
	end
	
	if tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'left-corner' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'left-corner' then
		cameraPosX = leftbound / (stagelocalcoordX/320)
		posx = - (stagelocalcoordX/2 - stageboundleft) / (stagelocalcoordX/320)
		if tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'close' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'close' then
			oppx = posx + 10
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'far' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'far' then
			oppx = posx + 260
		else --medium or nil
			oppx = posx + 130
		end
		if tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'left-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'right-corner' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'right-corner' then
		cameraPosX = rightbound / (stagelocalcoordX/320)
		posx = (stagelocalcoordX/2 - stageboundright) / (stagelocalcoordX/320)
		if tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'close' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'close' then
			oppx = posx - 10
		elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'far' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'far' then
			oppx = posx - 260
		else --medium or nil
			oppx = posx - 130
		end
		if tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'right-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'close' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'close' then
		dummyposx = 5
		playerposx = -5
	elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'medium' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'medium' then
		dummyposx = 65
		playerposx = -65
	elseif tutorial.data.lessons[tutorial.data.currentlesson].dummypos == 'far' or tutorial.data.lessons[tutorial.data.currentlesson].playerpos == 'far' then
		dummyposx = 130
		playerposx = -130
	end

	dummyposx = dummyposx + tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[1]
	dummyposy = dummyposy + tutorial.data.lessons[tutorial.data.currentlesson].dummyposoffset[2]
	playerposx = playerposx + tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[1]
	playerposy = playerposy + tutorial.data.lessons[tutorial.data.currentlesson].playerposoffset[2]
	
	mapSet('_iksys_tutorialCameraPosX', cameraPosX)
	mapSet('_iksys_tutorialDummyPosX', dummyposx)
	mapSet('_iksys_tutorialDummyPosY', dummyposy)
	mapSet('_iksys_tutorialPlayerPosX', playerposx)
	mapSet('_iksys_tutorialPlayerPosY', playerposy)
	
	-- This function is responsible for fadein/fadeout if tutorialresetonsuccess is set to true.
	if tutorial.draw.fadeout > 0 then
		if not fadeActive() then
			tutorial.draw.fadeoutData = fadeNew({
			time = tutorial.draw.fadeout,
			color = {tutorial.tutorial_mode.fadeout.col[1],
			tutorial.tutorial_mode.fadeout.col[2],
			tutorial.tutorial_mode.fadeout.col[3]},
			anim = tutorial.tutorial_mode.fadeout.anim
			})
		fadeOutInit(tutorial.draw.fadeoutData)
		end
		tutorial.draw.fadeout = tutorial.draw.fadeout - 1

	elseif tutorial.draw.fadein > 0 then
		if not fadeActive() then
			mapSet('_iksys_tutorialReposition', 1)
			tutorial.draw.fadeinData = fadeNew({
			time = tutorial.draw.fadein,
			color = {tutorial.tutorial_mode.fadein.col[1],
			tutorial.tutorial_mode.fadein.col[2],
			tutorial.tutorial_mode.fadein.col[3]},
			anim = tutorial.tutorial_mode.fadein.anim
			})
		fadeInInit(tutorial.draw.fadeinData)
	end
		tutorial.draw.fadein = tutorial.draw.fadein - 1
	end

	tutorial.draw.fade = tutorial.draw.fade - 1
	if tutorial.draw.fade == 0 then
			mapSet('_iksys_tutorialCameraReset', 1)
end
end

function tutorial.f_tutorialSelectScreen()
-- Grays out portraits on the select screen for characters the current track has no lessons for.
-- Which characters those are depends on the track (Character Guides grays everyone without a lesson
-- file of their own), so the cells are redone whenever the track changes, not only on entering
-- or leaving the mode. selectScreenPalMod is 'normal' or the track the grid was last grayed for.
	local want = tutorial.f_inMode() and tutorial.track or 'normal'
	if want == tutorial.selectScreenPalMod then
		return
	end
	tutorial.selectScreenPalMod = want
	local tm = tutorial.tutorial_mode
	local dark = {
		time = -1,
		add = tm.selscreenpalfx_add,
		mul = tm.selscreenpalfx_mul,
		sinadd = tm.selscreenpalfx_sinadd,
		invertall = tm.selscreenpalfx_invertall,
		color = tm.selscreenpalfx_color,
	}
	local normal = {time = -1, add = {0,0,0}, mul = {256,256,256}, sinadd = {0,0,0}, invertall = 0, color = 256}
	for row = 1, motif.select_info.rows do
		for col = 1, motif.select_info.columns do
			local cellIndex = (row - 1) * motif.select_info.columns + col
			local t = start.t_grid[row][col]
			if t.skip ~= 1 then
				local charData = start.f_selGrid(cellIndex)
				-- The random cell is left as the screenpack draws it.
				if charData and charData.char_ref ~= nil and charData.hidden == 0 and charData.char ~= 'randomselect' then
					-- Only cells whose state changes are touched, so a cell never grayed keeps its own palfx.
					local grayed = want ~= 'normal' and not tutorial.f_hasLessons(charData)
					if grayed ~= (charData.tutorialGrayed == true) then
						charData.tutorialGrayed = grayed
						animSetPalFX(charData.cell_data, grayed and dark or normal)
						animUpdate(charData.cell_data)
					end
				end
			end
		end
	end
end

--;===========================================================
--; Lesson select view
--;===========================================================
-- The profile in force's own pause menu section: [Trials Pause Menu] or [Tutorial Pause Menu].
function tutorial.f_pauseSection(p)
	p = p or tutorial.profile
	if motif.pause_menu == nil then
		return nil
	end
	return motif.pause_menu[p.pauseSection]
end

local function f_pauseMenuValues()
	local sec = tutorial.f_pauseSection()
	if sec ~= nil and type(sec.menu) == 'table' then
		return sec.menu.valuename or {}
	end
	return {}
end

local t_difficultyDefault = {
	all = 'All',
	beginner = 'Beginner',
	intermediate = 'Intermediate',
	advanced = 'Advanced',
	expert = 'Expert',
	none = 'Other',
}

-- Screenpacks rename or translate the tier labels through menu.valuename.tutorialdifficulty_*.
function tutorial.f_difficultyName(d)
	local key = d
	if key == nil or key == '' or key == 'other' then
		key = 'none'
	end
	local pmv = f_pauseMenuValues()
	return pmv['tutorialdifficulty_' .. key] or t_difficultyDefault[key] or key
end

-- The name a filter is shown under: a chapter's own name, or a difficulty tier's label.
-- menu.valuename.tutorialchapter_<id> overrides a chapter's name, for translations.
function tutorial.f_catName(cat)
	if cat == 'all' or cat == 'other' or cat == nil or cat == '' or tutorial.t_difficultyIndex[cat] then
		return tutorial.f_difficultyName(cat)
	end
	local pmv = f_pauseMenuValues()
	return pmv['tutorialchapter_' .. cat] or tutorial.chapterNames[cat] or cat
end

function tutorial.f_speedrunEnabled()
	return menu.tutorialspeedrun == 1 and not tutorial.f_demoOnly()
end

-- What the list is filtered by. Chapters when any lesson names one; difficulty when none does
-- but some declare a tier, as Trials Mode always did; nothing at all otherwise.
function tutorial.f_filterMode(arr)
	if arr == nil then
		return 'none'
	end
	local diff = false
	for i = 1, #arr, 1 do
		if arr[i].chapter ~= nil and arr[i].chapter ~= '' then
			return 'chapter'
		end
		if arr[i].difficulty ~= '' then
			diff = true
		end
	end
	return diff and 'difficulty' or 'none'
end

-- The filter a lesson falls under in the given mode.
function tutorial.f_lessonCat(lesson, mode)
	local c = ''
	if mode == 'chapter' then
		c = lesson.chapter or ''
	elseif mode == 'difficulty' then
		c = lesson.difficulty or ''
	end
	if c == '' then
		return 'other'
	end
	return c
end

function tutorial.f_filterOrder(arr)
	local t = {'all'}
	arr = arr or (tutorial.data ~= nil and tutorial.data.lessons or nil)
	local mode = tutorial.f_filterMode(arr)
	if mode == 'none' then
		return t
	end
	local has, other = {}, false
	if mode == 'chapter' then
		-- In the order chapters first come up: system lessons are listed first, so their chapters lead.
		for i = 1, #arr, 1 do
			local c = tutorial.f_lessonCat(arr[i], mode)
			if c == 'other' then
				other = true
			elseif not has[c] then
				has[c] = true
				t[#t + 1] = c
			end
		end
	else
		for i = 1, #arr, 1 do
			local c = tutorial.f_lessonCat(arr[i], mode)
			has[c] = true
		end
		for _, d in ipairs(tutorial.t_difficulty) do
			if has[d] then
				t[#t + 1] = d
			end
		end
		other = has.other
	end
	if other then
		t[#t + 1] = 'other'
	end
	return t
end

local function f_inFilter(arr, i, filter, mode)
	if filter == 'all' then
		return true
	end
	return tutorial.f_lessonCat(arr[i], mode or tutorial.f_filterMode(arr)) == filter
end

-- A gated file's lessons open one at a time: a lesson is locked until the one before it from the
-- same file (as the list stands, after grooves have thinned it) has been cleared.
function tutorial.f_isLocked(index, arr, ref)
	arr = arr or (tutorial.data ~= nil and tutorial.data.lessons or nil)
	-- Nothing is ever cleared in demonstrations-only, so nothing could ever open.
	if arr == nil or arr[index] == nil or not arr[index].gated or tutorial.f_demoOnly() then
		return false
	end
	for i = index - 1, 1, -1 do
		if arr[i].file == arr[index].file then
			local rec = tutorial.f_lessonRecord(i, arr, ref)
			return rec == nil or not rec.cleared
		end
	end
	return false
end

-- %s is the cleared tally (3/5), %p the percentage cleared.
function tutorial.f_headerValue(fmt, entry)
	return (fmt:gsub('%%s', entry.value or ''):gsub('%%p', tostring(entry.percent or 0)))
end

function tutorial.f_buildSelectItems(arr, ref, withTail)
	local items = {}
	arr = arr or (tutorial.data ~= nil and tutorial.data.lessons or nil)
	if arr == nil then
		return items
	end
	if withTail == nil then
		withTail = true
	end
	local order = tutorial.f_filterOrder(arr)
	local filter = tutorial.selectFilter or 'all'
	local known = false
	for _, v in ipairs(order) do
		if v == filter then
			known = true
			break
		end
	end
	if not known then
		filter = 'all'
		tutorial.selectFilter = filter
	end
	local mode = tutorial.f_filterMode(arr)
	local tier = {}
	local entries = {}
	for _, f in ipairs(order) do
		local n, done = 0, 0
		for i = 1, #arr, 1 do
			if f_inFilter(arr, i, f, mode) then
				n = n + 1
				local rec = tutorial.f_lessonRecord(i, arr, ref)
				if rec ~= nil and rec.cleared then
					done = done + 1
				end
				if f == filter then
					tier[#tier + 1] = i
				end
			end
		end
		entries[#entries + 1] = {cat = f, label = tutorial.f_catName(f), value = done .. '/' .. n,
			percent = n > 0 and math.floor(done * 100 / n) or 0}
	end

	local label = tutorial.f_catName(filter)
	if #order > 1 and tutorial.tutorial_mode.tutorialmenu.headerdisplay ~= 'sidebyside' then
		-- Laid out side by side the other filters are visible, so the arrows earn nothing.
		label = '< ' .. label .. ' >'
	end
	tutorial.selectHeader = {label = label, cat = filter, entries = entries}
	for _, e in ipairs(entries) do
		if e.cat == filter then
			tutorial.selectHeader.value = e.value
			tutorial.selectHeader.percent = e.percent
		end
	end
	for _, i in ipairs(tier) do
		items[#items + 1] = {
			itemname = 'tutorialentry',
			paramname = 'tutorialentry',
			displayname = arr[i].name,
			selected = tutorial.data ~= nil and i == tutorial.data.currentlesson,
			lesson = i,
			locked = tutorial.f_isLocked(i, arr, ref),
		}
	end
	if withTail and tutorial.listTail ~= nil then
		for _, item in ipairs(tutorial.listTail) do
			items[#items + 1] = item
		end
	end
	if #items == 0 then
		items[1] = {itemname = 'back', paramname = 'back', displayname = 'Back', vardisplay = '', selected = false}
	end
	return items
end

-- Where the cursor starts: the first Lesson the player has yet to clear, so re-entering a character
-- picks up where they left off.
function tutorial.f_firstUncleared(items, arr, ref)
	local first = nil
	for i, v in ipairs(items) do
		if v.lesson ~= nil then
			if first == nil then
				first = i
			end
			local rec = tutorial.f_lessonRecord(v.lesson, arr, ref)
			if (rec == nil or not rec.cleared) and not v.locked then
				return i
			end
		end
	end
	return first or 1
end

-- Rebuilt whenever progress changes, so a clear shows up on the row immediately.
function tutorial.f_refreshSelect()
	if tutorial.data == nil or not tutorial.data.tutorialInitialized then
		return
	end
	local items = tutorial.f_buildSelectItems()
	for _, node in ipairs(tutorial.f_selectNodes()) do
		node.items = items
		if node.item > #items then
			node.item = #items
		end
	end
	tutorial.selectDirty = false
end

-- The two views onto the same list: the Pause menu's Tutorial List and the match-load screen.
function tutorial.f_selectNodes()
	local t = {}
	if type(tutorial.listNode) == 'table' then t[#t + 1] = tutorial.listNode end
	if type(tutorial.select) == 'table' then t[#t + 1] = tutorial.select end
	return t
end

-- After a filter change both views are showing a different list, so both cursors go back to the
-- first Lesson that filter still leaves uncleared.
function tutorial.f_resetSelectCursors()
	for _, node in ipairs(tutorial.f_selectNodes()) do
		if type(node.items) == 'table' then
			node.item = tutorial.f_firstUncleared(node.items)
			node.first = 1
		end
	end
end

-- Left and right step through the filters. Returns whether anything moved, so the caller knows
-- whether to make a sound.
function tutorial.f_cycleFilterFor(node, dir)
	local order = tutorial.f_filterOrder(node.tutorial)
	if #order < 2 then
		return false
	end
	local idx = 1
	for i, v in ipairs(order) do
		if v == (tutorial.selectFilter or 'all') then
			idx = i
			break
		end
	end
	tutorial.selectFilter = order[(idx - 1 + dir) % #order + 1]
	node.items = tutorial.f_buildSelectItems(node.tutorial, node.ref, false)
	node.item = tutorial.f_firstUncleared(node.items, node.tutorial, node.ref)
	node.first = 1
	return true
end

function tutorial.f_cycleFilter(dir)
	local order = tutorial.f_filterOrder()
	if #order < 2 then
		return false
	end
	local idx = 1
	for i, v in ipairs(order) do
		if v == (tutorial.selectFilter or 'all') then
			idx = i
			break
		end
	end
	tutorial.selectFilter = order[(idx - 1 + dir) % #order + 1]
	tutorial.f_refreshSelect()
	tutorial.f_resetSelectCursors()
	return true
end

-- Holds both players still while the view is up. The value is a countdown dojo.zss ticks down,
-- so the hold releases itself if this stops being called every frame.
function tutorial.f_menuHold(on)
	local v = 0
	if on then
		v = 10
	end
	player(2)
	mapSet('_iksys_tutorialMenuOpen', v)
	player(1)
	mapSet('_iksys_tutorialMenuOpen', v)
end

-- tutoriallistdisplay decides when, if ever, the player is asked which Lesson to play:
--   select - between stage select and the fight loading
--   start  - once the match is up, over the frozen pair
--   off    - never; the match starts on the first Lesson
function tutorial.f_listDisplay()
	local v = tostring(tutorial.tutorial_mode.tutoriallistdisplay or 'start'):lower()
	if v == 'select' or v == 'off' then
		return v
	end
	return 'start'
end

-- Whether any of the character's Tutorial are gated on P1's vars. Those values do not exist until the
-- match is up, so a character with even one of them cannot be asked which Lesson to play beforehand -
-- the pre-fight list would offer every groove's Tutorial and most of them would be gone by roundState 2.
-- Reads the parsed data, never tutorial.data.lessons, which f_tutorialBuilder has already thinned.
function tutorial.f_hasVarGatedTutorial(arr)
	if arr == nil then
		if type(start.p) ~= 'table' or type(start.p[1]) ~= 'table'
			or type(start.p[1].t_selected) ~= 'table' or start.p[1].t_selected[1] == nil then
			return false
		end
		local ok, charData = pcall(start.f_getCharData, start.p[1].t_selected[1].ref)
		if not ok or type(charData) ~= 'table' then
			return false
		end
		arr = tutorial.f_lessonsFor(charData)
	end
	if type(arr) ~= 'table' then
		return false
	end
	for i = 1, #arr, 1 do
		-- The same test f_tutorialBuilder thins by, so the two cannot disagree about what counts as gated.
		if type(arr[i].showforvar) == 'table' and arr[i].showforvar[1] ~= nil then
			return true
		end
	end
	return false
end

function tutorial.f_openSelect()
	if tutorial.select == nil or tutorial.data == nil or #tutorial.data.lessons == 0 then
		return
	end
	tutorial.f_refreshSelect()
	tutorial.select.item = tutorial.f_firstUncleared(tutorial.select.items)
	tutorial.select.first = 1
	tutorial.select.openDelay = 10
	local it = tutorial.select.items[tutorial.select.item]
	if it ~= nil and it.lesson ~= nil then
		tutorial.data.currentlesson = it.lesson
	end
	tutorial.select.open = true
	tutorial.f_menuHold(true)
	local sec = tutorial.f_selectSection()
	if sec ~= nil then
		sndPlay(motif.Snd, sec.enter.snd[1], sec.enter.snd[2])
	end
end

function tutorial.f_armTimers(index, wholeRun)
	if tutorial.data == nil then
		return
	end
	local now = roundTime()
	if wholeRun then
		tutorial.data.starttick = now
		tutorial.data.elapsedtime = 0
	end
	if tutorial.data.lessons[index] ~= nil then
		tutorial.data.lessons[index].starttick = now
	end
end

function tutorial.f_closeSelect()
	if tutorial.select ~= nil then
		tutorial.select.open = false
	end
	tutorial.f_menuHold(false)
	-- Time spent choosing belongs to nobody's run.
	if tutorial.data ~= nil then
		tutorial.f_armTimers(tutorial.data.currentlesson, true)
	end
end

function tutorial.f_selectSection()
	if motif.pause_menu == nil then
		return nil
	end
	return tutorial.f_pauseSection() or motif.pause_menu.pause_menu
end

--;===========================================================
--; Lesson select menu - drawing
--;===========================================================
local function f_catState(base, cat, active, key)
	if active then
		local c = base[cat]
		if type(c) == 'table' and type(c.active) == 'table' and type(c.active[key]) == 'table' then
			return c.active[key], cat .. '.active'
		end
		if type(base.active) == 'table' and type(base.active[key]) == 'table' then
			return base.active[key], 'active'
		end
	end
	local c = base[cat]
	if type(c) == 'table' and type(c[key]) == 'table' then
		return c[key], cat
	end
	return f_node(base, key), ''
end

local function f_cat(base, cat, ...)
	local node = base[cat]
	for i = 1, select('#', ...) do
		if type(node) ~= 'table' then
			node = nil
			break
		end
		node = node[select(i, ...)]
	end
	if type(node) == 'table' then
		return node, cat
	end
	return f_node(base, ...), ''
end

-- Anims are built at the origin by t_elems and placed here, the same way the step backgrounds are.
local function f_menuAnim(node, x, y)
	if type(node) ~= 'table' or node.AnimData == nil then
		return
	end
	animSetPos(node.AnimData, x + node.offset[1], y + node.offset[2])
	animUpdate(node.AnimData)
	animDraw(node.AnimData)
end

-- Screenpacks write booleans either way round; the def parser hands some of them back as strings.
local function f_menuOn(v)
	return v == true or tostring(v):lower() == 'true'
end

-- A filled rect from an overlay node, its window read as x1,y1,x2,y2 relative to x,y. Used both for
-- the sheet dimming the match behind the menu (drawn at the origin) and for the bar under the active
-- row (drawn at that row). Localcoord goes on before the window, since the rect scales the window as
-- it takes it. A window with no area is nothing to draw.
local function f_menuRect(node, x, y)
	if type(node) ~= 'table' or not f_menuOn(node.visible) then
		return
	end
	local w = node.window
	if type(w) ~= 'table' or w[1] == w[3] or w[2] == w[4] then
		return
	end
	if node.RectData == nil then
		node.RectData = rectNew()
	end
	rectSetLocalcoord(node.RectData, tutorial.f_localcoord())
	rectSetColor(node.RectData, node.col[1], node.col[2], node.col[3])
	rectSetAlpha(node.RectData, node.alpha[1], node.alpha[2])
	rectSetLayerno(node.RectData, f_clampLayerno(node.layerno))
	rectSetWindow(node.RectData, x + w[1], y + w[2], x + w[3], y + w[4])
	rectDraw(node.RectData)
end

-- Whether the author actually named art for this element. A sprite or anim wins; otherwise the
-- element's .text label is drawn in its place, which is how the CLEAR label is replaced by art.
local function f_hasArt(node)
	if type(node) ~= 'table' then
		return false
	end
	if type(node.anim) == 'number' and node.anim >= 0 then
		return true
	end
	if type(node.spr) == 'string' then
		return node.spr ~= ''
	end
	if type(node.spr) == 'table' then
		return #node.spr > 0
	end
	return false
end

-- Text objects for the styles a category actually uses, made on first sight. Pre-allocating every
-- category against every state against every visible row would be 15 pools for a menu that draws
-- one style per row.
local function f_rowText(style, cat, row, node)
	local d = tutorial.menuDraw
	local key = style .. '.' .. cat
	if d.rows[key] == nil then
		d.rows[key] = {}
	end
	if d.rows[key][row] == nil then
		d.rows[key][row] = f_newText(node)
	end
	return d.rows[key][row]
end

local function f_menuText(obj, node, x, y, str)
	obj:update({x = x + node.offset[1], y = y + node.offset[2], text = str})
	obj:draw()
end

-- An element drawn as art if the author named any, and as its .text label otherwise. The
-- clear marker and the scroll arrows both work this way.
local function f_menuMark(node, obj, x, y)
	if f_hasArt(node) then
		f_menuAnim(node, x, y)
	elseif node.text ~= '' then
		f_menuText(obj, node, x, y, node.text)
	end
end

-- Keeps the cursor inside the window, and the window inside the list.
local function f_scrollTo(node, visible, total)
	if node.first == nil then
		node.first = 1
	end
	if node.item < node.first then
		node.first = node.item
	elseif node.item > node.first + visible - 1 then
		node.first = node.item - visible + 1
	end
	local maxFirst = math.max(1, total - visible + 1)
	if node.first > maxFirst then
		node.first = maxFirst
	end
	if node.first < 1 then
		node.first = 1
	end
end

function tutorial.f_selectDraw(node)
	-- Shown both before the fight, on the motif's aspect, and over a live match, on the stage's.
	tutorial.f_syncAspect()
	local m = tutorial.tutorial_mode.tutorialmenu
	local d = tutorial.menuDraw
	local t = node.items
	local visible = math.min(m.visibleitems, #t)
	f_scrollTo(node, visible, #t)
	-- Dim whatever is behind the menu. Its window is already in screen space, so it draws at 0,0.
	f_menuRect(m.overlay, 0, 0)
	f_menuAnim(m.bg, m.pos[1], m.pos[2])
	if m.title.text ~= '' then
		f_menuText(d.title, m.title, m.pos[1], m.pos[2], m.title.text)
	end
	-- The filter banner is pinned above the list: it does not scroll with the rows.
	local h = tutorial.selectHeader
	if h ~= nil then
		local hx, hy = m.pos[1] + m.header.offset[1], m.pos[2] + m.header.offset[2]
		if m.headerdisplay == 'sidebyside' then
			-- Every filter on one line, the one on show wearing the active elements.
			for k, e in ipairs(h.entries) do
				local ex = hx + m.header.spacing[1] * (k - 1)
				local ey = hy + m.header.spacing[2] * (k - 1)
				local on = e.cat == h.cat
				f_menuAnim((f_catState(m.header, e.cat, on, 'bg')), ex, ey)
				local txt, tk = f_catState(m.header, e.cat, on, 'text')
				f_menuText(f_rowText('header', tk .. e.cat, k, txt), txt, ex, ey, e.label)
				local val, vk = f_catState(m.header, e.cat, on, 'value')
				if val.text ~= '' then
					f_menuText(f_rowText('headervalue', vk .. e.cat, k, val), val, ex, ey,
						tutorial.f_headerValue(val.text, e))
				end
			end
		else
			local cat = h.cat or 'all'
			f_menuAnim((f_catState(m.header, cat, true, 'bg')), hx, hy)
			local txt, tk = f_catState(m.header, cat, true, 'text')
			f_menuText(f_rowText('header', tk, 1, txt), txt, hx, hy, h.label)
			local val, vk = f_catState(m.header, cat, true, 'value')
			if val.text ~= '' then
				f_menuText(f_rowText('headervalue', vk, 1, val), val, hx, hy, tutorial.f_headerValue(val.text, h))
			end
		end
	end
	for row = 0, visible - 1, 1 do
		local i = node.first + row
		local item = t[i]
		if item == nil then
			break
		end
		local x = m.pos[1] + m.spacing[1] * row
		local y = m.pos[2] + m.spacing[2] * row
		local active = i == node.item
		local cat = 'other'
		if item.lesson ~= nil then
			local arr = node.tutorial or (tutorial.data ~= nil and tutorial.data.lessons or nil)
			if arr ~= nil and arr[item.lesson] ~= nil then
				cat = tutorial.f_lessonCat(arr[item.lesson], tutorial.f_filterMode(arr))
			end
		end
		if active then
			-- Under the row background, so a screenpack that draws art there still covers it.
			f_menuRect(f_cat(m.item, cat, 'active', 'overlay'), x, y)
			f_menuAnim(f_cat(m.item, cat, 'active', 'bg'), x, y)
			f_menuAnim(m.cursor, x, y)
		else
			f_menuAnim(f_cat(m.item, cat, 'bg'), x, y)
		end
		local style, cfg, ck = 'name', nil, nil
		if item.locked then
			style = 'namelocked'
			cfg, ck = f_cat(m.item, cat, 'locked', 'text')
		elseif item.selected then
			style = 'nameselected'
			cfg, ck = f_cat(m.item, cat, 'selected', 'text')
		elseif active then
			style = 'nameactive'
			cfg, ck = f_cat(m.item, cat, 'active', 'text')
		else
			cfg, ck = f_cat(m.item, cat, 'text')
		end
		f_menuText(f_rowText(style, ck, row + 1, cfg), cfg, x, y, item.displayname)
		if item.lesson ~= nil then
			local rec = tutorial.f_lessonRecord(item.lesson, node.tutorial, node.ref)
			local cleared = rec ~= nil and rec.cleared
			local st = cleared and m.status.cleared or m.status.uncleared
			local obj2 = cleared and d.cleared[row + 1] or d.uncleared[row + 1]
			if item.locked then
				st, obj2 = m.status.locked, d.locked[row + 1]
			end
			f_menuMark(st, obj2, x + m.status.offset[1], y + m.status.offset[2])
			if cleared and rec.besttime ~= nil and m.besttime.text ~= '' then
				local mm, ss, xx = f_timeConvert(rec.besttime)
				f_menuText(d.besttime[row + 1], m.besttime, x, y,
					m.besttime.text:gsub('%%s', mm .. ':' .. ss .. ':' .. xx))
			end
		end
	end
	if node.first > 1 then
		f_menuMark(m.arrow.up, d.arrowup, m.pos[1], m.pos[2])
	end
	if node.first + visible - 1 < #t then
		f_menuMark(m.arrow.down, d.arrowdown, m.pos[1], m.pos[2])
	end
	f_menuAnim(m.front, m.pos[1], m.pos[2])
end

--;===========================================================
--; Lesson select menu - input
--;===========================================================
local function f_matchHeld(keys)
	local best = 0
	if type(keys) ~= 'table' then
		keys = {keys}
	end
	for _, k in ipairs(keys) do
		local ok, held = pcall(inputTime, k)
		if ok and type(held) == 'number' and held > best then
			best = held
		end
	end
	return best
end

local function f_matchPressed(node, name, keys, autorepeat)
	if node.inputHeld == nil then
		node.inputHeld = {}
	end
	local held = f_matchHeld(keys)
	local was = node.inputHeld[name] or 0
	node.inputHeld[name] = held
	if held > 0 and was <= 0 then
		return true
	end
	if autorepeat and held > 20 and (held - 20) % 6 == 0 then
		return true
	end
	return false
end

local function f_selectInput(node, standalone, sec)
	local dir, filter, done, cancel = 0, 0, false, false
	if standalone then
		player(1)
		if f_matchPressed(node, 'next', sec.menu.next.key, true) then
			dir = 1
		elseif f_matchPressed(node, 'previous', sec.menu.previous.key, true) then
			dir = -1
		end
		if f_matchPressed(node, 'add', sec.menu.add.key, true) then
			filter = 1
		elseif f_matchPressed(node, 'subtract', sec.menu.subtract.key, true) then
			filter = -1
		end
		done = f_matchPressed(node, 'done', sec.menu.done.key, false)
	else
		if getInput(-1, sec.menu.next.key) then
			dir = 1
		elseif getInput(-1, sec.menu.previous.key) then
			dir = -1
		end
		if getInput(-1, sec.menu.add.key) then
			filter = 1
		elseif getInput(-1, sec.menu.subtract.key) then
			filter = -1
		end
		done = getInput(-1, sec.menu.done.key)
		cancel = esc() or getInput(-1, sec.menu.cancel.key)
	end
	return dir, filter, done, cancel
end

local function f_moveCursor(node, dir)
	local n = #node.items
	if n < 2 then
		return false
	end
	local i = node.item + dir
	if i > n then
		i = 1
	elseif i < 1 then
		i = n
	end
	node.item = i
	return true
end

-- standalone: driven from the mode's own loop at match load, with no pause menu around it.
function tutorial.f_selectLoop(node, standalone)
	local sec = tutorial.f_selectSection()
	if sec == nil or tutorial.data == nil or tutorial.menuDraw == nil or node.items == nil then
		return
	end
	if not standalone then
		hook.run("menu.menu.loop")
	end
	if standalone then
		tutorial.f_menuHold(true)
	end
	if tutorial.selectDirty then
		tutorial.f_refreshSelect()
	end
	local t = node.items
	if #t == 0 then
		return
	end
	node.item = math.max(1, math.min(node.item, #t))
	for _, item in ipairs(t) do
		if item.lesson ~= nil then
			item.selected = item.lesson == tutorial.data.currentlesson
		end
	end
	tutorial.f_selectDraw(node)
	-- Sample input every frame, including the ones we go on to ignore, so a button still held from
	-- whatever opened the view reads as held rather than as a fresh press once we start listening.
	local dir, filter, done, cancel = f_selectInput(node, standalone, sec)
	-- Draw during fades, but don't act on input until they finish.
	if fadeActive() then
		return
	end
	if not standalone and (not main.pauseMenuActive or menu.pauseExitDelay >= 0) then
		return
	end
	if standalone and node.openDelay ~= nil and node.openDelay > 0 then
		node.openDelay = node.openDelay - 1
		return
	end
	-- Left and right change which difficulty the list is showing, wherever the cursor happens to be.
	if filter ~= 0 and tutorial.f_cycleFilter(filter) then
		sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
		return
	end
	if dir ~= 0 and f_moveCursor(node, dir) then
		sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
	end
	-- Cancel only has somewhere to go inside the pause menu. On the match-load screen the way out
	-- is to pick a Lesson, or the list's own Back item.
	if cancel then
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		menu.currentMenu[1] = menu.currentMenu[2]
		return
	end
	local it = t[node.item]
	if it == nil or not done then
		return
	end
	if it.locked then
		-- Not open yet: the lesson before it in its file has to be cleared first.
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
	elseif it.lesson ~= nil then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		tutorial.f_gotoLesson(it.lesson, false, standalone)
	elseif standalone then
		-- the section's own tail items, Back among them: nothing to go back to out here, so close.
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		tutorial.f_closeSelect()
	else
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		menu.currentMenu[1] = menu.currentMenu[2]
	end
end

--;===========================================================
--; Lesson select menu - before the fight
--;===========================================================
-- What the select screen had settled on when the pre-fight list opened. f_selectReset hands every
-- side fresh tables rather than clearing the old ones, so holding on to these is enough to put the
-- picks back after it runs.
local function f_snapshotSelect()
	local snap = {}
	for side = 1, 2 do
		local p = start.p[side]
		snap[side] = {
			t_selected = p.t_selected,
			t_selTemp = p.t_selTemp,
			t_selCmd = p.t_selCmd,
			numChars = p.numChars,
			teamEnd = p.teamEnd,
			selEnd = p.selEnd,
		}
	end
	return snap
end

-- Cancel out of the pre-fight list goes back one step rather than all the way to P1's pick: to stage
-- select when there is one, otherwise to P2's pick. Runs off the start.f_selectReset hook, after the
-- reset f_selectMode does on the way back to the select screen. The stage cursor survives that
-- reset on its own and stageEnd is cleared by it, so the stage list reopens on the stage picked.
function tutorial.f_restoreSelect()
	local snap = tutorial.backToSelectSnap
	tutorial.backToSelectSnap = nil
	if snap == nil or not tutorial.f_inMode() then
		return
	end
	local stageStep = main.stageMenu
	-- With no stage select, the step before the list is P2's pick - but only if P2 was picked at all.
	-- A forced P2 means the step before is P1's pick, which is what the plain reset already gives.
	local p2Step = not stageStep and main.selectMenu[2] and main.forceChar[2] == nil and #snap[2].t_selected > 0
	if not stageStep and not p2Step then
		return
	end
	for side = 1, 2 do
		local p, s = start.p[side], snap[side]
		p.numChars = s.numChars
		p.teamEnd = s.teamEnd
		if side == 2 and p2Step then
			p.selEnd = false
			p.t_selected = {}
			p.t_selTemp = {}
			p.t_selCmd = {}
			for _, v in ipairs(s.t_selCmd) do
				table.insert(p.t_selCmd, {cmd = v.cmd, player = v.player, selectState = 0})
			end
		else
			p.selEnd = s.selEnd
			p.t_selected = s.t_selected
			p.t_selTemp = s.t_selTemp
			p.t_selCmd = s.t_selCmd
		end
	end
end

-- The lesson list shown outside a match: before the fight in Character Guides and Combined, and as
-- the Game Tutorial's own menu. Returns the display name of the lesson picked, or nil on cancel.
-- The second return is true when the list had nothing in it to show, and so was never opened.
function tutorial.f_lessonListLoop(lessons, ref, sec)
	tutorial.selectFilter = 'all'
	local node = {tutorial = lessons, ref = ref, item = 1, first = 1}
	node.items = tutorial.f_buildSelectItems(node.tutorial, node.ref, false)
	if #node.items == 0 then
		return nil, true
	end
	node.item = tutorial.f_firstUncleared(node.items, node.tutorial, node.ref)
	-- Whatever the cursor rests on is the answer; cancel means no answer.
	local picked = node.items[node.item].displayname
	sndPlay(motif.Snd, sec.enter.snd[1], sec.enter.snd[2])
	resetKey()
	esc(false)
	while true do
		local done = getInput(-1, sec.menu.done.key)
		local cancel = esc() or getInput(-1, sec.menu.cancel.key)
		local dir, filter = 0, 0
		if getInput(-1, sec.menu.next.key) then
			dir = 1
		elseif getInput(-1, sec.menu.previous.key) then
			dir = -1
		end
		if getInput(-1, sec.menu.add.key) then
			filter = 1
		elseif getInput(-1, sec.menu.subtract.key) then
			filter = -1
		end
		if filter ~= 0 and tutorial.f_cycleFilterFor(node, filter) then
			sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
		elseif dir ~= 0 and f_moveCursor(node, dir) then
			sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
		end
		local it = node.items[node.item]
		if cancel then
			esc(false)
			sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
			picked = nil
			break
		elseif done and it ~= nil and it.locked then
			sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		elseif done then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			if it ~= nil and it.lesson ~= nil then
				picked = it.displayname
			end
			break
		end
		if it ~= nil and it.lesson ~= nil then
			picked = it.displayname
		end
		clearColor(motif.selectbgdef.bgclearcolor[1], motif.selectbgdef.bgclearcolor[2], motif.selectbgdef.bgclearcolor[3])
		bgDraw(motif.selectbgdef.BGDef, 0)
		tutorial.f_selectDraw(node)
		bgDraw(motif.selectbgdef.BGDef, 1)
		main.f_preloadTick(2)
		refresh()
	end
	resetKey()
	return picked
end

function tutorial.f_preFightMenu()
	-- The Game Tutorial picked its lesson before the match was set up (gametutorial.lua).
	if not tutorial.f_inMode() or tutorial.track == 'game' or tutorial.f_listDisplay() ~= 'select' then
		return
	end
	if type(start.p) ~= 'table' or type(start.p[1]) ~= 'table'
		or type(start.p[1].t_selected) ~= 'table' or start.p[1].t_selected[1] == nil then
		return
	end
	local ref = start.p[1].t_selected[1].ref
	local ok, charData = pcall(start.f_getCharData, ref)
	if not ok or type(charData) ~= 'table' then
		return
	end
	local lessons = tutorial.f_lessonsFor(charData)
	if #lessons == 0 then
		return
	end
	-- Nothing out here can read the vars this character's Tutorial are gated on, so asking now would list
	-- every groove's Tutorial and most of the answers would be wrong. The match-load list asks instead.
	if tutorial.f_hasVarGatedTutorial(lessons) then
		return
	end
	local sec = tutorial.f_selectSection()
	if sec == nil then
		return
	end
	local snap = f_snapshotSelect()
	tutorial.backToSelect = false
	local picked, empty = tutorial.f_lessonListLoop(lessons, ref, sec)
	if empty then
		return
	end
	tutorial.pendingLesson = picked
	if picked == nil then
		-- Back out one step to the select screen (stage select, or P2's pick without one). The
		-- fight is already being set up by now, so f_selectVersus is told to call it off.
		tutorial.backToSelect = true
		tutorial.backToSelectSnap = snap
	end
end

--;===========================================================
--; Game Tutorial
--;===========================================================
-- The Game Tutorial's match script, run as main.luaPath through gametutorial.lua: the lesson list,
-- then a match for the lesson picked, then the list again, until the player backs out of it.
-- P1 is the lesson's lesson.playerchar, else TutorialPlayerChar, else the select screen's pick. The
-- dummy is TutorialDummy, else the select screen's pick, else a mirror of P1.
function tutorial.f_gameTutorialRun()
	local selectShown = main.selectMenu[1] or main.selectMenu[2]
	-- launchFight overwrites t_selected, so what the select screen settled on is kept here.
	tutorial.pickedRef = start.p[1].t_selected[1] ~= nil and start.p[1].t_selected[1].ref or nil
	local p2Picked = nil
	if main.selectMenu[2] and main.forceChar[2] == nil and start.p[2].t_selected[1] ~= nil then
		p2Picked = start.p[2].t_selected[1].ref
	end
	tutorial.relaunchLesson = nil
	local sec = tutorial.f_selectSection()
	local lessons = tutorial.f_lessonsFor(nil)
	if #lessons == 0 or sec == nil then
		print('Dojo: the Game Tutorial has no game-wide lessons to offer; see SystemTutorial in config.ini.')
		setMatchNo(-1)
		return
	end
	while true do
		local name = tutorial.relaunchLesson
		tutorial.relaunchLesson = nil
		if name == nil then
			bgReset(motif.selectbgdef.BGDef)
			playBgm({source = "motif.select", interrupt = true})
			-- Fresh copies each time round, so the list shows what the last match cleared.
			lessons = tutorial.f_lessonsFor(nil)
			name = tutorial.f_lessonListLoop(lessons, tutorial.pickedRef, sec)
			if name == nil then
				-- Back out: to the select screen when there was one, to the main menu otherwise.
				if not selectShown then
					setMatchNo(-1)
				end
				return
			end
		end
		local lesson = nil
		for _, l in ipairs(lessons) do
			if l.name == name then
				lesson = l
				break
			end
		end
		local p1 = tutorial.f_playerFor(lesson)
		if p1 == nil then
			print('Dojo: no character to play "' .. tostring(name) .. '" with; set TutorialPlayerChar in config.ini.')
			setMatchNo(-1)
			return
		end
		local p2 = tutorial.dummyRef or p2Picked or p1
		tutorial.gameP1 = p1
		tutorial.pendingLesson = name
		-- launchFight replaces P1's selection when given p1char, but adds p2char to P2's.
		start.p[2].t_selected = {}
		start.p[2].t_selTemp = {}
		launchFight{
			p1char = {start.f_getCharData(p1).char},
			p2char = {start.f_getCharData(p2).char},
		}
		if tutorial.relaunchLesson == nil then
			-- Exit leaves for the main menu (launchFight sets matchNo -1 when there is no select
			-- screen to go back to). With a select screen, any way out of the match goes back to it.
			-- Without one, Character Change comes back to this list.
			if matchNo() == -1 or selectShown then
				return
			end
		end
	end
end

--;===========================================================
--; Speedrun
--;===========================================================
-- Speedrun is a run of the whole character, in order, against the clock. The Tutorial List is taken
-- off the Pause menu so no Lesson can be skipped, and Advancement is held at Auto-Advance because
-- Repeat would stall a run.
--
-- The same pass decides every root item that only applies some of the time, so both pause menus can
-- list everything and still never offer a row that would do nothing:
--   tutorialrecord / tutorialrecorddummy - authoring aids, only with [Config] RecordDemo = true
--   tutoriallist                         - not during a speedrun
--   tutorialdemo                         - only for an entry with a demoscript, and not in a speedrun
--   tutorialinstructions                 - only for an entry with instruction pages
-- In demonstrations-only, Watch Demo and both Record rows go: the demo is already playing, and
-- there is no playing the lesson to record.
-- Run again whenever the pause menu opens (menu.f_init below), since the current entry moves on.
local function f_rootItemShown(name, on)
	if name == 'tutorialrecord' or name == 'tutorialrecorddummy' then
		return tutorial.recordEnabled and not tutorial.f_demoOnly()
	elseif name == 'tutorialdemo' and tutorial.f_demoOnly() then
		return false
	elseif name == 'tutoriallist' then
		return not on
	elseif name == 'tutorialdemo' or name == 'tutorialinstructions' then
		local d = tutorial.data
		if d == nil or type(d.lessons) ~= 'table' or #d.lessons == 0 then
			return false
		end
		local l = d.lessons[math.min(d.currentlesson or 1, #d.lessons)]
		if name == 'tutorialdemo' then
			return not on and l ~= nil and l.demoscript ~= ''
		end
		return l ~= nil and type(l.pages) == 'table' and #l.pages > 0
	end
	return true
end

function tutorial.f_applySpeedrun()
	if tutorial.rootNode == nil or tutorial.rootItems == nil then
		return
	end
	local on = tutorial.f_speedrunEnabled()
	local items = {}
	for _, item in ipairs(tutorial.rootItems) do
		if f_rootItemShown(item.itemname, on) then
			items[#items + 1] = item
		end
	end
	-- A row coming or going moves every row under it, so the cursor would land on a different item
	-- than the one it was left on. Start it back at the top instead.
	if #items ~= #(tutorial.rootNode.items or {}) then
		tutorial.rootNode.item = 1
		tutorial.rootNode.cursorPosY = 1
		tutorial.rootNode.moveTxt = 0
	end
	tutorial.rootNode.items = items
	if tutorial.rootNode.item > #items then
		tutorial.rootNode.item = #items
		tutorial.rootNode.cursorPosY = 1
		tutorial.rootNode.moveTxt = 0
	end
	if on then
		menu.tutorialadvancement = 1
		if tutorial.data ~= nil then
			tutorial.data.tutorialadvancement = true
		end
		for _, v in ipairs(menu.t_vardisplayPointers) do
			if v.itemname == 'tutorialadvancement' then
				v.vardisplay = menu.f_vardisplay('tutorialadvancement')
			end
		end
	end
end

-- A run belongs to the sitting it was started in. Leaving for the character select screen ends it,
-- whether that was Character Change, the end of a match, or exiting the mode altogether - they all
-- come through start.f_selectReset.
function tutorial.f_resetSpeedrun()
	menu.tutorialspeedrun = 2
	tutorial.f_applySpeedrun()
	for _, v in ipairs(menu.t_vardisplayPointers) do
		if v.itemname == 'tutorialspeedrun' then
			v.vardisplay = menu.f_vardisplay('tutorialspeedrun')
		end
	end
end

-- Starts a fresh run: back to the first Lesson with the total timer armed and the run counted.
function tutorial.f_startSpeedrun()
	if tutorial.data == nil or #tutorial.data.lessons == 0 then
		return
	end
	tutorial.f_gotoLesson(1, true, true)
	tutorial.data.runValid = true
end

-- Game Tutorial only. Once the current lesson needs a different P1 from the one this match was
-- launched with - picked from the Lesson List, reached with Next / Previous or by auto-advance - the
-- match is ended the way Character Change ends one, and the lesson handed over to gametutorial.lua.
-- Waits out the pause menu and a Success banner, so both finish first. True while ending.
function tutorial.f_relaunchForPlayer()
	if tutorial.track ~= 'game' then
		return false
	end
	if tutorial.relaunchLesson ~= nil then
		return true
	end
	if paused() or (tutorial.draw ~= nil and (tutorial.draw.success or 0) > 0) then
		return false
	end
	local l = tutorial.data.lessons[tutorial.data.currentlesson]
	if l == nil or tutorial.f_playerFor(l) == tutorial.gameP1 then
		return false
	end
	tutorial.relaunchLesson = l.name
	tutorial.f_endDemo(false)
	tutorial.f_stopScript(1)
	tutorial.f_stopScript(2)
	endMatch()
	start.characterchange = true
	return true
end

function tutorial.f_tutorialMode()
	-- The match may be running at an aspect the module was not loaded on - with the aspect ratio
	-- option set to "stage", every stage can bring its own. Lay the canvas out for the one in force
	-- before anything is drawn in it. No-op once it has settled, which is every frame after the
	-- first of a match.
	tutorial.f_syncAspect()

	if roundStart() then
		tutorial.f_cancelRecording()
		tutorial.f_endDemo(false)
		tutorial.f_stopScript(1)
		tutorial.f_stopScript(2)
		tutorial.data = nil
		-- Empty the tutorial list back to the items and loop the section declared.
		if tutorial.listNode ~= nil and tutorial.listTail ~= nil then
			tutorial.listNode.items = tutorial.listTail
			tutorial.listNode.item = 1
			tutorial.listNode.cursorPosY = 1
			tutorial.listNode.moveTxt = 0
			tutorial.listNode.loop = tutorial.listLoop
		end
		if tutorial.rootNode ~= nil and tutorial.rootItems ~= nil then
			tutorial.rootNode.items = tutorial.rootItems
			tutorial.rootNode.item = 1
			tutorial.rootNode.cursorPosY = 1
			tutorial.rootNode.moveTxt = 0
		end
		tutorial.select = nil
		tutorial.pages = nil
		tutorial.selectDirty = false
		tutorial.p1selref = nil
		tutorial.charPortraitSff = nil
		if tutorial.tutorial_mode.textbox.portrait.anim ~= nil then
		animReset(tutorial.tutorial_mode.textbox.portrait.anim)
					end
		-- Check if there's a tutorial file - if so, parse it
		if tutorial.f_hasLessons(start.f_getCharData(start.p[1].t_selected[1].ref)) then
			tutorial.f_inittutorialData()
			tutorialExist = true
 		else
			tutorialExist = false
		end
	end

	if tutorial.p1selref == nil then
		if start.p[1].t_selected[1].ref ~= nil then
			tutorial.p1selref = start.p[1].t_selected[1].ref
		end
	end
					
	if tutorialExist and roundState() == 2 and not tutorial.data.tutorialInitialized then
		-- Initialize the tutorial based on parsed file and char state at roundState() == 2
		tutorial.f_tutorialBuilder()
		menu.f_tutorialReset()
		-- Honour a Lesson picked before the fight. Names, not indices: f_tutorialBuilder drops Tutorial
		-- whose showforvarvalpairs do not match, so the parsed indices need not survive into here.
		local pickLost = false
		if tutorial.pendingLesson ~= nil then
			pickLost = true
			for i = 1, #tutorial.data.lessons, 1 do
				if tutorial.data.lessons[i].name == tutorial.pendingLesson then
					tutorial.data.currentlesson = i
					pickLost = false
					break
				end
			end
			tutorial.pendingLesson = nil
		end
		-- Arm both clocks together before anything else looks at them. The paths that follow may
		-- re-arm (a run restarting, the select view closing); a match that starts straight on a
		-- Lesson has nothing else that would.
		tutorial.f_armTimers(tutorial.data.currentlesson, true)
		-- A speedrun goes straight to the first Lesson, and so does a screenpack that turned the
		-- menu off. Otherwise the player picks one before anything starts.
		-- Under 'select' the asking normally happened before the fight, so there is nothing to do
		-- here - except for a character whose Tutorial are gated on vars, which could not be asked out
		-- there, and for a pick that turned out to be gated away, which needs asking again.
		-- The Game Tutorial's lesson was always picked from its own list before the match.
		local mode = tutorial.f_listDisplay()
		if tutorial.f_speedrunEnabled() then
			tutorial.f_startSpeedrun()
		elseif tutorial.track == 'game' then
			if pickLost then
				tutorial.f_openSelect()
			end
		elseif mode == 'start' or (mode == 'select' and (tutorial.f_hasVarGatedTutorial() or pickLost)) then
			tutorial.f_openSelect()
		end
	elseif tutorialExist and roundState() == 2 and tutorial.data.tutorialInitialized
		and tutorial.select ~= nil and tutorial.select.open then
		-- The select view owns the frame until the player picks a Lesson - except while the pause
		-- menu is up, which owns it instead.
		if not paused() then
			tutorial.f_selectLoop(tutorial.select, true)
		end
	elseif tutorialExist and roundState() == 2 and tutorial.data.tutorialInitialized and tutorial.f_pagesOpen() then
		-- Instruction pages own the frame until read, like the select view, unless the pause menu is up.
		if not paused() then
			tutorial.f_pagesLoop()
		end
	elseif tutorialExist and roundState() == 2 and tutorial.data.tutorialInitialized then
		-- A Game Tutorial lesson played with another P1 than this match's ends the match here, and
		-- gametutorial.lua launches the next one with the right character.
		if tutorial.f_relaunchForPlayer() then
			return
		end
		-- If tutorial initialized, draw elements and check for success!
		if tutorial.f_demoActive() and not paused() then
			tutorial.f_demoTick()
		end
		tutorial.f_tutorialDrawer()
		tutorial.f_demoOnlyGuard()
		player(1)
		tutorial.f_tutorialChecker('root')
		if numHelper() > 0 and tutorial.draw.success == 0 then
			for i = 1, numHelper(), 1 do
				tutorial.f_tutorialChecker(i)
			end
		end
		player(1)
		if not paused() then
			tutorial.f_scriptTick()
		end
		tutorial.f_recordTick()
	elseif roundState() == 2 then
		-- No tutorial present!
		player(2)
		setAILevel(0)
		mapSet('_iksys_tutorialSetLife', lifeMax())
		player(1)
		mapSet('_iksys_tutorialDummyControl', 0)
		mapSet('_iksys_tutorialSetLife', lifeMax())
		if tutorial.notutorialcounter == nil then
			tutorial.notutorialcounter = f_newText(tutorial.tutorial_mode.lessoncounter)
		end
		tutorial.notutorialcounter:update({x = tutorial.tutorial_mode.lessoncounter_pos[1], y = tutorial.tutorial_mode.lessoncounter_pos[2], text = tutorial.tutorial_mode.lessoncounter_notutorialdata_text})
		tutorial.notutorialcounter:draw()
	end
end

--;===========================================================
--; Teaching features: instruction pages, repetitions, hints, event steps
--;===========================================================
-- Defaults for the UI def blocks these features draw from, so a def that predates them (a
-- trialsmode.def from before the merge, say) still gets a working, if plain, look. Run per profile
-- by f_buildProfile, like the rest of the UI build.
local function f_uiTeach()
	local tm = tutorial.tutorial_mode
	local cx, cy = tutorial.mtlcx / 2, tutorial.mtlcy / 2
	local function textNode(n, txt)
		if type(n.offset) ~= 'table' then n.offset = {0, 0} end
		if type(n.font) ~= 'table' then n.font = {-1} end
		if type(n.scale) ~= 'table' then n.scale = {1, 1} end
		if n.text == nil then n.text = txt or '' end
		return n
	end
	local function artNode(n)
		if type(n.offset) ~= 'table' then n.offset = {0, 0} end
		return n
	end

	local ins = f_node(tm, 'instructions')
	if type(ins.pos) ~= 'table' then ins.pos = {cx, cy} end
	local o = f_node(ins, 'overlay')
	if o.visible == nil then o.visible = true end
	if type(o.window) ~= 'table' then o.window = {-cx, -cy, cx, cy} end
	if type(o.col) ~= 'table' then o.col = {0, 0, 0} end
	if type(o.alpha) ~= 'table' then o.alpha = {0, 160} end
	o.layerno = tonumber(o.layerno) or 2
	artNode(f_node(ins, 'bg'))
	artNode(f_node(ins, 'front'))
	textNode(f_node(ins, 'title'), '%s')
	local body = textNode(f_node(ins, 'text'))
	if type(body.window) ~= 'table' then body.window = {-cx * 0.6, -cy * 0.4, cx * 0.6, cy * 0.4} end
	body.drawspeed = tonumber(body.drawspeed) or 0
	local pageNode = textNode(f_node(ins, 'page'), '%s/%t')
	if type(pageNode.snd) ~= 'table' then pageNode.snd = {-1, 0} end
	textNode(f_node(ins, 'prompt'))
	if type(ins.snd) ~= 'table' then ins.snd = {-1, 0} end
	-- The portrait is built per page when the page is shown (a page can name its own), so only its
	-- placement is settled here. spr / anim stay as the def wrote them.
	local por = artNode(f_node(ins, 'portrait'))
	por.source = tostring(por.source or 'system'):lower():gsub('"', '')
	if por.source ~= 'system' and por.source ~= 'char' then
		print('Dojo: instructions.portrait.source must be "system" or "char"; using "system".')
		por.source = 'system'
	end
	if type(por.scale) ~= 'table' then por.scale = {1, 1} end
	if type(por.window) ~= 'table' then por.window = {0, 0, 0, 0} end
	por.facing = tonumber(por.facing) or 1
	if por.layerno == nil then por.layerno = 2 end

	local hint = f_node(tm, 'hint')
	if type(hint.pos) ~= 'table' then hint.pos = {cx, tutorial.mtlcy - 40} end
	if hint.visible == nil then hint.visible = true end
	artNode(f_node(hint, 'bg'))
	textNode(f_node(hint, 'text'), '%s')
	local hw = f_node(hint, 'text')
	if type(hw.window) ~= 'table' then hw.window = {0, 0, 0, 0} end

	local demo = f_node(tm, 'demo')
	if type(demo.pos) ~= 'table' then demo.pos = {cx, 80} end
	artNode(f_node(demo, 'bg'))
	textNode(f_node(demo, 'text'), 'DEMO')
	local dprompt = f_node(tm, 'demoprompt')
	if type(dprompt.pos) ~= 'table' then dprompt.pos = {cx, tutorial.mtlcy - 80} end
	textNode(f_node(dprompt, 'text'), 'Pause and pick Watch Demo to see it done')
	local doprompt = f_node(tm, 'demoonlyprompt')
	if type(doprompt.pos) ~= 'table' then doprompt.pos = {cx, tutorial.mtlcy - 80} end
	local dot = textNode(f_node(doprompt, 'text'), 'Confirm: next lesson    Back: instructions')
	if dot.last == nil then dot.last = 'Confirm: lesson list    Back: instructions' end
	local rep = f_node(tm, 'repcounter')
	if type(rep.pos) ~= 'table' then rep.pos = {cx, 40} end
	artNode(f_node(rep, 'bg'))
	textNode(f_node(rep, 'text'), '%s/%t')
	if type(rep.snd) ~= 'table' then rep.snd = {-1, 0} end

	for _, n in ipairs({ins.bg, ins.front, hint.bg, rep.bg, demo.bg}) do
		if n.layerno == nil then n.layerno = 2 end
		n.AnimData = f_loadAnimData(n, 0, 0)
	end
	for _, n in ipairs({ins.title, ins.text, ins.page, ins.prompt}) do
		if n.layerno == nil then n.layerno = 2 end
	end

	tutorial.teach = {
		title = f_newText(ins.title),
		body = f_newText(ins.text),
		page = f_newText(ins.page),
		prompt = f_newText(ins.prompt),
		hint = f_newText(hint.text),
		rep = f_newText(rep.text),
		demo = f_newText(demo.text),
		demoprompt = f_newText(dprompt.text),
		demoonlyprompt = f_newText(doprompt.text),
	}
end

local function f_playSnd(snd)
	if type(snd) == 'table' and tonumber(snd[1]) ~= nil and snd[1] >= 0 then
		sndPlay(dojoSnd, snd[1], snd[2] or 0)
	end
end

local function f_drawArt(node, x, y)
	if type(node) == 'table' and node.AnimData ~= nil then
		animSetLocalcoord(node.AnimData, tutorial.f_localcoord())
		animSetPos(node.AnimData, x + node.offset[1], y + node.offset[2])
		animUpdate(node.AnimData)
		animDraw(node.AnimData)
	end
end

local function f_drawText(obj, node, x, y, str)
	if str == nil or str == '' then
		return
	end
	obj:update({x = x + node.offset[1], y = y + node.offset[2], text = str})
	obj:draw()
end

-- Body text wraps inside its window, which is authored relative to the block's pos.
local function f_wrapText(obj, node, x, y)
	local w = node.window
	if w[1] == w[3] then
		return
	end
	obj.window = {x + w[1], y + w[2], x + w[3], y + w[4]}
	textImgSetWindow(obj.ti, obj.window[1], obj.window[2], obj.window[3] - obj.window[1], obj.window[4] - obj.window[2])
	textImgSetTextWrap(obj.ti, true)
end

-- A character's own sprites and actions, for portraits sourced from it: the sprite and anim files
-- its def names under [Files]. Cached per character ref; false marks one that could not be read.
local t_charArt = {}
local function f_charArt(ref)
	if ref == nil then
		return nil
	end
	if t_charArt[ref] == nil then
		t_charArt[ref] = false
		local ok, def = pcall(getCharFileName, ref)
		local okText, src = false, nil
		if ok and type(def) == 'string' and def ~= '' then
			okText, src = pcall(loadText, def)
		end
		if okText and type(src) == 'string' then
			local files, section = {}, nil
			for line in src:gmatch('[^\r\n]+') do
				line = line:gsub(';.*$', '')
				local sec = line:match('^%s*%[%s*(.-)%s*%]')
				if sec ~= nil then
					section = sec:lower()
				elseif section == 'files' then
					local k, v = line:match('^%s*(%a+)%s*=%s*(.-)%s*$')
					if k ~= nil then
						files[k:lower()] = v:gsub('"', '')
					end
				end
			end
			local dir = def:gsub('\\', '/'):match('^(.*/)') or ''
			local okSff, charSff = false, nil
			if files.sprite ~= nil and files.sprite ~= '' then
				okSff, charSff = pcall(sffNew, dir .. files.sprite)
			end
			if okSff and charSff ~= nil then
				local anims = {}
				if files.anim ~= nil and files.anim ~= '' then
					local okAir, t = pcall(loadAnimTable, dir .. files.anim, charSff)
					if okAir and type(t) == 'table' then
						anims = t
					end
				end
				t_charArt[ref] = {sff = charSff, anims = anims}
			else
				print('Dojo: could not read the sprites of ' .. tostring(def) .. ' for an instruction page portrait.')
			end
		end
	end
	return t_charArt[ref] or nil
end

-- Builds the portrait for one instruction page. A page that names a portrait.spr or portrait.anim of
-- its own replaces both of the def's, so a page's sprite is never hidden behind the def's anim.
-- source picks where they come from: "system" is the Dojo's own sprites and actions (dojo.sff and
-- dojo.air / dojo.def, as every other element), "char" is P1's own sff and air.
local function f_pagePortrait(pg)
	local por = tutorial.tutorial_mode.instructions.portrait
	local pp = type(pg.portrait) == 'table' and pg.portrait or {}
	local spr, anim = por.spr, tonumber(por.anim)
	if pp.spr ~= nil or pp.anim ~= nil then
		spr, anim = pp.spr, pp.anim
	end
	if spr == nil and (anim == nil or anim < 0) then
		return nil
	end
	local sprData, animData = nil, nil
	if (pp.source or por.source) == 'char' then
		local art = f_charArt(tutorial.p1selref)
		if art == nil then
			return nil
		end
		sprData, animData = art.sff, art.anims
	end
	return f_loadAnimData({spr = spr, anim = anim, offset = por.offset, scale = por.scale,
		facing = por.facing, layerno = por.layerno}, 0, 0, sprData, animData)
end

-- What showing a page does besides drawing it: its portrait is built (and starts from its first
-- frame), and its sound plays - the page's own lesson.page.N.snd, else instructions.page.snd.
local function f_showPage(p, lesson)
	local pg = lesson.pages[p.page]
	if pg == nil then
		return
	end
	p.portrait = f_pagePortrait(pg)
	f_playSnd(pg.snd or tutorial.tutorial_mode.instructions.page.snd)
end

-- instructions.portrait.window is x1,y1,x2,y2 from the portrait's own position; all zero leaves it
-- unclipped.
local function f_drawPortrait(a, por, x, y)
	if a == nil then
		return
	end
	local px, py = x + por.offset[1], y + por.offset[2]
	local w = por.window
	animSetLocalcoord(a, tutorial.f_localcoord())
	animSetPos(a, px, py)
	if w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0 then
		animSetWindow(a, 0, 0, tutorial.vislcx, tutorial.mtlcy)
	else
		animSetWindow(a, px + w[1], py + w[2], px + w[3], py + w[4])
	end
	animUpdate(a)
	animDraw(a)
end

----------------------------------------------------------------
-- Instruction pages
----------------------------------------------------------------
-- A lesson's lesson.page.N.* is shown once each time the lesson is entered: on being picked,
-- advanced to or restarted, not on each repetition or reset. The pause menu reopens it.
function tutorial.f_openPages(index)
	local lesson = tutorial.data ~= nil and tutorial.data.lessons[index] or nil
	if lesson == nil or type(lesson.pages) ~= 'table' or #lesson.pages == 0 then
		return false
	end
	lesson.pagesSeen = true
	tutorial.pages = {open = true, lesson = index, page = 1, ticks = 0}
	tutorial.f_menuHold(true)
	f_playSnd(tutorial.tutorial_mode.instructions.snd)
	f_showPage(tutorial.pages, lesson)
	return true
end

function tutorial.f_closePages()
	if tutorial.pages ~= nil then
		tutorial.pages.open = false
	end
	tutorial.f_menuHold(false)
	-- Reading is nobody's attempt time. A speedrun never opens the pages, so its run clock is safe.
	if tutorial.data ~= nil then
		tutorial.f_armTimers(tutorial.data.currentlesson)
	end
end

function tutorial.f_pagesOpen()
	return tutorial.pages ~= nil and tutorial.pages.open
end

function tutorial.f_pagesLoop()
	local p = tutorial.pages
	local lesson = tutorial.data.lessons[p.lesson]
	local pg = lesson ~= nil and lesson.pages[p.page] or nil
	if pg == nil then
		tutorial.f_closePages()
		return
	end
	tutorial.f_syncAspect()
	tutorial.f_menuHold(true)
	local ins = tutorial.tutorial_mode.instructions
	local t = tutorial.teach
	local x, y = ins.pos[1], ins.pos[2]
	f_menuRect(ins.overlay, x, y)
	f_drawArt(ins.bg, x, y)
	f_drawPortrait(p.portrait, ins.portrait, x, y)
	local title = pg.title ~= '' and pg.title or lesson.name
	f_drawText(t.title, ins.title, x, y, (ins.title.text:gsub('%%s', title):gsub('%%n', lesson.name)))
	-- The body types itself out at drawspeed frames per character; 0 shows it all at once.
	local body = (pg.text:gsub('\\n', '\n'))
	local speed = ins.text.drawspeed
	local shown = #body
	if speed > 0 then
		shown = math.min(#body, math.floor(p.ticks / speed) + 1)
	end
	p.ticks = p.ticks + 1
	t.body:update({x = x + ins.text.offset[1], y = y + ins.text.offset[2], text = body:sub(1, shown)})
	f_wrapText(t.body, ins.text, x, y)
	t.body:draw()
	if #lesson.pages > 1 then
		f_drawText(t.page, ins.page, x, y, (ins.page.text:gsub('%%s', tostring(p.page)):gsub('%%t', tostring(#lesson.pages))))
	end
	f_drawText(t.prompt, ins.prompt, x, y, ins.prompt.text)
	f_drawArt(ins.front, x, y)

	-- Input, through the pause menu section's keys, like the lesson list. Sampled every frame so a
	-- held button from whatever opened the pages does not read as a fresh press.
	local sec = tutorial.f_selectSection()
	if sec == nil then
		return
	end
	player(1)
	local done = f_matchPressed(p, 'done', sec.menu.done.key, false)
	local back = f_matchPressed(p, 'cancel', sec.menu.cancel.key, false)
	if p.wait == nil then
		p.wait = 10
	end
	if p.wait > 0 then
		p.wait = p.wait - 1
		return
	end
	if done then
		if shown < #body then
			p.ticks = #body * math.max(speed, 1) -- finish typing first
		elseif p.page < #lesson.pages then
			p.page, p.ticks, p.wait = p.page + 1, 0, 6
			sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
			f_showPage(p, lesson)
		else
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			tutorial.f_closePages()
		end
	elseif back and p.page > 1 then
		p.page, p.ticks, p.wait = p.page - 1, 0, 6
		sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
		f_showPage(p, lesson)
	end
end

----------------------------------------------------------------
-- Repetitions, failures and hints
----------------------------------------------------------------
-- Called when the last step of a lesson passes. True once lesson.repeat clears have been made, at
-- which point the lesson is cleared as normal; until then the lesson goes round again without a
-- banner or a recorded clear.
-- Every step's hit tallies back to nothing, for a fresh attempt.
local function f_clearStepCounts(index)
	for _, s in ipairs(tutorial.data.lessons[index].steps) do
		for k = 1, s.numofmicrosteps, 1 do
			s.stephitscount[k] = 0
			s.comboCountonstep[k] = 0
		end
	end
end

function tutorial.f_countRep(index)
	local lesson = tutorial.data.lessons[index]
	-- A demo never earns a clear, and demonstrations-only never has anything else.
	local watching = tutorial.f_demoActive() or tutorial.f_demoOnly()
	if not watching then
		lesson.repsdone = (lesson.repsdone or 0) + 1
	end
	if lesson.repsdone >= (lesson.reps or 1) and not watching then
		lesson.repsdone = 0
		return true
	end
	tutorial.f_spendState()
	f_clearStepCounts(index)
	tutorial.data.currentlessonstep = 1
	tutorial.data.currentlessonmicrostep = 1
	-- The combo that finished this round is still running: hold on to its count, or its next frame
	-- reads as a fresh hit and makes the next round too.
	tutorial.data.comboCounter = comboCount()
	tutorial.data.validfortickcount = 0
	f_playSnd(tutorial.tutorial_mode.repcounter.snd)
	return false
end

-- An attempt that had got somewhere and was lost. Drives lesson.hintafter (and, in time, the demo
-- offer). Idle frames at the first step are not failures.
function tutorial.f_noteFail(index)
	local lesson = tutorial.data.lessons[index]
	if lesson ~= nil and not tutorial.f_demoActive() and not tutorial.f_demoOnly() then
		lesson.fails = (lesson.fails or 0) + 1
	end
end

-- Starts the attempt over from the first step - the reset Trials Mode always did - counting it as
-- a failure when there was progress to lose.
function tutorial.f_resetAttempt(index, si, mi)
	local step = tutorial.data.lessons[index].steps[si]
	if tutorial.f_comboUnderway(step, mi, si) then
		tutorial.f_noteFail(index)
	end
	tutorial.f_spendState()
	tutorial.data.currentlessonstep = 1
	tutorial.data.currentlessonmicrostep = 1
	-- All steps, not just this one: Trials zeroed only this one and left the idle reset on the
	-- next frame to catch the rest, which would now read as a second failure.
	f_clearStepCounts(index)
	tutorial.data.comboCounter = 0
	tutorial.data.validfortickcount = 0
end

-- Whether dropping to a combo count of 0 loses anything: hits were landed on this step, or the
-- steps before it built a combo. Without either the player simply has not started, which is
-- how a hit step can follow one that does not hit.
function tutorial.f_comboUnderway(step, mi, si)
	return ((si > 1 or mi > 1) and tutorial.data.comboCounter > 0) or (step.stephitscount[mi] or 0) > 0
end

function tutorial.f_hintsOn()
	return tostring(opts.Hints or 'true'):lower() ~= 'false'
end

-- The repetition counter and the hint, drawn with the rest of the lesson HUD.
function tutorial.f_drawLessonExtras(index)
	local lesson = tutorial.data.lessons[index]
	if lesson == nil then
		return
	end
	local tm, t = tutorial.tutorial_mode, tutorial.teach
	if (lesson.reps or 1) > 1 then
		local rep = tm.repcounter
		f_drawArt(rep.bg, rep.pos[1], rep.pos[2])
		f_drawText(t.rep, rep.text, rep.pos[1], rep.pos[2],
			(rep.text.text:gsub('%%s', tostring(lesson.repsdone or 0)):gsub('%%t', tostring(lesson.reps))))
	end
	if tutorial.f_recording() then
		local dm = tm.demo
		local who = tutorial.rec.pn == 2 and 'REC DUMMY' or 'REC'
		local label = tutorial.rec.phase == 'recording' and (who .. ' ' .. #tutorial.rec.frames) or (who .. ' - waiting for input (pause to stop)')
		f_drawText(t.demo, dm.text, dm.pos[1], dm.pos[2], label)
	elseif tutorial.f_demoActive() then
		local dm = tm.demo
		f_drawArt(dm.bg, dm.pos[1], dm.pos[2])
		f_drawText(t.demo, dm.text, dm.pos[1], dm.pos[2], dm.text.text)
		if tutorial.f_demoOnly() then
			local dp = tm.demoonlyprompt
			local last = index >= #tutorial.data.lessons
			local str = last and dp.text.last or dp.text.text
			if str ~= '' then
				f_drawText(t.demoonlyprompt, dp.text, dp.pos[1], dp.pos[2], str)
			end
		end
	elseif tutorial.f_demoOffered(lesson) then
		local dp = tm.demoprompt
		f_drawText(t.demoprompt, dp.text, dp.pos[1], dp.pos[2], dp.text.text)
	end
	local hint = tm.hint
	if lesson.hint ~= '' and tutorial.f_hintsOn() and f_menuOn(hint.visible) and (lesson.fails or 0) >= (lesson.hintafter or 0) then
		f_drawArt(hint.bg, hint.pos[1], hint.pos[2])
		t.hint:update({x = hint.pos[1] + hint.text.offset[1], y = hint.pos[2] + hint.text.offset[2],
			text = (hint.text.text:gsub('%%s', (lesson.hint:gsub('%%', '%%%%'))))})
		f_wrapText(t.hint, hint.text, hint.pos[1], hint.pos[2])
		t.hint:draw()
	end
end

----------------------------------------------------------------
-- Event steps: guard, isguarded, p2stateno
----------------------------------------------------------------
-- Guard-hit states from common1: standing, crouching and air guard. Entering one is a block.
tutorial.t_guardStates = {[150] = 'high', [151] = 'high', [152] = 'low', [153] = 'low', [154] = 'air', [155] = 'air'}

-- Per-frame bookkeeping in the root pass, whether or not a lesson is accepting input: what P1
-- blocked, whether P1 was hit, whether P1's own move was blocked, and the dummy's state. Each is
-- stamped with the frame it happened on so a step only ever counts what happened this frame.
function tutorial.f_trackEvents(newinstance)
	local d = tutorial.data
	d.frame = (d.frame or 0) + 1
	local ev = d.ev
	if ev == nil then
		ev = {}
		d.ev = ev
	end
	local sn = stateNo()
	local kind = tutorial.t_guardStates[sn]
	if kind ~= nil and newinstance and (sn == 150 or sn == 152 or sn == 154) then
		ev.guardFrame, ev.guardKind = d.frame, kind
	end
	local mt = moveType()
	if mt == 'H' and ev.lastMoveType ~= 'H' then
		ev.hitFrame = d.frame
	end
	ev.lastMoveType = mt
	local mg = moveGuarded()
	if mg > 0 and ((ev.lastGuarded or 0) == 0 or mg < ev.lastGuarded) then
		ev.guardedFrame = d.frame
	end
	ev.lastGuarded = mg
	player(2)
	local p2 = stateNo()
	local p2t = time()
	if p2 ~= ev.p2State or (ev.p2Time ~= nil and p2t < ev.p2Time) then
		ev.p2Frame = d.frame
	end
	ev.p2State, ev.p2Time = p2, p2t
	player(1)
end

local function f_inList(list, v)
	if type(list) ~= 'table' then
		return false
	end
	for _, x in ipairs(list) do
		if x == v then
			return true
		end
	end
	return false
end

-- Whether the dummy's state satisfies the microstep's p2stateno (free when it declares none).
function tutorial.f_p2StateOk(step, mi)
	local want = step.p2stateno[mi]
	if want == nil or #want == 0 then
		return true
	end
	return f_inList(want, tutorial.data.ev ~= nil and tutorial.data.ev.p2State or nil)
end

-- A step judged on events rather than on the combo: blocking (guard), getting your own move
-- blocked (isguarded), or the dummy entering a state with nothing else asked of the step.
function tutorial.f_isEventStep(step, mi)
	if step.guard[mi] ~= nil or step.isguarded[mi] then
		return true
	end
	return step.p2stateno[mi] ~= nil and #step.p2stateno[mi] > 0
		and #step.stateno == 0 and #step.animno == 0 and #step.projid == 0
end

-- Moves the attempt past the current microstep, and past the step and the lesson when it was the
-- last one. Event steps finish here; hit steps keep their own, older path.
local function f_advanceMicro(index, si, mi)
	local step = tutorial.data.lessons[index].steps[si]
	step.stephitscount[mi] = 0
	tutorial.data.currentlessonmicrostep = mi + 1
	tutorial.data.validfortickcount = 0
	tutorial.data.comboCounter = comboCount()
	if tutorial.data.currentlessonmicrostep > step.numofmicrosteps then
		tutorial.data.currentlessonmicrostep = 1
		tutorial.data.currentlessonstep = si + 1
		if tutorial.data.currentlessonstep > #tutorial.data.lessons[index].steps and tutorial.f_countRep(index) then
			tutorial.f_completeLesson(index)
		end
	end
end

-- Root pass only: every event is the root's (P1 blocking, P1's move blocked, the dummy's state).
function tutorial.f_checkEventStep(index, si, mi, statecheck, animcheck)
	local d, ev = tutorial.data, tutorial.data.ev or {}
	local step = d.lessons[index].steps[si]
	local need = math.max(step.hitcount[mi] or 1, 1)
	local happened = false
	if step.guard[mi] ~= nil then
		local want = step.guard[mi]
		happened = ev.guardFrame == d.frame and (want == 'any' or want == ev.guardKind)
		if not happened and ev.hitFrame == d.frame then
			-- Hit instead of blocking: that attempt is over.
			tutorial.f_noteFail(index)
			tutorial.f_spendState()
			d.currentlessonstep, d.currentlessonmicrostep = 1, 1
			step.stephitscount[mi] = 0
			return
		end
	elseif step.isguarded[mi] then
		happened = ev.guardedFrame == d.frame and statecheck and animcheck
	else
		happened = ev.p2Frame == d.frame
	end
	if happened and tutorial.f_p2StateOk(step, mi) then
		step.stephitscount[mi] = (step.stephitscount[mi] or 0) + 1
		if step.stephitscount[mi] >= need then
			f_advanceMicro(index, si, mi)
		end
	end
end

--;===========================================================
--; Input scripts: demonstrations (P1) and dummy scripts (P2)
--;===========================================================
-- lesson.demoscript and lesson.dummyscript are written the same way: comma-separated tokens of
-- <frames>:<inputs>, inputs joined with +, _ for nothing held. A token without a frame count lasts
-- one frame. F and B are relative to the way the character faces, as in a command.
--    lesson.demoscript = 6:D, 3:D+F, 3:F+x, 40:_    ; a quarter circle forward + x
-- Lua sets one map per input on the scripted character every frame, and dojo.zss's
-- TutorialScriptPress asserts them; asserted input reaches the command buffer like a held button.
tutorial.t_scriptInputs = {'U', 'D', 'F', 'B', 'a', 'b', 'c', 'x', 'y', 'z', 's', 'd', 'w'}
local t_scriptValid = {}
for _, k in ipairs(tutorial.t_scriptInputs) do t_scriptValid[k] = true end
tutorial.scriptMaxFrames = 3600

-- Script text -> array of per-frame input sets; nil and a reason when it cannot be read.
function tutorial.f_parseScript(src)
	if type(src) ~= 'string' or src:match('^%s*$') then
		return nil, 'empty'
	end
	local frames = {}
	for tok in (src .. ','):gmatch('([^,]*),') do
		tok = tok:gsub('%s+', '')
		if tok ~= '' then
			local n, inputs = tok:match('^(%d+):(.+)$')
			if n == nil then
				n, inputs = 1, tok
			end
			n = tonumber(n)
			local set = {}
			if inputs ~= '_' then
				for k in (inputs .. '+'):gmatch('([^+]*)%+') do
					-- case-sensitive, as in a command: directions U D F B, buttons a b c x y z s d w
					-- (b and d are buttons, not back and down)
					if not t_scriptValid[k] then
						return nil, 'unknown input "' .. k .. '" in "' .. tok .. '"'
					end
					set[k] = true
				end
			end
			for _ = 1, n, 1 do
				frames[#frames + 1] = set
				if #frames > tutorial.scriptMaxFrames then
					return nil, 'longer than ' .. tutorial.scriptMaxFrames .. ' frames'
				end
			end
		end
	end
	if #frames == 0 then
		return nil, 'empty'
	end
	return frames
end

-- One running script per side: tutorial.scripts[1] the demo, [2] the dummy's.
tutorial.scripts = {}

-- Map names are case-insensitive in the engine (stored lowercased), so the directions cannot be
-- _iksys_tutorialInD / InB: those would be the same maps as the d and b buttons.
tutorial.t_scriptMapName = {U = 'Up', D = 'Down', F = 'Fwd', B = 'Back'}

local function f_setScriptMaps(pn, set)
	player(pn)
	mapSet('_iksys_tutorialScript', set ~= nil and 1 or 0)
	for _, k in ipairs(tutorial.t_scriptInputs) do
		mapSet('_iksys_tutorialIn' .. (tutorial.t_scriptMapName[k] or k), (set ~= nil and set[k]) and 1 or 0)
	end
	player(1)
end

function tutorial.f_startScript(pn, frames, loop, delay)
	tutorial.scripts[pn] = {frames = frames, pos = 1, loop = loop, delay = delay or 0, wait = 0}
end

function tutorial.f_stopScript(pn)
	if tutorial.scripts[pn] ~= nil then
		tutorial.scripts[pn] = nil
		f_setScriptMaps(pn, nil)
	end
end

-- One frame of every running script. Returns nothing; a finished non-looping script stops itself.
function tutorial.f_scriptTick()
	for pn = 1, 2, 1 do
		local s = tutorial.scripts[pn]
		if s ~= nil then
			if s.wait > 0 then
				s.wait = s.wait - 1
				f_setScriptMaps(pn, {})
			elseif s.pos > #s.frames then
				if s.loop then
					s.pos, s.wait = 1, s.delay
					f_setScriptMaps(pn, {})
				else
					tutorial.f_stopScript(pn)
					if pn == 1 then
						tutorial.f_demoScriptDone()
					end
				end
			else
				f_setScriptMaps(pn, s.frames[s.pos])
				s.pos = s.pos + 1
			end
		end
	end
end

-- The dummy's own walking, jumping and button jam, switched off so they cannot fight a script or a
-- dummy take (auto-guard stays).
local function f_quietDummy()
	player(2)
	mapSet('_iksys_tutorialDummyMode', 0)
	mapSet('_iksys_tutorialButtonJam', 0)
	mapSet('_iksys_tutorialDistance', 0)
	player(1)
end

-- The dummy's script runs while its lesson is accepting input.
function tutorial.f_startDummyScript(index)
	tutorial.f_stopScript(2)
	-- A dummy take is the author driving the dummy: no script, and none of its own moves.
	if tutorial.rec ~= nil and tutorial.rec.pn == 2 then
		f_quietDummy()
		return
	end
	local lesson = tutorial.data.lessons[index]
	if lesson == nil or lesson.dummyscript == '' then
		return
	end
	if lesson.dummyframes == nil then
		local frames, why = tutorial.f_parseScript(lesson.dummyscript)
		if frames == nil then
			print('Dojo: "' .. lesson.name .. '" has an unreadable lesson.dummyscript (' .. why .. ').')
			lesson.dummyscript = ''
			return
		end
		lesson.dummyframes = frames
	end
	f_quietDummy()
	tutorial.f_startScript(2, lesson.dummyframes, lesson.dummyscriptloop, lesson.dummyscriptdelay)
end

----------------------------------------------------------------
-- Demonstrations
----------------------------------------------------------------
-- Watching one: the lesson restarts (so both sides are back in their start positions), P1's
-- controller is pointed at an empty input slot so the player cannot interfere, and lesson.demoscript
-- plays. The steps light up as it goes, but nothing is recorded. When it ends - or the player
-- skips it with the menu's done or cancel key - the controller comes back and the lesson starts
-- over for the player to try.
tutorial.demoSlot = 12 -- MaxPlayerNo; nobody's keys or pad are configured on it in practice

function tutorial.f_demoActive()
	return tutorial.demo ~= nil
end

function tutorial.f_hasDemo(index)
	local lesson = tutorial.data ~= nil and tutorial.data.lessons[index] or nil
	return lesson ~= nil and lesson.demoscript ~= ''
end

-- inPlace: the pair are already in their start positions (the lesson was only just entered), so
-- the lesson is not restarted first. Demonstrations-only uses it to save a second fade.
function tutorial.f_startDemo(index, inPlace)
	local lesson = tutorial.data.lessons[index]
	if lesson.demoframes == nil then
		local frames, why = tutorial.f_parseScript(lesson.demoscript)
		if frames == nil then
			print('Dojo: "' .. lesson.name .. '" has an unreadable lesson.demoscript (' .. why .. ').')
			lesson.demoscript = ''
			return false
		end
		lesson.demoframes = frames
	end
	if not inPlace then
		tutorial.f_gotoLesson(index, false, true)
	end
	lesson.pagesSeen = true
	tutorial.demo = {lesson = index, phase = 'waiting', tail = 0}
	if tutorial.data ~= nil then
		tutorial.data.demoOnlyPlayed = true
	end
	return true
end

-- Called every frame from the match loop while a demo is on.
function tutorial.f_demoTick()
	local dm = tutorial.demo
	if dm.phase == 'waiting' then
		-- for the restart's fade and reposition to finish
		if tutorial.data.active and tutorial.draw.fade == 0 then
			local ok, orig = pcall(getRemapInput, 1)
			dm.remap = ok and orig or 1
			pcall(remapInput, 1, tutorial.demoSlot)
			tutorial.f_startScript(1, tutorial.data.lessons[dm.lesson].demoframes, false, 0)
			dm.phase = 'playing'
		end
	elseif dm.phase == 'tail' then
		-- let the last move finish before handing back
		dm.tail = dm.tail - 1
		if dm.tail <= 0 then
			if tutorial.f_demoOnly() then
				-- demonstrations-only: round again until the player moves on
				tutorial.f_startDemo(dm.lesson)
			else
				tutorial.f_endDemo(true)
			end
			return
		end
	end
	local sec = tutorial.f_selectSection()
	if sec ~= nil and dm.phase ~= 'waiting' and tutorial.f_demoOnly() then
		-- done steps forward, cancel back; each needs a fresh press, so the one that closed the
		-- pages or picked the lesson is not read again here
		local done = getInput(-1, sec.menu.done.key)
		local back = getInput(-1, sec.menu.cancel.key)
		if dm.released and done then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			tutorial.f_demoOnlyNext(dm.lesson)
			return
		elseif dm.released and back then
			if tutorial.f_demoOnlyBack(dm.lesson) then
				sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
				return
			end
		end
		dm.released = not done and not back
	elseif sec ~= nil and dm.phase ~= 'waiting' then
		-- Raw UI input: P1's own command input is remapped away for the demo.
		local held = getInput(-1, sec.menu.done.key) or getInput(-1, sec.menu.cancel.key)
		if held and dm.released then
			tutorial.f_endDemo(true)
			return
		end
		if not held then
			dm.released = true
		end
	end
end

function tutorial.f_demoScriptDone()
	if tutorial.demo ~= nil then
		tutorial.demo.phase = 'tail'
		tutorial.demo.tail = 60
	end
end

-- restart: start the lesson over for the player (false when the match is being torn down).
function tutorial.f_endDemo(restart)
	local dm = tutorial.demo
	if dm == nil then
		return
	end
	tutorial.demo = nil
	tutorial.f_stopScript(1)
	if dm.remap ~= nil then
		pcall(remapInput, 1, dm.remap)
	end
	if restart and tutorial.data ~= nil and tutorial.data.lessons[dm.lesson] ~= nil then
		tutorial.f_gotoLesson(dm.lesson, false, true)
		tutorial.data.lessons[dm.lesson].pagesSeen = true
	end
end

-- Whether to put "watch the demo" in front of the player: lesson.demoafter failures and counting.
function tutorial.f_demoOffered(lesson)
	return lesson.demoscript ~= '' and (lesson.demoafter or 0) > 0 and (lesson.fails or 0) >= lesson.demoafter
end

----------------------------------------------------------------
-- Recording a demo (authoring aid)
----------------------------------------------------------------
-- With [Config] RecordDemo = true in config.ini, the pause menu offers Record Demo and Record
-- Dummy. Pick one and play; clearing the lesson (or pausing) ends the take. What the recorded side
-- held is printed to the console as a lesson.demoscript (P1) or lesson.dummyscript (P2) line, and
-- written to save/tutorial_demo.txt, ready to paste into a lesson file.
do
	local v = tostring(tutorial.ini.Config.RecordDemo or ''):lower()
	tutorial.recordEnabled = v == 'true' or v == '1' or v == 'yes'
end
tutorial.recordPath = 'save/tutorial_demo.txt'

----------------------------------------------------------------
-- Demonstrations only
----------------------------------------------------------------
-- With [Config] TutorialDemonstrationsOnly = true, every tutorial track (not Trials) becomes a
-- show-and-tell: a lesson's instruction pages, then its demo, looping, with the player's controller
-- off throughout. The menu's done key steps forward (next page, then the demo, then the next
-- lesson; the lesson list after the last), cancel steps back (previous page, or from the demo back
-- to the pages - the previous lesson when there are none). Nothing is ever cleared or recorded.
-- Lessons without a lesson.demoscript have nothing to show, so they are left out of the list.
do
	local v = tostring(tutorial.ini.Config.TutorialDemonstrationsOnly or ''):lower()
	tutorial.demoOnlyEnabled = v == 'true' or v == '1' or v == 'yes'
end

function tutorial.f_demoOnly()
	return tutorial.demoOnlyEnabled and tutorial.profile ~= nil and tutorial.profile.id == 'tutorial'
end

-- Whether a lesson is offered at all: in demonstrations-only, only one with a demo to show.
local t_demoOnlyWarned = {}
function tutorial.f_lessonOffered(lesson)
	if not tutorial.f_demoOnly() or lesson.demoscript ~= '' then
		return true
	end
	if not t_demoOnlyWarned[lesson] then
		t_demoOnlyWarned[lesson] = true
		print('Dojo: "' .. tostring(lesson.name) .. '" has no lesson.demoscript, so TutorialDemonstrationsOnly leaves it out.')
	end
	return false
end

-- Done during a demonstrations-only demo: on to the next lesson, or the list after the last one.
function tutorial.f_demoOnlyNext(index)
	tutorial.f_endDemo(false)
	if index < #tutorial.data.lessons then
		tutorial.f_gotoLesson(index + 1, false, true)
	else
		tutorial.f_openSelect()
	end
end

-- Cancel during a demonstrations-only demo: back to this lesson's pages, else the previous lesson.
-- False when there is nowhere to go back to, and the demo carries on.
function tutorial.f_demoOnlyBack(index)
	local lesson = tutorial.data.lessons[index]
	if lesson ~= nil and type(lesson.pages) == 'table' and #lesson.pages > 0 then
		tutorial.f_endDemo(false)
		tutorial.f_openPages(index)
		-- stepping back lands on the page before the demo: the last one
		if #lesson.pages > 1 then
			tutorial.pages.page = #lesson.pages
			f_showPage(tutorial.pages, lesson)
		end
		return true
	elseif index > 1 then
		tutorial.f_endDemo(false)
		tutorial.f_gotoLesson(index - 1, false, true)
		return true
	end
	return false
end

-- Run every match frame after the drawer, before the checker: whenever a lesson is up and neither
-- its pages nor its demo are, the demo starts. This is the one place that does it, so every way
-- of arriving at a lesson - entering it, closing its pages, backing out of the list - ends in the
-- demo, and no frame is ever left for the player to play the lesson themselves. A lesson just
-- entered still has the pair in their start positions, so its first demo starts in place; any
-- later one restarts the lesson to put them back.
function tutorial.f_demoOnlyGuard()
	if not tutorial.f_demoOnly() or tutorial.f_demoActive() or tutorial.f_pagesOpen() then
		return
	end
	local d = tutorial.data
	if not d.active or tutorial.draw.success > 0 or tutorial.draw.fade > 0 then
		return
	end
	local index = d.currentlesson
	if d.lessons[index] == nil or not tutorial.f_hasDemo(index) then
		return
	end
	tutorial.f_startDemo(index, not d.demoOnlyPlayed)
end

-- A frame set as script text: inputs in t_scriptInputs order, _ for none.
local function f_setText(set)
	local k = {}
	for _, n in ipairs(tutorial.t_scriptInputs) do
		if set[n] then k[#k + 1] = n end
	end
	return #k > 0 and table.concat(k, '+') or '_'
end

-- Frames -> "n:inputs, ..." with runs of identical frames merged; the inverse of f_parseScript.
function tutorial.f_scriptText(frames)
	local out, last, run = {}, nil, 0
	for _, set in ipairs(frames) do
		local s = f_setText(set)
		if s == last then
			run = run + 1
		else
			if last ~= nil then out[#out + 1] = run .. ':' .. last end
			last, run = s, 1
		end
	end
	if last ~= nil then out[#out + 1] = run .. ':' .. last end
	return table.concat(out, ', ')
end

function tutorial.f_recording()
	return tutorial.rec ~= nil
end

-- pn 1 records P1 for lesson.demoscript, pn 2 the dummy for lesson.dummyscript. A dummy take swaps
-- the two sides' controllers, so the author's pad drives the dummy (and a second pad, if any, drives
-- P1); the swap is undone when the take ends.
function tutorial.f_startRecording(pn)
	pn = pn or 1
	tutorial.f_cancelRecording()
	-- 'armed' until every button is let go, so the press that closed the menu is not recorded
	tutorial.rec = {frames = {}, phase = 'armed', pn = pn}
	if pn == 2 then
		local ok1, r1 = pcall(getRemapInput, 1)
		local ok2, r2 = pcall(getRemapInput, 2)
		if ok1 and ok2 then
			tutorial.rec.remap = {r1, r2}
			pcall(remapInput, 1, r2)
			pcall(remapInput, 2, r1)
		end
		tutorial.f_stopScript(2)
		f_quietDummy()
	end
end

-- Give the controllers back after a dummy take.
local function f_releaseRecording(rec)
	if rec ~= nil and rec.remap ~= nil then
		pcall(remapInput, 1, rec.remap[1])
		pcall(remapInput, 2, rec.remap[2])
	end
end

-- Drop a take without printing it (the match is ending or being torn down).
function tutorial.f_cancelRecording()
	local rec = tutorial.rec
	tutorial.rec = nil
	f_releaseRecording(rec)
end

local function f_heldNow(pn)
	player(pn)
	local set, any = {}, false
	for _, k in ipairs(tutorial.t_scriptInputs) do
		local ok, t = pcall(inputTime, k)
		if ok and type(t) == 'number' and t > 0 then
			set[k], any = true, true
		end
	end
	player(1)
	return set, any
end

-- restart: after a dummy take, start the lesson over so the dummy's own settings and script come
-- back (false when the lesson is being cleared, which moves on by itself).
function tutorial.f_finishRecording(restart)
	local rec = tutorial.rec
	tutorial.rec = nil
	if rec == nil then
		return
	end
	f_releaseRecording(rec)
	if rec.pn == 2 and restart ~= false and tutorial.data ~= nil and #tutorial.data.lessons > 0 then
		local ct = math.min(tutorial.data.currentlesson, #tutorial.data.lessons)
		tutorial.f_gotoLesson(ct, false, true)
		tutorial.data.lessons[ct].pagesSeen = true
	end
	local f = rec.frames
	-- Leading and trailing frames with nothing held carry nothing, and neither does the start
	-- press that paused the game to end the take.
	while #f > 0 and (next(f[#f]) == nil or (f[#f].s and f_setText(f[#f]) == 's')) do
		table.remove(f)
	end
	if #f == 0 then
		print('Dojo: Record Demo stopped with nothing recorded.')
		return
	end
	f[#f + 1] = {}
	-- Spelled the way the profile's own files are written; either prefix reads the same.
	local prefix = tutorial.profile.id == 'trials' and 'trial.' or 'lesson.'
	local line = prefix .. (rec.pn == 2 and 'dummyscript = ' or 'demoscript = ') .. tutorial.f_scriptText(f)
	print('Dojo: recorded ' .. #f .. ' frames:\n' .. line)
	local ok = pcall(main.f_fileWrite, tutorial.recordPath, line .. '\n')
	if ok then
		print('Dojo: also written to ' .. tutorial.recordPath .. '.')
	end
	tutorial.lastRecording = line
end

-- Every frame of the match loop, paused or not: pausing is what ends a take.
function tutorial.f_recordTick()
	local rec = tutorial.rec
	if rec == nil then
		return
	end
	if paused() then
		-- Still armed is the pause that started the take; past that, a pause ends it, even one
		-- with nothing recorded yet (which also hands a dummy take's controllers back).
		if rec.phase ~= 'armed' then
			tutorial.f_finishRecording()
		end
		return
	end
	local set, any = f_heldNow(rec.pn or 1)
	if rec.phase == 'armed' then
		if not any then
			rec.phase = 'waiting'
		end
	elseif rec.phase == 'waiting' then
		-- the take starts with the first input, not with dead air
		if any then
			rec.phase = 'recording'
			rec.frames[1] = set
		end
	else
		rec.frames[#rec.frames + 1] = set
		if #rec.frames >= tutorial.scriptMaxFrames then
			tutorial.f_finishRecording()
		end
	end
end

--;===========================================================
--; menu.lua
--;===========================================================

if menu.tutorialadvancement == nil then
	menu.tutorialadvancement = 1
end
if menu.tutorialresetonsuccess == nil then
	menu.tutorialresetonsuccess = 1
end
if menu.tutoriallayout == nil then
	menu.tutoriallayout = 1
end
if menu.tutorialhints == nil then
	menu.tutorialhints = 1
end
if menu.tutorialtextboxes == nil then
	menu.tutorialtextboxes = 1
end
if menu.tutorialspeedrun == nil then
	menu.tutorialspeedrun = 2
end
-- One state per clear, so wiping this character does not leave the everything row claiming it too.
if menu.tutorialclearprogress == nil then
	menu.tutorialclearprogress = 1
end
if menu.tutorialclearcharprogress == nil then
	menu.tutorialclearcharprogress = 1
end

-- [Trials Pause Menu]'s itemnames: Trials Mode 1.x's, plus trials* names for the rows added since.
-- They are renamed to the shared tutorial* ones before the engine builds its menus (menu.f_start
-- runs after every module has loaded), so the shipped section, an old screenpack's and one that
-- uses the shared names directly all work. menu.valuename keys are <itemname>_<value>, so they are
-- renamed by the same table.
tutorial.t_legacyPauseItems = {
	trialsinstructions = 'tutorialinstructions',
	trialsdemo = 'tutorialdemo',
	trialsrecord = 'tutorialrecord',
	trialsrecorddummy = 'tutorialrecorddummy',
	trialsrestart = 'tutorialrestart',
	trialshints = 'tutorialhints',
	trialschapter = 'tutorialchapter',
	trialslist = 'tutoriallist',
	trialsopts = 'tutorialopts',
	trialsspeedrun = 'tutorialspeedrun',
	nexttrial = 'tutorialnext',
	previoustrial = 'tutorialprevious',
	trialadvancement = 'tutorialadvancement',
	trialresetonsuccess = 'tutorialresetonsuccess',
	trialslayout = 'tutoriallayout',
	trialstextboxes = 'tutorialtextboxes',
	trialsprogress = 'tutorialprogress',
	trialsclearcharprogress = 'tutorialclearcharprogress',
	trialsclearcharconfirm = 'tutorialclearcharconfirm',
	trialsclearprogress = 'tutorialclearprogress',
	trialsclearconfirm = 'tutorialclearconfirm',
	trialsdifficulty = 'tutorialdifficulty',
}

local function f_renameLegacyPause(sec)
	if type(sec) ~= 'table' or type(sec.menu) ~= 'table' then
		return
	end
	local map = tutorial.t_legacyPauseItems
	local function rename(key)
		local parts = main.f_strsplit('_', key)
		local changed = false
		for i, c in ipairs(parts) do
			if map[c] ~= nil then
				parts[i] = map[c]
				changed = true
			end
		end
		return changed and table.concat(parts, '_') or key
	end
	if type(sec.menu.itemname_order) == 'table' then
		-- A row declared under both spellings is kept once, where it first appears (spacers repeat
		-- on purpose and are left alone).
		local order, seen = {}, {}
		for _, suffix in ipairs(sec.menu.itemname_order) do
			local new = rename(suffix)
			if new ~= suffix and type(sec.menu.itemname) == 'table' and sec.menu.itemname[new] == nil then
				sec.menu.itemname[new] = sec.menu.itemname[suffix]
			end
			if not seen[new] or new:match('spacer%d*$') then
				seen[new] = true
				table.insert(order, new)
			end
		end
		for i = #sec.menu.itemname_order, 1, -1 do
			sec.menu.itemname_order[i] = nil
		end
		for i, suffix in ipairs(order) do
			sec.menu.itemname_order[i] = suffix
		end
	end
	if type(sec.menu.valuename) == 'table' then
		local moved = {}
		for k, v in pairs(sec.menu.valuename) do
			local item, value = tostring(k):match('^([^_]+)_(.*)$')
			if item ~= nil and map[item] ~= nil then
				moved[map[item] .. '_' .. value] = v
			end
		end
		for k, v in pairs(moved) do
			if sec.menu.valuename[k] == nil then
				sec.menu.valuename[k] = v
			end
		end
	end
end
f_renameLegacyPause(tutorial.f_pauseSection(tutorial.t_profiles.trials))

-- The value labels of the pause menu's options, from the profile in force's section. Rebuilt by
-- f_useProfile, so Trials and the tutorial tracks can label them differently.
function tutorial.f_menuValueNames()
local pmv = f_pauseMenuValues()

menu.t_valuename.tutorialadvancement = {
	{itemname = "autoadvance", displayname = pmv.tutorialadvancement_autoadvance or "Auto-Advance"},
	{itemname = "repeat", displayname = pmv.tutorialadvancement_repeat or "Repeat"}
}
menu.t_valuename.tutorialresetonsuccess = {
	{itemname = "enabled", displayname = pmv.tutorialresetonsuccess_enabled or "Yes"},
	{itemname = "disabled", displayname = pmv.tutorialresetonsuccess_disabled or "No"}
}
menu.t_valuename.tutoriallayout = {
	{itemname = "vertical", displayname = pmv.tutoriallayout_vertical or "Vertical"},
	{itemname = "horizontal", displayname = pmv.tutoriallayout_horizontal or "Horizontal"}
}
menu.t_valuename.tutorialhints = {
	{itemname = "show", displayname = pmv.tutorialhints_show or "Show"},
	{itemname = "hide", displayname = pmv.tutorialhints_hide or "Hide"}
}
menu.t_valuename.tutorialtextboxes = {
	{itemname = "show", displayname = pmv.tutorialtextboxes_show or "Show"},
	{itemname = "hide", displayname = pmv.tutorialtextboxes_hide or "Hide"}
}
menu.t_valuename.tutorialspeedrun = {
	{itemname = "enabled", displayname = pmv.tutorialspeedrun_enabled or "On"},
	{itemname = "disabled", displayname = pmv.tutorialspeedrun_disabled or "Off"}
}
-- Clearing progress has nothing to display until it has happened, and then it has to say so: the
-- pause menu is drawn over a frozen match, so there is nowhere to put a dialog and nothing else on
-- screen would change. The row reads back "Cleared" until the menu is reset.
menu.t_valuename.tutorialclearprogress = {
	{itemname = "ready", displayname = pmv.tutorialclearprogress_ready or ""},
	{itemname = "cleared", displayname = pmv.tutorialclearprogress_cleared or "Cleared"}
}
end
tutorial.f_menuValueNames()
-- Moves the match to one Lesson and leaves the pause menu, the way its own Continue does.
-- Latching the fade is what actually repositions the pair: f_tutorialFade sets
-- _iksys_tutorialReposition, f_tutorialDummySetup only sets life and dummy mode.
--   keepTimer - starting a run rather than jumping within one, so the total timer stays armed and
--               restarts here. A plain jump retires the timer, because the run is no longer a run.
--   noMenu    - called from the select screen at match load, with no pause menu to leave.
function tutorial.f_gotoLesson(index, keepTimer, noMenu)
	if tutorial.data == nil or not tutorial.data.tutorialInitialized or tutorial.data.lessons[index] == nil then
		return true
	end
	-- Next / Previous Lesson can't jump into a lesson its gated file has not opened. A speedrun
	-- (keepTimer) plays everything in order, so it is never stopped by this.
	if not keepTimer and tutorial.f_isLocked(index) then
		return true
	end
	-- Going anywhere else ends a demo first, so the player always gets their controller back.
	if tutorial.f_demoActive() then
		tutorial.f_endDemo(false)
	end
	tutorial.f_stopScript(2)
	-- Picking a Lesson is what dismisses the select view, wherever it was picked from.
	if tutorial.select ~= nil and tutorial.select.open then
		tutorial.select.open = false
		tutorial.f_menuHold(false)
	end
	tutorial.f_spendState()
	tutorial.data.currentlessonstep = 1
	tutorial.data.currentlessonmicrostep = 1
	tutorial.data.comboCounter = 0
	tutorial.data.currentlesson = index
	tutorial.data.successlesson = nil
	-- Picking a Lesson cancels the banner the previous one may still be showing. Left up, it would
	-- keep running against the Lesson just jumped to and mark that one complete.
	tutorial.draw.success = 0
	tutorial.data.lessons[index].complete = false
	tutorial.data.lessons[index].active = false
	-- Entering a lesson starts its repetitions over and shows its pages again.
	tutorial.data.lessons[index].repsdone = 0
	tutorial.data.lessons[index].pagesSeen = false
	tutorial.data.active = false
	tutorial.data.allclear = false
	if keepTimer then
		tutorial.data.displaytimers.totaltimer = opts.TotalTimer ~= false
	else
		tutorial.data.displaytimers.totaltimer = false
		tutorial.data.runValid = false
	end
	tutorial.f_armTimers(index, keepTimer)
	tutorial.draw.fadein = tutorial.tutorial_mode.fadein_time
	tutorial.draw.fadeout = tutorial.tutorial_mode.fadeout_time
	tutorial.draw.fade = tutorial.draw.fadein + tutorial.draw.fadeout
	tutorial.draw.fadetriggered = true
	if not noMenu then
		menu.currentMenu[1] = menu.currentMenu[2]
		menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
	end
	return false
end

menu.t_itemname['tutorialadvancement'] = function(t, item, cursorPosY, moveTxt, sec)
	if tutorial.f_speedrunEnabled() then
		-- Repeat would stall a run, so a speedrun holds Advancement at Auto-Advance.
		return true
	end
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if tutorial.data ~= nil then
			if value == "autoadvance" then
				tutorial.data.tutorialadvancement = true
			else
				tutorial.data.tutorialadvancement = false
			end
		end
		tutorial.f_savePref('Advancement', value)
	end
	return true
end
menu.t_vardisplay['tutorialadvancement'] = function()
	return menu.t_valuename.tutorialadvancement[menu.tutorialadvancement or 1].displayname
end

options.t_vardisplay['tutorialadvancement'] = function()
	return menu.t_valuename.tutorialadvancement[menu.tutorialadvancement or 1].displayname
end

menu.t_itemname['tutoriallayout'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "vertical" then
			tutorial.tutorial_mode.tutoriallayout = "vertical"
		else
			tutorial.tutorial_mode.tutoriallayout = "horizontal"
		end
		tutorial.f_savePref('Layout', tutorial.tutorial_mode.tutoriallayout)
	end
	return true
end
menu.t_vardisplay['tutoriallayout'] = function()
	return menu.t_valuename.tutoriallayout[menu.tutoriallayout or 1].displayname
end

options.t_vardisplay['tutoriallayout'] = function()
	return menu.t_valuename.tutoriallayout[menu.tutoriallayout or 1].displayname
end

menu.t_itemname['tutorialresetonsuccess'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "enabled" then
			tutorial.tutorial_mode.tutorialresetonsuccess = true
		else
			tutorial.tutorial_mode.tutorialresetonsuccess = false
		end
		tutorial.f_savePref('ResetOnSuccess', tutorial.tutorial_mode.tutorialresetonsuccess)
	end
	return true
end
menu.t_vardisplay['tutorialresetonsuccess'] = function()
	return menu.t_valuename.tutorialresetonsuccess[menu.tutorialresetonsuccess or 1].displayname
end

options.t_vardisplay['tutorialresetonsuccess'] = function()
	return menu.t_valuename.tutorialresetonsuccess[menu.tutorialresetonsuccess or 1].displayname
end

menu.t_itemname['tutorialhints'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		tutorial.f_savePref('Hints', value == 'show')
	end
	return true
end
menu.t_vardisplay['tutorialhints'] = function()
	return menu.t_valuename.tutorialhints[menu.tutorialhints or 1].displayname
end
options.t_vardisplay['tutorialhints'] = function()
	return menu.t_valuename.tutorialhints[menu.tutorialhints or 1].displayname
end

-- Leaves the pause menu the way picking a lesson from the list does.
local function f_leavePause()
	menu.currentMenu[1] = menu.currentMenu[2]
	menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
end

-- Show Instructions: the current lesson's pages again, over the match.
menu.t_itemname['tutorialinstructions'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.data ~= nil and tutorial.data.tutorialInitialized then
		-- Demonstrations-only: the pages need the controller the demo has switched off. The demo
		-- starts over once they close.
		local l = tutorial.data.lessons[tutorial.data.currentlesson]
		if tutorial.f_demoOnly() and l ~= nil and type(l.pages) == 'table' and #l.pages > 0 then
			tutorial.f_endDemo(false)
		end
		if tutorial.f_openPages(tutorial.data.currentlesson) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			f_leavePause()
		else
			-- this lesson has no pages
			sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		end
	end
	return true
end

-- Watch Demo: the CPU plays the lesson's lesson.demoscript. Not during a speedrun, which it would void.
menu.t_itemname['tutorialdemo'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.data ~= nil and tutorial.data.tutorialInitialized then
		local ct_ = math.min(tutorial.data.currentlesson, #tutorial.data.lessons)
		if not tutorial.f_speedrunEnabled() and not tutorial.f_demoActive() and tutorial.f_hasDemo(ct_) and tutorial.f_startDemo(ct_) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			f_leavePause()
		else
			sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		end
	end
	return true
end

-- Record Demo: see tutorial.f_recordTick. Not offered unless RecordDemo is on.
menu.t_itemname['tutorialrecord'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.recordEnabled and tutorial.data ~= nil and not tutorial.f_demoActive() then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		tutorial.f_startRecording(1)
		f_leavePause()
	end
	return true
end

-- Record Dummy: the same for P2, played on the author's controller; see tutorial.f_startRecording.
menu.t_itemname['tutorialrecorddummy'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.recordEnabled and tutorial.data ~= nil and not tutorial.f_demoActive() then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		tutorial.f_startRecording(2)
		f_leavePause()
	end
	return true
end

-- Restart Lesson: back to its first step and its start positions, repetitions and pages included.
menu.t_itemname['tutorialrestart'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.data ~= nil and #tutorial.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return tutorial.f_gotoLesson(math.min(tutorial.data.currentlesson, #tutorial.data.lessons))
	end
	return true
end

menu.t_itemname['tutorialtextboxes'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "show" then
			tutorial.tutorial_mode.textbox_visible = true
		else
			tutorial.tutorial_mode.textbox_visible = false
		end
		tutorial.tutorial_mode.textbox.visible = tutorial.tutorial_mode.textbox_visible
		tutorial.f_savePref('Textboxes', value)
	end
	return true
end
menu.t_vardisplay['tutorialtextboxes'] = function()
	return menu.t_valuename.tutorialtextboxes[menu.tutorialtextboxes or 1].displayname
end

options.t_vardisplay['tutorialtextboxes'] = function()
	return menu.t_valuename.tutorialtextboxes[menu.tutorialtextboxes or 1].displayname
end


menu.t_itemname['tutorialspeedrun'] = function(t, item, cursorPosY, moveTxt, sec)
	-- A Game Tutorial whose lessons need more than one P1 reloads the match between them, and a
	-- run cannot survive that, so Speedrun Mode stays Off there.
	-- Nor in demonstrations-only, where there is nothing to clear.
	if tutorial.f_speedrunSpansChars() or tutorial.f_demoOnly() then
		return true
	end
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		menu.tutorialspeedrun = value == "enabled" and 1 or 2
		tutorial.f_applySpeedrun()
		for _, v in ipairs(menu.t_vardisplayPointers) do
			if v.itemname == 'tutorialspeedrun' then
				v.vardisplay = menu.f_vardisplay('tutorialspeedrun')
			end
		end
		if value == "enabled" then
			tutorial.f_startSpeedrun()
			-- Leave the menu the way picking a Lesson does: the run starts now.
			menu.currentMenu[1] = menu.currentMenu[2]
			menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
			return false
		end
	end
	return true
end
-- On/Off, followed by this character's best full run if they have one - the only place a run
-- record would otherwise have to show itself.
local function f_speedrunVardisplay()
	local label = menu.t_valuename.tutorialspeedrun[menu.tutorialspeedrun or 2].displayname
	local rec = tutorial.f_speedrunRecord()
	if rec ~= nil and rec.besttime ~= nil then
		local m, s, x = f_timeConvert(rec.besttime)
		label = label .. '  ' .. m .. ':' .. s .. ':' .. x
	end
	return label
end
menu.t_vardisplay['tutorialspeedrun'] = f_speedrunVardisplay
options.t_vardisplay['tutorialspeedrun'] = f_speedrunVardisplay

local t_clears = {
	{
		row = 'tutorialclearprogress',
		confirm = 'tutorialclearconfirm',
		yes = 'Yes, Erase Everything',
		no = 'No',
		run = function()
			tutorial.f_clearProgress()
			return true
		end,
	},
	{
		row = 'tutorialclearcharprogress',
		confirm = 'tutorialclearcharconfirm',
		yes = 'Yes, Erase This Character',
		no = 'No',
		-- Whoever is loaded into P1. Nothing is acknowledged when there is no character to resolve;
		-- the module has already said why on the console.
		run = function()
			return tutorial.f_clearCharProgress()
		end,
	},
}

local t_clearRows = {}
for _, c in ipairs(t_clears) do
	t_clearRows[c.row] = c
	local function f_clearVardisplay()
		return menu.t_valuename.tutorialclearprogress[menu[c.row] or 1].displayname
	end
	menu.t_vardisplay[c.row] = f_clearVardisplay
	menu.t_vardisplay[c.confirm] = f_clearVardisplay
	menu.t_itemname[c.confirm] = function(t, item, cursorPosY, moveTxt, sec)
		if getInput(-1, sec.menu.done.key) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			if c.run() then
				menu[c.row] = 2
				for _, v in ipairs(menu.t_vardisplayPointers) do
					if v.itemname == c.row or v.itemname == c.confirm then
						v.vardisplay = menu.f_vardisplay(v.itemname)
					end
				end
			end
		end
		-- Staying put is what makes the acknowledgement visible: leaving would drop the player at
		-- the top of the pause menu (the engine's Back goes to the root, not up a level), where
		-- neither row is on screen to read "Cleared" back to them.
		return true
	end
end

local function f_fillClearConfirm(tbl)
	if type(tbl) ~= 'table' or type(tbl.submenu) ~= 'table' then
		return
	end
	for name, sub in pairs(tbl.submenu) do
		if type(sub) == 'table' then
			local c = t_clearRows[name]
			if c ~= nil and type(sub.items) == 'table' and #sub.items == 0 then
				sub.items[1] = {itemname = c.confirm, displayname = c.yes, paramname = c.confirm,
					vardisplay = menu.f_vardisplay(c.confirm), selected = false}
				sub.items[2] = {itemname = 'back', displayname = c.no, paramname = 'back', vardisplay = '', selected = false}
				table.insert(menu.t_vardisplayPointers, sub.items[1])
			end
			f_fillClearConfirm(sub)
		end
	end
end

-- menu.f_start() builds every pause menu from the motif's itemnames, and main.lua calls it after
-- the last module has loaded, so there is nothing to walk until it has run. Another module wrapping
-- it too, before or after this one, simply chains.
-- Opening the pause menu refilters its root for the entry being played (see f_rootItemShown).
local f_menuInit = menu.f_init
function menu.f_init(...)
	if tutorial.f_inMode() then
		tutorial.f_applySpeedrun()
	end
	if f_menuInit ~= nil then
		return f_menuInit(...)
	end
end

local f_menuStart = menu.f_start
function menu.f_start(...)
	if f_menuStart ~= nil then
		f_menuStart(...)
	end
	for _, v in ipairs(menu.t_menus or {}) do
		f_fillClearConfirm(menu[v.id])
	end
end

menu.t_itemname['tutorialnext'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.data ~= nil and #tutorial.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return tutorial.f_gotoLesson(tutorial.data.currentlesson % #tutorial.data.lessons + 1)
	end
	return true
end

menu.t_itemname['tutorialprevious'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and tutorial.data ~= nil and #tutorial.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return tutorial.f_gotoLesson((tutorial.data.currentlesson - 2) % #tutorial.data.lessons + 1)
	end
	return true
end

local t_tutorialPrefs = {
	tutorialadvancement = true,
	tutorialresetonsuccess = true,
	tutoriallayout = true,
	tutorialtextboxes = true,
	tutorialhints = true,
	tutorialspeedrun = true,
	tutorialclearprogress = true,
	tutorialclearconfirm = true,
	tutorialclearcharprogress = true,
	tutorialclearcharconfirm = true,
}

function menu.f_tutorialReset()
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		menu.tutorialadvancement = 1
	else
		menu.tutorialadvancement = 2
	end
	if tutorial.tutorial_mode.tutorialresetonsuccess == true then
		menu.tutorialresetonsuccess = 1
	else
		menu.tutorialresetonsuccess = 2
	end
	if tutorial.tutorial_mode.tutoriallayout == "vertical" then
		menu.tutoriallayout = 1
	else
		menu.tutoriallayout = 2
	end
	if (opts.Textboxes ~= nil and tostring(opts.Textboxes):lower() ~= "hide")
		or (opts.Textboxes == nil and tutorial.tutorial_mode.textbox_visible == true) then
		menu.tutorialtextboxes = 1
	else
		menu.tutorialtextboxes = 2
	end
	menu.tutorialhints = tutorial.f_hintsOn() and 1 or 2
	-- "Cleared" is an acknowledgement of something that just happened, not a state to carry into
	-- the next match.
	menu.tutorialclearprogress = 1
	menu.tutorialclearcharprogress = 1
	for _, v in ipairs(menu.t_vardisplayPointers) do
		if t_tutorialPrefs[v.itemname] then
			v.vardisplay = menu.f_vardisplay(v.itemname)
		end
	end
	tutorial.f_applySpeedrun()
	player(2)
	setAILevel(0)
	mapSet('_iksys_tutorialDummyControl', 0)
	mapSet('_iksys_tutorialDummyMode', 0)
	mapSet('_iksys_tutorialGuardMode', 0)
	mapSet('_iksys_tutorialFallRecovery', 0)
	mapSet('_iksys_tutorialDistance', 0)
	mapSet('_iksys_tutorialButtonJam', 0)
	mapSet('_iksys_tutorialReposition', 0)
	mapSet('_iksys_tutorialSetLife', lifeMax())
	player(1)
	mapSet('_iksys_tutorialSetLife', lifeMax())
end

--;===========================================================
--; dojo.lua
--;===========================================================

--;===========================================================
--; Lesson files
--;===========================================================
-- A lesson file is read the same way wherever it comes from: a character's def names one with
-- `tutorial = tutorial.def` (the character track), and config.ini's SystemTutorial lists any
-- number of them (the system track, playable with every character).
--
-- Sections:   [Tutorial]                 file-wide settings (tutorial.gated)
--             [Chapter, <name>]          declares a chapter and its chapter.text
--             [Lesson, <name>]           one lesson; [TrialDef, <name>] is accepted as an alias
-- Keys are matched whole, case-insensitively. trial.* and trialstep.* are aliases of lesson.* and
-- lessonstep.*, so a Trials Mode file loads unchanged.

-- Keys that take a language suffix (lesson.textbox.es); the language picked is resolved at the
-- end of the file so the order the lines come in does not matter.
local t_multilingual = {
	['lesson.textbox'] = true,
	['lesson.hint'] = true,
	['chapter.text'] = true,
}

-- lesson.* keys holding a whole number of frames (or a count), 0 or more.
local t_lessonCounts = {
	dummyjumpdelay = 'jumpdelay',
	dummybuttondelay = 'buttondelay',
	['repeat'] = 'reps',
	hintafter = 'hintafter',
	demoafter = 'demoafter',
	dummyscriptdelay = 'dummyscriptdelay',
}

-- lessonstep.X.* list fields: commas separate microsteps. The id lists also take '|' alternatives.
local t_stepIdLists = {stateno = true, animno = true, projid = true, p2stateno = true}
local t_stepNumLists = {hitcount = true, validfortickcount = true,
	iconanim = true, iconanimoffset = true, iconanimscale = true, iconanimwindow = true}
local t_stepBoolLists = {isthrow = true, iscounterhit = true, ishelper = true, isproj = true, isguarded = true}
local t_guardValues = {any = true, high = true, low = true, air = true}

-- A chapter's id is its name folded to something usable as a dojo.def key, so a
-- screenpack can style tutorialmenu.item.<id>.* per chapter. Ids that would land on a structural
-- key of that block get a trailing underscore.
local t_reservedCats = {all = true, other = true, text = true, bg = true, active = true, selected = true,
	overlay = true, locked = true, value = true, spacing = true, offset = true}
function tutorial.f_chapterId(name)
	local id = tostring(name or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
	if id ~= '' and (t_reservedCats[id] or tutorial.t_difficultyIndex[id]) then
		id = id .. '_'
	end
	return id
end
tutorial.t_difficultyIndex = {}
for _, d in ipairs(tutorial.t_difficulty) do tutorial.t_difficultyIndex[d] = true end

-- Display names for chapter ids, filled as files are read; the select header looks names up here.
tutorial.chapterNames = tutorial.chapterNames or {}
tutorial.chapterText = tutorial.chapterText or {}

local function f_newLesson(name)
	return {
		name = name,
		difficulty = "",
		dummymode = "stand",
		guardmode = "none",
		buttonjam = "none",
		buttondelay = nil, -- resolved per mode when the Lesson starts
		jumpdelay = tutorial.jumpDelayDefault,
		active = false,
		complete = false,
		p1life = -1,
		p2life = -1,
		playerpos = nil,
		dummypos = nil,
		playerposoffset = {0,0},
		dummyposoffset = {0,0},
		showforvar = {nil},
		showforval = {nil},
		elapsedtime = 0,
		textbox = "",
		textcnt = 0,
		starttick = roundTime()+1,
		steps = {},
		-- Tutorial Mode additions
		chapter = "",
		chars = nil,     -- set of lowercase names / folders / def paths; nil = everyone
		playerchar = nil, -- game-wide lessons: P1 forced in the Game Tutorial (select.def spelling)
		reps = 1,        -- clears needed (lesson.repeat)
		repsdone = 0,
		hint = "",
		hintafter = 0,   -- failures before the hint shows; 0 = shown from the start
		demoafter = 0,   -- failures before the demo is offered; 0 = never offered
		fails = 0,
		demoscript = "",
		dummyscript = "",
		dummyscriptloop = false,
		dummyscriptdelay = 0,
		pages = {},
	}
end

local function f_newStep()
	return {
		numofmicrosteps = 1,
		text = "",
		glyphs = "",
		stateno = {},
		animno = {},
		projid = {},
		p2stateno = {},
		hitcount = {},
		stephitscount = {},
		comboCountonstep = {},
		isthrow = {},
		ishelper = {},
		isproj = {},
		iscounterhit = {},
		isguarded = {},
		guard = {},
		validfortickcount = {},
		validforvar = {},
		validforval = {},
		iconanim = {},
		iconanimoffset = {},
		iconanimscale = {},
		iconanimwindow = {},
		glyphline = {
			vertical = {glyph = {}, pos = {}, width = {}, alignOffset = {}, lengthOffset = {}, scale = {}},
			horizontal = {glyph = {}, pos = {}, width = {}, alignOffset = {}, lengthOffset = {}, scale = {}},
		},
	}
end

-- Fills every microstep's defaults once the whole step has been read. The microstep count comes
-- from the id lists (and guard), as it always has: hitcount and the flags follow it.
local function f_finishStep(step)
	local n = math.max(1, #step.stateno, #step.animno, #step.projid, #step.p2stateno, #step.guard)
	step.numofmicrosteps = n
	for k = 1, n, 1 do
		if step.stephitscount[k] == nil then step.stephitscount[k] = 0 end
		if step.comboCountonstep[k] == nil then step.comboCountonstep[k] = 0 end
		if step.hitcount[k] == nil then step.hitcount[k] = 1 end
		for f in pairs(t_stepBoolLists) do
			if step[f][k] == nil then step[f][k] = false end
		end
	end
	-- The icon fields describe one sprite for the whole step, not one per microstep.
	if #step.iconanim == 0 then
		local spr = tutorial.tutorial_mode.textbox.portrait.spr
		if spr ~= nil then
			step.iconanim = {spr[1], spr[2], 0, 0, -1}
		else
			step.iconanim = {0, 0, 0, 0, -1}
		end
	end
	if #step.iconanimoffset == 0 then step.iconanimoffset = {0, 0} end
	if #step.iconanimscale == 0 then step.iconanimscale = {1, 1} end
	if #step.iconanimwindow == 0 then step.iconanimwindow = {0, 0, 0, 0} end
end

-- '1, 2|3' -> {{1}, {2, 3}}
local function f_idList(v)
	local t = main.f_strsplit(',', (v:gsub('%s+', '')))
	for k = 1, #t, 1 do
		t[k] = f_str2number(main.f_strsplit('|', t[k]))
	end
	return t
end

local function f_numList(v)
	return f_str2number(main.f_strsplit(',', (v:gsub('%s+', ''))))
end

-- A single true/false value; anything but true, yes or 1 is false.
local function f_flag(v)
	v = tostring(v or ''):lower()
	return v == 'true' or v == 'yes' or v == '1'
end

local function f_boolList(v)
	return f_str2boolean(main.f_strsplit(',', (v:gsub('%s+', ''))))
end

-- Picks the text for the configured language: .<lang>, then .en, then the bare key.
local function f_pickLang(cands, lang)
	if cands == nil then
		return nil
	end
	return cands[lang] or cands.en or cands['']
end

-- Parses one lesson file. track is 'char' or 'system'; label names the file in console warnings.
-- Returns {lessons = {...}, gated = bool} or nil when the file cannot be read.
function tutorial.f_parseFile(path, track, label)
	local ok, src = pcall(loadText, path)
	if not ok or type(src) ~= 'string' then
		print('Dojo: could not read lesson file ' .. tostring(path) .. '.')
		return nil
	end
	label = label or path
	local lang = tostring(gameOption('Config.Language') or 'en'):lower()
	local function warn(msg)
		print('Dojo: ' .. label .. ' - ' .. msg)
	end

	local out = {lessons = {}, gated = false}
	local section = nil      -- 'tutorial' | 'chapter' | 'lesson' | 'unknown'
	local lesson = nil       -- the lesson being read
	local chapterId = nil    -- the chapter being read
	local ml = nil           -- multilingual candidates for the current lesson/chapter: ml[key][suffix]
	local steps = nil        -- sparse steps of the current lesson, keyed by number
	local pageml = nil       -- page candidates: pageml[n][field][suffix]
	local names = {}         -- dupe counter, for progress keys

	local function closeSection()
		if section == 'lesson' and lesson ~= nil then
			lesson.textbox = f_pickLang(ml['lesson.textbox'], lang) or ''
			lesson.hint = f_pickLang(ml['lesson.hint'], lang) or ''
			-- Steps may be written in any order; they are numbered 1..n and a gap is reported.
			local max = 0
			for n in pairs(steps) do
				if n > max then max = n end
			end
			for n = 1, max, 1 do
				local s = steps[n]
				if s == nil then
					warn('"' .. lesson.name .. '" has no lessonstep.' .. n .. '; the steps after it are numbered down.')
				else
					s.step.text = f_pickLang(s.text, lang) or ''
					f_finishStep(s.step)
					lesson.steps[#lesson.steps + 1] = s.step
				end
			end
			local pmax = 0
			for n in pairs(pageml) do
				if n > pmax then pmax = n end
			end
			for n = 1, pmax, 1 do
				local p = pageml[n]
				if p ~= nil then
					lesson.pages[#lesson.pages + 1] = {
						title = f_pickLang(p.title, lang) or '',
						text = f_pickLang(p.text, lang) or '',
						portrait = p.portrait, -- spr / anim / source of its own, each nil when the def's is used
						snd = p.snd,
					}
				end
			end
			-- Input scripts are read now, so a typo is reported at load rather than when played.
			for _, f in ipairs({'demoscript', 'dummyscript'}) do
				if lesson[f] ~= '' then
					local frames, why = tutorial.f_parseScript(lesson[f])
					if frames == nil then
						warn('"' .. lesson.name .. '" has an unreadable lesson.' .. f .. ' (' .. why .. '); it is ignored.')
						lesson[f] = ''
					else
						lesson[f == 'demoscript' and 'demoframes' or 'dummyframes'] = frames
					end
				end
			end
			if #lesson.steps == 0 then
				warn('"' .. lesson.name .. '" has no steps and is skipped.')
			else
				names[lesson.name] = (names[lesson.name] or 0) + 1
				lesson.key = lesson.name
				if names[lesson.name] > 1 then
					lesson.key = lesson.name .. ' #' .. names[lesson.name]
				end
				lesson.track = track
				lesson.file = path:gsub('\\', '/'):lower()
				out.lessons[#out.lessons + 1] = lesson
			end
		elseif section == 'chapter' and chapterId ~= nil then
			local t = f_pickLang(ml['chapter.text'], lang)
			if t ~= nil then
				tutorial.chapterText[chapterId] = t
			end
		end
		section, lesson, chapterId, ml, steps, pageml = nil, nil, nil, nil, nil, nil
	end

	local lineno = 0
	for line in src:gmatch("([^\r\n]*)\r?\n?") do
		lineno = lineno + 1
		line = line:gsub('%s*;.*$', '')
		local head = line:match('^%s*%[(.-)%]%s*$')
		if head ~= nil then
			closeSection()
			local kind, name = head:match('^%s*([^,]-)%s*,%s*(.-)%s*$')
			if kind == nil then
				kind, name = head:match('^%s*(.-)%s*$'), ''
			end
			kind = kind:lower()
			ml, steps, pageml = {}, {}, {}
			if kind == 'lesson' or kind == 'trialdef' then
				section = 'lesson'
				if name == '' then
					name = (tutorial.profile.id == 'trials' and 'Trial ' or 'Lesson ') .. tostring(#out.lessons + 1)
				end
				lesson = f_newLesson(name)
			elseif kind == 'chapter' then
				section = 'chapter'
				chapterId = tutorial.f_chapterId(name)
				if chapterId == '' then
					warn('[Chapter] on line ' .. lineno .. ' has no name and is ignored.')
					section = 'unknown'
				elseif tutorial.chapterNames[chapterId] == nil then
					tutorial.chapterNames[chapterId] = name
				end
			elseif kind == 'tutorial' then
				section = 'tutorial'
			else
				section = 'unknown'
				warn('unknown section [' .. head .. '] on line ' .. lineno .. '; its keys are ignored.')
			end
		elseif line:find('=') then
			local key = line:match('^%s*(.-)%s*=') :lower()
			local raw = line:match('=%s*(.-)%s*$') or ''
			local val = raw:lower()
			key = key:gsub('^trialstep%.', 'lessonstep.'):gsub('^trial%.', 'lesson.')
			if section == 'tutorial' then
				if key == 'tutorial.gated' then
					out.gated = f_flag(val)
				end
			elseif section == 'chapter' then
				local base, suffix = key, ''
				if not t_multilingual[key] then
					base, suffix = key:match('^(.-)%.(%a%a%a?)$')
				end
				if base ~= nil and t_multilingual[base] then
					ml[base] = ml[base] or {}
					ml[base][suffix] = raw
				end
			elseif section == 'lesson' then
				local sn, field = key:match('^lessonstep%.(%d+)%.(.+)$')
				local pn, pfield = key:match('^lesson%.page%.(%d+)%.(.+)$')
				if sn ~= nil then
					sn = tonumber(sn)
					steps[sn] = steps[sn] or {step = f_newStep(), text = {}}
					local s = steps[sn]
					local step = s.step
					local tsuffix = field == 'text' and '' or field:match('^text%.(%a%a%a?)$')
					if tsuffix ~= nil then
						s.text[tsuffix] = raw
					elseif raw:gsub('%s+', '') == '' then
						-- declared but empty: leave the default
					elseif field == 'glyphs' then
						step.glyphs = raw
					elseif t_stepIdLists[field] then
						step[field] = f_idList(val)
					elseif t_stepNumLists[field] then
						step[field] = f_numList(val)
					elseif t_stepBoolLists[field] then
						step[field] = f_boolList(val)
					elseif field == 'guard' then
						step.guard = main.f_strsplit(',', (val:gsub('%s+', '')))
						for k, g in ipairs(step.guard) do
							if not t_guardValues[g] then
								warn('"' .. lesson.name .. '" lessonstep.' .. sn .. '.guard has an unknown value (' .. g .. '); expected any, high, low or air.')
								step.guard[k] = 'any'
							end
						end
					elseif field == 'validforvarvalpairs' then
						local pairs_ = f_numList(val)
						step.validforvar, step.validforval = {}, {}
						for k = 1, #pairs_ - 1, 2 do
							step.validforvar[#step.validforvar + 1] = pairs_[k]
							step.validforval[#step.validforval + 1] = pairs_[k + 1]
						end
					else
						warn('unknown key ' .. key .. ' on line ' .. lineno .. '.')
					end
				elseif pn ~= nil then
					pn = tonumber(pn)
					pageml[pn] = pageml[pn] or {title = {}, text = {}, portrait = {}}
					local pg = pageml[pn]
					local f, suffix = pfield:match('^(%a+)%.?(%a*)$')
					if f == 'title' or f == 'text' then
						pg[f][suffix or ''] = raw
					elseif pfield == 'portrait.spr' or pfield == 'snd' then
						-- g,n. -1 turns it off for this page, where the def would otherwise supply one.
						local nums = f_numList(val)
						if tonumber(nums[1]) ~= nil then
							local v = {nums[1], tonumber(nums[2]) or 0}
							if pfield == 'snd' then pg.snd = v else pg.portrait.spr = v end
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an invalid ' .. key .. ' (' .. val .. '). Expected group, number.')
						end
					elseif pfield == 'portrait.anim' then
						if tonumber(val) ~= nil then
							pg.portrait.anim = tonumber(val)
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an invalid ' .. key .. ' (' .. val .. '). Expected an action number.')
						end
					elseif pfield == 'portrait.source' then
						local v = val:gsub('"', '')
						if v == 'system' or v == 'char' then
							pg.portrait.source = v
						elseif v ~= '' then
							warn('"' .. lesson.name .. '" has an unknown ' .. key .. ' (' .. v .. '); expected system or char.')
						end
					else
						warn('unknown key ' .. key .. ' on line ' .. lineno .. '.')
					end
				else
					local base, suffix = key, ''
					if not t_multilingual[key] then
						base, suffix = key:match('^(.-)%.(%a%a%a?)$')
					end
					local f = key:match('^lesson%.(.+)$')
					if base ~= nil and t_multilingual[base] then
						ml[base] = ml[base] or {}
						ml[base][suffix] = raw
					elseif f == nil then
						warn('unknown key ' .. key .. ' on line ' .. lineno .. '.')
					elseif f == 'difficulty' then
						lesson.difficulty = ''
						if tutorial.t_difficultyIndex[val] then
							lesson.difficulty = val
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an unrecognised lesson.difficulty (' .. val
								.. '). Expected Beginner, Intermediate, Advanced or Expert.')
						end
					elseif f == 'chapter' then
						lesson.chapter = tutorial.f_chapterId(raw)
						if lesson.chapter ~= '' and tutorial.chapterNames[lesson.chapter] == nil then
							tutorial.chapterNames[lesson.chapter] = raw
						end
					elseif f == 'chars' then
						lesson.chars = {}
						for _, c in ipairs(main.f_strsplit(',', val)) do
							c = c:gsub('\\', '/'):match('^%s*(.-)%s*$')
							if c ~= '' then lesson.chars[c] = true end
						end
					elseif f == 'playerchar' then
						-- Game-wide lessons only: in a character's file P1 is that character already.
						if track ~= 'system' then
							warn('"' .. lesson.name .. '" sets lesson.playerchar, which only game-wide lessons take; it is ignored.')
						elseif val ~= '' then
							lesson.playerchar = raw:gsub('\\', '/'):match('^%s*(.-)%s*$')
						end
					elseif f == 'dummymode' then
						lesson.dummymode = val
					elseif f == 'guardmode' then
						lesson.guardmode = val
						if tutorial.t_guardMode[val] == nil then
							warn('"' .. lesson.name .. '" has an unknown lesson.guardmode (' .. val .. '); expected none, auto, afterhit or random.')
						end
					elseif f == 'dummybuttonjam' then
						lesson.buttonjam = val
					elseif t_lessonCounts[f] then
						local n = tonumber(val)
						if n ~= nil and n >= 0 and n == math.floor(n) then
							lesson[t_lessonCounts[f]] = n
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an invalid lesson.' .. f .. ' (' .. val .. '). Expected a whole number, 0 or more.')
						end
					elseif f == 'playerlife' then
						lesson.p1life = tonumber(val)
					elseif f == 'dummylife' then
						lesson.p2life = tonumber(val)
					elseif f == 'playerposoffset' or f == 'dummyposoffset' then
						if val:gsub('%s+', '') ~= '' then
							lesson[f] = f_numList(val)
						end
					elseif f == 'playerpos' or f == 'dummypos' then
						lesson[f] = val
					elseif f == 'showforvarvalpairs' or f == 'showvarvalpairs' then
						local temp = main.f_strsplit(',', (val:gsub('%s+', '')))
						lesson.showforvar = {}
						lesson.showforval = {}
						for k = 1, #temp - 1, 2 do
							lesson.showforvar[#lesson.showforvar + 1] = tonumber(temp[k])
							lesson.showforval[#lesson.showforval + 1] = f_str2number(main.f_strsplit('|', temp[k + 1]))
						end
					elseif f == 'demoscript' or f == 'dummyscript' then
						lesson[f] = raw
					elseif f == 'dummyscriptloop' then
						lesson.dummyscriptloop = f_flag(val)
					else
						warn('unknown key ' .. key .. ' on line ' .. lineno .. '.')
					end
				end
			end
		end
	end
	closeSection()
	for _, l in ipairs(out.lessons) do
		l.gated = out.gated
	end
	return out
end

--;===========================================================
--; Building and switching profiles
--;===========================================================
-- Builds one profile: its UI (every f_ui* step above, in the order they always ran at load)
-- and its saved progress. Leaves the profile in force, and keeps what was built on the profile so
-- f_useProfile can put it back later without building anything again.
function tutorial.f_buildProfile(p)
	f_loadAssets()
	tutorial.profile = p
	opts = p.opts
	local root, lx, ly = f_prepareUI(p)
	tutorial.tutorial_mode = root
	tr_pos = root
	tutorial.mtlcx, tutorial.mtlcy = lx, ly
	f_uiMenuDefaults()
	f_uiStepDefaults()
	f_uiAnchors()
	tutorial.vislcx = f_vislcx(f_screenAspect())
	tutorial.anchordelta = tutorial.vislcx - tutorial.mtlcx
	f_applyAnchors()
	f_uiElems()
	f_uiMenuDraw()
	f_uiTeach()
	p.ui = {
		root = root,
		mtlcx = lx,
		mtlcy = ly,
		anchored = t_anchored,
		elems = t_elems,
		menuDraw = tutorial.menuDraw,
		teach = tutorial.teach,
		vislcx = tutorial.vislcx,
	}
	p.progress = tutorial.f_loadProgress(p)
	tutorial.progress = p.progress
	tutorial.progressPath = p.progressPath
	tutorial.dummyPath, tutorial.stagePath, tutorial.playerCharPath = p.dummyPath, p.stagePath, p.playerCharPath
	p.built = true
end

-- Puts a built profile in force: its config, look, labels and save file. The pause menu nodes the
-- module takes over (the List, the root's items) are remembered per profile, because each game mode
-- has a pause menu of its own and round start puts back whichever one it took over.
function tutorial.f_useProfile(p)
	if not p.built then
		tutorial.f_buildProfile(p)
	end
	local cur = tutorial.profile
	if cur ~= nil and cur.ui ~= nil then
		cur.ui.vislcx = tutorial.vislcx
		cur.menuCache = {
			listTail = tutorial.listTail,
			listLoop = tutorial.listLoop,
			listNode = tutorial.listNode,
			rootItems = tutorial.rootItems,
			rootNode = tutorial.rootNode,
		}
	end
	tutorial.profile = p
	opts = p.opts
	tutorial.tutorial_mode = p.ui.root
	tr_pos = p.ui.root
	tutorial.mtlcx, tutorial.mtlcy = p.ui.mtlcx, p.ui.mtlcy
	t_anchored, t_elems = p.ui.anchored, p.ui.elems
	tutorial.menuDraw, tutorial.teach = p.ui.menuDraw, p.ui.teach
	tutorial.vislcx = p.ui.vislcx
	tutorial.anchordelta = tutorial.vislcx - tutorial.mtlcx
	local c = p.menuCache or {}
	tutorial.listTail, tutorial.listLoop, tutorial.listNode = c.listTail, c.listLoop, c.listNode
	tutorial.rootItems, tutorial.rootNode = c.rootItems, c.rootNode
	tutorial.progress = p.progress
	tutorial.progressPath = p.progressPath
	tutorial.dummyPath, tutorial.stagePath, tutorial.playerCharPath = p.dummyPath, p.stagePath, p.playerCharPath
	-- Drawn with the last profile's font; rebuilt from this one's the first time it is needed.
	tutorial.notutorialcounter = nil
	tutorial.f_menuValueNames()
end

-- Every enabled profile is built now. Character files are read with their own profile in force,
-- because a step's default portrait comes from that profile's textbox.portrait.
for _, id in ipairs(tutorial.t_profileOrder) do
	local p = tutorial.t_profiles[id]
	if p.enabled then
		tutorial.f_buildProfile(p)
	end
end

-- The character tracks: every character whose def names a file with `<charKey> = <file>` -
-- `trials = trials.def` for Trials, `tutorial = tutorial.def` for Character Guides. Both files are
-- read by the same parser, so either key may point at a file of either kind.
for _, id in ipairs(tutorial.t_profileOrder) do
	local p = tutorial.t_profiles[id]
	if p.enabled then
		tutorial.f_useProfile(p)
		local pattern = '^%s*' .. p.charKey .. '%s*='
		for row = 1, #main.t_selChars, 1 do
			local c = main.t_selChars[row]
			local file = ""
			if c.def ~= nil then
				local ok, deffile = pcall(loadText, c.def)
				if ok and type(deffile) == 'string' then
					for line in deffile:gmatch("([^\r\n]*)[\r\n]?") do
						line = line:gsub('%s*;.*$', '')
						if line:lower():match(pattern) then
							file = c.dir .. f_trimforchar(line, "=", "after")
							break
						end
					end
				end
			end
			c[p.charKey .. 'def'] = file
			if file ~= "" then
				local res = tutorial.f_parseFile(file, 'char', tostring(c.name))
				c[p.dataField] = res ~= nil and res.lessons or {}
			end
		end
	end
end

-- The system track: config.ini's [Config] SystemTutorial, a comma-separated list of lesson files.
-- Game-wide lessons belong to the tutorial tracks only.
tutorial.systemLessons = {}
if tutorial.t_profiles.tutorial.enabled then
	tutorial.f_useProfile(tutorial.t_profiles.tutorial)
	local list = tutorial.ini.Config.SystemTutorial
	-- loadIni may already have split a comma list into a table.
	if type(list) == 'table' then
		list = table.concat(list, ',')
	end
	if type(list) == 'string' then
		for _, p in ipairs(main.f_strsplit(',', list)) do
			p = p:gsub('\\', '/'):match('^%s*(.-)%s*$')
			if p ~= '' then
				local res = main.f_fileExists(p) and tutorial.f_parseFile(p, 'system', p) or nil
				if res == nil then
					print('Dojo: SystemTutorial file ' .. p .. ' could not be read; it is skipped.')
				else
					for _, l in ipairs(res.lessons) do
						tutorial.systemLessons[#tutorial.systemLessons + 1] = l
					end
				end
			end
		end
	end
end

-- Whether a system lesson's lesson.chars admits a character: matched against its display name,
-- its folder and its def path, all lowercase.
local function f_charAdmits(lesson, charData)
	if lesson.chars == nil then
		return true
	end
	local cands = {}
	if type(charData.name) == 'string' then cands[#cands + 1] = charData.name:lower() end
	if type(charData.def) == 'string' then
		local def = charData.def:gsub('\\', '/'):lower()
		cands[#cands + 1] = def
		cands[#cands + 1] = def:match('([^/]+)/[^/]*$')      -- folder: chars/kfm/kfm.def -> kfm
		cands[#cands + 1] = def:match('([^/]+)%.def$')       -- def name, as select.def often lists it
		cands[#cands + 1] = def:match('^chars/(.*)$')
	end
	if type(charData.char) == 'string' then cands[#cands + 1] = charData.char:gsub('\\', '/'):lower() end
	for _, c in ipairs(cands) do
		if c ~= nil and lesson.chars[c] then
			return true
		end
	end
	return false
end

-- Whether a game-wide lesson belongs on the track being played. A lesson.chars restriction makes a
-- game-wide lesson character content: the Game Tutorial leaves it out, and Character Guides offers it
-- to the characters it names. Combined offers every game-wide lesson its lesson.chars admits.
-- Trials never offers game-wide lessons: its profile has no system track.
local function f_systemOnTrack(lesson, charData)
	if not tutorial.profile.system then
		return false
	elseif tutorial.track == 'game' then
		return lesson.chars == nil
	elseif tutorial.track == 'chars' then
		return lesson.chars ~= nil and type(charData) == 'table' and f_charAdmits(lesson, charData)
	end
	return type(charData) == 'table' and f_charAdmits(lesson, charData)
end

-- The character's own file for the profile in force: its trials file in Trials, its lesson file
-- in the tutorial tracks. nil when it has none.
local function f_charLessons(charData)
	if tutorial.track == 'game' or type(charData) ~= 'table' then
		return nil
	end
	local t = charData[tutorial.profile.dataField]
	return type(t) == 'table' and t or nil
end

-- Every lesson the current track offers, game-wide lessons first: a fresh copy each call, so a
-- match can mark its lessons up freely. charData is a t_selChars entry (or anything
-- start.f_getCharData returns); the Game Tutorial's list is the same whoever P1 is.
function tutorial.f_lessonsFor(charData)
	local t = {}
	for _, l in ipairs(tutorial.systemLessons) do
		if f_systemOnTrack(l, charData) and tutorial.f_lessonOffered(l) then
			t[#t + 1] = main.f_tableCopy(l)
		end
	end
	for _, l in ipairs(f_charLessons(charData) or {}) do
		if tutorial.f_lessonOffered(l) then
			t[#t + 1] = main.f_tableCopy(l)
		end
	end
	return t
end

-- Cheaper than building the list: whether the current track has anything for a character at all.
function tutorial.f_hasLessons(charData)
	for _, l in ipairs(f_charLessons(charData) or {}) do
		if tutorial.f_lessonOffered(l) then
			return true
		end
	end
	for _, l in ipairs(tutorial.systemLessons) do
		if f_systemOnTrack(l, charData) and tutorial.f_lessonOffered(l) then
			return true
		end
	end
	return false
end

-- The P1 a Game Tutorial lesson is played with: its own lesson.playerchar, else TutorialPlayerChar,
-- else whoever was picked on the select screen.
function tutorial.f_playerFor(lesson)
	if type(lesson) == 'table' and lesson.playerref ~= nil then
		return lesson.playerref
	end
	return tutorial.playerRef or tutorial.pickedRef
end

-- A Game Tutorial speedrun is one match, so it is only offered while every lesson shares a P1.
function tutorial.f_speedrunSpansChars()
	if tutorial.track ~= 'game' then
		return false
	end
	local first = nil
	for i, l in ipairs(tutorial.f_lessonsFor(nil)) do
		local p = tutorial.f_playerFor(l)
		if i == 1 then
			first = p
		elseif p ~= first then
			return true
		end
	end
	return false
end

--;===========================================================
--; global.lua
--;===========================================================
-- Each enabled profile's game mode runs the same per-frame loop.
for _, id in ipairs(tutorial.t_profileOrder) do
	local p = tutorial.t_profiles[id]
	if p.enabled then
		hook.add("loop#" .. p.gamemode, "f_tutorialMode", tutorial.f_tutorialMode)
	end
end
-- Each enabled track gets its main menu entry. A disabled one is hidden from every menu the way the
-- engine hides a locked mode (main.f_hiddenItems): an unlock condition that is never true. Merely
-- leaving its handler out would not do - the item would still be listed, and picking it would send
-- the menu looking for a submenu of that name.
for _, t in pairs(tutorial.t_tracks) do
	for _, name in ipairs({t.itemname, t.legacy}) do
		if t.enabled then
			main.t_itemname[name] = t.start
		else
			main.t_unlockLua.modes[name] = 'false'
		end
	end
end
-- Whichever profile the module was left on while loading, the first menu entry puts its own in force.
-- Until then, Trials is the default, which is what a screenpack's own [Trials Pause Menu] labels expect.
if tutorial.t_profiles.trials.enabled then
	tutorial.f_useProfile(tutorial.t_profiles.trials)
elseif tutorial.t_profiles.tutorial.enabled then
	tutorial.f_useProfile(tutorial.t_profiles.tutorial)
end
hook.add("start.f_selectScreen", "f_tutorialSelectScreen", tutorial.f_tutorialSelectScreen)
-- Fires once selection is settled and before the fight loads, which is where
-- tutoriallistdisplay = select puts the menu.
hook.add("start.f_selectReset", "f_tutorialSpeedrunReset", function()
	tutorial.f_cancelRecording()
	tutorial.f_endDemo(false)
	tutorial.f_resetSpeedrun()
	tutorial.f_restoreSelect()
end)
-- TrialsStage / TutorialStage. The engine only puts Config.TrainingStage up in training mode, so the module hands its own
-- stage over as an assigned one - which also wins over a character's stage parameter, as the
-- training stage does. A stage that cannot be loaded falls back to the engine's own choice.
local f_setStageOrig = start.f_setStage
function start.f_setStage(num, assigned)
	if tutorial.f_inMode() and tutorial.stagePath ~= '' and not main.stageMenu then
		local ref = main.t_stageDef[tutorial.stagePath:lower()]
		if ref == nil then
			ref = main.f_addStage(tutorial.stagePath)
		end
		if ref ~= nil then
			return f_setStageOrig(ref, true)
		end
		print('Dojo: ' .. tutorial.profile.stageKey .. ' (' .. tutorial.stagePath .. ') could not be loaded; using the default stage instead.')
		tutorial.stagePath = ''
		tutorial.profile.stagePath = ''
	end
	return f_setStageOrig(num, assigned)
end

hook.add("launchFight", "f_tutorialPreFightMenu", function()
	tutorial.f_preFightMenu()
end)
-- launchFight has no way for a hook to call the fight off, but it gives up on the match whenever
-- the VS screen reports a cancel. So a cancel out of the pre-fight list is passed off as one: the
-- match is dropped before anything loads, and f_selectMode resets selection and reopens the
-- select screen, the same as backing out of the VS screen; f_restoreSelect then puts the picks back
-- so the player lands one step back instead of on P1's pick.
local f_selectVersusOrig = start.f_selectVersus
function start.f_selectVersus(...)
	if tutorial.backToSelect then
		tutorial.backToSelect = false
		return false
	end
	return f_selectVersusOrig(...)
end

