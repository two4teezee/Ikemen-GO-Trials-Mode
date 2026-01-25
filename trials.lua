-- IKEMEN GO TRIALS MODE EXTERNAL MODULE --------------------------------
-- Last tested on Ikemen GO v0.99
-- Module developed by two4teezee
-------------------------------------------------------------------------
-- This external module implements TRIALS game mode (defeat all opponents
-- that are consider bosses). Features full screenpack integration via
-- system.def, ability to create and read trails for any character, and a
-- trials menu option, as well as a timer for the speed demons out there.
-- The trials mode and verification thresholds can be modified to suit your
-- custome game if needed. For more info on lua external modules:
-- https://github.com/K4thos/Ikemen_GO/wiki/Miscellaneous-Info#lua_modules
-- This mode is detectable by GameMode trigger as trials.
-- Only characters with a trials.def in their character folder will have
-- trials available for them; the character's def file also needs to be
-- modified to point to that trials.def. Documentation on how to use trials
-- mode is in README.md.
-------------------------------------------------------------------------

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
		if inputtime(key) <= 0 then
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

trials_mode = {}
trials_mode.ui_def = loadIni('external/mods/trials/config.def')

--;===========================================================
--; main.lua
--;===========================================================
main.t_itemname.trials = function()
	main.aiRamp = false
	-- main.charparam.ai = false
	-- main.charparam.music = true
	-- main.charparam.single = true
	-- main.charparam.stage = true
	-- main.charparam.time = true
	main.coop = false
	main.cpuSide = {false, false}
	main.elimination = true
	main.exitSelect = true
	main.lifebar = { --which lifebar elements should be rendered (these defaults are overwritten by fight.def, depending on game mode)
		active = true,
		bars = true,
		match = false,
		mode = true,
		p1ailevel = false,
		p1score = false,
		p1wincount = false,
		p2ailevel = false,
		p2score = false,
		p2wincount = false,
		timer = false,
		guardbar = gameOption('Options.GuardBreak'),
		stunbar = gameOption('Options.Dizzy'),
		redlifebar = gameOption('Options.RedLife'),
	}
	main.lifebar.p2ailevel = false
	main.makeRoster = false
	main.motif.hiscore = false
	main.motif.losescreen = false
	main.motif.victoryscreen = false
	main.motif.winscreen = false
	main.orderSelect = {true, true}
	main.rotationChars = true
	main.storyboard.credits = false
	main.storyboard.gameover = false
	main.teamMenu = {
		{ratio = false, simul = false, single = true, tag = false, turns = false}, --which team modes should be selectable by P1 side
		{ratio = false, simul = false, single = true, tag = false, turns = false}, --which team modes should be selectable by P2 side
	}
	main.roundTime = -1
	main.selectMenu = {true, true}
	main.stageMenu = true
	textImgSetText(motif.select_info.title.TextSpriteData, motif.select_info.title.text.trials)
	remapInput(main.playerInput, 1)
	setCommandInputSource(2, 1)
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

