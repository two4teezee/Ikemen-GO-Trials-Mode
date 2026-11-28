-- IKEMEN GO DOJO MODULE --------------------------------------------------
---------------------------------------------------------------------------
-- Module developed by two4teezee
--
-- The Ikemen GO Dojo Module is the evolution of the Ikemen GO Trials Mode,
-- enabling four game modes on a shared core:
--   - Trials - per-character combo trials
--   - System Tutorial - game-wide lessons
--   - Character Guides - per-character lessons
--   - Combined Tutorial - system lessons + character guides in one mode
--
-- It features full screenpack integration via config.ini, +system.def, and
-- dojo.def. Documentation on writing trials and lessons, and on configuring 
-- each mode, is in README.md. I also strongly recommend reading the Wiki
-- pages on the Ikemen GO Dojo Module GitHub repository, which are kept up to
-- date with the latest features. The Dojo is a massive module with many 
-- features, and they are all covered in the Wiki.
---------------------------------------------------------------------------

--;===========================================================
--; Read Configuration Files
--;===========================================================

local modulePath = "external/mods/dojo/"

-- Warn if the old trials/tutorial modules are still installed; they clash with the Dojo.
for _, old in ipairs({'external/mods/trials/trials.lua', 'external/mods/tutorial/tutorial.lua'}) do
	if main.f_fileExists(old) then
		print('Dojo: ' .. old .. ' is still installed; remove its folder, the Dojo replaces it.')
	end
end

local zss = gameOption("Common.States")
table.insert(zss, modulePath .. "dojo.zss")
modifyGameOption("Common.States", zss)

dojo = {}

dojo.configPath = modulePath .. 'config.ini'

local cfgok, cfg = pcall(loadIni, dojo.configPath, false)
if not cfgok then
	print('Dojo: cannot read ' .. dojo.configPath .. '. Player preferences will not persist.')
end
dojo.ini = cfgok and cfg or {}
if type(dojo.ini.Options) ~= 'table' then dojo.ini.Options = {} end
if type(dojo.ini.Config) ~= 'table' then dojo.ini.Config = {} end
if type(dojo.ini.Modes) ~= 'table' then dojo.ini.Modes = {} end

local function f_cfgPath(key)
	local v = dojo.ini.Config[key]
	if type(v) ~= 'string' then
		return ''
	end
	return (v:gsub('\\', '/'):match('^%s*(.-)%s*$'))
end

