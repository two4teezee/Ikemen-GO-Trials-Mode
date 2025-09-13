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

local function f_trimafterchar(line, char)
	-- trims a string after a specified character.
	-- also trims leading and trailing whitespace
	x = string.find(line, char)
	if x ~= nil then
		line = string.sub(line, x+1, #line)
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

--;===========================================================
--; main.lua
--;===========================================================
main.t_itemname.trials = function()
	setHomeTeam(1)
	main.f_playerInput(main.playerInput, 1)
	main.t_pIn[2] = 1
	if main.t_charDef[gameOption('Config.TrainingChar'):lower()] ~= nil then
		main.forceChar[2] = {main.t_charDef[gameOption('Config.TrainingChar'):lower()]}
  	end
	--main.lifebar.p1score = false
	--main.lifebar.p2aiLevel = true
	main.roundTime = -1
	main.selectMenu[2] = true
	main.stageMenu = true
	main.teamMenu[1].ratio = false
	main.teamMenu[1].simul = false
	main.teamMenu[1].single = true
	main.teamMenu[1].tag = false
	main.teamMenu[1].turns = false
	main.teamMenu[2].single = true
	main.txt_mainSelect:update({text = motif.select_info.title_trials_text})
	setGameMode('trials')
	hook.run("main.t_itemname")
	return start.f_selectMode
end

--;===========================================================
--; motif.lua
--;===========================================================
if motif.select_info.title_trials_text == nil then
	motif.select_info.title_trials_text = 'Trials'
end

local t_base = {
    trialsresetonsuccess = "false",
    trialslayout = "vertical",
	trialsteps_vertical_pos = {0, 0},
    trialsteps_vertical_spacing = {0, 0},
    trialsteps_vertical_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	trialsteps_vertical_window_withtextbox = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	trialsteps_horizontal_pos = {0, 0},
    trialsteps_horizontal_spacing = {0, 0},
	trialsteps_horizontal_padding = 0,
    trialsteps_horizontal_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	trialsteps_horizontal_window_withtextbox = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	trialsteps_vertical_bg_anim = -1,
    trialsteps_vertical_bg_spr = {},
    trialsteps_vertical_bg_offset = {0, 0},
    trialsteps_vertical_bg_facing = 1,
    trialsteps_vertical_bg_scale = {1.0, 1.0},
    trialsteps_vertical_bg_displaytime = 0,
	-- trialsteps_vertical_bg_overlay_visible = "false",
	-- trialsteps_vertical_bg_overlay_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	-- trialsteps_vertical_bg_overlay_window_withtextbox = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	-- trialsteps_vertical_bg_overlay_col = {0, 0, 0},
	-- trialsteps_vertical_bg_overlay_alpha = {0, 128},
	trialsteps_horizontal_bg_anim = -1,
    trialsteps_horizontal_bg_spr = {},
    trialsteps_horizontal_bg_offset = {0, 0},
    trialsteps_horizontal_bg_facing = 1,
    trialsteps_horizontal_bg_scale = {1.0, 1.0},
    trialsteps_horizontal_bg_displaytime = 0,
	-- trialsteps_horizontal_bg_overlay_visible = "false",
	-- trialsteps_horizontal_bg_overlay_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	-- trialsteps_horizontal_bg_overlay_window_withtextbox = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	-- trialsteps_horizontal_bg_overlay_col = {0, 0, 0},
	-- trialsteps_horizontal_bg_overlay_alpha = {0, 128},
	selscreenpalfx_add = {},
	selscreenpalfx_mul = {},
	selscreenpalfx_sinadd = {},
	selscreenpalfx_invertall = 0,
	selscreenpalfx_color = 256,
	fadein_time = 40, --Ikemen feature
	fadein_col = {0, 0, 0}, --Ikemen feature
	fadein_anim = -1, --Ikemen feature
	fadeout_time = 40, --Ikemen feature
	fadeout_col = {0, 0, 0}, --Ikemen feature
	fadeout_anim = -1, --Ikemen feature
	trialtitle_vertical_pos = {0,0},
	trialtitle_vertical_text_offset = {0,0},
    trialtitle_vertical_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    trialtitle_vertical_text_font_height = -1,
    trialtitle_vertical_text_text = '',
	trialtitle_vertical_text_scale = {1.0, 1.0},
    trialtitle_vertical_bg_anim = -1,
    trialtitle_vertical_bg_spr = {},
    trialtitle_vertical_bg_offset = {0, 0},
    trialtitle_vertical_bg_facing = 1,
    trialtitle_vertical_bg_scale = {1.0, 1.0},
    trialtitle_vertical_bg_displaytime = -1,
	trialtitle_vertical_front_anim = -1,
    trialtitle_vertical_front_spr = {},
    trialtitle_vertical_front_offset = {0, 0},
    trialtitle_vertical_front_facing = 1,
    trialtitle_vertical_front_scale = {1.0, 1.0},
    trialtitle_vertical_front_displaytime = -1,
	trialtitle_horizontal_pos = {0,0},
	trialtitle_horizontal_text_offset = {0,0},
    trialtitle_horizontal_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    trialtitle_horizontal_text_font_height = -1,
    trialtitle_horizontal_text_text = '',
	trialtitle_horizontal_text_scale = {1.0, 1.0},
    trialtitle_horizontal_bg_anim = -1,
    trialtitle_horizontal_bg_spr = {},
    trialtitle_horizontal_bg_offset = {0, 0},
    trialtitle_horizontal_bg_facing = 1,
    trialtitle_horizontal_bg_scale = {1.0, 1.0},
    trialtitle_horizontal_bg_displaytime = -1,
	trialtitle_horizontal_front_anim = -1,
    trialtitle_horizontal_front_spr = {},
    trialtitle_horizontal_front_offset = {0, 0},
    trialtitle_horizontal_front_facing = 1,
    trialtitle_horizontal_front_scale = {1.0, 1.0},
    trialtitle_horizontal_front_displaytime = -1,
	upcomingstep_vertical_text_offset = {0,0},
    upcomingstep_vertical_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    upcomingstep_vertical_text_font_height = -1,
    upcomingstep_vertical_text_text = '',
	upcomingstep_vertical_text_scale = {1.0, 1.0},
    upcomingstep_vertical_bg_anim = -1,
    upcomingstep_vertical_bg_spr = {},
    upcomingstep_vertical_bg_offset = {0, 0},
    upcomingstep_vertical_bg_facing = 1,
    upcomingstep_vertical_bg_scale = {1.0, 1.0},
    upcomingstep_vertical_bg_displaytime = -1,
	upcomingstep_vertical_bg_palfx_add = {0, 0, 0},
	upcomingstep_vertical_bg_palfx_mul = {256, 256, 256},
	upcomingstep_vertical_bg_palfx_sinadd = {0, 0, 0},
	upcomingstep_vertical_bg_palfx_invertall = 0,
	upcomingstep_vertical_bg_palfx_color = 256,
	upcomingstep_vertical_glyphs_palfx_add = {0, 0, 0},
	upcomingstep_vertical_glyphs_palfx_mul = {256, 256, 256},
	upcomingstep_vertical_glyphs_palfx_sinadd = {0, 0, 0},
	upcomingstep_vertical_glyphs_palfx_invertall = 0,
	upcomingstep_vertical_glyphs_palfx_color = 256,
	-- text in horizontal layouts not yet supported
    -- upcomingstep_horizontal_text_offset = {0,0},
    -- upcomingstep_horizontal_text_font = {},
    -- upcomingstep_horizontal_text_font_height = -1,
    -- upcomingstep_horizontal_text_text = '',
	-- upcomingstep_horizontal_text_scale = {1.0, 1.0},
    upcomingstep_horizontal_bg_anim = -1,
    upcomingstep_horizontal_bg_spr = {},
    upcomingstep_horizontal_bg_offset = {0, 0},
    upcomingstep_horizontal_bg_facing = 1,
    upcomingstep_horizontal_bg_scale = {1.0, 1.0},
    upcomingstep_horizontal_bg_displaytime = -1,
	upcomingstep_horizontal_bg_tail_anim = -1,
    upcomingstep_horizontal_bg_tail_spr = {},
    upcomingstep_horizontal_bg_tail_offset = {0, 0},
    upcomingstep_horizontal_bg_tail_facing = 1,
    upcomingstep_horizontal_bg_tail_scale = {1.0, 1.0},
    upcomingstep_horizontal_bg_head_anim = -1,
    upcomingstep_horizontal_bg_head_spr = {},
    upcomingstep_horizontal_bg_head_offset = {0, 0},
    upcomingstep_horizontal_bg_head_facing = 1,
    upcomingstep_horizontal_bg_head_scale = {1.0, 1.0},
	upcomingstep_horizontal_bg_palfx_add = {0, 0, 0},
	upcomingstep_horizontal_bg_palfx_mul = {256, 256, 256},
	upcomingstep_horizontal_bg_palfx_sinadd = {0, 0, 0},
	upcomingstep_horizontal_bg_palfx_invertall = 0,
	upcomingstep_horizontal_bg_palfx_color = 256,
	upcomingstep_horizontal_glyphs_palfx_add = {0, 0, 0},
	upcomingstep_horizontal_glyphs_palfx_mul = {256, 256, 256},
	upcomingstep_horizontal_glyphs_palfx_sinadd = {0, 0, 0},
	upcomingstep_horizontal_glyphs_palfx_invertall = 0,
	upcomingstep_horizontal_glyphs_palfx_color = 256,
	currentstep_vertical_text_offset = {0,0},
    currentstep_vertical_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    currentstep_vertical_text_font_height = -1,
    currentstep_vertical_text_text = '',
	currentstep_vertical_text_scale = {1.0, 1.0},
    currentstep_vertical_bg_anim = -1,
    currentstep_vertical_bg_spr = {},
    currentstep_vertical_bg_offset = {0, 0},
    currentstep_vertical_bg_facing = 1,
    currentstep_vertical_bg_scale = {1.0, 1.0},
    currentstep_vertical_bg_displaytime = -1,
	currentstep_vertical_bg_palfx_add = {0, 0, 0},
	currentstep_vertical_bg_palfx_mul = {256, 256, 256},
	currentstep_vertical_bg_palfx_sinadd = {0, 0, 0},
	currentstep_vertical_bg_palfx_invertall = 0,
	currentstep_vertical_bg_palfx_color = 256,
	currentstep_vertical_glyphs_palfx_add = {0, 0, 0},
	currentstep_vertical_glyphs_palfx_mul = {256, 256, 256},
	currentstep_vertical_glyphs_palfx_sinadd = {0, 0, 0},
	currentstep_vertical_glyphs_palfx_invertall = 0,
	currentstep_vertical_glyphs_palfx_color = 256,
	-- text in horizontal layouts not yet supported
	-- currentstep_horizontal_text_offset = {0,0},
    -- currentstep_horizontal_text_font = {},
    -- currentstep_horizontal_text_font_height = -1,
    -- currentstep_horizontal_text_text = '',
	-- currentstep_horizontal_text_scale = {1.0, 1.0},
    currentstep_horizontal_bg_anim = -1,
    currentstep_horizontal_bg_spr = {},
    currentstep_horizontal_bg_offset = {0, 0},
    currentstep_horizontal_bg_facing = 1,
    currentstep_horizontal_bg_scale = {1.0, 1.0},
    currentstep_horizontal_bg_displaytime = -1,
	currentstep_horizontal_bg_tail_anim = -1,
    currentstep_horizontal_bg_tail_spr = {},
    currentstep_horizontal_bg_tail_offset = {0, 0},
    currentstep_horizontal_bg_tail_facing = 1,
    currentstep_horizontal_bg_tail_scale = {1.0, 1.0},
    currentstep_horizontal_bg_head_anim = -1,
    currentstep_horizontal_bg_head_spr = {},
    currentstep_horizontal_bg_head_offset = {0, 0},
    currentstep_horizontal_bg_head_facing = 1,
    currentstep_horizontal_bg_head_scale = {1.0, 1.0},
	currentstep_horizontal_bg_palfx_add = {0, 0, 0},
	currentstep_horizontal_bg_palfx_mul = {256, 256, 256},
	currentstep_horizontal_bg_palfx_sinadd = {0, 0, 0},
	currentstep_horizontal_bg_palfx_invertall = 0,
	currentstep_horizontal_bg_palfx_color = 256,
	currentstep_horizontal_glyphs_palfx_add = {0, 0, 0},
	currentstep_horizontal_glyphs_palfx_mul = {256, 256, 256},
	currentstep_horizontal_glyphs_palfx_sinadd = {0, 0, 0},
	currentstep_horizontal_glyphs_palfx_invertall = 0,
	currentstep_horizontal_glyphs_palfx_color = 256,
	completedstep_vertical_text_offset = {0,0},
    completedstep_vertical_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    completedstep_vertical_text_font_height = -1,
    completedstep_vertical_text_text = '',
	completedstep_vertical_text_scale = {1.0, 1.0},
    completedstep_vertical_bg_anim = -1,
    completedstep_vertical_bg_spr = {},
    completedstep_vertical_bg_offset = {0, 0},
    completedstep_vertical_bg_facing = 1,
    completedstep_vertical_bg_scale = {1.0, 1.0},
    completedstep_vertical_bg_displaytime = -1,
	completedstep_vertical_bg_palfx_add = {0, 0, 0},
	completedstep_vertical_bg_palfx_mul = {256, 256, 256},
	completedstep_vertical_bg_palfx_sinadd = {0, 0, 0},
	completedstep_vertical_bg_palfx_invertall = 0,
	completedstep_vertical_bg_palfx_color = 256,
	completedstep_vertical_glyphs_palfx_add = {0, 0, 0},
	completedstep_vertical_glyphs_palfx_mul = {256, 256, 256},
	completedstep_vertical_glyphs_palfx_sinadd = {0, 0, 0},
	completedstep_vertical_glyphs_palfx_invertall = 0,
	completedstep_vertical_glyphs_palfx_color = 256,
	-- text in horizontal layouts not yet supported
    -- completedstep_horizontal_text_offset = {0,0},
    -- completedstep_horizontal_text_font = {},
    -- completedstep_horizontal_text_font_height = -1,
    -- completedstep_horizontal_text_text = '',
	-- completedstep_horizontal_text_scale = {1.0, 1.0},
    completedstep_horizontal_bg_anim = -1,
    completedstep_horizontal_bg_spr = {},
    completedstep_horizontal_bg_offset = {0, 0},
    completedstep_horizontal_bg_facing = 1,
    completedstep_horizontal_bg_scale = {1.0, 1.0},
    completedstep_horizontal_bg_displaytime = -1,
	completedstep_horizontal_bg_tail_anim = -1,
    completedstep_horizontal_bg_tail_spr = {},
    completedstep_horizontal_bg_tail_offset = {0, 0},
    completedstep_horizontal_bg_tail_facing = 1,
    completedstep_horizontal_bg_tail_scale = {1.0, 1.0},
    completedstep_horizontal_bg_head_anim = -1,
    completedstep_horizontal_bg_head_spr = {},
    completedstep_horizontal_bg_head_offset = {0, 0},
    completedstep_horizontal_bg_head_facing = 1,
    completedstep_horizontal_bg_head_scale = {1.0, 1.0},
	completedstep_horizontal_bg_palfx_add = {0, 0, 0},
	completedstep_horizontal_bg_palfx_mul = {256, 256, 256},
	completedstep_horizontal_bg_palfx_sinadd = {0, 0, 0},
	completedstep_horizontal_bg_palfx_invertall = 0,
	completedstep_horizontal_bg_palfx_color = 256,
	completedstep_horizontal_glyphs_palfx_add = {0, 0, 0},
	completedstep_horizontal_glyphs_palfx_mul = {256, 256, 256},
	completedstep_horizontal_glyphs_palfx_sinadd = {0, 0, 0},
	completedstep_horizontal_glyphs_palfx_invertall = 0,
	completedstep_horizontal_glyphs_palfx_color = 256,
    glyphs_vertical_offset = {0, 0},
    glyphs_vertical_scale = {1.0,1.0},
    glyphs_vertical_spacing = {0,0},
    glyphs_vertical_align = 1,
	glyphs_vertical_scalewithtext = "false",
    glyphs_horizontal_offset = {0, 0},
    glyphs_horizontal_scale = {1.0,1.0},
    glyphs_horizontal_spacing = {0,0},
    glyphs_horizontal_align = 1,
	trialcounter_pos = {0,0},
    trialcounter_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    trialcounter_scale = {1.0, 1.0},
    trialcounter_font_height = -1,
    trialcounter_text = '',
	trialcounter_allclear_text = '',
	trialcounter_notrialsdata_text = 'No Trials Data Found',
	totaltrialtimer_pos = {0,0},
    totaltrialtimer_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    totaltrialtimer_scale = {1.0, 1.0},
    totaltrialtimer_font_height = -1,
    totaltrialtimer_text = '',
    currenttrialtimer_pos = {0,0},
    currenttrialtimer_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    currenttrialtimer_scale = {1.0, 1.0},
    currenttrialtimer_font_height = -1,
    currenttrialtimer_text = '',
    success_pos = {0, 0},
    success_snd = {-1, 0},
    success_bg_anim = -1,
    success_bg_spr = {},
    success_bg_offset = {0, 0},
    success_bg_facing = 1,
    success_bg_scale = {1.0, 1.0},
    success_bg_displaytime = -1,
    success_front_anim = -1,
    success_front_spr = {},
    success_front_offset = {0, 0},
    success_front_facing = 1,
    success_front_scale = {1.0, 1.0},
    success_front_displaytime = -1,
	success_text_displaytime = -1,
    success_text_offset = {0,0},
    success_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    success_text_font_height = -1,
    success_text_text = '',
	success_text_scale = {1.0, 1.0},
    allclear_pos = {0, 0},
    allclear_snd = {-1, 0},
    allclear_bg_anim = -1,
    allclear_bg_spr = {},
    allclear_bg_offset = {0, 0},
    allclear_bg_facing = 1,
    allclear_bg_scale = {1.0, 1.0},
    allclear_bg_displaytime = -1,
    allclear_front_anim = -1,
    allclear_front_spr = {},
    allclear_front_offset = {0, 0},
    allclear_front_facing = 1,
    allclear_front_scale = {1.0, 1.0},
    allclear_front_displaytime = -1,
	allclear_text_displaytime = -1,
    allclear_text_offset = {0,0},
    allclear_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
    allclear_text_font_height = -1,
    allclear_text_text = '',
	allclear_text_scale = {1.0, 1.0},
	textbox_visible = "false",
	textbox_pos = {0,0},
	textbox_title_offset = {0,0},
	textbox_title_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
	textbox_title_text = '',
	textbox_title_font_height = -1,
	textbox_title_scale = {1.0, 1.0},
	textbox_text_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	textbox_text_offset = {0,0},
	textbox_text_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1},
	textbox_text_text = '',
	textbox_text_font_height = -1,
	textbox_text_scale = {1.0, 1.0},
	textbox_text_drawspeed = 2,
	textbox_bg_anim = -1,
	textbox_bg_spr = {},
	textbox_bg_offset = {0, 0},
	textbox_bg_facing = 1,
	textbox_bg_scale = {1.0, 1.0},
	textbox_bg_displaytime = -1,
	textbox_overlay_visible = "false",
	textbox_overlay_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
	textbox_overlay_col = {0, 0, 0},
	textbox_overlay_alpha = {0, 128},
	textbox_front_anim = -1,
	textbox_front_spr = {},
	textbox_front_offset = {0, 0},
	textbox_front_facing = 1,
	textbox_front_scale = {1.0, 1.0},
	textbox_front_displaytime = -1,
	textbox_portrait_source = "system",
	textbox_portrait_spr = {},
	textbox_portrait_offset = {0, 0},
	textbox_portrait_facing = 1,
	textbox_portrait_scale = {1.0, 1.0},
	textbox_portrait_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]},
}

