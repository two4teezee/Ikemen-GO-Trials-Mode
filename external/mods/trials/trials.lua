-- IKEMEN GO TRIALS MODE EXTERNAL MODULE --------------------------------
-- Last tested on Ikemen GO v1.0.0-nightly-20260124 - Jan 24, 2026
-- Module developed by two4teezee
-- With contributions from:
---- Cable Dorado 2 (CD2)
-------------------------------------------------------------------------
-- This external module implements TRIALS game mode. Features full 
-- screenpack integration via config.ini, +system.def and system.def, 
-- providing the ability to create and read trials definitions for any 
-- character, and a trials menu option. Documentation on how to create 
-- trials definitions and use trials mode is in README.md.
-------------------------------------------------------------------------

--;===========================================================
--; Read Configuration Files
--;===========================================================

local modulePath = "external/mods/trials/"

local zss = gameOption("Common.States")
table.insert(zss, modulePath .. "trials.zss")
modifyGameOption("Common.States", zss)

trials = {}
trials = loadIni(modulePath .. 'system.def')

trials.configPath = modulePath .. 'config.ini'

local cfgok, cfg = pcall(loadIni, trials.configPath, false)
if not cfgok then
	print('Trials: cannot read ' .. trials.configPath .. '. Player preferences will not persist.')
end
trials.ini = cfgok and cfg or {}
if type(trials.ini.Options) ~= 'table' then trials.ini.Options = {} end
if type(trials.ini.Options.Trials) ~= 'table' then trials.ini.Options.Trials = {} end
local opts = trials.ini.Options.Trials

-- Persists one Player Preference the moment it changes.
function trials.f_savePref(key, value)
	opts[key] = value
	local ok, err = pcall(saveIni, trials.ini, trials.configPath)
	if not ok then
		print('Trials: could not write ' .. trials.configPath .. ' (' .. tostring(err) .. ').')
	end
end

motif = loadMotif()

-- The engine already loaded and owns the screenpack's sprites, sounds and fonts; reach for
-- those rather than re-parsing the files (motif.Sff / motif.Snd / motif.Fnt, see src/motif.go).
local sff = motif.Sff
local snd = motif.Snd

-- Optional module-owned assets. trials.sff holds the sprites this mode ships with; trials.air
-- holds the actions an "anim = N" in system.def refers to. Both fall back to the screenpack's,
-- so a screenpack that defines everything itself keeps working untouched.
local trialsSff = sff
if main.f_fileExists(modulePath .. 'trials.sff') then
	trialsSff = sffNew(searchFile(modulePath .. 'trials.sff', {motif.def, '', 'data/'}))
end
local trialsAnims = {}
do
	local path, animSff = modulePath .. 'trials.air', trialsSff
	if main.f_fileExists(path) then
		path = searchFile(path, {motif.def, '', 'data/'})
	else
		path, animSff = motif.def, sff
	end
	local ok, t = pcall(loadAnimTable, path, animSff)
	if ok and type(t) == 'table' then
		trialsAnims = t
	else
		print('Trials: could not read actions from ' .. tostring(path) .. '; "anim" parameters will be ignored.')
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
	x = string.find(line, char)
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

trials.trials_mode = f_buildCompatConfig(trials.trials_mode or {})

-- config.ini's [Options] override the screenpack's authored defaults, but only where the
-- player has actually set one. 
if opts.Layout ~= nil then
	trials.trials_mode.trialslayout = tostring(opts.Layout):lower()
end
if opts.ResetOnSuccess ~= nil then
	trials.trials_mode.trialsresetonsuccess = opts.ResetOnSuccess ~= false
end
if opts.Textboxes ~= nil then
	local visible = tostring(opts.Textboxes):lower() ~= 'hide'
	trials.trials_mode.textbox_visible = visible
	trials.trials_mode.textbox.visible = visible
end

-- Resolve trialslocalcoord up front. Every anim built below lives in this coordinate
-- space, and animSetLocalcoord only affects setters called *after* it, so the value has
-- to exist before the sprite data is loaded (not just once f_trialsMode starts running).
if type(trials.trials_mode.trialslocalcoord) ~= 'table' then
	trials.trials_mode.trialslocalcoord = {320, 240}
end
trials.mtlcx = tonumber(trials.trials_mode.trialslocalcoord[1]) or 320
trials.mtlcy = tonumber(trials.trials_mode.trialslocalcoord[2]) or 240
trials.trials_mode.trialslocalcoord = {trials.mtlcx, trials.mtlcy}

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

text = {}
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
	if trials.lcdx00 ~= 1 then
	if trials.mtlcx > trials.stlcx then
	if t.x >= trials.mtlcx * 0.5 then
	t.x = t.x - trials.stlcx * 0.5
	end
	if t.x < trials.mtlcx * 0.5 then
	t.x = t.x + trials.stlcx * 0.5
	end
	end
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
	t.window[1] = (t.window[1] * trials.lcdx00)
	t.window[2] = (t.window[2] * trials.lcdy00)
	t.window[3] = (t.window[3] * trials.lcdx00)
	t.window[4] = (t.window[4] * trials.lcdy00)
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
		textImgSetLocalcoord(t.ti, trials.mtlcx, trials.mtlcy)
	textImgSetBank(t.ti, t.bank)
	textImgSetAlign(t.ti, t.align)
	textImgSetText(t.ti, t.text)
	textImgSetColor(t.ti, t.r, t.g, t.b, t.a)
	textImgSetPos(t.ti, t.x + f_alignOffset(t.align), t.y)
	textImgSetScale(t.ti, t.scaleX, t.scaleY)
	textImgSetWindow(t.ti, t.window[1], t.window[2], t.window[3] - t.window[1], t.window[4] - t.window[2])
	textImgSetXShear(t.ti, t.xshear)
	textImgSetAngle(t.ti, t.angle)
	return t
end

text.new = text.create

--update text
function text:update(t,lcd)
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

		if lcd ==  1 then
			if trials.lcdx00 ~= 1 then
				if trials.mtlcx > trials.stlcx then
					if self.x >= trials.mtlcx * 0.5 then
						self.x = self.x - trials.stlcx * 0.5
					end
					if self.x < trials.mtlcx * 0.5 then
						self.x = self.x + trials.stlcx * 0.5
					end
				end
			end
		end
		textImgSetLocalcoord(self.ti, trials.mtlcx, trials.mtlcy)
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
		textImgSetLocalcoord(self.ti, trials.mtlcx, trials.mtlcy)
		textImgSetText(self.ti, self.text)
	end

	return self
end

--draw text
function text:draw()
	if self.font == -1 then return end
		textImgDraw(self.ti)
	return self
end

-- Builds a text object straight from a system.def node, e.g. f_newText(trials.trials_mode.success.text)
-- for the "success.text.*" keys. Position comes from "pos" when the node has one, otherwise
-- "offset"; callers that need a different origin reposition through :update afterwards.
-- The node's "window" is deliberately not read: trials treats textbox.text.window as an offset
-- pair (see f_trialsDrawer), not as a clipping window.
function f_newText(node)
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
	})
end

-- Render layer for a motif element. The engine buckets Lua draw calls into a pre-pass plus
-- three layers (see System.luaQueueLayerDraw), all of which are flushed after the stage and
-- the characters, so this only orders trials elements against each other. Within one layer
-- the draw order is the order the elements are drawn by f_trialsDrawer.
-- Defaults to 0, which is what every element used before layerno was configurable.
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

-- Builds an Anim from a system.def element node (the table holding offset/scale/spr/anim/
-- facing/layerno) and returns it. Mirrors the engine's own SetAnim (src/iniutils.go):
-- an "anim = N" resolves through the action table, otherwise "spr = group, index" becomes a
-- single-frame anim, and an element with neither gets a blank one so the drawer can stay simple.
function f_loadAnimData(node, x, y, sffOverride, animsOverride)
	local node = type(node) == 'table' and node or {}
	local sprData = sffOverride or trialsSff
	local animData = animsOverride or trialsAnims
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
	-- Order matters: animSetLocalcoord only stores the scale factor, it does not re-derive
	-- values that were already committed. Position, scale and window all have to be applied
	-- *after* it or they stay in 320x240 space and the element renders unscaled.
	animSetLocalcoord(a, trials.mtlcx, trials.mtlcy)
	animSetPos(a, offset[1] + (x or 0), offset[2] + (y or 0))
	animSetScale(a, scale[1], scale[2])
	animSetFacing(a, node.facing or 1)
	animSetWindow(a, 0, 0, trials.mtlcx, trials.mtlcy)
	animSetLayerno(a, f_clampLayerno(node.layerno))
	animUpdate(a)
	return a
end

--;===========================================================
--; main.lua
--;===========================================================
main.t_itemname.trials = function()
	if main.t_charDef[gameOption('Config.TrainingChar'):lower()] ~= nil then
		main.forceChar[2] = {main.t_charDef[gameOption('Config.TrainingChar'):lower()]}
	end
	--main.lifebar.p1score = true
	--main.lifebar.p2ailevel = true
	main.roundTime = -1
	main.selectMenu[2] = true
	if gameOption('Config.TrainingStage') == '' then
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
	textImgSetText(motif.select_info.title.TextSpriteData, "trials")
	remapInput(1, getLastInputController())
	remapInput(getLastInputController(), 1)
	setGameMode('trials')
	setHomeTeam(1)
	hook.run("main.t_itemname")
	return start.f_selectMode
end

--trials spr/anim data
local tr_pos = trials.trials_mode

-- Walks to a system.def node, creating empty tables for any level a screenpack left out, so
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