--;===========================================================
--; Profiles, tracks and mode switches
--;===========================================================
-- Profile: what sets a mode family apart (game mode, dojo.def sections, options, save file, char def key).
dojo.t_profiles = {
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
dojo.t_profileOrder = {'trials', 'tutorial'}

-- Tracks: what the mode serves; key is its [Modes] switch, legacy its old Tutorial Mode itemname.
dojo.t_tracks = {
	trials   = {profile = 'trials',   itemname = 'trials',           key = 'Trials'},
	game     = {profile = 'tutorial', itemname = 'systemtutorial',   key = 'SystemTutorial',   legacy = 'tutorialgame'},
	chars    = {profile = 'tutorial', itemname = 'characterguides',  key = 'CharacterGuides',  legacy = 'tutorialchars'},
	combined = {profile = 'tutorial', itemname = 'combinedtutorial', key = 'CombinedTutorial', legacy = 'tutorial'},
}

-- [Modes] switch: 0/false/no/off disables a track; anything else, or absent, enables it.
local function f_switchOn(v)
	if v == nil then
		return true
	end
	local s = tostring(v):lower():match('^%s*(.-)%s*$')
	return not (s == '0' or s == 'false' or s == 'no' or s == 'off')
end
-- [Gating]: on opens a source's files one entry at a time, each locked until the one before it is cleared.
if type(dojo.ini.Gating) ~= 'table' then dojo.ini.Gating = {} end
function dojo.f_gatingOn(key)
	return dojo.ini.Gating[key] ~= nil and f_switchOn(dojo.ini.Gating[key])
end
for _, t in pairs(dojo.t_tracks) do
	t.enabled = f_switchOn(dojo.ini.Modes[t.key])
	if t.enabled then
		dojo.t_profiles[t.profile].enabled = true
	end
end

for _, p in pairs(dojo.t_profiles) do
	if type(dojo.ini.Options[p.optsKey]) ~= 'table' then dojo.ini.Options[p.optsKey] = {} end
	p.opts = dojo.ini.Options[p.optsKey]
	-- [Config] dummy / stage / P1 overrides; blank means picked on the select screen.
	p.dummyPath = f_cfgPath(p.dummyKey)
	p.stagePath = f_cfgPath(p.stageKey)
	p.playerCharPath = p.playerKey ~= nil and f_cfgPath(p.playerKey) or ''
end
-- Accept the pre-rename keys TrialsChar / TutorialChar.
for _, r in ipairs({{'trials', 'TrialsChar'}, {'tutorial', 'TutorialChar'}}) do
	local p, old = dojo.t_profiles[r[1]], r[2]
	if p.dummyPath == '' and f_cfgPath(old) ~= '' then
		p.dummyPath = f_cfgPath(old)
		print('Dojo: [Config] ' .. old .. ' has been renamed ' .. p.dummyKey .. '; please update config.ini.')
	end
end

-- Profile in force; opts is a shared upvalue, so reassigning it swaps preferences for every function.
local opts = dojo.t_profiles.trials.opts
dojo.track = 'trials'
dojo.profile = dojo.t_profiles.trials
dojo.dummyPath = dojo.profile.dummyPath
dojo.stagePath = dojo.profile.stagePath
dojo.playerCharPath = dojo.profile.playerCharPath

-- True while the engine is running one of this module's modes (select screen, match, pause menu).
function dojo.f_inMode()
	for _, id in ipairs(dojo.t_profileOrder) do
		local p = dojo.t_profiles[id]
		if p.enabled and gameMode(p.gamemode) then
			return true
		end
	end
	return false
end

-- Persists one Player Preference the moment it changes.
function dojo.f_savePref(key, value)
	opts[key] = value
	local ok, err = pcall(saveIni, dojo.ini, dojo.configPath)
	if not ok then
		print('Dojo: could not write ' .. dojo.configPath .. ' (' .. tostring(err) .. ').')
	end
end

--;===========================================================
--; Progress
--;===========================================================
dojo.t_difficulty = {'beginner', 'intermediate', 'advanced', 'expert'}
dojo.t_menuCats = {'all', 'beginner', 'intermediate', 'advanced', 'expert', 'other'}

-- One save file per profile; system lessons count for every character, game holds the Game Tutorial speedrun.
local function f_emptyProgress(p)
	p = p or dojo.profile
	if p.system then
		return {version = 1, chars = {}, system = {}, game = {speedrun = {}}}
	end
	return {version = 1, chars = {}}
end

function dojo.f_loadProgress(p)
	p = p or dojo.profile
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
dojo.progressPath = dojo.profile.progressPath
dojo.progress = f_emptyProgress()

local function f_saveProgress()
	-- Write the file ourselves if jsonEncode returns a string instead of writing it.
	local ok, err = pcall(jsonEncode, dojo.progress, dojo.progressPath)
	if ok then
		return
	end
	local ok2, str = pcall(jsonEncode, dojo.progress)
	if ok2 and type(str) == 'string' then
		main.f_fileWrite(dojo.progressPath, str)
		return
	end
	print('Dojo: could not write ' .. dojo.progressPath .. ' (' .. tostring(err) .. ').')
end

function dojo.f_clearProgress()
	dojo.progress = f_emptyProgress()
	dojo.profile.progress = dojo.progress
	f_saveProgress()
	dojo.selectDirty = true
end

function dojo.f_clearCharProgress(ref)
	local key = dojo.f_charKey(ref)
	if key == nil then
		return false
	end
	dojo.progress.chars[key] = nil
	f_saveProgress()
	dojo.selectDirty = true
	return true
end

function dojo.f_warnKey(why)
	if not dojo.keyWarned then
		dojo.keyWarned = true
		print('Dojo: ' .. why .. '; progress will not be recorded.')
	end
end

function dojo.f_charKey(ref)
	-- Nothing is selected yet while the menus are still being built, so every hop is checked.
	if ref == nil then ref = dojo.p1selref end
	if ref == nil and type(start.p) == 'table' and type(start.p[1]) == 'table'
		and type(start.p[1].t_selected) == 'table' and start.p[1].t_selected[1] ~= nil then
		ref = start.p[1].t_selected[1].ref
	end
	if ref == nil then
		if not dojo.charKeyWarned then
			dojo.charKeyWarned = true
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
		-- Warn once, so a broken key doesn't silently drop every clear.
		if not dojo.charKeyWarned then
			dojo.charKeyWarned = true
			print('Dojo: could not resolve the def path for character ref ' .. tostring(ref)
				.. '; progress will not be recorded.')
		end
		return nil
	end
	return path:gsub('\\', '/'):lower()
end

local function f_charProgress(create, ref)
	local key = dojo.f_charKey(ref)
	if key == nil then
		return nil
	end
	local t = dojo.progress.chars[key]
	if t == nil then
		if not create then
			return nil
		end
		t = {}
		dojo.progress.chars[key] = t
	end
	local b = dojo.profile.bucket
	if type(t[b]) ~= 'table' then t[b] = {} end
	if type(t.speedrun) ~= 'table' then t.speedrun = {} end
	return t
end

local function f_systemProgress(create, file)
	local t = dojo.progress.system[file]
	if t == nil then
		if not create then
			return nil
		end
		t = {}
		dojo.progress.system[file] = t
	end
	local b = dojo.profile.bucket
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

function dojo.f_lessonKey(index, arr)
	-- Explicit steps, not and/or: a nil here silently drops the record, so keep each step visible.
	if arr == nil and dojo.data ~= nil then
		arr = dojo.data.lessons
	end
	if type(arr) ~= 'table' or type(arr[index]) ~= 'table' then
		dojo.f_warnKey('no lesson at index ' .. tostring(index))
		return nil
	end
	if type(arr[index].key) == 'string' and arr[index].key ~= '' then
		return arr[index].key
	end
	local name = arr[index].name
	if type(name) ~= 'string' or name == '' then
		dojo.f_warnKey('lesson ' .. tostring(index) .. ' has no name')
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

function dojo.f_lessonRecord(index, arr, ref)
	if arr == nil and dojo.data ~= nil then
		arr = dojo.data.lessons
	end
	local key = dojo.f_lessonKey(index, arr)
	if key == nil then
		return nil
	end
	local t = f_lessonBucket(arr[index], false, ref)
	if t == nil then
		return nil
	end
	return t[dojo.profile.bucket][key]
end

function dojo.f_speedrunRecord()
	if dojo.track == 'game' then
		return dojo.progress.game.speedrun
	end
	local t = f_charProgress(false)
	if t == nil then
		return nil
	end
	return t.speedrun
end

function dojo.f_recordClear(index, ticks)
	local key = dojo.f_lessonKey(index)
	if key == nil then
		return
	end
	local t = f_lessonBucket(dojo.data.lessons[index], true)
	if t == nil then
		return
	end
	local b = dojo.profile.bucket
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

function dojo.f_recordSpeedrun(ticks)
	local t = dojo.track == 'game' and dojo.progress.game or f_charProgress(true)
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

-- Reuse the engine's already-loaded screenpack sprites and sounds.
local sff = motif.Sff
local snd = motif.Snd

-- Dojo art shared by every mode (dojo.sff/.snd/.air), each falling back to the screenpack's; loaded once.
dojo.uiDef = 'dojo.def'
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
		{modulePath .. dojo.uiDef, dojoSff},
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
	-- Trims a string before or after a character, plus surrounding whitespace.
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

-- Old dojo.def spellings mapped onto the neutral names; existing neutral keys win, from must never equal to.
dojo.t_uiAliases = {
	{'tutoriallocalcoord', 'localcoord'},
	{'trialslocalcoord', 'localcoord'},
	{'tutoriallistdisplay', 'listdisplay'},
	{'trialslistdisplay', 'listdisplay'},
	{'lessontitle', 'title'},
	{'trialtitle', 'title'},
	{'lessonsteps', 'steps'},
	{'trialsteps', 'steps'},
	{'lessoncounter', 'counter'},
	{'trialcounter', 'counter'},
	{'totallessontimer', 'totaltimer'},
	{'totaltrialtimer', 'totaltimer'},
	{'currentlessontimer', 'currenttimer'},
	{'currenttrialtimer', 'currenttimer'},
	{'lessonreset', 'reset'},
	{'trialreset', 'reset'},
	{'tutorialmenu', 'menu'},
	{'trialsmenu', 'menu'},
	{'counter', 'notutorialdata', 'nodata'},
	{'counter', 'notrialsdata', 'nodata'},
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

-- Overlay one section on another: lists replace whole, blocks merge key by key.
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

-- Build a profile's UI root: [Dojo] base, profile section over it; [Options] own behaviour, the def only styles.
local function f_prepareUI(p)
	local path = modulePath .. dojo.uiDef
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
			f_overlayUI(root, f_aliasUI(ini[sec], dojo.t_uiAliases))
		elseif i == 1 then
			print('Dojo: ' .. path .. ' has no [' .. sec:gsub('_', ' ') .. '] section; the ' .. p.label .. ' UI falls back to defaults.')
		end
	end
	root = f_buildCompatConfig(root)
	local o = p.opts
	root.layout = tostring(o.Layout):lower() == 'horizontal' and 'horizontal' or 'vertical'
	root.resetonsuccess = o.ResetOnSuccess == true
	if type(root.textbox) ~= 'table' then root.textbox = {} end
	if o.Textboxes ~= nil then
		local visible = tostring(o.Textboxes):lower() ~= 'hide'
		root.textbox_visible = visible
		root.textbox.visible = visible
	end
	if type(root.localcoord) ~= 'table' then
		root.localcoord = {320, 240}
	end
	local lx = tonumber(root.localcoord[1]) or 320
	local ly = tonumber(root.localcoord[2]) or 240
	root.localcoord = {lx, ly}
	return root, lx, ly
end

-- Until a profile is built (f_buildProfile, at the end of this file) the canvas is a plain default.
dojo.ui = {}
dojo.mtlcx = 320
dojo.mtlcy = 240

--;===========================================================
--; Aspect ratio
--;===========================================================
-- Lay the canvas out at the live aspect: vislcx is the visible width in authored units; anchors place elements.
dojo.vislcx = dojo.mtlcx
dojo.anchordelta = 0

-- The live game aspect, or the authored one while the engine cannot answer yet.
local function f_screenAspect()
	if type(screenWidth) ~= 'function' or type(screenHeight) ~= 'function' then
		return dojo.mtlcx / dojo.mtlcy
	end
	local ok, w, h = pcall(function() return screenWidth(), screenHeight() end)
	if not ok or type(w) ~= 'number' or type(h) ~= 'number' or w <= 0 or h <= 0 then
		return dojo.mtlcx / dojo.mtlcy
	end
	return w / h
end

-- Visible canvas width for an aspect, clamped at 4:3 where the engine caps its scale.
local function f_vislcx(aspect)
	return math.max(dojo.mtlcy * 4 / 3, dojo.mtlcy * aspect)
end

-- Localcoord for every Dojo element; use this, not mtlcx/mtlcy, with *SetLocalcoord.
function dojo.f_localcoord()
	return dojo.vislcx, dojo.mtlcy
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
	-- Localcoord first, matching the engine's SetTextSprite order.
		textImgSetLocalcoord(t.ti, dojo.f_localcoord())
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
		textImgSetLocalcoord(self.ti, dojo.f_localcoord())
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
		textImgSetLocalcoord(self.ti, dojo.f_localcoord())
		textImgSetText(self.ti, self.text)
	end

	return self
end

-- Re-commit every field after an aspect change; :update skips unchanged fields.
function text:relayout(x, y)
	if x ~= nil then self.x = x end
	if y ~= nil then self.y = y end
	textImgSetLocalcoord(self.ti, dojo.f_localcoord())
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

-- Place an anim from its node and origin; localcoord first since pos and scale divide by it.
local function f_placeAnim(a, node, x, y)
	local offset = type(node.offset) == 'table' and node.offset or {0, 0}
	local scale = type(node.scale) == 'table' and node.scale or {1.0, 1.0}
	animSetLocalcoord(a, dojo.f_localcoord())
	animSetPos(a, offset[1] + (x or 0), offset[2] + (y or 0))
	animSetScale(a, scale[1], scale[2])
	animSetFacing(a, node.facing or 1)
	animSetWindow(a, 0, 0, dojo.vislcx, dojo.mtlcy)
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
		-- Only use private glyph anims once the motif's glyph sff is confirmed usable.
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
-- Resolve a config/lesson character into the roster (excluded from random); nil when blank or unloadable.
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
dojo.f_charRefFor = f_charRefFor

-- Resolve every forced Game Tutorial P1 and P2 (TutorialPlayerChar, each playerchar / dummychar) on entering the track.
local function f_resolvePlayerChars()
	dojo.playerRef = f_charRefFor(dojo.playerCharPath, 'TutorialPlayerChar')
	if dojo.playerRef == nil then
		dojo.playerCharPath = ''
		dojo.profile.playerCharPath = ''
	end
	for _, l in ipairs(dojo.systemLessons) do
		if l.playerchar ~= nil and l.playerref == nil and not l.playercharFailed then
			l.playerref = f_charRefFor(l.playerchar, 'playerchar of "' .. l.name .. '"')
			l.playercharFailed = l.playerref == nil
		end
		if l.dummychar ~= nil and l.dummyref == nil and not l.dummycharFailed then
			l.dummyref = f_charRefFor(l.dummychar, 'dummychar of "' .. l.name .. '"')
			l.dummycharFailed = l.dummyref == nil
		end
	end
end

-- Select screen title: track itemname, then legacy itemname, then profile, then label.
local function f_selectTitle(track)
	local t = motif.select_info.title.text or {}
	local tr = dojo.t_tracks[track]
	for _, k in ipairs({tr.itemname, tr.legacy or tr.itemname, dojo.profile.title}) do
		if type(t[k]) == 'string' and t[k] ~= '' then
			return t[k]
		end
	end
	return dojo.profile.label
end

-- Shared track setup: endless single-character match vs a dummy, with the track's profile in force.
local function f_setupMode(track)
	dojo.f_useProfile(dojo.t_profiles[dojo.t_tracks[track].profile])
	dojo.track = track
	--main.lifebar.p1score = true
	--main.lifebar.p2ailevel = true
	main.motif.dialogue = false
	main.roundTime = -1
	if dojo.stagePath == '' then
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
	setGameMode(dojo.profile.gamemode)
	setHomeTeam(1)
end

-- Select screen picks P1, and P2 unless the profile forces a dummy.
local function f_selectScreenTrack(track)
	f_setupMode(track)
	dojo.dummyRef = f_charRefFor(dojo.dummyPath, dojo.profile.dummyKey)
	if dojo.dummyRef ~= nil then
		main.forceChar[2] = {dojo.dummyRef}
	end
	main.selectMenu[2] = true
	hook.run("main.t_itemname")
	return start.f_selectMode
end

-- Main menu entries per track, registered at file end when enabled in [Modes].
dojo.t_tracks.trials.start = function()
	return f_selectScreenTrack('trials')
end

dojo.t_tracks.combined.start = function()
	return f_selectScreenTrack('combined')
end

dojo.t_tracks.chars.start = function()
	return f_selectScreenTrack('chars')
end

-- Game Tutorial: skip the select screen unless config leaves P1, dummy or stage blank; gametutorial.lua runs the matches.
dojo.t_tracks.game.start = function()
	f_setupMode('game')
	f_resolvePlayerChars()
	dojo.dummyRef = f_charRefFor(dojo.dummyPath, 'TutorialDummy')
	main.selectMenu[1] = dojo.playerRef == nil
	if main.selectMenu[1] then
		if dojo.dummyRef ~= nil then
			main.forceChar[2] = {dojo.dummyRef}
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
local ui = dojo.ui

-- Walk to a dojo.def node, creating any missing levels.
local function f_node(t, ...)
	local node = t
	for i = 1, select('#', ...) do
		local k = select(i, ...)
		if type(node[k]) ~= 'table' then node[k] = {} end
		node = node[k]
	end
	return node
end

-- Categories menu.item / .header can restyle: difficulty tiers, all, other, and declared chapter ids.
local t_menuStructural = {text = true, bg = true, active = true, selected = true, locked = true,
	overlay = true, value = true, spacing = true, offset = true}
local function f_menuCats(m)
	local t, seen = {}, {}
	for _, c in ipairs(dojo.t_menuCats) do t[#t + 1] = c; seen[c] = true end
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
-- UI build steps, run once per profile from f_buildProfile.

-- Fill menu defaults a def predating the lesson select menu lacks.
local function f_uiMenuDefaults()
	local m = f_node(ui, 'menu')
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
	-- Rows a gated file has not opened yet ([Gating] in config.ini) inherit the plain row unless restyled.
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
	-- Active row overlay: rect under the cursor row, window relative to the row; zero size draws nothing.
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
	if type(o.window) ~= 'table' then o.window = {0, 0, dojo.mtlcx, dojo.mtlcy} end
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
		f_palfxDefaults(f_node(ui, sub, layout, 'bg', 'palfx'))
		f_palfxDefaults(f_node(ui, sub, layout, 'glyphs', 'palfx'))
		local paths = {{'bg'}}
		if layout == 'horizontal' then paths = {{'bg'}, {'bg', 'tail'}, {'bg', 'head'}} end
		for _, path in ipairs(paths) do
			local n = f_node(ui, sub, layout, unpack(path))
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
	local g = f_node(ui, 'glyphs', layout)
	if type(g.offset) ~= 'table' then g.offset = {0, 0} end
	if type(g.scale) ~= 'table' then g.scale = {1, 1} end
	if type(g.spacing) ~= 'table' then g.spacing = {0, 0} end
	g.align = tonumber(g.align) or 1
	if layout == 'horizontal' then g.align = 1 end
end

-- Hand the normalized values to the flat compat aliases the select screen reads.
do
	local fx = f_palfxDefaults(f_node(ui, 'selscreenpalfx'))
	for _, k in ipairs({'add', 'mul', 'sinadd', 'invertall', 'color'}) do
		ui['selscreenpalfx.' .. k] = fx[k]
		ui['selscreenpalfx_' .. k] = fx[k]
	end
end
end

--;===========================================================
--; Anchors
--;===========================================================
-- Anchor: left keeps x, right keeps distance to the right edge, center keeps the fraction; inferred if unset.
local t_anchorFactor = {left = 0, center = 0.5, right = 1}

local function f_inferAnchor(x)
	if x <= dojo.mtlcx / 3 then
		return 'left'
	elseif x >= dojo.mtlcx * 2 / 3 then
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

-- Authored x values and how each moves, kept pristine so relayouts never drift; one list per profile.
local t_anchored = {}

-- An element origin: one x that moves as a unit with the node's anchor.
local function f_anchorPos(node, key)
	if type(node) ~= 'table' or type(node[key]) ~= 'table' or type(node[key][1]) ~= 'number' then
		return
	end
	local pos = node[key]
	t_anchored[#t_anchored + 1] = {t = pos, i = 1, orig = pos[1], anchor = f_anchorOf(node, pos[1])}
end

-- Anchor a canvas-space window edge-to-edge so it keeps its margins at any aspect.
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
	f_anchorPos(f_node(ui, 'counter'), 'pos')
	f_anchorPos(f_node(ui, 'totaltimer'), 'pos')
	f_anchorPos(f_node(ui, 'currenttimer'), 'pos')
	f_anchorPos(f_node(ui, 'reset', 'text'), 'pos')
	f_anchorPos(f_node(ui, 'success'), 'pos')
	f_anchorPos(f_node(ui, 'allclear'), 'pos')
	f_anchorPos(f_node(ui, 'textbox'), 'pos')
	f_anchorPos(f_node(ui, 'menu'), 'pos')
	for _, layout in ipairs({'vertical', 'horizontal'}) do
		f_anchorPos(f_node(ui, 'title', layout), 'pos')
		f_anchorPos(f_node(ui, 'steps', layout), 'pos')
		f_anchorSpan(f_node(ui, 'steps', layout, 'window'), 'withouttextbox')
		f_anchorSpan(f_node(ui, 'steps', layout, 'window'), 'withtextbox')
	end
	f_anchorSpan(f_node(ui, 'menu', 'overlay'), 'window')
end

-- Writes every anchored x for the current canvas width. Returns whether anything actually moved.
local function f_applyAnchors()
	local delta = dojo.anchordelta
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

-- f_buildProfile lays out for the current aspect; f_syncAspect relayouts when a stage changes it.

-- Elements cache their Anim on .AnimData; p is held by reference so relayouts move them.
local t_elems = {}
local function f_uiElems()
t_elems = {
	{n = f_node(ui, 'steps', 'vertical', 'bg'),   p = ui.steps.vertical.pos},
	{n = f_node(ui, 'steps', 'horizontal', 'bg'), p = ui.steps.horizontal.pos},
	{n = f_node(ui, 'success', 'bg'),                  p = ui.success.pos},
	{n = f_node(ui, 'success', 'front'),               p = ui.success.pos},
	{n = f_node(ui, 'allclear', 'bg'),                 p = ui.allclear.pos},
	{n = f_node(ui, 'allclear', 'front'),              p = ui.allclear.pos},
	{n = f_node(ui, 'textbox', 'bg'),                  p = ui.textbox.pos},
	{n = f_node(ui, 'textbox', 'front'),               p = ui.textbox.pos},
}
t_elems[#t_elems + 1] = {n = f_node(ui, 'menu', 'bg'),    p = ui.menu.pos}
t_elems[#t_elems + 1] = {n = f_node(ui, 'menu', 'front'), p = ui.menu.pos}
for _, path in ipairs({
	{'cursor'}, {'header', 'bg'}, {'item', 'bg'}, {'item', 'active', 'bg'},
	{'status', 'cleared'}, {'status', 'uncleared'}, {'status', 'locked'}, {'arrow', 'up'}, {'arrow', 'down'},
}) do
	t_elems[#t_elems + 1] = {n = f_node(ui, 'menu', unpack(path))}
end
for _, cat in ipairs(f_menuCats(ui.menu)) do
	for _, path in ipairs({{'item', 'bg'}, {'item', 'active', 'bg'}, {'header', 'bg'}, {'header', 'active', 'bg'}}) do
		local n = ui.menu[path[1]][cat]
		for i = 2, #path, 1 do
			n = type(n) == 'table' and n[path[i]] or nil
		end
		if type(n) == 'table' then
			t_elems[#t_elems + 1] = {n = n}
		end
	end
end
for _, layout in ipairs({'vertical', 'horizontal'}) do
	t_elems[#t_elems + 1] = {n = f_node(ui, 'title', layout, 'bg'),    p = ui.title[layout].pos}
	t_elems[#t_elems + 1] = {n = f_node(ui, 'title', layout, 'front'), p = ui.title[layout].pos}
end
for _, sub in ipairs({'upcomingstep', 'currentstep', 'completedstep'}) do
	t_elems[#t_elems + 1] = {n = f_node(ui, sub, 'vertical', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(ui, sub, 'horizontal', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(ui, sub, 'horizontal', 'bg', 'tail')}
	t_elems[#t_elems + 1] = {n = f_node(ui, sub, 'horizontal', 'bg', 'head')}
end
for _, v in ipairs(t_elems) do
	v.n.AnimData = f_loadAnimData(v.n, v.p ~= nil and v.p[1] or nil, v.p ~= nil and v.p[2] or nil)
	main.f_loadingRefresh()
end
end

-- Lesson menu text objects, one per visible row per style, built once at load.
local function f_uiMenuDraw()
	local m = ui.menu
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
	dojo.menuDraw = d
end

-- Re-derive glyph positions from their original terms after an anchor move.
function dojo.f_relayoutGlyphs()
	if dojo.data == nil or type(dojo.data.lessons) ~= 'table' then
		return
	end
	for _, layout in ipairs({'vertical', 'horizontal'}) do
		local ox = ui.steps[layout].pos[1] + ui.glyphs[layout].offset[1]
		local oy = ui.steps[layout].pos[2] + ui.glyphs[layout].offset[2]
		for _, lesson in ipairs(dojo.data.lessons) do
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

-- Relayout for the current aspect; cheap no-op when unchanged, called where drawing happens.
function dojo.f_syncAspect()
	local vislcx = f_vislcx(f_screenAspect())
	if vislcx == dojo.vislcx then
		return false
	end
	dojo.vislcx = vislcx
	dojo.anchordelta = vislcx - dojo.mtlcx
	f_applyAnchors()
	-- Re-place every anim; animReset would otherwise restore the old localcoord and origin.
	for _, v in ipairs(t_elems) do
		if v.n.AnimData ~= nil then
			f_placeAnim(v.n.AnimData, v.n, v.p ~= nil and v.p[1] or nil, v.p ~= nil and v.p[2] or nil)
		end
	end
	-- Relayout text sprites built once with a baked position.
	local d = dojo.menuDraw
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
	if dojo.nodatacounter ~= nil then
		dojo.nodatacounter:relayout(ui.counter.pos[1], ui.counter.pos[2])
	end
	local dr = dojo.draw
	if dr ~= nil then
		dr.counter:relayout(ui.counter.pos[1], ui.counter.pos[2])
		dr.totaltimer:relayout(ui.totaltimer.pos[1], ui.totaltimer.pos[2])
		dr.currenttimer:relayout(ui.currenttimer.pos[1], ui.currenttimer.pos[2])
		dr.reset_text:relayout(ui.reset.text.pos[1], ui.reset.text.pos[2])
		dr.textbox_text:relayout()
		dr.textbox_title:relayout()
		dr.success_text:relayout()
		dr.allclear_text:relayout()
		for _, layout in ipairs({'vertical', 'horizontal'}) do
			local dl = dr[layout]
			if type(dl) == 'table' then
				local w = ui.steps[layout].window
				dl.windowXrange = w.withouttextbox[3] - w.withouttextbox[1]
				dl.windowXrangeWtext = w.withtextbox[3] - w.withtextbox[1]
				dl.title_text:relayout(
					ui.title[layout].pos[1] + ui.title[layout].text.offset[1],
					ui.title[layout].pos[2] + ui.title[layout].text.offset[2]
				)
				for _, key in ipairs({'upcomingtextline', 'currenttextline', 'completedtextline'}) do
					for _, obj in ipairs(dl[key] or {}) do
						obj:relayout()
					end
				end
			end
		end
	end
	-- Glyph runs are laid out from steps.pos, which has just moved under them.
	dojo.f_relayoutGlyphs()
	return true
end

--;===========================================================
--; start.lua
--;===========================================================
dojo.selectScreenPalMod = 'normal'

-- Current lesson / step / microstep, refreshed by f_drawer; lessonsExist is latched at round start.
local ct, cts, ctms
local lessonsExist = false

function dojo.f_initData()
	dojo.data = {
		lessonsExist = true,
		initialized = false,
		wasPaused = false,
		autoadvance = true,
		removalIndex = {},
		active = false,
		allclear = false,
		currentlesson = 1,
		successlesson = nil,
		currentlessonstep = 1,
		currentlessonmicrostep = 1,
		validfortickcount = 0,
		comboCounter = 0,
		-- No-hit steps key off state entries: stateinstance counts them, nohitinstance stops reuse.
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
		lessons = dojo.f_lessonsFor(start.f_getCharData(start.p[1].t_selected[1].ref)),
		bgelemdata = {
			vertical = {},
			horizontal = {},
		},
		draw = {},
		displaytimers = {
			totaltimer = opts.TotalTimer ~= false,
			lessontimer = opts[dojo.profile.timerKey] ~= false,
		},
	}

	-- Initialize autoadvance from the player's saved preference
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		dojo.data.autoadvance = true
	else
		dojo.data.autoadvance = false
	end
end

function dojo.f_buildMatch()
	local valvarcheck, sumcheck, tempglyphs
	-- Builds the lesson tables once from the UI and parsed lessons, starting with background elements.
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep','upcomingstep','completedstep'}) do
			local bg = dojo.ui[k][v].bg
			dojo.data.bgelemdata[v][k .. '_bgsize'] = animGetSpriteInfo(bg.AnimData)
			if v == 'horizontal' then
				dojo.data.bgelemdata[v][k .. '_bgtailwidth'] = animGetSpriteInfo(bg.tail.AnimData)
				dojo.data.bgelemdata[v][k .. '_bgheadwidth'] = animGetSpriteInfo(bg.head.AnimData)
			end
		end
	end
	
	-- thin out the lessons according to showforvarvalpairs
	for i = 1, #dojo.data.lessons, 1 do
		if dojo.data.lessons[i].showforvar[1] ~= nil then
			valvarcheck = true
			sumcheck = 0
			-- check every var
			for ii = 1, #dojo.data.lessons[i].showforvar, 1 do
				player(1)
				-- iterate over vals
				for iii = 1, #dojo.data.lessons[i].showforval[ii], 1 do
					if var(dojo.data.lessons[i].showforvar[ii]) == dojo.data.lessons[i].showforval[ii][iii] then
						sumcheck = sumcheck + 1
					end
				end
			end
			-- for every var, there should have been one hit; if not, set valvarcheck to false
			if sumcheck ~= #dojo.data.lessons[i].showforvar then
				valvarcheck = false
			end
			-- remove lessons that failed valvarcheck
			if not valvarcheck then
				dojo.data.removalIndex[#dojo.data.removalIndex+1] = i
			end
		end
	end
	for i = #dojo.data.removalIndex, 1, -1 do
		table.remove(dojo.data.lessons,dojo.data.removalIndex[i])
	end

	--Obtain all of the lesson information, to include the offset positions based on whether the display layout is horizontal or vertical
	for i = 1, #dojo.data.lessons, 1 do
		if #dojo.data.lessons[i].steps > dojo.data.maxsteps then
			dojo.data.maxsteps = #dojo.data.lessons[i].steps
		end
		for j = 1, #dojo.data.lessons[i].steps, 1 do
			local movelistline = dojo.data.lessons[i].steps[j].glyphs
			for kk, v in main.f_sortKeys(motif.glyphs, function(t, a, b) return string.len(a) > string.len(b) end) do
				local s = movelistline
				
				-- Replace glyph tokens with <token> for later lookup in motif.glyphs.
						
				movelistline = s:gsub('()' .. main.f_escapePattern(kk), function(pos)
								-- Inside a tag already; leave it to avoid nested replacements.
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
					if dojo.ui.glyphs[layout].align == -1 then
						for m = #tempglyphs, 1, -1 do
							-- Index off the slot the glyph landed in, not the new length.
							local n = #dojo.data.lessons[i].steps[j].glyphline[layout].glyph + 1
							dojo.data.lessons[i].steps[j].glyphline[layout].glyph[n] = tempglyphs[m]
							dojo.data.lessons[i].steps[j].glyphline[layout].pos[n] = {0,0}
							dojo.data.lessons[i].steps[j].glyphline[layout].width[n] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].alignOffset[n] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].lengthOffset[n] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].scale[n] = {1,1}
						end
					else
						for m = 1, #tempglyphs do
							dojo.data.lessons[i].steps[j].glyphline[layout].glyph[m] = tempglyphs[m]
							dojo.data.lessons[i].steps[j].glyphline[layout].pos[m] = {0,0}
							dojo.data.lessons[i].steps[j].glyphline[layout].width[m] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].alignOffset[m] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].lengthOffset[m] = 0
							dojo.data.lessons[i].steps[j].glyphline[layout].scale[m] = {1,1}
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
				if layout == "vertical" and dojo.ui.glyphs.vertical.scalewithtext == "true" then
					font_def = f_fontDef(dojo.ui.currentstep.vertical.text.font[1])
				end
				local glyphalign = dojo.ui.glyphs[layout].align
				for m = 1, #dojo.data.lessons[i].steps[j].glyphline[layout].glyph, 1 do
					if motif.glyphs[dojo.data.lessons[i].steps[j].glyphline[layout].glyph[m]] ~= nil then
						if glyphalign == 0 then --center align
							alignOffset = dojo.ui.glyphs[layout].offset[1] * 0.5
						elseif glyphalign == -1 then --right align
							alignOffset = dojo.ui.glyphs[layout].offset[1]
						end
						if glyphalign ~= align then
							lengthOffset = 0
							align = glyphalign
						end
						local scaleX = dojo.ui.glyphs[layout].scale[1]
						local scaleY = dojo.ui.glyphs[layout].scale[2]
						if glyphalign == -1 then
							alignOffset = alignOffset - motif.glyphs[dojo.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[1] * scaleX
						end
						dojo.data.lessons[i].steps[j].glyphline[layout].alignOffset[m] = alignOffset
						if font_def ~= nil then
							scaleY = font_def.Size[2] * dojo.ui.currentstep.vertical.text.scale[2] / motif.glyphs[dojo.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[2]
							scaleX = scaleY
						end
						dojo.data.lessons[i].steps[j].glyphline[layout].scale[m] = {scaleX, scaleY}
						dojo.data.lessons[i].steps[j].glyphline[layout].width[m] = math.floor(motif.glyphs[dojo.data.lessons[i].steps[j].glyphline[layout].glyph[m]].Size[1] * scaleX + dojo.ui.glyphs[layout].spacing[1])
						if glyphalign == 1 then
							lengthOffset = lengthOffset + dojo.data.lessons[i].steps[j].glyphline[layout].width[m]
						elseif glyphalign == -1 then
							lengthOffset = lengthOffset - dojo.data.lessons[i].steps[j].glyphline[layout].width[m]
						else
							lengthOffset = lengthOffset + dojo.data.lessons[i].steps[j].glyphline[layout].width[m] / 2
						end
						dojo.data.lessons[i].steps[j].glyphline[layout].lengthOffset[m] = lengthOffset
						dojo.data.lessons[i].steps[j].glyphline[layout].pos[m] = {
							math.floor(dojo.ui.steps[layout].pos[1] + dojo.ui.glyphs[layout].offset[1] + alignOffset + lengthOffset),
							dojo.ui.steps[layout].pos[2] + dojo.ui.glyphs[layout].offset[2]
						}
					end
				end
			end
		end
		if #dojo.data.lessons[i].steps > dojo.data.maxsteps then
			dojo.data.maxsteps = #dojo.data.lessons[i].steps
		end
	end
	--Pre-populate the draw table
	dojo.draw = {
		vertical = {},
		horizontal = {},
		success = 0,
		fade = 0,
		fadein = 0,
		fadeout = 0,
		fadetriggered = false,
		textbox_text = f_newText(dojo.ui.textbox.text),
		textbox_title = f_newText(dojo.ui.textbox.title),
		success_text = f_newText(dojo.ui.success.text),
		allclear = math.max(animGetLength(dojo.ui.allclear.front.AnimData), animGetLength(dojo.ui.allclear.bg.AnimData), dojo.ui.allclear.text.displaytime),
		allclear_text = f_newText(dojo.ui.allclear.text),
		counter = f_newText(dojo.ui.counter),
		totaltimer = f_newText(dojo.ui.totaltimer),
		currenttimer = f_newText(dojo.ui.currenttimer),
		reset_text = f_newText(dojo.ui.reset.text),
	}
	for _, v in ipairs({'vertical','horizontal'}) do
		dojo.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			title = math.max(animGetLength(dojo.ui.title[v].front.AnimData), animGetLength(dojo.ui.title[v].bg.AnimData)),
			--title = 100,
			title_text = f_newText(dojo.ui.title[v].text),
			windowXrange = dojo.ui.steps[v].window.withouttextbox[3] - dojo.ui.steps[v].window.withouttextbox[1],
			windowYrange = dojo.ui.steps[v].window.withouttextbox[4] - dojo.ui.steps[v].window.withouttextbox[2],
			windowXrangeWtext = dojo.ui.steps[v].window.withtextbox[3] - dojo.ui.steps[v].window.withtextbox[1],
			windowYrangeWtext = dojo.ui.steps[v].window.withtextbox[4] - dojo.ui.steps[v].window.withtextbox[2],
		}
		dojo.draw[v].title_text:update({x = dojo.ui.title[v].pos[1]+dojo.ui.title[v].text.offset[1], y = dojo.ui.title[v].pos[2]+dojo.ui.title[v].text.offset[2],})
		for i = 1, dojo.data.maxsteps, 1 do
			dojo.draw[v].upcomingtextline[i] = f_newText(dojo.ui.upcomingstep[v].text)
			dojo.draw[v].currenttextline[i] = f_newText(dojo.ui.currentstep[v].text)
			dojo.draw[v].completedtextline[i] = f_newText(dojo.ui.completedstep[v].text)
		end
	end

	-- Lesson select view; one item list backs the match-load screen and the pause menu's Lesson List.
	dojo.selectFilter = 'all'
	-- The engine builds one pause menu per [<Gamemode> Pause Menu] section, as menu.<gamemode>.
	dojo.rootNode = type(menu) == 'table' and menu[dojo.profile.gamemode] or nil
	local sub = nil
	local stack = {dojo.rootNode}
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
	dojo.listNode = sub
	if sub ~= nil then
		-- Remember what the section itself declared, so round start can put it all back.
		if dojo.listTail == nil then
			dojo.listTail = sub.items
		end
		if dojo.listLoop == nil then
			dojo.listLoop = sub.loop
		end
		sub.items = dojo.f_buildSelectItems()
		sub.item = dojo.f_firstUncleared(sub.items)
		sub.first = 1
		-- The Lesson List *is* the select view: hand the menu system our loop in place of its own.
		sub.loop = function()
			dojo.f_selectLoop(sub, false)
		end
	end
	if dojo.rootNode ~= nil and dojo.rootItems == nil then
		dojo.rootItems = dojo.rootNode.items
	end
	dojo.select = {
		items = sub ~= nil and sub.items or dojo.f_buildSelectItems(),
		item = 1,
		first = 1,
		open = false,
	}
	dojo.select.item = dojo.f_firstUncleared(dojo.select.items)

	dojo.data.initialized = true
end

function dojo.f_dummySetup()
	--If the tutorial initializer was successful and the round animation is completed, we will start drawing the lesson on the screen
	player(2)
	setAILevel(0)
	if dojo.data.currentlesson <= #dojo.data.lessons then
		if dojo.data.lessons[dojo.data.currentlesson].p2life > 0 then
			mapSet('_iksys_dojoSetLife', dojo.data.lessons[dojo.data.currentlesson].p2life)
			setLife(dojo.data.lessons[dojo.data.currentlesson].p2life)
		elseif map('_iksys_dojoSetLife') < lifeMax() then
			mapSet('_iksys_dojoSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_dojoSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(1)
	if dojo.data.currentlesson <= #dojo.data.lessons then
		if dojo.data.lessons[dojo.data.currentlesson].p1life > 0 then
			mapSet('_iksys_dojoSetLife', dojo.data.lessons[dojo.data.currentlesson].p1life)
			setLife(dojo.data.lessons[dojo.data.currentlesson].p1life)
		elseif map('_iksys_dojoSetLife') < lifeMax() then
			mapSet('_iksys_dojoSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_dojoSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(2)
	mapSet('_iksys_dojoDummyControl', 0)
	if not dojo.data.allclear and not dojo.data.lessons[dojo.data.currentlesson].active then
		if dojo.data.lessons[dojo.data.currentlesson].dummymode == 'stand' then
			mapSet('_iksys_dojoDummyMode', 0)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'crouch' then
			mapSet('_iksys_dojoDummyMode', 1)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'jump' then
			mapSet('_iksys_dojoDummyMode', 2)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'wjump' then
			mapSet('_iksys_dojoDummyMode', 3)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'fjump' then
			mapSet('_iksys_dojoDummyMode', 4)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'bjump' then
			mapSet('_iksys_dojoDummyMode', 5)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'fwjump' then
			mapSet('_iksys_dojoDummyMode', 6)
		elseif dojo.data.lessons[dojo.data.currentlesson].dummymode == 'bwjump' then
			mapSet('_iksys_dojoDummyMode', 7)
		end
		-- Guard modes: none, auto (or all), afterhit (briefly after being hit), random (about half the time).
		mapSet('_iksys_dojoGuardMode', dojo.t_guardMode[dojo.data.lessons[dojo.data.currentlesson].guardmode] or 0)
		if dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'none' then
			mapSet('_iksys_dojoButtonJam', 0)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'a' then
			mapSet('_iksys_dojoButtonJam', 1)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'b' then
			mapSet('_iksys_dojoButtonJam', 2)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'c' then
			mapSet('_iksys_dojoButtonJam', 3)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'x' then
			mapSet('_iksys_dojoButtonJam', 4)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'y' then
			mapSet('_iksys_dojoButtonJam', 5)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'z' then
			mapSet('_iksys_dojoButtonJam', 6)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'start' then
			mapSet('_iksys_dojoButtonJam', 7)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'd' then
			mapSet('_iksys_dojoButtonJam', 8)
		elseif dojo.data.lessons[dojo.data.currentlesson].buttonjam == 'w' then
			mapSet('_iksys_dojoButtonJam', 9)
		end
		-- Button jam delay, reset per lesson to its mode's default when unset.
		local jt = dojo.data.lessons[dojo.data.currentlesson]
		local jdefault = dojo.t_jumpModes[jt.dummymode] and dojo.buttonJamAirDelayDefault or dojo.buttonJamDelayDefault
		mapSet('_iksys_dojoButtonJamInterval', jt.buttondelay or jdefault)
		-- Every timer starts fresh, so the dummy's actions run the same from activation every time.
		mapSet('_iksys_dojoButtonJamDelay', jt.buttondelay or jdefault)
		mapSet('_iksys_dojoAirJamState', 0)
		-- Frames the dummy stays on the ground between jumps in the jump dummy modes, set the same way.
		mapSet('_iksys_dojoJumpInterval', dojo.data.lessons[dojo.data.currentlesson].jumpdelay or dojo.jumpDelayDefault)
		mapSet('_iksys_dojoJumpDelay', 0)
		-- Acting dummies walk back to their dummypos distance first; corners and stand/crouch are left alone.
		local t = dojo.data.lessons[dojo.data.currentlesson]
		local acts = dojo.t_jumpModes[t.dummymode] or (t.buttonjam ~= nil and t.buttonjam ~= 'none')
		mapSet('_iksys_dojoDistance', acts and (dojo.t_dummyDistance[t.dummypos] or 0) or 0)
		mapSet('_iksys_dojoDirection', 0)
		dojo.data.lessons[dojo.data.currentlesson].active = true
	end
	player(1)
end

-- lesson.dummypos values the dummy keeps its distance for, as _iksys_dojoDistance values.
dojo.t_dummyDistance = {close = 1, medium = 2, far = 3}
-- lesson.guardmode -> _iksys_dojoGuardMode (see the legend at the top of dojo.zss)
dojo.t_guardMode = {none = 0, afterhit = 1, auto = 2, all = 2, random = 3}
-- lesson.dummymode values that count as the dummy acting, for the distance keeping above.
dojo.t_jumpModes = {jump = true, wjump = true, fjump = true, bjump = true, fwjump = true, bwjump = true}

-- lesson.dummybuttondelay when a Lesson leaves it out: the gap the button jam has always used.
dojo.buttonJamDelayDefault = 11
-- The same in the jump modes, where it counts from takeoff: attack as soon as the dummy leaves the ground.
dojo.buttonJamAirDelayDefault = 0
-- lesson.dummyjumpdelay when a Lesson leaves it out: jump again as soon as the dummy lands.
dojo.jumpDelayDefault = 0

-- The textbox portrait's anim string, from textbox.portrait.spr; nil when the def names none.
local function f_textboxPortraitAnim()
	local spr = dojo.ui.textbox.portrait.spr
	if type(spr) ~= 'table' or spr[1] == nil then
		return nil
	end
	return tostring(spr[1]) .. ',' .. tostring(spr[2] or 0) .. ',0,0,-1'
end

function dojo.textboxportrait()
	-- Cached until roundStart clears it, because the selected character can change.
	if dojo.charPortraitSff == nil then
		local spr = loadText(getCharFileName(dojo.p1selref)):lower()
		spr = spr:gsub('([^\r\n;]*)%s*;[^\r\n]*', '%1')
		spr = spr:gsub('\n%s*\n', '\n')
		spr = spr:gsub('.*sprite.*=%s*(.*sff).*', '%1')
		dojo.charPortraitSff = sffNew(getCharFileName(dojo.p1selref):gsub('(.*)%/.*def.*', '%1/') .. spr)
	end
	local str = f_textboxPortraitAnim()
	if str ~= nil then
		dojo.ui.textbox.portrait.anim = animNew(dojo.charPortraitSff, str)
	end
end
	
function dojo.f_drawer()
	if dojo.data.initialized and roundState() == 2 and not dojo.data.active and dojo.draw.fade == 0
		and dojo.f_demoReady() then
		dojo.f_dummySetup()
		dojo.data.active = true
		-- Demonstrations-only: whether the pair have moved since the lesson was entered.
		dojo.data.demoOnlyPlayed = dojo.f_demoActive()
		-- Show a newly entered lesson's pages first, except in a speedrun.
		dojo.f_startDummyScript(dojo.data.currentlesson)
		-- A demo's script starts here, on the frame the dummy's script or actions do, so the two always line up.
		dojo.f_demoBegin()
		local lesson = dojo.data.lessons[dojo.data.currentlesson]
		if lesson ~= nil and not lesson.pagesSeen and not dojo.f_speedrunEnabled() and not dojo.f_demoActive() then
			dojo.f_openPages(dojo.data.currentlesson)
		end
	end

	if paused() and not dojo.data.wasPaused then
		dojo.data.wasPaused = true
	elseif not paused() then
		dojo.data.wasPaused = false
	end

	local accwidth = 0
	local addrow = 0
	local layout, spacing, sub, windowXrange, windowYrange, animposx, animposy
	local textboxwindow1, textboxwindow2, textboxwindow3, textboxwindow4, textboxtext_offset1, textboxtext_offset2
	-- Initialize abbreviated values for readability
	ct = dojo.data.currentlesson
	cts = dojo.data.currentlessonstep
	ctms = dojo.data.currentlessonmicrostep
	layout = dojo.ui.layout

	if dojo.data.active then
		if ct <= #dojo.data.lessons and dojo.draw.success == 0 then

			--According to motif instructions, draw the counter on screen
			local trtext = dojo.ui.counter.text
			trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%t', tostring(#dojo.data.lessons))
			dojo.draw.counter:update({text = trtext})
			dojo.draw.counter:draw()
			dojo.f_drawLessonExtras(ct)
			--Logic for the stopwatches: total time spent in lesson, and time spent on this current lesson
			if dojo.data.displaytimers.totaltimer then
				local totaltimertext = dojo.ui.totaltimer.text
				dojo.data.elapsedtime = roundTime() - dojo.data.starttick
				local m, s, x = f_timeConvert(dojo.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				dojo.draw.totaltimer:update({text = totaltimertext})
				dojo.draw.totaltimer:draw()
			else
				--dojo.draw.totaltimer:update({text = "Timer Disabled"})
				--dojo.draw.totaltimer:draw()
			end
			if dojo.data.displaytimers.lessontimer then
				local currenttimertext = dojo.ui.currenttimer.text
				dojo.data.lessons[ct].elapsedtime = roundTime() - dojo.data.lessons[ct].starttick
				local m, s, x = f_timeConvert(dojo.data.lessons[ct].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				dojo.draw.currenttimer:update({text = currenttimertext})
				dojo.draw.currenttimer:draw()
			else
				--dojo.draw.currenttimer:update({text = "Timer Disabled"})
				--dojo.draw.currenttimer:draw()
			end

			-- Draw lesson reset reminder if enabled
			if dojo.ui.reset.enabled then
				dojo.draw.reset_text:update({text = dojo.ui.reset.text.text})
				dojo.draw.reset_text:draw()
			end

			-- Draw lesson step background
			animUpdate(dojo.ui.steps[layout].bg.AnimData)
			animDraw(dojo.ui.steps[layout].bg.AnimData)

			-- Draw lesson title
			animUpdate(dojo.ui.title[layout].bg.AnimData)
			animDraw(dojo.ui.title[layout].bg.AnimData)
			dojo.draw[layout].title_text:update({text = dojo.data.lessons[ct].name})
			dojo.draw[layout].title_text:draw()
			animUpdate(dojo.ui.title[layout].front.AnimData)
			animDraw(dojo.ui.title[layout].front.AnimData)

			local startonstep = 1
			local drawtothisstep = #dojo.data.lessons[ct].steps

			-- Draw the textbox when shown and present, shrinking the step window to fit.
			if dojo.ui.textbox_visible == true and dojo.data.lessons[ct].textbox ~= '' then
				windowYrange = dojo.draw[layout].windowYrangeWtext
				windowXrange = dojo.draw[layout].windowXrangeWtext

						textboxwindow1 =    dojo.ui.textbox.pos[1]+dojo.ui.textbox.overlay.window[1]
						textboxwindow2 =    dojo.ui.textbox.pos[2]+dojo.ui.textbox.overlay.window[2]
						textboxwindow3 =    dojo.ui.textbox.pos[1]+dojo.ui.textbox.overlay.window[3]
						textboxwindow4 =    dojo.ui.textbox.pos[2]+dojo.ui.textbox.overlay.window[4]
		
	-- An unset overlay window means "the whole canvas", which is as wide as the screen is.
	if textboxwindow3 == 0 then
textboxwindow3 = dojo.vislcx
	end
	if textboxwindow4 == 0 then
textboxwindow4 = dojo.mtlcy
	end

		if dojo.ui.textbox.overlay.RectData == nil then
		dojo.ui.textbox.overlay.RectData = rectNew()
				end
		rectSetColor(dojo.ui.textbox.overlay.RectData, 
						dojo.ui.textbox.overlay.col[1],
						dojo.ui.textbox.overlay.col[2],
						dojo.ui.textbox.overlay.col[3])
		rectSetAlpha(dojo.ui.textbox.overlay.RectData, 
						dojo.ui.textbox.overlay.alpha[1],
						dojo.ui.textbox.overlay.alpha[2])
		rectSetLayerno(dojo.ui.textbox.overlay.RectData, 0)
		rectSetWindow(dojo.ui.textbox.overlay.RectData, 
						textboxwindow1,
						textboxwindow2,
						textboxwindow3,
						textboxwindow4)
		rectSetLocalcoord(dojo.ui.textbox.overlay.RectData, dojo.f_localcoord())
		rectDraw(dojo.ui.textbox.overlay.RectData)

				animSetLocalcoord(dojo.ui.textbox.bg.AnimData, dojo.f_localcoord())
				animUpdate(dojo.ui.textbox.bg.AnimData)
				animDraw(dojo.ui.textbox.bg.AnimData)

				-- Draw text
				local trtext = dojo.ui.textbox.title.text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', dojo.data.lessons[ct].name)
				dojo.draw.textbox_title:update({text = trtext})
				dojo.draw.textbox_title:draw()

				if not dojo.draw.draw_textbox_text then
					dojo.data.lessons[ct].textcnt = dojo.data.lessons[ct].textcnt + 1
				end
				
		if motif.Fnt[dojo.draw.textbox_text.font] ~= nil then
			textImgSetFont(dojo.draw.textbox_text.ti, motif.Fnt[dojo.draw.textbox_text.font])
		end

	textboxtext_offset1 = textboxwindow1 + dojo.ui.textbox_text_window[1] + dojo.ui.textbox_text_offset[1]
	textboxtext_offset2 = textboxwindow2 + dojo.ui.textbox_text_window[2] + dojo.ui.textbox_text_offset[2]

		textImgSetText(dojo.draw.textbox_text.ti,string.format(dojo.data.lessons[ct].textbox, main.f_countSubstring(dojo.data.lessons[ct].textbox, '_')))
		textImgSetPos(dojo.draw.textbox_text.ti, math.floor(textboxtext_offset1), math.floor(textboxtext_offset2))
		textImgSetScale(dojo.draw.textbox_text.ti, dojo.draw.textbox_text.scaleX, dojo.draw.textbox_text.scaleY)
		textImgSetLocalcoord(dojo.draw.textbox_text.ti, dojo.f_localcoord())
		textImgDraw(dojo.draw.textbox_text.ti)


				-- Portrait from its source, built once; round start clears it for the next character.
				local por = dojo.ui.textbox.portrait
				if por.anim == nil then
					if dojo.ui.textbox_portrait_source == "system" then
						local str = f_textboxPortraitAnim()
						if str ~= nil then
							por.anim = animNew(sff, str)
						end
					elseif dojo.ui.textbox_portrait_source == "char" then
						dojo.textboxportrait()
					end
				end

				if por.anim ~= nil then
					animposx = textboxwindow1 + dojo.ui.textbox_portrait_offset[1]
					animposy = textboxwindow2 + dojo.ui.textbox_portrait_offset[2]
					local w = dojo.ui.textbox_portrait_window
					local a = por.anim
					animSetLocalcoord(a, dojo.f_localcoord())
					animSetLayerno(a, 0)
					animSetPos(a, math.floor(animposx), math.floor(animposy))
					animSetScale(a, dojo.ui.textbox_portrait_scale[1], dojo.ui.textbox_portrait_scale[2])
					animSetFacing(a, dojo.ui.textbox_portrait_facing)
					animSetWindow(a, animposx + w[1], animposy + w[2], w[3] + dojo.vislcx, w[4] + dojo.mtlcy)
					animUpdate(a)
					animDraw(a)
				end

				-- Draw textbox front
				animUpdate(dojo.ui.textbox.front.AnimData)
				animDraw(dojo.ui.textbox.front.AnimData)
			else
				windowYrange = dojo.draw[layout].windowYrange
				windowXrange = dojo.draw[layout].windowXrange
			end

			-- Vertical layouts: decide scrolling up front; horizontal works it out while measuring glyphs.
			if #dojo.data.lessons[ct].steps*dojo.ui.steps[layout].spacing[2] > windowYrange and layout == "vertical" then
				startonstep = math.max(cts-2, 1)
				if (drawtothisstep - startonstep)*dojo.ui.steps[layout].spacing[2] > windowYrange then
					drawtothisstep = math.min(startonstep+math.floor(windowYrange/dojo.ui.steps[layout].spacing[2]),#dojo.data.lessons[ct].steps)
				end
			end

			--This is the draw loop
			for i = startonstep, drawtothisstep, 1 do
				local tempoffset = {dojo.ui.steps[layout].spacing[1]*(i-startonstep),dojo.ui.steps[layout].spacing[2]*(i-startonstep)}
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
					-- Vertical: fixed-width bg with text over it and glyphs where specified; no incrementors.
					local stepbg = dojo.ui[sub .. 'step'].vertical.bg
					-- animReset first: it restores pos/scale/window and clears palfx.
					animReset(stepbg.AnimData)
					animSetPos(
						stepbg.AnimData,
						dojo.ui.steps.vertical.pos[1] + stepbg.offset[1] + tempoffset[1],
						dojo.ui.steps.vertical.pos[2] + stepbg.offset[2] + tempoffset[2]
					)
					dojo.draw.vertical[sub .. 'textline'][i]:update({
						x = dojo.ui.steps.vertical.pos[1]+dojo.ui[sub .. 'step'].vertical.text.offset[1]+dojo.ui.steps.vertical.spacing[1]*(i-startonstep),
						y = dojo.ui.steps.vertical.pos[2]+dojo.ui[sub .. 'step'].vertical.text.offset[2]+dojo.ui.steps.vertical.spacing[2]*(i-startonstep),
						text = dojo.data.lessons[ct].steps[i].text
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
					dojo.draw.vertical[sub .. 'textline'][i]:draw()
				elseif layout == "horizontal" then
					-- Horizontal: glyphs only, on a tiled body with optional head (incrementor), wrapping at the window width.
					local bgsize = {0,0}
					local hbg = dojo.ui[sub .. 'step'].horizontal.bg
					-- Budget head and tail at their drawn scale, not raw sprite size.
					if dojo.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'] ~= nil then bgtailwidth = math.floor(dojo.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'].Size[1] * hbg.tail.scale[1]) end
					if dojo.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'] ~= nil then bgheadwidth = math.floor(dojo.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'].Size[1] * hbg.head.scale[1]) end
					if dojo.data.bgelemdata.horizontal[sub .. 'step_bgsize'] ~= nil then bgsize = dojo.data.bgelemdata.horizontal[sub .. 'step_bgsize'].Size end

					totalglyphlength = dojo.data.lessons[ct].steps[i].glyphline.horizontal.lengthOffset[#dojo.data.lessons[ct].steps[i].glyphline.horizontal.lengthOffset]
					padding = dojo.ui.steps_horizontal_padding
					spacing = dojo.ui.steps_horizontal_spacing[1]

					local tempwidth = spacing + bgtailwidth + padding + totalglyphlength + padding + bgheadwidth + accwidth
					-- Only wrap when the row already has something on it.
					if accwidth > 0 and tempwidth - dojo.ui.steps_horizontal_spacing[1] > windowXrange then
						accwidth = 0
						addrow = addrow + 1
					end

					tempoffset[2] = dojo.ui.steps_horizontal_spacing[2]*(addrow)
					-- Rows start at steps.pos; glyphs.offset is applied once, where glyphs draw.
					local rowy = dojo.ui.steps_horizontal_pos[2] + tempoffset[2]

					-- Calculate initial positions
					if accwidth == 0 then
						bgcomponentposX = dojo.ui.steps_horizontal_pos[1]
					else
						bgcomponentposX = accwidth + spacing -- + bgheadwidth 
					end

					-- Tail: head and tail draw at their declared scale; only the body stretches, on x.
					local hpalfx = {
						time = 1,
						add = hbg.palfx.add,
						mul = hbg.palfx.mul,
						sinadd = hbg.palfx.sinadd,
						invertall = hbg.palfx.invertall,
						color = hbg.palfx.color
					}
					local glyphrow = dojo.data.lessons[ct].steps[i].glyphline.horizontal
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

					-- Body: stretch x to the glyph run, keep the declared y scale.
					local bgstretch = hbg.scale[1]
					if bgsize[1] > 0 then bgstretch = (padding + totalglyphlength + padding)/bgsize[1] end
					bgtargetscale = {bgstretch, hbg.scale[2]}
					bgcomponentposX = (bgcomponentposX + bgtailwidth)
					-- Glyphs run left to right from the body's left padding.
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
				local glyphline = dojo.data.lessons[ct].steps[i].glyphline[layout]
				local glyphpalfx = dojo.ui[sub .. 'step'][layout].glyphs.palfx
				for m = 1, #glyphline.glyph, 1 do
					-- One anim per glyph per step category so palfx doesn't bleed; moved into Dojo space before placing.
					local g = f_glyphAnim(sub, glyphline.glyph[m])
					-- The movelist can carry tags that are not glyphs; those never got a position.
					if g ~= nil and glyphline.pos[m] ~= nil then
						animReset(g)
						animSetLocalcoord(g, dojo.f_localcoord())
						animSetLayerno(g, f_clampLayerno(dojo.ui.glyphs[layout].layerno))
						animSetScale(g, glyphline.scale[m][1], glyphline.scale[m][2])
						-- pos already includes glyphs.offset; add only the row offset.
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
		elseif ct > #dojo.data.lessons then
			-- All lessons have been completed, draw the all clear and freeze the timer
			if not dojo.data.allclear and dojo.f_speedrunEnabled() and dojo.data.runValid then
				dojo.f_recordSpeedrun(roundTime() - dojo.data.starttick)
				dojo.data.runValid = false
			end
			if dojo.draw.allclear ~= 0 then
				dojo.f_drawSuccess('allclear', ct-1)
			end

			dojo.data.allclear = true
			dojo.draw.success = 0
			dojo.draw.counter:update({text = dojo.ui.counter.allclear.text})
			dojo.draw.counter:draw()

			if dojo.data.displaytimers.totaltimer then
				local totaltimertext = dojo.ui.totaltimer.text
				local m, s, x = f_timeConvert(dojo.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				dojo.draw.totaltimer:update({text = totaltimertext})
				dojo.draw.totaltimer:draw()
			else
				--tutorial.draw.totaltimer:update({text = "Timer Disabled"})
				--tutorial.draw.totaltimer:draw()
			end
			if dojo.data.displaytimers.lessontimer then
				local currenttimertext = dojo.ui.currenttimer.text
				local m, s, x = f_timeConvert(dojo.data.lessons[ct-1].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				dojo.draw.currenttimer:update({text = currenttimertext})
				dojo.draw.currenttimer:draw()
			else
				--tutorial.draw.currenttimer:update({text = "Timer Disabled"})
				--tutorial.draw.currenttimer:draw()
			end
		end
	end
end


-- Spend the current state so a fresh attempt's first no-hit step needs a new entry.
function dojo.f_spendState()
	if dojo.data ~= nil then
		dojo.data.nohitinstance = dojo.data.stateinstance
	end
end

function dojo.f_checker(CheckIt)
	local nctms
	-- Sets dummy actions and validates attempts; the root counts state entries every frame (time falls on re-entry).
	if CheckIt == 'root' then
		local sn, st = stateNo(), time()
		local newinstance = sn ~= dojo.data.laststateno or (dojo.data.laststatetime ~= nil and st < dojo.data.laststatetime)
		if newinstance then
			dojo.data.stateinstance = dojo.data.stateinstance + 1
		end
		dojo.data.laststateno = sn
		dojo.data.laststatetime = st
		dojo.f_trackEvents(newinstance)
	end
	if ct <= #dojo.data.lessons and dojo.draw.success == 0 and dojo.draw.fade == 0 and dojo.data.active then
	
			if dojo.data.lessons[ct].steps[cts].hitcount[ctms] == nil then
			dojo.data.lessons[ct].steps[cts].hitcount[ctms] = -1
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
				-- Redirect to the owner first so numProjId asks the right character.
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
		local step = dojo.data.lessons[ct].steps[cts]
		local newhit = comboCount() > dojo.data.comboCounter
		-- One state entry satisfies one no-hit step, not one per frame.
		local newstate = dojo.data.stateinstance ~= dojo.data.nohitinstance
		local nohitok = step.hitcount[ctms] == 0 and newstate
		local isprojstep = step.isproj[ctms] or step.projid[ctms] ~= nil
		if CheckIt ~= nil and CheckIt ~= 'root' then
			helperIndex(CheckIt)
		end

		for i = 0, numProj() - 1 do
			local ptime, pid = projVar(-1, i, 'time'), projVar(-1, i, 'projid')
			if ptime ~= nil and pid ~= nil and ptime <= 1 then
				dojo.data.projsource[pid] = stateNo()
			end
		end

		-- Check states and anims; iterate over 'or' operand if multiple states and/or anims are provided
		local launchstate = projid >= 0 and dojo.data.projsource[projid] or nil
		local desiredstates = dojo.data.lessons[ct].steps[cts].stateno[ctms]
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
		if dojo.data.lessons[ct].steps[cts].animno[ctms] ~= nil then
			animcheck = false
			local desiredanims = dojo.data.lessons[ct].steps[cts].animno[ctms]
			for k = 1, #desiredanims, 1 do
				if anim() == desiredanims[k] or attackeranim == desiredanims[k] then
					animcheck = true
					break
				end
			end
		end

		-- The window counts down for every kind of step; running out with this step still to come is noted.
		if dojo.data.validfortickcount > 0 and paused() == false and pauseTime() == 0 and CheckIt == 'root' then
			dojo.data.validfortickcount = dojo.data.validfortickcount - 1
			if dojo.data.validfortickcount == 0 then
				dojo.data.windowExpired = true
			end
		end

		if dojo.f_isEventStep(step, ctms) then
			-- Event steps are judged on events, so the combo-drop resets below don't apply.
			if CheckIt == 'root' then
				dojo.f_checkEventStep(ct, cts, ctms, statecheck, animcheck)
			end
		else
		if (step.ishelper[ctms] and statecheck) and animcheck then
			-- Helper projectiles score on the root, so match them by projid.
			helpercheck = ((moveHit() > 0 or projid >= 0) and newhit)
				or step.isthrow[ctms] or nohitok
			if dojo.data.lessons[ct].steps[cts].validforvar ~= nil and helpercheck then
				for i = 1, #dojo.data.lessons[ct].steps[cts].validforvar, 1 do
					if helpercheck then
						helpercheck = var(dojo.data.lessons[ct].steps[cts].validforvar[i]) == dojo.data.lessons[ct].steps[cts].validforval[i]
					end
				end
			end
		end

		if isprojstep then
			local wantids = step.projid[ctms]
			if step.hitcount[ctms] == 0 then
				-- No-hit steps match on state alone; projid doesn't apply.
				projcheck = statecheck and animcheck and newstate
			elseif wantids == nil then
				-- Legacy step with no projid: match stateno as before, but require a real hit.
				projcheck = statecheck and animcheck and projid >= 0 and newhit
			elseif CheckIt == 'root' and projid >= 0 and newhit then
				-- Match ProjIDs once per frame in the root pass, or a step advances twice.
				for k = 1, #wantids, 1 do
					if projid == wantids[k] then
						-- statecheck separates moves sharing a ProjID; free when no stateno is set.
						projcheck = statecheck and animcheck
						break
					end
				end
			end
			if dojo.data.lessons[ct].steps[cts].validforvar ~= nil and projcheck then
				for i = 1, #dojo.data.lessons[ct].steps[cts].validforvar, 1 do
					if projcheck then
						projcheck = var(dojo.data.lessons[ct].steps[cts].validforvar[i]) == dojo.data.lessons[ct].steps[cts].validforval[i]
					end
				end
			end
		end

		maincharcheck = (statecheck and not(isprojstep) and not(step.ishelper[ctms]) and animcheck and ((moveHit() > 0 and newhit) or step.isthrow[ctms] or nohitok))
		if dojo.data.lessons[ct].steps[cts].validforvar ~= nil and maincharcheck then
			for i = 1, #dojo.data.lessons[ct].steps[cts].validforvar, 1 do
				if maincharcheck then
					maincharcheck = var(dojo.data.lessons[ct].steps[cts].validforvar[i]) == dojo.data.lessons[ct].steps[cts].validforval[i]
				end
			end
		end		

		if (maincharcheck or projcheck or helpercheck) and not dojo.f_p2StateOk(step, ctms) then
			maincharcheck, projcheck, helpercheck = false, false, false
		end

		if maincharcheck or projcheck or helpercheck then
			if dojo.data.lessons[ct].steps[cts].hitcount[ctms] >= 1 then
				if dojo.data.lessons[ct].steps[cts].stephitscount[ctms] == 0 then
					dojo.data.lessons[ct].steps[cts].comboCountonstep[ctms] = comboCount()
				end
				if comboCount() - dojo.data.lessons[ct].steps[cts].stephitscount[ctms] == dojo.data.lessons[ct].steps[cts].comboCountonstep[ctms] then
					dojo.data.lessons[ct].steps[cts].stephitscount[ctms] = dojo.data.lessons[ct].steps[cts].stephitscount[ctms] + 1
				end
			elseif dojo.data.lessons[ct].steps[cts].hitcount[ctms] == 0 then
				dojo.data.lessons[ct].steps[cts].stephitscount[ctms] = 0
				-- Spend the entry that satisfied this no-hit step.
				dojo.data.nohitinstance = dojo.data.stateinstance
			end

			if dojo.data.lessons[ct].steps[cts].hitcount[ctms] == dojo.data.lessons[ct].steps[cts].stephitscount[ctms] then
				nctms = ctms + 1
				-- First, check that the microstep has passed
				if nctms >= 1 and ((comboCount() > 0 and (dojo.data.lessons[ct].steps[cts].iscounterhit[ctms] and moveCountered() > 0) or not dojo.data.lessons[ct].steps[cts].iscounterhit[ctms]) or dojo.data.lessons[ct].steps[cts].hitcount[ctms] == 0) then
					if nctms >= 1 and ((dojo.data.lessons[ct].steps[cts].hitcount[ctms] > 1 and comboCount() == dojo.data.lessons[ct].steps[cts].stephitscount[ctms] + dojo.data.lessons[ct].steps[cts].comboCountonstep[ctms] - 1) or dojo.data.lessons[ct].steps[cts].hitcount[ctms] == 1 or dojo.data.lessons[ct].steps[cts].hitcount[ctms] == 0) then
						dojo.data.currentlessonmicrostep = nctms
						if dojo.data.lessons[ct].steps[cts].validfortickcount[ctms] ~= nil then
							dojo.data.validfortickcount = dojo.data.lessons[ct].steps[cts].validfortickcount[ctms]
							dojo.data.windowExpired = false
						else
							dojo.data.validfortickcount = 0
							dojo.data.windowExpired = false
						end
						dojo.data.comboCounter = comboCount()
					elseif ((comboCount() == 0 and dojo.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0) and dojo.data.validfortickcount == 0) or (dojo.data.validfortickcount > 0 and comboCount() > dojo.data.comboCounter) then
						dojo.f_resetAttempt(ct, cts, ctms)
					end
				end
				-- Next, if microstep is exceeded, go to next lesson step
				if dojo.data.currentlessonmicrostep > dojo.data.lessons[ct].steps[cts].numofmicrosteps then
					dojo.data.currentlessonmicrostep = 1
					dojo.data.currentlessonstep = cts + 1
					if dojo.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0 and comboCount() == 0 and comboCount() == dojo.data.comboCounter then
						dojo.data.comboCounter = dojo.data.comboCounter + 1
					else
						dojo.data.comboCounter = comboCount()
					end	
					if dojo.data.lessons[ct].steps[cts].validfortickcount[ctms] ~= nil then
						dojo.data.validfortickcount = dojo.data.lessons[ct].steps[cts].validfortickcount[ctms]
						dojo.data.windowExpired = false
					else
						dojo.data.validfortickcount = 0
						dojo.data.windowExpired = false
					end
					if dojo.data.currentlessonstep > #dojo.data.lessons[ct].steps and dojo.f_countRep(ct) then
						dojo.f_completeLesson(ct)
					end
				end
			end
		elseif ((comboCount() == 0 and dojo.data.lessons[ct].steps[cts].hitcount[ctms] ~= 0) and dojo.data.validfortickcount == 0) or (dojo.data.validfortickcount > 0 and comboCount() > dojo.data.comboCounter)
			or (dojo.data.windowExpired and dojo.data.validfortickcount == 0 and comboCount() == 0) then
			if dojo.data.windowExpired and not dojo.f_comboUnderway(step, ctms, cts) then
				-- Expired window, no combo: f_resetAttempt wouldn't count it, so count it here.
				dojo.f_noteFail(ct)
				dojo.f_resetAttempt(ct, cts, ctms)
			elseif (cts == 1 and ctms == 1) or dojo.data.validfortickcount > 0 or dojo.f_comboUnderway(step, ctms, cts) then
				dojo.f_resetAttempt(ct, cts, ctms)
			else
				-- Hit step after non-hit steps: no combo to lose, so wait for the hit.
				dojo.data.comboCounter = 0
			end
		end
		end -- event step / hit step
	end
	--If the lesson was completed successfully, draw the success banner
	if dojo.draw.success > 0 then
		-- The Lesson the banner is for, not whichever one ct has moved on to.
		dojo.f_drawSuccess('success', dojo.data.successlesson or ct)
	elseif dojo.data.wasPaused then
		-- Hold the fade and reposition where they are while the pause menu is open.
	elseif dojo.draw.fade > 0 and (dojo.ui.resetonsuccess == true or dojo.draw.fadetriggered) and CheckIt == 'root' then
		if dojo.draw.fade < dojo.draw.fadein + dojo.draw.fadeout then
			dojo.f_fade()
		else
			player(2)
			if stateNo() == 0 or dojo.draw.fadetriggered then
							mapSet('_iksys_dojoButtonJamDelay',dojo.draw.fade)
				dojo.f_fade()
			end
			player(1)
		end
	elseif f_checkKeyCombo(dojo.ui.reset_buttonpress) and dojo.draw.fade == 0 and dojo.ui.reset.enabled and dojo.data.currentlesson <= #dojo.data.lessons then
		-- A reset restarts the attempt clock but not the run timer.
		dojo.f_armTimers(dojo.data.currentlesson)
		dojo.draw.fadein = dojo.ui.fadein_time
		dojo.draw.fadeout = dojo.ui.fadeout_time
		dojo.draw.fade = dojo.draw.fadein + dojo.draw.fadeout
		dojo.draw.fadetriggered = true
	-- Only the fade test matters; clearing fadetriggered on a helper pass would cut a reset fade short.
	elseif dojo.draw.fade == 0 then
		dojo.draw.fadetriggered = false
	end
		player(1)
end

-- Last step passed and reps done: record the clear, show the banner, move on.
function dojo.f_completeLesson(ct)
	dojo.f_stopScript(2)
	-- A take that clears the lesson ends here; one not yet recording holds nothing.
	if dojo.f_recording() and dojo.rec.phase == 'recording' then
		dojo.f_finishRecording(false)
	end
	-- Record the clear here, once; f_drawSuccess runs after ct has moved on.
	dojo.f_recordClear(ct, roundTime() - dojo.data.lessons[ct].starttick)
	dojo.selectDirty = true
	-- Remember which lesson earned the banner; ct moves on next frame.
	dojo.data.successlesson = ct
	-- If lesson step was last, go to next lesson and display success banner
	if dojo.data.autoadvance then
		dojo.data.currentlesson = ct + 1
	end
	dojo.f_spendState()
	dojo.data.currentlessonstep = 1
	dojo.data.comboCounter = 0
	if ct < #dojo.data.lessons or (not dojo.data.autoadvance and ct == #dojo.data.lessons) then
		if (dojo.ui.success_front_displaytime == -1) and (dojo.ui.success_bg_displaytime == -1) then
			dojo.draw.success = math.max(animGetLength(dojo.ui.success.front.AnimData), animGetLength(dojo.ui.success.bg.AnimData), dojo.ui.success_text_displaytime)
		else
			dojo.draw.success = math.max(dojo.ui.success_front_displaytime, dojo.ui.success_bg_displaytime, dojo.ui.success_text_displaytime)
		end
		if dojo.ui.resetonsuccess == true then
			dojo.draw.fadein = dojo.ui.fadein_time
			dojo.draw.fadeout = dojo.ui.fadeout_time
			dojo.draw.fade = dojo.draw.fadein + dojo.draw.fadeout
		end
	end
	-- With no banner, release the dummy-setup latch here; the last lesson is the All Clear's.
	if dojo.draw.success == 0 and dojo.data.currentlesson <= #dojo.data.lessons then
		dojo.data.lessons[ct].active = false
		dojo.data.active = false
	end
end

function dojo.f_drawSuccess(successstring, index)
	-- This function is responsible for drawing the Success or All Clear banners after a lesson is completed successfully.
	player(2)
	mapSet('_iksys_dojoDummyMode', 0)
	mapSet('_iksys_dojoGuardMode', 0)
	mapSet('_iksys_dojoButtonJam', 0)
	mapSet('_iksys_dojoDistance', 0)
	mapSet('_iksys_dojoDirection', 0)
	player(1)
	if not dojo.data.lessons[index].complete or (successstring == "allclear" and not dojo.data.allclear) then
		-- Play sound only once
		sndPlay(dojoSnd, dojo.ui[successstring .. '_snd'][1], dojo.ui[successstring .. '_snd'][2])
	end
	-- The banner text is centred on its element's pos rather than its own offset.
	local banner = dojo.ui[successstring]
	dojo.draw[successstring .. '_text']:update({
		text = banner.text.text,
		x = banner.pos[1],
		y = banner.pos[2],
	})
	animUpdate(banner.bg.AnimData)
	animDraw(banner.bg.AnimData)
	dojo.draw[successstring .. '_text']:draw()
	animUpdate(banner.front.AnimData)
	animDraw(banner.front.AnimData)
	dojo.draw[successstring] = dojo.draw[successstring] - 1
	dojo.data.lessons[index].complete = true
	-- Release the frame only once the banner ends, or the next lesson's dummy settings get wiped.
	if dojo.draw[successstring] <= 0 then
		dojo.data.lessons[index].active = false
		dojo.data.active = false
	end
	if not dojo.data.autoadvance then
		dojo.data.lessons[index].starttick = roundTime()
	end
	if index ~= #dojo.data.lessons then
		dojo.data.lessons[index+1].starttick = roundTime()
	end
end

function dojo.f_fade()
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

	if dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[1] == nil then
	dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[1] = 0
	end
	if dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[2] == nil then
	dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[2] = 0
	end
	if dojo.data.lessons[dojo.data.currentlesson].playerposoffset[1] == nil then
	dojo.data.lessons[dojo.data.currentlesson].playerposoffset[1] = 0
	end
	if dojo.data.lessons[dojo.data.currentlesson].playerposoffset[2] == nil then
	dojo.data.lessons[dojo.data.currentlesson].playerposoffset[2] = 0
	end
	
	if dojo.data.lessons[dojo.data.currentlesson].dummypos == 'left-corner' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'left-corner' then
		cameraPosX = leftbound / (stagelocalcoordX/320)
		posx = - (stagelocalcoordX/2 - stageboundleft) / (stagelocalcoordX/320)
		if dojo.data.lessons[dojo.data.currentlesson].dummypos == 'close' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'close' then
			oppx = posx + 10
		elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'far' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'far' then
			oppx = posx + 260
		else --medium or nil
			oppx = posx + 130
		end
		if dojo.data.lessons[dojo.data.currentlesson].dummypos == 'left-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'right-corner' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'right-corner' then
		cameraPosX = rightbound / (stagelocalcoordX/320)
		posx = (stagelocalcoordX/2 - stageboundright) / (stagelocalcoordX/320)
		if dojo.data.lessons[dojo.data.currentlesson].dummypos == 'close' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'close' then
			oppx = posx - 10
		elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'far' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'far' then
			oppx = posx - 260
		else --medium or nil
			oppx = posx - 130
		end
		if dojo.data.lessons[dojo.data.currentlesson].dummypos == 'right-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'close' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'close' then
		dummyposx = 5
		playerposx = -5
	elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'medium' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'medium' then
		dummyposx = 65
		playerposx = -65
	elseif dojo.data.lessons[dojo.data.currentlesson].dummypos == 'far' or dojo.data.lessons[dojo.data.currentlesson].playerpos == 'far' then
		dummyposx = 130
		playerposx = -130
	end

	dummyposx = dummyposx + dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[1]
	dummyposy = dummyposy + dojo.data.lessons[dojo.data.currentlesson].dummyposoffset[2]
	playerposx = playerposx + dojo.data.lessons[dojo.data.currentlesson].playerposoffset[1]
	playerposy = playerposy + dojo.data.lessons[dojo.data.currentlesson].playerposoffset[2]
	
	mapSet('_iksys_dojoCameraPosX', cameraPosX)
	mapSet('_iksys_dojoDummyPosX', dummyposx)
	mapSet('_iksys_dojoDummyPosY', dummyposy)
	mapSet('_iksys_dojoPlayerPosX', playerposx)
	mapSet('_iksys_dojoPlayerPosY', playerposy)
	
	-- This function is responsible for fadein/fadeout if resetonsuccess is set to true.
	if dojo.draw.fadeout > 0 then
		if not fadeActive() then
			dojo.draw.fadeoutData = fadeNew({
			time = dojo.draw.fadeout,
			color = {dojo.ui.fadeout.col[1],
			dojo.ui.fadeout.col[2],
			dojo.ui.fadeout.col[3]},
			anim = dojo.ui.fadeout.anim
			})
		fadeOutInit(dojo.draw.fadeoutData)
		end
		dojo.draw.fadeout = dojo.draw.fadeout - 1

	elseif dojo.draw.fadein > 0 then
		if not fadeActive() then
			mapSet('_iksys_dojoReposition', 1)
			dojo.draw.fadeinData = fadeNew({
			time = dojo.draw.fadein,
			color = {dojo.ui.fadein.col[1],
			dojo.ui.fadein.col[2],
			dojo.ui.fadein.col[3]},
			anim = dojo.ui.fadein.anim
			})
		fadeInInit(dojo.draw.fadeinData)
	end
		dojo.draw.fadein = dojo.draw.fadein - 1
	end

	dojo.draw.fade = dojo.draw.fade - 1
	if dojo.draw.fade == 0 then
			mapSet('_iksys_dojoCameraReset', 1)
end
end

function dojo.f_selectScreen()
-- Gray out select-screen portraits with no lessons on this track; redone when the track changes.
	local want = dojo.f_inMode() and dojo.track or 'normal'
	if want == dojo.selectScreenPalMod then
		return
	end
	dojo.selectScreenPalMod = want
	local tm = dojo.ui
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
					local grayed = want ~= 'normal' and not dojo.f_hasLessons(charData)
					if grayed ~= (charData.dojoGrayed == true) then
						charData.dojoGrayed = grayed
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
function dojo.f_pauseSection(p)
	p = p or dojo.profile
	if motif.pause_menu == nil then
		return nil
	end
	return motif.pause_menu[p.pauseSection]
end

local function f_pauseMenuValues()
	local sec = dojo.f_pauseSection()
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
function dojo.f_difficultyName(d)
	local key = d
	if key == nil or key == '' or key == 'other' then
		key = 'none'
	end
	local pmv = f_pauseMenuValues()
	return pmv['tutorialdifficulty_' .. key] or t_difficultyDefault[key] or key
end

-- Filter display name: chapter name or tier label, overridable via menu.valuename.tutorialchapter_<id>.
function dojo.f_catName(cat)
	if cat == 'all' or cat == 'other' or cat == nil or cat == '' or dojo.t_difficultyIndex[cat] then
		return dojo.f_difficultyName(cat)
	end
	local pmv = f_pauseMenuValues()
	return pmv['tutorialchapter_' .. cat] or dojo.chapterNames[cat] or cat
end

function dojo.f_speedrunEnabled()
	return menu.tutorialspeedrun == 1 and not dojo.f_demoOnly()
end

-- Filter by chapter if any lesson names one, else difficulty if any declare it, else nothing.
function dojo.f_filterMode(arr)
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
function dojo.f_lessonCat(lesson, mode)
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

function dojo.f_filterOrder(arr)
	local t = {'all'}
	arr = arr or (dojo.data ~= nil and dojo.data.lessons or nil)
	local mode = dojo.f_filterMode(arr)
	if mode == 'none' then
		return t
	end
	local has, other = {}, false
	if mode == 'chapter' then
		-- In the order chapters first come up: system lessons are listed first, so their chapters lead.
		for i = 1, #arr, 1 do
			local c = dojo.f_lessonCat(arr[i], mode)
			if c == 'other' then
				other = true
			elseif not has[c] then
				has[c] = true
				t[#t + 1] = c
			end
		end
	else
		for i = 1, #arr, 1 do
			local c = dojo.f_lessonCat(arr[i], mode)
			has[c] = true
		end
		for _, d in ipairs(dojo.t_difficulty) do
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
	return dojo.f_lessonCat(arr[i], mode or dojo.f_filterMode(arr)) == filter
end

-- Gated file: a lesson is locked until the previous lesson from the same file is cleared.
function dojo.f_isLocked(index, arr, ref)
	arr = arr or (dojo.data ~= nil and dojo.data.lessons or nil)
	-- Nothing is ever cleared in demonstrations-only, so nothing could ever open.
	if arr == nil or arr[index] == nil or not arr[index].gated or dojo.f_demoOnly() then
		return false
	end
	for i = index - 1, 1, -1 do
		if arr[i].file == arr[index].file then
			local rec = dojo.f_lessonRecord(i, arr, ref)
			return rec == nil or not rec.cleared
		end
	end
	return false
end

-- %s is the cleared tally (3/5), %p the percentage cleared.
function dojo.f_headerValue(fmt, entry)
	return (fmt:gsub('%%s', entry.value or ''):gsub('%%p', tostring(entry.percent or 0)))
end

function dojo.f_buildSelectItems(arr, ref, withTail)
	local items = {}
	arr = arr or (dojo.data ~= nil and dojo.data.lessons or nil)
	if arr == nil then
		return items
	end
	if withTail == nil then
		withTail = true
	end
	local order = dojo.f_filterOrder(arr)
	local filter = dojo.selectFilter or 'all'
	local known = false
	for _, v in ipairs(order) do
		if v == filter then
			known = true
			break
		end
	end
	if not known then
		filter = 'all'
		dojo.selectFilter = filter
	end
	local mode = dojo.f_filterMode(arr)
	local tier = {}
	local entries = {}
	for _, f in ipairs(order) do
		local n, done = 0, 0
		for i = 1, #arr, 1 do
			if f_inFilter(arr, i, f, mode) then
				n = n + 1
				local rec = dojo.f_lessonRecord(i, arr, ref)
				if rec ~= nil and rec.cleared then
					done = done + 1
				end
				if f == filter then
					tier[#tier + 1] = i
				end
			end
		end
		entries[#entries + 1] = {cat = f, label = dojo.f_catName(f), value = done .. '/' .. n,
			percent = n > 0 and math.floor(done * 100 / n) or 0}
	end

	local label = dojo.f_catName(filter)
	if #order > 1 and dojo.ui.menu.headerdisplay ~= 'sidebyside' then
		-- Laid out side by side the other filters are visible, so the arrows earn nothing.
		label = '< ' .. label .. ' >'
	end
	dojo.selectHeader = {label = label, cat = filter, entries = entries}
	for _, e in ipairs(entries) do
		if e.cat == filter then
			dojo.selectHeader.value = e.value
			dojo.selectHeader.percent = e.percent
		end
	end
	for _, i in ipairs(tier) do
		items[#items + 1] = {
			itemname = 'tutorialentry',
			paramname = 'tutorialentry',
			displayname = arr[i].name,
			selected = dojo.data ~= nil and i == dojo.data.currentlesson,
			lesson = i,
			locked = dojo.f_isLocked(i, arr, ref),
		}
	end
	if withTail and dojo.listTail ~= nil then
		for _, item in ipairs(dojo.listTail) do
			items[#items + 1] = item
		end
	end
	if #items == 0 then
		items[1] = {itemname = 'back', paramname = 'back', displayname = 'Back', vardisplay = '', selected = false}
	end
	return items
end

-- Cursor starts on the first uncleared lesson.
function dojo.f_firstUncleared(items, arr, ref)
	local first = nil
	for i, v in ipairs(items) do
		if v.lesson ~= nil then
			if first == nil then
				first = i
			end
			local rec = dojo.f_lessonRecord(v.lesson, arr, ref)
			if (rec == nil or not rec.cleared) and not v.locked then
				return i
			end
		end
	end
	return first or 1
end

-- Rebuilt whenever progress changes, so a clear shows up on the row immediately.
function dojo.f_refreshSelect()
	if dojo.data == nil or not dojo.data.initialized then
		return
	end
	local items = dojo.f_buildSelectItems()
	for _, node in ipairs(dojo.f_selectNodes()) do
		node.items = items
		if node.item > #items then
			node.item = #items
		end
	end
	dojo.selectDirty = false
end

-- The two views onto the same list: the Pause menu's Lesson List and the match-load screen.
function dojo.f_selectNodes()
	local t = {}
	if type(dojo.listNode) == 'table' then t[#t + 1] = dojo.listNode end
	if type(dojo.select) == 'table' then t[#t + 1] = dojo.select end
	return t
end

-- After a filter change, both cursors go to the first uncleared lesson in the filter.
function dojo.f_resetSelectCursors()
	for _, node in ipairs(dojo.f_selectNodes()) do
		if type(node.items) == 'table' then
			node.item = dojo.f_firstUncleared(node.items)
			node.first = 1
		end
	end
end

-- Step through filters; returns whether anything moved, for the sound.
function dojo.f_cycleFilterFor(node, dir)
	local order = dojo.f_filterOrder(node.list)
	if #order < 2 then
		return false
	end
	local idx = 1
	for i, v in ipairs(order) do
		if v == (dojo.selectFilter or 'all') then
			idx = i
			break
		end
	end
	dojo.selectFilter = order[(idx - 1 + dir) % #order + 1]
	node.items = dojo.f_buildSelectItems(node.list, node.ref, false)
	node.item = dojo.f_firstUncleared(node.items, node.list, node.ref)
	node.first = 1
	return true
end

function dojo.f_cycleFilter(dir)
	local order = dojo.f_filterOrder()
	if #order < 2 then
		return false
	end
	local idx = 1
	for i, v in ipairs(order) do
		if v == (dojo.selectFilter or 'all') then
			idx = i
			break
		end
	end
	dojo.selectFilter = order[(idx - 1 + dir) % #order + 1]
	dojo.f_refreshSelect()
	dojo.f_resetSelectCursors()
	return true
end

-- Freeze both players while the view is up; a countdown in dojo.zss releases it if not refreshed.
function dojo.f_menuHold(on)
	local v = 0
	if on then
		v = 10
	end
	player(2)
	mapSet('_iksys_dojoMenuOpen', v)
	player(1)
	mapSet('_iksys_dojoMenuOpen', v)
end

-- When the lesson list shows: select (before the fight), start (over the frozen match), or off.
function dojo.f_listDisplay()
	local v = tostring(dojo.ui.listdisplay or 'start'):lower()
	if v == 'select' or v == 'off' then
		return v
	end
	return 'start'
end

-- Whether any lesson is gated on P1's vars, which can't be read before the match; uses the unthinned list.
function dojo.f_hasVarGatedLessons(arr)
	if arr == nil then
		if type(start.p) ~= 'table' or type(start.p[1]) ~= 'table'
			or type(start.p[1].t_selected) ~= 'table' or start.p[1].t_selected[1] == nil then
			return false
		end
		local ok, charData = pcall(start.f_getCharData, start.p[1].t_selected[1].ref)
		if not ok or type(charData) ~= 'table' then
			return false
		end
		arr = dojo.f_lessonsFor(charData)
	end
	if type(arr) ~= 'table' then
		return false
	end
	for i = 1, #arr, 1 do
		-- The same test f_buildMatch thins by, so the two cannot disagree about what counts as gated.
		if type(arr[i].showforvar) == 'table' and arr[i].showforvar[1] ~= nil then
			return true
		end
	end
	return false
end

function dojo.f_openSelect()
	if dojo.select == nil or dojo.data == nil or #dojo.data.lessons == 0 then
		return
	end
	dojo.f_refreshSelect()
	dojo.select.item = dojo.f_firstUncleared(dojo.select.items)
	dojo.select.first = 1
	dojo.select.openDelay = 10
	local it = dojo.select.items[dojo.select.item]
	if it ~= nil and it.lesson ~= nil then
		dojo.data.currentlesson = it.lesson
	end
	dojo.select.open = true
	dojo.f_menuHold(true)
	local sec = dojo.f_selectSection()
	if sec ~= nil then
		sndPlay(motif.Snd, sec.enter.snd[1], sec.enter.snd[2])
	end
end

function dojo.f_armTimers(index, wholeRun)
	if dojo.data == nil then
		return
	end
	local now = roundTime()
	if wholeRun then
		dojo.data.starttick = now
		dojo.data.elapsedtime = 0
	end
	if dojo.data.lessons[index] ~= nil then
		dojo.data.lessons[index].starttick = now
	end
end

function dojo.f_closeSelect()
	if dojo.select ~= nil then
		dojo.select.open = false
	end
	dojo.f_menuHold(false)
	-- Time spent choosing belongs to nobody's run.
	if dojo.data ~= nil then
		dojo.f_armTimers(dojo.data.currentlesson, true)
	end
end

function dojo.f_selectSection()
	if motif.pause_menu == nil then
		return nil
	end
	return dojo.f_pauseSection() or motif.pause_menu.pause_menu
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

-- Filled rect from an overlay node, window relative to x,y; localcoord first, empty windows skipped.
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
	rectSetLocalcoord(node.RectData, dojo.f_localcoord())
	rectSetColor(node.RectData, node.col[1], node.col[2], node.col[3])
	rectSetAlpha(node.RectData, node.alpha[1], node.alpha[2])
	rectSetLayerno(node.RectData, f_clampLayerno(node.layerno))
	rectSetWindow(node.RectData, x + w[1], y + w[2], x + w[3], y + w[4])
	rectDraw(node.RectData)
end

-- Whether the author named art; if not, the element's .text label draws instead.
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

-- Text objects per used style, made on first sight rather than pre-allocated.
local function f_rowText(style, cat, row, node)
	local d = dojo.menuDraw
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

-- Draw as art if named, otherwise as the .text label.
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

function dojo.f_selectDraw(node)
	-- Shown both before the fight, on the motif's aspect, and over a live match, on the stage's.
	dojo.f_syncAspect()
	local m = dojo.ui.menu
	local d = dojo.menuDraw
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
	local h = dojo.selectHeader
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
						dojo.f_headerValue(val.text, e))
				end
			end
		else
			local cat = h.cat or 'all'
			f_menuAnim((f_catState(m.header, cat, true, 'bg')), hx, hy)
			local txt, tk = f_catState(m.header, cat, true, 'text')
			f_menuText(f_rowText('header', tk, 1, txt), txt, hx, hy, h.label)
			local val, vk = f_catState(m.header, cat, true, 'value')
			if val.text ~= '' then
				f_menuText(f_rowText('headervalue', vk, 1, val), val, hx, hy, dojo.f_headerValue(val.text, h))
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
			local arr = node.list or (dojo.data ~= nil and dojo.data.lessons or nil)
			if arr ~= nil and arr[item.lesson] ~= nil then
				cat = dojo.f_lessonCat(arr[item.lesson], dojo.f_filterMode(arr))
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
			local rec = dojo.f_lessonRecord(item.lesson, node.list, node.ref)
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
function dojo.f_selectLoop(node, standalone)
	local sec = dojo.f_selectSection()
	if sec == nil or dojo.data == nil or dojo.menuDraw == nil or node.items == nil then
		return
	end
	if not standalone then
		hook.run("menu.menu.loop")
	end
	if standalone then
		dojo.f_menuHold(true)
	end
	if dojo.selectDirty then
		dojo.f_refreshSelect()
	end
	local t = node.items
	if #t == 0 then
		return
	end
	node.item = math.max(1, math.min(node.item, #t))
	for _, item in ipairs(t) do
		if item.lesson ~= nil then
			item.selected = item.lesson == dojo.data.currentlesson
		end
	end
	dojo.f_selectDraw(node)
	-- Sample input every frame so a held button doesn't read as a fresh press.
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
	if filter ~= 0 and dojo.f_cycleFilter(filter) then
		sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
		return
	end
	if dir ~= 0 and f_moveCursor(node, dir) then
		sndPlay(motif.Snd, sec.cursor.move.snd[1], sec.cursor.move.snd[2])
	end
	-- Cancel only applies in the pause menu; match-load exits by picking or Back.
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
		dojo.f_gotoLesson(it.lesson, false, standalone)
	elseif standalone then
		-- the section's own tail items, Back among them: nothing to go back to out here, so close.
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		dojo.f_closeSelect()
	else
		sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		menu.currentMenu[1] = menu.currentMenu[2]
	end
end

--;===========================================================
--; Lesson select menu - before the fight
--;===========================================================
-- Snapshot the select picks so they can be restored after f_selectReset.
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

-- Cancelling the pre-fight list goes back one step (stage select, else P2's pick), not to P1's pick.
function dojo.f_restoreSelect()
	local snap = dojo.backToSelectSnap
	dojo.backToSelectSnap = nil
	if snap == nil or not dojo.f_inMode() then
		return
	end
	local stageStep = main.stageMenu
	-- Without stage select, step back to P2's pick only if P2 was picked rather than forced.
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

-- Out-of-match lesson list; returns the picked name or nil, and true when it was empty.
function dojo.f_lessonListLoop(lessons, ref, sec)
	dojo.selectFilter = 'all'
	local node = {list = lessons, ref = ref, item = 1, first = 1}
	node.items = dojo.f_buildSelectItems(node.list, node.ref, false)
	if #node.items == 0 then
		return nil, true
	end
	node.item = dojo.f_firstUncleared(node.items, node.list, node.ref)
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
		if filter ~= 0 and dojo.f_cycleFilterFor(node, filter) then
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
		dojo.f_selectDraw(node)
		bgDraw(motif.selectbgdef.BGDef, 1)
		main.f_preloadTick(2)
		refresh()
	end
	resetKey()
	return picked
end

function dojo.f_preFightMenu()
	-- The Game Tutorial picked its lesson before the match was set up (gametutorial.lua).
	if not dojo.f_inMode() or dojo.track == 'game' or dojo.f_listDisplay() ~= 'select' then
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
	local lessons = dojo.f_lessonsFor(charData)
	if #lessons == 0 then
		return
	end
	-- Var-gated lessons can't be listed before the match; the match-load list asks instead.
	if dojo.f_hasVarGatedLessons(lessons) then
		return
	end
	local sec = dojo.f_selectSection()
	if sec == nil then
		return
	end
	local snap = f_snapshotSelect()
	dojo.backToSelect = false
	local picked, empty = dojo.f_lessonListLoop(lessons, ref, sec)
	if empty then
		return
	end
	dojo.pendingLesson = picked
	if picked == nil then
		-- Back one step to the select screen; f_selectVersus calls the fight off.
		dojo.backToSelect = true
		dojo.backToSelectSnap = snap
	end
end

--;===========================================================
--; Game Tutorial
--;===========================================================
-- Game Tutorial loop: lesson list, match, repeat; P1 from playerchar/TutorialPlayerChar/pick, P2 from dummychar/TutorialDummy/pick/mirror.
function dojo.f_gameTutorialRun()
	local selectShown = main.selectMenu[1] or main.selectMenu[2]
	-- launchFight overwrites t_selected, so what the select screen settled on is kept here.
	dojo.pickedRef = start.p[1].t_selected[1] ~= nil and start.p[1].t_selected[1].ref or nil
	dojo.p2PickedRef = nil
	if main.selectMenu[2] and main.forceChar[2] == nil and start.p[2].t_selected[1] ~= nil then
		dojo.p2PickedRef = start.p[2].t_selected[1].ref
	end
	dojo.relaunchLesson = nil
	local sec = dojo.f_selectSection()
	local lessons = dojo.f_lessonsFor(nil)
	if #lessons == 0 or sec == nil then
		print('Dojo: the Game Tutorial has no game-wide lessons to offer; see SystemTutorial in config.ini.')
		setMatchNo(-1)
		return
	end
	while true do
		local name = dojo.relaunchLesson
		dojo.relaunchLesson = nil
		if name == nil then
			bgReset(motif.selectbgdef.BGDef)
			playBgm({source = "motif.select", interrupt = true})
			-- Fresh copies each time round, so the list shows what the last match cleared.
			lessons = dojo.f_lessonsFor(nil)
			name = dojo.f_lessonListLoop(lessons, dojo.pickedRef, sec)
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
		local p1 = dojo.f_playerFor(lesson)
		if p1 == nil then
			print('Dojo: no character to play "' .. tostring(name) .. '" with; set TutorialPlayerChar in config.ini.')
			setMatchNo(-1)
			return
		end
		local p2 = dojo.f_dummyFor(lesson)
		dojo.gameP1, dojo.gameP2 = p1, p2
		dojo.pendingLesson = name
		-- launchFight replaces P1's selection when given p1char, but adds p2char to P2's.
		start.p[2].t_selected = {}
		start.p[2].t_selTemp = {}
		launchFight{
			p1char = {start.f_getCharData(p1).char},
			p2char = {start.f_getCharData(p2).char},
		}
		if dojo.relaunchLesson == nil then
			-- Leave on exit or when a select screen exists; otherwise Character Change returns to the list.
			if matchNo() == -1 or selectShown then
				return
			end
		end
	end
end

--;===========================================================
--; Speedrun
--;===========================================================
-- Decides which conditional root items show: no list in speedrun, demo/record/instructions only where they apply.
local function f_rootItemShown(name, on)
	if name == 'tutorialrecord' or name == 'tutorialrecorddummy' then
		return dojo.recordEnabled and not dojo.f_demoOnly()
	elseif name == 'tutorialdemo' and dojo.f_demoOnly() then
		return false
	elseif name == 'tutoriallist' then
		return not on
	elseif name == 'tutorialdemo' or name == 'tutorialinstructions' then
		local d = dojo.data
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

function dojo.f_applySpeedrun()
	if dojo.rootNode == nil or dojo.rootItems == nil then
		return
	end
	local on = dojo.f_speedrunEnabled()
	local items = {}
	for _, item in ipairs(dojo.rootItems) do
		if f_rootItemShown(item.itemname, on) then
			items[#items + 1] = item
		end
	end
	-- Rows changed, so reset the cursor to the top.
	if #items ~= #(dojo.rootNode.items or {}) then
		dojo.rootNode.item = 1
		dojo.rootNode.cursorPosY = 1
		dojo.rootNode.moveTxt = 0
	end
	dojo.rootNode.items = items
	if dojo.rootNode.item > #items then
		dojo.rootNode.item = #items
		dojo.rootNode.cursorPosY = 1
		dojo.rootNode.moveTxt = 0
	end
	if on then
		menu.tutorialadvancement = 1
		if dojo.data ~= nil then
			dojo.data.autoadvance = true
		end
		for _, v in ipairs(menu.t_vardisplayPointers) do
			if v.itemname == 'tutorialadvancement' then
				v.vardisplay = menu.f_vardisplay('tutorialadvancement')
			end
		end
	end
end

-- Leaving for character select ends the speedrun.
function dojo.f_resetSpeedrun()
	menu.tutorialspeedrun = 2
	dojo.f_applySpeedrun()
	for _, v in ipairs(menu.t_vardisplayPointers) do
		if v.itemname == 'tutorialspeedrun' then
			v.vardisplay = menu.f_vardisplay('tutorialspeedrun')
		end
	end
end

-- Starts a fresh run: back to the first Lesson with the total timer armed and the run counted.
function dojo.f_startSpeedrun()
	if dojo.data == nil or #dojo.data.lessons == 0 then
		return
	end
	dojo.f_gotoLesson(1, true, true)
	dojo.data.runValid = true
end

-- Game Tutorial: end the match when the lesson needs a different P1 or dummy, after pause and banner finish.
function dojo.f_relaunchForPlayer()
	if dojo.track ~= 'game' then
		return false
	end
	if dojo.relaunchLesson ~= nil then
		return true
	end
	if paused() or (dojo.draw ~= nil and (dojo.draw.success or 0) > 0) then
		return false
	end
	local l = dojo.data.lessons[dojo.data.currentlesson]
	if l == nil or (dojo.f_playerFor(l) == dojo.gameP1 and dojo.f_dummyFor(l) == dojo.gameP2) then
		return false
	end
	dojo.relaunchLesson = l.name
	dojo.f_endDemo(false)
	dojo.f_stopScript(1)
	dojo.f_stopScript(2)
	endMatch()
	start.characterchange = true
	return true
end

function dojo.f_matchLoop()
	-- Lay the canvas out for the current aspect; no-op once settled.
	dojo.f_syncAspect()
	dojo.f_shieldTick()

	if roundStart() then
		dojo.f_cancelRecording()
		dojo.f_endDemo(false)
		dojo.f_stopScript(1)
		dojo.f_stopScript(2)
		dojo.data = nil
		-- Empty the lesson list back to the items and loop the section declared.
		if dojo.listNode ~= nil and dojo.listTail ~= nil then
			dojo.listNode.items = dojo.listTail
			dojo.listNode.item = 1
			dojo.listNode.cursorPosY = 1
			dojo.listNode.moveTxt = 0
			dojo.listNode.loop = dojo.listLoop
		end
		if dojo.rootNode ~= nil and dojo.rootItems ~= nil then
			dojo.rootNode.items = dojo.rootItems
			dojo.rootNode.item = 1
			dojo.rootNode.cursorPosY = 1
			dojo.rootNode.moveTxt = 0
		end
		dojo.select = nil
		dojo.pages = nil
		dojo.selectDirty = false
		dojo.p1selref = nil
		dojo.charPortraitSff = nil
		dojo.ui.textbox.portrait.anim = nil
		-- Check if there's a lesson file - if so, parse it
		if dojo.f_hasLessons(start.f_getCharData(start.p[1].t_selected[1].ref)) then
			dojo.f_initData()
			lessonsExist = true
 		else
			lessonsExist = false
		end
	end

	if dojo.p1selref == nil then
		if start.p[1].t_selected[1].ref ~= nil then
			dojo.p1selref = start.p[1].t_selected[1].ref
		end
	end
					
	if lessonsExist and roundState() == 2 and not dojo.data.initialized then
		-- Initialize the lessons based on parsed file and char state at roundState() == 2
		dojo.f_buildMatch()
		menu.f_dojoReset()
		-- Restore the pre-fight pick by name, since f_buildMatch may have dropped lessons.
		local pickLost = false
		if dojo.pendingLesson ~= nil then
			pickLost = true
			for i = 1, #dojo.data.lessons, 1 do
				if dojo.data.lessons[i].name == dojo.pendingLesson then
					dojo.data.currentlesson = i
					pickLost = false
					break
				end
			end
			dojo.pendingLesson = nil
		end
		-- Arm both clocks before anything reads them.
		dojo.f_armTimers(dojo.data.currentlesson, true)
		-- Speedrun or list off goes straight in; otherwise ask, unless already asked before the fight.
		local mode = dojo.f_listDisplay()
		if dojo.f_speedrunEnabled() then
			dojo.f_startSpeedrun()
		elseif dojo.track == 'game' then
			if pickLost then
				dojo.f_openSelect()
			end
		elseif mode == 'start' or (mode == 'select' and (dojo.f_hasVarGatedLessons() or pickLost)) then
			dojo.f_openSelect()
		end
	elseif lessonsExist and roundState() == 2 and dojo.data.initialized
		and dojo.select ~= nil and dojo.select.open then
		-- The select view owns the frame unless paused.
		if not paused() then
			dojo.f_selectLoop(dojo.select, true)
		end
	elseif lessonsExist and roundState() == 2 and dojo.data.initialized and dojo.f_pagesOpen() then
		-- Instruction pages own the frame until read, like the select view, unless the pause menu is up.
		if not paused() then
			dojo.f_pagesLoop()
		end
	elseif lessonsExist and roundState() == 2 and dojo.data.initialized then
		-- Game Tutorial: end the match here when the lesson needs another P1.
		if dojo.f_relaunchForPlayer() then
			return
		end
		-- If the lessons are initialized, draw elements and check for success!
		if dojo.f_demoActive() and not paused() then
			dojo.f_demoTick()
		end
		dojo.f_drawer()
		dojo.f_demoOnlyGuard()
		player(1)
		dojo.f_checker('root')
		if numHelper() > 0 and dojo.draw.success == 0 then
			for i = 1, numHelper(), 1 do
				dojo.f_checker(i)
			end
		end
		player(1)
		if not paused() then
			dojo.f_scriptTick()
		end
		dojo.f_recordTick()
	elseif roundState() == 2 then
		-- No lessons present!
		player(2)
		setAILevel(0)
		mapSet('_iksys_dojoSetLife', lifeMax())
		player(1)
		mapSet('_iksys_dojoDummyControl', 0)
		mapSet('_iksys_dojoSetLife', lifeMax())
		if dojo.nodatacounter == nil then
			dojo.nodatacounter = f_newText(dojo.ui.counter)
		end
		dojo.nodatacounter:update({x = dojo.ui.counter_pos[1], y = dojo.ui.counter_pos[2], text = dojo.ui.counter_nodata_text})
		dojo.nodatacounter:draw()
	end
end

--;===========================================================
--; Teaching features: instruction pages, repetitions, hints, event steps
--;===========================================================
-- Defaults for the teaching blocks, so older defs still get a plain working look.
local function f_uiTeach()
	local tm = dojo.ui
	local cx, cy = dojo.mtlcx / 2, dojo.mtlcy / 2
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
	-- Only the portrait's placement is settled here; it's built per page.
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
	if type(hint.pos) ~= 'table' then hint.pos = {cx, dojo.mtlcy - 40} end
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
	if type(dprompt.pos) ~= 'table' then dprompt.pos = {cx, dojo.mtlcy - 80} end
	textNode(f_node(dprompt, 'text'), 'Pause and pick Watch Demo to see it done')
	local doprompt = f_node(tm, 'demoonlyprompt')
	if type(doprompt.pos) ~= 'table' then doprompt.pos = {cx, dojo.mtlcy - 80} end
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

	dojo.teach = {
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
		animSetLocalcoord(node.AnimData, dojo.f_localcoord())
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

-- Per-character sprite and anim cache for char-sourced portraits; false marks an unreadable one.
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

-- Page portrait: the page's spr/anim replace the def's; source is system (Dojo art) or char (P1's).
local function f_pagePortrait(pg)
	local por = dojo.ui.instructions.portrait
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
		local art = f_charArt(dojo.p1selref)
		if art == nil then
			return nil
		end
		sprData, animData = art.sff, art.anims
	end
	return f_loadAnimData({spr = spr, anim = anim, offset = por.offset, scale = por.scale,
		facing = por.facing, layerno = por.layerno}, 0, 0, sprData, animData)
end

-- Showing a page builds its portrait and plays its sound.
local function f_showPage(p, lesson)
	local pg = lesson.pages[p.page]
	if pg == nil then
		return
	end
	p.portrait = f_pagePortrait(pg)
	f_playSnd(pg.snd or dojo.ui.instructions.page.snd)
end

-- Portrait window is x1,y1,x2,y2 from its position; all zero leaves it unclipped.
local function f_drawPortrait(a, por, x, y)
	if a == nil then
		return
	end
	local px, py = x + por.offset[1], y + por.offset[2]
	local w = por.window
	animSetLocalcoord(a, dojo.f_localcoord())
	animSetPos(a, px, py)
	if w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0 then
		animSetWindow(a, 0, 0, dojo.vislcx, dojo.mtlcy)
	else
		animSetWindow(a, px + w[1], py + w[2], px + w[3], py + w[4])
	end
	animUpdate(a)
	animDraw(a)
end

----------------------------------------------------------------
-- Instruction pages
----------------------------------------------------------------
-- Pages show once per lesson entry; the pause menu reopens them.
function dojo.f_openPages(index)
	local lesson = dojo.data ~= nil and dojo.data.lessons[index] or nil
	if lesson == nil or type(lesson.pages) ~= 'table' or #lesson.pages == 0 then
		return false
	end
	lesson.pagesSeen = true
	dojo.pages = {open = true, lesson = index, page = 1, ticks = 0}
	dojo.f_menuHold(true)
	f_playSnd(dojo.ui.instructions.snd)
	f_showPage(dojo.pages, lesson)
	return true
end

function dojo.f_closePages()
	if dojo.pages ~= nil then
		dojo.pages.open = false
	end
	dojo.f_menuHold(false)
	-- Reading is nobody's attempt time. A speedrun never opens the pages, so its run clock is safe.
	if dojo.data ~= nil then
		dojo.f_armTimers(dojo.data.currentlesson)
	end
end

function dojo.f_pagesOpen()
	return dojo.pages ~= nil and dojo.pages.open
end

function dojo.f_pagesLoop()
	local p = dojo.pages
	local lesson = dojo.data.lessons[p.lesson]
	local pg = lesson ~= nil and lesson.pages[p.page] or nil
	if pg == nil then
		dojo.f_closePages()
		return
	end
	dojo.f_syncAspect()
	dojo.f_menuHold(true)
	local ins = dojo.ui.instructions
	local t = dojo.teach
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

	-- Pause section keys, sampled every frame so a held button isn't a fresh press.
	local sec = dojo.f_selectSection()
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
			dojo.f_closePages()
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
-- Zero every step's hit tallies for a fresh attempt.
local function f_clearStepCounts(index)
	for _, s in ipairs(dojo.data.lessons[index].steps) do
		for k = 1, s.numofmicrosteps, 1 do
			s.stephitscount[k] = 0
			s.comboCountonstep[k] = 0
		end
	end
end

function dojo.f_countRep(index)
	local lesson = dojo.data.lessons[index]
	-- A demo never earns a clear, and demonstrations-only never has anything else.
	local watching = dojo.f_demoActive() or dojo.f_demoOnly()
	if not watching then
		lesson.repsdone = (lesson.repsdone or 0) + 1
	end
	if lesson.repsdone >= (lesson.reps or 1) and not watching then
		lesson.repsdone = 0
		return true
	end
	dojo.f_spendState()
	f_clearStepCounts(index)
	dojo.data.currentlessonstep = 1
	dojo.data.currentlessonmicrostep = 1
	-- Keep the finishing combo's count so its next frame isn't a fresh hit.
	dojo.data.comboCounter = comboCount()
	dojo.data.validfortickcount = 0
	dojo.data.windowExpired = false
	f_playSnd(dojo.ui.repcounter.snd)
	return false
end

-- Count a lost attempt toward hintafter; idle frames at step one aren't failures.
function dojo.f_noteFail(index)
	local lesson = dojo.data.lessons[index]
	if lesson ~= nil and not dojo.f_demoActive() and not dojo.f_demoOnly() then
		lesson.fails = (lesson.fails or 0) + 1
	end
end

-- Restart the attempt from step one, counting a failure if progress was lost.
function dojo.f_resetAttempt(index, si, mi)
	local step = dojo.data.lessons[index].steps[si]
	if dojo.f_comboUnderway(step, mi, si) then
		dojo.f_noteFail(index)
	end
	dojo.f_spendState()
	dojo.data.currentlessonstep = 1
	dojo.data.currentlessonmicrostep = 1
	-- Clear all steps, so the idle reset next frame isn't a second failure.
	f_clearStepCounts(index)
	dojo.data.comboCounter = 0
	dojo.data.validfortickcount = 0
	dojo.data.windowExpired = false
end

-- Whether a drop to zero combo loses progress: hits on this step, or a combo from earlier steps.
function dojo.f_comboUnderway(step, mi, si)
	return ((si > 1 or mi > 1) and dojo.data.comboCounter > 0) or (step.stephitscount[mi] or 0) > 0
end

function dojo.f_hintsOn()
	return tostring(opts.Hints or 'true'):lower() ~= 'false'
end

-- The repetition counter and the hint, drawn with the rest of the lesson HUD.
function dojo.f_drawLessonExtras(index)
	local lesson = dojo.data.lessons[index]
	if lesson == nil then
		return
	end
	local tm, t = dojo.ui, dojo.teach
	if (lesson.reps or 1) > 1 then
		local rep = tm.repcounter
		f_drawArt(rep.bg, rep.pos[1], rep.pos[2])
		f_drawText(t.rep, rep.text, rep.pos[1], rep.pos[2],
			(rep.text.text:gsub('%%s', tostring(lesson.repsdone or 0)):gsub('%%t', tostring(lesson.reps))))
	end
	if dojo.f_recording() then
		local dm = tm.demo
		local who = dojo.rec.pn == 2 and 'REC DUMMY' or 'REC'
		local label = dojo.rec.phase == 'recording' and (who .. ' ' .. #dojo.rec.frames) or (who .. ' - waiting for input (pause to stop)')
		f_drawText(t.demo, dm.text, dm.pos[1], dm.pos[2], label)
	elseif dojo.f_demoActive() then
		local dm = tm.demo
		f_drawArt(dm.bg, dm.pos[1], dm.pos[2])
		f_drawText(t.demo, dm.text, dm.pos[1], dm.pos[2], dm.text.text)
		if dojo.f_demoOnly() then
			local dp = tm.demoonlyprompt
			local last = index >= #dojo.data.lessons
			local str = last and dp.text.last or dp.text.text
			if str ~= '' then
				f_drawText(t.demoonlyprompt, dp.text, dp.pos[1], dp.pos[2], str)
			end
		end
	elseif dojo.f_demoOffered(lesson) then
		local dp = tm.demoprompt
		f_drawText(t.demoprompt, dp.text, dp.pos[1], dp.pos[2], dp.text.text)
	end
	local hint = tm.hint
	if lesson.hint ~= '' and dojo.f_hintsOn() and f_menuOn(hint.visible) and (lesson.fails or 0) >= (lesson.hintafter or 0) then
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
dojo.t_guardStates = {[150] = 'high', [151] = 'high', [152] = 'low', [153] = 'low', [154] = 'air', [155] = 'air'}

-- Per-frame events stamped with the frame: P1 blocked, P1 hit, P1's move blocked, dummy state.
function dojo.f_trackEvents(newinstance)
	local d = dojo.data
	d.frame = (d.frame or 0) + 1
	local ev = d.ev
	if ev == nil then
		ev = {}
		d.ev = ev
	end
	local sn = stateNo()
	local kind = dojo.t_guardStates[sn]
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
	-- P1's projectiles being blocked: ticks since the last blocked contact, -1 when the last contact wasn't one.
	local okp, pg = pcall(projGuardedTime, 0)
	pg = okp and tonumber(pg) or -1
	if pg >= 0 and ((ev.lastProjGuarded or -1) < 0 or pg < ev.lastProjGuarded) then
		ev.projGuardedFrame = d.frame
	end
	ev.lastProjGuarded = pg
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
function dojo.f_p2StateOk(step, mi)
	local want = step.p2stateno[mi]
	if want == nil or #want == 0 then
		return true
	end
	return f_inList(want, dojo.data.ev ~= nil and dojo.data.ev.p2State or nil)
end

-- Event step: guard, isguarded, or dummy state with nothing else asked.
function dojo.f_isEventStep(step, mi)
	if step.guard[mi] ~= nil or step.isguarded[mi] then
		return true
	end
	return step.p2stateno[mi] ~= nil and #step.p2stateno[mi] > 0
		and #step.stateno == 0 and #step.animno == 0 and #step.projid == 0
end

-- Advance past the microstep, and past the step and lesson when last; event steps only.
local function f_advanceMicro(index, si, mi)
	local step = dojo.data.lessons[index].steps[si]
	step.stephitscount[mi] = 0
	dojo.data.stringUnit = nil
	dojo.data.currentlessonmicrostep = mi + 1
	dojo.data.validfortickcount = step.validfortickcount[mi] or 0
	dojo.data.windowExpired = false
	dojo.data.comboCounter = comboCount()
	if dojo.data.currentlessonmicrostep > step.numofmicrosteps then
		dojo.data.currentlessonmicrostep = 1
		dojo.data.currentlessonstep = si + 1
		if dojo.data.currentlessonstep > #dojo.data.lessons[index].steps and dojo.f_countRep(index) then
			dojo.f_completeLesson(index)
		end
	end
end

-- Blockstring: an isguarded unit right after another must land before the dummy leaves blockstun.
-- Enforced once the dummy is seen in blockstun after the earlier block, so arrival-frame timing can't fail it.
local function f_blockstringBroken(index, si, mi)
	local d = dojo.data
	local lesson = d.lessons[index]
	local ps, pm = nil, nil
	if mi > 1 then
		ps, pm = lesson.steps[si], mi - 1
	elseif si > 1 then
		ps = lesson.steps[si - 1]
		pm = ps.numofmicrosteps
	end
	if ps == nil or not ps.isguarded[pm] then
		return false
	end
	local unit = si .. ':' .. mi
	if d.stringUnit ~= unit then
		d.stringUnit, d.stringSeen = unit, false
	end
	if dojo.t_guardStates[(d.ev or {}).p2State] ~= nil then
		d.stringSeen = true
		return false
	end
	return d.stringSeen
end

-- isguarded with projid: the blocked contact was one of the step's projectiles, fired from its stateno if any.
local function f_projGuardMatch(step, mi, statecheck)
	local want = step.stateno[mi]
	for _, id in ipairs(step.projid[mi]) do
		local ok, t = pcall(projGuardedTime, id)
		if ok and tonumber(t) ~= nil and tonumber(t) >= 0 then
			if want == nil or #want == 0 or statecheck then
				return true
			end
			for _, s in ipairs(want) do
				if dojo.data.projsource[id] == s then
					return true
				end
			end
		end
	end
	return false
end

-- Root pass only: every event is the root's (P1 blocking, P1's move blocked, the dummy's state).
function dojo.f_checkEventStep(index, si, mi, statecheck, animcheck)
	local d, ev = dojo.data, dojo.data.ev or {}
	local step = d.lessons[index].steps[si]
	local need = math.max(step.hitcount[mi] or 1, 1)
	local happened = false
	if step.guard[mi] ~= nil then
		local want = step.guard[mi]
		happened = ev.guardFrame == d.frame and (want == 'any' or want == ev.guardKind)
		if not happened and ev.hitFrame == d.frame then
			-- Hit instead of blocking: that attempt is over.
			dojo.f_noteFail(index)
			dojo.f_spendState()
			d.currentlessonstep, d.currentlessonmicrostep = 1, 1
			step.stephitscount[mi] = 0
			return
		end
	elseif step.isguarded[mi] then
		if step.projid[mi] ~= nil and #step.projid[mi] > 0 then
			-- A projectile is blocked on the projectile, not on P1's move.
			happened = ev.projGuardedFrame == d.frame and f_projGuardMatch(step, mi, statecheck)
		else
			happened = ev.guardedFrame == d.frame and statecheck and animcheck
		end
		if not happened and f_blockstringBroken(index, si, mi) then
			-- The dummy got out of blockstun between blocked steps: that attempt is over.
			dojo.f_noteFail(index)
			dojo.f_spendState()
			d.currentlessonstep, d.currentlessonmicrostep = 1, 1
			d.stringUnit = nil
			step.stephitscount[mi] = 0
			return
		end
	else
		happened = ev.p2Frame == d.frame
	end
	if not happened and d.windowExpired then
		-- The previous step's window ran out first: that attempt is over, whatever the combo.
		dojo.f_noteFail(index)
		dojo.f_spendState()
		d.currentlessonstep, d.currentlessonmicrostep = 1, 1
		d.stringUnit = nil
		d.validfortickcount, d.windowExpired = 0, false
		step.stephitscount[mi] = 0
		return
	end
	if happened and dojo.f_p2StateOk(step, mi) then
		step.stephitscount[mi] = (step.stephitscount[mi] or 0) + 1
		if step.stephitscount[mi] >= need then
			f_advanceMicro(index, si, mi)
		end
	end
end

--;===========================================================
--; Input scripts: demonstrations (P1) and dummy scripts (P2)
--;===========================================================
-- Input scripts: frames:inputs tokens, + joins, _ is nothing, F/B face-relative; dojo.zss asserts them.
dojo.t_scriptInputs = {'U', 'D', 'F', 'B', 'a', 'b', 'c', 'x', 'y', 'z', 's', 'd', 'w'}
local t_scriptValid = {}
for _, k in ipairs(dojo.t_scriptInputs) do t_scriptValid[k] = true end
dojo.scriptMaxFrames = 3600

-- Script text -> array of per-frame input sets; nil and a reason when it cannot be read.
function dojo.f_parseScript(src)
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
					-- Case-sensitive: directions U D F B, buttons a b c x y z s d w.
					if not t_scriptValid[k] then
						return nil, 'unknown input "' .. k .. '" in "' .. tok .. '"'
					end
					set[k] = true
				end
			end
			for _ = 1, n, 1 do
				frames[#frames + 1] = set
				if #frames > dojo.scriptMaxFrames then
					return nil, 'longer than ' .. dojo.scriptMaxFrames .. ' frames'
				end
			end
		end
	end
	if #frames == 0 then
		return nil, 'empty'
	end
	return frames
end

-- One running script per side: dojo.scripts[1] the demo, [2] the dummy's.
dojo.scripts = {}

-- Map names are case-insensitive, so directions avoid colliding with the d and b buttons.
dojo.t_scriptMapName = {U = 'Up', D = 'Down', F = 'Fwd', B = 'Back'}

local function f_setScriptMaps(pn, set)
	player(pn)
	mapSet('_iksys_dojoScript', set ~= nil and 1 or 0)
	for _, k in ipairs(dojo.t_scriptInputs) do
		mapSet('_iksys_dojoIn' .. (dojo.t_scriptMapName[k] or k), (set ~= nil and set[k]) and 1 or 0)
	end
	player(1)
end

local function f_idleFrame(set)
	return next(set) == nil
end

-- distance: a looping dummy script's _iksys_dojoDistance. The dummy keeps that distance on the script's idle
-- frames; an action (the first input frame after idle) found out of place holds the script, and once the
-- dummy is back in place the script starts over from its first frame.
function dojo.f_startScript(pn, frames, loop, delay, distance)
	local s = {frames = frames, pos = 1, loop = loop, delay = delay or 0, wait = 0, distance = distance}
	if distance ~= nil then
		s.actionStart = {}
		for i = 1, #frames, 1 do
			if not f_idleFrame(frames[i]) and (i == 1 or f_idleFrame(frames[i - 1])) then
				s.actionStart[i] = true
			end
		end
	end
	dojo.scripts[pn] = s
end

-- Distance keeping on or off for a gated script's dummy; off also ends any walk in progress.
local function f_scriptWalk(pn, s, on)
	player(pn)
	mapSet('_iksys_dojoDistance', on and s.distance or 0)
	if not on then
		mapSet('_iksys_dojoDirection', 0)
	end
	player(1)
	s.walking = on
end

-- Whether the dummy is where a gated script's action expects it. Only the cooperative dummy keeps
-- distance (dojo.zss), so AI and manual control are never held.
local function f_scriptInPlace(pn)
	player(pn)
	local ok = map('_iksys_dojoDummyControl') ~= 0 or map('_iksys_dojoInPlace') ~= 0
	player(1)
	return ok
end

function dojo.f_stopScript(pn)
	local s = dojo.scripts[pn]
	if s ~= nil then
		dojo.scripts[pn] = nil
		f_setScriptMaps(pn, nil)
		-- Stopped mid walk: the walk was the script's, so it ends with it.
		if s.walking then
			f_scriptWalk(pn, s, false)
		end
	end
end

-- One frame of every running script. Returns nothing; a finished non-looping script stops itself.
function dojo.f_scriptTick()
	for pn = 1, 2, 1 do
		local s = dojo.scripts[pn]
		if s ~= nil then
			local gated = s.distance ~= nil
			if pn == 2 and dojo.draw ~= nil and dojo.draw.fade > 0 then
				-- A reset fade repositions both sides: press nothing through it, then start over from the top.
				s.pos, s.wait, s.holding = 1, 0, false
				if gated then f_scriptWalk(pn, s, false) end
				f_setScriptMaps(pn, {})
			elseif s.holding then
				-- Walking back into place; the script starts over once the dummy gets there.
				f_scriptWalk(pn, s, true)
				f_setScriptMaps(pn, {})
				if f_scriptInPlace(pn) then
					s.pos, s.holding = 1, false
				end
			elseif s.wait > 0 then
				s.wait = s.wait - 1
				if gated then f_scriptWalk(pn, s, true) end
				f_setScriptMaps(pn, {})
			elseif s.pos > #s.frames then
				if s.loop then
					s.pos, s.wait = 1, s.delay
					if gated then f_scriptWalk(pn, s, true) end
					f_setScriptMaps(pn, {})
				else
					dojo.f_stopScript(pn)
					if pn == 1 then
						dojo.f_demoScriptDone()
					end
				end
			elseif gated and s.actionStart[s.pos] and not f_scriptInPlace(pn) then
				-- Out of place: hold the script until the dummy is back, then run it from the top.
				s.holding = true
				f_scriptWalk(pn, s, true)
				f_setScriptMaps(pn, {})
			else
				if gated then f_scriptWalk(pn, s, f_idleFrame(s.frames[s.pos])) end
				f_setScriptMaps(pn, s.frames[s.pos])
				s.pos = s.pos + 1
			end
		end
	end
end

-- Switch off the dummy's own movement and jam so it can't fight a script (guard stays).
local function f_quietDummy()
	player(2)
	mapSet('_iksys_dojoDummyMode', 0)
	mapSet('_iksys_dojoButtonJam', 0)
	mapSet('_iksys_dojoDistance', 0)
	player(1)
end

-- The dummy's script runs while its lesson is accepting input.
function dojo.f_startDummyScript(index)
	dojo.f_stopScript(2)
	-- A dummy take is the author driving the dummy: no script, and none of its own moves.
	if dojo.rec ~= nil and dojo.rec.pn == 2 then
		f_quietDummy()
		return
	end
	local lesson = dojo.data.lessons[index]
	if lesson == nil or lesson.dummyscript == '' then
		return
	end
	if lesson.dummyframes == nil then
		local frames, why = dojo.f_parseScript(lesson.dummyscript)
		if frames == nil then
			print('Dojo: "' .. lesson.name .. '" has an unreadable dummyscript (' .. why .. ').')
			lesson.dummyscript = ''
			return
		end
		lesson.dummyframes = frames
	end
	f_quietDummy()
	-- A looping script with a dummypos distance acts from that distance, not wherever the player has pushed or left the dummy.
	local distance = lesson.dummyscriptloop and dojo.t_dummyDistance[lesson.dummypos] or nil
	dojo.f_startScript(2, lesson.dummyframes, lesson.dummyscriptloop, lesson.dummyscriptdelay, distance)
end

----------------------------------------------------------------
-- Demonstrations
----------------------------------------------------------------
-- Demo: restart, point P1 at an empty slot, play demoscript; nothing recorded, done/cancel skips.
dojo.demoSlot = 12 -- MaxPlayerNo; nobody's keys or pad are configured on it in practice

function dojo.f_demoActive()
	return dojo.demo ~= nil
end

function dojo.f_hasDemo(index)
	local lesson = dojo.data ~= nil and dojo.data.lessons[index] or nil
	return lesson ~= nil and lesson.demoscript ~= ''
end

-- The shield: P1's character reads the empty demo slot, so nothing the player presses reaches it. The
-- UI reads controllers through the same remap, so a spare controller with no character on it (the
-- watcher) is pointed at P1's own input instead: the player's presses are still seen, getInput(-1)
-- included, without ever driving the demo.
dojo.t_watchKeys = {'a', 'b', 'c', 'x', 'y', 'z', 'd', 'w'}
-- Frames after the watcher is pointed at P1 before its buttons are trusted.
dojo.shieldSettle = 4

function dojo.f_shieldOn()
	local ok, orig = pcall(getRemapInput, 1)
	if dojo.shield ~= nil then
		if ok and orig == dojo.demoSlot then
			return
		end
		-- The remap was reset behind the shield's back (a new match): start it over.
		dojo.shield = nil
	end
	local sh = {remap = ok and orig or 1, released = false, settle = dojo.shieldSettle}
	pcall(remapInput, 1, dojo.demoSlot)
	-- Highest controller past P2 with no character on it.
	for w = tonumber(gameOption('Config.Players')) or 0, 3, -1 do
		if not player(w) then
			local okw, wr = pcall(getRemapInput, w)
			if okw and pcall(remapInput, w, sh.remap) then
				sh.watcher, sh.watcherRemap = w, wr
				break
			end
		end
	end
	player(1)
	if sh.watcher == nil and not dojo.watcherWarned then
		dojo.watcherWarned = true
		print('Dojo: no spare controller to read P1 through during a demo (raise Players in config.ini to 3 or more).')
	end
	dojo.shield = sh
end

function dojo.f_shieldOff()
	local sh = dojo.shield
	if sh == nil then
		return
	end
	dojo.shield = nil
	pcall(remapInput, 1, sh.remap)
	if sh.watcher ~= nil then
		pcall(remapInput, sh.watcher, sh.watcherRemap)
	end
end

-- Whether P1 is holding any of the watched buttons, read through the watcher.
function dojo.f_shieldHeld()
	local sh = dojo.shield
	if sh == nil or sh.watcher == nil then
		return false
	end
	local ok, t = pcall(getInputTime, sh.watcher, dojo.t_watchKeys)
	return ok and type(t) == 'number' and t > 0
end

-- A fresh press of a watched button: one that started after the shield went up, never one carried
-- in (the press that closed the pages, or the one that ended the last demo).
function dojo.f_shieldPressed()
	local sh = dojo.shield
	if sh == nil then
		return false
	end
	local held = dojo.f_shieldHeld()
	-- The watcher's buffer only picks P1 up on its next step, so for its first frames a button still
	-- held from the pages reads as let go. Nothing is a release, or a press, until it has caught up.
	if sh.settle > 0 then
		sh.settle = sh.settle - 1
		sh.released = false
		return false
	end
	local pressed = held and sh.released
	sh.released = not held
	return pressed
end

-- Every frame: a shield kept up past its demo (demonstrations-only, between lessons) stays up through
-- the fade into the next lesson, and comes down only once something that holds the character still
-- needs P1's input (the pages or the lesson list) and the press that moved on has been let go. A
-- lesson that goes straight to its demo takes the shield over without it ever coming down.
function dojo.f_shieldTick()
	if dojo.shield == nil then
		return
	end
	-- The buttons that drive the pause menu are its own: one still held as it closes isn't a fresh press.
	if paused() then
		dojo.shield.released = false
	end
	if dojo.f_demoActive() or dojo.f_shieldHeld() then
		return
	end
	if not dojo.f_demoOnly() or dojo.f_pagesOpen() or (dojo.select ~= nil and dojo.select.open) then
		dojo.f_shieldOff()
	end
end

-- inPlace skips the restart when the pair are already in their start positions.
function dojo.f_startDemo(index, inPlace)
	local lesson = dojo.data.lessons[index]
	if lesson.demoframes == nil then
		local frames, why = dojo.f_parseScript(lesson.demoscript)
		if frames == nil then
			print('Dojo: "' .. lesson.name .. '" has an unreadable demoscript (' .. why .. ').')
			lesson.demoscript = ''
			return false
		end
		lesson.demoframes = frames
	end
	if not inPlace then
		-- Ends any demo already running, handing its remap back, before this one takes P1.
		dojo.f_gotoLesson(index, false, true)
	else
		-- No fade, but the lesson is set up again so the dummy starts over with the demo (f_drawer).
		if dojo.f_pagesOpen() then
			dojo.f_closePages()
		end
		dojo.data.lessons[index].active = false
		dojo.data.active = false
	end
	-- P1's own input goes for the whole demo, fade and wait included.
	dojo.f_shieldOn()
	-- The dummy goes quiet until the demo starts: whatever it was doing would otherwise carry on through
	-- the fade, and its actions would start out of step with the demo script.
	dojo.f_stopScript(2)
	f_quietDummy()
	player(2)
	mapSet('_iksys_dojoDirection', 0)
	player(1)
	lesson.pagesSeen = true
	dojo.demo = {lesson = index, phase = 'waiting', tail = 0, wait = 0}
	if dojo.data ~= nil then
		dojo.data.demoOnlyPlayed = true
	end
	return true
end

-- Called every frame from the match loop while a demo is on.
function dojo.f_demoTick()
	local dm = dojo.demo
	if dm.phase == 'waiting' then
		-- for the restart's fade and reposition to finish; f_drawer starts it (dojo.f_demoBegin)
		if dojo.draw.fade == 0 and not paused() then
			dm.wait = dm.wait + 1
		end
	elseif dm.phase == 'tail' then
		-- let the last move finish before handing back
		dm.tail = dm.tail - 1
		if dm.tail <= 0 then
			if dojo.f_demoOnly() then
				-- demonstrations-only: round again until the player moves on
				dojo.f_startDemo(dm.lesson)
			else
				dojo.f_endDemo(true)
			end
			return
		end
	end
	local sec = dojo.f_selectSection()
	if dojo.f_demoOnly() then
		-- Any button (a b c x y z d w), at any point of the demo, moves on. It is read through the
		-- watcher, never the character, and needs a fresh press.
		if dojo.f_shieldPressed() then
			if sec ~= nil then
				sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			end
			dojo.f_demoOnlyNext(dm.lesson)
			return
		end
	elseif sec ~= nil and dm.phase ~= 'waiting' then
		-- Raw UI input: P1's own command input is remapped away for the demo.
		local held = getInput(-1, sec.menu.done.key) or getInput(-1, sec.menu.cancel.key)
		if held and dm.released then
			dojo.f_endDemo(true)
			return
		end
		if not held then
			dm.released = true
		end
	end
end

-- Most frames a waiting demo holds the lesson's start for the pair to settle, so neither side is still
-- mid-move when the demo and the dummy begin.
dojo.demoSettleMax = 120

-- Whether the lesson may start: always, unless a demo is waiting for both sides to stand idle.
function dojo.f_demoReady()
	local dm = dojo.demo
	if dm == nil or dm.phase ~= 'waiting' then
		return true
	end
	if dm.wait >= dojo.demoSettleMax then
		return true
	end
	player(2)
	local idle = stateNo() == 0
	player(1)
	return idle and stateNo() == 0
end

-- Called by f_drawer on the frame the lesson starts, after the dummy's setup and script.
function dojo.f_demoBegin()
	local dm = dojo.demo
	if dm == nil or dm.phase ~= 'waiting' then
		return
	end
	dojo.f_startScript(1, dojo.data.lessons[dm.lesson].demoframes, false, 0)
	dm.phase = 'playing'
end

function dojo.f_demoScriptDone()
	if dojo.demo ~= nil then
		dojo.demo.phase = 'tail'
		dojo.demo.tail = 60
	end
end

-- restart: start the lesson over for the player (false when the match is being torn down).
-- keepShield: leave P1 shielded (dojo.f_shieldTick lets go once the buttons are up).
function dojo.f_endDemo(restart, keepShield)
	if not keepShield then
		dojo.f_shieldOff()
	end
	local dm = dojo.demo
	if dm == nil then
		return
	end
	dojo.demo = nil
	dojo.f_stopScript(1)
	if restart and dojo.data ~= nil and dojo.data.lessons[dm.lesson] ~= nil then
		dojo.f_gotoLesson(dm.lesson, false, true)
		dojo.data.lessons[dm.lesson].pagesSeen = true
	end
end

-- Whether to put "watch the demo" in front of the player: lesson.demoafter failures and counting.
function dojo.f_demoOffered(lesson)
	return lesson.demoscript ~= '' and (lesson.demoafter or 0) > 0 and (lesson.fails or 0) >= lesson.demoafter
end

----------------------------------------------------------------
-- Recording a demo (authoring aid)
----------------------------------------------------------------
-- RecordDemo: pause menu Record Demo / Dummy; the take prints and saves a script line to save/dojo_demo.txt.
do
	local v = tostring(dojo.ini.Config.RecordDemo or ''):lower()
	dojo.recordEnabled = v == 'true' or v == '1' or v == 'yes'
end
dojo.recordPath = 'save/dojo_demo.txt'

----------------------------------------------------------------
-- Demonstrations only
----------------------------------------------------------------
-- TutorialDemonstrationsOnly: tutorial tracks show pages then a looping demo, controller off; nothing cleared.
do
	local v = tostring(dojo.ini.Config.TutorialDemonstrationsOnly or ''):lower()
	dojo.demoOnlyEnabled = v == 'true' or v == '1' or v == 'yes'
end

function dojo.f_demoOnly()
	return dojo.demoOnlyEnabled and dojo.profile ~= nil and dojo.profile.id == 'tutorial'
end

-- Whether a lesson is offered at all: in demonstrations-only, only one with a demo to show.
local t_demoOnlyWarned = {}
function dojo.f_lessonOffered(lesson)
	if not dojo.f_demoOnly() or lesson.demoscript ~= '' then
		return true
	end
	if not t_demoOnlyWarned[lesson] then
		t_demoOnlyWarned[lesson] = true
		print('Dojo: "' .. tostring(lesson.name) .. '" has no demoscript, so TutorialDemonstrationsOnly leaves it out.')
	end
	return false
end

-- A button during a demonstrations-only demo: on to the next lesson, or the list after the last one.
-- P1 stays shielded until the press is let go, so it never reaches the character.
function dojo.f_demoOnlyNext(index)
	dojo.f_endDemo(false, true)
	if index < #dojo.data.lessons then
		dojo.f_gotoLesson(index + 1, false, true)
	else
		dojo.f_openSelect()
	end
end

-- Start the demo whenever a lesson is up without pages or demo, so the player never gets control.
function dojo.f_demoOnlyGuard()
	if not dojo.f_demoOnly() or dojo.f_demoActive() or dojo.f_pagesOpen() then
		return
	end
	local d = dojo.data
	if not d.active or dojo.draw.success > 0 or dojo.draw.fade > 0 then
		return
	end
	local index = d.currentlesson
	if d.lessons[index] == nil or not dojo.f_hasDemo(index) then
		return
	end
	dojo.f_startDemo(index, not d.demoOnlyPlayed)
end

-- A frame set as script text: inputs in t_scriptInputs order, _ for none.
local function f_setText(set)
	local k = {}
	for _, n in ipairs(dojo.t_scriptInputs) do
		if set[n] then k[#k + 1] = n end
	end
	return #k > 0 and table.concat(k, '+') or '_'
end

-- Frames -> "n:inputs, ..." with runs of identical frames merged; the inverse of f_parseScript.
function dojo.f_scriptText(frames)
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

function dojo.f_recording()
	return dojo.rec ~= nil
end

-- pn 1 records P1, pn 2 the dummy; a dummy take swaps controllers until it ends.
function dojo.f_startRecording(pn)
	pn = pn or 1
	dojo.f_cancelRecording()
	-- 'armed' until every button is let go, so the press that closed the menu is not recorded
	dojo.rec = {frames = {}, phase = 'armed', pn = pn}
	if pn == 2 then
		local ok1, r1 = pcall(getRemapInput, 1)
		local ok2, r2 = pcall(getRemapInput, 2)
		if ok1 and ok2 then
			dojo.rec.remap = {r1, r2}
			pcall(remapInput, 1, r2)
			pcall(remapInput, 2, r1)
		end
		dojo.f_stopScript(2)
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
function dojo.f_cancelRecording()
	local rec = dojo.rec
	dojo.rec = nil
	f_releaseRecording(rec)
end

local function f_heldNow(pn)
	player(pn)
	local set, any = {}, false
	for _, k in ipairs(dojo.t_scriptInputs) do
		local ok, t = pcall(inputTime, k)
		if ok and type(t) == 'number' and t > 0 then
			set[k], any = true, true
		end
	end
	player(1)
	return set, any
end

-- restart: after a dummy take, restart the lesson to restore the dummy's settings.
function dojo.f_finishRecording(restart)
	local rec = dojo.rec
	dojo.rec = nil
	if rec == nil then
		return
	end
	f_releaseRecording(rec)
	if rec.pn == 2 and restart ~= false and dojo.data ~= nil and #dojo.data.lessons > 0 then
		local ct = math.min(dojo.data.currentlesson, #dojo.data.lessons)
		dojo.f_gotoLesson(ct, false, true)
		dojo.data.lessons[ct].pagesSeen = true
	end
	local f = rec.frames
	-- Trim empty leading/trailing frames and the start press that ended the take.
	while #f > 0 and (next(f[#f]) == nil or (f[#f].s and f_setText(f[#f]) == 's')) do
		table.remove(f)
	end
	if #f == 0 then
		print('Dojo: Record Demo stopped with nothing recorded.')
		return
	end
	f[#f + 1] = {}
	local line = (rec.pn == 2 and 'dummyscript = ' or 'demoscript = ') .. dojo.f_scriptText(f)
	print('Dojo: recorded ' .. #f .. ' frames:\n' .. line)
	local ok = pcall(main.f_fileWrite, dojo.recordPath, line .. '\n')
	if ok then
		print('Dojo: also written to ' .. dojo.recordPath .. '.')
	end
	dojo.lastRecording = line
end

-- Every frame of the match loop, paused or not: pausing is what ends a take.
function dojo.f_recordTick()
	local rec = dojo.rec
	if rec == nil then
		return
	end
	if paused() then
		-- Past the arming pause, any pause ends the take.
		if rec.phase ~= 'armed' then
			dojo.f_finishRecording()
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
		if #rec.frames >= dojo.scriptMaxFrames then
			dojo.f_finishRecording()
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

-- Legacy trials* pause itemnames, renamed to the shared tutorial* ones before menus build.
dojo.t_legacyPauseItems = {
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
	local map = dojo.t_legacyPauseItems
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
		-- Keep a row declared under both spellings once (spacers excepted).
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
f_renameLegacyPause(dojo.f_pauseSection(dojo.t_profiles.trials))

-- Pause option value labels from the profile's section; rebuilt per profile.
function dojo.f_menuValueNames()
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
-- The row reads "Cleared" after clearing, until the menu resets.
menu.t_valuename.tutorialclearprogress = {
	{itemname = "ready", displayname = pmv.tutorialclearprogress_ready or ""},
	{itemname = "cleared", displayname = pmv.tutorialclearprogress_cleared or "Cleared"}
}
end
dojo.f_menuValueNames()
-- Jump to a lesson and leave the pause menu; the fade repositions the pair.
function dojo.f_gotoLesson(index, keepTimer, noMenu)
	if dojo.data == nil or not dojo.data.initialized or dojo.data.lessons[index] == nil then
		return true
	end
	-- Next / Previous can't enter a locked lesson; a speedrun is exempt.
	if not keepTimer and dojo.f_isLocked(index) then
		return true
	end
	-- Going anywhere else ends a demo first, so the player always gets their controller back.
	-- Demonstrations-only keeps P1 shielded: the next demo takes it over, or f_shieldTick lets go.
	if dojo.f_demoActive() then
		dojo.f_endDemo(false, dojo.f_demoOnly())
	end
	-- Pages left up would own every frame (f_drawer never runs, so the lesson never starts) and keep the
	-- select hold on. The new lesson opens its own pages once it starts, unless a demo has marked them seen.
	if dojo.f_pagesOpen() then
		dojo.f_closePages()
	end
	dojo.f_stopScript(2)
	-- Picking a Lesson is what dismisses the select view, wherever it was picked from.
	if dojo.select ~= nil and dojo.select.open then
		dojo.select.open = false
		dojo.f_menuHold(false)
	end
	dojo.f_spendState()
	dojo.data.currentlessonstep = 1
	dojo.data.currentlessonmicrostep = 1
	dojo.data.comboCounter = 0
	dojo.data.currentlesson = index
	dojo.data.successlesson = nil
	-- Cancel any banner still up so it can't complete the new lesson.
	dojo.draw.success = 0
	dojo.data.lessons[index].complete = false
	dojo.data.lessons[index].active = false
	-- Entering a lesson starts its repetitions over and shows its pages again.
	dojo.data.lessons[index].repsdone = 0
	dojo.data.lessons[index].pagesSeen = false
	dojo.data.active = false
	dojo.data.allclear = false
	if keepTimer then
		dojo.data.displaytimers.totaltimer = opts.TotalTimer ~= false
	else
		dojo.data.displaytimers.totaltimer = false
		dojo.data.runValid = false
	end
	dojo.f_armTimers(index, keepTimer)
	dojo.draw.fadein = dojo.ui.fadein_time
	dojo.draw.fadeout = dojo.ui.fadeout_time
	dojo.draw.fade = dojo.draw.fadein + dojo.draw.fadeout
	dojo.draw.fadetriggered = true
	if not noMenu then
		menu.currentMenu[1] = menu.currentMenu[2]
		menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
	end
	return false
end

menu.t_itemname['tutorialadvancement'] = function(t, item, cursorPosY, moveTxt, sec)
	if dojo.f_speedrunEnabled() then
		-- Repeat would stall a run, so a speedrun holds Advancement at Auto-Advance.
		return true
	end
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if dojo.data ~= nil then
			if value == "autoadvance" then
				dojo.data.autoadvance = true
			else
				dojo.data.autoadvance = false
			end
		end
		dojo.f_savePref('Advancement', value)
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
			dojo.ui.layout = "vertical"
		else
			dojo.ui.layout = "horizontal"
		end
		dojo.f_savePref('Layout', dojo.ui.layout)
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
			dojo.ui.resetonsuccess = true
		else
			dojo.ui.resetonsuccess = false
		end
		dojo.f_savePref('ResetOnSuccess', dojo.ui.resetonsuccess)
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
		dojo.f_savePref('Hints', value == 'show')
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
	if getInput(-1, sec.menu.done.key) and dojo.data ~= nil and dojo.data.initialized then
		-- End any demo so the pages get the controller back: P1 is remapped away for a demo, and the
		-- pages read P1's input. Demonstrations-only restarts its demo on close; otherwise the lesson
		-- starts over for the player once the pages close.
		local l = dojo.data.lessons[dojo.data.currentlesson]
		if dojo.f_demoActive() and l ~= nil and type(l.pages) == 'table' and #l.pages > 0 then
			dojo.f_endDemo(not dojo.f_demoOnly())
		end
		if dojo.f_openPages(dojo.data.currentlesson) then
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
	if getInput(-1, sec.menu.done.key) and dojo.data ~= nil and dojo.data.initialized then
		local ct_ = math.min(dojo.data.currentlesson, #dojo.data.lessons)
		if not dojo.f_speedrunEnabled() and not dojo.f_demoActive() and dojo.f_hasDemo(ct_) and dojo.f_startDemo(ct_) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			f_leavePause()
		else
			sndPlay(motif.Snd, sec.cancel.snd[1], sec.cancel.snd[2])
		end
	end
	return true
end

-- Record Demo: see dojo.f_recordTick. Not offered unless RecordDemo is on.
menu.t_itemname['tutorialrecord'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and dojo.recordEnabled and dojo.data ~= nil and not dojo.f_demoActive() then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		dojo.f_startRecording(1)
		f_leavePause()
	end
	return true
end

-- Record Dummy: the same for P2, played on the author's controller; see dojo.f_startRecording.
menu.t_itemname['tutorialrecorddummy'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and dojo.recordEnabled and dojo.data ~= nil and not dojo.f_demoActive() then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		dojo.f_startRecording(2)
		f_leavePause()
	end
	return true
end

-- Restart Lesson: back to its first step and its start positions, repetitions and pages included.
menu.t_itemname['tutorialrestart'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and dojo.data ~= nil and #dojo.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return dojo.f_gotoLesson(math.min(dojo.data.currentlesson, #dojo.data.lessons))
	end
	return true
end

menu.t_itemname['tutorialtextboxes'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "show" then
			dojo.ui.textbox_visible = true
		else
			dojo.ui.textbox_visible = false
		end
		dojo.ui.textbox.visible = dojo.ui.textbox_visible
		dojo.f_savePref('Textboxes', value)
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
	-- No speedrun across P1 changes or in demonstrations-only.
	if dojo.f_speedrunSpansChars() or dojo.f_demoOnly() then
		return true
	end
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		menu.tutorialspeedrun = value == "enabled" and 1 or 2
		dojo.f_applySpeedrun()
		for _, v in ipairs(menu.t_vardisplayPointers) do
			if v.itemname == 'tutorialspeedrun' then
				v.vardisplay = menu.f_vardisplay('tutorialspeedrun')
			end
		end
		if value == "enabled" then
			dojo.f_startSpeedrun()
			-- Leave the menu the way picking a Lesson does: the run starts now.
			menu.currentMenu[1] = menu.currentMenu[2]
			menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
			return false
		end
	end
	return true
end
-- On/Off plus the character's best run, if any.
local function f_speedrunVardisplay()
	local label = menu.t_valuename.tutorialspeedrun[menu.tutorialspeedrun or 2].displayname
	local rec = dojo.f_speedrunRecord()
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
			dojo.f_clearProgress()
			return true
		end,
	},
	{
		row = 'tutorialclearcharprogress',
		confirm = 'tutorialclearcharconfirm',
		yes = 'Yes, Erase This Character',
		no = 'No',
		-- P1's character; nothing to acknowledge when it can't be resolved.
		run = function()
			return dojo.f_clearCharProgress()
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
		-- Stay on the row so "Cleared" is visible.
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

-- Wrap menu.f_init so opening the pause menu refilters its root items.
local f_menuInit = menu.f_init
function menu.f_init(...)
	if dojo.f_inMode() then
		dojo.f_applySpeedrun()
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
	if getInput(-1, sec.menu.done.key) and dojo.data ~= nil and #dojo.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return dojo.f_gotoLesson(dojo.data.currentlesson % #dojo.data.lessons + 1)
	end
	return true
end

menu.t_itemname['tutorialprevious'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and dojo.data ~= nil and #dojo.data.lessons > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return dojo.f_gotoLesson((dojo.data.currentlesson - 2) % #dojo.data.lessons + 1)
	end
	return true
end

local t_prefItems = {
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

function menu.f_dojoReset()
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		menu.tutorialadvancement = 1
	else
		menu.tutorialadvancement = 2
	end
	if dojo.ui.resetonsuccess == true then
		menu.tutorialresetonsuccess = 1
	else
		menu.tutorialresetonsuccess = 2
	end
	if dojo.ui.layout == "vertical" then
		menu.tutoriallayout = 1
	else
		menu.tutoriallayout = 2
	end
	if (opts.Textboxes ~= nil and tostring(opts.Textboxes):lower() ~= "hide")
		or (opts.Textboxes == nil and dojo.ui.textbox_visible == true) then
		menu.tutorialtextboxes = 1
	else
		menu.tutorialtextboxes = 2
	end
	menu.tutorialhints = dojo.f_hintsOn() and 1 or 2
	-- "Cleared" doesn't carry into the next match.
	menu.tutorialclearprogress = 1
	menu.tutorialclearcharprogress = 1
	for _, v in ipairs(menu.t_vardisplayPointers) do
		if t_prefItems[v.itemname] then
			v.vardisplay = menu.f_vardisplay(v.itemname)
		end
	end
	dojo.f_applySpeedrun()
	player(2)
	setAILevel(0)
	mapSet('_iksys_dojoDummyControl', 0)
	mapSet('_iksys_dojoDummyMode', 0)
	mapSet('_iksys_dojoGuardMode', 0)
	mapSet('_iksys_dojoFallRecovery', 0)
	mapSet('_iksys_dojoDistance', 0)
	mapSet('_iksys_dojoButtonJam', 0)
	mapSet('_iksys_dojoReposition', 0)
	mapSet('_iksys_dojoSetLife', lifeMax())
	player(1)
	mapSet('_iksys_dojoSetLife', lifeMax())
end

--;===========================================================
--; dojo.lua
--;===========================================================

--;===========================================================
--; Lesson files
--;===========================================================
-- Lesson files: [Lesson, name] (or [TrialDef, name]) sections; trial* keys alias lesson*.

-- Language-suffixed keys, resolved at file end.
local t_multilingual = {
	['lesson.textbox'] = true,
	['lesson.hint'] = true,
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
local t_stepNumLists = {hitcount = true, validfortickcount = true}
local t_stepBoolLists = {isthrow = true, iscounterhit = true, ishelper = true, isproj = true, isguarded = true}
local t_guardValues = {any = true, high = true, low = true, air = true}

-- Chapter id: name folded to a dojo.def key; structural names get a trailing underscore.
local t_reservedCats = {all = true, other = true, text = true, bg = true, active = true, selected = true,
	overlay = true, locked = true, value = true, spacing = true, offset = true}
function dojo.f_chapterId(name)
	local id = tostring(name or ''):lower():gsub('[^%w]+', '_'):gsub('^_+', ''):gsub('_+$', '')
	if id ~= '' and (t_reservedCats[id] or dojo.t_difficultyIndex[id]) then
		id = id .. '_'
	end
	return id
end
dojo.t_difficultyIndex = {}
for _, d in ipairs(dojo.t_difficulty) do dojo.t_difficultyIndex[d] = true end

-- Display names for chapter ids, filled as files are read; the select header looks names up here.
dojo.chapterNames = dojo.chapterNames or {}

local function f_newLesson(name)
	return {
		name = name,
		difficulty = "",
		dummymode = "stand",
		guardmode = "none",
		buttonjam = "none",
		buttondelay = nil, -- resolved per mode when the Lesson starts
		jumpdelay = dojo.jumpDelayDefault,
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
		showforchars = nil, -- set of lowercase names / folders / def paths; nil = everyone
		playerchar = nil, -- game-wide lessons: P1 forced in the Game Tutorial (select.def spelling)
		dummychar = nil,  -- game-wide lessons: P2 forced in the Game Tutorial (select.def spelling)
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
		glyphline = {
			vertical = {glyph = {}, pos = {}, width = {}, alignOffset = {}, lengthOffset = {}, scale = {}},
			horizontal = {glyph = {}, pos = {}, width = {}, alignOffset = {}, lengthOffset = {}, scale = {}},
		},
	}
end

-- Fill microstep defaults once the step is read; the count comes from the id lists.
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

-- Parse a lesson file; returns {lessons} or nil. Gating comes from config.ini's [Gating], by source.
function dojo.f_parseFile(path, track, label)
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

	local out = {lessons = {}}
	local section = nil      -- 'lesson' | 'unknown'
	local lesson = nil       -- the lesson being read
	local ml = nil           -- multilingual candidates for the current lesson: ml[key][suffix]
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
					warn('"' .. lesson.name .. '" has no step.' .. n .. '; the steps after it are numbered down.')
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
					local frames, why = dojo.f_parseScript(lesson[f])
					if frames == nil then
						warn('"' .. lesson.name .. '" has an unreadable ' .. f .. ' (' .. why .. '); it is ignored.')
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
		end
		section, lesson, ml, steps, pageml = nil, nil, nil, nil, nil
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
					name = (dojo.profile.id == 'trials' and 'Trial ' or 'Lesson ') .. tostring(#out.lessons + 1)
				end
				lesson = f_newLesson(name)
			elseif kind == 'chapter' then
				section = 'unknown'
				warn('[Chapter] sections are no longer read (line ' .. lineno .. '); a chapter is named by chapter = on its entries.')
			elseif kind == 'tutorial' then
				section = 'unknown'
				warn('[Tutorial] sections are no longer read (line ' .. lineno .. '); gating is set in config.ini [Gating].')
			else
				section = 'unknown'
				warn('unknown section [' .. head .. '] on line ' .. lineno .. '; its keys are ignored.')
			end
		elseif line:find('=') then
			local key = line:match('^%s*(.-)%s*=') :lower()
			local raw = line:match('=%s*(.-)%s*$') or ''
			local val = raw:lower()
			-- Short form (hint, page.1.text, step.1.stateno) and the old prefixed ones read the same; the
			-- parser below works on the prefixed names, so short keys are expanded here.
			local written = key
			key = key:gsub('^trialstep%.', 'lessonstep.'):gsub('^trial%.', 'lesson.'):gsub('^step%.', 'lessonstep.')
			if section == 'lesson' and not key:find('^lesson%.') and not key:find('^lessonstep%.') then
				key = 'lesson.' .. key
			end
			if section == 'lesson' then
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
								warn('"' .. lesson.name .. '" step.' .. sn .. '.guard has an unknown value (' .. g .. '); expected any, high, low or air.')
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
						warn('unknown key ' .. written .. ' on line ' .. lineno .. '.')
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
							warn('"' .. lesson.name .. '" has an invalid ' .. written .. ' (' .. val .. '). Expected group, number.')
						end
					elseif pfield == 'portrait.anim' then
						if tonumber(val) ~= nil then
							pg.portrait.anim = tonumber(val)
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an invalid ' .. written .. ' (' .. val .. '). Expected an action number.')
						end
					elseif pfield == 'portrait.source' then
						local v = val:gsub('"', '')
						if v == 'system' or v == 'char' then
							pg.portrait.source = v
						elseif v ~= '' then
							warn('"' .. lesson.name .. '" has an unknown ' .. written .. ' (' .. v .. '); expected system or char.')
						end
					else
						warn('unknown key ' .. written .. ' on line ' .. lineno .. '.')
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
						warn('unknown key ' .. written .. ' on line ' .. lineno .. '.')
					elseif f == 'difficulty' then
						lesson.difficulty = ''
						if dojo.t_difficultyIndex[val] then
							lesson.difficulty = val
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an unrecognised difficulty (' .. val
								.. '). Expected Beginner, Intermediate, Advanced or Expert.')
						end
					elseif f == 'chapter' then
						lesson.chapter = dojo.f_chapterId(raw)
						if lesson.chapter ~= '' and dojo.chapterNames[lesson.chapter] == nil then
							dojo.chapterNames[lesson.chapter] = raw
						end
					elseif f == 'showforchars' or f == 'chars' then -- chars: the old name
						lesson.showforchars = {}
						for _, c in ipairs(main.f_strsplit(',', val)) do
							c = c:gsub('\\', '/'):match('^%s*(.-)%s*$')
							if c ~= '' then lesson.showforchars[c] = true end
						end
					elseif f == 'playerchar' then
						-- Game-wide lessons only: in a character's file P1 is that character already.
						if track ~= 'system' then
							warn('"' .. lesson.name .. '" sets playerchar, which only game-wide lessons take; it is ignored.')
						elseif val ~= '' then
							lesson.playerchar = raw:gsub('\\', '/'):match('^%s*(.-)%s*$')
						end
					elseif f == 'dummychar' then
						-- Game-wide lessons only, like playerchar: only the Game Tutorial can reload the match for it.
						if track ~= 'system' then
							warn('"' .. lesson.name .. '" sets dummychar, which only game-wide lessons take; it is ignored.')
						elseif val ~= '' then
							lesson.dummychar = raw:gsub('\\', '/'):match('^%s*(.-)%s*$')
						end
					elseif f == 'dummymode' then
						lesson.dummymode = val
					elseif f == 'guardmode' then
						lesson.guardmode = val
						if dojo.t_guardMode[val] == nil then
							warn('"' .. lesson.name .. '" has an unknown guardmode (' .. val .. '); expected none, auto, afterhit or random.')
						end
					elseif f == 'dummybuttonjam' then
						lesson.buttonjam = val
					elseif t_lessonCounts[f] then
						local n = tonumber(val)
						if n ~= nil and n >= 0 and n == math.floor(n) then
							lesson[t_lessonCounts[f]] = n
						elseif val ~= '' then
							warn('"' .. lesson.name .. '" has an invalid ' .. f .. ' (' .. val .. '). Expected a whole number, 0 or more.')
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
						warn('unknown key ' .. written .. ' on line ' .. lineno .. '.')
					end
				end
			end
		end
	end
	closeSection()
	-- Character files gate by the profile reading them: Trials, or Character Guides.
	local gated = dojo.f_gatingOn(track == 'system' and 'SystemTutorial'
		or (dojo.profile.id == 'trials' and 'Trials' or 'CharacterGuides'))
	for _, l in ipairs(out.lessons) do
		l.gated = gated
	end
	return out
end

--;===========================================================
--; Building and switching profiles
--;===========================================================
-- Build a profile's UI and progress, store them on it, and leave it in force.
function dojo.f_buildProfile(p)
	f_loadAssets()
	dojo.profile = p
	opts = p.opts
	local root, lx, ly = f_prepareUI(p)
	dojo.ui = root
	ui = root
	dojo.mtlcx, dojo.mtlcy = lx, ly
	f_uiMenuDefaults()
	f_uiStepDefaults()
	f_uiAnchors()
	dojo.vislcx = f_vislcx(f_screenAspect())
	dojo.anchordelta = dojo.vislcx - dojo.mtlcx
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
		menuDraw = dojo.menuDraw,
		teach = dojo.teach,
		vislcx = dojo.vislcx,
	}
	p.progress = dojo.f_loadProgress(p)
	dojo.progress = p.progress
	dojo.progressPath = p.progressPath
	dojo.dummyPath, dojo.stagePath, dojo.playerCharPath = p.dummyPath, p.stagePath, p.playerCharPath
	p.built = true
end

-- Put a built profile in force; its pause menu nodes are cached per profile.
function dojo.f_useProfile(p)
	if not p.built then
		dojo.f_buildProfile(p)
	end
	local cur = dojo.profile
	if cur ~= nil and cur.ui ~= nil then
		cur.ui.vislcx = dojo.vislcx
		cur.menuCache = {
			listTail = dojo.listTail,
			listLoop = dojo.listLoop,
			listNode = dojo.listNode,
			rootItems = dojo.rootItems,
			rootNode = dojo.rootNode,
		}
	end
	dojo.profile = p
	opts = p.opts
	dojo.ui = p.ui.root
	ui = p.ui.root
	dojo.mtlcx, dojo.mtlcy = p.ui.mtlcx, p.ui.mtlcy
	t_anchored, t_elems = p.ui.anchored, p.ui.elems
	dojo.menuDraw, dojo.teach = p.ui.menuDraw, p.ui.teach
	dojo.vislcx = p.ui.vislcx
	dojo.anchordelta = dojo.vislcx - dojo.mtlcx
	local c = p.menuCache or {}
	dojo.listTail, dojo.listLoop, dojo.listNode = c.listTail, c.listLoop, c.listNode
	dojo.rootItems, dojo.rootNode = c.rootItems, c.rootNode
	dojo.progress = p.progress
	dojo.progressPath = p.progressPath
	dojo.dummyPath, dojo.stagePath, dojo.playerCharPath = p.dummyPath, p.stagePath, p.playerCharPath
	-- Drawn with the last profile's font; rebuilt from this one's the first time it is needed.
	dojo.nodatacounter = nil
	dojo.f_menuValueNames()
end

-- Build every enabled profile.
for _, id in ipairs(dojo.t_profileOrder) do
	local p = dojo.t_profiles[id]
	if p.enabled then
		dojo.f_buildProfile(p)
	end
end

-- Character tracks: read each char def's <charKey> file; one parser handles both kinds.
for _, id in ipairs(dojo.t_profileOrder) do
	local p = dojo.t_profiles[id]
	if p.enabled then
		dojo.f_useProfile(p)
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
				local res = dojo.f_parseFile(file, 'char', tostring(c.name))
				c[p.dataField] = res ~= nil and res.lessons or {}
			end
		end
	end
end

-- System track: game-wide lesson files from [Config] SystemTutorial, tutorial tracks only.
dojo.systemLessons = {}
if dojo.t_profiles.tutorial.enabled then
	dojo.f_useProfile(dojo.t_profiles.tutorial)
	local list = dojo.ini.Config.SystemTutorial
	-- loadIni may already have split a comma list into a table.
	if type(list) == 'table' then
		list = table.concat(list, ',')
	end
	if type(list) == 'string' then
		for _, p in ipairs(main.f_strsplit(',', list)) do
			p = p:gsub('\\', '/'):match('^%s*(.-)%s*$')
			if p ~= '' then
				local res = main.f_fileExists(p) and dojo.f_parseFile(p, 'system', p) or nil
				if res == nil then
					print('Dojo: SystemTutorial file ' .. p .. ' could not be read; it is skipped.')
				else
					for _, l in ipairs(res.lessons) do
						dojo.systemLessons[#dojo.systemLessons + 1] = l
					end
				end
			end
		end
	end
end

-- Whether lesson.showforchars admits a character by name, folder or def path, lowercase.
local function f_charAdmits(lesson, charData)
	if lesson.showforchars == nil then
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
		if c ~= nil and lesson.showforchars[c] then
			return true
		end
	end
	return false
end

-- Whether a game-wide lesson belongs on this track, per lesson.showforchars; never in Trials.
local function f_systemOnTrack(lesson, charData)
	if not dojo.profile.system then
		return false
	elseif dojo.track == 'game' then
		return lesson.showforchars == nil
	elseif dojo.track == 'chars' then
		return lesson.showforchars ~= nil and type(charData) == 'table' and f_charAdmits(lesson, charData)
	end
	return type(charData) == 'table' and f_charAdmits(lesson, charData)
end

-- The character's own file for this profile, or nil.
local function f_charLessons(charData)
	if dojo.track == 'game' or type(charData) ~= 'table' then
		return nil
	end
	local t = charData[dojo.profile.dataField]
	return type(t) == 'table' and t or nil
end

-- Every lesson the track offers, game-wide first, as fresh copies.
function dojo.f_lessonsFor(charData)
	local t = {}
	for _, l in ipairs(dojo.systemLessons) do
		if f_systemOnTrack(l, charData) and dojo.f_lessonOffered(l) then
			t[#t + 1] = main.f_tableCopy(l)
		end
	end
	for _, l in ipairs(f_charLessons(charData) or {}) do
		if dojo.f_lessonOffered(l) then
			t[#t + 1] = main.f_tableCopy(l)
		end
	end
	return t
end

-- Cheaper than building the list: whether the current track has anything for a character at all.
function dojo.f_hasLessons(charData)
	for _, l in ipairs(f_charLessons(charData) or {}) do
		if dojo.f_lessonOffered(l) then
			return true
		end
	end
	for _, l in ipairs(dojo.systemLessons) do
		if f_systemOnTrack(l, charData) and dojo.f_lessonOffered(l) then
			return true
		end
	end
	return false
end

-- Game Tutorial P1: lesson.playerchar, else TutorialPlayerChar, else the pick.
function dojo.f_playerFor(lesson)
	if type(lesson) == 'table' and lesson.playerref ~= nil then
		return lesson.playerref
	end
	return dojo.playerRef or dojo.pickedRef
end

-- Game Tutorial P2: lesson.dummychar, else TutorialDummy, else the pick, else a mirror of P1.
function dojo.f_dummyFor(lesson)
	if type(lesson) == 'table' and lesson.dummyref ~= nil then
		return lesson.dummyref
	end
	return dojo.dummyRef or dojo.p2PickedRef or dojo.f_playerFor(lesson)
end

-- A Game Tutorial speedrun is one match, so it is only offered while every lesson shares a P1 and a dummy.
function dojo.f_speedrunSpansChars()
	if dojo.track ~= 'game' then
		return false
	end
	local first, firstDummy = nil, nil
	for i, l in ipairs(dojo.f_lessonsFor(nil)) do
		local p, d = dojo.f_playerFor(l), dojo.f_dummyFor(l)
		if i == 1 then
			first, firstDummy = p, d
		elseif p ~= first or d ~= firstDummy then
			return true
		end
	end
	return false
end

--;===========================================================
--; global.lua
--;===========================================================
-- Each enabled profile's game mode runs the same per-frame loop.
for _, id in ipairs(dojo.t_profileOrder) do
	local p = dojo.t_profiles[id]
	if p.enabled then
		hook.add("loop#" .. p.gamemode, "f_dojoMatchLoop", dojo.f_matchLoop)
	end
end
-- Register enabled tracks; hide disabled ones with an unlock that's never true.
for _, t in pairs(dojo.t_tracks) do
	for _, name in ipairs({t.itemname, t.legacy}) do
		if t.enabled then
			main.t_itemname[name] = t.start
		else
			main.t_unlockLua.modes[name] = 'false'
		end
	end
end
-- Put the first entry's profile in force; Trials is the default until then.
if dojo.t_profiles.trials.enabled then
	dojo.f_useProfile(dojo.t_profiles.trials)
elseif dojo.t_profiles.tutorial.enabled then
	dojo.f_useProfile(dojo.t_profiles.tutorial)
end
hook.add("start.f_selectScreen", "f_dojoSelectScreen", dojo.f_selectScreen)
-- Runs once selection settles, before the fight loads (listdisplay = select).
hook.add("start.f_selectReset", "f_dojoSpeedrunReset", function()
	dojo.f_cancelRecording()
	dojo.f_endDemo(false)
	dojo.f_resetSpeedrun()
	dojo.f_restoreSelect()
end)
-- Hand TrialsStage / TutorialStage over as an assigned stage; falls back if unloadable.
local f_setStageOrig = start.f_setStage
function start.f_setStage(num, assigned)
	if dojo.f_inMode() and dojo.stagePath ~= '' and not main.stageMenu then
		local ref = main.t_stageDef[dojo.stagePath:lower()]
		if ref == nil then
			ref = main.f_addStage(dojo.stagePath)
		end
		if ref ~= nil then
			return f_setStageOrig(ref, true)
		end
		print('Dojo: ' .. dojo.profile.stageKey .. ' (' .. dojo.stagePath .. ') could not be loaded; using the default stage instead.')
		dojo.stagePath = ''
		dojo.profile.stagePath = ''
	end
	return f_setStageOrig(num, assigned)
end

hook.add("launchFight", "f_dojoPreFightMenu", function()
	dojo.f_preFightMenu()
end)
-- Pass a pre-fight list cancel off as a VS cancel so the match drops and picks are restored.
local f_selectVersusOrig = start.f_selectVersus
function start.f_selectVersus(...)
	if dojo.backToSelect then
		dojo.backToSelect = false
		return false
	end
	return f_selectVersusOrig(...)
end