-- Merge trials data into table
if motif.trials_mode == nil then
	motif.trials_mode = {}
end
motif.trials_mode = main.f_tableMerge(t_base, motif.trials_mode)

-- Initialize Trials Pause Menu data
local t_base_info = {
	fadein_time = 10, --Ikemen feature
	fadein_col = {0, 0, 0}, --Ikemen feature
	fadein_anim = -1, --Ikemen feature
	fadeout_time = 10, --Ikemen feature
	fadeout_col = {0, 0, 0}, --Ikemen feature
	fadeout_anim = -1, --Ikemen feature
	title_offset = {159, 15}, --Ikemen feature
	title_font = {'f-6x9.def', 0, 0, 255, 255, 255, -1}, --Ikemen feature
	title_scale = {1.0, 1.0}, --Ikemen feature
	title_text = 'PAUSE', --Ikemen feature
	menu_uselocalcoord = 0, --Ikemen feature
	menu_pos = {85, 33}, --Ikemen feature
	menu_item_offset = {0, 0}, --Ikemen feature
	menu_item_font = {'f-6x9.def', 0, 1, 191, 191, 191, -1}, --Ikemen feature
	menu_item_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_active_offset = {0, 0}, --Ikemen feature
	menu_item_active_font = {'f-6x9.def', 0, 1, 255, 255, 255, -1}, --Ikemen feature
	menu_item_active_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_selected_offset = {0, 0}, --Ikemen feature
	menu_item_selected_font = {'f-6x9.def', 0, 1, 0, 247, 247, -1}, --Ikemen feature
	menu_item_selected_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_selected_active_offset = {0, 0}, --Ikemen feature
	menu_item_selected_active_font = {'f-6x9.def', 0, 1, 0, 247, 247, -1}, --Ikemen feature
	menu_item_selected_active_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_value_offset = {150, 0}, --Ikemen feature
	menu_item_value_font = {'f-6x9.def', 0, -1, 191, 191, 191, -1}, --Ikemen feature
	menu_item_value_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_value_active_offset = {150, 0}, --Ikemen feature
	menu_item_value_active_font = {'f-6x9.def', 0, -1, 255, 255, 255, -1}, --Ikemen feature
	menu_item_value_active_scale = {1.0, 1.0}, --Ikemen feature
	menu_item_spacing = {0, 14}, --Ikemen feature
	menu_window_margins_y = {0, 0}, --Ikemen feature
	menu_window_visibleitems = 13, --Ikemen feature
	menu_boxcursor_visible = 1, --Ikemen feature
	menu_boxcursor_coords = {-5, -10, 154, 3}, --Ikemen feature
	menu_boxcursor_col = {255, 255, 255}, --Ikemen feature
	menu_boxcursor_alpharange = {10, 40, 2, 255, 255, 0}, --Ikemen feature
	menu_boxbg_visible = 1, --Ikemen feature
	menu_boxbg_col = {0, 0, 0}, --Ikemen feature
	menu_boxbg_alpha = {0, 128}, --Ikemen feature
	menu_arrow_up_anim = -1, --Ikemen feature
	menu_arrow_up_spr = {}, --Ikemen feature
	menu_arrow_up_offset = {0, 0}, --Ikemen feature
	menu_arrow_up_facing = 1, --Ikemen feature
	menu_arrow_up_scale = {1.0, 1.0}, --Ikemen feature
	menu_arrow_down_anim = -1, --Ikemen feature
	menu_arrow_down_spr = {}, --Ikemen feature
	menu_arrow_down_offset = {0, 0}, --Ikemen feature
	menu_arrow_down_facing = 1, --Ikemen feature
	menu_arrow_down_scale = {1.0, 1.0}, --Ikemen feature
	menu_title_uppercase = 1, --Ikemen feature
	overlay_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]}, --Ikemen feature (0, 0, 320, 240)
	overlay_col = {0, 0, 0}, --Ikemen feature
	overlay_alpha = {0, 128}, --Ikemen feature
	cursor_move_snd = {100, 0}, --Ikemen feature
	cursor_done_snd = {100, 1}, --Ikemen feature
	cancel_snd = {100, 2}, --Ikemen feature
	enter_snd = {-1, 0}, --Ikemen feature
	movelist_pos = {10, 20}, --Ikemen feature
	movelist_title_offset = {150, 0}, --Ikemen feature
	movelist_title_font = {'Open_Sans.def', 0, 0, 255, 255, 255, -1}, --Ikemen feature
	movelist_title_scale = {0.4, 0.4}, --Ikemen feature
	movelist_title_text = '%s', --Ikemen feature
	movelist_title_uppercase = 0, --Ikemen feature
	movelist_text_offset = {0, 12}, --Ikemen feature
	movelist_text_font = {'Open_Sans.def', 0, 1, 255, 255, 255, -1}, --Ikemen feature
	movelist_text_scale = {0.4, 0.4}, --Ikemen feature
	movelist_text_spacing = {1, 1}, --Ikemen feature
	movelist_text_text = 'Command List not found.', --Ikemen feature
	movelist_glyphs_offset = {0, 2}, --Ikemen feature
	movelist_glyphs_scale = {1.0, 1.0}, --Ikemen feature
	movelist_glyphs_spacing = {2, 0}, --Ikemen feature
	movelist_window_width = 300, --Ikemen feature
	movelist_window_margins_y = {20, 1}, --Ikemen feature
	movelist_window_visibleitems = 18, --Ikemen feature
	movelist_overlay_window = {0, 0, main.SP_Localcoord[1], main.SP_Localcoord[2]}, --Ikemen feature (0, 0, 320, 240)
	movelist_overlay_col = {0, 0, 0}, --Ikemen feature
	movelist_overlay_alpha = {0, 128}, --Ikemen feature
	movelist_arrow_up_anim = -1, --Ikemen feature
	movelist_arrow_up_spr = {}, --Ikemen feature
	movelist_arrow_up_offset = {0, 0}, --Ikemen feature
	movelist_arrow_up_facing = 1, --Ikemen feature
	movelist_arrow_up_scale = {1.0, 1.0}, --Ikemen feature
	movelist_arrow_down_anim = -1, --Ikemen feature
	movelist_arrow_down_spr = {}, --Ikemen feature
	movelist_arrow_down_offset = {0, 0}, --Ikemen feature
	movelist_arrow_down_facing = 1, --Ikemen feature
	movelist_arrow_down_scale = {1.0, 1.0}, --Ikemen feature
	menu_valuename_trialslist = "", --Ikemen feature
	menu_valuename_trialadvancement_autoadvance = "Auto-Advance",
	menu_valuename_trialadvancement_repeat = "Repeat",
	menu_valuename_trialresetonsuccess_yes = "Yes",
	menu_valuename_trialresetonsuccess_no = "No",
	menu_valuename_trialslayout_vertical = "Vertical",
	menu_valuename_trialslayout_horizontal = "Horizontal",
	menu_valuename_trialstextboxes_show = "Show",
	menu_valuename_trialstextboxes_hide = "Hide",
}
if motif.trials_info == nil then
	motif.trials_info = {}