-- Each element caches its Anim on its own config node as .AnimData, the same convention the
-- engine uses for motif elements (and that textbox.overlay.RectData already follows here).
-- x/y is the element's origin; f_loadAnimData adds the node's own offset on top of it.
local t_elems = {
	{n = f_node(tr_pos, 'trialsteps', 'vertical', 'bg'),   x = tr_pos.trialsteps.vertical.pos[1],   y = tr_pos.trialsteps.vertical.pos[2]},
	{n = f_node(tr_pos, 'trialsteps', 'horizontal', 'bg'), x = tr_pos.trialsteps.horizontal.pos[1], y = tr_pos.trialsteps.horizontal.pos[2]},
	{n = f_node(tr_pos, 'success', 'bg'),                  x = tr_pos.success.pos[1],               y = tr_pos.success.pos[2]},
	{n = f_node(tr_pos, 'success', 'front'),               x = tr_pos.success.pos[1],               y = tr_pos.success.pos[2]},
	{n = f_node(tr_pos, 'allclear', 'bg'),                 x = tr_pos.allclear.pos[1],              y = tr_pos.allclear.pos[2]},
	{n = f_node(tr_pos, 'allclear', 'front'),              x = tr_pos.allclear.pos[1],              y = tr_pos.allclear.pos[2]},
	{n = f_node(tr_pos, 'textbox', 'bg'),                  x = tr_pos.textbox.pos[1],               y = tr_pos.textbox.pos[2]},
	{n = f_node(tr_pos, 'textbox', 'front'),               x = tr_pos.textbox.pos[1],               y = tr_pos.textbox.pos[2]},
}
for _, layout in ipairs({'vertical', 'horizontal'}) do
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'trialtitle', layout, 'bg'),    x = tr_pos.trialtitle[layout].pos[1], y = tr_pos.trialtitle[layout].pos[2]}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, 'trialtitle', layout, 'front'), x = tr_pos.trialtitle[layout].pos[1], y = tr_pos.trialtitle[layout].pos[2]}
end
-- Per-step backgrounds are placed by the draw loop, so they are built at the origin. Horizontal
-- layouts additionally use a fixed-width head and tail either side of the stretched body.
for _, sub in ipairs({'upcomingstep', 'currentstep', 'completedstep'}) do
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'vertical', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg', 'tail')}
	t_elems[#t_elems + 1] = {n = f_node(tr_pos, sub, 'horizontal', 'bg', 'head')}
end
for _, v in ipairs(t_elems) do
	v.n.AnimData = f_loadAnimData(v.n, v.x, v.y)
	main.f_loadingRefresh()
end

--;===========================================================
--; start.lua
--;===========================================================
start.selectScreenPalMod = 'normal'

function trials.f_inittrialsData()
	trials.data = {
		trialsExist = true,
		trialsInitialized = false,
		trialsPaused = false,
		trialadvancement = true,
		trialsRemovalIndex = {},
		active = false,
		allclear = false,
		currenttrial = 1,
		currenttrialstep = 1,
		currenttrialmicrostep = 1,
		validfortickcount = 0,
		comboCounter = 0,
		maxsteps = 0,
		starttick = roundTime(),
		elapsedtime = 0,
		trial = main.f_tableCopy(start.f_getCharData(start.p[1].t_selected[1].ref).trialsdata),
		bgelemdata = {
			vertical = {},
			horizontal = {},
		},
		draw = {},
		displaytimers = {
			totaltimer = opts.TotalTimer ~= false,
			trialtimer = opts.TrialTimer ~= false,
		},
	}

	-- Initialize trialadvancement from the player's saved preference
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		trials.data.trialadvancement = true
	else
		trials.data.trialadvancement = false
	end
end

function trials.f_trialsBuilder()
	--This function will initialize once to build all the trial tables based on the motif information and the trials information loaded when the char was selected
	--Populate background elements information
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep','upcomingstep','completedstep'}) do
			local bg = trials.trials_mode[k][v].bg
			trials.data.bgelemdata[v][k .. '_bgsize'] = animGetSpriteInfo(bg.AnimData)
			if v == 'horizontal' then
				trials.data.bgelemdata[v][k .. '_bgtailwidth'] = animGetSpriteInfo(bg.tail.AnimData)
				trials.data.bgelemdata[v][k .. '_bgheadwidth'] = animGetSpriteInfo(bg.head.AnimData)
			end
		end
	end
	
	-- thin out trials data according to showforvarvalpairs
	for i = 1, #trials.data.trial, 1 do
		if trials.data.trial[i].showforvar[1] ~= nil then
			valvarcheck = true
			sumcheck = 0
			-- check every var
			for ii = 1, #trials.data.trial[i].showforvar, 1 do
				player(1)
				-- iterate over vals
				for iii = 1, #trials.data.trial[i].showforval[ii], 1 do
					if var(trials.data.trial[i].showforvar[ii]) == trials.data.trial[i].showforval[ii][iii] then
						sumcheck = sumcheck + 1
					end
				end
			end
			-- for every var, there should have been one hit; if not, set valvarcheck to false
			if sumcheck ~= #trials.data.trial[i].showforvar then
				valvarcheck = false
			end
			-- remove trials that failed valvarcheck
			if not valvarcheck then
				trials.data.trialsRemovalIndex[#trials.data.trialsRemovalIndex+1] = i
			end
		end
	end
	for i = #trials.data.trialsRemovalIndex, 1, -1 do
		table.remove(trials.data.trial,trials.data.trialsRemovalIndex[i])
	end

	--Obtain all of the trials information, to include the offset positions based on whether the display layout is horizontal or vertical
	for i = 1, #trials.data.trial, 1 do
		if #trials.data.trial[i].trialstep > trials.data.maxsteps then
			trials.data.maxsteps = #trials.data.trial[i].trialstep
		end
		for j = 1, #trials.data.trial[i].trialstep, 1 do
			local movelistline = trials.data.trial[i].trialstep[j].glyphs
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
					if trials.trials_mode.glyphs[layout].align == -1 then
						for m = #tempglyphs, 1, -1 do
							trials.data.trial[i].trialstep[j].glyphline[layout].glyph[#trials.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = tempglyphs[m]
							trials.data.trial[i].trialstep[j].glyphline[layout].pos[#trials.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = {0,0}
							trials.data.trial[i].trialstep[j].glyphline[layout].width[#trials.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].alignOffset[#trials.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[#trials.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
						end
					else
						for m = 1, #tempglyphs do
							trials.data.trial[i].trialstep[j].glyphline[layout].glyph[m] = tempglyphs[m]
							trials.data.trial[i].trialstep[j].glyphline[layout].pos[m] = {0,0}
							trials.data.trial[i].trialstep[j].glyphline[layout].width[m] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = 0
							trials.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
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
				if layout == "vertical" and trials.trials_mode.glyphs.vertical.scalewithtext == "true" then
					font_def = f_fontDef(trials.trials_mode.currentstep.vertical.text.font[1])
				end
				for m in pairs(trials.data.trial[i].trialstep[j].glyphline[layout].glyph) do
					if motif.glyphs[trials.data.trial[i].trialstep[j].glyphline[layout].glyph[m]] ~= nil then
						if trials.trials_mode.glyphs[layout].align == 0 then --center align
							alignOffset = trials.trials_mode.glyphs[layout].offset[1] * 0.5
						elseif trials.trials_mode.glyphs[layout].align == -1 then --right align
							alignOffset = trials.trials_mode.glyphs[layout].offset[1]
						end
						if trials.trials_mode.glyphs[layout].align ~= align then
							lengthOffset = 0
							align = trials.trials_mode.glyphs[layout].align
						end
						local scaleX = trials.trials_mode.glyphs[layout].scale[1]
						local scaleY = trials.trials_mode.glyphs[layout].scale[2]
						if trials.trials_mode.glyphs[layout].align == -1 then
							alignOffset = alignOffset - motif.glyphs[trials.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].Size[1] * scaleX
						end
						trials.data.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = alignOffset
						if font_def ~= nil then
							scaleY = (font_def.Size[2] * trials.trials_mode.currentstep.vertical.text.scale[2] / motif.glyphs[trials.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].Size[2])
							 * trials.lcdy00
							scaleX = scaleY
						end
						trials.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {scaleX, scaleY}
						trials.data.trial[i].trialstep[j].glyphline[layout].width[m] = math.floor(motif.glyphs[trials.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].Size[1] * scaleX + trials.trials_mode.glyphs[layout].spacing[1])
						if trials.trials_mode.glyphs[layout].align == 1 then
							lengthOffset = lengthOffset + trials.data.trial[i].trialstep[j].glyphline[layout].width[m]
						elseif trials.trials_mode.glyphs[layout].align == -1 then
							lengthOffset = lengthOffset - trials.data.trial[i].trialstep[j].glyphline[layout].width[m]
						else
							lengthOffset = lengthOffset + trials.data.trial[i].trialstep[j].glyphline[layout].width[m] / 2
						end
						trials.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = lengthOffset
						trials.data.trial[i].trialstep[j].glyphline[layout].pos[m] = {
							math.floor(trials.trials_mode.trialsteps[layout].pos[1] + trials.trials_mode.glyphs[layout].offset[1] + alignOffset + lengthOffset),
							trials.trials_mode.trialsteps[layout].pos[2] + trials.trials_mode.glyphs[layout].offset[2]
						}
					end
				end
			end
		end
		if #trials.data.trial[i].trialstep > trials.data.maxsteps then
			trials.data.maxsteps = #trials.data.trial[i].trialstep
		end
	end
	--Pre-populate the draw table
	trials.draw = {
		vertical = {},
		horizontal = {},
		success = 0,
		fade = 0,
		fadein = 0,
		fadeout = 0,
		fadetriggered = false,
		textbox_text = f_newText(trials.trials_mode.textbox.text),
		textbox_title = f_newText(trials.trials_mode.textbox.title),
		success_text = f_newText(trials.trials_mode.success.text),
		allclear = math.max(animGetLength(trials.trials_mode.allclear.front.AnimData), animGetLength(trials.trials_mode.allclear.bg.AnimData), trials.trials_mode.allclear.text.displaytime),
		allclear_text = f_newText(trials.trials_mode.allclear.text),
		trialcounter = f_newText(trials.trials_mode.trialcounter),
		totaltrialtimer = f_newText(trials.trials_mode.totaltrialtimer),
		currenttrialtimer = f_newText(trials.trials_mode.currenttrialtimer),
		trialreset_text = f_newText(trials.trials_mode.trialreset.text),
	}
	for _, v in ipairs({'vertical','horizontal'}) do
		trials.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			trialtitle = math.max(animGetLength(trials.trials_mode.trialtitle[v].front.AnimData), animGetLength(trials.trials_mode.trialtitle[v].bg.AnimData)),
			--trialtitle = 100,
			trialtitle_text = f_newText(trials.trials_mode.trialtitle[v].text),
			windowXrange = trials.trials_mode.trialsteps[v].window.withouttextbox[3] - trials.trials_mode.trialsteps[v].window.withouttextbox[1],
			windowYrange = trials.trials_mode.trialsteps[v].window.withouttextbox[4] - trials.trials_mode.trialsteps[v].window.withouttextbox[2],
			windowXrangeWtext = trials.trials_mode.trialsteps[v].window.withtextbox[3] - trials.trials_mode.trialsteps[v].window.withtextbox[1],
			windowYrangeWtext = trials.trials_mode.trialsteps[v].window.withtextbox[4] - trials.trials_mode.trialsteps[v].window.withtextbox[2],
		}
		trials.draw[v].trialtitle_text:update({x = trials.trials_mode.trialtitle[v].pos[1]+trials.trials_mode.trialtitle[v].text.offset[1], y = trials.trials_mode.trialtitle[v].pos[2]+trials.trials_mode.trialtitle[v].text.offset[2],})
		for i = 1, trials.data.maxsteps, 1 do
			trials.draw[v].upcomingtextline[i] = f_newText(trials.trials_mode.upcomingstep[v].text)
			trials.draw[v].currenttextline[i] = f_newText(trials.trials_mode.currentstep[v].text)
			trials.draw[v].completedtextline[i] = f_newText(trials.trials_mode.completedstep[v].text)
		end
	end

	-- Build list out all of the available trials for Pause menu.
	local sub = nil
	local stack = {type(menu) == 'table' and menu.trials or nil}
	while #stack > 0 do
		local node = table.remove(stack)
		if type(node) == 'table' and type(node.submenu) == 'table' then
			if type(node.submenu.trialslist) == 'table' and type(node.submenu.trialslist.items) == 'table' then
				sub = node.submenu.trialslist
				break
			end
			for _, child in pairs(node.submenu) do
				stack[#stack + 1] = child
			end
		end
	end
	trials.listNode = sub
	if sub ~= nil then
		if trials.listTail == nil then
			trials.listTail = sub.items
		end
		local items = {}
		for i = 1, #trials.data.trial, 1 do
			items[i] = {
				itemname = 'trialsentry',
				paramname = 'trialsentry',
				displayname = trials.data.trial[i].name,
				vardisplay = '',
				selected = i == trials.data.currenttrial,
				trial = i,
			}
		end
		for _, item in ipairs(trials.listTail) do
			items[#items + 1] = item
		end
		if #items == 0 then
			items[1] = {itemname = 'back', paramname = 'back', displayname = 'Back', vardisplay = '', selected = false}
		end
		sub.items = items
		sub.item = 1
		sub.cursorPosY = 1
		sub.moveTxt = 0
	end

	trials.data.trialsInitialized = true
end

function trials.f_trialsDummySetup()
	--If the trials initializer was successful and the round animation is completed, we will start drawing trials on the screen
	player(2)
	setAILevel(0)
	if trials.data.currenttrial <= #trials.data.trial then
		if trials.data.trial[trials.data.currenttrial].p2life > 0 then
			mapSet('_iksys_trialsSetLife', trials.data.trial[trials.data.currenttrial].p2life)
			setLife(trials.data.trial[trials.data.currenttrial].p2life)
		elseif map('_iksys_trialsSetLife') < lifeMax() then
			mapSet('_iksys_trialsSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_trialsSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(1)
	if trials.data.currenttrial <= #trials.data.trial then
		if trials.data.trial[trials.data.currenttrial].p1life > 0 then
			mapSet('_iksys_trialsSetLife', trials.data.trial[trials.data.currenttrial].p1life)
			setLife(trials.data.trial[trials.data.currenttrial].p1life)
		elseif map('_iksys_trialsSetLife') < lifeMax() then
			mapSet('_iksys_trialsSetLife', lifeMax())
			setLife(lifeMax())
		end
	else
		mapSet('_iksys_trialsSetLife', lifeMax())
		setLife(lifeMax())
	end
	player(2)
	mapSet('_iksys_trialsDummyControl', 0)
	if not trials.data.allclear and not trials.data.trial[trials.data.currenttrial].active then
		if trials.data.trial[trials.data.currenttrial].dummymode == 'stand' then
			mapSet('_iksys_trialsDummyMode', 0)
		elseif trials.data.trial[trials.data.currenttrial].dummymode == 'crouch' then
			mapSet('_iksys_trialsDummyMode', 1)
		elseif trials.data.trial[trials.data.currenttrial].dummymode == 'jump' then
			mapSet('_iksys_trialsDummyMode', 2)
		elseif trials.data.trial[trials.data.currenttrial].dummymode == 'wjump' then
			mapSet('_iksys_trialsDummyMode', 3)
		end
		if trials.data.trial[trials.data.currenttrial].guardmode == 'none' then
			mapSet('_iksys_trialsGuardMode', 0)
		elseif trials.data.trial[trials.data.currenttrial].guardmode == 'auto' then
			mapSet('_iksys_trialsGuardMode', 2)
		end
		if trials.data.trial[trials.data.currenttrial].buttonjam == 'none' then
			mapSet('_iksys_trialsButtonJam', 0)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'a' then
			mapSet('_iksys_trialsButtonJam', 1)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'b' then
			mapSet('_iksys_trialsButtonJam', 2)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'c' then
			mapSet('_iksys_trialsButtonJam', 3)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'x' then
			mapSet('_iksys_trialsButtonJam', 4)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'y' then
			mapSet('_iksys_trialsButtonJam', 5)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'z' then
			mapSet('_iksys_trialsButtonJam', 6)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'start' then
			mapSet('_iksys_trialsButtonJam', 7)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'd' then
			mapSet('_iksys_trialsButtonJam', 8)
		elseif trials.data.trial[trials.data.currenttrial].buttonjam == 'w' then
			mapSet('_iksys_trialsButtonJam', 9)
		end
		trials.data.trial[trials.data.currenttrial].active = true
	end
	player(1)
end

-- The portrait beside the textbox is a per-step anim: the trials definition's "iconanim" is
-- already a raw anim string once split, so it goes straight to animNew. Source "char" pulls it
-- from the selected character's own sff, source "system" from the screenpack's.
local function f_iconAnimString(step)
	local t = {}
	for _, k in ipairs(step.iconanim) do
		t[#t + 1] = tostring(k)
	end
	return table.concat(t, ',')
end

function trials.textboxportrait()
	-- Cached until roundStart clears it, because the selected character can change.
	if trials.charPortraitSff == nil then
		local spr = loadText(getCharFileName(trials.p1selref)):lower()
		spr = spr:gsub('([^\r\n;]*)%s*;[^\r\n]*', '%1')
		spr = spr:gsub('\n%s*\n', '\n')
		spr = spr:gsub('.*sprite.*=%s*(.*sff).*', '%1')
		trials.charPortraitSff = sffNew(getCharFileName(trials.p1selref):gsub('(.*)%/.*def.*', '%1/') .. spr)
	end
	trialsanim = f_iconAnimString(trials.data.trial[ct].trialstep[cts])
	trials.trials_mode.textbox.portrait.anim = animNew(trials.charPortraitSff, trialsanim)
end
	
function trials.f_trialsDrawer()
	if trials.data.trialsInitialized and roundState() == 2 and not trials.data.active and trials.draw.fade == 0 then
		trials.f_trialsDummySetup()
		trials.data.active = true
	end

	-- Track whether the pause menu is open. The fade and reposition machinery is held while it
	-- is, because Common.Lua runs every tick regardless - without this a Trial picked from the
	-- list starts its fade behind the menu it was picked from, then waits on the menu's own
	-- closing fade, which is the same fade object.
	if paused() and not trials.data.trialsPaused then
		trials.data.trialsPaused = true
	elseif not paused() then
		trials.data.trialsPaused = false
	end

	local accwidth = 0
	local addrow = 0
	-- Initialize abbreviated values for readability
	ct = trials.data.currenttrial
	cts = trials.data.currenttrialstep
	ctms = trials.data.currenttrialmicrostep
	layout = trials.trials_mode.trialslayout

	if trials.data.active then
		if ct <= #trials.data.trial and trials.draw.success == 0 then

			--According to motif instructions, draw trials counter on screen
			local trtext = trials.trials_mode.trialcounter.text
			trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%t', tostring(#trials.data.trial))
			trials.draw.trialcounter:update({text = trtext})
			trials.draw.trialcounter:draw()
			--Logic for the stopwatches: total time spent in trial, and time spent on this current trial
			if trials.data.displaytimers.totaltimer then
				local totaltimertext = trials.trials_mode.totaltrialtimer.text
				trials.data.elapsedtime = roundTime() - trials.data.starttick
				local m, s, x = f_timeConvert(trials.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials.draw.totaltrialtimer:update({text = totaltimertext})
				trials.draw.totaltrialtimer:draw()
			else
				--trials.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--trials.draw.totaltrialtimer:draw()
			end
			if trials.data.displaytimers.trialtimer then
				local currenttimertext = trials.trials_mode.currenttrialtimer.text
				trials.data.trial[ct].elapsedtime = roundTime() - trials.data.trial[ct].starttick
				local m, s, x = f_timeConvert(trials.data.trial[ct].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials.draw.currenttrialtimer:update({text = currenttimertext})
				trials.draw.currenttrialtimer:draw()
			else
				--trials.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--trials.draw.currenttrialtimer:draw()
			end

			-- Draw trial reset reminder if enabled
			if trials.trials_mode.trialreset.enabled then
				trials.draw.trialreset_text:update({text = trials.trials_mode.trialreset.text.text})
				trials.draw.trialreset_text:draw()
			end

			-- Draw trialsteps bg overlay if enabled
			-- TODO: use the dynamic scaling in the draw loop to adjust the overlay size (new x2, y2 values)
			-- if trials.trials_mode.trialsteps[layout].bg.overlay.visible == 'true' then
			-- 	local windowKey = 'withouttextbox'
			-- 	if trials.trials_mode.textbox.visible == true and trials.data.trial[ct].textbox ~= '' then
			-- 		windowKey = 'withtextbox'
			-- 	end
				
			-- 	local bgoverlay = rect:create({})
			-- 	bgoverlay:update({
			-- 		x1 = trials.trials_mode.trialsteps[layout].bg.overlay.window[windowKey][1],
			-- 		y1 = trials.trials_mode.trialsteps[layout].bg.overlay.window[windowKey][2],
			-- 		x2 = trials.trials_mode.trialsteps[layout].bg.overlay.window[windowKey][3],
			-- 		y2 = trials.trials_mode.trialsteps[layout].bg.overlay.window[windowKey][4],
			-- 		r = trials.trials_mode.trialsteps[layout].bg.overlay.col[1],
			-- 		g = trials.trials_mode.trialsteps[layout].bg.overlay.col[2],
			-- 		b = trials.trials_mode.trialsteps[layout].bg.overlay.col[3],
			-- 		src = trials.trials_mode.trialsteps[layout].bg.overlay.alpha[1],
			-- 		dst = trials.trials_mode.trialsteps[layout].bg.overlay.alpha[2],
			-- 		defsc = false,
			-- 	})
			-- 	bgoverlay:draw()
			-- end

			-- Draw trialstep background
			animUpdate(trials.trials_mode.trialsteps[layout].bg.AnimData)
			animDraw(trials.trials_mode.trialsteps[layout].bg.AnimData)

			-- Draw trial title
			animUpdate(trials.trials_mode.trialtitle[layout].bg.AnimData)
			animDraw(trials.trials_mode.trialtitle[layout].bg.AnimData)
			trials.draw[layout].trialtitle_text:update({text = trials.data.trial[ct].name})
			trials.draw[layout].trialtitle_text:draw()
			animUpdate(trials.trials_mode.trialtitle[layout].front.AnimData)
			animDraw(trials.trials_mode.trialtitle[layout].front.AnimData)

			local startonstep = 1
			local drawtothisstep = #trials.data.trial[ct].trialstep

			--Determine whether textboxes are being shown and whether the current trial has a textbox to display, and if so, draw them!
			--Also adjust the window range to account for the textbox as specified in the motif
			if trials.trials_mode.textbox_visible == true and trials.data.trial[ct].textbox ~= '' then
				windowYrange = trials.draw[layout].windowYrangeWtext
				windowXrange = trials.draw[layout].windowXrangeWtext

						textboxwindow1 =    trials.trials_mode.textbox.pos[1]+trials.trials_mode.textbox.overlay.window[1]
						textboxwindow2 =    trials.trials_mode.textbox.pos[2]+trials.trials_mode.textbox.overlay.window[2]
						textboxwindow3 =    trials.trials_mode.textbox.pos[1]+trials.trials_mode.textbox.overlay.window[3]
						textboxwindow4 =    trials.trials_mode.textbox.pos[2]+trials.trials_mode.textbox.overlay.window[4]
		
	if textboxwindow3 == 0 then
textboxwindow3 = trials.mtlcx
	end
	if textboxwindow4 == 0 then
textboxwindow4 = trials.mtlcx
	end
	if trials.lcdx00 ~= 1 then
	if trials.mtlcx > trials.stlcx then
	twpx = textboxwindow3 - textboxwindow1
	twpy = textboxwindow4 - textboxwindow2
	textboxwindow1 = const720p(textboxwindow1 - twpx * 0.5 / trials.lcdy00)
	textboxwindow2 = const720p(textboxwindow2 - twpy * 0.5 / trials.lcdy00)
	textboxwindow3 = const720p(textboxwindow3 + twpx * 0.5 / trials.lcdy00)
	textboxwindow4 = const720p(textboxwindow4 + twpy * 0.5 / trials.lcdy00)
	end
	if trials.mtlcx < trials.stlcx then
	textboxwindow1 = textboxwindow1 / trials.lcdx00
	textboxwindow2 = textboxwindow2 / trials.lcdy00
	textboxwindow3 = textboxwindow3 / trials.lcdx00
	textboxwindow4 = textboxwindow4 / trials.lcdy00

	end
	end

		if trials.trials_mode.textbox.overlay.RectData == nil then
		trials.trials_mode.textbox.overlay.RectData = rectNew()
				end
		rectSetColor(trials.trials_mode.textbox.overlay.RectData, 
						trials.trials_mode.textbox.overlay.col[1],
						trials.trials_mode.textbox.overlay.col[2],
						trials.trials_mode.textbox.overlay.col[3])
		rectSetAlpha(trials.trials_mode.textbox.overlay.RectData, 
						trials.trials_mode.textbox.overlay.alpha[1],
						trials.trials_mode.textbox.overlay.alpha[2])
		rectSetLayerno(trials.trials_mode.textbox.overlay.RectData, 0)
		rectSetWindow(trials.trials_mode.textbox.overlay.RectData, 
						textboxwindow1,
						textboxwindow2,
						textboxwindow3,
						textboxwindow4)
		rectSetLocalcoord(trials.trials_mode.textbox.overlay.RectData, trials.stlcx, trials.stlcy)
		rectDraw(trials.trials_mode.textbox.overlay.RectData)
				
				-- The textbox sits in stage space, unlike the rest of the trials elements.
				animSetLocalcoord(trials.trials_mode.textbox.bg.AnimData, trials.stlcx, trials.stlcy)
				animUpdate(trials.trials_mode.textbox.bg.AnimData)
				animDraw(trials.trials_mode.textbox.bg.AnimData)

				-- Draw text
				local trtext = trials.trials_mode.textbox.title.text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', trials.data.trial[ct].name)
				trials.draw.textbox_title:update({text = trtext})
				trials.draw.textbox_title:draw()

				if not trials.draw.draw_textbox_text then
					trials.data.trial[ct].textcnt = trials.data.trial[ct].textcnt + 1
				end
				
		if motif.Fnt[trials.draw.textbox_text.font] ~= nil then
			textImgSetFont(trials.draw.textbox_text.ti, motif.Fnt[trials.draw.textbox_text.font])
		end

	textboxtext_offset1 = textboxwindow1 * trials.lcdx00 + trials.trials_mode.textbox_text_window[1]+trials.trials_mode.textbox_text_offset[1]
	textboxtext_offset2 = textboxwindow2 * trials.lcdy00 + trials.trials_mode.textbox_text_window[2]+trials.trials_mode.textbox_text_offset[2]
		textboxtext_offset1 = textboxtext_offset1 / trials.lcdx00
		textboxtext_offset2 = textboxtext_offset2 / trials.lcdy00
	
		textImgSetText(trials.draw.textbox_text.ti,string.format(trials.data.trial[ct].textbox, main.f_countSubstring(trials.data.trial[ct].textbox, '_')))
		textImgSetPos(trials.draw.textbox_text.ti, math.floor(textboxtext_offset1), math.floor(textboxtext_offset2))
		textImgSetScale(trials.draw.textbox_text.ti, trials.draw.textbox_text.scaleX / trials.lcdy00, trials.draw.textbox_text.scaleY / trials.lcdy00)
		textImgSetLocalcoord(trials.draw.textbox_text.ti, trials.stlcx, trials.stlcy)
		textImgDraw(trials.draw.textbox_text.ti)


				-- Draw portrait depending on desired source. Both sources feed the same draw
				-- below; the anim is rebuilt every frame because iconanim is per trial step.
				if trials.trials_mode.textbox_portrait_source == "system" then
					trialsanim = f_iconAnimString(trials.data.trial[ct].trialstep[cts])
					trials.trials_mode.textbox.portrait.anim = animNew(sff, trialsanim)
				elseif trials.trials_mode.textbox_portrait_source == "char" then
					trials.textboxportrait()
				end

				if trials.trials_mode.textbox.portrait.anim ~= nil then
					trialsanimoffset = trials.data.trial[ct].trialstep[cts].iconanimoffset
					animposx = (textboxwindow1 * trials.lcdx00 + trials.trials_mode.textbox_portrait_offset[1] + trialsanimoffset[1])
					animposy = (textboxwindow2 * trials.lcdx00 + trials.trials_mode.textbox_portrait_offset[2] + trialsanimoffset[2])
					trialsanimscalex = trials.trials_mode.textbox_portrait_scale[1] * trials.data.trial[ct].trialstep[cts].iconanimscale[1]
					trialsanimscaley = trials.trials_mode.textbox_portrait_scale[2] * trials.data.trial[ct].trialstep[cts].iconanimscale[2]
					trialsanimwindow3 = trials.trials_mode.textbox_portrait_window[3] + trials.data.trial[ct].trialstep[cts].iconanimwindow[3] + trials.mtlcx
					trialsanimwindow4 = trials.trials_mode.textbox_portrait_window[4] + trials.data.trial[ct].trialstep[cts].iconanimwindow[4] + trials.mtlcy

					if trials.lcdx00 ~= 1 then
						if trials.mtlcx > trials.stlcx then
							trialsanimscalex = trialsanimscalex / trials.lcdy00
							trialsanimscaley = trialsanimscaley / trials.lcdy00
							animposx = const720p(animposx)
							animposy = const720p(animposy)
						end
						if trials.mtlcx < trials.stlcx then
							trialsanimscalex = trialsanimscalex / trials.lcdy00
							trialsanimscaley = trialsanimscaley / trials.lcdy00
							animposx = animposx / trials.lcdx00
							animposy = animposy / trials.lcdx00
							trialsanimwindow3 = trialsanimwindow3 * 2 / trials.lcdx00
							trialsanimwindow4 = trialsanimwindow4 * 2 / trials.lcdy00
						end
					end

					trialsanimwindow1 = animposx + trials.trials_mode.textbox_portrait_window[1] + trials.data.trial[ct].trialstep[cts].iconanimwindow[1]
					trialsanimwindow2 = animposy + trials.trials_mode.textbox_portrait_window[2] + trials.data.trial[ct].trialstep[cts].iconanimwindow[2]

					local a = trials.trials_mode.textbox.portrait.anim
					-- Portraits are placed in stage space, like the textbox they sit in.
					animSetLocalcoord(a, trials.stlcx, trials.stlcy)
					animSetLayerno(a, 0)
					animSetPos(a, math.floor(animposx), math.floor(animposy))
					animSetScale(a, trialsanimscalex, trialsanimscaley)
					animSetFacing(a, trials.trials_mode.textbox_portrait_facing)
					animSetWindow(a, trialsanimwindow1, trialsanimwindow2, trialsanimwindow3, trialsanimwindow4)
					animUpdate(a)
					animDraw(a)
				end

				-- Draw textbox front
				animUpdate(trials.trials_mode.textbox.front.AnimData)
				animDraw(trials.trials_mode.textbox.front.AnimData)
			else
				windowYrange = trials.draw[layout].windowYrange
				windowXrange = trials.draw[layout].windowXrange
			end

			--For vertical trial layouts, determine if all assets will be drawn within the trials window range, or if scrolling needs to be enabled. For horizontal layouts, we will figure it out
			--when we determine glyph and incrementor widths (see notes below). We do this step outside of the draw loop to speed things up.
			if #trials.data.trial[ct].trialstep*trials.trials_mode.trialsteps[layout].spacing[2] > windowYrange and layout == "vertical" then
				startonstep = math.max(cts-2, 1)
				if (drawtothisstep - startonstep)*trials.trials_mode.trialsteps[layout].spacing[2] > windowYrange then
					drawtothisstep = math.min(startonstep+math.floor(windowYrange/trials.trials_mode.trialsteps[layout].spacing[2]),#trials.data.trial[ct].trialstep)
				end
			end

			--This is the draw loop
			for i = startonstep, drawtothisstep, 1 do
				local tempoffset = {trials.trials_mode.trialsteps[layout].spacing[1]*(i-startonstep),trials.trials_mode.trialsteps[layout].spacing[2]*(i-startonstep)}
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

				-- if trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'] == 'true' then
				-- 	bgoverlay = rect:create({})
				-- 	bgoverlay:update({
				-- 		x1 =    trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		y1 =    trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		x2 =    trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		y2 =    trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][4],
				-- 		r =     trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		g =     trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		b =     trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		src =   trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		dst =   trials.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		defsc = false,
				-- 	})
				-- 	bgoverlay:draw()
				-- end

				if layout == "vertical" then
					--Vertical layouts are the simplest - they have a constant width sprite or anim that the text is drawn on top of, and the glyphs are displayed wherever specified.
					--The vertical layouts do NOT support incrementors (see notes below for horizontal layout).
					local stepbg = trials.trials_mode[sub .. 'step'].vertical.bg
					animSetPos(
						stepbg.AnimData,
						trials.trials_mode.trialsteps.vertical.pos[1] + stepbg.offset[1] + tempoffset[1],
						trials.trials_mode.trialsteps.vertical.pos[2] + stepbg.offset[2] + tempoffset[2]
					)
					trials.draw.vertical[sub .. 'textline'][i]:update({
						x = trials.trials_mode.trialsteps.vertical.pos[1]+trials.trials_mode[sub .. 'step'].vertical.text.offset[1]+trials.trials_mode.trialsteps.vertical.spacing[1]*(i-startonstep),
						y = trials.trials_mode.trialsteps.vertical.pos[2]+trials.trials_mode[sub .. 'step'].vertical.text.offset[2]+trials.trials_mode.trialsteps.vertical.spacing[2]*(i-startonstep),
						text = trials.data.trial[ct].trialstep[i].text
					},1)
					animSetPalFX(stepbg.AnimData, {
						time = 1,
						add = stepbg.palfx.add,
						mul = stepbg.palfx.mul,
						sinadd = stepbg.palfx.sinadd,
						invertall = stepbg.palfx.invertall,
						color = stepbg.palfx.color
					})
					animReset(stepbg.AnimData)
					animUpdate(stepbg.AnimData)
					animDraw(stepbg.AnimData)
					trials.draw.vertical[sub .. 'textline'][i]:draw()
				elseif layout == "horizontal" then
					--Horizontal layouts are much more complicated. Text is not drawn in horizontal mode, instead we only display the glyphs. A small sprite is dynamically tiled to the width of the
					--glyphs, and an optional background element called an incrementor (bginc) can be used to link the pieces together (think of an arrow where the body of the arrow is where the
					--glyphs are being drawn and that's the dynamically sized part, and the head of the arrow is the incrementor which is a fixed width sprite). There's quite a bit more work that
					--goes into displaying the horizontal layouts because the code needs to figure out the window size, and determine when it needs to "go to the next line" and create a return so
					--that trials can be displayed dynamically. Back to the arrow analogy, you always want an arrow body to have an arrow head, so the incrementor width is added to the glyphs length
					--and the padding factor specified in the motif data, it's all added together until the window width is met or exceeded, then a line return occurs and the next line is drawn.
					local bgsize = {0,0}
					if trials.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'] ~= nil then bgtailwidth = math.floor(trials.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'].Size[1]) end
					if trials.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'] ~= nil then bgheadwidth = math.floor(trials.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'].Size[1]) end
					if trials.data.bgelemdata.horizontal[sub .. 'step_bgsize'] ~= nil then bgsize = trials.data.bgelemdata.horizontal[sub .. 'step_bgsize'].Size end

					totalglyphlength = trials.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[#trials.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset]
					padding = trials.trials_mode.trialsteps_horizontal_padding
					spacing = trials.trials_mode.trialsteps_horizontal_spacing[1]

					local tempwidth = spacing + bgtailwidth + padding + totalglyphlength + padding + bgheadwidth + accwidth
					if tempwidth - trials.trials_mode.trialsteps_horizontal_spacing[1] > windowXrange then
						accwidth = 0
						addrow = addrow + 1
					end

					tempoffset[2] = trials.trials_mode.trialsteps_horizontal_spacing[2]*(addrow)

					-- Calculate initial positions
					if accwidth == 0 then
						bgcomponentposX = trials.trials_mode.trialsteps_horizontal_pos[1]
					else
						bgcomponentposX = accwidth + spacing -- + bgheadwidth 
					end
					
	tailscalex = trials.data.trial[ct].trialstep[i].glyphline.horizontal.scale[1][1]
	tailscaley = trials.data.trial[ct].trialstep[i].glyphline.horizontal.scale[1][2]

	if trials.mtlcx == 1280 then
	if trials.lcdx00 == 1 then
	tailscalex = tailscalex * 2 * trials.lcdx00
	tailscaley = tailscaley * 2 * trials.lcdy00
					end
	if trials.lcdx00 ~= 1 then
	tailscalex = tailscalex * 0.5 * trials.lcdx00
	tailscaley = tailscaley * 0.5 * trials.lcdy00
					end
					end
	if trials.mtlcx == 320 then
	if trials.lcdx00 == 1 then
	tailscalex = tailscalex * 2 * trials.lcdx00
	tailscaley = tailscaley * 2 * trials.lcdy00
					end
	if trials.lcdx00 ~= 1 then
	tailscalex = tailscalex * 0.5 / trials.lcdx00
	tailscaley = tailscaley * 0.5 / trials.lcdy00
					end
					end
	
					-- Draw tail
					local hbg = trials.trials_mode[sub .. 'step'].horizontal.bg
					local hpalfx = {
						time = 1,
						add = hbg.palfx.add,
						mul = hbg.palfx.mul,
						sinadd = hbg.palfx.sinadd,
						invertall = hbg.palfx.invertall,
						color = hbg.palfx.color
					}
					local glyphrow = trials.data.trial[ct].trialstep[i].glyphline.horizontal
					animSetPos(hbg.tail.AnimData,
						bgcomponentposX + hbg.tail.offset[1],
						glyphrow.pos[1][2] + hbg.tail.offset[2] + tempoffset[2]
					)
					animSetScale(hbg.tail.AnimData, tailscalex, tailscaley)
					animSetPalFX(hbg.tail.AnimData, hpalfx)
					animReset(hbg.tail.AnimData)
					animUpdate(hbg.tail.AnimData)
					if menu.itemname ~= 'commandlist' then
						animDraw(hbg.tail.AnimData)
					end

					-- Draw BG for Glyphs - scale to length, start from tail pos
					bgtargetscale = {(padding + totalglyphlength + padding)/bgsize[1], 1}
					bgcomponentposX = (bgcomponentposX + bgtailwidth)
					local gpoffset = 0
					for m in pairs(glyphrow.glyph) do
						if m > 1 then gpoffset = glyphrow.lengthOffset[m-1] end
						glyphrow.pos[m][1] = bgcomponentposX + padding + gpoffset
					end

					animSetScale(hbg.AnimData, bgtargetscale[1], bgtargetscale[2])
					animSetPos(hbg.AnimData,
						bgcomponentposX + hbg.offset[1],
						glyphrow.pos[1][2] + hbg.offset[2] + tempoffset[2]
					)
					animSetPalFX(hbg.AnimData, hpalfx)
					animReset(hbg.AnimData)
					animUpdate(hbg.AnimData)
					animDraw(hbg.AnimData)

					-- Draw head
					bgcomponentposX = bgcomponentposX + (totalglyphlength + 2*padding)
					animSetPos(hbg.head.AnimData,
						bgcomponentposX + hbg.head.offset[1] + glyphrow.alignOffset[1],
						glyphrow.pos[1][2] + hbg.head.offset[2] + tempoffset[2]
					)
					animSetPalFX(hbg.head.AnimData, hpalfx)
					animReset(hbg.head.AnimData)
					animUpdate(hbg.head.AnimData)
					animDraw(hbg.head.AnimData)
				end
				local glyphline = trials.data.trial[ct].trialstep[i].glyphline[layout]
				local glyphpalfx = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx
				for m = 1, #glyphline.glyph, 1 do
					-- Glyph anims belong to the engine's motif and were built in the motif's own
					-- coordinate space, so pull them into trials space before placing them.
					local g = motif.glyphs[glyphline.glyph[m]].AnimData
					animSetLocalcoord(g, trials.mtlcx, trials.mtlcy)
					animSetScale(g, glyphline.scale[m][1], glyphline.scale[m][2])
					animSetPos(g,
						glyphline.pos[m][1],
						glyphline.pos[m][2] + tempoffset[2] + trials.trials_mode.glyphs[layout].offset[2]
					)
					animSetPalFX(g, {
						time = 1,
						add = glyphpalfx.add,
						mul = glyphpalfx.mul,
						sinadd = glyphpalfx.sinadd,
						invertall = glyphpalfx.invertall,
						color = glyphpalfx.color
					})
					animReset(g)
					animUpdate(g)
					if menu.itemname ~= 'commandlist' then
						animDraw(g)
					end
				end
				accwidth = bgcomponentposX
			end
		elseif ct > #trials.data.trial then
			-- All trials have been completed, draw the all clear and freeze the timer
			if trials.draw.allclear ~= 0 then
				trials.f_trialsSuccess('allclear', ct-1)
			end

			trials.data.allclear = true
			trials.draw.success = 0
			trials.draw.trialcounter:update({text = trials.trials_mode.trialcounter.allclear.text})
			trials.draw.trialcounter:draw()

			if trials.data.displaytimers.totaltimer then
				local totaltimertext = trials.trials_mode.totaltrialtimer.text
				local m, s, x = f_timeConvert(trials.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials.draw.totaltrialtimer:update({text = totaltimertext})
				trials.draw.totaltrialtimer:draw()
			else
				--trials.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--trials.draw.totaltrialtimer:draw()
			end
			if trials.data.displaytimers.trialtimer then
				local currenttimertext = trials.trials_mode.currenttrialtimer.text
				local m, s, x = f_timeConvert(trials.data.trial[ct-1].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials.draw.currenttrialtimer:update({text = currenttimertext})
				trials.draw.currenttrialtimer:draw()
			else
				--trials.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--trials.draw.currenttrialtimer:draw()
			end
		end
	end
end


function trials.f_trialsChecker(CheckIt)
	--This function sets dummy actions according to the character trials info and validates trials attempts
	--To help follow along, ct = current trial, cts = current trial step, ncts = next current trial step
	if ct <= #trials.data.trial and trials.draw.success == 0 and trials.draw.fade == 0 and trials.data.active then
	
			if trials.data.trial[ct].trialstep[cts].hitcount[ctms] == nil then
			trials.data.trial[ct].trialstep[cts].hitcount[ctms] = -1
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
				if numProjId(projid) > 0 and playerId(attackerid) then
					attackeranim = projVar(projid, 0, 'anim')
				end
			else
				if playerId(attackerid) then
					attackerstate = stateNo()
					attackeranim = anim()
				end
			end
			-- Can uncomment this sec to debug helper/proj data
			print("ID: " .. attackerid)
			print("Source: " .. source)
			print("State: " .. attackerstate)
			print("Anim: " .. attackeranim)
		end
		player(1)
		if CheckIt ~= nil and CheckIt ~= 'root' then
			helperIndex(CheckIt)
		end

		-- Check states and anims; iterate over 'or' operand if multiple states and/or anims are provided
		local desiredstates = trials.data.trial[ct].trialstep[cts].stateno[ctms]
		if desiredstates == nil or #desiredstates == 0 then
			statecheck = true
		else
			for k = 1, #desiredstates, 1 do
				if stateNo() == desiredstates[k] or attackerstate == desiredstates[k] then
					statecheck = true
					break
				end
			end
		end
		if trials.data.trial[ct].trialstep[cts].animno[ctms] ~= nil then
			animcheck = false
			local desiredanims = trials.data.trial[ct].trialstep[cts].animno[ctms]
			for k = 1, #desiredanims, 1 do
				if anim() == desiredanims[k] or attackeranim == desiredanims[k] then
					animcheck = true
					break
				end
			end
		end

		if (trials.data.trial[ct].trialstep[cts].ishelper[ctms] and statecheck) and animcheck then
			helpercheck = true
			if trials.data.trial[ct].trialstep[cts].validforvar ~= nil and helpercheck then
				for i = 1, #trials.data.trial[ct].trialstep[cts].validforvar, 1 do
					if helpercheck then
						helpercheck = var(trials.data.trial[ct].trialstep[cts].validforvar[i]) == trials.data.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		if (trials.data.trial[ct].trialstep[cts].isproj[ctms] and statecheck) and animcheck then
			projcheck = true
			if trials.data.trial[ct].trialstep[cts].validforvar ~= nil and projcheck then
				for i = 1, #trials.data.trial[ct].trialstep[cts].validforvar, 1 do
					if projcheck then
						projcheck = var(trials.data.trial[ct].trialstep[cts].validforvar[i]) == trials.data.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		maincharcheck = (statecheck and not(trials.data.trial[ct].trialstep[cts].isproj[ctms]) and not(trials.data.trial[ct].trialstep[cts].ishelper[ctms]) and animcheck and ((moveHit() > 0 and comboCount() > trials.data.comboCounter) or trials.data.trial[ct].trialstep[cts].isthrow[ctms] or trials.data.trial[ct].trialstep[cts].hitcount[ctms] == 0))
		if trials.data.trial[ct].trialstep[cts].validforvar ~= nil and maincharcheck then
			for i = 1, #trials.data.trial[ct].trialstep[cts].validforvar, 1 do
				if maincharcheck then
					maincharcheck = var(trials.data.trial[ct].trialstep[cts].validforvar[i]) == trials.data.trial[ct].trialstep[cts].validforval[i]
				end
			end
		end		

		if trials.data.validfortickcount > 0 and paused() == false and pauseTime() == 0 and CheckIt == 'root' then
			trials.data.validfortickcount = trials.data.validfortickcount - 1
		end
		
		if maincharcheck or projcheck or helpercheck then
			if trials.data.trial[ct].trialstep[cts].hitcount[ctms] >= 1 then
				if trials.data.trial[ct].trialstep[cts].stephitscount[ctms] == 0 then
					trials.data.trial[ct].trialstep[cts].comboCountonstep[ctms] = comboCount()
				end
				if comboCount() - trials.data.trial[ct].trialstep[cts].stephitscount[ctms] == trials.data.trial[ct].trialstep[cts].comboCountonstep[ctms] then
					trials.data.trial[ct].trialstep[cts].stephitscount[ctms] = trials.data.trial[ct].trialstep[cts].stephitscount[ctms] + 1
				end
			elseif trials.data.trial[ct].trialstep[cts].hitcount[ctms] == 0 then
				trials.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			end

			if trials.data.trial[ct].trialstep[cts].hitcount[ctms] == trials.data.trial[ct].trialstep[cts].stephitscount[ctms] then
				nctms = ctms + 1
				-- First, check that the microstep has passed
				if nctms >= 1 and ((comboCount() > 0 and (trials.data.trial[ct].trialstep[cts].iscounterhit[ctms] and moveCountered() > 0) or not trials.data.trial[ct].trialstep[cts].iscounterhit[ctms]) or trials.data.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
					if nctms >= 1 and ((trials.data.trial[ct].trialstep[cts].hitcount[ctms] > 1 and comboCount() == trials.data.trial[ct].trialstep[cts].stephitscount[ctms] + trials.data.trial[ct].trialstep[cts].comboCountonstep[ctms] - 1) or trials.data.trial[ct].trialstep[cts].hitcount[ctms] == 1 or trials.data.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
						trials.data.currenttrialmicrostep = nctms
						if trials.data.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
							trials.data.validfortickcount = trials.data.trial[ct].trialstep[cts].validfortickcount[ctms]
						else
							trials.data.validfortickcount = 0
						end
						trials.data.comboCounter = comboCount()
					elseif ((comboCount() == 0 and trials.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and trials.data.validfortickcount == 0) or (trials.data.validfortickcount > 0 and comboCount() > trials.data.comboCounter) then
						trials.data.currenttrialstep = 1
						trials.data.currenttrialmicrostep = 1
						trials.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
						trials.data.trial[ct].trialstep[cts].comboCountonstep[ctms] = 0
						trials.data.comboCounter = 0
						trials.data.validfortickcount = 0
					end
				end
				-- Next, if microstep is exceeded, go to next trial step
				if trials.data.currenttrialmicrostep > trials.data.trial[ct].trialstep[cts].numofmicrosteps then
					trials.data.currenttrialmicrostep = 1
					trials.data.currenttrialstep = cts + 1
					if trials.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0 and comboCount() == 0 and comboCount() == trials.data.comboCounter then
						trials.data.comboCounter = trials.data.comboCounter + 1
					else
						trials.data.comboCounter = comboCount()
					end	
					if trials.data.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
						trials.data.validfortickcount = trials.data.trial[ct].trialstep[cts].validfortickcount[ctms]
					else
						trials.data.validfortickcount = 0
					end
					if trials.data.currenttrialstep > #trials.data.trial[ct].trialstep then
						-- If trial step was last, go to next trial and display success banner
						if trials.data.trialadvancement then
							trials.data.currenttrial = ct + 1
						end
						trials.data.currenttrialstep = 1
						trials.data.comboCounter = 0
						if ct < #trials.data.trial or (not trials.data.trialadvancement and ct == #trials.data.trial) then
							if (trials.trials_mode.success_front_displaytime == -1) and (trials.trials_mode.success_bg_displaytime == -1) then
								trials.draw.success = math.max(animGetLength(trials.trials_mode.success.front.AnimData), animGetLength(trials.trials_mode.success.bg.AnimData), trials.trials_mode.success_text_displaytime)
							else
								trials.draw.success = math.max(trials.trials_mode.success_front_displaytime, trials.trials_mode.success_bg_displaytime, trials.trials_mode.success_text_displaytime)
							end
							if trials.trials_mode.trialsresetonsuccess == true then
								trials.draw.fadein = trials.trials_mode.fadein_time
								trials.draw.fadeout = trials.trials_mode.fadeout_time
								trials.draw.fade = trials.draw.fadein + trials.draw.fadeout
							end
						end
					end
				end
			end
		elseif ((comboCount() == 0 and trials.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and trials.data.validfortickcount == 0) or (trials.data.validfortickcount > 0 and comboCount() > trials.data.comboCounter) then
			trials.data.currenttrialstep = 1
			trials.data.currenttrialmicrostep = 1
			trials.data.comboCounter = 0
			trials.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			trials.data.trial[ct].trialstep[cts].comboCountonstep[ctms] = 0
			trials.data.validfortickcount = 0
		end
	end
	--If the trial was completed successfully, draw the trials success
	if trials.draw.success > 0 then
		trials.f_trialsSuccess('success', ct)
	elseif trials.data.trialsPaused then
		-- Hold the fade and reposition where they are while the pause menu is open.
	elseif trials.draw.fade > 0 and (trials.trials_mode.trialsresetonsuccess == true or trials.draw.fadetriggered) and CheckIt == 'root' then
		if trials.draw.fade < trials.draw.fadein + trials.draw.fadeout then
			trials.f_trialsFade()
		else
			player(2)
			if stateNo() == 0 or trials.draw.fadetriggered then
							mapSet('_iksys_trialsButtonJamDelay',trials.draw.fade)
				trials.f_trialsFade()
			end
			player(1)
		end
	elseif f_checkKeyCombo(trials.trials_mode.trialreset_buttonpress) and trials.draw.fade == 0 and trials.trials_mode.trialreset.enabled and trials.data.currenttrial <= #trials.data.trial then
		trials.draw.fadein = trials.trials_mode.fadein_time
		trials.draw.fadeout = trials.trials_mode.fadeout_time
		trials.draw.fade = trials.draw.fadein + trials.draw.fadeout
		trials.draw.fadetriggered = true
	elseif not CheckIt == 'root' or trials.draw.fade == 0 then
		trials.draw.fadetriggered = false
	end
		player(1)
end

function trials.f_trialsSuccess(successstring, index)
	-- This function is responsible for drawing the Success or All Clear banners after a trial is completed successfully.
	player(2)
	mapSet('_iksys_trialsDummyMode', 0)
	mapSet('_iksys_trialsGuardMode', 0)
	mapSet('_iksys_trialsButtonJam', 0)
	player(1)
	if not trials.data.trial[index].complete or (successstring == "allclear" and not trials.data.allclear) then
		-- Play sound only once
		sndPlay(snd, trials.trials_mode[successstring .. '_snd'][1], trials.trials_mode[successstring .. '_snd'][2])
	end
	-- The banner text is centred on its element's pos rather than its own offset.
	local banner = trials.trials_mode[successstring]
	trials.draw[successstring .. '_text']:update({
		text = banner.text.text,
		x = banner.pos[1],
		y = banner.pos[2],
	})
	animUpdate(banner.bg.AnimData)
	animDraw(banner.bg.AnimData)
	trials.draw[successstring .. '_text']:draw()
	animUpdate(banner.front.AnimData)
	animDraw(banner.front.AnimData)
	trials.draw[successstring] = trials.draw[successstring] - 1
	trials.data.trial[index].complete = true
	trials.data.trial[index].active = false
	trials.data.active = false
	if not trials.data.trialadvancement then
		trials.data.trial[index].starttick = roundTime()
	end
	if index ~= #trials.data.trial then
		trials.data.trial[index+1].starttick = roundTime()
	end
end

function trials.f_trialsFade()
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

	if trials.data.trial[trials.data.currenttrial].dummyposoffset[1] == nil then
	trials.data.trial[trials.data.currenttrial].dummyposoffset[1] = 0
	end
	if trials.data.trial[trials.data.currenttrial].dummyposoffset[2] == nil then
	trials.data.trial[trials.data.currenttrial].dummyposoffset[2] = 0
	end
	if trials.data.trial[trials.data.currenttrial].playerposoffset[1] == nil then
	trials.data.trial[trials.data.currenttrial].playerposoffset[1] = 0
	end
	if trials.data.trial[trials.data.currenttrial].playerposoffset[2] == nil then
	trials.data.trial[trials.data.currenttrial].playerposoffset[2] = 0
	end
	
	if trials.data.trial[trials.data.currenttrial].dummypos == 'left-corner' or trials.data.trial[trials.data.currenttrial].playerpos == 'left-corner' then
		cameraPosX = leftbound / (stagelocalcoordX/320)
		posx = - (stagelocalcoordX/2 - stageboundleft) / (stagelocalcoordX/320)
		if trials.data.trial[trials.data.currenttrial].dummypos == 'close' or trials.data.trial[trials.data.currenttrial].playerpos == 'close' then
			oppx = posx + 10
		elseif trials.data.trial[trials.data.currenttrial].dummypos == 'far' or trials.data.trial[trials.data.currenttrial].playerpos == 'far' then
			oppx = posx + 260
		else --medium or nil
			oppx = posx + 130
		end
		if trials.data.trial[trials.data.currenttrial].dummypos == 'left-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif trials.data.trial[trials.data.currenttrial].dummypos == 'right-corner' or trials.data.trial[trials.data.currenttrial].playerpos == 'right-corner' then
		cameraPosX = rightbound / (stagelocalcoordX/320)
		posx = (stagelocalcoordX/2 - stageboundright) / (stagelocalcoordX/320)
		if trials.data.trial[trials.data.currenttrial].dummypos == 'close' or trials.data.trial[trials.data.currenttrial].playerpos == 'close' then
			oppx = posx - 10
		elseif trials.data.trial[trials.data.currenttrial].dummypos == 'far' or trials.data.trial[trials.data.currenttrial].playerpos == 'far' then
			oppx = posx - 260
		else --medium or nil
			oppx = posx - 130
		end
		if trials.data.trial[trials.data.currenttrial].dummypos == 'right-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif trials.data.trial[trials.data.currenttrial].dummypos == 'close' or trials.data.trial[trials.data.currenttrial].playerpos == 'close' then
		dummyposx = 5
		playerposx = -5
	elseif trials.data.trial[trials.data.currenttrial].dummypos == 'medium' or trials.data.trial[trials.data.currenttrial].playerpos == 'medium' then
		dummyposx = 65
		playerposx = -65
	elseif trials.data.trial[trials.data.currenttrial].dummypos == 'far' or trials.data.trial[trials.data.currenttrial].playerpos == 'far' then
		dummyposx = 130
		playerposx = -130
	end

	dummyposx = dummyposx + trials.data.trial[trials.data.currenttrial].dummyposoffset[1]
	dummyposy = dummyposy + trials.data.trial[trials.data.currenttrial].dummyposoffset[2]
	playerposx = playerposx + trials.data.trial[trials.data.currenttrial].playerposoffset[1]
	playerposy = playerposy + trials.data.trial[trials.data.currenttrial].playerposoffset[2]
	
	mapSet('_iksys_trialsCameraPosX', cameraPosX)
	mapSet('_iksys_trialsDummyPosX', dummyposx)
	mapSet('_iksys_trialsDummyPosY', dummyposy)
	mapSet('_iksys_trialsPlayerPosX', playerposx)
	mapSet('_iksys_trialsPlayerPosY', playerposy)
	
	-- This function is responsible for fadein/fadeout if trialsresetonsuccess is set to true.
	if trials.draw.fadeout > 0 then
		if not fadeActive() then
			trials.draw.fadeoutData = fadeNew({
			time = trials.draw.fadeout,
			color = {trials.trials_mode.fadeout.col[1],
			trials.trials_mode.fadeout.col[2],
			trials.trials_mode.fadeout.col[3]},
			anim = trials.trials_mode.fadeout.anim
			})
		fadeOutInit(trials.draw.fadeoutData)
		end
		trials.draw.fadeout = trials.draw.fadeout - 1

	elseif trials.draw.fadein > 0 then
		if not fadeActive() then
			mapSet('_iksys_trialsReposition', 1)
			trials.draw.fadeinData = fadeNew({
			time = trials.draw.fadein,
			color = {trials.trials_mode.fadein.col[1],
			trials.trials_mode.fadein.col[2],
			trials.trials_mode.fadein.col[3]},
			anim = trials.trials_mode.fadein.anim
			})
		fadeInInit(trials.draw.fadeinData)
	end
		trials.draw.fadein = trials.draw.fadein - 1
	end

	trials.draw.fade = trials.draw.fade - 1
	if trials.draw.fade == 0 then
			mapSet('_iksys_trialsCameraReset', 1)
end
end

function trials.f_trialsSelectScreen()
-- Grays out portaits on the trial select screen for characters without trials files
	local selectScreenPalMod = false

	if gameMode("trials") and start.selectScreenPalMod == 'normal' then
		paladd = trials.trials_mode.selscreenpalfx_add
		palmul = trials.trials_mode.selscreenpalfx_mul
		palsinadd = trials.trials_mode.selscreenpalfx_sinadd
		palinvertall = trials.trials_mode.selscreenpalfx_invertall
		palcolor = trials.trials_mode.selscreenpalfx_color
		start.selectScreenPalMod = 'darkened'
		selectScreenPalMod = true
	elseif not gameMode("trials") and start.selectScreenPalMod == 'darkened' then
		paladd = {0,0,0}
		palmul = {256,256,256}
		palsinadd = {0,0,0}
		palinvertall = 0
		palcolor = 256
		start.selectScreenPalMod = 'normal'
		selectScreenPalMod = true
	end

	if selectScreenPalMod then
		for row = 1, motif.select_info.rows do
			for col = 1, motif.select_info.columns do
				local cellIndex = (row - 1) * motif.select_info.columns + col
				local t = start.t_grid[row][col]
				if t.skip ~= 1 then
					local charData = start.f_selGrid(cellIndex)
					--draw random cell
					if charData and (charData.char == 'randomselect' or charData.hidden == 3) then
						-- animSetPalFX(motif.select_info.cell_random_data, {
						-- 	time = 1,
						-- 	add = trials.trials_mode.selscreenpalfx_add,
						-- 	mul = trials.trials_mode.selscreenpalfx_mul,
						-- 	sinadd = trials.trials_mode.selscreenpalfx_sinadd,
						-- 	invertall = trials.trials_mode.selscreenpalfx_invertall,
						-- 	color = trials.trials_mode.selscreenpalfx_color
						-- })
					--draw face cell
					elseif charData and charData.char_ref ~= nil and charData.hidden == 0 and charData.trialsdef == "" then
						animSetPalFX(charData.cell_data, {
							time = -1,
							add = paladd,
							mul = palmul,
							sinadd = palsinadd,
							invertall = palinvertall,
							color = palcolor,
						})
						animUpdate(charData.cell_data)
					end
				end
			end
		end
	end
end

function trials.f_trialsMode()
	-- Value used for localcoord
	trials.lcdx00 = 1
	trials.lcdy00 = 1
	if trials.mtlcx == nil then
	trials.mtlcx = trials.trials_mode.trialslocalcoord[1]
					end
	if trials.mtlcy == nil then
	trials.mtlcy = trials.trials_mode.trialslocalcoord[2]
					end
	if stageVar('stageinfo.localcoord.x') ~= nil then
	trials.stlcx = stageVar('stageinfo.localcoord.x')
if trials.mtlcx ~= trials.stlcx then
	trials.lcdx00 = trials.mtlcx / trials.stlcx
					end
					end
	if stageVar('stageinfo.localcoord.y') ~= nil then
	trials.stlcy = stageVar('stageinfo.localcoord.y')
if trials.mtlcy ~= trials.stlcy then
	trials.lcdy00 = trials.mtlcy / trials.stlcy
					end
					end
					
	if roundStart() then
		trials.data = nil
		-- Empty the trials list back to the items the section declared.
		if trials.listNode ~= nil and trials.listTail ~= nil then
			trials.listNode.items = trials.listTail
			trials.listNode.item = 1
			trials.listNode.cursorPosY = 1
			trials.listNode.moveTxt = 0
		end
		trials.p1selref = nil
		trials.charPortraitSff = nil
		trialsanim = nil
		if trials.trials_mode.textbox.portrait.anim ~= nil then
		animReset(trials.trials_mode.textbox.portrait.anim)
					end
		-- Check if there's a trials file - if so, parse it
		if start.f_getCharData(start.p[1].t_selected[1].ref).trialsdef ~= "" then
			trials.f_inittrialsData()
			trialsExist = true
 		else
			trialsExist = false
		end
	end

	if trials.p1selref == nil then
		if start.p[1].t_selected[1].ref ~= nil then
			trials.p1selref = start.p[1].t_selected[1].ref
		end
	end
					
	if trialsExist and roundState() == 2 and not trials.data.trialsInitialized then
		-- Initialize the trials based on parsed file and char state at roundState() == 2
		trials.f_trialsBuilder()
		menu.f_trialsReset()
	elseif trialsExist and roundState() == 2 and trials.data.trialsInitialized then
		-- If trials initialized, draw elements and check for success!
		trials.f_trialsDrawer()
		player(1)
		trials.f_trialsChecker('root')
		if numHelper() > 0 and trials.draw.success == 0 then
			for i = 1, numHelper(), 1 do
				trials.f_trialsChecker(i)
			end
		end
		player(1)
	elseif roundState() == 2 then
		-- No trials present!
		player(2)
		setAILevel(0)
		mapSet('_iksys_trialsSetLife', lifeMax())
		player(1)
		mapSet('_iksys_trialsDummyControl', 0)
		mapSet('_iksys_trialsSetLife', lifeMax())
		if trials.notrialscounter == nil then
			trials.notrialscounter = f_newText(trials.trials_mode.trialcounter)
		end
		trials.notrialscounter:update({x = trials.trials_mode.trialcounter_pos[1], y = trials.trials_mode.trialcounter_pos[2], text = trials.trials_mode.trialcounter_notrialsdata_text})
		trials.notrialscounter:draw()
	end
end

--;===========================================================
--; menu.lua
--;===========================================================

if menu.trialadvancement == nil then
	menu.trialadvancement = 1
end
if menu.trialresetonsuccess == nil then
	menu.trialresetonsuccess = 1
end
if menu.trialslayout == nil then
	menu.trialslayout = 1
end
if menu.trialstextboxes == nil then
	menu.trialstextboxes = 1
end

local pmv = motif.pause_menu ~= nil and motif.pause_menu.trials_pause_menu ~= nil and motif.pause_menu.trials_pause_menu.menu.valuename or {}

menu.t_valuename.trialadvancement = {
	{itemname = "autoadvance", displayname = pmv.trialadvancement_autoadvance or "Auto-Advance"},
	{itemname = "repeat", displayname = pmv.trialadvancement_repeat or "Repeat"}
}
menu.t_valuename.trialresetonsuccess = {
	{itemname = "enabled", displayname = pmv.trialresetonsuccess_enabled or "Yes"},
	{itemname = "disabled", displayname = pmv.trialresetonsuccess_disabled or "No"}
}
menu.t_valuename.trialslayout = {
	{itemname = "vertical", displayname = pmv.trialslayout_vertical or "Vertical"},
	{itemname = "horizontal", displayname = pmv.trialslayout_horizontal or "Horizontal"}
}
menu.t_valuename.trialstextboxes = {
	{itemname = "show", displayname = pmv.trialstextboxes_show or "Show"},
	{itemname = "hide", displayname = pmv.trialstextboxes_hide or "Hide"}
}
-- Moves the match to one Trial and leaves the pause menu, the way its own Continue does.
-- Latching the fade is what actually repositions the pair: f_trialsFade sets
-- _iksys_trialsReposition, f_trialsDummySetup only sets life and dummy mode.
function trials.f_gotoTrial(index)
	if trials.data == nil or not trials.data.trialsInitialized or trials.data.trial[index] == nil then
		return true
	end
	trials.data.currenttrialstep = 1
	trials.data.currenttrialmicrostep = 1
	trials.data.comboCounter = 0
	trials.data.currenttrial = index
	trials.data.trial[index].complete = false
	trials.data.trial[index].active = false
	trials.data.active = false
	trials.data.displaytimers.totaltimer = false
	trials.data.trial[index].starttick = roundTime()
	trials.draw.fadein = trials.trials_mode.fadein_time
	trials.draw.fadeout = trials.trials_mode.fadeout_time
	trials.draw.fade = trials.draw.fadein + trials.draw.fadeout
	trials.draw.fadetriggered = true
	menu.currentMenu[1] = menu.currentMenu[2]
	menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
	return false
end

menu.t_itemname['trialsentry'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return trials.f_gotoTrial(t.items[item].trial)
	end
	return true
end

menu.t_itemname['trialadvancement'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if trials.data ~= nil then
			if value == "autoadvance" then
				trials.data.trialadvancement = true
			else
				trials.data.trialadvancement = false
			end
		end
		trials.f_savePref('Advancement', value)
	end
	return true
end
menu.t_vardisplay['trialadvancement'] = function()
	return menu.t_valuename.trialadvancement[menu.trialadvancement or 1].displayname
end

options.t_vardisplay['trialadvancement'] = function()
	return menu.t_valuename.trialadvancement[menu.trialadvancement or 1].displayname
end

menu.t_itemname['trialslayout'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "vertical" then
			trials.trials_mode.trialslayout = "vertical"
		else
			trials.trials_mode.trialslayout = "horizontal"
		end
		trials.f_savePref('Layout', trials.trials_mode.trialslayout)
	end
	return true
end
menu.t_vardisplay['trialslayout'] = function()
	return menu.t_valuename.trialslayout[menu.trialslayout or 1].displayname
end

options.t_vardisplay['trialslayout'] = function()
	return menu.t_valuename.trialslayout[menu.trialslayout or 1].displayname
end

menu.t_itemname['trialresetonsuccess'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "enabled" then
			trials.trials_mode.trialsresetonsuccess = true
		else
			trials.trials_mode.trialsresetonsuccess = false
		end
		trials.f_savePref('ResetOnSuccess', trials.trials_mode.trialsresetonsuccess)
	end
	return true
end
menu.t_vardisplay['trialresetonsuccess'] = function()
	return menu.t_valuename.trialresetonsuccess[menu.trialresetonsuccess or 1].displayname
end

options.t_vardisplay['trialresetonsuccess'] = function()
	return menu.t_valuename.trialresetonsuccess[menu.trialresetonsuccess or 1].displayname
end

menu.t_itemname['trialstextboxes'] = function(t, item, cursorPosY, moveTxt, sec)
	local changed, value = menu.f_valueChanged(t.items[item], sec)
	if changed then
		if value == "show" then
			trials.trials_mode.textbox_visible = true
		else
			trials.trials_mode.textbox_visible = false
		end
		trials.trials_mode.textbox.visible = trials.trials_mode.textbox_visible
		trials.f_savePref('Textboxes', value)
	end
	return true
end
menu.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end

options.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end


menu.t_itemname['nexttrial'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and trials.data ~= nil and #trials.data.trial > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return trials.f_gotoTrial(trials.data.currenttrial % #trials.data.trial + 1)
	end
	return true
end

menu.t_itemname['previoustrial'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, sec.menu.done.key) and trials.data ~= nil and #trials.data.trial > 0 then
		sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
		return trials.f_gotoTrial((trials.data.currenttrial - 2) % #trials.data.trial + 1)
	end
	return true
end

local t_trialsPrefs = {
	trialadvancement = true,
	trialresetonsuccess = true,
	trialslayout = true,
	trialstextboxes = true,
}

function menu.f_trialsReset()
	if tostring(opts.Advancement or 'autoadvance'):lower() == 'autoadvance' then
		menu.trialadvancement = 1
	else
		menu.trialadvancement = 2
	end
	if (opts.ResetOnSuccess ~= nil and opts.ResetOnSuccess ~= false)
		or (opts.ResetOnSuccess == nil and trials.trials_mode.trialsresetonsuccess == true) then
		menu.trialresetonsuccess = 1
	else
		menu.trialresetonsuccess = 2
	end
	if tostring(opts.Layout or trials.trials_mode.trialslayout):lower() == "vertical" then
		menu.trialslayout = 1
	else
		menu.trialslayout = 2
	end
	if (opts.Textboxes ~= nil and tostring(opts.Textboxes):lower() ~= "hide")
		or (opts.Textboxes == nil and trials.trials_mode.textbox_visible == true) then
		menu.trialstextboxes = 1
	else
		menu.trialstextboxes = 2
	end
	for _, v in ipairs(menu.t_vardisplayPointers) do
		if t_trialsPrefs[v.itemname] then
			v.vardisplay = menu.f_vardisplay(v.itemname)
		end
	end
	player(2)
	setAILevel(0)
	mapSet('_iksys_trialsDummyControl', 0)
	mapSet('_iksys_trialsDummyMode', 0)
	mapSet('_iksys_trialsGuardMode', 0)
	mapSet('_iksys_trialsFallRecovery', 0)
	mapSet('_iksys_trialsDistance', 0)
	mapSet('_iksys_trialsButtonJam', 0)
	mapSet('_iksys_trialsReposition', 0)
	mapSet('_iksys_trialsSetLife', lifeMax())
	player(1)
	mapSet('_iksys_trialsSetLife', lifeMax())
end

--;===========================================================
--; trials.lua
--;===========================================================

local function f_initTrialStepMicrosteps(step, count)
	if count == nil or count < 1 then
		return
	end
	if step.numofmicrosteps < count then
		step.numofmicrosteps = count
	end
	for k = 1, step.numofmicrosteps, 1 do
		if step.stephitscount[k] == nil then step.stephitscount[k] = 0 end
		if step.comboCountonstep[k] == nil then step.comboCountonstep[k] = 0 end
		if step.hitcount[k] == nil then step.hitcount[k] = 1 end
		if step.isthrow[k] == nil then step.isthrow[k] = false end
		if step.ishelper[k] == nil then step.ishelper[k] = false end
		if step.isproj[k] == nil then step.isproj[k] = false end
		if step.iscounterhit[k] == nil then step.iscounterhit[k] = false end
		if step.validforval[k] == nil then step.validforval[k] = nil end
		if step.validforvar[k] == nil then step.validforvar[k] = nil end
		if step.validfortickcount[k] == nil then step.validfortickcount[k] = nil end
		
		
		if step.iconanim[k] == nil then
		 step.iconanim = {0,0,0,0,-1}
		if trials.trials_mode.textbox.portrait.spr ~= nil then
		 step.iconanim = {trials.trials_mode.textbox.portrait.spr[1],trials.trials_mode.textbox.portrait.spr[2],0,0,-1}
		  end end
		if step.iconanimoffset[k] == nil then step.iconanimoffset = {0,0} end
		if step.iconanimscale[k] == nil then step.iconanimscale = {1,1} end
		if step.iconanimwindow[k] == nil then step.iconanimwindow = {0,0,0,0} end
	end
end

-- Find trials files and parse them; append t_selChars table
for row = 1, #main.t_selChars, 1 do
	if main.t_selChars[row].def ~= nil then
		main.t_selChars[row].trialsdef = ""
		local deffile = loadText(main.t_selChars[row].def)
		for line in deffile:gmatch("([^\r\n]*)[\r\n]?") do
			line = line:gsub('%s*;.*$', '')
			lcline = string.lower(line)
			if lcline:match('trials') then
				main.t_selChars[row].trialsdef = main.t_selChars[row].dir .. f_trimforchar(line, "=", "after")
				break
			end
		end
	end
	if  main.t_selChars[row].def ~= nil and main.t_selChars[row].trialsdef ~= "" then
		i = 0 --Trial number
		j = 0 --TrialStep number
		trial = {}
		local trialsFile = loadText(main.t_selChars[row].trialsdef)
		for line in trialsFile:gmatch("([^\r\n]*)[\r\n]?") do
			line = line:gsub('%s*;.*$', '')
			lcline = string.lower(line)

			if lcline:find("trialstep." .. j+1 .. ".") then
				j = j + 1
				trialsteplangfound = false
				trial[i].trialstep[j] = {
					numofmicrosteps = 1,
					text = "",
					glyphs = "",
					stateno = {},
					animno = {},
					hitcount = {},
					stephitscount = {},
					comboCountonstep = {},
					isthrow = {},
					ishelper = {},
					isproj = {},
					iscounterhit = {},
					validfortickcount = {},
					validforvar = {},
					validforval = {},
		iconanim = {},
		iconanimoffset ={},
		iconanimscale ={},
		iconanimwindow ={},
					glyphline = {
						vertical = {
							glyph = {},
							pos = {},
							width = {},
							alignOffset = {},
							lengthOffset = {},
							scale = {},
						},
						horizontal = {
							glyph = {},
							pos = {},
							width = {},
							alignOffset = {},
							lengthOffset = {},
							scale = {},
							
						},
					},
				}
			end 

			if line:match('^%s*%[.-%s*%]%s*$') then --matched [] group
				line = line:match('^%s*%[(.-)%s*%]%s*$') --match text between []
				lcline = string.lower(line)
				if lcline:match('^trialdef') then --matched trialdef block
					i = i + 1 -- increment Trial number
					j = 0 -- reset trialstep number
					triallangfound = false
					lang = gameOption('Config.Language'):lower()
					trial[i] = {
						name = "",
						dummymode = "stand",
						guardmode = "none",
						buttonjam = "none",
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
						trialstep = {},
					}
					temp = {}
					line = f_trimforchar(line, ",", "after")
					if line == "" then
						line = "Trial " .. tostring(i)
					end
					trial[i].name = line
				end
			elseif lcline:find("dummymode") then
				trial[i].dummymode = f_trimforchar(lcline, "=", "after")
			elseif lcline:find("guardmode") then
				trial[i].guardmode = f_trimforchar(lcline, "=", "after")
			elseif lcline:find("dummybuttonjam") then
				trial[i].buttonjam = f_trimforchar(lcline, "=", "after")
			elseif lcline:find("playerlife") then
				trial[i].p1life = tonumber(f_trimforchar(lcline, "=", "after"))
			elseif lcline:find("dummylife") then
				trial[i].p2life = tonumber(f_trimforchar(lcline, "=", "after"))
			elseif lcline:find("playerposoffset") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].playerposoffset = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("dummyposoffset") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].dummyposoffset = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("playerpos") then
				trial[i].playerpos = f_trimforchar(lcline, "=", "after")
			elseif lcline:find("dummypos") then
				trial[i].dummypos = f_trimforchar(lcline, "=", "after")
			elseif lcline:find("showforvarvalpairs") then
				showforvarvalpairsfound = false
				temp = main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", ""))
				trial[i].showforvar = {}
				trial[i].showforval = {}
				for k = 1, #temp, 2 do
					trial[i].showforvar[#trial[i].showforvar+1] = tonumber(temp[k])
					trial[i].showforval[#trial[i].showforval+1] = f_str2number(main.f_strsplit('|', temp[k+1]))
				end
			elseif lcline:find("textbox") and not triallangfound then
				if lcline:find("textbox." .. lang) then
					trial[i].textbox = f_trimforchar(lcline, "=", "after")
					triallangfound = true
				elseif string.match(lcline, "trial.textbox.en") then
					trial[i].textbox = f_trimforchar(lcline, "=", "after")
				elseif string.match(f_trimforchar(lcline, "=", "before"), "^trial.textbox$") then
					trial[i].textbox = f_trimforchar(lcline, "=", "after")
					triallangfound = true
				end
			elseif lcline:find("trialstep." .. j .. ".text") and not trialsteplangfound then
				if lcline:find("trialstep." .. j .. ".text." .. lang) then
					trial[i].trialstep[j].text = f_trimforchar(line, "=", "after")
					trialsteplangfound = true
				elseif string.match(lcline, "trialstep." .. j .. ".text.en") then
					trial[i].trialstep[j].text = f_trimforchar(line, "=", "after")
				elseif string.match(f_trimforchar(lcline, "=", "before"), "^trialstep." .. j .. ".text$") then
					trial[i].trialstep[j].text = f_trimforchar(line, "=", "after")
					trialsteplangfound = true
				end
				trial[i].trialstep[j].text = f_trimforchar(line, "=", "after")
			elseif lcline:find("trialstep." .. j .. ".glyphs") then
				trial[i].trialstep[j].glyphs = f_trimforchar(line, "=", "after")
			elseif lcline:find("trialstep." .. j .. ".stateno") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].stateno = main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", ""))
					for k = 1, #trial[i].trialstep[j].stateno, 1 do
						local temp = trial[i].trialstep[j].stateno[k]
						trial[i].trialstep[j].stateno[k] = f_str2number(main.f_strsplit('|', temp))
					end
					f_initTrialStepMicrosteps(trial[i].trialstep[j], #trial[i].trialstep[j].stateno)
				end
			elseif lcline:find("trialstep." .. j .. ".animno") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].animno = main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", ""))
					for k = 1, #trial[i].trialstep[j].animno, 1 do
						local temp = trial[i].trialstep[j].animno[k]
						trial[i].trialstep[j].animno[k] = f_str2number(main.f_strsplit('|', temp))
					end
					f_initTrialStepMicrosteps(trial[i].trialstep[j], #trial[i].trialstep[j].animno)
				end
			elseif lcline:find("trialstep." .. j .. ".hitcount") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].hitcount = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".isthrow") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].isthrow = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iscounterhit") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].iscounterhit = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".ishelper") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].ishelper = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".isproj") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].isproj = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".validforvarvalpairs") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					local varvalpairs = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
					for ii = 1, #varvalpairs, 2 do
						trial[i].trialstep[j].validforvar[ii] = varvalpairs[ii]
						trial[i].trialstep[j].validforval[ii] = varvalpairs[ii+1]
					end
				end
			elseif lcline:find("trialstep." .. j .. ".validfortickcount") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].validfortickcount = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iconanimoffset") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].iconanimoffset = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iconanimscale") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].iconanimscale = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iconanimwindow") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].iconanimwindow = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iconanim") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].iconanim = f_str2number(main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "")))
				end
			end
		end
		main.t_selChars[row].trialsdata = trial
	end
end

--;===========================================================
--; global.lua
--;===========================================================
hook.add("loop#trials", "f_trialsMode", trials.f_trialsMode)
hook.add("start.f_selectScreen", "f_trialsSelectScreen", trials.f_trialsSelectScreen)

hook.add("menu.menu.loop", "f_trialsListMark", function()
	local sub = trials.listNode
	if not gameMode('trials') or trials.data == nil or type(sub) ~= 'table' then
		return
	end
	for _, item in ipairs(sub.items) do
		item.selected = item.trial == trials.data.currenttrial
	end
end)
