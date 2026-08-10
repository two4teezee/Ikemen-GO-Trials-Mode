-- IKEMEN GO TRIALS MODE EXTERNAL MODULE --------------------------------
-- Last tested on Ikemen GO v1.0.0-nightly-20260124 - Jan 24, 2026
-- Module developed by two4teezee
-------------------------------------------------------------------------
-- This external module implements TRIALS game mode. Features full 
-- screenpack integration via config.def and system.def, ability to create
-- and read trials definitions for any character, and a trials menu option. 
-- Documentation on how to create trials definitions and use trials mode is 
-- in README.md.
-------------------------------------------------------------------------
--Set Common Module Files Path & Auto-Load ZSS Module
--Author: Cable Dorado 2 (CD2)
local modulePath = "external/mods/trials/"

local zss = gameOption("Common.States")
table.insert(zss, modulePath.."trials.zss")
modifyGameOption("Common.States", zss)
------------------------------------------------------------------------------------
trials = {}
trials = loadIni('external/mods/trials/config.def')
trials.sprData = {}

motif = loadMotif()
motif.files.spr_data = sffNew(motif.files.spr)
motif.files.snd_data = sndNew(motif.files.snd)

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

local function f_deepCopy(orig)
	-- copies a table into a local instance that can be modified freely
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[f_deepCopy(orig_key)] = f_deepCopy(orig_value)
        end
        setmetatable(copy, f_deepCopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
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

--split strings
local function f_strsplit(delimiter, text)
	local list = {}
	local pos = 1
	if string.find('', delimiter, 1) then
		if string.len(text) == 0 then
			table.insert(list, text)
		else
			for i = 1, string.len(text) do
				table.insert(list, string.sub(text, i, i))
			end
		end
	else
		while true do
			local first, last = string.find(text, delimiter, pos)
			if first then
				table.insert(list, string.sub(text, pos, first - 1))
				pos = last + 1
			else
				table.insert(list, string.sub(text, pos))
				break
			end
		end
	end
	return list
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
	t.defsc = t.defsc or false
		if t.ti == nil then
	t.ti = textImgNew()
		end
	setmetatable(t, self)
	self.__index = self
	if t.font ~= -1 then
		if main.font_def == nil then
			main.font_def = fontGetDef(main.font[t.font])
		end
		if main.font_def[font] == nil then
			main.font_def = fontGetDef(main.font[t.font])
		end
		textImgSetFont(t.ti, main.font[t.font])
	end
		textImgSetLocalcoord(t.ti, trials.mtlcx, trials.mtlcy)
	textImgSetBank(t.ti, t.bank)
	textImgSetAlign(t.ti, t.align)
	textImgSetText(t.ti, t.text)
	textImgSetColor(t.ti, t.r, t.g, t.b, t.a)
	if t.defsc then disableLuaScale() end
	textImgSetPos(t.ti, t.x + f_alignOffset(t.align), t.y)
	textImgSetScale(t.ti, t.scaleX, t.scaleY)
	textImgSetWindow(t.ti, t.window[1], t.window[2], t.window[3] - t.window[1], t.window[4] - t.window[2])
	textImgSetXShear(t.ti, t.xshear)
	textImgSetAngle(t.ti, t.angle)
	if t.defsc then setLuaScale() end
	return t
end

text.new = text.create

--align text
function text:setAlign(align)
	if align:lower() == "left" then
		self.align = -1
	elseif align:lower() == "center" or align:lower() == "middle" then
		self.align = 0
	elseif align:lower() == "right" then
		self.align = 1
	end
	textImgSetAlign(self.ti,self.align)
	return self
end

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
		if fontChange and self.font ~= -1 then
		if main.font_def == nil then
			main.font_def = fontGetDef(main.font[self.font])
		end
		if main.font_def[font] == nil then
			main.font_def = fontGetDef(main.font[self.font])
		end
		textImgSetFont(self.ti, main.font[self.font])
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
		--if self.defsc then disableLuaScale() end
		textImgSetPos(self.ti, self.x + f_alignOffset(self.align), self.y)
		textImgSetScale(self.ti, self.scaleX, self.scaleY)
		textImgSetWindow(self.ti, self.window[1], self.window[2], self.window[3] - self.window[1], self.window[4] - self.window[2])
		textImgSetXShear(self.ti, self.xshear)
		textImgSetAngle(self.ti, self.angle)
		--if self.defsc then setLuaScale() end
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
		textImgSetLocalcoord(self.ti, trials.mtlcx, trials.mtlcy)
		textImgSetText(self.ti, self.text)
	textImgDraw(self.ti)
	return self
end

--create textImg based on usual motif parameters
function f_createTextImg(t, prefix, mod)
	local mod = mod or {}
	if t[prefix] == nil then
	t[prefix] = {}
	end
	if t[prefix]['font'] == nil then t[prefix]['font'] = {-1} end
	if t[prefix]['offset'] == nil then t[prefix]['offset'] = {0,0} end
	if t[prefix]['scale'] == nil then t[prefix]['scale'] = {1,1} end
	
		x =      (t[prefix]['offset'][1] or 0) + (mod.x or 0)
		y =      (t[prefix]['offset'][2] or 0) + (mod.y or 0)
		scaleX = (t[prefix]['scale'][1] or 1) * (mod.scaleX or 1)
		scaleY = (t[prefix]['scale'][2] or 1) * (mod.scaleY or 1)
	if t[prefix]['pos'] ~= nil then
	x = t[prefix]['pos'][1]
	y = t[prefix]['pos'][2]
	end
	if t[prefix]['scale'] ~= nil then
	scaleX = t[prefix]['scale'][1]
	scaleY = t[prefix]['scale'][2]
	end
	
	return text:create({
		font =   t[prefix]['font'][1],
		bank =   t[prefix]['font'][2],
		align =  t[prefix]['font'][3],
		text =   t[prefix .. '.text'],
		x =      x,
		y =      y,
		scaleX = scaleX,
		scaleY = scaleY,
		r =     t[prefix]['font'][4],
		g =     t[prefix]['font'][5],
		b =     t[prefix]['font'][6],
		a =     t[prefix]['font'][7],
		height =t[prefix]['font'][8],
		xshear = t[prefix .. '.xshear'] or 0,
		angle  = t[prefix .. '.angle'] or 0,
		window = t[prefix .. '.window'],
		defsc = mod.defsc or false,
	})
end


function f_alignOffset(align)
	if align == -1 then
		return 1
	end
	return 0
end

--creates sprite data out of table values
local facing = ''
local function f_getSprNode(t, path)
	if type(t) ~= 'table' then
		return nil
	end
	local node = t
	local normalized = path:gsub('[_%.]$', ''):gsub('_', '.')
	for part in normalized:gmatch('[^%.]+') do
		if type(node) ~= 'table' then
			return nil
		end
		node = node[part]
	end
	if type(node) ~= 'table' then
		return nil
	end
	return node
end

function f_loadSprData(t, v, sff)
	local data = v.s .. 'data'
	local sprData = sff or motif.files.spr_data
	local node = f_getSprNode(t, v.s) or {}
	local offset = type(node.offset) == 'table' and node.offset or {0, 0}
	local scale = type(node.scale) == 'table' and node.scale or {1.0, 1.0}
	local animNo = node.anim
	local spr = node.spr
	local facingNo = node.facing
	if v.prefix ~= nil then
		data = v.s .. v.prefix .. 'data'
		if type(node[v.prefix]) == 'table' then
			node = node[v.prefix]
			offset = type(node.offset) == 'table' and node.offset or offset
			scale = type(node.scale) == 'table' and node.scale or scale
			animNo = node.anim
			spr = node.spr
			facingNo = node.facing
		end
	end
	if facingNo == nil then facingNo = 1 end
	if type(animNo) == 'number' and animNo ~= -1 and type(motif.anim) == 'table' and motif.anim[animNo] ~= nil then --create animation data
		t[data] = f_animFromTable(
			motif.anim[animNo],
			sprData,
			(offset[1] + (v.x or 0)) / scale[1],
			(offset[2] + (v.y or 0)) / scale[2],
			scale[1],
			scale[2],
			facingNo
		)
	else
		if type(spr) == 'string' then
			if spr == '' then
				spr = nil
			else
				spr = {tonumber(spr:match('^([0-9]+)')), 0}
			end
		end
	end
	if type(spr) == 'table' and #spr > 0 then --create sprite data
		if #spr == 1 then --fix values
			if type(spr[1]) == 'string' then
				spr = {tonumber(spr[1]:match('^([0-9]+)')), 0}
			else
				spr = {spr[1], 0}
			end
		end
		if facingNo == -1 then facing = ', H' else facing = '' end
		t[data] = animNew(sprData, spr[1] .. ', ' .. spr[2] .. ', ' .. (offset[1] + (v.x or 0)) / scale[1] .. ', ' .. (offset[2] + (v.y or 0)) / scale[2] .. ', -1' .. facing)
		animSetScale(t[data], scale[1], scale[2])
		animUpdate(t[data])
	else --create dummy data
		t[data] = animNew(sprData, '-1,0, 0,0, -1')
		animUpdate(t[data])
	end
	animSetWindow(t[data], 0, 0, motif.info.localcoord[1], motif.info.localcoord[2])
end

--generate anim from table
local function f_animFromTable(t, sff, x, y, scaleX, scaleY, facing, infFrame, defsc)
	local t = t or {}
	local x = x or 0
	local y = y or 0
	local scaleX = scaleX or 1.0
	local scaleY = scaleY or 1.0
	local facing = facing or '0'
	local infFrame = infFrame or 1
	local facing_sav = ''
	local animText = ''
	local length = 0
	for i = 1, #t do
		local t_anim = {}
		for j, c in ipairs(f_strsplit(',', t[i])) do --split using "," delimiter
			table.insert(t_anim, c)
		end
		if #t_anim > 1 then
			--required parameters
			t_anim[3] = tonumber(t_anim[3]) + x
			t_anim[4] = tonumber(t_anim[4]) + y
			if tonumber(t_anim[5]) == -1 then
				length = length + infFrame
			else
				length = length + tonumber(t_anim[5])
			end
			--optional parameters
			if t_anim[6] ~= nil and not t_anim[6]:match(facing) then --flip parameter not negated by repeated flipping
				if t_anim[6]:match('[Hh]') then t_anim[3] = t_anim[3] + 1 end --fix for wrong offset after flipping sprites
				if t_anim[6]:match('[Vv]') then t_anim[4] = t_anim[4] + 1 end --fix for wrong offset after flipping sprites
				t_anim[6] = facing .. t_anim[6]
			end
		end
		for j = 1, #t_anim do
			if j == 1 then
				animText = animText .. t_anim[j]
			else
				animText = animText .. ', ' .. t_anim[j]
			end
		end
		anim = anim .. '\n'
	end
	if defsc then disableLuaScale() end
	if animText == '' then
		animText = '-1,0, 0,0, -1'
	end
	local data = animNew(sff, animText)
	animSetScale(data, scaleX, scaleY)
	animUpdate(data)
	if defsc then setLuaScale() end
	return data, length
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

-- -- This code creates data out of optional [trialsbgdef] sff file.
-- -- Defaults to motif.files.spr_data, defined in screenpack, if not declared.
-- if motif.trialsbgdef.spr ~= nil and motif.trialsbgdef.spr ~= '' then
-- 	motif.trialsbgdef.spr = searchFile(motif.trialsbgdef.spr, {motif.fileDir, '', 'data/'})
-- 	motif.trialsbgdef.spr_data = sffNew(motif.trialsbgdef.spr)
-- else
-- 	motif.trialsbgdef.spr = motif.files.spr
-- 	motif.trialsbgdef.spr_data = motif.files.spr_data
-- end

-- -- Background data generation.
-- -- Refer to official Elecbyte docs for information how to define backgrounds.
-- -- http://www.elecbyte.com/mugendocs/bgs.html#description-of-background-elements
-- motif.trialsbgdef.bg = bgNew(motif.trialsbgdef.spr_data, motif.def, 'trialsbg')

--trials spr/anim data
local tr_pos = trials.trials_mode
for _, v in ipairs({
	{s = 'trialsteps_vertical_bg_',				x = tr_pos.trialsteps.vertical.pos[1] + tr_pos.trialsteps.vertical.bg.offset[1],		y = tr_pos.trialsteps.vertical.pos[2] + tr_pos.trialsteps.vertical.bg.offset[2],		},
	{s = 'trialsteps_horizontal_bg_',			x = tr_pos.trialsteps.horizontal.pos[1] + tr_pos.trialsteps.horizontal.bg.offset[1],	y = tr_pos.trialsteps.horizontal.pos[2] + tr_pos.trialsteps.horizontal.bg.offset[2],	},
	{s = 'success_bg_',    						x = tr_pos.success.pos[1] + tr_pos.success.bg.offset[1],								y = tr_pos.success.pos[2] + tr_pos.success.bg.offset[2],								},
	{s = 'allclear_bg_',	   					x = tr_pos.allclear.pos[1] + tr_pos.allclear.bg.offset[1],								y = tr_pos.allclear.pos[2] + tr_pos.allclear.bg.offset[2],								},
	{s = 'textbox_bg_',	   						x = tr_pos.textbox.pos[1] + tr_pos.textbox.bg.offset[1],								y = tr_pos.textbox.pos[2] + tr_pos.textbox.bg.offset[2],								},
	{s = 'success_front_',  	  				x = tr_pos.success.pos[1] + tr_pos.success.front.offset[1],								y = tr_pos.success.pos[2] + tr_pos.success.front.offset[2],								},
	{s = 'allclear_front_',   					x = tr_pos.allclear.pos[1] + tr_pos.allclear.front.offset[1],							y = tr_pos.allclear.pos[2] + tr_pos.allclear.front.offset[2],							},
	{s = 'textbox_front_',	   					x = tr_pos.textbox.pos[1] + tr_pos.textbox.front.offset[1],								y = tr_pos.textbox.pos[2] + tr_pos.textbox.front.offset[2],								},
	{s = 'upcomingstep_vertical_bg_',			x = 0,																					y = 0,																					},
	{s = 'upcomingstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
	{s = 'upcomingstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
	{s = 'currentstep_vertical_bg_',			x = 0,																					y = 0,																					},
	{s = 'currentstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
	{s = 'currentstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
	{s = 'completedstep_vertical_bg_',			x = 0,																					y = 0,																					},
	{s = 'completedstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
	{s = 'completedstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
    {s = 'upcomingstep_horizontal_bg_',			x = 0,																					y = 0,																					},
	{s = 'upcomingstep_horizontal_bg_tail_',	x = 0,																					y = 0,																					},
	{s = 'upcomingstep_horizontal_bg_head_',	x = 0,																					y = 0,																					},
	{s = 'currentstep_horizontal_bg_',			x = 0,																					y = 0,																					},
	{s = 'currentstep_horizontal_bg_tail_',		x = 0,																					y = 0,																					},
	{s = 'currentstep_horizontal_bg_head_',		x = 0,																					y = 0,																					},
	{s = 'completedstep_horizontal_bg_',		x = 0,																					y = 0,																					},
	{s = 'completedstep_horizontal_bg_tail_',	x = 0,																					y = 0,																					},
	{s = 'completedstep_horizontal_bg_head_',	x = 0,																					y = 0,																					},
	{s = 'trialtitle_vertical_bg_',    			x = tr_pos.trialtitle.vertical.pos[1] + tr_pos.trialtitle.vertical.bg.offset[1],		y = tr_pos.trialtitle.vertical.pos[2] + tr_pos.trialtitle.vertical.bg.offset[2],		},
	{s = 'trialtitle_vertical_front_',    		x = tr_pos.trialtitle.vertical.pos[1] + tr_pos.trialtitle.vertical.front.offset[1],		y = tr_pos.trialtitle.vertical.pos[2] + tr_pos.trialtitle.vertical.front.offset[2],		},
    {s = 'trialtitle_horizontal_bg_',    		x = tr_pos.trialtitle.horizontal.pos[1] + tr_pos.trialtitle.horizontal.bg.offset[1],	y = tr_pos.trialtitle.horizontal.pos[2] + tr_pos.trialtitle.horizontal.bg.offset[2],	},
	{s = 'trialtitle_horizontal_front_',    	x = tr_pos.trialtitle.horizontal.pos[1] + tr_pos.trialtitle.horizontal.front.offset[1],	y = tr_pos.trialtitle.horizontal.pos[2] + tr_pos.trialtitle.horizontal.front.offset[2],	},
}) do
	if main.f_fileExists('external/mods/trials/trials.sff') then
		motif.files.data = sffNew(searchFile('external/mods/trials/trials.sff', {motif.fileDir, '', 'data/'}))
	 	main.f_loadingRefresh()
	 	f_loadSprData(trials.trials_mode, v, motif.files.data)
	else
		f_loadSprData(trials.trials_mode, v)
	end
end

if trials.trials_mode.textbox.portrait.source == "system" and trials.trials_mode.textbox.portrait.spr ~= nil then
	f_loadSprData(trials.trials_mode, {s = 'textbox.portrait_', x = trials.trials_mode.textbox.pos[1] + trials.trials_mode.textbox.portrait.offset[1], y = trials.trials_mode.textbox.pos[2] + trials.trials_mode.textbox.portrait.offset[2]})
end

-- fadein/fadeout anim data generation.
if trials.trials_mode.fadein.anim ~= -1 then
	f_loadSprData(trials.trials_mode, {s = 'fadein.'})
end
if trials.trials_mode.fadeout.anim ~= -1 then
	f_loadSprData(trials.trials_mode, {s = 'fadeout.'})
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
		trial = f_deepCopy(start.f_getCharData(start.p[1].t_selected[1].ref).trialsdata),
		bgelemdata = {
			vertical = {},
			horizontal = {},
		},
		draw = {},
		displaytimers = {
			totaltimer = true,
			trialtimer = true,
		},
	}

	-- Initialize trialadvancement based on last-left menu value
	if menu.t_valuename.trialadvancement[menu.trialadvancement or 1].itemname == "Auto-Advance" then
		trials.data.trialadvancement = true
	else
		trials.data.trialadvancement = false
	end
end

function trials.f_trialsBuilder()
	--This function will initialize once to build all the trial tables based on the motif information and the trials information loaded when the char was selected
	--Populate background elements information
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep_','upcomingstep_','completedstep_'}) do
			trials.data.bgelemdata[v][k .. 'bgsize'] = animGetSpriteInfo(trials.trials_mode[k .. v .. '_bg_data'])
			if v == 'horizontal' then
				trials.data.bgelemdata[v][k .. 'bgtailwidth'] = animGetSpriteInfo(trials.trials_mode[k .. v .. '_bg_tail_data'])
				trials.data.bgelemdata[v][k .. 'bgheadwidth'] = animGetSpriteInfo(trials.trials_mode[k .. v .. '_bg_head_data'])
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
				local font_def = 0
				--Some fonts won't give us the data we need to scale glyphs from, but sometimes that doesn't matter anyway
				if layout == "vertical" and trials.trials_mode.currentstep.vertical.text.font[7] == nil and trials.trials_mode.glyphs.vertical.scalewithtext == "true" then
					font_def = main.font_def[trials.trials_mode.currentstep.vertical.text.font[1] .. trials.trials_mode.currentstep.vertical.text.font.height]
				elseif layout == "vertical" and trials.trials_mode.glyphs.vertical.scalewithtext == "true" then
					font_def = main.font_def[trials.trials_mode.currentstep.vertical.text.font[1] .. trials.trials_mode.currentstep.vertical.text.font[7]]
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
						if layout == "vertical" and trials.trials_mode.glyphs.vertical.scalewithtext == "true" then
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
		textbox_text = f_createTextImg(trials.trials_mode.textbox, 'text'),
		textbox_title = f_createTextImg(trials.trials_mode.textbox, 'title'),
		success_text = f_createTextImg(trials.trials_mode.success, 'text'),
		allclear = math.max(animGetLength(trials.trials_mode.allclear_front_data), animGetLength(trials.trials_mode.allclear_bg_data), trials.trials_mode.allclear.text.displaytime),
		allclear_text = f_createTextImg(trials.trials_mode.allclear, 'text'),
		trialcounter = f_createTextImg(trials.trials_mode, 'trialcounter'),
		totaltrialtimer = f_createTextImg(trials.trials_mode, 'totaltrialtimer'),
		currenttrialtimer = f_createTextImg(trials.trials_mode, 'currenttrialtimer'),
		trialreset_text = f_createTextImg(trials.trials_mode.trialreset, 'text'),
	}
	for _, v in ipairs({'vertical','horizontal'}) do
		trials.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			trialtitle = math.max(animGetLength(trials.trials_mode['trialtitle_' .. v .. '_front_data']), animGetLength(trials.trials_mode['trialtitle_' .. v .. '_bg_data'])),
			--trialtitle = 100,
			trialtitle_text = f_createTextImg(trials.trials_mode, 'trialtitle.' .. v .. '.text'),
			windowXrange = trials.trials_mode.trialsteps[v].window.withouttextbox[3] - trials.trials_mode.trialsteps[v].window.withouttextbox[1],
			windowYrange = trials.trials_mode.trialsteps[v].window.withouttextbox[4] - trials.trials_mode.trialsteps[v].window.withouttextbox[2],
			windowXrangeWtext = trials.trials_mode.trialsteps[v].window.withtextbox[3] - trials.trials_mode.trialsteps[v].window.withtextbox[1],
			windowYrangeWtext = trials.trials_mode.trialsteps[v].window.withtextbox[4] - trials.trials_mode.trialsteps[v].window.withtextbox[2],
		}
		trials.draw[v].trialtitle_text:update({x = trials.trials_mode.trialtitle[v].pos[1]+trials.trials_mode.trialtitle[v].text.offset[1], y = trials.trials_mode.trialtitle[v].pos[2]+trials.trials_mode.trialtitle[v].text.offset[2],})
		for i = 1, trials.data.maxsteps, 1 do
			trials.draw[v].upcomingtextline[i] = f_createTextImg(trials.trials_mode.upcomingstep[v], 'text')
			trials.draw[v].currenttextline[i] = f_createTextImg(trials.trials_mode.currentstep[v], 'text')
			trials.draw[v].completedtextline[i] = f_createTextImg(trials.trials_mode.completedstep[v], 'text')
		end
	end

	-- Build list out all of the available trials for Pause menu
	menu.t_valuename.trialslist = {}
	for i = 1, #trials.data.trial, 1 do
		table.insert(menu.t_valuename.trialslist, {itemname = tostring(i), displayname = trials.data.trial[i].name})
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

function trials.f_trialsDrawer()
	if trials.data.trialsInitialized and roundState() == 2 and not trials.data.active and trials.draw.fade == 0 then
		trials.f_trialsDummySetup()
		trials.data.active = true
	end

	-- Check if game is paused - if so, set pause menu loop
	-- if paused() and not trials.data.trialsPaused then
	-- trials.data.trialsPaused = true
	-- menu.currentMenu = {menu.trials.loop, menu.trials.loop}
	-- elseif not paused() then
	-- trials.data.trialsPaused = false
	-- end

	if paused() and not trials.data.trialsPaused then
		trials.data.trialsPaused = true
		-- menu.currentMenu = {menu.trials.loop, menu.trials.loop}
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
			if menu.trialreset == 1 then
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
				animSetLocalcoord(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'], trials.mtlcx, trials.mtlcy)
			animUpdate(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'])
			animDraw(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'])
				animSetLocalcoord(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'], trials.mtlcx, trials.mtlcy)
			animUpdate(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'])
			animDraw(trials.trials_mode['trialsteps_' .. layout .. '_bg_data'])

			-- Draw trial title
				animSetLocalcoord(trials.trials_mode['trialtitle_' .. layout .. '_bg_data'], trials.mtlcx, trials.mtlcy)
			animUpdate(trials.trials_mode['trialtitle_' .. layout .. '_bg_data'])
			animDraw(trials.trials_mode['trialtitle_' .. layout .. '_bg_data'])
			trials.draw[layout].trialtitle_text:update({text = trials.data.trial[ct].name})
			trials.draw[layout].trialtitle_text:draw()
				animSetLocalcoord(trials.trials_mode['trialtitle_' .. layout .. '_front_data'], trials.mtlcx, trials.mtlcy)
			animUpdate(trials.trials_mode['trialtitle_' .. layout .. '_front_data'])
			animDraw(trials.trials_mode['trialtitle_' .. layout .. '_front_data'])

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
				
				animSetLocalcoord(trials.trials_mode.textbox_bg_data, trials.stlcx, trials.stlcy)
				animUpdate(trials.trials_mode.textbox_bg_data)
				animDraw(trials.trials_mode.textbox_bg_data)

				-- Draw text
				local trtext = trials.trials_mode.textbox.title.text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', trials.data.trial[ct].name)
				trials.draw.textbox_title:update({text = trtext})
				trials.draw.textbox_title:draw()

				if not trials.draw.draw_textbox_text then
					trials.data.trial[ct].textcnt = trials.data.trial[ct].textcnt + 1
				end
				
		if main.font_def == nil then
			main.font_def = fontGetDef(main.font[trials.draw.textbox_text.font])
		end
		if main.font_def[font] == nil then
			main.font_def = fontGetDef(main.font[trials.draw.textbox_text.font])
		end
		textImgSetFont(trials.draw.textbox_text.ti, main.font[trials.draw.textbox_text.font])
	
	textboxtext_offset1 = textboxwindow1 * trials.lcdx00 + trials.trials_mode.textbox_text_window[1]+trials.trials_mode.textbox_text_offset[1]
	textboxtext_offset2 = textboxwindow2 * trials.lcdy00 + trials.trials_mode.textbox_text_window[2]+trials.trials_mode.textbox_text_offset[2]
		textboxtext_offset1 = textboxtext_offset1 / trials.lcdx00
		textboxtext_offset2 = textboxtext_offset2 / trials.lcdy00
	
		textImgSetText(trials.draw.textbox_text.ti,string.format(trials.data.trial[ct].textbox, main.f_countSubstring(trials.data.trial[ct].textbox, '_')))
		textImgSetPos(trials.draw.textbox_text.ti, math.floor(textboxtext_offset1), math.floor(textboxtext_offset2))
		textImgSetScale(trials.draw.textbox_text.ti, trials.draw.textbox_text.scaleX / trials.lcdy00, trials.draw.textbox_text.scaleY / trials.lcdy00)
		textImgSetLocalcoord(trials.draw.textbox_text.ti, trials.stlcx, trials.stlcy)
		textImgDraw(trials.draw.textbox_text.ti)


				-- Draw portrait depending on desired source
				if trials.trials_mode.textbox_portrait_source == "system" then
	if trials.trials_mode.textbox.portrait.anim == nil then
Temporarysan9000 = sffNew(motif.files.spr)
			end
trialsanim = ""
	for i,k in pairs(trials.data.trial[ct].trialstep[cts].iconanim) do
		k = tostring(k)
		k = k:gsub('(%d*)','%1')
		trialsanim = trialsanim .. "," .. k
			end
				trialsanim = trialsanim:gsub('\,(%d*.*)','%1')
				trialsanim = tostring(trialsanim)
				
	trials.trials_mode.textbox.portrait.anim = animNew(Temporarysan9000,trialsanim)
				elseif trials.trials_mode.textbox_portrait_source == "char" then
				
Temporarysan0000 = loadText(getCharFileName(trials.p1selref))
Temporarysan0000 = Temporarysan0000:lower()
Temporarysan0000 = Temporarysan0000:gsub('([^\r\n;]*)%s*;[^\r\n]*', '%1')
Temporarysan0000 = Temporarysan0000:gsub('\n%s*\n', '\n')
Temporarysan0000 = Temporarysan0000:gsub('.*sprite.*=%s*(.*sff).*','%1')

Temporarysan0001 = getCharFileName(trials.p1selref):gsub('(.*)%/.*def.*','%1/')
Temporarysan0000 = Temporarysan0001 .. Temporarysan0000
Temporarysan9000 = sffNew(Temporarysan0000)

trialsanim = ""
	for i,k in pairs(trials.data.trial[ct].trialstep[cts].iconanim) do
		k = tostring(k)
		k = k:gsub('(%d*)','%1')
		trialsanim = trialsanim .. "," .. k
			end
				trialsanim = trialsanim:gsub('\,(%d*.*)','%1')
				trialsanim = tostring(trialsanim)
				
	trials.trials_mode.textbox.portrait.anim = animNew(Temporarysan9000,trialsanim)
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

	
		if trialsanim ~= nil then
			local a = trials.trials_mode.textbox.portrait.anim
			if a then
				animSetLocalcoord(a, trials.stlcx, trials.stlcy)
				animSetLayerno(a, 0)
				animSetPos(a, 
						math.floor(animposx),
						math.floor(animposy))
				animSetScale(
					a,
						trialsanimscalex,
						trialsanimscaley
				)
				animSetFacing(a, 
						trials.trials_mode.textbox_portrait_facing)
				animSetWindow(a, 
						trialsanimwindow1,
						trialsanimwindow2,
						trialsanimwindow3,
						trialsanimwindow4)
				animUpdate(a)
				animDraw(a)

			end
		end
	end

				-- Draw textbox front
				animSetLocalcoord(trials.trials_mode.textbox_front_data, trials.mtlcx, trials.mtlcy)
				animUpdate(trials.trials_mode.textbox_front_data)
				animDraw(trials.trials_mode.textbox_front_data)
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
					animSetPos(
						trials.trials_mode[sub .. 'step_vertical_bg_data'],
						trials.trials_mode.trialsteps.vertical.pos[1] + trials.trials_mode[sub .. 'step'].vertical.bg.offset[1] + tempoffset[1],
						trials.trials_mode.trialsteps.vertical.pos[2] + trials.trials_mode[sub .. 'step'].vertical.bg.offset[2] + tempoffset[2]
					)
					trials.draw.vertical[sub .. 'textline'][i]:update({
						x = trials.trials_mode.trialsteps.vertical.pos[1]+trials.trials_mode[sub .. 'step'].vertical.text.offset[1]+trials.trials_mode.trialsteps.vertical.spacing[1]*(i-startonstep),
						y = trials.trials_mode.trialsteps.vertical.pos[2]+trials.trials_mode[sub .. 'step'].vertical.text.offset[2]+trials.trials_mode.trialsteps.vertical.spacing[2]*(i-startonstep),
						text = trials.data.trial[ct].trialstep[i].text
					},1)
					animSetPalFX(trials.trials_mode[sub .. 'step_vertical_bg_data'], {
						time = 1,
						add = trials.trials_mode[sub .. 'step'].vertical.bg.palfx.add,
						mul = trials.trials_mode[sub .. 'step'].vertical.bg.palfx.mul,
						sinadd = trials.trials_mode[sub .. 'step'].vertical.bg.palfx.sinadd,
						invertall = trials.trials_mode[sub .. 'step'].vertical.bg.palfx.invertall,
						color = trials.trials_mode[sub .. 'step'].vertical.bg.palfx.color
					})
					animReset(trials.trials_mode[sub .. 'step_vertical_bg_data'])
				animSetLocalcoord(trials.trials_mode[sub .. 'step_vertical_bg_data'], trials.mtlcx, trials.mtlcy)
					animUpdate(trials.trials_mode[sub .. 'step_vertical_bg_data'])
					animDraw(trials.trials_mode[sub .. 'step_vertical_bg_data'])
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
					local tailoffset = trials.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][1]
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
					
	tailposx = bgcomponentposX + trials.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][1]
	tailposy = trials.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][2] + tempoffset[2]
	
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
					animSetPos(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'], 
						bgcomponentposX + trials.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][1], 
						trials.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][2] + tempoffset[2]
					)
				animSetScale(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'], 
					 tailscalex,
					  tailscaley
				)
					animSetPalFX(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'], {
						time = 1,
						add = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
				animSetLocalcoord(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'], trials.mtlcx, trials.mtlcy)
					animUpdate(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
					animDraw(trials.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
					
					-- Draw BG for Glyphs - scale to length, start from tail pos
					bgtargetscale = {(padding + totalglyphlength + padding)/bgsize[1], 1}
					bgcomponentposX = (bgcomponentposX + bgtailwidth)
					local gpoffset = 0
					for m in pairs(trials.data.trial[ct].trialstep[i].glyphline.horizontal.glyph) do
						if m > 1 then gpoffset = trials.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[m-1] end
						trials.data.trial[ct].trialstep[i].glyphline.horizontal.pos[m][1] = bgcomponentposX + padding + gpoffset -- trials.trials_mode.trialsteps_pos[1] + trials.data.trial[ct].trialstep[i].glyphline.alignOffset[m] +
					end

					animSetScale(trials.trials_mode[sub .. 'step_horizontal_bg_data'],
					 bgtargetscale[1],
					  bgtargetscale[2])
					animSetPos(trials.trials_mode[sub .. 'step_horizontal_bg_data'], 
						bgcomponentposX + trials.trials_mode[sub .. 'step_horizontal_bg_offset'][1], 
						trials.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials.trials_mode[sub .. 'step_horizontal_bg_offset'][2] + tempoffset[2]
					)
					animSetPalFX(trials.trials_mode[sub .. 'step_horizontal_bg_data'], {
						time = 1,
						add = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials.trials_mode[sub .. 'step_horizontal_bg_data'])
				animSetLocalcoord(trials.trials_mode[sub .. 'step_horizontal_bg_data'], trials.mtlcx, trials.mtlcy)
					animUpdate(trials.trials_mode[sub .. 'step_horizontal_bg_data'])
					animDraw(trials.trials_mode[sub .. 'step_horizontal_bg_data'])
					
					-- Draw head
					bgcomponentposX = bgcomponentposX + (totalglyphlength + 2*padding)
					animSetPos(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'], 
						bgcomponentposX + trials.trials_mode[sub .. 'step_horizontal_bg_head_offset'][1] + trials.data.trial[ct].trialstep[i].glyphline.horizontal.alignOffset[1], 
						trials.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials.trials_mode[sub .. 'step_horizontal_bg_head_offset'][2] + tempoffset[2]
					)
					animSetPalFX(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'], {
						time = 1,
						add = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'])
				animSetLocalcoord(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'], trials.mtlcx, trials.mtlcy)
					animUpdate(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'])
					animDraw(trials.trials_mode[sub .. 'step_horizontal_bg_head_data'])
				end
				for m = 1, #trials.data.trial[ct].trialstep[i].glyphline[layout].glyph, 1 do
					animSetScale(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData,
					 trials.data.trial[ct].trialstep[i].glyphline[layout].scale[m][1],
					  trials.data.trial[ct].trialstep[i].glyphline[layout].scale[m][2])
					animSetPos(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData, 
						trials.data.trial[ct].trialstep[i].glyphline[layout].pos[m][1], 
						trials.data.trial[ct].trialstep[i].glyphline[layout].pos[m][2] + tempoffset[2] + trials.trials_mode.glyphs[layout].offset[2]
					)
					animSetPalFX(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData, {
						time = 1,
						add = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx.add,
						mul = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx.mul,
						sinadd = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx.sinadd,
						invertall = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx.invertall,
						color = trials.trials_mode[sub .. 'step'][layout].glyphs.palfx.color
					})
					animReset(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData)
				animSetLocalcoord(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData, trials.mtlcx, trials.mtlcy)
					animUpdate(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData)
					animDraw(motif.glyphs[trials.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].AnimData)
				end
				accwidth = bgcomponentposX
			end
		elseif ct > #trials.data.trial then
			-- All trials have been completed, draw the all clear and freeze the timer
			if trials.draw.allclear ~= 0 then
				trials.f_trialsSuccess('allclear', ct-1)
				f_createTextImg(trials.trials_mode, 'allclear_text')
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

		if trials.data.validfortickcount > 0 then
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
								trials.draw.success = math.max(animGetLength(trials.trials_mode.success_front_data), animGetLength(trials.trials_mode.success_bg_data), trials.trials_mode.success_text_displaytime)
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
	elseif trials.draw.fade > 0 and (trials.trials_mode.trialsresetonsuccess == true or trials.draw.fadetriggered) then
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
	elseif f_checkKeyCombo(trials.trials_mode.trialreset_buttonpress) and trials.draw.fade == 0 and menu.trialreset == 1 then
		trials.draw.fadein = trials.trials_mode.fadein_time
		trials.draw.fadeout = trials.trials_mode.fadeout_time
		trials.draw.fade = trials.draw.fadein + trials.draw.fadeout
		trials.draw.fadetriggered = true
	else
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
		sndPlay(motif.files.snd_data, trials.trials_mode[successstring .. '_snd'][1], trials.trials_mode[successstring .. '_snd'][2])
	end
		trials.draw.success_text.text = trials.trials_mode.success.text.text
		trials.draw.success_text.x = trials.trials_mode.success.pos[1]
		trials.draw.success_text.y = trials.trials_mode.success.pos[2]
		trials.draw.allclear_text.text = trials.trials_mode.allclear.text.text
		trials.draw.allclear_text.x = trials.trials_mode.allclear.pos[1]
		trials.draw.allclear_text.y = trials.trials_mode.allclear.pos[2]
		textImgSetFont(trials.draw[successstring .. '_text'].ti, main.font[trials.draw[successstring .. '_text'].font])
		textImgSetBank(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].bank)
		textImgSetAlign(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].align)
		textImgSetText(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].text)
		textImgSetColor(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].r, trials.draw[successstring .. '_text'].g, trials.draw[successstring .. '_text'].b, trials.draw[successstring .. '_text'].a)
		--if trials.draw[successstring .. '_text'].defsc then disableLuaScale() end
		textImgSetPos(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].x + f_alignOffset(trials.draw[successstring .. '_text'].align), trials.draw[successstring .. '_text'].y)
		textImgSetScale(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].scaleX, trials.draw[successstring .. '_text'].scaleY)
		textImgSetWindow(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].window[1], trials.draw[successstring .. '_text'].window[2], trials.draw[successstring .. '_text'].window[3] - trials.draw[successstring .. '_text'].window[1], trials.draw[successstring .. '_text'].window[4] - trials.draw[successstring .. '_text'].window[2])
		textImgSetXShear(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].xshear)
		textImgSetAngle(trials.draw[successstring .. '_text'].ti, trials.draw[successstring .. '_text'].angle)
		  textImgUpdate(trials.draw[successstring .. '_text'].ti)
				animSetLocalcoord(trials.trials_mode[successstring .. '_bg_data'], trials.mtlcx, trials.mtlcy)
	animUpdate(trials.trials_mode[successstring .. '_bg_data'])
	animDraw(trials.trials_mode[successstring .. '_bg_data'])
	trials.draw[successstring .. '_text']:draw()
				animSetLocalcoord(trials.trials_mode[successstring .. '_front_data'], trials.mtlcx, trials.mtlcy)
	animUpdate(trials.trials_mode[successstring .. '_front_data'])
	animDraw(trials.trials_mode[successstring .. '_front_data'])
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
			mapSet('_iksys_trialsCameraReset', 1)
		fadeInInit(trials.draw.fadeinData)
	end
		trials.draw.fadein = trials.draw.fadein - 1
	end

	trials.draw.fade = trials.draw.fade - 1
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

if main.font == nil then
main.font = motif.Fnt
	end
if motif.files.spr_data == nil then
motif.files.spr_data = sffNew(motif.files.spr)
	end
if motif.files.snd_data == nil then
motif.files.snd_data = sndNew(motif.files.snd)
	end
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
				trials.p1selref = nil
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
		trialcounter = f_createTextImg(trials.trials_mode, 'trialcounter')
		trialcounter:update({x = trials.trials_mode.trialcounter_pos[1], y = trials.trials_mode.trialcounter_pos[2], text = trials.trials_mode.trialcounter_notrialsdata_text})
		trialcounter:draw()
	end
end

--;===========================================================
--; menu.lua
--;===========================================================

		if menu.trialslist == nil then
menu.trialslist = 1
			end
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
		if menu.trialreset == nil then
menu.trialreset = 1
			end
		motif.option_info.menu.valuename.trialslist_1 = "Select Trial"
menu.t_valuename.trialslist = {
 	{itemname = "Select Trial", displayname = motif.option_info.menu.valuename.trialslist_1}
}
		motif.option_info.menu.valuename.trialadvancement_1 = "Auto-Advance"
		motif.option_info.menu.valuename.trialadvancement_2 = "Repeat"
menu.t_valuename.trialadvancement = {
	{itemname = "Auto-Advance", displayname = motif.option_info.menu.valuename.trialadvancement_1},
	{itemname = "Repeat", displayname = motif.option_info.menu.valuename.trialadvancement_2}
}
		motif.option_info.menu.valuename.trialresetonsuccess_1 = "Yes"
		motif.option_info.menu.valuename.trialresetonsuccess_2 = "No"
menu.t_valuename.trialresetonsuccess = {
	{itemname = "Yes", displayname = motif.option_info.menu.valuename.trialresetonsuccess_1},
	{itemname = "No", displayname = motif.option_info.menu.valuename.trialresetonsuccess_2}
}
		motif.option_info.menu.valuename.trialslayout_1 = "Vertical"
		motif.option_info.menu.valuename.trialslayout_2 = "Horizontal"
menu.t_valuename.trialslayout = {
	{itemname = "Vertical", displayname = motif.option_info.menu.valuename.trialslayout_1},
	{itemname = "Horizontal", displayname = motif.option_info.menu.valuename.trialslayout_2}
}
		motif.option_info.menu.valuename.trialstextboxes_1 = "Show"
		motif.option_info.menu.valuename.trialstextboxes_2 = "Hide"
menu.t_valuename.trialstextboxes = {
	{itemname = "Show", displayname = motif.option_info.menu.valuename.trialstextboxes_1},
	{itemname = "Hide", displayname = motif.option_info.menu.valuename.trialstextboxes_2}
}
		motif.option_info.menu.valuename.trialreset_1 = "enabled"
		motif.option_info.menu.valuename.trialreset_2 = "disabled"
menu.t_valuename.trialreset = {
	{itemname = "enabled", displayname = motif.option_info.menu.valuename.trialreset_1},
	{itemname = "disabled", displayname = motif.option_info.menu.valuename.trialreset_2}
}
menu.t_itemname['trialslist'] = function(t, item, cursorPosY, movTeTxt, sec)
	if menu.f_valueChanged(t.items[item], sec) then
		trials.data.currenttrialstep = 1
		trials.data.currenttrialmicrostep = 1
		trials.data.currenttrial = menu.trialslist
		trials.data.trial[trials.data.currenttrial].complete = false
		trials.data.trial[trials.data.currenttrial].active = false
		trials.data.active = false
		trials.data.displaytimers.totaltimer = false
		trials.data.trial[trials.data.currenttrial].starttick = roundTime()
	end
	return true
end
menu.t_vardisplay['trialslist'] = function()
	return menu.t_valuename.trialslist[menu.trialslist or 1].displayname
end

options.t_vardisplay['trialslist'] = function()
	return menu.t_valuename.trialslist[menu.trialslist or 1].displayname
end

menu.t_itemname['trialadvancement'] = function(t, item, cursorPosY, moveTxt, sec)
	if menu.f_valueChanged(t.items[item], sec) then
		if menu.t_valuename.trialadvancement[menu.trialadvancement or 1].itemname == "Auto-Advance" then
			trials.data.trialadvancement = true
		else
			trials.data.trialadvancement = false
		end
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
	if menu.f_valueChanged(t.items[item], sec) then
		if menu.t_valuename.trialslayout[menu.trialslayout or 1].itemname == "Vertical" then
			trials.trials_mode.trialslayout = "vertical"
		else
			trials.trials_mode.trialslayout = "horizontal"
		end
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
	if menu.f_valueChanged(t.items[item], sec) then
		if menu.t_valuename.trialresetonsuccess[menu.trialresetonsuccess or 1].itemname == "Yes" then
			trials.trials_mode.trialsresetonsuccess = true
		else
			trials.trials_mode.trialsresetonsuccess = false
		end
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
	if menu.f_valueChanged(t.items[item], sec) then
		if menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].itemname == "Show" then
			trials.trials_mode.textbox_visible = true
		else
			trials.trials_mode.textbox_visible = false
		end
	end
	return true
end
menu.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end

options.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end

menu.t_itemname['trialreset'] = function(t, item, cursorPosY, moveTxt, sec)
	if menu.f_valueChanged(t.items[item], sec) then
		if menu.t_valuename.trialreset[menu.trialreset or 1].itemname == "enabled" then
			trials.trials_mode.trialreset_enabled = true
		else
			trials.trials_mode.trialreset_enabled = false
		end
	end
	return true
end
menu.t_vardisplay['trialreset'] = function()
	return menu.t_valuename.trialreset[menu.trialreset or 1].displayname
end

options.t_vardisplay['trialreset'] = function()
	return menu.t_valuename.trialreset[menu.trialreset or 1].displayname
end

menu.t_itemname['nexttrial'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, motif.option_info.menu.done.key) then
		trials.data.currenttrialstep = 1
		trials.data.currenttrialmicrostep = 1
		sndPlay(motif.Snd, motif.option_info.cursor.move.snd[1], motif.option_info.cursor.move.snd[2])
		trials.data.currenttrial = math.min(trials.data.currenttrial + 1, #trials.data.trial)
		trials.data.trial[trials.data.currenttrial].complete = false
		trials.data.trial[trials.data.currenttrial].active = false
		trials.data.active = false
		trials.data.displaytimers.totaltimer = false
		trials.data.trial[trials.data.currenttrial].starttick = roundTime()
	end
	return true
end

menu.t_itemname['previoustrial'] = function(t, item, cursorPosY, moveTxt, sec)
	if getInput(-1, motif.option_info.menu.done.key) then
		trials.data.currenttrialstep = 1
		trials.data.currenttrialmicrostep = 1
		sndPlay(motif.Snd, motif.option_info.cursor.move.snd[1], motif.option_info.cursor.move.snd[2])
		trials.data.currenttrial = math.max(trials.data.currenttrial - 1, 1)
		trials.data.trial[trials.data.currenttrial].complete = false
		trials.data.trial[trials.data.currenttrial].active = false
		trials.data.active = false
		trials.data.displaytimers.totaltimer = false
		trials.data.trial[trials.data.currenttrial].starttick = roundTime()
	end
	return true
end

function menu.f_trialsReset()
	for k, _ in pairs(menu.t_valuename) do
		menu[k] = 1
	end
	if trials.data.trialadvancement == true then
		menu.trialadvancement = 1
	else
		menu.trialadvancement = 2
	end
	if trials.trials_mode.trialsresetonsuccess == true then
		menu.trialresetonsuccess = 1
	else
		menu.trialresetonsuccess = 2
	end
	if trials.trials_mode.trialslayout == "vertical" then
		menu.trialslayout = 1
	else
		menu.trialslayout = 2
	end
	if trials.trials_mode.textbox_visible == true then
		menu.trialstextboxes = 1
	else
		menu.trialstextboxes = 2
	end
	if trials.trials_mode.trialreset_enabled == true then
		menu.trialreset = 1
	else
		menu.trialreset = 2
	end
	for _, v in ipairs(menu.t_vardisplayPointers) do
		v.vardisplay = menu.f_vardisplay(v.itemname)
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