end
motif.trials_info = main.f_tableMerge(t_base_info, motif.trials_info)

if motif.trialsbgdef == nil then
    motif.trialsbgdef = {
        spr = '',
        bgclearcolor = {0, 0, 0},
    }
end

--trials_info section reuses menu_info values (excluding itemnames)
t = {}
motif.trials_info = main.f_tableMerge(motif.trials_info, motif.menu_info)
t.trials_info = {}
for k, v in pairs(motif.menu_info) do
	if t.trials_info[k] == nil and not k:match('_itemname_') then
		t.trials_info[k] = v
	end
end
motif = main.f_tableMerge(motif, t)

--arrows spr/anim data
motif.f_loadSprData(motif.trials_info, {s = 'menu_arrow_up_',   x = motif.trials_info.menu_pos[1], y = motif.trials_info.menu_pos[2]})
motif.f_loadSprData(motif.trials_info, {s = 'menu_arrow_down_', x = motif.trials_info.menu_pos[1], y = motif.trials_info.menu_pos[2]})
motif.f_loadSprData(motif.trials_info, {s = 'movelist_arrow_up_',   x = motif.trials_info.movelist_pos[1], y = motif.trials_info.movelist_pos[2]})
motif.f_loadSprData(motif.trials_info, {s = 'movelist_arrow_down_', x = motif.trials_info.movelist_pos[1], y = motif.trials_info.movelist_pos[2]})

-- This code creates data out of optional [trialsbgdef] sff file.
-- Defaults to motif.files.spr_data, defined in screenpack, if not declared.
if motif.trialsbgdef.spr ~= nil and motif.trialsbgdef.spr ~= '' then
	motif.trialsbgdef.spr = searchFile(motif.trialsbgdef.spr, {motif.fileDir, '', 'data/'})
	motif.trialsbgdef.spr_data = sffNew(motif.trialsbgdef.spr)
else
	motif.trialsbgdef.spr = motif.files.spr
	motif.trialsbgdef.spr_data = motif.files.spr_data
end

-- Background data generation.
-- Refer to official Elecbyte docs for information how to define backgrounds.
-- http://www.elecbyte.com/mugendocs/bgs.html#description-of-background-elements
motif.trialsbgdef.bg = bgNew(motif.trialsbgdef.spr_data, motif.def, 'trialsbg')

--trials spr/anim data
local tr_pos = motif.trials_mode
for _, v in ipairs({
	{s = 'trialsteps_vertical_bg_',				x = tr_pos.trialsteps_vertical_pos[1] + tr_pos.trialsteps_vertical_bg_offset[1],		y = tr_pos.trialsteps_vertical_pos[2] + tr_pos.trialsteps_vertical_bg_offset[2],		},
	{s = 'trialsteps_horizontal_bg_',			x = tr_pos.trialsteps_horizontal_pos[1] + tr_pos.trialsteps_horizontal_bg_offset[1],	y = tr_pos.trialsteps_horizontal_pos[2] + tr_pos.trialsteps_horizontal_bg_offset[2],	},
	{s = 'success_bg_',    						x = tr_pos.success_pos[1] + tr_pos.success_bg_offset[1],								y = tr_pos.success_pos[2] + tr_pos.success_bg_offset[2],								},
	{s = 'allclear_bg_',	   					x = tr_pos.allclear_pos[1] + tr_pos.allclear_bg_offset[1],								y = tr_pos.allclear_pos[2] + tr_pos.allclear_bg_offset[2],								},
	{s = 'textbox_bg_',	   						x = tr_pos.textbox_pos[1] + tr_pos.textbox_bg_offset[1],								y = tr_pos.textbox_pos[2] + tr_pos.textbox_bg_offset[2],								},
	{s = 'success_front_',  	  				x = tr_pos.success_pos[1] + tr_pos.success_front_offset[1],								y = tr_pos.success_pos[2] + tr_pos.success_front_offset[2],								},
	{s = 'allclear_front_',   					x = tr_pos.allclear_pos[1] + tr_pos.allclear_front_offset[1],							y = tr_pos.allclear_pos[2] + tr_pos.allclear_front_offset[2],							},
	{s = 'textbox_front_',	   					x = tr_pos.textbox_pos[1] + tr_pos.textbox_front_offset[1],								y = tr_pos.textbox_pos[2] + tr_pos.textbox_front_offset[2],								},
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
	{s = 'trialtitle_vertical_bg_',    			x = tr_pos.trialtitle_vertical_pos[1] + tr_pos.trialtitle_vertical_bg_offset[1],		y = tr_pos.trialtitle_vertical_pos[2] + tr_pos.trialtitle_vertical_bg_offset[2],		},
	{s = 'trialtitle_vertical_front_',    		x = tr_pos.trialtitle_vertical_pos[1] + tr_pos.trialtitle_vertical_front_offset[1],		y = tr_pos.trialtitle_vertical_pos[2] + tr_pos.trialtitle_vertical_front_offset[2],		},
    {s = 'trialtitle_horizontal_bg_',    		x = tr_pos.trialtitle_horizontal_pos[1] + tr_pos.trialtitle_horizontal_bg_offset[1],	y = tr_pos.trialtitle_horizontal_pos[2] + tr_pos.trialtitle_horizontal_bg_offset[2],	},
	{s = 'trialtitle_horizontal_front_',    	x = tr_pos.trialtitle_horizontal_pos[1] + tr_pos.trialtitle_horizontal_front_offset[1],	y = tr_pos.trialtitle_horizontal_pos[2] + tr_pos.trialtitle_horizontal_front_offset[2],	},
}) do
	if motif.files.trials ~= nil and motif.files.trials ~= '' then
	 	motif.files.trials_data = sffNew(searchFile(motif.files.trials, {motif.fileDir, '', 'data/'}))
	 	main.f_loadingRefresh()
	 	motif.f_loadSprData(motif.trials_mode, v, motif.files.trials_data)
	elseif main.f_fileExists('external/mods/trials/trials.sff') then
		motif.files.trials_data = sffNew(searchFile('external/mods/trials/trials.sff', {motif.fileDir, '', 'data/'}))
	 	main.f_loadingRefresh()
	 	motif.f_loadSprData(motif.trials_mode, v, motif.files.trials_data)
	else
	 	motif.f_loadSprData(motif.trials_mode, v)
	end
end

if motif.trials_mode.textbox_portrait_source == "system" and motif.trials_mode.textbox_portrait_spr ~= nil then
	motif.f_loadSprData(motif.trials_mode, {s = 'textbox_portrait_', x = motif.trials_mode.textbox_pos[1] + motif.trials_mode.textbox_portrait_offset[1], y = motif.trials_mode.textbox_pos[2] + motif.trials_mode.textbox_portrait_offset[2]})
end

-- fadein/fadeout anim data generation.
if motif.trials_mode.fadein_anim ~= -1 then
	motif.f_loadSprData(motif.trials_mode, {s = 'fadein_'})
end
if motif.trials_mode.fadeout_anim ~= -1 then
	motif.f_loadSprData(motif.trials_mode, {s = 'fadeout_'})
end

function motif.setBaseTrialsInfo()
	motif.trials_info.menu_itemname_back = "Continue"
	motif.trials_info.menu_itemname_nexttrial = "Next Trial"
	motif.trials_info.menu_itemname_previoustrial = "Previous Trial"
	motif.trials_info.menu_itemname_menutrials = "Trials Menu"
	motif.trials_info.menu_itemname_menutrials_trialslist = "Trials List"
	motif.trials_info.menu_itemname_menutrials_trialadvancement = "Trial Advancement"
	motif.trials_info.menu_itemname_menutrials_trialresetonsuccess = "Reset on Success"
	motif.trials_info.menu_itemname_menutrials_trialslayout = "Trials Layout"
	motif.trials_info.menu_itemname_menutrials_trialstextboxes = "Trials Textboxes"
	motif.trials_info.menu_itemname_menutrials_back = "Back"
	motif.trials_info.menu_itemname_empty = ""
	motif.trials_info.menu_itemname_menuinput = "Button Config"
	motif.trials_info.menu_itemname_menuinput_keyboard = "Key Config"
	motif.trials_info.menu_itemname_menuinput_gamepad = "Joystick Config"
	motif.trials_info.menu_itemname_menuinput_empty = ""
	motif.trials_info.menu_itemname_menuinput_inputdefault = "Default"
	motif.trials_info.menu_itemname_menuinput_back = "Back"
	motif.trials_info.menu_itemname_commandlist = "Command List"
	motif.trials_info.menu_itemname_characterchange = "Character Change"
	motif.trials_info.menu_itemname_exit = "Exit"
	if main.t_sort.trials_info == nil then
		main.t_sort.trials_info = {}
	end
	main.t_sort.trials_info.menu = {
		"back",
		"nexttrial",
		"previoustrial",
		"menutrials",
		"menutrials_trialslist",
		"menutrials_trialadvancement",
		"menutrials_trialresetonsuccess",
		"menutrials_trialslayout",
		"menutrials_trialstextboxes",
		"menutrials_back",
		"empty",
		"menuinput",
		"menuinput_keyboard",
		"menuinput_gamepad",
		"menuinput_empty",
		"menuinput_inputdefault",
		"menuinput_back",
		"commandlist",
		"characterchange",
		"exit",
	}
	hook.run("motif.setBaseTrialsInfo")