-- --trials spr/anim data
-- local tr_pos = trials_mode.ui_def
-- for _, v in ipairs({
-- 	{s = 'trialsteps_vertical_bg_',				x = tr_pos.trialsteps_vertical_pos[1] + tr_pos.trialsteps_vertical_bg_offset[1],		y = tr_pos.trialsteps_vertical_pos[2] + tr_pos.trialsteps_vertical_bg_offset[2],		},
-- 	{s = 'trialsteps_horizontal_bg_',			x = tr_pos.trialsteps_horizontal_pos[1] + tr_pos.trialsteps_horizontal_bg_offset[1],	y = tr_pos.trialsteps_horizontal_pos[2] + tr_pos.trialsteps_horizontal_bg_offset[2],	},
-- 	{s = 'success_bg_',    						x = tr_pos.success_pos[1] + tr_pos.success_bg_offset[1],								y = tr_pos.success_pos[2] + tr_pos.success_bg_offset[2],								},
-- 	{s = 'allclear_bg_',	   					x = tr_pos.allclear_pos[1] + tr_pos.allclear_bg_offset[1],								y = tr_pos.allclear_pos[2] + tr_pos.allclear_bg_offset[2],								},
-- 	{s = 'textbox_bg_',	   						x = tr_pos.textbox_pos[1] + tr_pos.textbox_bg_offset[1],								y = tr_pos.textbox_pos[2] + tr_pos.textbox_bg_offset[2],								},
-- 	{s = 'success_front_',  	  				x = tr_pos.success_pos[1] + tr_pos.success_front_offset[1],								y = tr_pos.success_pos[2] + tr_pos.success_front_offset[2],								},
-- 	{s = 'allclear_front_',   					x = tr_pos.allclear_pos[1] + tr_pos.allclear_front_offset[1],							y = tr_pos.allclear_pos[2] + tr_pos.allclear_front_offset[2],							},
-- 	{s = 'textbox_front_',	   					x = tr_pos.textbox_pos[1] + tr_pos.textbox_front_offset[1],								y = tr_pos.textbox_pos[2] + tr_pos.textbox_front_offset[2],								},
-- 	{s = 'upcomingstep_vertical_bg_',			x = 0,																					y = 0,																					},
-- 	{s = 'upcomingstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
-- 	{s = 'upcomingstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_vertical_bg_',			x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_vertical_bg_',			x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_vertical_bg_tail_',		x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_vertical_bg_head_',		x = 0,																					y = 0,																					},
--     {s = 'upcomingstep_horizontal_bg_',			x = 0,																					y = 0,																					},
-- 	{s = 'upcomingstep_horizontal_bg_tail_',	x = 0,																					y = 0,																					},
-- 	{s = 'upcomingstep_horizontal_bg_head_',	x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_horizontal_bg_',			x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_horizontal_bg_tail_',		x = 0,																					y = 0,																					},
-- 	{s = 'currentstep_horizontal_bg_head_',		x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_horizontal_bg_',		x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_horizontal_bg_tail_',	x = 0,																					y = 0,																					},
-- 	{s = 'completedstep_horizontal_bg_head_',	x = 0,																					y = 0,																					},
-- 	{s = 'trialtitle_vertical_bg_',    			x = tr_pos.trialtitle_vertical_pos[1] + tr_pos.trialtitle_vertical_bg_offset[1],		y = tr_pos.trialtitle_vertical_pos[2] + tr_pos.trialtitle_vertical_bg_offset[2],		},
-- 	{s = 'trialtitle_vertical_front_',    		x = tr_pos.trialtitle_vertical_pos[1] + tr_pos.trialtitle_vertical_front_offset[1],		y = tr_pos.trialtitle_vertical_pos[2] + tr_pos.trialtitle_vertical_front_offset[2],		},
--     {s = 'trialtitle_horizontal_bg_',    		x = tr_pos.trialtitle_horizontal_pos[1] + tr_pos.trialtitle_horizontal_bg_offset[1],	y = tr_pos.trialtitle_horizontal_pos[2] + tr_pos.trialtitle_horizontal_bg_offset[2],	},
-- 	{s = 'trialtitle_horizontal_front_',    	x = tr_pos.trialtitle_horizontal_pos[1] + tr_pos.trialtitle_horizontal_front_offset[1],	y = tr_pos.trialtitle_horizontal_pos[2] + tr_pos.trialtitle_horizontal_front_offset[2],	},
-- }) do
-- 	if motif.files.trials ~= nil and motif.files.trials ~= '' then
-- 	 	motif.files.data = sffNew(searchFile(motif.files.trials, {motif.fileDir, '', 'data/'}))
-- 	 	main.f_loadingRefresh()
-- 	 	motif.f_loadSprData(trials_mode.ui_def, v, motif.files.data)
-- 	elseif main.f_fileExists('external/mods/trials/trials.sff') then
-- 		motif.files.data = sffNew(searchFile('external/mods/trials/trials.sff', {motif.fileDir, '', 'data/'}))
-- 	 	main.f_loadingRefresh()
-- 	 	motif.f_loadSprData(trials_mode.ui_def, v, motif.files.data)
-- 	else
-- 	 	motif.f_loadSprData(trials_mode.ui_def, v)
-- 	end
-- end

-- if trials_mode.ui_def.textbox_portrait_source == "system" and trials_mode.ui_def.textbox_portrait_spr ~= nil then
-- 	motif.f_loadSprData(trials_mode.ui_def, {s = 'textbox_portrait_', x = trials_mode.ui_def.textbox_pos[1] + trials_mode.ui_def.textbox_portrait_offset[1], y = trials_mode.ui_def.textbox_pos[2] + trials_mode.ui_def.textbox_portrait_offset[2]})
-- end

-- -- fadein/fadeout anim data generation.
-- if trials_mode.ui_def.fadein_anim ~= -1 then
-- 	motif.f_loadSprData(trials_mode.ui_def, {s = 'fadein_'})
-- end
-- if trials_mode.ui_def.fadeout_anim ~= -1 then
-- 	motif.f_loadSprData(trials_mode.ui_def, {s = 'fadeout_'})
-- end

--;===========================================================
--; start.lua
--;===========================================================
start.selectScreenPalMod = 'normal'

function start.f_inittrialsData()
	trials_mode.data = {
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
		combocounter = 0,
		maxsteps = 0,
		starttick = roundtime(),
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
		trials_mode.data.trialadvancement = true
	else
		trials_mode.data.trialadvancement = false
	end
end

function start.f_trialsBuilder()
	--This function will initialize once to build all the trial tables based on the motif information and the trials information loaded when the char was selected
	--Populate background elements information
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep_','upcomingstep_','completedstep_'}) do
			trials_mode.data.bgelemdata[v][k .. 'bgsize'] = animGetSpriteInfo(trials_mode.ui_def[k .. v .. '_bg_data'])
			if v == 'horizontal' then
				trials_mode.data.bgelemdata[v][k .. 'bgtailwidth'] = animGetSpriteInfo(trials_mode.ui_def[k .. v .. '_bg_tail_data'])
				trials_mode.data.bgelemdata[v][k .. 'bgheadwidth'] = animGetSpriteInfo(trials_mode.ui_def[k .. v .. '_bg_tail_data'])
			end
		end
	end
	
	-- thin out trials data according to showforvarvalpairs
	for i = 1, #trials_mode.data.trial, 1 do
		if trials_mode.data.trial[i].showforvar[1] ~= nil then
			valvarcheck = true
			sumcheck = 0
			-- check every var
			for ii = 1, #trials_mode.data.trial[i].showforvar, 1 do
				player(1)
				-- iterate over vals
				for iii = 1, #trials_mode.data.trial[i].showforval[ii], 1 do
					if var(trials_mode.data.trial[i].showforvar[ii]) == trials_mode.data.trial[i].showforval[ii][iii] then
						sumcheck = sumcheck + 1
					end
				end
			end
			-- for every var, there should have been one hit; if not, set valvarcheck to false
			if sumcheck ~= #trials_mode.data.trial[i].showforvar then
				valvarcheck = false
			end
			-- remove trials that failed valvarcheck
			if not valvarcheck then
				trials_mode.data.trialsRemovalIndex[#trials_mode.data.trialsRemovalIndex+1] = i
			end
		end
	end
	for i = #trials_mode.data.trialsRemovalIndex, 1, -1 do
		table.remove(trials_mode.data.trial,trials_mode.data.trialsRemovalIndex[i])
	end

	--Obtain all of the trials information, to include the offset positions based on whether the display layout is horizontal or vertical
	for i = 1, #trials_mode.data.trial, 1 do
		if #trials_mode.data.trial[i].trialstep > trials_mode.data.maxsteps then
			trials_mode.data.maxsteps = #trials_mode.data.trial[i].trialstep
		end
		for j = 1, #trials_mode.data.trial[i].trialstep, 1 do
			local movelistline = trials_mode.data.trial[i].trialstep[j].glyphs
			for kk, v in main.f_sortKeys(motif.glyphs, function(t, a, b) return string.len(a) > string.len(b) end) do
				movelistline = movelistline:gsub(main.f_escapePattern(kk), '<' .. numberToRune(v[1] + 0xe000) .. '>')
			end
			movelistline = movelistline:gsub('%s+$', '')
			for moves in movelistline:gmatch('(	*[^	]+)') do
				moves = moves .. '<#>'
				tempglyphs = {}
				for m1, m2 in moves:gmatch('(.-)<([^%g <>]+)>') do
					if not m2:match('^#[A-Za-z0-9]+$') and not m2:match('^/$') and not m2:match('^#$') then
						tempglyphs[#tempglyphs+1] = m2
					end
				end
				for _, layout in ipairs({'vertical','horizontal'}) do
					if trials_mode.ui_def['glyphs_' .. layout .. '_align'] == -1 then
						for m = #tempglyphs, 1, -1 do
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[#trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = tempglyphs[m]
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].pos[#trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = {0,0}
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[#trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].alignOffset[#trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[#trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
						end
					else
						for m = 1, #tempglyphs do
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[m] = tempglyphs[m]
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].pos[m] = {0,0}
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[m] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = 0
							trials_mode.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
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
				if layout == "vertical" and trials_mode.ui_def.currentstep_vertical_text_font[7] == nil and trials_mode.ui_def.glyphs_vertical_scalewithtext == "true" then
					font_def = main.font_def[trials_mode.ui_def.currentstep_vertical_text_font[1] .. trials_mode.ui_def.currentstep_vertical_text_font_height]
				elseif layout == "vertical" and trials_mode.ui_def.glyphs_vertical_scalewithtext == "true" then
					font_def = main.font_def[trials_mode.ui_def.currentstep_vertical_text_font[1] .. trials_mode.ui_def.currentstep_vertical_text_font[7]]
				end
				for m in pairs(trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph) do
					if motif.glyphs_data[trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[m]] ~= nil then
						if trials_mode.ui_def['glyphs_' .. layout .. '_align'] == 0 then --center align
							alignOffset = trials_mode.ui_def['glyphs_' .. layout .. '_offset'][1] * 0.5
						elseif trials_mode.ui_def['glyphs_' .. layout .. '_align'] == -1 then --right align
							alignOffset = trials_mode.ui_def['glyphs_' .. layout .. '_offset'][1]
						end
						if trials_mode.ui_def['glyphs_' .. layout .. '_align'] ~= align then
							lengthOffset = 0
							align = trials_mode.ui_def['glyphs_' .. layout .. '_align']
						end
						local scaleX = trials_mode.ui_def['glyphs_' .. layout .. '_scale'][1]
						local scaleY = trials_mode.ui_def['glyphs_' .. layout .. '_scale'][2]
						if trials_mode.ui_def['glyphs_' .. layout .. '_align'] == -1 then
							alignOffset = alignOffset - motif.glyphs_data[trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[1] * scaleX
						end
						trials_mode.data.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = alignOffset
						if layout == "vertical" and trials_mode.ui_def.glyphs_vertical_scalewithtext == "true" then
							scaleY = font_def.Size[2] * trials_mode.ui_def.currentstep_vertical_text_scale[2] / motif.glyphs_data[trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[2]
							scaleX = scaleY
						end
						trials_mode.data.trial[i].trialstep[j].glyphline[layout].scale[m] = {scaleX, scaleY}
						trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[m] = math.floor(motif.glyphs_data[trials_mode.data.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[1] * scaleX + trials_mode.ui_def['glyphs_' .. layout .. '_spacing'][1])
						if trials_mode.ui_def['glyphs_' .. layout .. '_align'] == 1 then
							lengthOffset = lengthOffset + trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[m]
						elseif trials_mode.ui_def['glyphs_' .. layout .. '_align'] == -1 then
							lengthOffset = lengthOffset - trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[m]
						else
							lengthOffset = lengthOffset + trials_mode.data.trial[i].trialstep[j].glyphline[layout].width[m] / 2
						end
						trials_mode.data.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = lengthOffset
						trials_mode.data.trial[i].trialstep[j].glyphline[layout].pos[m] = {
							math.floor(trials_mode.ui_def['trialsteps_' .. layout .. '_pos'][1] + trials_mode.ui_def['glyphs_' .. layout .. '_offset'][1] + alignOffset + lengthOffset),
							trials_mode.ui_def['trialsteps_' .. layout .. '_pos'][2] + trials_mode.ui_def['glyphs_' .. layout .. '_offset'][2]
						}
					end
				end
			end
		end
		if #trials_mode.data.trial[i].trialstep > trials_mode.data.maxsteps then
			trials_mode.data.maxsteps = #trials_mode.data.trial[i].trialstep
		end
	end
	--Pre-populate the draw table
	trials_mode.data.draw = {
		vertical = {},
		horizontal = {},
		success = 0,
		fade = 0,
		fadein = 0,
		fadeout = 0,
		fadetriggered = false,
		textbox_text = main.f_createTextImg(trials_mode.ui_def, 'textbox_text'),
		textbox_title = main.f_createTextImg(trials_mode.ui_def, 'textbox_title'),
		success_text = main.f_createTextImg(trials_mode.ui_def, 'success_text'),
		allclear = math.max(animGetLength(trials_mode.ui_def.allclear_front_data), animGetLength(trials_mode.ui_def.allclear_bg_data), trials_mode.ui_def.allclear_text_displaytime),
		allclear_text = main.f_createTextImg(trials_mode.ui_def, 'allclear_text'),
		trialcounter = main.f_createTextImg(trials_mode.ui_def, 'trialcounter'),
		totaltrialtimer = main.f_createTextImg(trials_mode.ui_def, 'totaltrialtimer'),
		currenttrialtimer = main.f_createTextImg(trials_mode.ui_def, 'currenttrialtimer'),
		trialreset_text = main.f_createTextImg(trials_mode.ui_def, 'trialreset_text'),
	}
	trials_mode.data.draw.textbox_title:update({x = trials_mode.ui_def.textbox_pos[1]+trials_mode.ui_def.textbox_title_offset[1], y = trials_mode.ui_def.textbox_pos[2]+trials_mode.ui_def.textbox_title_offset[1],})
	trials_mode.data.draw.textbox_text:update({x = trials_mode.ui_def.textbox_pos[1]+trials_mode.ui_def.textbox_text_offset[1]+trials_mode.ui_def.textbox_text_window[1], y = trials_mode.ui_def.textbox_pos[2]+trials_mode.ui_def.textbox_text_offset[2]+trials_mode.ui_def.textbox_text_window[2],})
	trials_mode.data.draw.success_text:update({x = trials_mode.ui_def.success_pos[1]+trials_mode.ui_def.success_text_offset[1], y = trials_mode.ui_def.success_pos[2]+trials_mode.ui_def.success_text_offset[2],})
	trials_mode.data.draw.allclear_text:update({x = trials_mode.ui_def.allclear_pos[1]+trials_mode.ui_def.allclear_text_offset[1], y = trials_mode.ui_def.allclear_pos[2]+trials_mode.ui_def.allclear_text_offset[2],})
	trials_mode.data.draw.trialcounter:update({x = trials_mode.ui_def.trialcounter_pos[1], y = trials_mode.ui_def.trialcounter_pos[2],})
	trials_mode.data.draw.totaltrialtimer:update({x = trials_mode.ui_def.totaltrialtimer_pos[1], y = trials_mode.ui_def.totaltrialtimer_pos[2],})
	trials_mode.data.draw.currenttrialtimer:update({x = trials_mode.ui_def.currenttrialtimer_pos[1], y = trials_mode.ui_def.currenttrialtimer_pos[2],})
	trials_mode.data.draw.trialreset_text:update({x = trials_mode.ui_def.trialreset_text_pos[1], y = trials_mode.ui_def.trialreset_text_pos[2], text = trials_mode.ui_def.trialreset_text_text})
	for _, v in ipairs({'vertical','horizontal'}) do
		trials_mode.data.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			trialtitle = math.max(animGetLength(trials_mode.ui_def['trialtitle_' .. v .. '_front_data']), animGetLength(trials_mode.ui_def['trialtitle_' .. v .. '_bg_data'])),
			trialtitle_text = main.f_createTextImg(trials_mode.ui_def, 'trialtitle_' .. v .. '_text'),
			windowXrange = trials_mode.ui_def['trialsteps_' .. v .. '_window'][3] - trials_mode.ui_def['trialsteps_' .. v .. '_window'][1],
			windowYrange = trials_mode.ui_def['trialsteps_' .. v .. '_window'][4] - trials_mode.ui_def['trialsteps_' .. v .. '_window'][2],
			windowXrangeWtext = trials_mode.ui_def['trialsteps_' .. v .. '_window_withtextbox'][3] - trials_mode.ui_def['trialsteps_' .. v .. '_window_withtextbox'][1],
			windowYrangeWtext = trials_mode.ui_def['trialsteps_' .. v .. '_window_withtextbox'][4] - trials_mode.ui_def['trialsteps_' .. v .. '_window_withtextbox'][2],
		}
		trials_mode.data.draw[v].trialtitle_text:update({x = trials_mode.ui_def['trialtitle_' .. v .. '_pos'][1]+trials_mode.ui_def['trialtitle_' .. v .. '_text_offset'][1], y = trials_mode.ui_def['trialtitle_' .. v .. '_pos'][2]+trials_mode.ui_def['trialtitle_' .. v .. '_text_offset'][2],})
		for i = 1, trials_mode.data.maxsteps, 1 do
			trials_mode.data.draw[v].upcomingtextline[i] = main.f_createTextImg(trials_mode.ui_def, 'upcomingstep_' .. v .. '_text')
			trials_mode.data.draw[v].currenttextline[i] = main.f_createTextImg(trials_mode.ui_def, 'currentstep_' .. v .. '_text')
			trials_mode.data.draw[v].completedtextline[i] = main.f_createTextImg(trials_mode.ui_def, 'completedstep_' .. v .. '_text')
		end
	end

	-- Build list out all of the available trials for Pause menu
	menu.t_valuename.trialslist = {}
	for i = 1, #trials_mode.data.trial, 1 do
		table.insert(menu.t_valuename.trialslist, {itemname = tostring(i), displayname = trials_mode.data.trial[i].name})
	end

	trials_mode.data.trialsInitialized = true
end

function start.f_trialsDummySetup()
	--If the trials initializer was successful and the round animation is completed, we will start drawing trials on the screen
	player(2)
	setAILevel(0)
	if trials_mode.data.currenttrial <= #trials_mode.data.trial then
		if trials_mode.data.trial[trials_mode.data.currenttrial].p2life > 0 then
			mapSet('_iksys_trialsSetLife', trials_mode.data.trial[trials_mode.data.currenttrial].p2life)
			setLife(trials_mode.data.trial[trials_mode.data.currenttrial].p2life)
		elseif map('_iksys_trialsSetLife') < lifemax() then
			mapSet('_iksys_trialsSetLife', lifemax())
			setLife(lifemax())
		end
	else
		mapSet('_iksys_trialsSetLife', lifemax())
		setLife(lifemax())
	end
	player(1)
	if trials_mode.data.currenttrial <= #trials_mode.data.trial then
		if trials_mode.data.trial[trials_mode.data.currenttrial].p1life > 0 then
			mapSet('_iksys_trialsSetLife', trials_mode.data.trial[trials_mode.data.currenttrial].p1life)
			setLife(trials_mode.data.trial[trials_mode.data.currenttrial].p1life)
		elseif map('_iksys_trialsSetLife') < lifemax() then
			mapSet('_iksys_trialsSetLife', lifemax())
			setLife(lifemax())
		end
	else
		mapSet('_iksys_trialsSetLife', lifemax())
		setLife(lifemax())
	end
	player(2)
	mapSet('_iksys_trialsDummyControl', 0)
	if not trials_mode.data.allclear and not trials_mode.data.trial[trials_mode.data.currenttrial].active then
		if trials_mode.data.trial[trials_mode.data.currenttrial].dummymode == 'stand' then
			mapSet('_iksys_trialsDummyMode', 0)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummymode == 'crouch' then
			mapSet('_iksys_trialsDummyMode', 1)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummymode == 'jump' then
			mapSet('_iksys_trialsDummyMode', 2)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummymode == 'wjump' then
			mapSet('_iksys_trialsDummyMode', 3)
		end
		if trials_mode.data.trial[trials_mode.data.currenttrial].guardmode == 'none' then
			mapSet('_iksys_trialsGuardMode', 0)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].guardmode == 'auto' then
			mapSet('_iksys_trialsGuardMode', 2)
		end
		if trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'none' then
			mapSet('_iksys_trialsButtonJam', 0)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'a' then
			mapSet('_iksys_trialsButtonJam', 1)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'b' then
			mapSet('_iksys_trialsButtonJam', 2)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'c' then
			mapSet('_iksys_trialsButtonJam', 3)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'x' then
			mapSet('_iksys_trialsButtonJam', 4)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'y' then
			mapSet('_iksys_trialsButtonJam', 5)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'z' then
			mapSet('_iksys_trialsButtonJam', 6)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'start' then
			mapSet('_iksys_trialsButtonJam', 7)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'd' then
			mapSet('_iksys_trialsButtonJam', 8)
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].buttonjam == 'w' then
			mapSet('_iksys_trialsButtonJam', 9)
		end
		trials_mode.data.trial[trials_mode.data.currenttrial].active = true
	end
	player(1)
end

function start.f_trialsDrawer()
	if trials_mode.data.trialsInitialized and roundstate() == 2 and not trials_mode.data.active and trials_mode.data.draw.fade == 0 then
		start.f_trialsDummySetup()
		trials_mode.data.active = true
	end

	-- Check if game is paused - if so, set pause menu loop
	if paused() and not trials_mode.data.trialsPaused then
		trials_mode.data.trialsPaused = true
		menu.currentMenu = {menu.trials.loop, menu.trials.loop}
	elseif not paused() then
		trials_mode.data.trialsPaused = false
	end

	local accwidth = 0
	local addrow = 0
	-- Initialize abbreviated values for readability
	ct = trials_mode.data.currenttrial
	cts = trials_mode.data.currenttrialstep
	ctms = trials_mode.data.currenttrialmicrostep
	layout = trials_mode.ui_def.trialslayout

	if trials_mode.data.active then
		if ct <= #trials_mode.data.trial and trials_mode.data.draw.success == 0 then

			--According to motif instructions, draw trials counter on screen
			local trtext = trials_mode.ui_def.trialcounter_text
			trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%t', tostring(#trials_mode.data.trial))
			trials_mode.data.draw.trialcounter:update({text = trtext})
			trials_mode.data.draw.trialcounter:draw()
			--Logic for the stopwatches: total time spent in trial, and time spent on this current trial
			if trials_mode.data.displaytimers.totaltimer then
				local totaltimertext = trials_mode.ui_def.totaltrialtimer_text
				trials_mode.data.elapsedtime = roundtime() - trials_mode.data.starttick
				local m, s, x = f_timeConvert(trials_mode.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials_mode.data.draw.totaltrialtimer:update({text = totaltimertext})
				trials_mode.data.draw.totaltrialtimer:draw()
			else
				--trials_mode.data.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--trials_mode.data.draw.totaltrialtimer:draw()
			end
			if trials_mode.data.displaytimers.trialtimer then
				local currenttimertext = trials_mode.ui_def.currenttrialtimer_text
				trials_mode.data.trial[ct].elapsedtime = roundtime() - trials_mode.data.trial[ct].starttick
				local m, s, x = f_timeConvert(trials_mode.data.trial[ct].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials_mode.data.draw.currenttrialtimer:update({text = currenttimertext})
				trials_mode.data.draw.currenttrialtimer:draw()
			else
				--trials_mode.data.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--trials_mode.data.draw.currenttrialtimer:draw()
			end

			-- Draw trial reset reminder if enabled
			if trials_mode.ui_def.trialreset_enabled == "true" then
				trials_mode.data.draw.trialreset_text:draw()
			end

			-- Draw trialsteps bg overlay if enabled
			-- TODO: use the dynamic scaling in the draw loop to adjust the overlay size (new x2, y2 values)
			if trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'] == 'true' then
				local windowKey = 'trialsteps_' .. layout .. '_bg_overlay_window'
				if trials_mode.ui_def.textbox_visible == 'true' and trials_mode.data.trial[ct].textbox ~= '' then
					windowKey = 'trialsteps_' .. layout .. '_bg_overlay_window_withtextbox'
				end
				
				local bgoverlay = rect:create({})
				bgoverlay:update({
					x1 = trials_mode.ui_def[windowKey][1],
					y1 = trials_mode.ui_def[windowKey][2],
					x2 = trials_mode.ui_def[windowKey][3],
					y2 = trials_mode.ui_def[windowKey][4],
					r = trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_col'][1],
					g = trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_col'][2],
					b = trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_col'][3],
					src = trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_alpha'][1],
					dst = trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_alpha'][2],
					defsc = false,
				})
				bgoverlay:draw()
			end

			-- Draw trialstep background
			animUpdate(trials_mode.ui_def['trialsteps_' .. layout .. '_bg_data'])
			animDraw(trials_mode.ui_def['trialsteps_' .. layout .. '_bg_data'])
			animUpdate(trials_mode.ui_def['trialsteps_' .. layout .. '_bg_data'])
			animDraw(trials_mode.ui_def['trialsteps_' .. layout .. '_bg_data'])

			-- Draw trial title
			animUpdate(trials_mode.ui_def['trialtitle_' .. layout .. '_bg_data'])
			animDraw(trials_mode.ui_def['trialtitle_' .. layout .. '_bg_data'])
			trials_mode.data.draw[layout].trialtitle_text:update({text = trials_mode.data.trial[ct].name})
			trials_mode.data.draw[layout].trialtitle_text:draw()
			animUpdate(trials_mode.ui_def['trialtitle_' .. layout .. '_front_data'])
			animDraw(trials_mode.ui_def['trialtitle_' .. layout .. '_front_data'])

			local startonstep = 1
			local drawtothisstep = #trials_mode.data.trial[ct].trialstep

			--Determine whether textboxes are being shown and whether the current trial has a textbox to display, and if so, draw them!
			--Also adjust the window range to account for the textbox as specified in the motif
			if trials_mode.ui_def.textbox_visible == 'true' and trials_mode.data.trial[ct].textbox ~= '' then
				windowYrange = trials_mode.data.draw[layout].windowYrangeWtext
				windowXrange = trials_mode.data.draw[layout].windowXrangeWtext

				if trials_mode.ui_def.textbox_overlay_visible == 'true' then
					textboxoverlay = rect:create({})
					textboxoverlay:update({
						x1 =    trials_mode.ui_def.textbox_pos[1]+trials_mode.ui_def.textbox_overlay_window[1],
						y1 =    trials_mode.ui_def.textbox_pos[2]+trials_mode.ui_def.textbox_overlay_window[2],
						x2 =    trials_mode.ui_def.textbox_pos[1]+trials_mode.ui_def.textbox_overlay_window[3],
						y2 =    trials_mode.ui_def.textbox_pos[2]+trials_mode.ui_def.textbox_overlay_window[4],
						r =     trials_mode.ui_def.textbox_overlay_col[1],
						g =     trials_mode.ui_def.textbox_overlay_col[2],
						b =     trials_mode.ui_def.textbox_overlay_col[3],
						src =   trials_mode.ui_def.textbox_overlay_alpha[1],
						dst =   trials_mode.ui_def.textbox_overlay_alpha[2],
						defsc = false,
					})
					textboxoverlay:draw()
				end

				animUpdate(trials_mode.ui_def.textbox_bg_data)
				animDraw(trials_mode.ui_def.textbox_bg_data)

				-- Draw text
				local trtext = trials_mode.ui_def.textbox_title_text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', trials_mode.data.trial[ct].name)
				trials_mode.data.draw.textbox_title:update({text = trtext})
				trials_mode.data.draw.textbox_title:draw()

				if not trials_mode.data.draw.draw_textbox_text then
					trials_mode.data.trial[ct].textcnt = trials_mode.data.trial[ct].textcnt + 1
				end
				trials_mode.data.draw.draw_textbox_text = main.f_textRender(
					trials_mode.data.draw.textbox_text,
					trials_mode.data.trial[ct].textbox,
					trials_mode.data.trial[ct].textcnt,
					trials_mode.ui_def.textbox_text_window[1]+trials_mode.ui_def.textbox_text_offset[1],
					trials_mode.ui_def.textbox_text_window[2]+trials_mode.ui_def.textbox_text_offset[2],
					0,
					0,
					main.font_def[trials_mode.ui_def.textbox_text_font[1] .. trials_mode.ui_def.textbox_text_font[7]],
					trials_mode.ui_def.textbox_text_drawspeed,
					main.f_lineLength(
						trials_mode.ui_def.textbox_text_offset[1],
						motif.info.localcoord[1],
						trials_mode.ui_def.textbox_text_font[3],
						trials_mode.ui_def.textbox_text_window,
						true
					)
				)

				-- Draw portrait depending on desired source
				if trials_mode.ui_def.textbox_portrait_source == "system" then
					animUpdate(trials_mode.ui_def.textbox_portrait_data)
					animDraw(trials_mode.ui_def.textbox_portrait_data)
				elseif trials_mode.ui_def.textbox_portrait_source == "char" then
					charSpriteDraw(
						-- pn, spr_tbl (1 or more pairs), x, y, scaleX, scaleY, facing, window
						1,
						trials_mode.ui_def.textbox_portrait_spr,
						trials_mode.ui_def.textbox_pos[1] + trials_mode.ui_def.textbox_portrait_offset[1],
						trials_mode.ui_def.textbox_pos[2] + trials_mode.ui_def.textbox_portrait_offset[2],
						trials_mode.ui_def.textbox_portrait_scale[1],
						trials_mode.ui_def.textbox_portrait_scale[2],
						trials_mode.ui_def.textbox_portrait_facing,
						trials_mode.ui_def.textbox_pos[1] + trials_mode.ui_def.textbox_portrait_offset[1] + trials_mode.ui_def.textbox_portrait_window[1],
						trials_mode.ui_def.textbox_pos[2] + trials_mode.ui_def.textbox_portrait_offset[2] + trials_mode.ui_def.textbox_portrait_window[2],
						trials_mode.ui_def.textbox_portrait_window[3],
						trials_mode.ui_def.textbox_portrait_window[4]
					)
				end

				-- Draw textbox front
				animUpdate(trials_mode.ui_def.textbox_front_data)
				animDraw(trials_mode.ui_def.textbox_front_data)
			else
				windowYrange = trials_mode.data.draw[layout].windowYrange
				windowXrange = trials_mode.data.draw[layout].windowXrange
			end

			--For vertical trial layouts, determine if all assets will be drawn within the trials window range, or if scrolling needs to be enabled. For horizontal layouts, we will figure it out
			--when we determine glyph and incrementor widths (see notes below). We do this step outside of the draw loop to speed things up.
			if #trials_mode.data.trial[ct].trialstep*trials_mode.ui_def['trialsteps_' .. layout .. '_spacing'][2] > windowYrange and layout == "vertical" then
				startonstep = math.max(cts-2, 1)
				if (drawtothisstep - startonstep)*trials_mode.ui_def['trialsteps_' .. layout .. '_spacing'][2] > windowYrange then
					drawtothisstep = math.min(startonstep+math.floor(windowYrange/trials_mode.ui_def['trialsteps_' .. layout .. '_spacing'][2]),#trials_mode.data.trial[ct].trialstep)
				end
			end

			--This is the draw loop
			for i = startonstep, drawtothisstep, 1 do
				local tempoffset = {trials_mode.ui_def['trialsteps_' .. layout .. '_spacing'][1]*(i-startonstep),trials_mode.ui_def['trialsteps_' .. layout .. '_spacing'][2]*(i-startonstep)}
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

				-- if trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'] == 'true' then
				-- 	bgoverlay = rect:create({})
				-- 	bgoverlay:update({
				-- 		x1 =    trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		y1 =    trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		x2 =    trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		y2 =    trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][4],
				-- 		r =     trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		g =     trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		b =     trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		src =   trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		dst =   trials_mode.ui_def['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		defsc = false,
				-- 	})
				-- 	bgoverlay:draw()
				-- end

				if layout == "vertical" then
					--Vertical layouts are the simplest - they have a constant width sprite or anim that the text is drawn on top of, and the glyphs are displayed wherever specified.
					--The vertical layouts do NOT support incrementors (see notes below for horizontal layout).
					animSetPos(
						trials_mode.ui_def[sub .. 'step_vertical_bg_data'],
						trials_mode.ui_def.trialsteps_vertical_pos[1] + trials_mode.ui_def[sub .. 'step_vertical_bg_offset'][1] + tempoffset[1],
						trials_mode.ui_def.trialsteps_vertical_pos[2] + trials_mode.ui_def[sub .. 'step_vertical_bg_offset'][2] + tempoffset[2]
					)
					trials_mode.data.draw.vertical[sub .. 'textline'][i]:update({
						x = trials_mode.ui_def.trialsteps_vertical_pos[1]+trials_mode.ui_def[sub .. 'step_vertical_text_offset'][1]+trials_mode.ui_def.trialsteps_vertical_spacing[1]*(i-startonstep),
						y = trials_mode.ui_def.trialsteps_vertical_pos[2]+trials_mode.ui_def[sub .. 'step_vertical_text_offset'][2]+trials_mode.ui_def.trialsteps_vertical_spacing[2]*(i-startonstep),
						text = trials_mode.data.trial[ct].trialstep[i].text
					})
					animSetPalFX(trials_mode.ui_def[sub .. 'step_vertical_bg_data'], {
						time = 1,
						add = trials_mode.ui_def[sub .. 'step_vertical_bg_palfx_add'],
						mul = trials_mode.ui_def[sub .. 'step_vertical_bg_palfx_mul'],
						sinadd = trials_mode.ui_def[sub .. 'step_vertical_bg_palfx_sinadd'],
						invertall = trials_mode.ui_def[sub .. 'step_vertical_bg_palfx_invertall'],
						color = trials_mode.ui_def[sub .. 'step_vertical_bg_palfx_color']
					})
					animReset(trials_mode.ui_def[sub .. 'step_vertical_bg_data'])
					animUpdate(trials_mode.ui_def[sub .. 'step_vertical_bg_data'])
					animDraw(trials_mode.ui_def[sub .. 'step_vertical_bg_data'])
					trials_mode.data.draw.vertical[sub .. 'textline'][i]:draw()
				elseif layout == "horizontal" then
					--Horizontal layouts are much more complicated. Text is not drawn in horizontal mode, instead we only display the glyphs. A small sprite is dynamically tiled to the width of the
					--glyphs, and an optional background element called an incrementor (bginc) can be used to link the pieces together (think of an arrow where the body of the arrow is where the
					--glyphs are being drawn and that's the dynamically sized part, and the head of the arrow is the incrementor which is a fixed width sprite). There's quite a bit more work that
					--goes into displaying the horizontal layouts because the code needs to figure out the window size, and determine when it needs to "go to the next line" and create a return so
					--that trials can be displayed dynamically. Back to the arrow analogy, you always want an arrow body to have an arrow head, so the incrementor width is added to the glyphs length
					--and the padding factor specified in the motif data, it's all added together until the window width is met or exceeded, then a line return occurs and the next line is drawn.
					local bgsize = {0,0}
					if trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'] ~= nil then bgtailwidth = math.floor(trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgtailwidth'].Size[1]) end
					if trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'] ~= nil then bgheadwidth = math.floor(trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgheadwidth'].Size[1]) end
					if trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgsize'] ~= nil then bgsize = trials_mode.data.bgelemdata.horizontal[sub .. 'step_bgsize'].Size end

					totalglyphlength = trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[#trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset]
					local tailoffset = trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_offset'][1]
					padding = trials_mode.ui_def.trialsteps_horizontal_padding
					spacing = trials_mode.ui_def.trialsteps_horizontal_spacing[1]

					local tempwidth = spacing + bgtailwidth + padding + totalglyphlength + padding + bgheadwidth + accwidth
					if tempwidth - trials_mode.ui_def.trialsteps_horizontal_spacing[1] > windowXrange then
						accwidth = 0
						addrow = addrow + 1
					end

					tempoffset[2] = trials_mode.ui_def.trialsteps_horizontal_spacing[2]*(addrow)

					-- Calculate initial positions
					if accwidth == 0 then
						bgcomponentposX = trials_mode.ui_def.trialsteps_horizontal_pos[1]
					else
						bgcomponentposX = accwidth + spacing -- + bgheadwidth 
					end
					
					-- Draw tail
					animSetPos(trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_data'], 
						bgcomponentposX + trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_offset'][1], 
						trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_offset'][2] + tempoffset[2]
					)
					animSetPalFX(trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_data'], {
						time = 1,
						add = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_data'])
					animUpdate(trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_data'])
					animDraw(trials_mode.ui_def[sub .. 'step_horizontal_bg_tail_data'])
					
					-- Draw BG for Glyphs - scale to length, start from tail pos
					bgtargetscale = {(padding + totalglyphlength + padding)/bgsize[1], 1}
					bgcomponentposX = bgcomponentposX + bgtailwidth
					local gpoffset = 0
					for m in pairs(trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.glyph) do
						if m > 1 then gpoffset = trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[m-1] end
						trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.pos[m][1] = bgcomponentposX + padding + gpoffset -- trials_mode.ui_def.trialsteps_pos[1] + trials_mode.data.trial[ct].trialstep[i].glyphline.alignOffset[m] +
					end

					animSetScale(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'], bgtargetscale[1], bgtargetscale[2])
					animSetPos(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'], 
						bgcomponentposX + trials_mode.ui_def[sub .. 'step_horizontal_bg_offset'][1], 
						trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials_mode.ui_def[sub .. 'step_horizontal_bg_offset'][2] + tempoffset[2]
					)
					animSetPalFX(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'], {
						time = 1,
						add = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'])
					animUpdate(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'])
					animDraw(trials_mode.ui_def[sub .. 'step_horizontal_bg_data'])
					
					-- Draw head
					bgcomponentposX = bgcomponentposX + (totalglyphlength + 2*padding)
					animSetPos(trials_mode.ui_def[sub .. 'step_horizontal_bg_head_data'], 
						bgcomponentposX + trials_mode.ui_def[sub .. 'step_horizontal_bg_head_offset'][1] + trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.alignOffset[1], 
						trials_mode.data.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + trials_mode.ui_def[sub .. 'step_horizontal_bg_head_offset'][2] + tempoffset[2]
					)
					animSetPalFX(trials_mode.ui_def[sub .. 'step_horizontal_bg_head_data'], {
						time = 1,
						add = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_add'],
						mul = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = trials_mode.ui_def[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(trials_mode.ui_def[sub .. 'step_horizontal_bg_head_data'])
					animUpdate(trials_mode.ui_def[sub .. 'step_horizontal_bg_head_data'])
					animDraw(trials_mode.ui_def[sub .. 'step_horizontal_bg_head_data'])
				end
				for m = 1, #trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph, 1 do
					animSetScale(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, trials_mode.data.trial[ct].trialstep[i].glyphline[layout].scale[m][1], trials_mode.data.trial[ct].trialstep[i].glyphline[layout].scale[m][2])
					animSetPos(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, 
						trials_mode.data.trial[ct].trialstep[i].glyphline[layout].pos[m][1], 
						trials_mode.data.trial[ct].trialstep[i].glyphline[layout].pos[m][2] + tempoffset[2] + trials_mode.ui_def['glyphs_' .. layout .. '_offset'][2]
					)
					animSetPalFX(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, {
						time = 1,
						add = trials_mode.ui_def[sub .. 'step_' .. layout .. '_glyphs_palfx_add'],
						mul = trials_mode.ui_def[sub .. 'step_' .. layout .. '_glyphs_palfx_mul'],
						sinadd = trials_mode.ui_def[sub .. 'step_' .. layout .. '_glyphs_palfx_sinadd'],
						invertall = trials_mode.ui_def[sub .. 'step_' .. layout .. '_glyphs_palfx_invertall'],
						color = trials_mode.ui_def[sub .. 'step_' .. layout .. '_glyphs_palfx_color']
					})
					animReset(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
					animUpdate(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
					animDraw(motif.glyphs_data[trials_mode.data.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
				end
				accwidth = bgcomponentposX
			end
		elseif ct > #trials_mode.data.trial then
			-- All trials have been completed, draw the all clear and freeze the timer
			if trials_mode.data.draw.allclear ~= 0 then
				start.f_trialsSuccess('allclear', ct-1)
				main.f_createTextImg(trials_mode.ui_def, 'allclear_text')
			end

			trials_mode.data.allclear = true
			trials_mode.data.draw.success = 0
			trials_mode.data.draw.trialcounter:update({text = trials_mode.ui_def.trialcounter_allclear_text})
			trials_mode.data.draw.trialcounter:draw()

			if trials_mode.data.displaytimers.totaltimer then
				local totaltimertext = trials_mode.ui_def.totaltrialtimer_text
				local m, s, x = f_timeConvert(trials_mode.data.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials_mode.data.draw.totaltrialtimer:update({text = totaltimertext})
				trials_mode.data.draw.totaltrialtimer:draw()
			else
				--trials_mode.data.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--trials_mode.data.draw.totaltrialtimer:draw()
			end
			if trials_mode.data.displaytimers.trialtimer then
				local currenttimertext = trials_mode.ui_def.currenttrialtimer_text
				local m, s, x = f_timeConvert(trials_mode.data.trial[ct-1].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				trials_mode.data.draw.currenttrialtimer:update({text = currenttimertext})
				trials_mode.data.draw.currenttrialtimer:draw()
			else
				--trials_mode.data.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--trials_mode.data.draw.currenttrialtimer:draw()
			end
		end
	end
end

function start.f_trialsChecker()
	--This function sets dummy actions according to the character trials info and validates trials attempts
	--To help follow along, ct = current trial, cts = current trial step, ncts = next current trial step
	if ct <= #trials_mode.data.trial and trials_mode.data.draw.success == 0 and trials_mode.data.draw.fade == 0 and trials_mode.data.active then
		local helpercheck = false
		local projcheck = false
		local maincharcheck = false
		local statecheck = false
		local animcheck = true

		player(2)
		local attackerid = gethitvar('id')
		player(1)
		local attackerstate = nil
		local attackeranim = nil
		if attackerid > 0 then
			playerid(attackerid)
			attackerstate = stateno()
			attackeranim = anim()
			player(1)
			-- Can uncomment this section to debug helper/proj data
			-- print("ID: " .. attackerid)
			-- print("State: " .. attackerstate)
			-- print("Anim: " .. attackeranim)
		end

		-- Check states and anims; iterate over 'or' operand if multiple states and/or anims are provided
		local desiredstates = trials_mode.data.trial[ct].trialstep[cts].stateno[ctms]
		for k = 1, #desiredstates, 1 do
			if stateno() == desiredstates[k] or attackerstate == desiredstates[k] then
				statecheck = true
				break
			end
		end
		if trials_mode.data.trial[ct].trialstep[cts].animno[ctms] ~= nil then
			animcheck = false
			local desiredanims = trials_mode.data.trial[ct].trialstep[cts].animno[ctms]
			for k = 1, #desiredanims, 1 do
				if anim() == desiredanims[k] or attackeranim == desiredanims[k] then
					animcheck = true
					break
				end
			end
		end

		if (trials_mode.data.trial[ct].trialstep[cts].ishelper[ctms] and statecheck) and animcheck then
			helpercheck = true
			if trials_mode.data.trial[ct].trialstep[cts].validforvar ~= nil and helpercheck then
				for i = 1, #trials_mode.data.trial[ct].trialstep[cts].validforvar, 1 do
					if helpercheck then
						helpercheck = var(trials_mode.data.trial[ct].trialstep[cts].validforvar[i]) == trials_mode.data.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		if (trials_mode.data.trial[ct].trialstep[cts].isproj[ctms] and statecheck) and animcheck then
			projcheck = true
			if trials_mode.data.trial[ct].trialstep[cts].validforvar ~= nil and projcheck then
				for i = 1, #trials_mode.data.trial[ct].trialstep[cts].validforvar, 1 do
					if projcheck then
						projcheck = var(trials_mode.data.trial[ct].trialstep[cts].validforvar[i]) == trials_mode.data.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		maincharcheck = (statecheck and not(trials_mode.data.trial[ct].trialstep[cts].isproj[ctms]) and not(trials_mode.data.trial[ct].trialstep[cts].ishelper[ctms]) and animcheck and ((movehit() and combocount() > trials_mode.data.combocounter) or trials_mode.data.trial[ct].trialstep[cts].isthrow[ctms] or trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == 0))
		if trials_mode.data.trial[ct].trialstep[cts].validforvar ~= nil and maincharcheck then
			for i = 1, #trials_mode.data.trial[ct].trialstep[cts].validforvar, 1 do
				if maincharcheck then
					maincharcheck = var(trials_mode.data.trial[ct].trialstep[cts].validforvar[i]) == trials_mode.data.trial[ct].trialstep[cts].validforval[i]
				end
			end
		end		

		if trials_mode.data.validfortickcount > 0 then
			trials_mode.data.validfortickcount = trials_mode.data.validfortickcount - 1
		end
		
		if maincharcheck or projcheck or helpercheck then
			if trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] >= 1 then
				if trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] == 0 then
					trials_mode.data.trial[ct].trialstep[cts].combocountonstep[ctms] = combocount()
				end
				if combocount() - trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] == trials_mode.data.trial[ct].trialstep[cts].combocountonstep[ctms] then
					trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] = trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] + 1
				end
			elseif trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == 0 then
				trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			end

			if trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] then
				nctms = ctms + 1
				-- First, check that the microstep has passed
				if nctms >= 1 and ((combocount() > 0 and (trials_mode.data.trial[ct].trialstep[cts].iscounterhit[ctms] and movecountered() > 0) or not trials_mode.data.trial[ct].trialstep[cts].iscounterhit[ctms]) or trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
					if nctms >= 1 and ((trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] > 1 and combocount() == trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] + trials_mode.data.trial[ct].trialstep[cts].combocountonstep[ctms] - 1) or trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == 1 or trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
						trials_mode.data.currenttrialmicrostep = nctms
						if trials_mode.data.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
							trials_mode.data.validfortickcount = trials_mode.data.trial[ct].trialstep[cts].validfortickcount[ctms]
						else
							trials_mode.data.validfortickcount = 0
						end
						trials_mode.data.combocounter = combocount()
					elseif ((combocount() == 0 and trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and trials_mode.data.validfortickcount == 0) or (trials_mode.data.validfortickcount > 0 and combocount() > trials_mode.data.combocounter) then
						trials_mode.data.currenttrialstep = 1
						trials_mode.data.currenttrialmicrostep = 1
						trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
						trials_mode.data.trial[ct].trialstep[cts].combocountonstep[ctms] = 0
						trials_mode.data.combocounter = 0
						trials_mode.data.validfortickcount = 0
					end
				end
				-- Next, if microstep is exceeded, go to next trial step
				if trials_mode.data.currenttrialmicrostep > trials_mode.data.trial[ct].trialstep[cts].numofmicrosteps then
					trials_mode.data.currenttrialmicrostep = 1
					trials_mode.data.currenttrialstep = cts + 1
					if trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0 and combocount() == 0 and combocount() == trials_mode.data.combocounter then
						trials_mode.data.combocounter = trials_mode.data.combocounter + 1
					else
						trials_mode.data.combocounter = combocount()
					end	
					if trials_mode.data.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
						trials_mode.data.validfortickcount = trials_mode.data.trial[ct].trialstep[cts].validfortickcount[ctms]
					else
						trials_mode.data.validfortickcount = 0
					end
					if trials_mode.data.currenttrialstep > #trials_mode.data.trial[ct].trialstep then
						-- If trial step was last, go to next trial and display success banner
						if trials_mode.data.trialadvancement then
							trials_mode.data.currenttrial = ct + 1
						end
						trials_mode.data.currenttrialstep = 1
						trials_mode.data.combocounter = 0
						if ct < #trials_mode.data.trial or (not trials_mode.data.trialadvancement and ct == #trials_mode.data.trial) then
							if (trials_mode.ui_def.success_front_displaytime == -1) and (trials_mode.ui_def.success_bg_displaytime == -1) then
								trials_mode.data.draw.success = math.max(animGetLength(trials_mode.ui_def.success_front_data), animGetLength(trials_mode.ui_def.success_bg_data), trials_mode.ui_def.success_text_displaytime)
							else
								trials_mode.data.draw.success = math.max(trials_mode.ui_def.success_front_displaytime, trials_mode.ui_def.success_bg_displaytime, trials_mode.ui_def.success_text_displaytime)
							end
							if trials_mode.ui_def.trialsresetonsuccess == "true" then
								trials_mode.data.draw.fadein = trials_mode.ui_def.fadein_time
								trials_mode.data.draw.fadeout = trials_mode.ui_def.fadeout_time
								trials_mode.data.draw.fade = trials_mode.data.draw.fadein + trials_mode.data.draw.fadeout
							end
						end
					end
				end
			end
		elseif ((combocount() == 0 and trials_mode.data.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and trials_mode.data.validfortickcount == 0) or (trials_mode.data.validfortickcount > 0 and combocount() > trials_mode.data.combocounter) then
			trials_mode.data.currenttrialstep = 1
			trials_mode.data.currenttrialmicrostep = 1
			trials_mode.data.combocounter = 0
			trials_mode.data.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			trials_mode.data.trial[ct].trialstep[cts].combocountonstep[ctms] = 0
			trials_mode.data.validfortickcount = 0
		end
	end
	--If the trial was completed successfully, draw the trials success
	if trials_mode.data.draw.success > 0 then
		start.f_trialsSuccess('success', ct)
	elseif trials_mode.data.draw.fade > 0 and (trials_mode.ui_def.trialsresetonsuccess == "true" or trials_mode.data.draw.fadetriggered) then
		if trials_mode.data.draw.fade < trials_mode.data.draw.fadein + trials_mode.data.draw.fadeout then
			start.f_trialsFade()
		else
			player(2)
			if stateno() == 0 then
				start.f_trialsFade()
			end
			player(1)
		end
	elseif f_checkKeyCombo(trials_mode.ui_def.trialreset_buttonpress) and trials_mode.data.draw.fade == 0 and trials_mode.ui_def.trialreset_enabled == "true" then
		trials_mode.data.draw.fadein = trials_mode.ui_def.fadein_time
		trials_mode.data.draw.fadeout = trials_mode.ui_def.fadeout_time
		trials_mode.data.draw.fade = trials_mode.data.draw.fadein + trials_mode.data.draw.fadeout
		trials_mode.data.draw.fadetriggered = true
	else
		trials_mode.data.draw.fadetriggered = false
	end
end

function start.f_trialsSuccess(successstring, index)
	-- This function is responsible for drawing the Success or All Clear banners after a trial is completed successfully.
	mapSet('_iksys_trialsDummyMode', 0)
	mapSet('_iksys_trialsGuardMode', 0)
	mapSet('_iksys_trialsButtonJam', 0)
	player(1)
	if not trials_mode.data.trial[index].complete or (successstring == "allclear" and not trials_mode.data.allclear) then
		-- Play sound only once
		sndPlay(motif.files.snd_data, trials_mode.ui_def[successstring .. '_snd'][1], trials_mode.ui_def[successstring .. '_snd'][2])
	end
	animUpdate(trials_mode.ui_def[successstring .. '_bg_data'])
	animDraw(trials_mode.ui_def[successstring .. '_bg_data'])
	trials_mode.data.draw[successstring .. '_text']:draw()
	animUpdate(trials_mode.ui_def[successstring .. '_front_data'])
	animDraw(trials_mode.ui_def[successstring .. '_front_data'])
	trials_mode.data.draw[successstring] = trials_mode.data.draw[successstring] - 1
	trials_mode.data.trial[index].complete = true
	trials_mode.data.trial[index].active = false
	trials_mode.data.active = false
	if not trials_mode.data.trialadvancement then
		trials_mode.data.trial[index].starttick = roundtime()
	end
	if index ~= #trials_mode.data.trial then
		trials_mode.data.trial[index+1].starttick = roundtime()
	end
end

function start.f_trialsFade()
	local stagelocalcoordX = stagevar("stageinfo.localcoord.x")
	local stageboundleft = stagevar("bound.screenleft")
	local stageboundright = stagevar("bound.screenright")
	local dummyposx = stagevar("playerinfo.p2startx") / (stagelocalcoordX/320)
	local dummyposy = stagevar("playerinfo.p2starty") / (stagelocalcoordX/320)
	local playerposx = stagevar("playerinfo.p1startx") / (stagelocalcoordX/320)
	local playerposy = stagevar("playerinfo.p1starty") / (stagelocalcoordX/320)
	local leftbound = stagevar("camera.boundleft")
	local rightbound = stagevar("camera.boundright")
	local cameraPosX = 0
	local posx = 0
	local oppx = 0

	if trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'left-corner' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'left-corner' then
		cameraPosX = leftbound / (stagelocalcoordX/320)
		posx = - (stagelocalcoordX/2 - stageboundleft) / (stagelocalcoordX/320)
		if trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'close' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'close' then
			oppx = posx + 10
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'far' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'far' then
			oppx = posx + 260
		else --medium or nil
			oppx = posx + 130
		end
		if trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'left-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'right-corner' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'right-corner' then
		cameraPosX = rightbound / (stagelocalcoordX/320)
		posx = (stagelocalcoordX/2 - stageboundright) / (stagelocalcoordX/320)
		if trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'close' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'close' then
			oppx = posx - 10
		elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'far' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'far' then
			oppx = posx - 260
		else --medium or nil
			oppx = posx - 130
		end
		if trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'right-corner' then
			dummyposx = posx
			playerposx = oppx
		else
			playerposx = posx
			dummyposx = oppx
		end
	elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'close' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'close' then
		dummyposx = 5
		playerposx = -5
	elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'medium' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'medium' then
		dummyposx = 65
		playerposx = -65
	elseif trials_mode.data.trial[trials_mode.data.currenttrial].dummypos == 'far' or trials_mode.data.trial[trials_mode.data.currenttrial].playerpos == 'far' then
		dummyposx = 130
		playerposx = -130
	end

	mapSet('_iksys_trialsCameraPosX', cameraPosX)
	mapSet('_iksys_trialsDummyPosX', dummyposx)
	mapSet('_iksys_trialsDummyPosY', dummyposy)
	mapSet('_iksys_trialsPlayerPosX', playerposx)
	mapSet('_iksys_trialsPlayerPosY', playerposy)
	
	-- This function is responsible for fadein/fadeout if trialsresetonsuccess is set to true.
	if trials_mode.data.draw.fadeout > 0 then
		if not main.fadeActive then
			main.f_fadeReset('fadeout',trials_mode.ui_def)
		end
		main.f_fadeAnim(trials_mode.ui_def)
		trials_mode.data.draw.fadeout = trials_mode.data.draw.fadeout - 1
	elseif trials_mode.data.draw.fadein > 0 then
		if main.fadeType == 'fadeout' then
			mapSet('_iksys_trialsReposition', 1)
			main.f_fadeReset('fadein',trials_mode.ui_def)
		elseif main.fadeType == 'fadein' then
			mapSet('_iksys_trialsCameraReset', 1)
		end
		main.f_fadeAnim(trials_mode.ui_def)
		trials_mode.data.draw.fadein = trials_mode.data.draw.fadein - 1
	end

	trials_mode.data.draw.fade = trials_mode.data.draw.fade - 1
end

function start.f_trialsSelectScreen()
-- Grays out portaits on the trial select screen for characters without trials files
	local selectScreenPalMod = false

	if gamemode("trials") and start.selectScreenPalMod == 'normal' then
		paladd = trials_mode.ui_def.selscreenpalfx_add
		palmul = trials_mode.ui_def.selscreenpalfx_mul
		palsinadd = trials_mode.ui_def.selscreenpalfx_sinadd
		palinvertall = trials_mode.ui_def.selscreenpalfx_invertall
		palcolor = trials_mode.ui_def.selscreenpalfx_color
		start.selectScreenPalMod = 'darkened'
		selectScreenPalMod = true
	elseif not gamemode("trials") and start.selectScreenPalMod == 'darkened' then
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
						-- 	add = trials_mode.ui_def.selscreenpalfx_add,
						-- 	mul = trials_mode.ui_def.selscreenpalfx_mul,
						-- 	sinadd = trials_mode.ui_def.selscreenpalfx_sinadd,
						-- 	invertall = trials_mode.ui_def.selscreenpalfx_invertall,
						-- 	color = trials_mode.ui_def.selscreenpalfx_color
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

function start.f_trialsMode()
	if roundstart() then
		trials_mode.data = nil
		-- Check if there's a trials file - if so, parse it
		if start.f_getCharData(start.p[1].t_selected[1].ref).trialsdef ~= "" then
			start.f_inittrialsData()
			trialsExist = true
 		else
			trialsExist = false
		end
	end

	if trialsExist and roundstate() == 2 and not trials_mode.data.trialsInitialized then
		-- Initialize the trials based on parsed file and char state at roundstate() == 2
		start.f_trialsBuilder()
		menu.f_trialsReset()
	elseif trialsExist and roundstate() == 2 and trials_mode.data.trialsInitialized then
		-- If trials initialized, draw elements and check for success!
		start.f_trialsDrawer()
		start.f_trialsChecker()
	elseif roundstate() == 2 then
		-- No trials present!
		player(2)
		setAILevel(0)
		mapSet('_iksys_trialsSetLife', lifemax())
		player(1)
		mapSet('_iksys_trialsDummyControl', 0)
		mapSet('_iksys_trialsSetLife', lifemax())
		trialcounter = main.f_createTextImg(trials_mode.ui_def, 'trialcounter')
		trialcounter:update({x = trials_mode.ui_def.trialcounter_pos[1], y = trials_mode.ui_def.trialcounter_pos[2], text = trials_mode.ui_def.trialcounter_notrialsdata_text})
		trialcounter:draw()
	end
end

--;===========================================================
--; menu.lua
--;===========================================================
menu.t_valuename.trialslist = {
 	{itemname = "0", displayname = "Select Trial"},
}
menu.t_valuename.trialadvancement = {
	{itemname = "Auto-Advance", displayname = "Auto-Advance"},
	{itemname = "Repeat", displayname = "Repeat"}
}
menu.t_valuename.trialresetonsuccess = {
	{itemname = "Yes", displayname = "Yes"},
	{itemname = "No", displayname = "No"}
}
menu.t_valuename.trialslayout = {
	{itemname = "Vertical", displayname = "Vertical"},
	{itemname = "Horizontal", displayname = "Horizontal"}
}
menu.t_valuename.trialstextboxes = {
	{itemname = "Show", displayname = "Show"},
	{itemname = "Hide", displayname = "Hide"}
}
menu.t_itemname['trialslist'] = function(t, item, cursorPosY, movTeTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		trials_mode.data.currenttrialstep = 1
		trials_mode.data.currenttrialmicrostep = 1
		trials_mode.data.currenttrial = menu.trialslist
		trials_mode.data.trial[trials_mode.data.currenttrial].complete = false
		trials_mode.data.trial[trials_mode.data.currenttrial].active = false
		trials_mode.data.active = false
		trials_mode.data.displaytimers.totaltimer = false
		trials_mode.data.trial[trials_mode.data.currenttrial].starttick = roundtime()
	end
	return true
end
menu.t_vardisplay['trialslist'] = function()
	return menu.t_valuename.trialslist[menu.trialslist or 1].displayname
end

menu.t_itemname['trialadvancement'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		if menu.t_valuename.trialadvancement[menu.trialadvancement or 1].itemname == "Auto-Advance" then
			trials_mode.data.trialadvancement = true
		else
			trials_mode.data.trialadvancement = false
		end
	end
	return true
end
menu.t_vardisplay['trialadvancement'] = function()
	return menu.t_valuename.trialadvancement[menu.trialadvancement or 1].displayname
end

menu.t_itemname['trialslayout'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		if menu.t_valuename.trialslayout[menu.trialslayout or 1].itemname == "Vertical" then
			trials_mode.ui_def.trialslayout = "vertical"
		else
			trials_mode.ui_def.trialslayout = "horizontal"
		end
	end
	return true
end
menu.t_vardisplay['trialslayout'] = function()
	return menu.t_valuename.trialslayout[menu.trialslayout or 1].displayname
end

menu.t_itemname['trialresetonsuccess'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		if menu.t_valuename.trialresetonsuccess[menu.trialresetonsuccess or 1].itemname == "Yes" then
			trials_mode.ui_def.trialsresetonsuccess = "true"
		else
			trials_mode.ui_def.trialsresetonsuccess = "false"
		end
	end
	return true
end
menu.t_vardisplay['trialresetonsuccess'] = function()
	return menu.t_valuename.trialresetonsuccess[menu.trialresetonsuccess or 1].displayname
end

menu.t_itemname['trialstextboxes'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		if menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].itemname == "Show" then
			trials_mode.ui_def.textbox_visible = "true"
		else
			trials_mode.ui_def.textbox_visible = "false"
		end
	end
	return true
end
menu.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end

menu.t_itemname['nexttrial'] = function(t, item, cursorPosY, moveTxt, section)
	if main.f_input(main.t_players, {'pal', 's'}) then
		trials_mode.data.currenttrialstep = 1
		trials_mode.data.currenttrialmicrostep = 1
		sndPlay(motif.files.snd_data, motif[section].cursor_done_snd[1], motif[section].cursor_done_snd[2])
		trials_mode.data.currenttrial = math.min(trials_mode.data.currenttrial + 1, #trials_mode.data.trial)
		trials_mode.data.trial[trials_mode.data.currenttrial].complete = false
		trials_mode.data.trial[trials_mode.data.currenttrial].active = false
		trials_mode.data.active = false
		trials_mode.data.displaytimers.totaltimer = false
		trials_mode.data.trial[trials_mode.data.currenttrial].starttick = roundtime()
	end
	return true
end

menu.t_itemname['previoustrial'] = function(t, item, cursorPosY, moveTxt, section)
	if main.f_input(main.t_players, {'pal', 's'}) then
		trials_mode.data.currenttrialstep = 1
		trials_mode.data.currenttrialmicrostep = 1
		sndPlay(motif.files.snd_data, motif[section].cursor_done_snd[1], motif[section].cursor_done_snd[2])
		trials_mode.data.currenttrial = math.max(trials_mode.data.currenttrial - 1, 1)
		trials_mode.data.trial[trials_mode.data.currenttrial].complete = false
		trials_mode.data.trial[trials_mode.data.currenttrial].active = false
		trials_mode.data.active = false
		trials_mode.data.displaytimers.totaltimer = false
		trials_mode.data.trial[trials_mode.data.currenttrial].starttick = roundtime()
	end
	return true
end

function menu.f_trialsReset()
	for k, _ in pairs(menu.t_valuename) do
		menu[k] = 1
	end
	if trials_mode.ui_def.trialsresetonsuccess == "true" then
		menu.trialresetonsuccess = 1
	else
		menu.trialresetonsuccess = 2
	end
	if trials_mode.ui_def.trialslayout == "vertical" then
		menu.trialslayout = 1
	else
		menu.trialslayout = 2
	end
	if trials_mode.ui_def.textbox_visible == "true" then
		menu.trialstextboxes = 1
	else
		menu.trialstextboxes = 2
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
	mapSet('_iksys_trialsSetLife', lifemax())
	player(1)
	mapSet('_iksys_trialsSetLife', lifemax())
end

--;===========================================================
--; trials.lua
--;===========================================================

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
					combocountonstep = {},
					isthrow = {},
					ishelper = {},
					isproj = {},
					iscounterhit = {},
					validfortickcount = {},
					validforvar = {},
					validforval = {},
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
						starttick = roundtime()+1,
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
				trial[i].trialstep[j].stateno = main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", ""))
				for k = 1, #trial[i].trialstep[j].stateno, 1 do
					local temp = trial[i].trialstep[j].stateno[k]
					trial[i].trialstep[j].stateno[k] = f_str2number(main.f_strsplit('|', temp))
				end
				trial[i].trialstep[j].numofmicrosteps = #trial[i].trialstep[j].stateno
				for k = 1, trial[i].trialstep[j].numofmicrosteps, 1 do
					trial[i].trialstep[j].stephitscount[k] = 0
					trial[i].trialstep[j].combocountonstep[k] = 0
					trial[i].trialstep[j].hitcount[k] = 1
					trial[i].trialstep[j].isthrow[k] = false
					trial[i].trialstep[j].ishelper[k] = false
					trial[i].trialstep[j].isproj[k] = false
					trial[i].trialstep[j].iscounterhit[k] = false
					trial[i].trialstep[j].validforval[k] = nil
					trial[i].trialstep[j].validforvar[k] = nil
					trial[i].trialstep[j].validfortickcount[k] = nil
				end
			elseif lcline:find("trialstep." .. j .. ".animno") then
				if string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", "") ~= "" then
					trial[i].trialstep[j].animno = main.f_strsplit(',', string.gsub(f_trimforchar(lcline, "=", "after"),"%s+", ""))
					for k = 1, #trial[i].trialstep[j].animno, 1 do
						local temp = trial[i].trialstep[j].animno[k]
						trial[i].trialstep[j].animno[k] = f_str2number(main.f_strsplit('|', temp))
					end
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
			end
		end
		main.t_selChars[row].trialsdata = trial
	end
end

--;===========================================================
--; global.lua
--;===========================================================
hook.add("loop#trials", "f_trialsMode", start.f_trialsMode)
hook.add("start.f_selectScreen", "f_trialsSelectScreen", start.f_trialsSelectScreen)