end

--;===========================================================
--; start.lua
--;===========================================================
start.selectScreenPalMod = 'normal'

function start.f_inittrialsData()
	start.trials = {
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
		start.trials.trialadvancement = true
	else
		start.trials.trialadvancement = false
	end
end

function start.f_trialsBuilder()
	--This function will initialize once to build all the trial tables based on the motif information and the trials information loaded when the char was selected
	--Populate background elements information
	for _, v in ipairs({'vertical','horizontal'}) do
		for _, k in ipairs({'currentstep_','upcomingstep_','completedstep_'}) do
			start.trials.bgelemdata[v][k .. 'bgsize'] = animGetSpriteInfo(motif.trials_mode[k .. v .. '_bg_data'])
			if v == 'horizontal' then
				start.trials.bgelemdata[v][k .. 'bgtailwidth'] = animGetSpriteInfo(motif.trials_mode[k .. v .. '_bg_tail_data'])
				start.trials.bgelemdata[v][k .. 'bgheadwidth'] = animGetSpriteInfo(motif.trials_mode[k .. v .. '_bg_tail_data'])
			end
		end
	end
	
	-- thin out trials data according to showforvarvalpairs
	for i = 1, #start.trials.trial, 1 do
		if start.trials.trial[i].showforvar[1] ~= nil then
			valvarcheck = true
			sumcheck = 0
			-- check every var
			for ii = 1, #start.trials.trial[i].showforvar, 1 do
				player(1)
				-- iterate over vals
				for iii = 1, #start.trials.trial[i].showforval[ii], 1 do
					if var(start.trials.trial[i].showforvar[ii]) == start.trials.trial[i].showforval[ii][iii] then
						sumcheck = sumcheck + 1
					end
				end
			end
			-- for every var, there should have been one hit; if not, set valvarcheck to false
			if sumcheck ~= #start.trials.trial[i].showforvar then
				valvarcheck = false
			end
			-- remove trials that failed valvarcheck
			if not valvarcheck then
				start.trials.trialsRemovalIndex[#start.trials.trialsRemovalIndex+1] = i
			end
		end
	end
	for i = #start.trials.trialsRemovalIndex, 1, -1 do
		table.remove(start.trials.trial,start.trials.trialsRemovalIndex[i])
	end

	--Obtain all of the trials information, to include the offset positions based on whether the display layout is horizontal or vertical
	for i = 1, #start.trials.trial, 1 do
		if #start.trials.trial[i].trialstep > start.trials.maxsteps then
			start.trials.maxsteps = #start.trials.trial[i].trialstep
		end
		for j = 1, #start.trials.trial[i].trialstep, 1 do
			local movelistline = start.trials.trial[i].trialstep[j].glyphs
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
					if motif.trials_mode['glyphs_' .. layout .. '_align'] == -1 then
						for m = #tempglyphs, 1, -1 do
							start.trials.trial[i].trialstep[j].glyphline[layout].glyph[#start.trials.trial[i].trialstep[j].glyphline[layout].glyph+1] = tempglyphs[m]
							start.trials.trial[i].trialstep[j].glyphline[layout].pos[#start.trials.trial[i].trialstep[j].glyphline[layout].glyph+1] = {0,0}
							start.trials.trial[i].trialstep[j].glyphline[layout].width[#start.trials.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].alignOffset[#start.trials.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].lengthOffset[#start.trials.trial[i].trialstep[j].glyphline[layout].glyph+1] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
						end
					else
						for m = 1, #tempglyphs do
							start.trials.trial[i].trialstep[j].glyphline[layout].glyph[m] = tempglyphs[m]
							start.trials.trial[i].trialstep[j].glyphline[layout].pos[m] = {0,0}
							start.trials.trial[i].trialstep[j].glyphline[layout].width[m] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = 0
							start.trials.trial[i].trialstep[j].glyphline[layout].scale[m] = {1,1}
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
				if layout == "vertical" and motif.trials_mode.currentstep_vertical_text_font[7] == nil and motif.trials_mode.glyphs_vertical_scalewithtext == "true" then
					font_def = main.font_def[motif.trials_mode.currentstep_vertical_text_font[1] .. motif.trials_mode.currentstep_vertical_text_font_height]
				elseif layout == "vertical" and motif.trials_mode.glyphs_vertical_scalewithtext == "true" then
					font_def = main.font_def[motif.trials_mode.currentstep_vertical_text_font[1] .. motif.trials_mode.currentstep_vertical_text_font[7]]
				end
				for m in pairs(start.trials.trial[i].trialstep[j].glyphline[layout].glyph) do
					if motif.glyphs_data[start.trials.trial[i].trialstep[j].glyphline[layout].glyph[m]] ~= nil then
						if motif.trials_mode['glyphs_' .. layout .. '_align'] == 0 then --center align
							alignOffset = motif.trials_mode['glyphs_' .. layout .. '_offset'][1] * 0.5
						elseif motif.trials_mode['glyphs_' .. layout .. '_align'] == -1 then --right align
							alignOffset = motif.trials_mode['glyphs_' .. layout .. '_offset'][1]
						end
						if motif.trials_mode['glyphs_' .. layout .. '_align'] ~= align then
							lengthOffset = 0
							align = motif.trials_mode['glyphs_' .. layout .. '_align']
						end
						local scaleX = motif.trials_mode['glyphs_' .. layout .. '_scale'][1]
						local scaleY = motif.trials_mode['glyphs_' .. layout .. '_scale'][2]
						if motif.trials_mode['glyphs_' .. layout .. '_align'] == -1 then
							alignOffset = alignOffset - motif.glyphs_data[start.trials.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[1] * scaleX
						end
						start.trials.trial[i].trialstep[j].glyphline[layout].alignOffset[m] = alignOffset
						if layout == "vertical" and motif.trials_mode.glyphs_vertical_scalewithtext == "true" then
							scaleY = font_def.Size[2] * motif.trials_mode.currentstep_vertical_text_scale[2] / motif.glyphs_data[start.trials.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[2]
							scaleX = scaleY
						end
						start.trials.trial[i].trialstep[j].glyphline[layout].scale[m] = {scaleX, scaleY}
						start.trials.trial[i].trialstep[j].glyphline[layout].width[m] = math.floor(motif.glyphs_data[start.trials.trial[i].trialstep[j].glyphline[layout].glyph[m]].info.Size[1] * scaleX + motif.trials_mode['glyphs_' .. layout .. '_spacing'][1])
						if motif.trials_mode['glyphs_' .. layout .. '_align'] == 1 then
							lengthOffset = lengthOffset + start.trials.trial[i].trialstep[j].glyphline[layout].width[m]
						elseif motif.trials_mode['glyphs_' .. layout .. '_align'] == -1 then
							lengthOffset = lengthOffset - start.trials.trial[i].trialstep[j].glyphline[layout].width[m]
						else
							lengthOffset = lengthOffset + start.trials.trial[i].trialstep[j].glyphline[layout].width[m] / 2
						end
						start.trials.trial[i].trialstep[j].glyphline[layout].lengthOffset[m] = lengthOffset
						start.trials.trial[i].trialstep[j].glyphline[layout].pos[m] = {
							math.floor(motif.trials_mode['trialsteps_' .. layout .. '_pos'][1] + motif.trials_mode['glyphs_' .. layout .. '_offset'][1] + alignOffset + lengthOffset),
							motif.trials_mode['trialsteps_' .. layout .. '_pos'][2] + motif.trials_mode['glyphs_' .. layout .. '_offset'][2]
						}
					end
				end
			end
		end
		if #start.trials.trial[i].trialstep > start.trials.maxsteps then
			start.trials.maxsteps = #start.trials.trial[i].trialstep
		end
	end
	--Pre-populate the draw table
	start.trials.draw = {
		vertical = {},
		horizontal = {},
		success = 0,
		fade = 0,
		fadein = 0,
		fadeout = 0,
		textbox_text = main.f_createTextImg(motif.trials_mode, 'textbox_text'),
		textbox_title = main.f_createTextImg(motif.trials_mode, 'textbox_title'),
		success_text = main.f_createTextImg(motif.trials_mode, 'success_text'),
		allclear = math.max(animGetLength(motif.trials_mode.allclear_front_data), animGetLength(motif.trials_mode.allclear_bg_data), motif.trials_mode.allclear_text_displaytime),
		allclear_text = main.f_createTextImg(motif.trials_mode, 'allclear_text'),
		trialcounter = main.f_createTextImg(motif.trials_mode, 'trialcounter'),
		totaltrialtimer = main.f_createTextImg(motif.trials_mode, 'totaltrialtimer'),
		currenttrialtimer = main.f_createTextImg(motif.trials_mode, 'currenttrialtimer'),
	}
	start.trials.draw.textbox_title:update({x = motif.trials_mode.textbox_pos[1]+motif.trials_mode.textbox_title_offset[1], y = motif.trials_mode.textbox_pos[2]+motif.trials_mode.textbox_title_offset[1],})
	start.trials.draw.textbox_text:update({x = motif.trials_mode.textbox_pos[1]+motif.trials_mode.textbox_text_offset[1]+motif.trials_mode.textbox_text_window[1], y = motif.trials_mode.textbox_pos[2]+motif.trials_mode.textbox_text_offset[2]+motif.trials_mode.textbox_text_window[2],})
	start.trials.draw.success_text:update({x = motif.trials_mode.success_pos[1]+motif.trials_mode.success_text_offset[1], y = motif.trials_mode.success_pos[2]+motif.trials_mode.success_text_offset[2],})
	start.trials.draw.allclear_text:update({x = motif.trials_mode.allclear_pos[1]+motif.trials_mode.allclear_text_offset[1], y = motif.trials_mode.allclear_pos[2]+motif.trials_mode.allclear_text_offset[2],})
	start.trials.draw.trialcounter:update({x = motif.trials_mode.trialcounter_pos[1], y = motif.trials_mode.trialcounter_pos[2],})
	start.trials.draw.totaltrialtimer:update({x = motif.trials_mode.totaltrialtimer_pos[1], y = motif.trials_mode.totaltrialtimer_pos[2],})
	start.trials.draw.currenttrialtimer:update({x = motif.trials_mode.currenttrialtimer_pos[1], y = motif.trials_mode.currenttrialtimer_pos[2],})
	for _, v in ipairs({'vertical','horizontal'}) do
		start.trials.draw[v] = {
			upcomingtextline = {},
			currenttextline = {},
			completedtextline = {},
			trialtitle = math.max(animGetLength(motif.trials_mode['trialtitle_' .. v .. '_front_data']), animGetLength(motif.trials_mode['trialtitle_' .. v .. '_bg_data'])),
			trialtitle_text = main.f_createTextImg(motif.trials_mode, 'trialtitle_' .. v .. '_text'),
			windowXrange = motif.trials_mode['trialsteps_' .. v .. '_window'][3] - motif.trials_mode['trialsteps_' .. v .. '_window'][1],
			windowYrange = motif.trials_mode['trialsteps_' .. v .. '_window'][4] - motif.trials_mode['trialsteps_' .. v .. '_window'][2],
			windowXrangeWtext = motif.trials_mode['trialsteps_' .. v .. '_window_withtextbox'][3] - motif.trials_mode['trialsteps_' .. v .. '_window_withtextbox'][1],
			windowYrangeWtext = motif.trials_mode['trialsteps_' .. v .. '_window_withtextbox'][4] - motif.trials_mode['trialsteps_' .. v .. '_window_withtextbox'][2],
		}
		start.trials.draw[v].trialtitle_text:update({x = motif.trials_mode['trialtitle_' .. v .. '_pos'][1]+motif.trials_mode['trialtitle_' .. v .. '_text_offset'][1], y = motif.trials_mode['trialtitle_' .. v .. '_pos'][2]+motif.trials_mode['trialtitle_' .. v .. '_text_offset'][2],})
		for i = 1, start.trials.maxsteps, 1 do
			start.trials.draw[v].upcomingtextline[i] = main.f_createTextImg(motif.trials_mode, 'upcomingstep_' .. v .. '_text')
			start.trials.draw[v].currenttextline[i] = main.f_createTextImg(motif.trials_mode, 'currentstep_' .. v .. '_text')
			start.trials.draw[v].completedtextline[i] = main.f_createTextImg(motif.trials_mode, 'completedstep_' .. v .. '_text')
		end
	end

	-- Build list out all of the available trials for Pause menu
	menu.t_valuename.trialslist = {}
	for i = 1, #start.trials.trial, 1 do
		table.insert(menu.t_valuename.trialslist, {itemname = tostring(i), displayname = start.trials.trial[i].name})
	end

	start.trials.trialsInitialized = true
end

function start.f_trialsDummySetup()
	--If the trials initializer was successful and the round animation is completed, we will start drawing trials on the screen
	player(2)
	setAILevel(0)
	player(1)
	charMapSet(2, '_iksys_trialsDummyControl', 0)
	if not start.trials.allclear and not start.trials.trial[start.trials.currenttrial].active then
		if start.trials.trial[start.trials.currenttrial].dummymode == 'stand' then
			charMapSet(2, '_iksys_trialsDummyMode', 0)
		elseif start.trials.trial[start.trials.currenttrial].dummymode == 'crouch' then
			charMapSet(2, '_iksys_trialsDummyMode', 1)
		elseif start.trials.trial[start.trials.currenttrial].dummymode == 'jump' then
			charMapSet(2, '_iksys_trialsDummyMode', 2)
		elseif start.trials.trial[start.trials.currenttrial].dummymode == 'wjump' then
			charMapSet(2, '_iksys_trialsDummyMode', 3)
		end
		if start.trials.trial[start.trials.currenttrial].guardmode == 'none' then
			charMapSet(2, '_iksys_trialsGuardMode', 0)
		elseif start.trials.trial[start.trials.currenttrial].guardmode == 'auto' then
			charMapSet(2, '_iksys_trialsGuardMode', 2)
		end
		if start.trials.trial[start.trials.currenttrial].buttonjam == 'none' then
			charMapSet(2, '_iksys_trialsButtonJam', 0)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'a' then
			charMapSet(2, '_iksys_trialsButtonJam', 1)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'b' then
			charMapSet(2, '_iksys_trialsButtonJam', 2)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'c' then
			charMapSet(2, '_iksys_trialsButtonJam', 3)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'x' then
			charMapSet(2, '_iksys_trialsButtonJam', 4)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'y' then
			charMapSet(2, '_iksys_trialsButtonJam', 5)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'z' then
			charMapSet(2, '_iksys_trialsButtonJam', 6)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'start' then
			charMapSet(2, '_iksys_trialsButtonJam', 7)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'd' then
			charMapSet(2, '_iksys_trialsButtonJam', 8)
		elseif start.trials.trial[start.trials.currenttrial].buttonjam == 'w' then
			charMapSet(2, '_iksys_trialsButtonJam', 9)
		end
		start.trials.trial[start.trials.currenttrial].active = true
	end
end

function start.f_trialsDrawer()
	if start.trials.trialsInitialized and roundstate() == 2 and not start.trials.active and start.trials.draw.fade == 0 then
		start.f_trialsDummySetup()
		start.trials.active = true
	end

	-- Check if game is paused - if so, set pause menu loop
	if paused() and not start.trials.trialsPaused then
		start.trials.trialsPaused = true
		menu.currentMenu = {menu.trials.loop, menu.trials.loop}
	elseif not paused() then
		start.trials.trialsPaused = false
	end

	local accwidth = 0
	local addrow = 0
	-- Initialize abbreviated values for readability
	ct = start.trials.currenttrial
	cts = start.trials.currenttrialstep
	ctms = start.trials.currenttrialmicrostep
	layout = motif.trials_mode.trialslayout

	if start.trials.active then
		if ct <= #start.trials.trial and start.trials.draw.success == 0 then

			--According to motif instructions, draw trials counter on screen
			local trtext = motif.trials_mode.trialcounter_text
			trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%t', tostring(#start.trials.trial))
			start.trials.draw.trialcounter:update({text = trtext})
			start.trials.draw.trialcounter:draw()
			--Logic for the stopwatches: total time spent in trial, and time spent on this current trial
			if start.trials.displaytimers.totaltimer then
				local totaltimertext = motif.trials_mode.totaltrialtimer_text
				start.trials.elapsedtime = roundtime() - start.trials.starttick
				local m, s, x = f_timeConvert(start.trials.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				start.trials.draw.totaltrialtimer:update({text = totaltimertext})
				start.trials.draw.totaltrialtimer:draw()
			else
				--start.trials.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--start.trials.draw.totaltrialtimer:draw()
			end
			if start.trials.displaytimers.trialtimer then
				local currenttimertext = motif.trials_mode.currenttrialtimer_text
				start.trials.trial[ct].elapsedtime = roundtime() - start.trials.trial[ct].starttick
				local m, s, x = f_timeConvert(start.trials.trial[ct].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				start.trials.draw.currenttrialtimer:update({text = currenttimertext})
				start.trials.draw.currenttrialtimer:draw()
			else
				--start.trials.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--start.trials.draw.currenttrialtimer:draw()
			end

			-- Draw trialsteps bg overlay if enabled
			-- TODO: use the dynamic scaling in the draw loop to adjust the overlay size (new x2, y2 values)
			if motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'] == 'true' then
				local windowKey = 'trialsteps_' .. layout .. '_bg_overlay_window'
				if motif.trials_mode.textbox_visible == 'true' and start.trials.trial[ct].textbox ~= '' then
					windowKey = 'trialsteps_' .. layout .. '_bg_overlay_window_withtextbox'
				end
				
				local bgoverlay = rect:create({})
				bgoverlay:update({
					x1 = motif.trials_mode[windowKey][1],
					y1 = motif.trials_mode[windowKey][2],
					x2 = motif.trials_mode[windowKey][3],
					y2 = motif.trials_mode[windowKey][4],
					r = motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_col'][1],
					g = motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_col'][2],
					b = motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_col'][3],
					src = motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_alpha'][1],
					dst = motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_alpha'][2],
					defsc = false,
				})
				bgoverlay:draw()
			end

			-- Draw trialstep background
			animUpdate(motif.trials_mode['trialsteps_' .. layout .. '_bg_data'])
			animDraw(motif.trials_mode['trialsteps_' .. layout .. '_bg_data'])
			animUpdate(motif.trials_mode['trialsteps_' .. layout .. '_bg_data'])
			animDraw(motif.trials_mode['trialsteps_' .. layout .. '_bg_data'])

			-- Draw trial title
			animUpdate(motif.trials_mode['trialtitle_' .. layout .. '_bg_data'])
			animDraw(motif.trials_mode['trialtitle_' .. layout .. '_bg_data'])
			start.trials.draw[layout].trialtitle_text:update({text = start.trials.trial[ct].name})
			start.trials.draw[layout].trialtitle_text:draw()
			animUpdate(motif.trials_mode['trialtitle_' .. layout .. '_front_data'])
			animDraw(motif.trials_mode['trialtitle_' .. layout .. '_front_data'])

			local startonstep = 1
			local drawtothisstep = #start.trials.trial[ct].trialstep

			--Determine whether textboxes are being shown and whether the current trial has a textbox to display, and if so, draw them!
			--Also adjust the window range to account for the textbox as specified in the motif
			if motif.trials_mode.textbox_visible == 'true' and start.trials.trial[ct].textbox ~= '' then
				windowYrange = start.trials.draw[layout].windowYrangeWtext
				windowXrange = start.trials.draw[layout].windowXrangeWtext

				if motif.trials_mode.textbox_overlay_visible == 'true' then
					textboxoverlay = rect:create({})
					textboxoverlay:update({
						x1 =    motif.trials_mode.textbox_pos[1]+motif.trials_mode.textbox_overlay_window[1],
						y1 =    motif.trials_mode.textbox_pos[2]+motif.trials_mode.textbox_overlay_window[2],
						x2 =    motif.trials_mode.textbox_pos[1]+motif.trials_mode.textbox_overlay_window[3],
						y2 =    motif.trials_mode.textbox_pos[2]+motif.trials_mode.textbox_overlay_window[4],
						r =     motif.trials_mode.textbox_overlay_col[1],
						g =     motif.trials_mode.textbox_overlay_col[2],
						b =     motif.trials_mode.textbox_overlay_col[3],
						src =   motif.trials_mode.textbox_overlay_alpha[1],
						dst =   motif.trials_mode.textbox_overlay_alpha[2],
						defsc = false,
					})
					textboxoverlay:draw()
				end

				animUpdate(motif.trials_mode.textbox_bg_data)
				animDraw(motif.trials_mode.textbox_bg_data)

				-- Draw text
				local trtext = motif.trials_mode.textbox_title_text
				trtext = trtext:gsub('%%s', tostring(ct)):gsub('%%n', start.trials.trial[ct].name)
				start.trials.draw.textbox_title:update({text = trtext})
				start.trials.draw.textbox_title:draw()

				if not start.trials.draw.draw_textbox_text then
					start.trials.trial[ct].textcnt = start.trials.trial[ct].textcnt + 1
				end
				start.trials.draw.draw_textbox_text = main.f_textRender(
					start.trials.draw.textbox_text,
					start.trials.trial[ct].textbox,
					start.trials.trial[ct].textcnt,
					motif.trials_mode.textbox_text_window[1]+motif.trials_mode.textbox_text_offset[1],
					motif.trials_mode.textbox_text_window[2]+motif.trials_mode.textbox_text_offset[2],
					0,
					0,
					main.font_def[motif.trials_mode.textbox_text_font[1] .. motif.trials_mode.textbox_text_font[7]],
					motif.trials_mode.textbox_text_drawspeed,
					main.f_lineLength(
						motif.trials_mode.textbox_text_offset[1],
						motif.info.localcoord[1],
						motif.trials_mode.textbox_text_font[3],
						motif.trials_mode.textbox_text_window,
						true
					)
				)

				-- Draw portrait depending on desired source
				if motif.trials_mode.textbox_portrait_source == "system" then
					animUpdate(motif.trials_mode.textbox_portrait_data)
					animDraw(motif.trials_mode.textbox_portrait_data)
				elseif motif.trials_mode.textbox_portrait_source == "char" then
					charSpriteDraw(
						-- pn, spr_tbl (1 or more pairs), x, y, scaleX, scaleY, facing, window
						1,
						motif.trials_mode.textbox_portrait_spr,
						motif.trials_mode.textbox_pos[1] + motif.trials_mode.textbox_portrait_offset[1],
						motif.trials_mode.textbox_pos[2] + motif.trials_mode.textbox_portrait_offset[2],
						motif.trials_mode.textbox_portrait_scale[1],
						motif.trials_mode.textbox_portrait_scale[2],
						motif.trials_mode.textbox_portrait_facing,
						motif.trials_mode.textbox_pos[1] + motif.trials_mode.textbox_portrait_offset[1] + motif.trials_mode.textbox_portrait_window[1],
						motif.trials_mode.textbox_pos[2] + motif.trials_mode.textbox_portrait_offset[2] + motif.trials_mode.textbox_portrait_window[2],
						motif.trials_mode.textbox_portrait_window[3],
						motif.trials_mode.textbox_portrait_window[4]
					)
				end

				-- Draw textbox front
				animUpdate(motif.trials_mode.textbox_front_data)
				animDraw(motif.trials_mode.textbox_front_data)
			else
				windowYrange = start.trials.draw[layout].windowYrange
				windowXrange = start.trials.draw[layout].windowXrange
			end

			--For vertical trial layouts, determine if all assets will be drawn within the trials window range, or if scrolling needs to be enabled. For horizontal layouts, we will figure it out
			--when we determine glyph and incrementor widths (see notes below). We do this step outside of the draw loop to speed things up.
			if #start.trials.trial[ct].trialstep*motif.trials_mode['trialsteps_' .. layout .. '_spacing'][2] > windowYrange and layout == "vertical" then
				startonstep = math.max(cts-2, 1)
				if (drawtothisstep - startonstep)*motif.trials_mode['trialsteps_' .. layout .. '_spacing'][2] > windowYrange then
					drawtothisstep = math.min(startonstep+math.floor(windowYrange/motif.trials_mode['trialsteps_' .. layout .. '_spacing'][2]),#start.trials.trial[ct].trialstep)
				end
			end

			--This is the draw loop
			for i = startonstep, drawtothisstep, 1 do
				local tempoffset = {motif.trials_mode['trialsteps_' .. layout .. '_spacing'][1]*(i-startonstep),motif.trials_mode['trialsteps_' .. layout .. '_spacing'][2]*(i-startonstep)}
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

				-- if motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'] == 'true' then
				-- 	bgoverlay = rect:create({})
				-- 	bgoverlay:update({
				-- 		x1 =    motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		y1 =    motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		x2 =    motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		y2 =    motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][4],
				-- 		r =     motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		g =     motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		b =     motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][3],
				-- 		src =   motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][1],
				-- 		dst =   motif.trials_mode['trialsteps_' .. layout .. '_bg_overlay_visible'][2],
				-- 		defsc = false,
				-- 	})
				-- 	bgoverlay:draw()
				-- end

				if layout == "vertical" then
					--Vertical layouts are the simplest - they have a constant width sprite or anim that the text is drawn on top of, and the glyphs are displayed wherever specified.
					--The vertical layouts do NOT support incrementors (see notes below for horizontal layout).
					animSetPos(
						motif.trials_mode[sub .. 'step_vertical_bg_data'],
						motif.trials_mode.trialsteps_vertical_pos[1] + motif.trials_mode[sub .. 'step_vertical_bg_offset'][1] + tempoffset[1],
						motif.trials_mode.trialsteps_vertical_pos[2] + motif.trials_mode[sub .. 'step_vertical_bg_offset'][2] + tempoffset[2]
					)
					start.trials.draw.vertical[sub .. 'textline'][i]:update({
						x = motif.trials_mode.trialsteps_vertical_pos[1]+motif.trials_mode[sub .. 'step_vertical_text_offset'][1]+motif.trials_mode.trialsteps_vertical_spacing[1]*(i-startonstep),
						y = motif.trials_mode.trialsteps_vertical_pos[2]+motif.trials_mode[sub .. 'step_vertical_text_offset'][2]+motif.trials_mode.trialsteps_vertical_spacing[2]*(i-startonstep),
						text = start.trials.trial[ct].trialstep[i].text
					})
					animSetPalFX(motif.trials_mode[sub .. 'step_vertical_bg_data'], {
						time = 1,
						add = motif.trials_mode[sub .. 'step_vertical_bg_palfx_add'],
						mul = motif.trials_mode[sub .. 'step_vertical_bg_palfx_mul'],
						sinadd = motif.trials_mode[sub .. 'step_vertical_bg_palfx_sinadd'],
						invertall = motif.trials_mode[sub .. 'step_vertical_bg_palfx_invertall'],
						color = motif.trials_mode[sub .. 'step_vertical_bg_palfx_color']
					})
					animReset(motif.trials_mode[sub .. 'step_vertical_bg_data'])
					animUpdate(motif.trials_mode[sub .. 'step_vertical_bg_data'])
					animDraw(motif.trials_mode[sub .. 'step_vertical_bg_data'])
					start.trials.draw.vertical[sub .. 'textline'][i]:draw()
				elseif layout == "horizontal" then
					--Horizontal layouts are much more complicated. Text is not drawn in horizontal mode, instead we only display the glyphs. A small sprite is dynamically tiled to the width of the
					--glyphs, and an optional background element called an incrementor (bginc) can be used to link the pieces together (think of an arrow where the body of the arrow is where the
					--glyphs are being drawn and that's the dynamically sized part, and the head of the arrow is the incrementor which is a fixed width sprite). There's quite a bit more work that
					--goes into displaying the horizontal layouts because the code needs to figure out the window size, and determine when it needs to "go to the next line" and create a return so
					--that trials can be displayed dynamically. Back to the arrow analogy, you always want an arrow body to have an arrow head, so the incrementor width is added to the glyphs length
					--and the padding factor specified in the motif data, it's all added together until the window width is met or exceeded, then a line return occurs and the next line is drawn.
					local bgsize = {0,0}
					if start.trials.bgelemdata.horizontal[sub .. 'step_bgtailwidth'] ~= nil then bgtailwidth = math.floor(start.trials.bgelemdata.horizontal[sub .. 'step_bgtailwidth'].Size[1]) end
					if start.trials.bgelemdata.horizontal[sub .. 'step_bgheadwidth'] ~= nil then bgheadwidth = math.floor(start.trials.bgelemdata.horizontal[sub .. 'step_bgheadwidth'].Size[1]) end
					if start.trials.bgelemdata.horizontal[sub .. 'step_bgsize'] ~= nil then bgsize = start.trials.bgelemdata.horizontal[sub .. 'step_bgsize'].Size end

					totalglyphlength = start.trials.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[#start.trials.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset]
					local tailoffset = motif.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][1]
					padding = motif.trials_mode.trialsteps_horizontal_padding
					spacing = motif.trials_mode.trialsteps_horizontal_spacing[1]

					local tempwidth = spacing + bgtailwidth + padding + totalglyphlength + padding + bgheadwidth + accwidth
					if tempwidth - motif.trials_mode.trialsteps_horizontal_spacing[1] > windowXrange then
						accwidth = 0
						addrow = addrow + 1
					end

					tempoffset[2] = motif.trials_mode.trialsteps_horizontal_spacing[2]*(addrow)

					-- Calculate initial positions
					if accwidth == 0 then
						bgcomponentposX = motif.trials_mode.trialsteps_horizontal_pos[1]
					else
						bgcomponentposX = accwidth + spacing -- + bgheadwidth 
					end
					
					-- Draw tail
					animSetPos(motif.trials_mode[sub .. 'step_horizontal_bg_tail_data'], 
						bgcomponentposX + motif.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][1], 
						start.trials.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + motif.trials_mode[sub .. 'step_horizontal_bg_tail_offset'][2] + tempoffset[2]
					)
					animSetPalFX(motif.trials_mode[sub .. 'step_horizontal_bg_tail_data'], {
						time = 1,
						add = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(motif.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
					animUpdate(motif.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
					animDraw(motif.trials_mode[sub .. 'step_horizontal_bg_tail_data'])
					
					-- Draw BG for Glyphs - scale to length, start from tail pos
					bgtargetscale = {(padding + totalglyphlength + padding)/bgsize[1], 1}
					bgcomponentposX = bgcomponentposX + bgtailwidth
					local gpoffset = 0
					for m in pairs(start.trials.trial[ct].trialstep[i].glyphline.horizontal.glyph) do
						if m > 1 then gpoffset = start.trials.trial[ct].trialstep[i].glyphline.horizontal.lengthOffset[m-1] end
						start.trials.trial[ct].trialstep[i].glyphline.horizontal.pos[m][1] = bgcomponentposX + padding + gpoffset -- motif.trials_mode.trialsteps_pos[1] + start.trials.trial[ct].trialstep[i].glyphline.alignOffset[m] +
					end

					animSetScale(motif.trials_mode[sub .. 'step_horizontal_bg_data'], bgtargetscale[1], bgtargetscale[2])
					animSetPos(motif.trials_mode[sub .. 'step_horizontal_bg_data'], 
						bgcomponentposX + motif.trials_mode[sub .. 'step_horizontal_bg_offset'][1], 
						start.trials.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + motif.trials_mode[sub .. 'step_horizontal_bg_offset'][2] + tempoffset[2]
					)
					animSetPalFX(motif.trials_mode[sub .. 'step_horizontal_bg_data'], {
						time = 1,
						add = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(motif.trials_mode[sub .. 'step_horizontal_bg_data'])
					animUpdate(motif.trials_mode[sub .. 'step_horizontal_bg_data'])
					animDraw(motif.trials_mode[sub .. 'step_horizontal_bg_data'])
					
					-- Draw head
					bgcomponentposX = bgcomponentposX + (totalglyphlength + 2*padding)
					animSetPos(motif.trials_mode[sub .. 'step_horizontal_bg_head_data'], 
						bgcomponentposX + motif.trials_mode[sub .. 'step_horizontal_bg_head_offset'][1] + start.trials.trial[ct].trialstep[i].glyphline.horizontal.alignOffset[1], 
						start.trials.trial[ct].trialstep[i].glyphline.horizontal.pos[1][2] + motif.trials_mode[sub .. 'step_horizontal_bg_head_offset'][2] + tempoffset[2]
					)
					animSetPalFX(motif.trials_mode[sub .. 'step_horizontal_bg_head_data'], {
						time = 1,
						add = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_add'],
						mul = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_mul'],
						sinadd = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_sinadd'],
						invertall = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_invertall'],
						color = motif.trials_mode[sub .. 'step_horizontal_bg_palfx_color']
					})
					animReset(motif.trials_mode[sub .. 'step_horizontal_bg_head_data'])
					animUpdate(motif.trials_mode[sub .. 'step_horizontal_bg_head_data'])
					animDraw(motif.trials_mode[sub .. 'step_horizontal_bg_head_data'])
				end
				for m = 1, #start.trials.trial[ct].trialstep[i].glyphline[layout].glyph, 1 do
					animSetScale(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, start.trials.trial[ct].trialstep[i].glyphline[layout].scale[m][1], start.trials.trial[ct].trialstep[i].glyphline[layout].scale[m][2])
					animSetPos(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, 
						start.trials.trial[ct].trialstep[i].glyphline[layout].pos[m][1], 
						start.trials.trial[ct].trialstep[i].glyphline[layout].pos[m][2] + tempoffset[2] + motif.trials_mode['glyphs_' .. layout .. '_offset'][2]
					)
					animSetPalFX(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim, {
						time = 1,
						add = motif.trials_mode[sub .. 'step_' .. layout .. '_glyphs_palfx_add'],
						mul = motif.trials_mode[sub .. 'step_' .. layout .. '_glyphs_palfx_mul'],
						sinadd = motif.trials_mode[sub .. 'step_' .. layout .. '_glyphs_palfx_sinadd'],
						invertall = motif.trials_mode[sub .. 'step_' .. layout .. '_glyphs_palfx_invertall'],
						color = motif.trials_mode[sub .. 'step_' .. layout .. '_glyphs_palfx_color']
					})
					animReset(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
					animUpdate(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
					animDraw(motif.glyphs_data[start.trials.trial[ct].trialstep[i].glyphline[layout].glyph[m]].anim)
				end
				accwidth = bgcomponentposX
			end
		elseif ct > #start.trials.trial then
			-- All trials have been completed, draw the all clear and freeze the timer
			if start.trials.draw.allclear ~= 0 then
				start.f_trialsSuccess('allclear', ct-1)
				main.f_createTextImg(motif.trials_mode, 'allclear_text')
			end

			start.trials.allclear = true
			start.trials.draw.success = 0
			start.trials.draw.trialcounter:update({text = motif.trials_mode.trialcounter_allclear_text})
			start.trials.draw.trialcounter:draw()

			if start.trials.displaytimers.totaltimer then
				local totaltimertext = motif.trials_mode.totaltrialtimer_text
				local m, s, x = f_timeConvert(start.trials.elapsedtime)
				totaltimertext = totaltimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				start.trials.draw.totaltrialtimer:update({text = totaltimertext})
				start.trials.draw.totaltrialtimer:draw()
			else
				--start.trials.draw.totaltrialtimer:update({text = "Timer Disabled"})
				--start.trials.draw.totaltrialtimer:draw()
			end
			if start.trials.displaytimers.trialtimer then
				local currenttimertext = motif.trials_mode.currenttrialtimer_text
				local m, s, x = f_timeConvert(start.trials.trial[ct-1].elapsedtime)
				currenttimertext = currenttimertext:gsub('%%s', m .. ":" .. s .. ":" .. x)
				start.trials.draw.currenttrialtimer:update({text = currenttimertext})
				start.trials.draw.currenttrialtimer:draw()
			else
				--start.trials.draw.currenttrialtimer:update({text = "Timer Disabled"})
				--start.trials.draw.currenttrialtimer:draw()
			end
		end
	end
end

function start.f_trialsChecker()
	--This function sets dummy actions according to the character trials info and validates trials attempts
	--To help follow along, ct = current trial, cts = current trial step, ncts = next current trial step
	if ct <= #start.trials.trial and start.trials.draw.success == 0 and start.trials.draw.fade == 0 and start.trials.active then
		local helpercheck = false
		local projcheck = false
		local maincharcheck = false
		local statecheck = false
		local animcheck = false
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
		local desiredstates = start.trials.trial[ct].trialstep[cts].stateno[ctms]
		for k = 1, #desiredstates, 1 do
			if attackerstate == desiredstates[k] then
				statecheck = true
				break
			end
		end
		if start.trials.trial[ct].trialstep[cts].animno[ctms] ~= nil then
			animcheck = false
			local desiredanims = start.trials.trial[ct].trialstep[cts].animno[ctms]
			for k = 1, #desiredanims, 1 do
				if attackeranim == desiredanims[k] then
					animcheck = true
					break
				end
			end
		end

		if (start.trials.trial[ct].trialstep[cts].ishelper[ctms] and statecheck) and animcheck then
			helpercheck = true
			if start.trials.trial[ct].trialstep[cts].validforvar ~= nil and helpercheck then
				for i = 1, #start.trials.trial[ct].trialstep[cts].validforvar, 1 do
					if helpercheck then
						helpercheck = var(start.trials.trial[ct].trialstep[cts].validforvar[i]) == start.trials.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		if (start.trials.trial[ct].trialstep[cts].isproj[ctms] and statecheck) and animcheck then
			projcheck = true
			if start.trials.trial[ct].trialstep[cts].validforvar ~= nil and projcheck then
				for i = 1, #start.trials.trial[ct].trialstep[cts].validforvar, 1 do
					if projcheck then
						projcheck = var(start.trials.trial[ct].trialstep[cts].validforvar[i]) == start.trials.trial[ct].trialstep[cts].validforval[i]
					end
				end
			end
		end

		maincharcheck = (statecheck and not(start.trials.trial[ct].trialstep[cts].isproj[ctms]) and not(start.trials.trial[ct].trialstep[cts].ishelper[ctms]) and animcheck and ((hitpausetime() > 1 and movehit() and combocount() > start.trials.combocounter) or start.trials.trial[ct].trialstep[cts].isthrow[ctms] or start.trials.trial[ct].trialstep[cts].hitcount[ctms] == 0))
		if start.trials.trial[ct].trialstep[cts].validforvar ~= nil and maincharcheck then
			for i = 1, #start.trials.trial[ct].trialstep[cts].validforvar, 1 do
				if maincharcheck then
					maincharcheck = var(start.trials.trial[ct].trialstep[cts].validforvar[i]) == start.trials.trial[ct].trialstep[cts].validforval[i]
				end
			end
		end		

		if start.trials.validfortickcount > 0 then
			start.trials.validfortickcount = start.trials.validfortickcount - 1
		end
		
		if maincharcheck or projcheck or helpercheck then
			if start.trials.trial[ct].trialstep[cts].hitcount[ctms] >= 1 then
				if start.trials.trial[ct].trialstep[cts].stephitscount[ctms] == 0 then
					start.trials.trial[ct].trialstep[cts].combocountonstep[ctms] = combocount()
				end
				if combocount() - start.trials.trial[ct].trialstep[cts].stephitscount[ctms] == start.trials.trial[ct].trialstep[cts].combocountonstep[ctms] then
					start.trials.trial[ct].trialstep[cts].stephitscount[ctms] = start.trials.trial[ct].trialstep[cts].stephitscount[ctms] + 1
				end
			elseif start.trials.trial[ct].trialstep[cts].hitcount[ctms] == 0 then
				start.trials.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			end

			if start.trials.trial[ct].trialstep[cts].hitcount[ctms] == start.trials.trial[ct].trialstep[cts].stephitscount[ctms] then
				nctms = ctms + 1
				-- First, check that the microstep has passed
				if nctms >= 1 and ((combocount() > 0 and (start.trials.trial[ct].trialstep[cts].iscounterhit[ctms] and movecountered() > 0) or not start.trials.trial[ct].trialstep[cts].iscounterhit[ctms]) or start.trials.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
					if nctms >= 1 and ((start.trials.trial[ct].trialstep[cts].hitcount[ctms] > 1 and combocount() == start.trials.trial[ct].trialstep[cts].stephitscount[ctms] + start.trials.trial[ct].trialstep[cts].combocountonstep[ctms] - 1) or start.trials.trial[ct].trialstep[cts].hitcount[ctms] == 1 or start.trials.trial[ct].trialstep[cts].hitcount[ctms] == 0) then
						start.trials.currenttrialmicrostep = nctms
						if start.trials.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
							start.trials.validfortickcount = start.trials.trial[ct].trialstep[cts].validfortickcount[ctms]
						else
							start.trials.validfortickcount = 0
						end
						start.trials.combocounter = combocount()
					elseif ((combocount() == 0 and start.trials.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and start.trials.validfortickcount == 0) or (start.trials.validfortickcount > 0 and combocount() > start.trials.combocounter) then
						start.trials.currenttrialstep = 1
						start.trials.currenttrialmicrostep = 1
						start.trials.trial[ct].trialstep[cts].stephitscount[ctms] = 0
						start.trials.trial[ct].trialstep[cts].combocountonstep[ctms] = 0
						start.trials.combocounter = 0
						start.trials.validfortickcount = 0
					end
				end
				-- Next, if microstep is exceeded, go to next trial step
				if start.trials.currenttrialmicrostep > start.trials.trial[ct].trialstep[cts].numofmicrosteps then
					start.trials.currenttrialmicrostep = 1
					start.trials.currenttrialstep = cts + 1
					if start.trials.trial[ct].trialstep[cts].hitcount[ctms] ~= 0 and combocount() == 0 and combocount() == start.trials.combocounter then
						start.trials.combocounter = start.trials.combocounter + 1
					else
						start.trials.combocounter = combocount()
					end	
					if start.trials.trial[ct].trialstep[cts].validfortickcount[ctms] ~= nil then
						start.trials.validfortickcount = start.trials.trial[ct].trialstep[cts].validfortickcount[ctms]
					else
						start.trials.validfortickcount = 0
					end
					if start.trials.currenttrialstep > #start.trials.trial[ct].trialstep then
						-- If trial step was last, go to next trial and display success banner
						if start.trials.trialadvancement then
							start.trials.currenttrial = ct + 1
						end
						start.trials.currenttrialstep = 1
						start.trials.combocounter = 0
						if ct < #start.trials.trial or (not start.trials.trialadvancement and ct == #start.trials.trial) then
							if (motif.trials_mode.success_front_displaytime == -1) and (motif.trials_mode.success_bg_displaytime == -1) then
								start.trials.draw.success = math.max(animGetLength(motif.trials_mode.success_front_data), animGetLength(motif.trials_mode.success_bg_data), motif.trials_mode.success_text_displaytime)
							else
								start.trials.draw.success = math.max(motif.trials_mode.success_front_displaytime, motif.trials_mode.success_bg_displaytime, motif.trials_mode.success_text_displaytime)
							end
							if motif.trials_mode.trialsresetonsuccess == "true" then
								start.trials.draw.fadein = motif.trials_mode.fadein_time
								start.trials.draw.fadeout = motif.trials_mode.fadeout_time
								start.trials.draw.fade = start.trials.draw.fadein + start.trials.draw.fadeout
							end
						end
					end
				end
			end
		elseif ((combocount() == 0 and start.trials.trial[ct].trialstep[cts].hitcount[ctms] ~= 0) and start.trials.validfortickcount == 0) or (start.trials.validfortickcount > 0 and combocount() > start.trials.combocounter) then
			start.trials.currenttrialstep = 1
			start.trials.currenttrialmicrostep = 1
			start.trials.combocounter = 0
			start.trials.trial[ct].trialstep[cts].stephitscount[ctms] = 0
			start.trials.trial[ct].trialstep[cts].combocountonstep[ctms] = 0
			start.trials.validfortickcount = 0
		end
	end
	--If the trial was completed successfully, draw the trials success
	if start.trials.draw.success > 0 then
		start.f_trialsSuccess('success', ct)
	elseif start.trials.draw.fade > 0 and motif.trials_mode.trialsresetonsuccess == "true" then
		if start.trials.draw.fade < start.trials.draw.fadein + start.trials.draw.fadeout then
			start.f_trialsFade()
		else
			player(2)
			if stateno() == 0 then
				start.f_trialsFade()
			end
			player(1)
		end
	end
end

function start.f_trialsSuccess(successstring, index)
	-- This function is responsible for drawing the Success or All Clear banners after a trial is completed successfully.
	charMapSet(2, '_iksys_trialsDummyMode', 0)
	charMapSet(2, '_iksys_trialsGuardMode', 0)
	charMapSet(2, '_iksys_trialsButtonJam', 0)
	if not start.trials.trial[index].complete or (successstring == "allclear" and not start.trials.allclear) then
		-- Play sound only once
		sndPlay(motif.files.snd_data, motif.trials_mode[successstring .. '_snd'][1], motif.trials_mode[successstring .. '_snd'][2])
	end
	animUpdate(motif.trials_mode[successstring .. '_bg_data'])
	animDraw(motif.trials_mode[successstring .. '_bg_data'])
	start.trials.draw[successstring .. '_text']:draw()
	animUpdate(motif.trials_mode[successstring .. '_front_data'])
	animDraw(motif.trials_mode[successstring .. '_front_data'])
	start.trials.draw[successstring] = start.trials.draw[successstring] - 1
	start.trials.trial[index].complete = true
	start.trials.trial[index].active = false
	start.trials.active = false
	if not start.trials.trialadvancement then
		start.trials.trial[index].starttick = roundtime()
	end
	if index ~= #start.trials.trial then
		start.trials.trial[index+1].starttick = roundtime()
	end
end

function start.f_trialsFade()
	-- This function is responsible for fadein/fadeout if trialsresetonsuccess is set to true.
	if start.trials.draw.fadeout > 0 then
		if not main.fadeActive then
			main.f_fadeReset('fadeout',motif.trials_mode)
		end
		main.f_fadeAnim(motif.trials_mode)
		start.trials.draw.fadeout = start.trials.draw.fadeout - 1
	elseif start.trials.draw.fadein > 0 then
		if main.fadeType == 'fadeout' then
			charMapSet(2, '_iksys_trialsReposition', 1)
			main.f_fadeReset('fadein',motif.trials_mode)
		elseif main.fadeType == 'fadein' then
			charMapSet(2, '_iksys_trialsCameraReset', 1)
		end
		main.f_fadeAnim(motif.trials_mode)
		start.trials.draw.fadein = start.trials.draw.fadein - 1
	end

	start.trials.draw.fade = start.trials.draw.fade - 1
end

function start.f_trialsSelectScreen()
-- Grays out portaits on the trial select screen for characters without trials files
	local selectScreenPalMod = false

	if gamemode("trials") and start.selectScreenPalMod == 'normal' then
		paladd = motif.trials_mode.selscreenpalfx_add
		palmul = motif.trials_mode.selscreenpalfx_mul
		palsinadd = motif.trials_mode.selscreenpalfx_sinadd
		palinvertall = motif.trials_mode.selscreenpalfx_invertall
		palcolor = motif.trials_mode.selscreenpalfx_color
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
						-- 	add = motif.trials_mode.selscreenpalfx_add,
						-- 	mul = motif.trials_mode.selscreenpalfx_mul,
						-- 	sinadd = motif.trials_mode.selscreenpalfx_sinadd,
						-- 	invertall = motif.trials_mode.selscreenpalfx_invertall,
						-- 	color = motif.trials_mode.selscreenpalfx_color
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
		start.trials = nil
		-- Check if there's a trials file - if so, parse it
		if start.f_getCharData(start.p[1].t_selected[1].ref).trialsdef ~= "" then
			start.f_inittrialsData()
			trialsExist = true
 		else
			trialsExist = false
		end
	end

	if trialsExist and roundstate() == 2 and not start.trials.trialsInitialized then
		-- Initialize the trials based on parsed file and char state at roundstate() == 2
		start.f_trialsBuilder()
		menu.f_trialsReset()
	elseif trialsExist and roundstate() == 2 and start.trials.trialsInitialized then
		-- If trials initialized, draw elements and check for success!
		start.f_trialsDrawer()
		start.f_trialsChecker()
	elseif roundstate() == 2 then
		-- No trials present!
		player(2)
		setAILevel(0)
		player(1)
		charMapSet(2, '_iksys_trialsDummyControl', 0)
		trialcounter = main.f_createTextImg(motif.trials_mode, 'trialcounter')
		trialcounter:update({x = motif.trials_mode.trialcounter_pos[1], y = motif.trials_mode.trialcounter_pos[2], text = motif.trials_mode.trialcounter_notrialsdata_text})
		trialcounter:draw()
	end
end

--;===========================================================
--; menu.lua
--;===========================================================

-- Initialize Trials Pause Menu
table.insert(menu.t_menus, {id = 'trials', section = 'trials_info', bgdef = 'trialsbgdef', txt_title = 'txt_title_trials', movelist = true})
if main.t_sort.trials_info == nil or main.t_sort.trials_info.menu == nil or #main.t_sort.trials_info.menu == 0 then
	motif.setBaseTrialsInfo()
end

menu.t_valuename.trialslist = {
 	{itemname = "0", displayname = "Select Trial"},
}
menu.t_valuename.trialadvancement = {
	{itemname = "Auto-Advance", displayname = motif.trials_info.menu_valuename_trialadvancement_autoadvance},
	{itemname = "Repeat", displayname = motif.trials_info.menu_valuename_trialadvancement_repeat}
}
menu.t_valuename.trialresetonsuccess = {
	{itemname = "Yes", displayname = motif.trials_info.menu_valuename_trialresetonsuccess_yes},
	{itemname = "No", displayname = motif.trials_info.menu_valuename_trialresetonsuccess_no}
}
menu.t_valuename.trialslayout = {
	{itemname = "Vertical", displayname = motif.trials_info.menu_valuename_trialslayout_vertical},
	{itemname = "Horizontal", displayname = motif.trials_info.menu_valuename_trialslayout_horizontal}
}
menu.t_valuename.trialstextboxes = {
	{itemname = "Show", displayname = motif.trials_info.menu_valuename_trialstextboxes_show},
	{itemname = "Hide", displayname = motif.trials_info.menu_valuename_trialstextboxes_hide}
}
menu.t_itemname['trialslist'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		start.trials.currenttrialstep = 1
		start.trials.currenttrialmicrostep = 1
		start.trials.currenttrial = menu.trialslist
		start.trials.trial[start.trials.currenttrial].complete = false
		start.trials.trial[start.trials.currenttrial].active = false
		start.trials.active = false
		start.trials.displaytimers.totaltimer = false
		start.trials.trial[start.trials.currenttrial].starttick = roundtime()
	end
	return true
end
menu.t_vardisplay['trialslist'] = function()
	return menu.t_valuename.trialslist[menu.trialslist or 1].displayname
end

menu.t_itemname['trialadvancement'] = function(t, item, cursorPosY, moveTxt, section)
	if menu.f_valueChanged(t.items[item], motif[section]) then
		if menu.t_valuename.trialadvancement[menu.trialadvancement or 1].itemname == "Auto-Advance" then
			start.trials.trialadvancement = true
		else
			start.trials.trialadvancement = false
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
			motif.trials_mode.trialslayout = "vertical"
		else
			motif.trials_mode.trialslayout = "horizontal"
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
			motif.trials_mode.trialsresetonsuccess = "true"
		else
			motif.trials_mode.trialsresetonsuccess = "false"
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
			motif.trials_mode.textbox_visible = "true"
		else
			motif.trials_mode.textbox_visible = "false"
		end
	end
	return true
end
menu.t_vardisplay['trialstextboxes'] = function()
	return menu.t_valuename.trialstextboxes[menu.trialstextboxes or 1].displayname
end

menu.t_itemname['nexttrial'] = function(t, item, cursorPosY, moveTxt, section)
	if main.f_input(main.t_players, {'pal', 's'}) then
		start.trials.currenttrialstep = 1
		start.trials.currenttrialmicrostep = 1
		sndPlay(motif.files.snd_data, motif[section].cursor_done_snd[1], motif[section].cursor_done_snd[2])
		start.trials.currenttrial = math.min(start.trials.currenttrial + 1, #start.trials.trial)
		start.trials.trial[start.trials.currenttrial].complete = false
		start.trials.trial[start.trials.currenttrial].active = false
		start.trials.active = false
		start.trials.displaytimers.totaltimer = false
		start.trials.trial[start.trials.currenttrial].starttick = roundtime()
	end
	return true
end

menu.t_itemname['previoustrial'] = function(t, item, cursorPosY, moveTxt, section)
	if main.f_input(main.t_players, {'pal', 's'}) then
		start.trials.currenttrialstep = 1
		start.trials.currenttrialmicrostep = 1
		sndPlay(motif.files.snd_data, motif[section].cursor_done_snd[1], motif[section].cursor_done_snd[2])
		start.trials.currenttrial = math.max(start.trials.currenttrial - 1, 1)
		start.trials.trial[start.trials.currenttrial].complete = false
		start.trials.trial[start.trials.currenttrial].active = false
		start.trials.active = false
		start.trials.displaytimers.totaltimer = false
		start.trials.trial[start.trials.currenttrial].starttick = roundtime()
	end
	return true
end

function menu.f_trialsReset()
	for k, _ in pairs(menu.t_valuename) do
		menu[k] = 1
	end
	if motif.trials_mode.trialsresetonsuccess == "true" then
		menu.trialresetonsuccess = 1
	else
		menu.trialresetonsuccess = 2
	end
	if motif.trials_mode.trialslayout == "vertical" then
		menu.trialslayout = 1
	else
		menu.trialslayout = 2
	end
	if motif.trials_mode.textbox_visible == "true" then
		menu.trialstextboxes = 1
	else
		menu.trialstextboxes = 2
	end
	for _, v in ipairs(menu.t_vardisplayPointers) do
		v.vardisplay = menu.f_vardisplay(v.itemname)
	end
	player(2)
	setAILevel(0)
	charMapSet(2, '_iksys_trialsDummyControl', 0)
	charMapSet(2, '_iksys_trialsDummyMode', 0)
	charMapSet(2, '_iksys_trialsGuardMode', 0)
	charMapSet(2, '_iksys_trialsFallRecovery', 0)
	charMapSet(2, '_iksys_trialsDistance', 0)
	charMapSet(2, '_iksys_trialsButtonJam', 0)
	charMapSet(2, '_iksys_trialsReposition', 0)
	player(1)
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
				main.t_selChars[row].trialsdef = main.t_selChars[row].dir .. f_trimafterchar(line, "=")
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
					trial[i] = {
						name = "",
						dummymode = "stand",
						guardmode = "none",
						buttonjam = "none",
						active = false,
						complete = false,
						showforvar = {nil},
						showforval = {nil},
						elapsedtime = 0,
						textbox = "",
						textcnt = 0,
						starttick = roundtime()+1,
						trialstep = {},
					}
					temp = {}
					line = f_trimafterchar(line, ",")
					if line == "" then
						line = "Trial " .. tostring(i)
					end
					trial[i].name = line
				end
			elseif lcline:find("dummymode") then
				trial[i].dummymode = f_trimafterchar(lcline, "=")
			elseif lcline:find("guardmode") then
				trial[i].guardmode = f_trimafterchar(lcline, "=")
			elseif lcline:find("dummybuttonjam") then
				trial[i].buttonjam = f_trimafterchar(lcline, "=")
			elseif lcline:find("showforvarvalpairs") then
				temp = main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", ""))
				trial[i].showforvar = {}
				trial[i].showforval = {}
				for k = 1, #temp, 2 do
					trial[i].showforvar[#trial[i].showforvar+1] = tonumber(temp[k])
					trial[i].showforval[#trial[i].showforval+1] = f_str2number(main.f_strsplit('|', temp[k+1]))
				end
			elseif lcline:find("textbox") then
				trial[i].textbox = f_trimafterchar(lcline, "=")
			elseif lcline:find("trialstep." .. j .. ".text") then
				trial[i].trialstep[j].text = f_trimafterchar(line, "=")
			elseif lcline:find("trialstep." .. j .. ".glyphs") then
				trial[i].trialstep[j].glyphs = f_trimafterchar(line, "=")
			elseif lcline:find("trialstep." .. j .. ".stateno") then
				trial[i].trialstep[j].stateno = main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", ""))
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
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].animno = f_str2number(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
				for k = 1, #trial[i].trialstep[j].animno, 1 do
					local temp = trial[i].trialstep[j].animno[k]
					trial[i].trialstep[j].animno[k] = f_str2number(main.f_strsplit('|', temp))
				end
			elseif lcline:find("trialstep." .. j .. ".hitcount") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].hitcount = f_str2number(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".isthrow") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].isthrow = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".iscounterhit") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].iscounterhit = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".ishelper") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].ishelper = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".isproj") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].isproj = f_str2boolean(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
				end
			elseif lcline:find("trialstep." .. j .. ".validforvarvalpairs") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					local varvalpairs = f_str2number(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
					for ii = 1, #varvalpairs, 2 do
						trial[i].trialstep[j].validforvar[ii] = varvalpairs[ii]
						trial[i].trialstep[j].validforval[ii] = varvalpairs[ii+1]
					end
				end
			elseif lcline:find("trialstep." .. j .. ".validfortickcount") then
				if string.gsub(f_trimafterchar(lcline, "="),"%s+", "") ~= "" then
					trial[i].trialstep[j].validfortickcount = f_str2number(main.f_strsplit(',', string.gsub(f_trimafterchar(lcline, "="),"%s+", "")))
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