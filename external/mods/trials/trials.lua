-- ikemenversion: 1.0
--;===========================================================
--; TRIALS MODE
--;===========================================================
-- Universal trials module for Ikemen GO.
--
-- All module state lives in the local `trials` table below. Globals are touched only
-- at documented extension points: main.t_itemname.trials; the loop#trials, launchFight,
-- main.f_addChar.files, start.f_selectScreen and menu.menu.loop hooks; and the three
-- pause-menu tables the engine documents as appendable by an external module —
-- menu.t_itemname, menu.t_valuename and menu.t_vardisplay (menu.lua:8, :92, :338).
-- Nothing is installed onto `start`, and nothing on `menu` beyond those tables: that
-- coupling is what made the previous version unrecoverable across an engine update.
--
-- One motif table is edited in place rather than only read, and it is the only one: the
-- legacy [Trials Info] fold rewrites motif.pause_menu.trials_pause_menu.menu.itemname
-- so a screenpack that never migrated keeps a working menu. See the PAUSE MENU section.
--
-- Configuration model: docs/adr/0001. Dummy namespace: docs/adr/0002.
-- Vocabulary (Trial / Step / Part / Trial Definition / Trials Config): CONTEXT.md

local trials = {}

trials.dir = 'external/mods/trials/'

-- The Trials Config sections the module owns. Everything else in the screenpack's
-- system.def belongs to the engine and is read through `motif`, not through here.
trials.sections = {'trials_mode', 'trialsbgdef'}

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

-- An authored path resolved to a file that is there, or nil and why not.
--
-- Both readers below need this and neither may raise: a module installed by copying a
-- folder can arrive incomplete, and loadIni and loadText both raise a Lua error on a
-- missing file — which would take the whole game down with a raw stack trace before
-- the menu ever appears.
local function resolveFile(path)
	if path == nil or path == '' then
		return nil, 'no path configured'
	end
	local resolved = normalizePath(path)
	if resolved == '' or not main.f_fileExists(resolved) then
		return nil, 'file not found: ' .. tostring(path)
	end
	return resolved, nil
end

-- Trials Config, and every other ini the module reads through the engine. Degrades
-- with a message naming the file: trials then disables itself and the rest of the game
-- still runs.
local function safeLoadIni(path, normalizeSections, keepMeta)
	local resolved, err = resolveFile(path)
	if resolved == nil then
		return nil, err
	end
	local ok, result = pcall(loadIni, resolved, normalizeSections, keepMeta)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

trials.configPath = trials.dir .. 'config.ini'
trials.enabled = true

-- config.ini as authored: [Common] and [Files] are read back by exact key, so this
-- copy keeps its section names and key case. The Trials Config layer built out of the
-- same file below is a separate, normalized read.
--
-- Deliberately not lowercased the way a character def's [Files] is (#47). This is the
-- module's own file, so no other author's spelling is at stake, and it is the table
-- writePreference hands to saveIni: saveIni rewrites the file from this table, so a
-- normalized copy would rewrite the player's config.ini with its sections and keys
-- lowercased the first time they change a preference.
local iniErr
trials.ini, iniErr = safeLoadIni(trials.configPath, false)
if trials.ini == nil then
	print('Trials: cannot read ' .. trials.configPath .. ' (' .. iniErr .. '). Mode disabled.')
	trials.enabled = false
	trials.ini = {}
end

--;===========================================================
--; LANGUAGE
--;===========================================================
-- Mirrors the engine's SelectedLanguage() (src/iniutils.go:19), which is not exposed
-- to Lua: Config.Language, the OS locale when that reads 'system', then 'en'. Only
-- the first two letters count, so 'pt-BR' resolves as 'pt'.
local function selectedLanguage()
	local ok, lang = pcall(gameOption, 'Config.Language')
	lang = ok and tostring(lang or ''):lower() or ''
	if lang == '' or lang == 'system' then
		lang = tostring(os.getenv('LC_ALL') or os.getenv('LC_MESSAGES') or os.getenv('LANG') or ''):lower()
	end
	lang = lang:match('^(%a%a)') or ''
	if lang == '' or lang == 'c' then
		return 'en'
	end
	return lang
end

trials.language = selectedLanguage()

--;===========================================================
--; TRIALS CONFIG
--;===========================================================
-- Three layers, merged last-wins: the module's own defaults, then its config.ini,
-- then the screenpack's system.def. The screenpack layer is what keeps every existing
-- trials integration working unchanged. See docs/adr/0001 for why none of this can
-- come off the `motif` table.

-- True for a table loadIni produced from a comma-separated value ({10, 690}), as
-- opposed to a nested table it produced from dotted keys. The two need opposite merge
-- rules: a later layer writing `scale = 3` must not inherit the earlier layer's y.
local function isValueList(t)
	if type(t) ~= 'table' then
		return false
	end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= 'number' then
			return false
		end
		n = n + 1
	end
	return n > 0
end

-- go-ini keeps key case as authored, and pre-refactor motif.lua lowercased every
-- param it read, so a screenpack that wrote `TrialCounter.Pos` still resolves.
local function lowerKeys(v)
	if type(v) ~= 'table' then
		return v
	end
	if isValueList(v) then
		return v
	end
	local out = {}
	for k, sub in pairs(v) do
		if k == '__order' then
			local order = {}
			for i, name in ipairs(sub) do
				order[i] = tostring(name):lower()
			end
			out.__order = order
		elseif k == '__value' then
			out.__value = sub
		elseif type(k) == 'string' then
			out[k:lower()] = lowerKeys(sub)
		else
			out[k] = lowerKeys(sub)
		end
	end
	return out
end

-- Deep-merges one layer's section into the accumulator, recording which layer supplied
-- each leaf so the debug dump can answer "which layer won this key" without a rerun.
--
-- Note this is deliberately not main.f_tableMerge. That one writes t1[k][1] = v when a
-- scalar lands on a table, which is the wrong slot for a loadIni keepMeta table (the
-- scalar belongs in __value), and it prints a type-mismatch warning per key when a
-- screenpack legitimately changes a value's shape.
local function mergeLayer(dst, src, layer, source, prefix)
	for k, v in pairs(src) do
		local path = prefix == '' and k or (prefix .. '.' .. k)
		if k == '__order' then
			-- loadIni's key-order metadata. Append names the earlier layers did not
			-- have rather than replacing the list, so authored order survives.
			dst.__order = dst.__order or {}
			local seen = {}
			for _, name in ipairs(dst.__order) do
				seen[name] = true
			end
			for _, name in ipairs(v) do
				if not seen[name] then
					table.insert(dst.__order, name)
					seen[name] = true
				end
			end
		elseif type(v) == 'table' and not isValueList(v) then
			if type(dst[k]) ~= 'table' or isValueList(dst[k]) then
				-- The mirror of the branch below: a later layer setting only a dotted
				-- child (font.height, window.withtextbox) promotes the key to a parent,
				-- and the value an earlier layer put there moves into __value rather
				-- than being dropped. This is what loadIni itself does when the same
				-- file writes both spellings (setNestedLuaKey, src/script.go:470); a
				-- screenpack that overrides one child would otherwise silently delete
				-- the module's whole default for that key.
				dst[k] = dst[k] ~= nil and {__value = dst[k]} or {}
			end
			-- One layer writing both spellings — `window = 25, 34, 295, 138` and
			-- `window.withtextbox =` in the same file — is handed to us as a single
			-- table carrying both: the list on its array part, the child by name.
			-- The list is this layer's value for the key itself, so record it as one.
			-- Without this the key has no provenance at all, and every "did this layer
			-- set it?" test reads false — which is what decides whether a length
			-- written in the module's own space is converted into a screenpack's.
			if v[1] ~= nil then
				source[path] = layer
			end
			mergeLayer(dst[k], v, layer, source, path)
		elseif type(dst[k]) == 'table' and not isValueList(dst[k]) then
			-- An earlier layer promoted this key to a parent (font = 1,0,1 alongside
			-- font.height). Override only the scalar, which is where keepMeta puts it,
			-- and leave the children alone.
			dst[k].__value = v
			source[path] = layer
		else
			dst[k] = v
			source[path] = layer
		end
	end
end

-- Keys the pre-refactor module documented under a name trials no longer uses. The
-- umbrella spec promises exactly one breaking rename ([Trials Info] -> [Trials Pause
-- Menu]) and this is not it: README.md documents trialcounter.notrialsdata.text, so a
-- screenpack that already ships one must keep working.
--
-- Applied per layer rather than once at the end, so provenance stays honest: a
-- screenpack's legacy spelling out-ranks the module's default for the modern key, and
-- the modern key still wins when both come from the same layer.
local aliases = {
	trials_mode = {
		{from = {'trialcounter', 'notrialsdata', 'text'}, to = {'nodata', 'text'}},
		-- The Textbox's typed reveal. README.md documents textbox.text.drawspeed and an
		-- existing screenpack ships one; the modern key says what the number is —
		-- frames per character — where "speed" reads as though larger were faster.
		{from = {'textbox', 'text', 'drawspeed'}, to = {'textbox', 'text', 'delay'}},
	},
}

local function applyAliases(section, src, layerLabel)
	for _, alias in ipairs(aliases[section] or {}) do
		local cur = src
		for _, key in ipairs(alias.from) do
			if type(cur) ~= 'table' then
				cur = nil
				break
			end
			cur = cur[key]
		end
		if type(cur) == 'table' and cur.__value ~= nil then
			cur = cur.__value
		end
		if cur ~= nil and type(cur) ~= 'table' then
			local dst = trials.config[section]
			for i = 1, #alias.to - 1 do
				if type(dst[alias.to[i]]) ~= 'table' then
					dst[alias.to[i]] = {}
				end
				dst = dst[alias.to[i]]
			end
			dst[alias.to[#alias.to]] = cur
			trials.configSource[section .. '.' .. table.concat(alias.to, '.')] =
				layerLabel .. ' (via ' .. table.concat(alias.from, '.') .. ')'
		end
	end
end

-- The module's trials-specific defaults. Deliberately a different file from
-- +system.def: the engine parses that one and warns per unassignable key, so trials
-- sections there would print a warning per key on every boot. See docs/adr/0001.
local defaultsPath = (trials.ini.Files or {}).defaults or (trials.dir .. 'system.def')

local layers = {}
local function addLayer(name, path, required)
	local ini, err = safeLoadIni(path, true, true)
	if ini == nil then
		if required then
			print('Trials: cannot read ' .. tostring(path) .. ' (' .. err .. '). Mode disabled.')
			trials.enabled = false
		end
		return
	end
	table.insert(layers, {name = name, path = normalizePath(path), ini = ini})
end

addLayer('defaults', defaultsPath, true)
-- Layer 2 contributes nothing today and that is by design, not an oversight: config.ini
-- holds Player Preferences under [Options], and the merge below only walks the sections
-- trials owns as presentation. Separating authored config from Player Preference by
-- *kind* is what removes the three-way precedence ambiguity (umbrella spec, #46). The
-- layer stays in the chain because ADR-0001 fixes the order, and because a player who
-- writes a [Trials Mode] section into config.ini should out-rank the module's defaults
-- and still lose to their screenpack.
addLayer('config.ini', trials.configPath, false)
addLayer('screenpack', gameOption('Config.Motif'), false)

-- The screenpack as parsed, kept whole rather than only the sections the merge below
-- walks. The legacy [Trials Info] fold in the pause menu section needs a section this
-- module does not own, and re-reading the file for it would parse the screenpack twice.
local screenpackIni = {}
for _, layer in ipairs(layers) do
	if layer.name == 'screenpack' then
		screenpackIni = layer.ini
	end
end

trials.layers = {}
for i, layer in ipairs(layers) do
	trials.layers[i] = {name = layer.name, path = layer.path}
end

-- Resolved Trials Config, and the layer each leaf came from.
trials.config = {}
trials.configSource = {}

for _, section in ipairs(trials.sections) do
	trials.config[section] = {}
	for _, layer in ipairs(layers) do
		-- Language prefixes are section-name prefixes, and this is the engine's overlay
		-- order verbatim (ResolveLangSectionNames, src/iniutils.go:63): the base section
		-- first, then the language-prefixed one on top of it. Nothing else — the engine
		-- reaches for [EN.Section] only in the single-section form, and only when the
		-- base is absent, so overlaying it here would make [EN.Trials Mode] outrank
		-- [Trials Mode] under any other language.
		local names = {
			{section, layer.name},
			{trials.language .. '.' .. section, layer.name .. ' [' .. trials.language .. ']'},
		}
		for _, entry in ipairs(names) do
			local src = layer.ini[entry[1]]
			if type(src) == 'table' then
				mergeLayer(trials.config[section], lowerKeys(src), entry[2], trials.configSource, section)
				applyAliases(section, lowerKeys(src), entry[2])
			end
		end
	end
end

-- Reads one Trials Config value by its dotted path. Unwraps loadIni's __value, which
-- is where a key that is both a scalar and a parent keeps its scalar (`font = 1,0,1`
-- sitting alongside `font.height = 20`).
local function cfgGet(path)
	local cur = trials.config
	for _, key in ipairs(path) do
		if type(cur) ~= 'table' then
			return nil
		end
		cur = cur[key]
	end
	if type(cur) == 'table' and cur.__value ~= nil then
		return cur.__value
	end
	return cur
end

-- Coerces a config value into a fixed-length number list, filling from `def`.
local function numList(v, def)
	local out = {}
	for i = 1, #def do
		out[i] = def[i]
	end
	if type(v) == 'table' then
		for i = 1, #def do
			out[i] = tonumber(v[i]) or out[i]
		end
	else
		out[1] = tonumber(v) or out[1]
	end
	return out
end

-- loadIni splits an unquoted value on commas, so an author who wrote
-- `nodata.text = No trials, sorry` gets a list back. Rejoin it rather than rendering
-- "table: 0x...".
local function strValue(v, default)
	if v == nil then
		return default
	end
	if type(v) == 'table' then
		local parts = {}
		for _, e in ipairs(v) do
			parts[#parts + 1] = tostring(e)
		end
		return table.concat(parts, ', ')
	end
	return tostring(v)
end

-- Coerces a Trials Config value into a boolean, taking `default` where the key is
-- absent or holds a word this does not recognise.
--
-- Unrecognised takes the default rather than reading as false, so a typo cannot silently
-- turn a feature off — the failure that leaves an author staring at a key they did set.
--
-- Distinct from boolValue below, which reads Trial Definitions: there an absent key is
-- false and the only true word is `true`, which is what that format documents. This one
-- reads the config files, where a flag is spelled `1` as often as `true` and every key
-- has a shipped default that absence has to fall back to.
local function flagValue(v, default)
	if type(v) == 'boolean' then
		return v
	end
	if v == nil then
		return default
	end
	local word = tostring(v):lower()
	if word == 'true' or word == 'yes' or word == 'on' or word == '1' then
		return true
	end
	if word == 'false' or word == 'no' or word == 'off' or word == '0' then
		return false
	end
	return default
end

--;===========================================================
--; ELEMENT CONSTRUCTION
--;===========================================================
-- The engine's element schema is adopted verbatim rather than reinvented: the Lua
-- primitives are a 1:1 cover of the property structs the motif parser fills in, so
-- these mappers follow SetTextSprite / SetAnim / SetRect (src/iniutils.go) key for
-- key. Trials keeps its own extra keys where the engine has no counterpart, and picks
-- up the engine's newer properties for free.
--
-- Everything but the text is applied once, here. The per-frame path only sets text and
-- draws.

-- motif.Fnt is the engine's preloaded font map, keyed by the index a screenpack's
-- [Files] fontN declares. It reaches Lua under the Go field name because it carries no
-- ini tag, unlike every other motif key.
local function resolveFont(raw, font)
	local first = raw
	if type(raw) == 'table' then
		first = raw[1]
	end
	-- A filename in the first slot loads that font directly, matching the engine's
	-- resolveInlineFonts (src/iniutils.go:3050). The height is the 8th slot.
	if type(first) == 'string' and first ~= '' and tonumber(first) == nil then
		return fontNew(first, font[8])
	end
	if font[1] >= 0 and type(motif.Fnt) == 'table' then
		return motif.Fnt[font[1]]
	end
	return nil
end

-- Concatenates an element's config path with the key being read off it.
local function join(path, ...)
	local full = {}
	for _, v in ipairs(path) do
		full[#full + 1] = v
	end
	for _, v in ipairs({...}) do
		full[#full + 1] = v
	end
	return full
end

-- Which layer supplied one of an element's keys, or nil if none did. An element that
-- inherits shared geometry from a parent block falls back to that block, exactly as
-- elementReader does, so a key's value and its provenance always come from one place.
local function sourceOf(path, key, origin)
	local own = trials.configSource[table.concat(path, '.') .. '.' .. key]
	if own ~= nil or origin == nil then
		return own
	end
	return trials.configSource[table.concat(origin, '.') .. '.' .. key]
end

-- The space the coordinates in the module's own system.def are written in. Paired with
-- them: change this and every shipped position moves.
--
-- 320x240 rather than something widescreen because a match does not necessarily render
-- at the screenpack's aspect ratio — Video.FightAspect defaults to the stage's, and a
-- 4:3 stage renders 4:3 even in a 16:9 screenpack. Only the central 4:3 slice of a
-- widescreen localcoord is on screen when that happens. 320x240 has no such margins.
local MODULE_LOCALCOORD = {320, 240}

-- Every trials element draws in the same coordinate space, so that space is one setting
-- — [Trials Mode] trials.localcoord — rather than a copy per element. An element may
-- still carry its own `localcoord` where it genuinely needs a different one; this is
-- what it falls back to.
--
-- Nobody has to write it, at any layer, and leaving it out never changes where an
-- element lands. The space follows whoever positioned the element: the module's own
-- shipped positions resolve in MODULE_LOCALCOORD, and a screenpack's resolve in the
-- screenpack's own, which is what every existing trials integration already assumes.
-- Setting trials.localcoord overrides both.
local function sharedLocalcoord(path, own, ownSource, origin)
	local screen = {motif.info.localcoord[1], motif.info.localcoord[2]}

	-- Whose coordinates are these? A position the module shipped is written in the
	-- module's space; one a screenpack wrote is written in the screenpack's. Nothing
	-- else distinguishes them — an existing integration sets `trialcounter.pos` and no
	-- localcoord at all, and so does this module, so the *absence* of a localcoord
	-- means two different things depending on who left it out.
	local posSource = sourceOf(path, 'pos', origin)
	local ours = posSource == nil or posSource == 'defaults'
	local fallback = ours and MODULE_LOCALCOORD or screen

	-- An explicit localcoord always wins, except where the module set it and a
	-- screenpack has since moved the element out of the module's space.
	if ownSource ~= nil and (ownSource ~= 'defaults' or ours) then
		return numList(own, fallback)
	end
	local sharedSource = trials.configSource['trials_mode.trials.localcoord']
	if sharedSource ~= nil and (sharedSource ~= 'defaults' or ours) then
		return numList(cfgGet({'trials_mode', 'trials', 'localcoord'}), fallback)
	end
	-- Copied: MODULE_LOCALCOORD is a constant every element would otherwise share one
	-- table with, and the dump elides a table it has already printed, so the second
	-- element onwards would report no localcoord at all in the dump.
	return {fallback[1], fallback[2]}
end

-- Shared prelude for every element: the geometry keys the three property structs have
-- in common, resolved once so the mappers below read as the setter chain they are.
local function elementGeometry(g, path, origin)
	local lc = sharedLocalcoord(path, g('localcoord'), sourceOf(path, 'localcoord', origin), origin)
	-- Summed, the way the engine sums them: its own elements carry `offset`, and the
	-- parent block's `pos` is added on top at load (offsetTexts, src/motif.go:2648).
	-- Trials elements have always spelled their origin `pos` and have no parent block,
	-- so both land on the same element here — an existing config that sets only `pos`
	-- and a new one that sets only `offset` both resolve the same way.
	local pos = numList(g('pos'), {0, 0})
	local offset = numList(g('offset'), {0, 0})
	return {
		localcoord = lc,
		pos = {pos[1] + offset[1], pos[2] + offset[2]},
		scale = numList(g('scale'), {1, 1}),
		xshear = numList(g('xshear'), {0})[1],
		angle = numList(g('angle'), {0})[1],
		xangle = numList(g('xangle'), {0})[1],
		yangle = numList(g('yangle'), {0})[1],
		projection = g('projection') or 'orthographic',
		focallength = numList(g('focallength'), {2048})[1],
		window = numList(g('window'), {0, 0, 0, 0}),
		-- Every drawable element takes a layer number, defaulting to 0.
		layerno = numList(g('layerno'), {0})[1],
	}
end

-- Returns a getter reading one element's keys out of the resolved Trials Config.
--
-- `origin` names a parent block the element inherits from. The Step rows are the case
-- it exists for: all three Step Status elements sit on the one trialsteps.<layout>
-- block, which carries the origin and window they share, so a screenpack moves the
-- whole block by setting one pos rather than the same pos three times. The element's
-- own key wins wherever it has one.
local function elementReader(path, origin)
	return function(...)
		local v = cfgGet(join(path, ...))
		if v == nil and origin ~= nil then
			v = cfgGet(join(origin, ...))
		end
		return v
	end
end

-- TextProperties -> TextSprite.
local function buildText(path, origin)
	local g = elementReader(path, origin)
	local font = numList(g('font'), {-1, 0, 0, 255, 255, 255, 255, -1})
	-- Trials has always spelled the font height as its own key; the engine puts it in
	-- the 8th font slot. The dedicated key wins when both are present.
	font[8] = tonumber(g('font', 'height')) or font[8]
	local geo = elementGeometry(g, path, origin)

	local ts = textImgNew()
	local fnt = resolveFont(g('font'), font)
	if fnt ~= nil then
		textImgSetFont(ts, fnt)
	else
		-- A TextSprite with no font draws nothing, and draws it silently — which is a
		-- hard thing to diagnose from the screen, because the element is present,
		-- positioned and holding the right words. Every text element the module ships
		-- names a font, so reaching here means a configuration dropped one.
		print('Trials: ' .. table.concat(path, '.') .. '.font names no font this ' ..
			'screenpack has, so this element draws no text. Give it a font index from ' ..
			'the screenpack\'s [Files], e.g. font = 1, 0, 1.')
	end
	textImgSetBank(ts, font[2])
	textImgSetAlign(ts, font[3])
	textImgSetColor(ts, font[4], font[5], font[6], font[7])
	-- Before SetPos: the engine's SetPos multiplies by the scale SetLocalcoord derives.
	textImgSetLocalcoord(ts, geo.localcoord[1], geo.localcoord[2])
	textImgSetPos(ts, geo.pos[1], geo.pos[2])
	textImgSetScale(ts, geo.scale[1], geo.scale[2])
	textImgSetXShear(ts, geo.xshear)
	textImgSetAngle(ts, geo.angle)
	textImgSetXAngle(ts, geo.xangle)
	textImgSetYAngle(ts, geo.yangle)
	textImgSetProjection(ts, geo.projection)
	textImgSetFocalLength(ts, geo.focallength)
	textImgSetWindow(ts, geo.window[1], geo.window[2], geo.window[3], geo.window[4])
	textImgSetLayerno(ts, geo.layerno)
	textImgSetText(ts, strValue(g('text'), ''))

	geo.font = font
	-- The metrics of the font that was actually resolved, which is what a Glyph drawn
	-- beside this element sizes itself against. Read through fontGetDef rather than off
	-- motif.files.font, which has no entry for an element that named a font file of its
	-- own — the resolved Fnt answers for both cases.
	geo.fontdef = fnt ~= nil and fontGetDef(fnt) or nil
	geo.TextSpriteData = ts
	return geo
end

-- The module's own artwork: external/mods/trials/trials.sff, generated by
-- tools/make-trials-sff.py.
--
-- Loaded lazily, and only once, so a screenpack that styles every element out of its
-- own sff never pays for a second copy of sprites nothing draws. That is the guard the
-- umbrella spec asks for; the cost it avoids is real, since the block backgrounds are
-- the largest sprites the file holds.
--
-- Guarded, because sffNew raises rather than returning nil when the file is missing
-- (src/script.go:2419) and a module that cannot find its own sprites should still draw
-- its Steps. Said once, not per element: the condition is a property of the install.
local moduleArtTried, moduleArtSff = false, nil
local function moduleSff()
	if not moduleArtTried then
		moduleArtTried = true
		local path = trials.dir .. 'trials.sff'
		local ok, sff = pcall(sffNew, path)
		if ok then
			moduleArtSff = sff
		else
			print('Trials: could not load ' .. path .. ' (' .. tostring(sff) .. '). ' ..
				'Elements drawn from the module\'s own artwork will not appear; ' ..
				'Step text and Glyphs are unaffected.')
		end
	end
	return moduleArtSff
end

-- AnimationProperties -> Anim.
--
-- The `anim = N` branch is written the way the engine writes it, and will not fire on a
-- stock build: `AnimationTable`'s only fields are unexported, so the reflection in
-- toLValue hands Lua an empty `motif.AnimTable` and a screenpack's [Begin Action N] is
-- unreachable from a pure-Lua module. `spr = group, index` against an Sff is the route
-- that works, and is what everything the module ships uses. The branch stays so that a
-- build which does expose the table gets the engine's own priority order for free.
--
-- The module ships no actions of its own to resolve `anim` against, deliberately: every
-- element it draws is one static sprite, so an .air beside its .sff would be a file
-- nothing ever read. See buildArt for what a screenpack's `anim` gets instead.
-- `frametime` is how long the single sprite is held, in ticks, and defaults to -1: an
-- element that stays up for as long as it is drawn, which is what every element on the
-- Step display is. Only a fade passes anything else, and it has to — the engine measures
-- a fade's whole duration from its animation's length, and GetLength counts a -1 frame
-- as exactly one tick (src/anim.go:557). A static sprite would therefore make the fade
-- one frame long. See buildFade.
local function buildAnim(path, sff, origin, frametime)
	local g = elementReader(path, origin)
	local geo = elementGeometry(g, path, origin)
	local anim = tonumber(g('anim'))
	local spr = numList(g('spr'), {-1, 0})

	local a = nil
	if anim ~= nil and anim >= 0 and type(motif.AnimTable) == 'table' and motif.AnimTable[anim] ~= nil then
		a = animNew(sff, motif.AnimTable[anim])
	elseif spr[1] >= 0 then
		a = animNew(sff, spr[1] .. ',' .. spr[2] .. ', 0,0, ' .. (frametime or -1))
	end
	if a == nil then
		return nil
	end

	animSetLocalcoord(a, geo.localcoord[1], geo.localcoord[2])
	animSetPos(a, geo.pos[1], geo.pos[2])
	animSetScale(a, geo.scale[1], geo.scale[2])
	animSetFacing(a, numList(g('facing'), {1})[1])
	animSetXShear(a, geo.xshear)
	animSetAngle(a, geo.angle)
	animSetXAngle(a, geo.xangle)
	animSetYAngle(a, geo.yangle)
	animSetProjection(a, geo.projection)
	animSetFocalLength(a, geo.focallength)
	animSetWindow(a, geo.window[1], geo.window[2], geo.window[3], geo.window[4])
	animSetLayerno(a, geo.layerno)

	-- One forced update, the way the engine's own element builder does it
	-- (src/iniutils.go:2093-2096). animNew leaves the Animation with no current sprite:
	-- only UpdateSprite sets one (src/anim.go:684), and that runs from Action, which
	-- runs from Update. Until then animGetSpriteInfo has nothing to report
	-- (src/script.go:1240), so anything measuring this element at load — which is when
	-- a background's width is measured, because that width decides where a row wraps —
	-- would read zero and lay the row out as though the artwork were not there.
	animUpdate(a, true)

	geo.AnimData = a
	return geo
end

-- OverlayProperties -> Rect.
local function buildOverlay(path, origin)
	local g = elementReader(path, origin)
	local geo = elementGeometry(g, path, origin)
	local col = numList(g('col'), {0, 0, 0})
	local alpha = numList(g('alpha'), {0, 255})

	local r = rectNew()
	rectSetColor(r, col[1], col[2], col[3])
	rectSetAlpha(r, alpha[1], alpha[2])
	rectSetLocalcoord(r, geo.localcoord[1], geo.localcoord[2])
	rectSetWindow(r, geo.window[1], geo.window[2], geo.window[3], geo.window[4])
	rectSetLayerno(r, geo.layerno)

	geo.col = col
	geo.alpha = alpha
	geo.RectData = r
	return geo
end

-- Which file an element's artwork comes from, decided the way its coordinate space is
-- decided: by whoever wrote the key naming it. A `spr` or `anim` this module shipped
-- means a sprite in this module's own trials.sff; one a screenpack wrote means a sprite
-- in the screenpack's, because that is the only file its numbers can be about.
--
-- Nothing else could tell them apart. Both layers spell the key identically and neither
-- names a file, so the provenance of the key is the whole of the answer — exactly the
-- question sharedLocalcoord asks about `pos`, and answered the same way.
--
-- `anim` is asked about first because buildAnim prefers it, so an element that carries
-- both resolves its file against the key that will actually be used.
local function artIsOurs(path, origin)
	local src = sourceOf(path, 'anim', origin) or sourceOf(path, 'spr', origin)
	return src == nil or src == 'defaults'
end

-- One drawn element, built against whichever artwork its keys named. nil where the
-- element declares none, which is what an unconfigured background is: a screenpack that
-- says nothing draws nothing, rather than a placeholder it never asked for.
--
-- `foreign` says the block this element belongs to was positioned by a screenpack, and
-- so resolved into the screenpack's coordinate space rather than this module's. The
-- module's own artwork is drawn at 320x240 and is dropped in that case rather than
-- converted: a sprite covers as many units of its element's localcoord as it has pixels,
-- so the shipped 280-unit panel that spans the block at 320x240 would cover under a
-- quarter of the width it was drawn for at 1280x720. This is the same answer the block
-- gives for its own default window, and for the same reason — a default written for one
-- space is worse than no default at all in another, because it fails in a way that reads
-- as a layout bug rather than as a missing style. A screenpack in that position styles
-- its own backgrounds, which is what the feature is for.
local function buildArt(path, origin, foreign, frametime)
	if artIsOurs(path, origin) then
		if foreign then
			return nil
		end
		local sff = moduleSff()
		if sff == nil then
			return nil
		end
		return buildAnim(path, sff, origin, frametime)
	end
	-- A screenpack named an action but no sprite. The engine's action table does not
	-- reach a Lua module, so there is nothing to resolve it against — and buildAnim's
	-- next choice would be `spr`, which here can only be the module's own default. That
	-- would read THIS module's sprite numbers out of the SCREENPACK's sff: artwork
	-- neither of them asked for, in the one failure mode where drawing nothing is
	-- clearly better than drawing something. Said per element, because each one is a key
	-- the author has to change.
	if sourceOf(path, 'spr', origin) == nil or sourceOf(path, 'spr', origin) == 'defaults' then
		print('Trials: ' .. table.concat(path, '.') .. '.anim names an action, and a ' ..
			'screenpack\'s actions cannot be reached from a Lua module. Spell it as ' ..
			'spr = group, index instead. Nothing is drawn for this element.')
		return nil
	end
	return buildAnim(path, motif.Sff, origin, frametime)
end

-- Exposed so the slices that add drawn elements build them the same way this one does,
-- rather than growing a second construction path: #37 and #41 (Step text), #42
-- (Glyphs), #43 (Textbox portraits and backgrounds), #44 (overlays and fades).
trials.f_buildText = buildText
trials.f_buildAnim = buildAnim
trials.f_buildArt = buildArt
trials.f_buildOverlay = buildOverlay

trials.elements = {}

-- Where a Step sits relative to the player's progress. Each is styled independently,
-- from its own configuration block, and is one text element built once at load.
local STEP_STATUSES = {'upcoming', 'current', 'completed'}

-- The two Layouts, each with its own configuration block and its own set of elements.
-- Both are built at load and the Layout Player Preference picks between them, so
-- switching from the pause menu swaps prepared element sets rather than rebuilding.
local STEP_LAYOUTS = {'vertical', 'horizontal'}

-- A palette effect, in the shape animSetPalFX takes.
--
-- Neutral where nothing is configured, so that a screenpack saying nothing gets the
-- Glyphs it drew rather than a tint it never asked for: mul and color at 256 are the
-- engine's identity, and animSetPalFX raises on any key outside this set.
--
-- time is -1 and not a duration. An effect is applied to one Anim once, when that Anim
-- is built, and stands for the life of the module — PalFX.step disables itself the tick
-- its time reaches 0 (src/image.go:279), so a finite time here would tint the Glyph for
-- one frame and then stop.
local function readPalFX(path)
	local g = elementReader(path)
	return {
		time = -1,
		add = numList(g('add'), {0, 0, 0}),
		mul = numList(g('mul'), {256, 256, 256}),
		sinadd = numList(g('sinadd'), {0, 0, 0, 0}),
		invertall = numList(g('invertall'), {0})[1],
		color = numList(g('color'), {256})[1],
	}
end

-- How wide one background piece draws, in the coordinate space its block lays out in.
--
-- animGetSpriteInfo reports a sprite in its own pixels (src/script.go:320), and an Anim
-- at scale 1 covers exactly that many units of its own localcoord — SetScale divides by
-- the localcoord's scale and Draw multiplies it back (src/anim.go:2199) — so the
-- element's own x scale is the only conversion between the two. Every trials element
-- resolves the same localcoord, so this number is directly comparable with a measured
-- text width.
--
-- Zero for an element that declares no artwork, which is what makes a Step Status with
-- no background lay out exactly as it did before there were any.
--
-- Measured once, at load, from the sprite the element's action starts on. This number
-- decides where a row wraps, so it has to be the same on every frame of a run whatever
-- else is happening — a width remeasured per frame would reflow the whole row under a
-- multi-frame animation whose frames differ in size, which is a worse answer than
-- measuring the first frame and holding it.
local function artWidth(e)
	if e == nil or e.AnimData == nil then
		return 0
	end
	local info = animGetSpriteInfo(e.AnimData)
	if type(info) ~= 'table' or type(info.Size) ~= 'table' then
		return 0
	end
	return (tonumber(info.Size[1]) or 0) * e.scale[1]
end

-- The background under one Step, for one Step Status.
--
-- Three pieces in the horizontal Layout and one in the vertical, because the two put a
-- Step in a different kind of place. A vertical row is a fixed-width slot, so its
-- background is one sprite drawn as authored. A horizontal Step is as wide as whatever
-- it renders, so its background is an arrow: a tail that leads in, a body stretched to
-- the width of that Step's own content, and a fixed-width head that terminates it. One
-- narrow body sprite therefore fits every Step, however long.
--
-- The head's width is read from the HEAD. The pre-refactor module read it from the tail
-- (old trials.lua:790), so an asymmetric head has always been mis-measured and every
-- horizontal row has wrapped in slightly the wrong place.
--
-- One palette effect for all three pieces, read off the `bg` block rather than off each:
-- they are one graphic and tinting the body without its head would read as a seam. It is
-- bound to each Anim at build time for the reason a Glyph's is (see glyphAnim): PalFX
-- reaches the draw through animUpdate, which runs at most once per Anim per frame, so an
-- effect set per draw would land on every other draw of that Anim in the same frame.
local function buildStepBg(layout, status, origin, foreign)
	local path = {'trials_mode', status .. 'step', layout, 'bg'}
	local bg = {path = path, palfx = readPalFX(join(path, 'palfx'))}
	bg.body = buildArt(path, origin, foreign)
	if layout == 'horizontal' then
		-- Both read with the block as their origin, not with the body as theirs. Each
		-- piece carries its own offset from the block's own origin, the way the Step
		-- Status text elements do, so moving the block moves all three and none of them
		-- inherits a nudge meant for one of the others.
		bg.tail = buildArt(join(path, 'tail'), origin, foreign)
		bg.head = buildArt(join(path, 'head'), origin, foreign)
	end
	bg.bodyWidth = artWidth(bg.body)
	bg.tailWidth = artWidth(bg.tail)
	bg.headWidth = artWidth(bg.head)
	for name, e in pairs({body = bg.body, tail = bg.tail, head = bg.head}) do
		animSetPalFX(e.AnimData, bg.palfx)
		trials.elements[status .. 'step.' .. layout .. '.bg' ..
			(name == 'body' and '' or ('.' .. name))] = e
	end
	return bg
end

-- The Glyphs accompanying a Step, as configuration: where their run sits relative to
-- the Step, how far apart they are, which way the run grows, and the palette effect
-- each Step Status draws it under.
--
-- `scale` is a multiplier and not a size. A Glyph stands in for a word of the Step it
-- accompanies, so it is sized from that Step's own font — the engine's movelist sizes
-- its own glyphs the same way (menu.lua:891) — and this is what is applied on top.
--
-- `align` is the engine's own three: 1 grows the run right from the anchor, -1 ends it
-- there, 0 centres it. It is the vertical Layout's alone, and was in the pre-refactor
-- module too. Aligning against an anchor only means something where the anchor stands
-- still: vertical rows all start at the block's origin, so a right-aligned run there is
-- a tidy column beside text of varying length. A horizontal Step's run is anchored at
-- the end of that Step's own text, and a run growing left from there would be drawn
-- over the words while the room reserved for it sat empty to their right.
local function buildGlyphs(layout, origin, foreign)
	local path = {'trials_mode', 'glyphs', layout}
	-- Deliberately no origin: these keys are read off the glyphs block and nowhere else.
	-- The Step block carries a `spacing` of its own with an unrelated meaning — the gap
	-- between one row and the next — and inheriting it here would space a run of Glyphs
	-- by the height of a row.
	local g = elementReader(path)
	-- The one thing that does inherit, for the reason every element inherits it: the
	-- coordinate space follows whoever positioned the block these Glyphs are drawn on.
	-- Read with the origin, exactly as the Step text elements read theirs — without it a
	-- screenpack setting trialsteps.<layout>.localcoord would move the words into that
	-- space and leave the Glyphs behind in this module's.
	local own = cfgGet(join(path, 'localcoord'))
	if own == nil then
		own = cfgGet(join(origin, 'localcoord'))
	end
	local lc = sharedLocalcoord(path, own, sourceOf(path, 'localcoord', origin), origin)
	-- Offset and spacing are lengths, so a default written in MODULE_LOCALCOORD is
	-- converted into whatever space the block resolved into rather than used raw —
	-- exactly as the block converts its own row spacing and padding.
	local function length(key, default)
		local out = numList(g(key), default)
		if foreign and sourceOf(path, key) == 'defaults' then
			return {
				out[1] * lc[1] / MODULE_LOCALCOORD[1],
				out[2] * lc[2] / MODULE_LOCALCOORD[2],
			}
		end
		return out
	end
	local gl = {
		path = path,
		localcoord = {lc[1], lc[2]},
		offset = length('offset', {0, 0}),
		-- Only the first argument is read: a run is a row, and there is nothing for a
		-- vertical gap between one Glyph and the next to mean.
		spacing = length('spacing', {0, 0}),
		scale = numList(g('scale'), {1, 1}),
		-- Whether `scale` above is a multiplier on the size the accompanying text gives,
		-- or the size itself. See glyphScale.
		scalewithtext = flagValue(g('scalewithtext'), true),
		align = numList(g('align'), {1})[1],
		layerno = numList(g('layerno'), {0})[1],
		-- One Anim per token per Step Status, built when a Trial that needs it is
		-- selected. Per Step Status and not per token, because a palette effect belongs
		-- to the Anim and not to the draw: see glyphAnim.
		anims = {},
		palfx = {},
	}
	for _, status in ipairs(STEP_STATUSES) do
		gl.palfx[status] = readPalFX({'trials_mode', status .. 'step', layout, 'glyphs', 'palfx'})
		gl.anims[status] = {}
	end
	return gl
end

-- The semi-transparent panel behind the whole Step block.
--
-- A Rect and not a sprite, because what it is for is a flat colour at an alpha: making
-- Step text readable over a busy stage without the screenpack having to draw a plate for
-- it. That is what the engine's own menus use rectNew for, and OverlayProperties is the
-- shape they configure it in, so this reads the same five keys they do.
--
-- Off unless a screenpack asks for it. The module ships artwork behind the Steps
-- already, and an overlay under that would darken a background authored at the alpha it
-- wanted — so the panel exists for a screenpack that styles the Steps with nothing
-- behind them, and `visible` is how it says so.
--
-- A Rect has no position: its window IS its geometry. So the window falls back to the
-- Step block's own, in both variants, and a screenpack that reshapes the block gets a
-- panel covering exactly the Steps without writing the same rect twice.
--
-- Built once, like every other element. The pre-refactor module called rect:create()
-- inside the draw loop, once per frame per Layout (old trials.lua:1116).
local function buildStepOverlay(block, origin)
	local path = join(origin, 'bg', 'overlay')
	if not flagValue(cfgGet(join(path, 'visible')), false) then
		return nil
	end
	local ov = buildOverlay(path, origin)
	local function copy(w)
		return {w[1], w[2], w[3], w[4]}
	end
	-- `visible` on its own has to draw something. OverlayProperties defaults alpha to
	-- 0, 255 — the engine's own default, and one that contributes nothing to the frame —
	-- so a screenpack that uncomments the one key that turns this feature on and leaves
	-- the rest would get a fully built, correctly windowed, entirely invisible panel,
	-- with nothing said about it anywhere. `visible` is this module's own key rather than
	-- the engine's, so it carries its own default: the half-transparent black the def
	-- block documents beside it, which is the value the feature exists to draw.
	if sourceOf(path, 'alpha') == nil then
		ov.alpha = {0, 128}
		rectSetAlpha(ov.RectData, ov.alpha[1], ov.alpha[2])
	end
	-- An all-zero rect means two different things to the two kinds of element, and for a
	-- Rect it means the useless one. On a text sprite it says "do not clip"; on a Rect
	-- the window is the whole geometry, so a zero rect is a panel with no area — and
	-- rectSetWindow refuses it outright, returning without storing it (src/rect.go:331),
	-- exactly as textImgSetWindow does. So an unclipped window has to be spelled as the
	-- full localcoord rect here, or the panel is invisible where the block does not clip,
	-- and switching TO an unclipped variant would leave the other variant's rect in
	-- place. This is the same answer buildStepBlock's own normalize gives, for the same
	-- reason, one element down.
	local function bounded(w)
		if w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0 then
			return {0, 0, ov.localcoord[1], ov.localcoord[2]}
		end
		return copy(w)
	end
	-- The two variants are asked about separately, because they are separately
	-- authorable and a screenpack may well write only the second: "keep the block's own
	-- shape normally, shrink when a Textbox is up" is one line, and reading it as none
	-- would discard the only rect its author wrote.
	--
	-- Asked of the element's own path with no origin, so each answers strictly for a key
	-- THIS element declared. buildOverlay read `window` through the origin, so where the
	-- element declared none it is holding the block's AUTHORED rect — which is not
	-- necessarily the rect the block resolved to. A block a screenpack repositioned
	-- drops the module's 320x240 default rather than clipping a corner of a 1280x720
	-- screen (see buildStepBlock), and the panel has to follow it there.
	local ownWindow = sourceOf(path, 'window') ~= nil
	local ownWithTextbox = sourceOf(path, 'window.withtextbox') ~= nil
	ov.window = bounded(ownWindow and ov.window or block.window)
	if ownWithTextbox then
		ov.windowWithTextbox =
			bounded(numList(cfgGet(join(path, 'window', 'withtextbox')), ov.window))
	elseif ownWindow then
		-- Its own rect and no variant: the panel keeps that one shape either way, which
		-- is what a screenpack that shaped one panel asked for.
		ov.windowWithTextbox = copy(ov.window)
	else
		ov.windowWithTextbox = bounded(block.windowWithTextbox)
	end
	rectSetWindow(ov.RectData, ov.window[1], ov.window[2], ov.window[3], ov.window[4])
	ov.activeWindow = ov.window
	return ov
end

-- Builds the Step block: the three Step Status text elements, plus the geometry they
-- share — the origin rows lay out from, the spacing between them, and the window they
-- clip to, in both its with- and without-Textbox variants.
--
-- The elements inherit that shared geometry through elementReader's origin, so
-- `trialsteps.<layout>.pos` positions all three and each Step Status only spells what
-- distinguishes it: font, colour, scale and its own offset.
local function buildStepBlock(layout)
	local path = {'trials_mode', 'trialsteps', layout}
	local g = elementReader(path)
	local block = {path = path, layout = layout, text = {}}

	for _, status in ipairs(STEP_STATUSES) do
		local e = buildText({'trials_mode', status .. 'step', layout, 'text'}, path)
		block.text[status] = e
		trials.elements[status .. 'step.' .. layout .. '.text'] = e
	end

	-- Whose space the block resolved into. A screenpack that positions the block writes
	-- its pos in its own localcoord, and every length this module ships as a default is
	-- written in MODULE_LOCALCOORD — so where the two differ, a default length means
	-- nothing until it is converted. See sharedLocalcoord for the same question asked
	-- about the coordinate space itself.
	local posSource = sourceOf(path, 'pos')
	local foreign = posSource ~= nil and posSource ~= 'defaults'
	-- One space for the whole block: the elements all resolved it the same way, so any
	-- one of them answers for the rest.
	local lc = block.text.current.localcoord

	-- Row spacing is a length, so a default written in MODULE_LOCALCOORD is converted
	-- into whatever space the block resolved into rather than used raw: 9 units apart
	-- reads as a list at 320x240 and as overlapping text at 1280x720. The window below
	-- is dropped instead of converted, because it is an absolute rect and a converted
	-- guess that misses the block would hide the Steps entirely.
	block.spacing = numList(g('spacing'), {0, 0})
	if foreign and sourceOf(path, 'spacing') == 'defaults' then
		block.spacing = {
			block.spacing[1] * lc[1] / MODULE_LOCALCOORD[1],
			block.spacing[2] * lc[2] / MODULE_LOCALCOORD[2],
		}
	end

	-- The gap between a Step's text and the edges of its own item, applied on both
	-- sides. The horizontal Layout is what reads it — it is what a background drawn
	-- behind a flowing Step needs in order not to touch the words — and it is a length
	-- along x, so a default written in MODULE_LOCALCOORD is converted the way the
	-- spacing above is.
	block.padding = numList(g('padding'), {0})[1]
	if foreign and sourceOf(path, 'padding') == 'defaults' then
		block.padding = block.padding * lc[1] / MODULE_LOCALCOORD[1]
	end

	-- A Textbox displaces the block rather than being drawn over it. `window.withtextbox`
	-- is the documented key for that and every existing screenpack already ships one;
	-- `pos.withtextbox` is the same idea for the origin, and defaults to no shift at all,
	-- so a config that only ever set the window behaves exactly as it did before.
	local pos = numList(g('pos'), {0, 0})
	local posWithTextbox = numList(g('pos', 'withtextbox'), pos)
	block.shift = {posWithTextbox[1] - pos[1], posWithTextbox[2] - pos[2]}
	-- The origin rows lay out from, kept because the window alone does not say where
	-- the list starts: the two are configured independently.
	block.pos = pos
	-- Copied for the reason sharedLocalcoord copies its own: the dump elides a table it
	-- has already printed, and this is the same one the block's elements carry.
	block.localcoord = {lc[1], lc[2]}

	-- textImgSetWindow ignores an all-zero rect (src/font.go:915), so a window can be
	-- set but never cleared. Wherever this needs to say "do not clip" to an element that
	-- already has a window applied, it has to spell it as the full localcoord rect.
	local full = {0, 0, lc[1], lc[2]}
	local function unclipped(w)
		return w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0
	end
	local function copy(w)
		return {w[1], w[2], w[3], w[4]}
	end

	-- A window is written in the same coordinate space as the pos it accompanies, and
	-- this module's own defaults are written in MODULE_LOCALCOORD. A screenpack that
	-- repositions the block without supplying a window of its own would otherwise have
	-- the module's 320x240 rect clip a corner of its 1280x720 screen. Drop the default
	-- instead of clipping in a space it was never written for.
	--
	-- Resolved in order, because the with-Textbox variant falls back to the plain one:
	-- dropping the plain window after deriving the variant from it would leave the
	-- variant holding the very default that was just dropped.
	local window = numList(g('window'), {0, 0, 0, 0})
	if foreign and sourceOf(path, 'window') == 'defaults' then
		window = copy(full)
	end
	local windowWithTextbox = numList(g('window', 'withtextbox'), window)
	if foreign and sourceOf(path, 'window.withtextbox') == 'defaults' then
		windowWithTextbox = copy(window)
	end

	-- Where one variant clips and the other does not, the same rule applies: the
	-- unclipped one has to be the full rect, or switching to it from the clipped one
	-- would leave the clip in place.
	local function normalize(w, other)
		if unclipped(w) and not unclipped(other) then
			return copy(full)
		end
		return w
	end
	block.window = normalize(window, windowWithTextbox)
	block.windowWithTextbox = normalize(windowWithTextbox, window)
	block.activeWindow = block.window

	block.glyphs = buildGlyphs(layout, path, foreign)

	-- The graphical layer, under everything above. The overlay is the bottom of it — a
	-- flat panel the artwork is drawn over. The block's own background sits behind the
	-- whole list; each Step Status carries its own, drawn under the Step it styles. All
	-- three inherit the block's origin and window through the origin argument, so a
	-- screenpack that moves or reshapes the block takes its artwork with it.
	--
	-- After the windows above, which the overlay falls back to.
	block.overlay = buildStepOverlay(block, path)
	if block.overlay ~= nil then
		trials.elements['trialsteps.' .. layout .. '.bg.overlay'] = block.overlay
	end
	block.bg = buildArt(join(path, 'bg'), path, foreign)
	if block.bg ~= nil then
		trials.elements['trialsteps.' .. layout .. '.bg'] = block.bg
	end
	block.stepbg = {}
	for _, status in ipairs(STEP_STATUSES) do
		block.stepbg[status] = buildStepBg(layout, status, path, foreign)
	end
	-- Kept because the dump has to tell a background that was never configured from one
	-- that was dropped for being in the wrong coordinate space: see bgState.
	block.foreign = foreign

	return block
end

-- Clipping is textImgSetWindow's job, so switching variants is switching what it was
-- given. Called when the match moves to a Trial, not per frame.
local function applyStepWindow(block, withTextbox)
	local w = withTextbox and block.windowWithTextbox or block.window
	block.activeWindow = w
	for _, status in ipairs(STEP_STATUSES) do
		local e = block.text[status]
		textImgSetWindow(e.TextSpriteData, w[1], w[2], w[3], w[4])
		-- The element's own record of its window, which is what the debug dump reports.
		-- Left at the build-time value it would describe the window the element was
		-- constructed with rather than the one it is drawing under.
		e.window = {w[1], w[2], w[3], w[4]}
	end
	-- The backgrounds clip to it as well. A Step scrolled out of view has to take its
	-- artwork with it, or a list that scrolls would leave a trail of empty plates where
	-- the rows it clipped used to be.
	local function clip(e)
		if e ~= nil and e.AnimData ~= nil then
			animSetWindow(e.AnimData, w[1], w[2], w[3], w[4])
			e.window = {w[1], w[2], w[3], w[4]}
		end
	end
	-- The panel behind them switches with them. It is a rect and not a text sprite, so
	-- the same rect is reshaped rather than reclipped: its window is its whole geometry,
	-- which is why the with-Textbox variant is a second rect's worth of numbers and not
	-- a clip applied over the first.
	if block.overlay ~= nil then
		local ow = withTextbox and block.overlay.windowWithTextbox or block.overlay.window
		rectSetWindow(block.overlay.RectData, ow[1], ow[2], ow[3], ow[4])
		block.overlay.activeWindow = ow
	end
	clip(block.bg)
	for _, bg in pairs(block.stepbg or {}) do
		clip(bg.body)
		clip(bg.tail)
		clip(bg.head)
	end
	-- Glyphs clip to the same rect the text they accompany does, so they follow it into
	-- the with-Textbox variant rather than hanging outside the reshaped window.
	if block.glyphs ~= nil then
		for _, cache in pairs(block.glyphs.anims) do
			for _, a in pairs(cache) do
				if a ~= false then
					animSetWindow(a, w[1], w[2], w[3], w[4])
				end
			end
		end
		block.glyphs.window = {w[1], w[2], w[3], w[4]}
	end
end

-- Said once per run: see prepareGlyphs.
local glyphsWarned = false

-- The Anim one Glyph draws with, built once per token per Step Status per Layout and
-- cached on the block. `false` marks a token this screenpack has no Glyph for, so the
-- lookup that failed once is not retried every frame.
--
-- Built here rather than reusing motif.glyphs[token].AnimData, which is what the
-- engine's own movelist draws with. That Anim is shared with the movelist and resolves
-- in the screenpack's coordinate space rather than this module's, so drawing through it
-- would both misplace the Glyph and leave this module's settings on it for the next
-- Command List. The sprite comes from the same [Files] glyphs sff either way.
--
-- One per Step Status, rather than one per token drawn under whichever effect the Step
-- needs, because a palette effect cannot be a per-draw setting. animDraw snapshots the
-- Anim but the snapshot shares its PalFX pointer (src/script.go:1127), and the effect
-- only reaches the draw through PalFX.step, which animUpdate runs once per Anim per
-- frame — so a Step Status's effect set just before its draw would land on every other
-- draw of that Glyph in the same frame. Bound to the Anim instead, it cannot.
local function glyphAnim(block, status, token)
	local gl = block.glyphs
	local cache = gl.anims[status]
	local cached = cache[token]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end
	local g = type(motif.glyphs) == 'table' and motif.glyphs[token] or nil
	-- menu.lua:887 guards on exactly this, and the absence of that guard is what #3
	-- reported: a token the screenpack does not define has no sprite to draw and no
	-- size to lay a run out from.
	if g == nil or type(g.Spr) ~= 'table' or type(g.Size) ~= 'table'
		or (tonumber(g.Size[2]) or 0) <= 0 then
		cache[token] = false
		return nil
	end
	local a = animNew(motif.GlyphsSff, g.Spr[1] .. ',' .. g.Spr[2] .. ', 0,0, -1')
	animSetLocalcoord(a, gl.localcoord[1], gl.localcoord[2])
	animSetLayerno(a, gl.layerno)
	animSetWindow(a, block.activeWindow[1], block.activeWindow[2],
		block.activeWindow[3], block.activeWindow[4])
	animSetPalFX(a, gl.palfx[status])
	cache[token] = a
	return a
end

-- Builds the Anims the Steps of one Trial need, in both Layouts.
--
-- Called when the match moves to a Trial, not per frame, and for both Layouts at once
-- so that switching Layout mid-match draws immediately. The per-frame path only ever
-- looks a token up.
local function prepareGlyphs(steps)
	if trials.stepblocks == nil then
		return
	end
	local asked, built = 0, 0
	for _, block in pairs(trials.stepblocks) do
		if block.glyphs ~= nil then
			for _, step in ipairs(steps) do
				for _, token in ipairs(step.glyphs) do
					for _, status in ipairs(STEP_STATUSES) do
						asked = asked + 1
						if glyphAnim(block, status, token) ~= nil then
							built = built + 1
						end
					end
				end
			end
		end
	end
	-- A Trial that asked for Glyphs and got none of them. The likeliest cause is a
	-- screenpack whose [Files] glyphs sff is missing or failed to load: the engine
	-- substitutes an empty one (motif.go:2437) rather than reporting it, so every
	-- token's sprite comes back sizeless and the run simply never draws. Said once,
	-- not per Trial — the condition is a property of the screenpack, not of the Trial
	-- that happened to reveal it.
	if asked > 0 and built == 0 and not glyphsWarned then
		glyphsWarned = true
		print('Trials: this screenpack has no Glyph sprites for any token these Trials ' ..
			'use — check [Files] glyphs. Steps still draw their text.')
	end
end

-- A stopwatch element. Everything the per-frame path needs is resolved here: the
-- format its reading is substituted into, and how many ticks make one second of it.
local function buildTimer(name)
	local path = {'trials_mode', name}
	local e = buildText(path)
	e.text = strValue(cfgGet(join(path, 'text')), '%s')
	-- The engine's own name for the same thing, on its own timer elements. A build
	-- running at something other than 60 ticks a second is what sets it.
	e.framespercount = math.max(1, numList(cfgGet(join(path, 'framespercount')), {60})[1])
	return e
end

-- Breaks `text` into lines no wider than `width`, by inserting newlines.
--
-- Greedy and word-based: words are added to a line until the next one would not fit, and
-- a word wider than the whole width is left to overflow rather than split, because
-- splitting a word is worse than a line that runs long. Newlines the author wrote are
-- kept, and each of the lines they make is wrapped on its own.
--
-- Measured the way every other width in this module is measured — textImgGetTextWidth in
-- the font's own pixels, times the element's x scale — so the result is comparable with
-- a width in that element's localcoord. That is the same pairing drawStepsHorizontal
-- uses to decide where a row wraps.
local function wrapProse(e, text, width)
	if width <= 0 or text == '' then
		return text
	end
	local ts = e.TextSpriteData
	local out, n = {}, 0
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		local built = nil
		for word in line:gmatch('%S+') do
			if built == nil then
				built = word
			elseif textImgGetTextWidth(ts, built .. ' ' .. word) * e.scale[1] > width then
				n = n + 1
				out[n] = built
				built = word
			else
				built = built .. ' ' .. word
			end
		end
		n = n + 1
		out[n] = built or ''
	end
	return table.concat(out, '\n')
end

-- Puts one Trial's prose on the Textbox and starts its reveal over.
--
-- textImgReset is what zeroes the tick count the typed reveal is measured against
-- (src/font.go:1456), and it also empties the text of a Lua-made sprite (see
-- buildBanner) — so the words go back on after it, wrapped, and never before.
local function setProse(box, text)
	if box == nil then
		return
	end
	textImgReset(box.text.TextSpriteData)
	textImgSetText(box.text.TextSpriteData,
		box.wrap and wrapProse(box.text, text, box.wrapWidth) or text)
end

-- The Textbox: the explanatory prose a Trial can carry, with an optional portrait.
--
-- Five elements on one origin. `textbox.pos` positions all of them and each spells only
-- its own offset, the way the Step block's three Step Statuses share theirs:
--
--   .bg        artwork behind the whole box
--   .portrait  the character being played, or a sprite from the screenpack
--   .title     one line, usually the Trial's number and name
--   .text      the Trial's own prose, wrapped and optionally typed out
--   .front     artwork over everything, for a frame or a gloss
--
-- Drawn in that order, so `front` is over the words and `bg` behind them. Elements
-- sharing a layer number draw in the order they are drawn in.
--
-- The portrait is not built here when it comes from the character: which character that
-- is only becomes known when a match resolves, so that one is built on demand and cached
-- per character. See charPortrait.
local function buildTextbox()
	local path = {'trials_mode', 'textbox'}
	local g = elementReader(path)
	local box = {path = path}

	box.title = buildText(join(path, 'title'), path)
	box.title.text = strValue(g('title', 'text'), '')
	trials.elements['textbox.title'] = box.title

	box.text = buildText(join(path, 'text'), path)
	trials.elements['textbox.text'] = box.text

	-- Line spacing and the typed-out reveal are the engine's own; WRAPPING IS NOT, and
	-- the difference is not obvious from the binding list.
	--
	-- There is a textImgSetTextWrap, and it sets a flag — but that flag is read in one
	-- place only, TextSprite.wrapText (src/font.go:1142), and wrapText is called from the
	-- engine's own Go text paths (dialogue, win quotes, storyboards) and from nothing
	-- else. It is not called from Draw, and no textImg binding reaches it. A Lua draw
	-- splits the string on newlines and does nothing further (src/font.go:1412). So the
	-- newlines have to be in the string before it is set, which is what wrapProse does —
	-- the same job main.f_textRender and main.f_lineLength did for the pre-refactor
	-- module before both were removed from the engine's main.lua.
	--
	-- The delay and the spacing below really are the engine's: draw honours textDelay
	-- itself (src/font.go:1396) and advances each line by the font's height plus
	-- textSpacing.y (src/font.go:1424).
	box.wrap = flagValue(g('text', 'wrap'), true)
	local spacing = numList(g('text', 'spacing'), {0, 0})
	textImgSetTextSpacing(box.text.TextSpriteData, spacing[1], spacing[2])
	box.spacing = spacing
	-- Frames per character. 0 is the whole of the prose at once, which is what the
	-- engine reads a non-positive delay as (src/font.go:1396) and what a screenpack that
	-- says nothing gets. The pre-refactor key was `drawspeed` and meant the same thing.
	box.delay = numList(g('text', 'delay'), {0})[1]
	textImgSetTextDelay(box.text.TextSpriteData, box.delay)

	-- How wide the prose may run before it turns, in the element's own coordinate space.
	-- Resolved once: the window, the origin and the scale are all fixed at load, and
	-- nothing in the draw path moves the body.
	--
	-- The three cases are the engine's own (getLineLength, src/font.go:1017), because
	-- where an aligned line ends depends on which end is anchored. An all-zero window is
	-- the engine's spelling of "do not clip", and prose with nothing to turn inside runs
	-- to the edge of its coordinate space.
	local win = box.text.window
	local unclipped = win[1] == 0 and win[2] == 0 and win[3] == 0 and win[4] == 0
	local left = unclipped and 0 or win[1]
	local right = unclipped and box.text.localcoord[1] or win[3]
	local align = box.text.font[3]
	if align == 1 then
		box.wrapWidth = right - box.text.pos[1]
	elseif align == 0 then
		box.wrapWidth = 2 * math.min(box.text.pos[1] - left, right - box.text.pos[1])
	else
		box.wrapWidth = box.text.pos[1] - left
	end

	box.bg = buildArt(join(path, 'bg'), path)
	box.front = buildArt(join(path, 'front'), path)
	if box.bg ~= nil then
		trials.elements['textbox.bg'] = box.bg
	end
	if box.front ~= nil then
		trials.elements['textbox.front'] = box.front
	end

	-- Where the portrait comes from. `char` is the character being played, drawn from
	-- the sprites the select screen already preloaded; anything else is a sprite out of
	-- an sff, through the same mapper every other element uses.
	box.portraitSource = strValue(g('portrait', 'source'), 'system'):lower()
	box.portraitPath = join(path, 'portrait')
	if box.portraitSource ~= 'char' then
		box.portrait = buildArt(box.portraitPath, path)
		if box.portrait ~= nil then
			trials.elements['textbox.portrait'] = box.portrait
		end
	else
		-- Read now so the per-match build has them without re-reading config: the
		-- geometry a character portrait draws under is the same element geometry
		-- everything else resolves, and only the sprite is late.
		local pg = elementReader(box.portraitPath, path)
		box.portraitGeo = elementGeometry(pg, box.portraitPath, path)
		box.portraitSpr = numList(pg('spr'), {9000, 0})
		box.portraitFacing = numList(pg('facing'), {1})[1]
		-- One Anim per character, built the first time that character's Textbox is
		-- drawn. Keyed by char_ref because that is what animGetPreloadedCharData takes.
		box.portraits = {}
	end

	return box
end

-- Success and All-Clear share one shape: a banner positioned by the parent key, with
-- its words styled under `.text`, so `success.pos` moves both the text and everything
-- a later slice draws behind it.
--
-- Text only here. The `.bg` and `.front` animation layers, and the fades that go with
-- them, are the rest of the presentation layer — the module ships no sff for buildAnim
-- to read them out of yet, so configuring them now resolves to nothing rather than to
-- a half-drawn banner.
local function buildBanner(name)
	local path = {'trials_mode', name}
	local e = buildText({'trials_mode', name, 'text'}, path)
	-- buildText puts the words on the sprite, but textImgReset restores the sprite's
	-- engine-side initial text, and that is written in exactly one place: the Go motif
	-- parser. A sprite Lua made has none, so a reset empties it. Keeping the string here
	-- lets drawBanner set it back every frame, the way drawSteps and drawTimer do.
	e.text = strValue(cfgGet(join(path, 'text', 'text')), '')
	-- Trials keeps its own key here, the way buildAnim does: the engine has no
	-- per-element display time for text.
	--
	-- The pre-refactor config spelled -1 as "stay up as long as the banner's animation
	-- runs", and there is no animation to measure yet, so a non-positive value falls
	-- back to the default rather than to a banner that flashes for one frame.
	e.displaytime = numList(cfgGet({'trials_mode', name, 'text', 'displaytime'}), {70})[1]
	if e.displaytime <= 0 then
		e.displaytime = 70
	end
	-- A negative group plays nothing, matching how the engine reads an absent snd.
	e.snd = numList(cfgGet({'trials_mode', name, 'snd'}), {-1, 0})
	return e
end

-- The keys the engine's own inputTime answers for. A combination is spelled in these
-- and nothing else, so a typo is caught at load rather than silently never firing.
local INPUT_KEYS = {
	B = true, D = true, F = true, U = true, L = true, R = true,
	a = true, b = true, c = true, x = true, y = true, z = true, s = true,
	d = true, w = true, m = true,
}

-- The key combination that repositions the pair mid-Trial, as a list of input names.
--
-- Case is meaningful here and nowhere else in this file: the engine spells directions
-- in capitals and buttons in lower case, and `D` (down) is a different key from `d`
-- (the taunt button the pre-refactor combination used). So the value is read as
-- authored rather than lowercased, and an unrecognised name is dropped with a warning
-- instead of arming a combination the player can never complete.
local function repositionKeys()
	local raw = cfgGet({'trials_mode', 'trialresetkeys'})
	if type(raw) ~= 'table' then
		raw = {raw}
	end
	local out = {}
	for _, v in ipairs(raw) do
		local key = tostring(v):match('^%s*(.-)%s*$')
		if key ~= '' then
			if INPUT_KEYS[key] then
				out[#out + 1] = key
			else
				print('Trials: trialresetkeys names ' .. key .. ', which is not an input ' ..
					'the engine answers for — ignoring it.')
			end
		end
	end
	return out
end

-- One end of the reposition fade: time, colour, an optional animation drawn over the
-- darkened screen, and an optional sound played as it starts. A time of 0 means no fade
-- at all, which fadeNew already treats as nothing to run.
--
-- THE ANIMATION REPLACES THE COLOUR WIPE rather than accompanying it. That is the
-- engine's own rule for its own fades, not a choice made here: Fade.init takes the
-- overlay's duration from colorFadeTime, which returns 0 whenever an animation is
-- present, and the fade then lasts exactly as long as that animation
-- (src/rect.go:47, :71). A screenpack that sets both gets the artwork.
--
-- Which is why the sprite is held for the configured time rather than indefinitely. A
-- Lua module can only build single-sprite animations — the engine's action table is
-- unexported, as buildAnim explains — and GetLength counts an indefinite frame as one
-- tick (src/anim.go:557). Left at the default the artwork would suppress the colour
-- wipe and then last a single frame, so `time` would be honoured by neither. Given to
-- the frame instead, the fade lasts exactly as long as it is configured to, whether the
-- screen goes dark or the artwork plays over it.
--
-- Returns the Fade and whether an animation was built for it, which the debug dump
-- reports: a fade drawing artwork and one drawing a colour are the same fade from
-- outside, and this is what tells them apart without a screenshot.
--
-- The artwork is built only where a key actually names some. buildArt falls back to the
-- module's own trials.sff, and asking it unconditionally would load that file on every
-- install whether or not anything ever draws out of it — which is exactly the cost
-- moduleSff is lazy to avoid.
local function buildFade(name)
	local path = {'trials_mode', name}
	local col = numList(cfgGet(join(path, 'col')), {0, 0, 0})
	-- A negative group plays nothing, which is how the engine reads an absent snd and
	-- what this file ships: the module carries no sounds of its own.
	local snd = numList(cfgGet(join(path, 'snd')), {-1, 0})
	local time = math.max(0, numList(cfgGet(join(path, 'time')), {0})[1])
	local art = nil
	if time > 0 and (cfgGet(join(path, 'spr')) ~= nil or cfgGet(join(path, 'anim')) ~= nil) then
		art = buildArt(path, nil, false, time)
		-- A fade is the one element with no position of its own, and that breaks the
		-- rule the rest of them resolve their coordinate space by.
		--
		-- sharedLocalcoord asks who wrote `pos`, because for every other element that is
		-- who decided where it sits and therefore whose space it sits in. Nobody writes
		-- `fadeout.pos` — a fade covers the screen — so the answer comes back "nobody",
		-- which it reads as this module's own 320x240. A screenpack's sprite then draws
		-- in a space a quarter the width it was authored for: at 1280x720 the artwork
		-- covers four screens and hangs off the top-left corner.
		--
		-- So the space follows the ARTWORK here, which is the only provenance a fade
		-- actually has, and is the question artIsOurs already answers for the file the
		-- sprite comes out of. A screenpack's sprite resolves in the screenpack's
		-- localcoord — which is also what the engine's own fades get, since it threads
		-- the motif's localcoord down to every element as the default
		-- (src/iniutils.go:2782). An explicit pos or localcoord still wins.
		if art ~= nil and sourceOf(path, 'pos') == nil
			and sourceOf(path, 'localcoord') == nil then
			local lc = artIsOurs(path, nil) and MODULE_LOCALCOORD
				or {motif.info.localcoord[1], motif.info.localcoord[2]}
			animSetLocalcoord(art.AnimData, lc[1], lc[2])
			-- Copied, for the reason every localcoord in this file is: MODULE_LOCALCOORD
			-- is one shared table and the dump elides a table it has already printed.
			art.localcoord = {lc[1], lc[2]}
		end
		-- Registered like any other drawn element, so the dump reports the geometry it
		-- resolved to. This is the one element whose coordinate space is decided by a
		-- rule of its own, and a fade drawing its artwork at the wrong scale looks like
		-- the fade being broken rather than like a localcoord.
		if art ~= nil then
			trials.elements[name] = art
		end
	end
	return fadeNew({
		time = time,
		color = {col[1] or 0, col[2] or 0, col[3] or 0},
		anim = art ~= nil and art.AnimData or nil,
		sound = {snd[1], snd[2]},
	}), art ~= nil
end

if trials.enabled then
	trials.elements.trialcounter = buildText({'trials_mode', 'trialcounter'})
	trials.elements.totaltrialtimer = buildTimer('totaltrialtimer')
	trials.elements.currenttrialtimer = buildTimer('currenttrialtimer')
	trials.elements.success = buildBanner('success')
	trials.elements.allclear = buildBanner('allclear')
	trials.elements.trialresetreminder = buildText({'trials_mode', 'trialresetreminder'})
	trials.elements.trialresetreminder.text =
		strValue(cfgGet({'trials_mode', 'trialresetreminder', 'text'}), '')
	trials.textbox = buildTextbox()
	-- Both Layouts, built once. trials.stepblock is whichever one the Layout preference
	-- selects, and applyStepLayout below points it at that — it cannot be resolved here,
	-- because reading a preference is reading config.ini and that reader is defined with
	-- the rest of them, further down.
	trials.stepblocks = {}
	for _, layout in ipairs(STEP_LAYOUTS) do
		trials.stepblocks[layout] = buildStepBlock(layout)
	end
	trials.stepblock = trials.stepblocks[STEP_LAYOUTS[1]]
	-- Everything the mid-Trial reposition needs, resolved once. `keys` empty, or
	-- enabled false, is the feature switched off.
	trials.reposition = {
		-- On unless the config says otherwise. loadIni hands `false` back as a Lua
		-- boolean, and a screenpack writing the word is just as clear.
		enabled = not (cfgGet({'trials_mode', 'trialresetenabled'}) == false
			or strValue(cfgGet({'trials_mode', 'trialresetenabled'}), ''):lower() == 'false'),
		keys = repositionKeys(),
		fadeoutTime = math.max(0, numList(cfgGet({'trials_mode', 'fadeout', 'time'}), {0})[1]),
		fadeinTime = math.max(0, numList(cfgGet({'trials_mode', 'fadein', 'time'}), {0})[1]),
	}
	-- Assigned rather than written into the constructor above, because buildFade answers
	-- with two values and a constructor field takes only the first.
	trials.reposition.fadeout, trials.reposition.fadeoutAnim = buildFade('fadeout')
	trials.reposition.fadein, trials.reposition.fadeinAnim = buildFade('fadein')
end

--;===========================================================
--; THE TRIALS BACKGROUND
--;===========================================================
-- The mode's own backdrop: a [TrialsBgDef] section, with its elements in [TrialsBg ...]
-- sections beside it, drawn behind everything else this module puts on screen.
--
-- This is the one part of the presentation layer the closed motif struct cannot take
-- away. bgNew is handed a DEF PATH and a SECTION NAME and parses the file itself, so
-- `[TrialsBgDef]` resolves in full — scroll, sinx, velocity, every background element
-- key the engine documents — even though the Go struct drops the section on the floor
-- (motif.go:1330 has a map for `*resultsbgdef` and one for `*pausebgdef`, and nothing
-- either would match). Nothing here reads trials.config for the elements; the merged
-- table is consulted only for `spr`, which names the file the sprites come out of.
--
-- WHERE IT DRAWS. Over the stage, under the module's own elements, for the length of a
-- live round — the module draws in a match and nowhere else, so that is where a mode
-- backdrop can be. A screenpack positions it wherever its own artwork wants: a panel
-- behind the Step block, a frame around the screen, a strip along the top. Absent, it
-- is nothing at all, which is what a stock install gets.
--
-- Deliberately NOT the pause menu's background. That one is `[TrialsPauseBgDef]` and
-- the engine resolves it natively from the game mode name (menu.lua:391, motif.go:1336),
-- which is what the pre-refactor module's own trialsbgdef was doing by hand.
--
-- bgclearcolor is read by bgNew and then never used here: clearing the screen is what
-- it does, and a mode drawn over a live match would erase the stage with it.
if trials.enabled then
	-- Which file to parse. bgNew re-reads the def rather than taking the merged table,
	-- so the section has to be pointed at ONE file — and the one it points at is the
	-- last layer that declared it, which is the precedence every other key resolves
	-- under. config.ini can win it like any other layer; a player who writes the section
	-- there gets it, and pays for the oddity of a def section in an ini by writing it.
	local defPath = nil
	for _, layer in ipairs(layers) do
		if type(layer.ini.trialsbgdef) == 'table' then
			defPath = layer.path
		end
	end
	if defPath ~= nil then
		-- The screenpack's own sff unless the section names another, which is the
		-- fallback the pre-refactor module had and the one a screenpack styling the mode
		-- out of its existing artwork wants. Guarded because sffNew raises rather than
		-- returning nil on a missing file (src/script.go:2419), the way moduleSff is.
		local sff = motif.Sff
		-- The authored value and the resolved path are kept apart on purpose.
		-- normalizePath answers '' both for a key nobody wrote and for one naming a file
		-- searchFile could not find, and those are not the same thing: the second is a
		-- typo the author wants told about, and folding it into the first would fall
		-- back to the screenpack's sff in silence — drawing the wrong artwork, or none,
		-- with nothing anywhere to say why.
		local authored = strValue(cfgGet({'trialsbgdef', 'spr'}), '')
		local spr = normalizePath(authored)
		if authored ~= '' and spr == '' then
			print('Trials: [TrialsBgDef] spr = ' .. authored .. ' was not found. ' ..
				'Falling back to the screenpack\'s own sff.')
		elseif spr ~= '' then
			local ok, loaded = pcall(sffNew, spr)
			if ok then
				sff = loaded
			else
				print('Trials: [TrialsBgDef] spr = ' .. spr .. ' did not load (' ..
					tostring(loaded) .. '). Falling back to the screenpack\'s own sff.')
			end
		end
		trials.backgroundDef = defPath
		-- What was asked for, not what resolved: the dump has to be able to tell a
		-- missing file from an absent key, and the message above from silence.
		trials.backgroundSpr = authored
		trials.backgroundSprResolved = spr
		-- bgNew raises on a def it cannot read, and a background is the most decorative
		-- thing this module owns: a malformed one should cost its own absence and not
		-- the mode.
		local ok, bg = pcall(bgNew, sff, defPath, 'trialsbg')
		if ok then
			trials.background = bg
		else
			print('Trials: [TrialsBgDef] in ' .. defPath .. ' did not load (' ..
				tostring(bg) .. '). No trials background is drawn.')
		end
	end
end

--;===========================================================
--; TRIAL DEFINITION PARSING
--;===========================================================
-- The one file the module parses itself. Everything else it reads goes through the
-- engine's loadIni (docs/adr/0001); this does not, and docs/adr/0004 is why.
--
-- The short of it: go-ini merges same-named sections, so a character that spells the
-- same combo once per mode as a repeated [TrialDef, <title>] loses every body but the
-- last by the time loadIni returns (#51). The bodies are only recoverable from the raw
-- text, and no Lua entry point parses ini out of a string, so the text is parsed here.
--
-- What follows is deliberately a copy rather than an improvement: a Trial Definition
-- has to resolve to the same values whichever reader sees it. It reproduces go-ini's
-- parser (parser.go:340, under the options src/script.go:4396 passes it) and then
-- iniToLuaTable, setNestedLuaKey and parseIniLuaValue (src/script.go:450-630) with
-- normalizeSections off and keepMeta on — the arguments readTrialDefinition used to
-- hand loadIni. The one intended difference is the merge: sections come back as a
-- list, in authored order, and two headers with the same name stay apart.

-- Scoped rather than adding a dozen more file-level locals: Lua allows 200 to a scope
-- and this file is well into them. Only the two the discovery below calls leave the
-- block, and the helpers inside are named after the Go they reproduce.
local parseIniText, safeLoadText
do

-- strings.TrimSpace, near enough: Go trims every unicode space and this trims the
-- ASCII ones, which is every space an ini line is written with.
local function trim(s)
	return (s:gsub('^%s*(.-)%s*$', '%1'))
end

-- The last occurrence of `needle` in `s`, 1-based, or nil. strings.LastIndex.
local function lastIndex(s, needle)
	local at = nil
	local from = 1
	while true do
		local p = s:find(needle, from, true)
		if p == nil then
			return at
		end
		at, from = p, p + 1
	end
end

-- Splits a value on the commas that are not inside quotes, and reports a value that
-- does not split as the single token it is. splitIniListOutsideQuotes, src/script.go:494.
local function splitOutsideQuotes(s)
	local out, buf = {}, {}
	local inSingle, inDouble, escaped = false, false, false
	local function flush()
		local tok = trim(table.concat(buf))
		buf = {}
		if tok ~= '' then
			out[#out + 1] = tok
		end
	end
	for i = 1, #s do
		local c = s:sub(i, i)
		if escaped then
			-- The escape is kept as written. It exists to stop \" and \' from
			-- toggling the quote state, not to unescape anything here.
			buf[#buf + 1] = c
			escaped = false
		elseif c == '\\' and (inSingle or inDouble) then
			escaped = true
			buf[#buf + 1] = c
		elseif c == '"' then
			if not inSingle then inDouble = not inDouble end
			buf[#buf + 1] = c
		elseif c == "'" then
			if not inDouble then inSingle = not inSingle end
			buf[#buf + 1] = c
		elseif c == ',' and not inSingle and not inDouble then
			flush()
		else
			buf[#buf + 1] = c
		end
	end
	flush()
	local whole = trim(s)
	if #out == 0 then
		return whole == '' and {} or {whole}
	end
	if #out == 1 and out[1] == whole then
		return {whole}
	end
	return out
end

-- One code point, as UTF-8. What Go writes for a \u or \U escape, and the one part of
-- unquoting below that Lua 5.1 has no library call for.
local function utf8Char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000),
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
	return string.char(0xF0 + math.floor(cp / 0x40000),
		0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- strconv.Unquote, as far as an ini value can reach it, with Go's own fallback: where
-- Unquote fails the outer quotes are stripped and the body kept verbatim
-- (parseIniLuaValue, src/script.go:576). Every `return body` below is one of Go's
-- syntax errors taking that fallback.
--
-- Single quotes take the fallback in Go for anything but a one-rune literal, so `'a b'`
-- and `'a'` both come back as their body either way. The divergence left is `'\n'`,
-- which Go reads as a newline and this reads as a backslash and an n; no Trial
-- Definition writes a rune literal.
local function unquote(s)
	local body = s:sub(2, -2)
	if s:sub(1, 1) ~= '"' or body:find('[\n\r]') then
		return body
	end
	-- `\'` is missing on purpose: Go allows it only in a rune literal, and rejects the
	-- whole string for it inside double quotes.
	local simple = {
		n = '\n', t = '\t', r = '\r', a = '\a', b = '\b', f = '\f', v = '\v',
		['\\'] = '\\', ['"'] = '"',
	}
	local out, i = {}, 1
	while i <= #body do
		local c = body:sub(i, i)
		if c ~= '\\' then
			if c == '"' then
				-- An unescaped quote inside the string: not a Go string literal.
				return body
			end
			out[#out + 1] = c
			i = i + 1
		else
			local e = body:sub(i + 1, i + 1)
			if simple[e] ~= nil then
				out[#out + 1] = simple[e]
				i = i + 2
			elseif e == 'x' or e == 'u' or e == 'U' then
				-- Fixed widths, all three of them: \xNN, \uNNNN, \UNNNNNNNN.
				local width = (e == 'x' and 2) or (e == 'u' and 4) or 8
				local digits = body:sub(i + 2, i + 1 + width)
				if #digits ~= width or digits:find('%X') then
					return body
				end
				local n = tonumber(digits, 16)
				if e == 'x' then
					out[#out + 1] = string.char(n)
				else
					-- A surrogate half is not a code point, and Go says so.
					if (n >= 0xD800 and n <= 0xDFFF) or n > 0x10FFFF then
						return body
					end
					out[#out + 1] = utf8Char(n)
				end
				i = i + 2 + width
			else
				-- Octal, which Go spells in exactly three digits and no fewer, so `\0`
				-- on its own is a syntax error rather than a NUL.
				local digits = body:sub(i + 1, i + 3)
				if not digits:match('^[0-7][0-7][0-7]$') then
					return body
				end
				local n = tonumber(digits, 8)
				if n > 255 then
					return body
				end
				out[#out + 1] = string.char(n)
				i = i + 4
			end
		end
	end
	return table.concat(out)
end

-- strconv.ParseInt(s, 0, 64): a base taken from the literal's own prefix, and the whole
-- string or nothing. Lua's tonumber(s, base) is strconv.ParseInt(s, base) underneath
-- (gopher-lua baselib), so it rejects the same digits.
--
-- Underscore separators, which Go allows at base 0, are not read here — `1_000` comes
-- back as the string it was written as.
local function parseInt(s)
	local sign = 1
	if s:sub(1, 1) == '+' then
		s = s:sub(2)
	elseif s:sub(1, 1) == '-' then
		sign, s = -1, s:sub(2)
	end
	local base, digits = 10, s
	local prefix = s:sub(1, 2):lower()
	if prefix == '0x' then
		base, digits = 16, s:sub(3)
	elseif prefix == '0b' then
		base, digits = 2, s:sub(3)
	elseif prefix == '0o' then
		base, digits = 8, s:sub(3)
	elseif #s > 1 and s:sub(1, 1) == '0' then
		base, digits = 8, s:sub(2)
	end
	-- gopher-lua's tonumber takes the base only for a string with no '.' in it: with one
	-- it reaches strconv.ParseFloat and ignores the base entirely (baselib.go:412), so
	-- `0.5` would come back from the octal branch as a float. ParseInt takes neither.
	if digits == '' or digits:find('.', 1, true) then
		return nil
	end
	local n = tonumber(digits, base)
	if n == nil then
		return nil
	end
	return sign * n
end

-- strconv.ParseFloat, which gopher-lua's tonumber is not: it only reaches ParseFloat
-- when the string holds a '.', so `1e3` comes back nil from it (baselib.go:412) while
-- the engine reads 1000. The exponent is split off and applied here for that reason.
local function parseFloat(s)
	local mantissa, exponent = s:match('^([^eE]*)[eE]([-+]?%d+)$')
	if mantissa == nil then
		mantissa = s
	end
	if not mantissa:match('^[-+]?%d*%.?%d*$') or mantissa:match('^[-+]?%.?$') then
		return nil
	end
	-- A mantissa with no '.' is given one, so that tonumber takes the ParseFloat path
	-- for it rather than the base path.
	local n = tonumber(mantissa:find('.', 1, true) and mantissa or (mantissa .. '.0'))
	if n == nil then
		return nil
	end
	if exponent ~= nil then
		n = n * 10 ^ tonumber(exponent)
	end
	return n
end

-- One ini value as the engine types it: a comma-separated list becomes an array, a
-- quoted token a string, `true`/`false` a boolean, a number a number, and anything
-- else the string it was written as. parseIniLuaValue, src/script.go:552.
local function iniValue(raw)
	local s = trim(raw)
	if s == '' then
		return ''
	end
	local parts = splitOutsideQuotes(s)
	if #parts > 1 then
		local list = {}
		for _, p in ipairs(parts) do
			list[#list + 1] = iniValue(p)
		end
		return list
	end
	local first, last = s:sub(1, 1), s:sub(-1)
	if #s >= 2 and ((first == '"' and last == '"') or (first == "'" and last == "'")) then
		return unquote(s)
	end
	local lower = s:lower()
	if lower == 'true' then
		return true
	elseif lower == 'false' then
		return false
	end
	local n = parseInt(s)
	if n ~= nil then
		return n
	end
	-- Rounded to six places, as RoundFloat does (src/common.go:383). Go's `inf` and
	-- `nan` words and its hex floats are the values parseFloat does not read; they stay
	-- the strings they were written as, which no Trial Definition notices.
	n = parseFloat(s)
	if n ~= nil then
		-- math.Round is half away from zero, which floor(x + 0.5) is not below zero.
		if n < 0 then
			return -math.floor(-n * 1000000 + 0.5) / 1000000
		end
		return math.floor(n * 1000000 + 0.5) / 1000000
	end
	return s
end

-- keepMeta's key order: every table carries the keys written into it, in the order
-- they were first written. luaIniAppendOrder, src/script.go:433.
local function appendOrder(t, key)
	local order = t.__order
	if order == nil then
		order = {}
		t.__order = order
	end
	for i = 1, #order do
		if order[i] == key then
			return
		end
	end
	order[#order + 1] = key
end

-- A dotted key written into its nested tables, with keepMeta's rule for a key that is
-- both a value and a parent: the scalar is parked in __value rather than lost, whichever
-- of the two was written first. setNestedLuaKey, src/script.go:450.
local function setNestedKey(t, key, value)
	local parts = {}
	local from = 1
	while true do
		local p = key:find('.', from, true)
		if p == nil then
			parts[#parts + 1] = key:sub(from)
			break
		end
		parts[#parts + 1] = key:sub(from, p - 1)
		from = p + 1
	end
	local cur = t
	for i, part in ipairs(parts) do
		appendOrder(cur, part)
		if i == #parts then
			if type(cur[part]) == 'table' then
				cur[part].__value = value
			else
				cur[part] = value
			end
			return
		end
		local existing = cur[part]
		if type(existing) == 'table' then
			cur = existing
		else
			local sub = {}
			if existing ~= nil then
				sub.__value = existing
			end
			cur[part] = sub
			cur = sub
		end
	end
end

-- The lines of a file, however its author ended them. NormalizeNewlines,
-- src/common.go:388, which is what the engine hands go-ini.
local function iniLines(text)
	text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
	local lines = {}
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		lines[#lines + 1] = line
	end
	return lines
end

-- The key name on one line, and where its value starts. readKeyName, parser.go:124.
--
-- Returns nil for a line with no `=` or `:` on it and for one that starts with the
-- delimiter, both of which SkipUnrecognizableLines drops; and nil plus a message for a
-- key quote that is never closed, which go-ini fails the whole file over.
local function readKeyName(line)
	local quote = nil
	local head = line:sub(1, 1)
	if head == '"' then
		-- go-ini measures the line with its newline still on it, so its `len > 6` is
		-- six characters of key line here, and the value below is the same. The last
		-- line of a file that ends without a newline is the one place that is a
		-- character out, and it takes a `"""` with nothing after it to notice.
		quote = (#line >= 6 and line:sub(1, 3) == '"""') and '"""' or '"'
	elseif head == '`' then
		quote = '`'
	end
	if quote ~= nil then
		local q = #quote
		local close = line:find(quote, q + 1, true)
		if close == nil then
			return nil, nil, 'missing closing key quote: ' .. line
		end
		local delim = line:find('[=:]', close + q)
		if delim == nil then
			return nil
		end
		return trim(line:sub(q + 1, close - 1)), delim + 1
	end
	local delim = line:find('[=:]')
	if delim == nil or delim == 1 then
		return nil
	end
	return trim(line:sub(1, delim - 1)), delim + 1
end

-- The value starting at `from` on line `n`, and the last line it consumed — a triple
-- quoted or backquoted value runs to its closing quote and a value ending in a
-- backslash runs to the first line that does not. readValue, parser.go:228.
--
-- Inline comments are cut at the first `#` or `;` anywhere in an unquoted value, which
-- is go-ini's default and is why a Step's text cannot contain either character. The
-- surrounding quotes of a quoted value are left on: PreserveSurroundedQuote is set, so
-- stripping them is parseIniLuaValue's job and not this one's.
local function readValue(lines, n, from)
	local line = lines[n]:sub(from):gsub('^%s+', '')
	if line == '' then
		return '', n
	end
	local quote = nil
	if #line >= 3 and line:sub(1, 3) == '"""' then
		quote = '"""'
	elseif line:sub(1, 1) == '`' then
		quote = '`'
	end
	if quote ~= nil then
		local rest = line:sub(#quote + 1)
		local close = lastIndex(rest, quote)
		if close ~= nil then
			return rest:sub(1, close - 1), n
		end
		local val, i = rest .. '\n', n
		while true do
			i = i + 1
			if lines[i] == nil then
				return nil, nil, 'missing closing key quote: ' .. line
			end
			local nxt = lines[i] .. '\n'
			local p = lastIndex(nxt, quote)
			if p ~= nil then
				return val .. nxt:sub(1, p - 1), i
			end
			val = val .. nxt
		end
	end
	line = trim(line)
	if line:sub(-1) == '\\' then
		local val, i = line:sub(1, -2), n
		while true do
			i = i + 1
			if lines[i] == nil then
				return val, i - 1
			end
			local nxt = trim(lines[i])
			if nxt == '' then
				return val, i
			end
			val = val .. nxt
			if val:sub(-1) ~= '\\' then
				return val, i
			end
			val = val:sub(1, -2)
		end
	end
	local comment = line:find('[#;]')
	if comment ~= nil then
		line = trim(line:sub(1, comment - 1))
	end
	return line, n
end

-- A Trial Definition's sections, in the order the file declares them: an array of
-- {name = <section name>, data = <the section as loadIni would have built it>}.
--
-- Sections are not merged and neither are their names compared, which is the whole
-- point of parsing here (#51). Keys inside one section still are: go-ini's NewKey
-- overwrites a name it already holds and leaves it where it first appeared, so a key
-- written twice in one body keeps its first position and its last value.
--
-- The name is read the way go-ini reads it — from the opening bracket to the *last*
-- closing bracket on the line, then trimmed the way iniToLuaTable trims it. That is
-- why a header's trailing `;comment` is only dropped when it holds no bracket of its
-- own, which is what trialTitle then has to undo.
--
-- Returns nil and a message wherever go-ini refuses the whole file — an unclosed
-- section, an empty section name, a key or value quote that never closes — so a
-- definition the engine could not read is still not read here.
function parseIniText(text)
	local lines = iniLines(text)
	local sections = {}
	-- Keys written before the first header land in go-ini's DEFAULT section. Nothing
	-- reads it; it exists so that stray keys cannot fall into the first Trial.
	local current = {name = 'DEFAULT', keys = {}, values = {}}
	sections[1] = current
	local count = 1
	local n = 1
	while n <= #lines do
		local line = lines[n]:gsub('^%s+', '')
		local head = line:sub(1, 1)
		if line == '' or head == '#' or head == ';' then
			-- comment or blank
		elseif head == '[' then
			local close = lastIndex(line, ']')
			if close == nil then
				return nil, 'unclosed section: ' .. line
			end
			local name = line:sub(2, close - 1)
			if name == '' then
				return nil, 'empty section name'
			end
			current = {name = trim(name), keys = {}, values = {}}
			sections[#sections + 1] = current
			count = 1
		else
			local key, from, err = readKeyName(line)
			if err ~= nil then
				return nil, err
			end
			if key ~= nil then
				-- go-ini's auto-increment key, kept for the same reason the DEFAULT
				-- section is: so a line the engine would have read is not dropped.
				if key == '-' then
					key = '#' .. count
					count = count + 1
				end
				local value, last, verr = readValue(lines, n, from)
				if verr ~= nil then
					return nil, verr
				end
				if current.values[key] == nil then
					current.keys[#current.keys + 1] = key
				end
				current.values[key] = value
				n = last
			end
		end
		n = n + 1
	end
	-- Built here rather than as the file is read, so that the caller is handed the two
	-- fields this documents and not the scanner's own key list behind them.
	local out = {}
	for i, sec in ipairs(sections) do
		local data = {}
		for _, key in ipairs(sec.keys) do
			setNestedKey(data, key, iniValue(sec.values[key]))
		end
		out[i] = {name = sec.name, data = data}
	end
	return out, nil
end

-- A Trial Definition, as text. The other half of the pair safeLoadIni is in: same
-- resolution, same degradation, a different reader at the end of it.
--
-- loadText hands back nil for a file it cannot read rather than raising
-- (src/script.go:5038), so the nil is what has to be caught; the pcall is there for
-- the argument errors the binding itself raises.
function safeLoadText(path)
	local resolved, err = resolveFile(path)
	if resolved == nil then
		return nil, err
	end
	local ok, result = pcall(loadText, resolved)
	if not ok then
		return nil, tostring(result)
	end
	if type(result) ~= 'string' then
		return nil, 'unreadable: ' .. resolved
	end
	return result, nil
end

end

--;===========================================================
--; TRIAL DEFINITION DISCOVERY
--;===========================================================

-- The Trial title is whatever follows the first comma of the section name.
--
-- When the header's trailing comment contains a bracket, go-ini's last-bracket rule
-- swallows the comment into the name and takes the header's own closing bracket with
-- it — the sample KFM definition does exactly this. Strip both, but only when a
-- semicolon is actually present, so a title that legitimately ends in a bracket
-- ([TrialDef, Combo [hard]]) survives intact.
local function trialTitle(section)
	local title = section:match('^[^,]*,%s*(.-)%s*$') or ''
	if title:find(';') then
		title = title:gsub('%s*;.*$', ''):gsub('%s*%]%s*$', '')
	end
	return (title:gsub('%s*$', ''))
end

-- Reads one Trial Definition value in the player's language.
--
-- Trials Config takes its language from a section-name prefix, but a Trial Definition
-- takes it from a key suffix — `trialstep.1.text.es` alongside `trialstep.1.text` —
-- which is the format's own documented spelling and is unchanged. loadIni turns that
-- pair into a table holding the variants, with the unsuffixed value in __value, so the
-- fallback chain the README describes reads straight off it: the selected language,
-- then English, then whatever was written with no suffix at all.
local function localized(v)
	if type(v) ~= 'table' or isValueList(v) then
		return v
	end
	local pick = v[trials.language]
	if pick == nil then
		pick = v.en
	end
	if pick == nil then
		pick = v.__value
	end
	return pick
end

-- The Dummy vocabulary a Trial Definition is written in, mapped onto the values
-- trials.zss reads back out of the shared training maps (docs/adr/0002). Names and
-- defaults are the ones the README documents, and the file format is unchanged.
--
-- `auto` guard resolves to 2 — the map's "guard everything" — rather than to 1, its
-- "guard once hit". That is what the pre-refactor module settled on (b0211ff, "Fixes
-- autoguard") and what the README means by auto: a Dummy that only starts guarding
-- after the first hit lands has already let the combo starter through, which is the
-- opposite of what a Trial author asks for. 1 and 3 stay unreachable from a Trial
-- Definition because the format has never spelled them.
--
-- One entry per setting, each carrying everything about it that anything downstream
-- needs: the key a Trial Definition spells it with, the shared map trials.zss reads it
-- back out of, its default, and the words that resolve to each value.
local dummyVocabulary = {
	{
		field = 'mode',
		key = 'dummymode',
		map = '_iksys_trainingDummyMode',
		default = 0,
		values = {stand = 0, crouch = 1, jump = 2, wjump = 3},
	},
	{
		field = 'guard',
		key = 'guardmode',
		map = '_iksys_trainingGuardMode',
		default = 0,
		values = {none = 0, auto = 2},
	},
	{
		field = 'buttonjam',
		key = 'dummybuttonjam',
		map = '_iksys_trainingButtonJam',
		default = 0,
		values = {none = 0, a = 1, b = 2, c = 3, x = 4, y = 5, z = 6, start = 7, d = 8, w = 9},
	},
}

-- One Trial's Dummy settings, fully resolved.
--
-- Every field is filled even when the Trial names none, which is what stops a setting
-- leaking from the Trial before it: with the pause menu carrying no dummy items
-- (docs/adr/0002) there is nothing a player could use to notice a stale value, so the
-- Trial always carries the whole triple rather than a partial one.
--
-- The authored word is kept alongside each number. It is what the debug dump is
-- readable from, and what makes a fallback distinguishable from a Trial that asked for
-- the default outright: an empty word means the Trial named nothing.
--
-- `data` is one parsed [TrialDef]; nil asks for the defaults on their own.
-- One `trial.*` key as the author wrote it: lowercased, trimmed, '' when unwritten.
local function authoredWord(raw, key)
	local v = type(raw) == 'table' and raw[key] or nil
	-- loadIni parks the scalar in __value when a key is both a value and a parent.
	if type(v) == 'table' and v.__value ~= nil then
		v = v.__value
	end
	return strValue(v, ''):lower():match('^%s*(.-)%s*$')
end

-- The one thing every unusable value in the authored block does: say so, then fall back.
local function warnValue(path, section, key, word)
	print('Trials: ' .. path .. ' [' .. section .. '] trial.' .. key ..
		' = ' .. word .. ' is not a recognised value — using the default.')
end

local function readDummy(data, path, section)
	local raw = type(data) == 'table' and data.trial or nil
	local out = {authored = {}}
	for _, spec in ipairs(dummyVocabulary) do
		local word = authoredWord(raw, spec.key)
		if word ~= '' and spec.values[word] == nil then
			warnValue(path, section, spec.key, word)
			word = ''
		end
		out[spec.field] = word ~= '' and spec.values[word] or spec.default
		out.authored[spec.field] = word
	end
	return out
end

-- What a Trial that names nothing resolves to, and what a character with no Trial
-- Definition gets.
local defaultDummy = readDummy(nil)

-- The five words `trial.playerpos` and `trial.dummypos` are written in, and what each
-- one actually says. Two of them name a corner, three name a distance — which is the
-- whole of why the two keys read the way they do below.
local POSITION_WORDS = {
	['left-corner'] = {corner = 'left'},
	['right-corner'] = {corner = 'right'},
	-- One gap table, used both for the space behind a cornered character and for the
	-- space either side of centre stage. The pre-refactor module spelled the second as
	-- half of the first (5/65/130 against 10/130/260); it is the same distance said
	-- twice, so it is written once here.
	close = {gap = 10},
	medium = {gap = 130},
	far = {gap = 260},
}

-- The gap a corner assumes when no Trial named one.
local DEFAULT_GAP = 130

-- Where a Trial stands the two characters, resolved as far as it can be without a
-- stage.
--
-- The two keys are *not* interchangeable, which is the one thing the pre-refactor
-- module got wrong here: it read either key for either meaning, so `playerpos =
-- left-corner` put the *Dummy* in the corner half the time. Each key now names its own
-- character, and the split falls out of the vocabulary:
--
--   * A corner is a place, so it belongs to the character whose key spelled it. Only
--     one character can have it; a Trial naming two corners keeps the Dummy's and is
--     warned about the other.
--   * A distance is a relation, not a place, so it belongs to neither character on its
--     own. Either key may name it and it means the same thing: how far apart the pair
--     starts. Two different distances keep the Dummy's, again with a warning.
--
-- `spaced` is whether a distance was actually named, which is what separates "put them
-- 130 apart around centre stage" from "leave them on the stage's own start positions".
local function readPositions(data, path, section)
	local raw = type(data) == 'table' and data.trial or nil
	local out = {corner = '', cornered = '', gap = DEFAULT_GAP, spaced = false,
		authored = {player = '', dummy = ''}}
	-- The Dummy first, so hers is the one already in place when the player's is read
	-- and found to conflict.
	for _, side in ipairs({{field = 'dummy', key = 'dummypos'}, {field = 'player', key = 'playerpos'}}) do
		local word = authoredWord(raw, side.key)
		if word ~= '' and POSITION_WORDS[word] == nil then
			warnValue(path, section, side.key, word)
			word = ''
		end
		out.authored[side.field] = word
		local meaning = POSITION_WORDS[word]
		if meaning ~= nil then
			if meaning.corner ~= nil then
				if out.corner ~= '' then
					print('Trials: ' .. path .. ' [' .. section .. '] trial.' .. side.key ..
						' = ' .. word .. ' — only one character can be in a corner, and ' ..
						'trial.' .. (out.cornered == 'dummy' and 'dummypos' or 'playerpos') ..
						' already named one. Ignoring this one.')
				else
					out.corner = meaning.corner
					out.cornered = side.field
				end
			elseif out.spaced and out.gap ~= meaning.gap then
				print('Trials: ' .. path .. ' [' .. section .. '] trial.' .. side.key ..
					' = ' .. word .. ' — a distance is the gap between the two ' ..
					'characters, and the other key already set it. Ignoring this one.')
			else
				out.gap = meaning.gap
				out.spaced = true
			end
		end
	end
	return out
end

-- How much life a Trial starts each character with.
--
-- 0 is the map's own word for "no override, use lifeMax", so it is what an unnamed and
-- an unusable value both resolve to. A life total is a count, so anything that is not a
-- positive whole number is a mistake worth saying out loud rather than rounding into
-- something playable.
local function readLife(data, path, section)
	local raw = type(data) == 'table' and data.trial or nil
	local out = {player = 0, dummy = 0, authored = {player = '', dummy = ''}}
	for _, side in ipairs({{field = 'player', key = 'playerlife'}, {field = 'dummy', key = 'dummylife'}}) do
		local word = authoredWord(raw, side.key)
		out.authored[side.field] = word
		if word ~= '' then
			-- Plain decimal digits and nothing else. tonumber would also take `5e2`
			-- and `0x1f`, spellings no Trial Definition uses and every reader of this
			-- file would have to agree on.
			local n = word:match('^%d+$') and tonumber(word) or nil
			if n == nil or n < 1 then
				warnValue(path, section, side.key, word)
			else
				out[side.field] = n
			end
		end
	end
	return out
end

local defaultPositions = readPositions(nil)
local defaultLife = readLife(nil)

-- The condition fields a Step verifies against, in the order the format documents
-- them. What a Step's Part count is measured over: whichever of these the author wrote
-- as the longest list decides how many Parts the Step has, so a field missing from
-- this list would be silently unable to create one.
local CONDITION_KEYS = {
	'stateno', 'animno', 'projid', 'hitcount',
	'isthrow', 'iscounterhit', 'ishelper', 'isproj',
	'validfortickcount',
}

-- One Part's value of one condition field.
--
-- loadIni hands back an array for a comma-separated field and a bare value for a
-- single one, and those mean different things: `stateno = 200, 210` is one value per
-- Part, while `hitcount = 1` alongside it is Part 1's hit count and says nothing about
-- Part 2 — which then takes the field's default. An unwritten key arrives as the empty
-- string it was authored as rather than as nil, so both read as "not named".
local function partValue(v, index)
	if type(v) == 'table' then
		if isValueList(v) then
			v = v[index]
		else
			-- A key that is both a scalar and a parent keeps its scalar in __value.
			v = index == 1 and v.__value or nil
		end
	elseif index > 1 then
		v = nil
	end
	if v == nil or v == '' then
		return nil
	end
	return v
end

-- The numbers one Part will accept for a field. The format separates alternatives with
-- "|", so `stateno = 200|205` passes on either.
--
-- nil, not an empty list, for a field the Part does not name: the two are different
-- conditions, and only nil means "do not check this at all".
local function alternatives(v)
	if v == nil then
		return nil
	end
	local out = {}
	for token in tostring(v):gmatch('[^|]+') do
		local n = tonumber(token:match('^%s*(.-)%s*$'))
		if n ~= nil then
			out[#out + 1] = n
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

-- loadIni already turns `true` and `false` into Lua booleans. A quoted or otherwise
-- unrecognised spelling still resolves, which is what the pre-refactor parser did.
local function boolValue(v)
	if type(v) == 'boolean' then
		return v
	end
	return tostring(v or ''):lower() == 'true'
end

-- `12, 0|2|4` — a character variable and the values it may hold, in pairs, all of which
-- must hold. Two keys are written in this format and both are read here rather than
-- parsed twice: trialstep.X.validforvarvalpairs, which gates a Step (per Step and not
-- per Part, which is what the format documents), and trial.showforvarvalpairs, which
-- gates a whole Trial (#52).
local function readVarPairs(v)
	local list
	if type(v) == 'table' and isValueList(v) then
		list = v
	elseif v ~= nil and v ~= '' and type(v) ~= 'table' then
		list = {v}
	else
		return nil
	end
	local out = {}
	for i = 1, #list - 1, 2 do
		local index = tonumber(tostring(list[i]))
		local values = alternatives(list[i + 1])
		if index ~= nil and values ~= nil then
			out[#out + 1] = {var = index, values = values}
		end
	end
	if #out == 0 then
		return nil
	end
	return out
end

-- How many Parts a Step has: the length of its longest condition list. A Step whose
-- fields are all single values has exactly one Part, which is what an ordinary Step is.
local function partCount(raw)
	local n = 1
	for _, key in ipairs(CONDITION_KEYS) do
		local v = raw[key]
		if isValueList(v) and #v > n then
			n = #v
		end
	end
	return n
end

-- One Part, fully resolved. Every field is filled, so verification never has to ask
-- whether the author wrote one — an unwritten condition is nil and an unwritten flag
-- is false, and both are the same answer every frame.
--
-- Defaults are the ones README.md documents: hit count 1, every flag false.
local function readPart(raw, index)
	return {
		stateno = alternatives(partValue(raw.stateno, index)),
		animno = alternatives(partValue(raw.animno, index)),
		-- The Projectile controller's ProjID, and the only thing that identifies a
		-- projectile once it has connected. See readAttacker for why not stateno.
		projid = alternatives(partValue(raw.projid, index)),
		hitcount = math.max(0, math.floor(tonumber(partValue(raw.hitcount, index)) or 1)),
		isthrow = boolValue(partValue(raw.isthrow, index)),
		iscounterhit = boolValue(partValue(raw.iscounterhit, index)),
		ishelper = boolValue(partValue(raw.ishelper, index)),
		isproj = boolValue(partValue(raw.isproj, index)),
		-- Ticks the run survives without the next hit landing. nil is the format's
		-- default and means no grace at all.
		validfortickcount = tonumber(partValue(raw.validfortickcount, index)),
	}
end

-- The lengths of the screenpack's Glyph tokens, longest first.
--
-- Longest first is the engine's own rule (menu.lua:769) and it is what makes tokenising
-- work at all: `_D` is a prefix of `_DF`, so matching the shorter token first would
-- swallow the longer one's head and leave its tail unrecognised.
--
-- Lengths rather than the tokens themselves, because motif.glyphs is already a table
-- keyed by the raw token string — so trying one length is a single hash lookup, where
-- trying every token in order is a comparison against each of the seventy-odd a stock
-- screenpack ships, at every position of every Step of every Trial on the roster. The
-- result is identical: the longest token that matches here is the one the engine's own
-- ordered scan would have reached first.
--
-- Resolved once. motif.glyphs is fixed for the run.
local glyphLengths = nil
local function glyphTokenLengths()
	if glyphLengths ~= nil then
		return glyphLengths
	end
	glyphLengths = {}
	local seen = {}
	if type(motif.glyphs) == 'table' then
		for token in pairs(motif.glyphs) do
			-- An empty key would match everywhere and advance nowhere.
			if type(token) == 'string' and #token > 0 and not seen[#token] then
				seen[#token] = true
				glyphLengths[#glyphLengths + 1] = #token
			end
		end
	end
	table.sort(glyphLengths, function(a, b) return a > b end)
	return glyphLengths
end

-- The Glyphs one Step declares, as the tokens this screenpack knows.
--
-- Read at parse time rather than at draw time, so that a Step's notation is settled
-- before the first frame and the per-frame path only lays out what is already resolved.
--
-- Anything matching no token is dropped rather than drawn or raised: a Trial Definition
-- written against another screenpack's vocabulary keeps the Glyphs this one has and
-- loses the rest, and a Trial Definition declaring no Glyphs at all is an empty list
-- and not a missing one (#3). What was dropped is collected in `unknown` and reported
-- once for the whole file.
local function readGlyphs(raw, unknown)
	local text = strValue(raw, '')
	local lengths = glyphTokenLengths()
	local out = {}
	local i = 1
	while i <= #text do
		local matched = nil
		for _, n in ipairs(lengths) do
			local token = text:sub(i, i + n - 1)
			if #token == n and motif.glyphs[token] ~= nil then
				matched = token
				break
			end
		end
		if matched ~= nil then
			out[#out + 1] = matched
			i = i + #matched
		else
			local c = text:sub(i, i)
			-- Whitespace separates tokens in some authored notations and stands for
			-- nothing on screen, so it is not worth reporting.
			if c:match('%S') then
				unknown[c] = true
			end
			i = i + 1
		end
	end
	return out
end

-- The Steps of one Trial, in Step-number order, each with its Parts resolved.
--
-- loadIni splits `trialstep.1.text` into nested tables keyed by the literal string
-- '1' (setNestedLuaKey, src/script.go:450), so the list is a Lua hash and not an
-- array — # would report 0 and ipairs would stop immediately. Rebuild it by number.
local function readSteps(data, unknown)
	local raw = data.trialstep
	if type(raw) ~= 'table' then
		return {}
	end
	-- Sorted on the number, indexed by the key as authored: `trialstep.01` and
	-- `trialstep.1` are the same Step number but not the same table key, so the key has
	-- to be carried rather than rebuilt from the number.
	local order = {}
	for key, v in pairs(raw) do
		local n = tonumber(key)
		if n ~= nil and type(v) == 'table' then
			order[#order + 1] = {number = n, key = key}
		end
	end
	table.sort(order, function(a, b) return a.number < b.number end)
	local steps = {}
	for _, entry in ipairs(order) do
		local step = raw[entry.key]
		local parts = {}
		for i = 1, partCount(step) do
			parts[i] = readPart(step, i)
		end
		steps[#steps + 1] = {
			number = entry.number,
			text = strValue(localized(step.text), ''),
			-- Not localized: a Glyph is a picture of an input and reads the same in
			-- every language, so the key carries no language suffix the way text does.
			glyphs = readGlyphs(step.glyphs, unknown),
			parts = parts,
			-- Gates the whole Step rather than one of its Parts, so it sits here.
			validfor = readVarPairs(step.validforvarvalpairs),
		}
	end
	return steps
end

-- Parses a Trial Definition into its Trials, in the order the author wrote them.
--
-- One Trial per [TrialDef] section, whatever the section is called. Two sections may
-- carry the same title and they are still two Trials: that is how a character with
-- modes or grooves spells the same combo once per mode, with trial.showforvarvalpairs
-- deciding which of them the player is offered (#51, #52). The title is a label from
-- here on; the Trial's index is its identity.
local function readTrialDefinition(path)
	local text, err = safeLoadText(path)
	if text == nil then
		return nil, err
	end
	local sections, perr = parseIniText(text)
	if sections == nil then
		return nil, perr
	end
	local list = {}
	-- The characters no Glyph in this screenpack's vocabulary accounted for, gathered
	-- across the whole file so that a Trial Definition written for another screenpack
	-- costs one line of console rather than one per Step.
	local unknown = {}
	for _, sec in ipairs(sections) do
		if sec.name:lower():match('^trialdef') then
			-- Lowercased for the same reason Trials Config is: go-ini keeps key
			-- case as authored and the pre-refactor parser lowercased everything
			-- it read, so `TrialStep.1.Text` has always resolved.
			local name = sec.name
			local data = lowerKeys(sec.data)
			table.insert(list, {
				section = name,
				title = trialTitle(name),
				-- Read here rather than at draw time so a Trial's Textbox is known
				-- before the first frame: it decides which window variant the Step
				-- block clips to. Drawing the Textbox itself is #43.
				textbox = strValue(localized(type(data.trial) == 'table' and data.trial.textbox or nil), ''),
				steps = readSteps(data, unknown),
				-- Resolved here rather than at Trial start so the whole triple is
				-- known before the first frame, and so it lands in the debug dump
				-- with everything else the Trial Definition parsed to.
				dummy = readDummy(data, path, name),
				-- Where the pair stands and what life they start with. Resolved
				-- here for the same reason, and only as far as a stage-free parse
				-- can go: the words and the gap between them are settled now, the
				-- stage coordinates they land on at Trial start.
				positions = readPositions(data, path, name),
				life = readLife(data, path, name),
				-- Which modes this Trial is offered in: the character variables it
				-- is gated on, and the values they have to hold (#52). nil is an
				-- ungated Trial, which is every Trial that does not say otherwise.
				-- Read with the same function the Step gate is, because it is the
				-- same format — see readVarPairs.
				showfor = readVarPairs(type(data.trial) == 'table'
					and data.trial.showforvarvalpairs or nil),
				-- The section as parsed, kept for the keys no slice reads yet.
				-- Nothing on the per-frame path touches it.
				data = data,
			})
		end
	end
	local dropped = {}
	for c in pairs(unknown) do
		dropped[#dropped + 1] = c
	end
	if #dropped > 0 then
		table.sort(dropped)
		print('Trials: ' .. path .. ' names glyphs this screenpack has none for (' ..
			table.concat(dropped, ' ') .. ') — those are skipped, the rest still draw.')
	end
	-- Where each Trial sits in the file, carried on the Trial itself. Once
	-- showforvarvalpairs starts thinning the list a match runs (#52), position in that
	-- list is a moving target — it is rebuilt every round — and this is the one index
	-- that does not move. Completion is recorded against it, and it is how the player
	-- is kept on the Trial they were on across a re-evaluation.
	for i, trial in ipairs(list) do
		trial.index = i
	end
	return list, nil
end

-- Resolves the Trial Definition a character declares, through its own def file.
--
-- Sets t.trials to the parsed Trial list, or false when the character ships none. The
-- false matters: it marks the character as checked, so the sweep below is idempotent
-- and a character without Trials is never re-read.
local function discoverChar(t)
	if type(t) ~= 'table' or t.trials ~= nil or not t.playable or t.def == nil then
		return
	end
	t.trials = false
	local def = safeLoadIni(t.def, true, false)
	if def == nil or type(def.files) ~= 'table' then
		return
	end
	-- Lowercased for the same reason Trials Config and the Trial Definition are:
	-- loadIni normalizes section names only, so a def that writes `Trials =` under
	-- [Files] keeps that case. The pre-refactor module lowercased each line before
	-- matching (old_trials.lua:1554) and every other reader of a character def in the
	-- engine is case-insensitive, so a case-sensitive read here would silently drop
	-- definition files that used to work (#47).
	local rel = lowerKeys(def.files).trials
	if type(rel) ~= 'string' or rel == '' then
		return
	end
	local path = searchFile(rel, {t.dir or '', '', motif.def, 'data/'})
	if path == '' then
		print('Trials: ' .. tostring(t.name) .. ' declares trials = ' .. rel .. ', which was not found.')
		return
	end
	local list, err = readTrialDefinition(path)
	if list == nil then
		print('Trials: cannot read ' .. path .. ' (' .. tostring(err) .. ').')
		return
	end
	if #list == 0 then
		print('Trials: ' .. path .. ' declares no [TrialDef] sections.')
		return
	end
	-- The list itself, carrying the file it came from. #t.trials is then the number of
	-- Trials the character ships, which is what the counter needs.
	list.def = path
	t.trials = list
end

-- Fires for characters added after the module loads. The initial roster is not one of
-- them: main.lua builds it around line 1600 and only requires external modules at line
-- 3990, so this hook cannot see the characters that already exist. The sweep below is
-- what covers those.
hook.add('main.f_addChar.files', 'trials', discoverChar)

-- Reads every playable character's Trial Definition. Idempotent: discoverChar marks a
-- character with no Trials as `false`, so a repeat sweep re-reads nothing.
function trials.f_discoverAll()
	for _, t in ipairs(main.t_selChars) do
		discoverChar(t)
	end
end

-- At load, not on demand. The umbrella spec makes Trial Definition parsing one of the
-- things assertable from the startup dump with no interaction (#46, testing
-- decisions), and deferring the sweep to menu entry would leave that dump empty.
if trials.enabled then
	trials.f_discoverAll()
end

--;===========================================================
--; SELECT SCREEN
--;===========================================================
-- Characters shipping no Trial Definition are drawn under a palette effect while Trials
-- Mode is the active mode, so a player picking someone to practise with can see at a
-- glance who has content. The roster was swept at load, so `t.trials` already answers
-- the question for every character on the grid and nothing is parsed here.
--
-- The effect goes on the cell portrait's own Anim, which is what the engine's select
-- screen batch-draws, and it is applied with time = -1 so it stands rather than lasting
-- a tick — the same reason a Glyph's does (see readPalFX).
--
-- Every frame, and not once on entry. Portraits are preloaded lazily (main.lua:773
-- replaces cell_data the frame a character's own artwork arrives), so a one-shot pass
-- would tint whoever happened to be ready and leave the rest bright. Recording the Anim
-- each character was tinted THROUGH is what makes the repeat cheap: a cell whose
-- portrait has not changed costs one table lookup.
--
-- `start.selectScreenPalMod`, the module-global the pre-refactor version drove this
-- from, is not recreated. The state is two fields on the module's own table.
if trials.enabled then
	trials.selectpalfx = {
		fx = readPalFX({'trials_mode', 'selscreenpalfx'}),
		-- The engine's identity, for taking the effect off again. A PalFX cannot be
		-- removed from an Anim, only overwritten with one that does nothing.
		neutral = {
			time = -1,
			add = {0, 0, 0},
			mul = {256, 256, 256},
			sinadd = {0, 0, 0, 0},
			invertall = 0,
			color = 256,
		},
		-- Which Anim each darkened character was last tinted through, keyed by the
		-- character's own roster row. Both halves matter: the keys are who to clear on
		-- the way out, the values are how a lazily-loaded portrait is noticed.
		applied = {},
		active = false,
	}
end

hook.add('start.f_selectScreen', 'trials', function()
	local sp = trials.selectpalfx
	if sp == nil then
		return
	end
	if not gameMode('trials') then
		-- Off on the way out, and only on the way out: the select screen is shared with
		-- every other mode, and a portrait this module darkened would otherwise stay
		-- darkened in all of them. Cleared against the character's CURRENT Anim rather
		-- than the recorded one, since a portrait that finished loading since is the one
		-- carrying the effect now.
		if sp.active then
			for ch in pairs(sp.applied) do
				if ch.cell_data ~= nil then
					animSetPalFX(ch.cell_data, sp.neutral)
				end
				sp.applied[ch] = nil
			end
			sp.active = false
		end
		return
	end
	sp.active = true
	for row = 1, motif.select_info.rows do
		local grid = start.t_grid[row]
		for col = 1, motif.select_info.columns do
			local cell = grid ~= nil and grid[col] or nil
			if cell ~= nil and cell.skip ~= 1 then
				local ch = start.f_selGrid((row - 1) * motif.select_info.columns + col)
				-- A real character in a visible cell, with no Trials, whose portrait has
				-- not already been tinted through the Anim it is drawing with now.
				-- randomselect is excluded for the reason the pre-refactor module
				-- excluded it: it stands for whoever it picks, and dimming it would say
				-- something about that character that is not known yet.
				if type(ch) == 'table' and ch.char_ref ~= nil and ch.hidden == 0
					and ch.char ~= 'randomselect' and not ch.trials
					and ch.cell_data ~= nil and sp.applied[ch] ~= ch.cell_data then
					animSetPalFX(ch.cell_data, sp.fx)
					sp.applied[ch] = ch.cell_data
				end
			end
		end
	end
end)

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
		strValue(cfgGet({'trials_mode', 'menu', 'itemname', 'trials'}), 'TRIALS'),
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
	-- The roster was swept at load. This picks up anything a module loaded after trials
	-- added since, and costs one table walk when it has not.
	trials.f_discoverAll()

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
	main.luaPath = trials.dir .. 'fight.luascript'

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
--; MATCH
--;===========================================================
-- Which Trials this match is running, resolved from P1's selected character.
trials.match = nil

-- start.p[1].t_selected is the only place the engine records who P1 picked, and it is
-- read, never written — the header's warning is about *installing* onto `start`, which
-- is what tied the previous version to engine internals. Every step of the walk is
-- guarded, because a mode that reaches this hook without a selection should draw
-- nothing rather than raise mid-match.
local function resolveMatch()
	local m = {
		-- `declared` is every Trial the character's file spells; `trials` is the ones
		-- currently on offer, which is what everything downstream counts and indexes.
		-- The two differ only where trial.showforvarvalpairs gates one out (#52), and
		-- the thinning is applyAvailability's — once a round, see docs/adr/0003.
		declared = {}, trials = {}, total = 0, current = 1, steps = {},
		textbox = false, char = nil,
		-- Progress. `step` and `part` are where the player is; `combo` is comboCount()
		-- as of the last Part completed, which is what makes the next hit tell itself
		-- apart from the one that has already been counted.
		step = 1, part = 1, combo = 0, partHits = 0, partCombo = 0, grace = 0,
		-- Which Trials have been completed at least once, and how many of the ones
		-- currently on offer that is. All-Clear is the moment that count reaches the
		-- total (CONTEXT.md), which is not the same as walking off the end of the list.
		--
		-- Keyed by the Trial's DECLARED index, not by its position in `trials`: the
		-- available list is rebuilt every round and positions move under it, so a
		-- position-keyed record would credit the wrong Trial the moment a groove
		-- changed. completedCount is recounted against the available set with it.
		completed = {}, completedCount = 0, allclear = false,
		-- Bumped whenever the available list is rebuilt into a different one, which is
		-- what tells the pause menu's trials list to follow a change that did not move
		-- the player off the Trial they were on.
		availableGen = 0,
		-- The Success or All-Clear banner currently on screen, and its remaining ticks.
		banner = nil, bannerTimer = 0,
		-- Both stopwatches count up. totalTicks runs for the whole match, trialTicks
		-- restarts with every Trial.
		totalTicks = 0, trialTicks = 0,
	}
	local selected = start.p and start.p[1] and start.p[1].t_selected and start.p[1].t_selected[1]
	if selected ~= nil and selected.ref ~= nil then
		local char = main.t_selChars[selected.ref + 1]
		if type(char) == 'table' then
			m.char = char.name
			-- Kept whole for the Textbox's portrait, which needs the character's own
			-- char_ref, portraitscale and localcoord — see charPortrait. Held rather
			-- than copied out because it is the select screen's row and the module does
			-- not own it.
			m.charRow = char
			if type(char.trials) == 'table' then
				-- Unthinned until the round is live enough to read the character's
				-- variables. Nothing draws and nothing is written to the shared maps
				-- before then, and applyAvailability runs ahead of both.
				m.declared = char.trials
				m.trials = char.trials
				m.total = #char.trials
				m.def = char.trials.def
			end
		end
	end
	return m
end

-- One Player Preference, out of the module's own config.ini. These are the settings a
-- player changes rather than a screenpack author, which is why they live in config.ini
-- and not in system.def — see docs/adr/0001. The trials pause menu below writes them
-- back with saveIni; a config.ini edited by hand is read exactly the same way.
local function preference(name, default)
	local opts = trials.ini.Options or {}
	if type(opts.Trials) ~= 'table' then
		return default
	end
	-- Read out before it is tested, not through `a and b or c`: loadIni turns
	-- `ResetOnSuccess = false` into a Lua false, and that idiom collapses a false to
	-- its fallback — every boolean preference the player switches off would read back
	-- as on.
	local v = opts.Trials[name]
	if v == nil or v == '' then
		return default
	end
	return v
end

-- The Textbox Player Preference. A Textbox the player has hidden displaces nothing:
-- the window variant follows what is actually on screen, not what the Trial declares.
local function textboxesVisible()
	return tostring(preference('Textboxes', 'show')):lower() ~= 'hide'
end

-- Advancement: what a completed Trial does next. Auto-advance moves to the next Trial,
-- repeat plays the same one again so it can be drilled.
local function autoAdvances()
	return tostring(preference('Advancement', 'autoadvance')):lower() == 'autoadvance'
end

-- loadIni turns `true` and `false` into Lua booleans, but a config.ini a player has
-- hand-edited can hold anything, so the string spellings resolve too.
local function preferenceEnabled(name, default)
	local v = preference(name, default)
	if type(v) == 'boolean' then
		return v
	end
	local word = tostring(v):lower()
	return word ~= 'false' and word ~= 'no' and word ~= '0' and word ~= 'off'
end

-- The Layout Player Preference: which of the two prepared Step blocks is drawn. An
-- unrecognised word in a hand-edited config.ini falls back to the vertical one rather
-- than leaving the player with no Steps at all.
local function stepLayout()
	local word = tostring(preference('Layout', STEP_LAYOUTS[1])):lower()
	if trials.stepblocks ~= nil and trials.stepblocks[word] ~= nil then
		return word
	end
	return STEP_LAYOUTS[1]
end

-- Points the module at the block the Layout preference names.
--
-- Both blocks were built at load, so this is the whole of switching Layout: the new
-- block's elements already carry their font, origin, scale and localcoord, and only the
-- window has to be caught up — it is the one thing that changes after construction,
-- because it switches with the Trial's Textbox. Catching it up here rather than waiting
-- for the next Trial is what makes the switch immediate.
local function applyStepLayout()
	local block = trials.stepblocks ~= nil and trials.stepblocks[stepLayout()] or nil
	if block == nil then
		return
	end
	trials.stepblock = block
	-- What is on screen, not what the match has moved on to: the Steps drawn across a
	-- Success are the finished Trial's, and so is the window they clip to (syncDisplay).
	local m = trials.match
	applyStepWindow(block, m ~= nil and m.shownTextbox == true)
end

if trials.enabled then
	applyStepLayout()
end

-- Forgets whatever progress has been made through the current Trial and starts it over
-- from its first Step.
local function resetProgress(m)
	m.step = 1
	m.part = 1
	m.partHits = 0
	m.partCombo = 0
	m.combo = 0
	m.grace = 0
end

-- Catches the screen up with the Trial the match is on.
--
-- The two are not always the same, on purpose. Finishing a Trial moves the match onto
-- the next one on the frame it is finished — the Dummy, the positions and the verifier
-- all have to follow it — but the player is still reading SUCCESS over the Steps they
-- have just completed. So the display lags, and catches up when the pair is placed:
-- after the banner has gone, and behind the fade where there is one, so the Steps change
-- while the screen is dark rather than in front of the player.
local function syncDisplay(m)
	m.shownSteps = m.steps
	m.shownCurrent = m.current
	m.shownTextbox = m.textbox
	m.shownComplete = false
	-- The held progress goes with the held Trial: whatever was frozen on screen is
	-- caught up here, in the one place the display catches up.
	m.shownStep = nil
	if trials.stepblock ~= nil then
		applyStepWindow(trials.stepblock, m.textbox)
	end
	-- The prose on screen, alongside the Steps on screen and for the same reason: across
	-- a Success the Textbox belongs to the Trial the player just finished, not to the one
	-- the match has moved on to.
	local trial = m.trials[m.shownCurrent]
	m.shownText = type(trial) == 'table' and strValue(trial.textbox, '') or ''
	-- The typed reveal is measured from a tick count textImgReset zeroes
	-- (src/font.go:1456), so this is where it starts over: a new Trial types its own
	-- prose out from the beginning rather than inheriting how far the last one got.
	-- Reset empties a Lua-made sprite's text (see buildBanner), so the words go back on
	-- after it.
	setProse(trials.textbox, m.shownText)
end

-- Whether the Trial at `index` shows a Textbox: it has to carry one, and the player has
-- to want to see it. Read here rather than at draw time, because it is what decides
-- which window variant the Step block clips to.
local function trialTextbox(m, index)
	local trial = m.trials[index]
	return type(trial) == 'table' and trial.textbox ~= nil and trial.textbox ~= ''
		and textboxesVisible()
end

-- Moves the match onto one Trial and resolves everything that depends on which Trial
-- it is: the Steps to draw, whether a Textbox pushes the Step block into its
-- with-Textbox window, and the progress and per-Trial timer, both of which start over.
-- `defer` holds the display on whatever is already there, so the new Trial arrives with
-- the fade rather than in front of it. See jumpToTrial.
local function selectTrial(index, defer)
	local m = trials.match
	m.current = index
	local trial = m.trials[index]
	m.steps = type(trial) == 'table' and trial.steps or {}
	-- The Anims this Trial's Glyphs draw with, in both Layouts. Here rather than at
	-- draw time so that nothing is constructed on the per-frame path, and so that
	-- switching Layout mid-match draws the Glyphs immediately.
	prepareGlyphs(m.steps)
	m.textbox = trialTextbox(m, index)
	resetProgress(m)
	m.trialTicks = 0
	-- Nothing on screen changes yet while a banner is up, or when the caller is holding
	-- the display back: syncDisplay runs when the pair is placed, which is behind the
	-- fade. Selecting a Trial with nothing in the way — the start of a match — shows it
	-- at once.
	if m.banner == nil and not defer then
		syncDisplay(m)
	end
end

--;===========================================================
--; PAUSE MENU
--;===========================================================
-- Pausing a Trials match opens the [Trials Pause Menu] the module ships in +system.def,
-- and shipping that section is the whole of the registration: the engine's motif parser
-- turns any section matching ^(?i).*pause.*menu$ into a pause menu (motif.go:1335), and
-- menu.f_init resolves which one to open from gameMode() (menu.lua:558). There is no
-- menu loop in this module and there should not be one.
--
-- What the module contributes is the behaviour behind its own items, through the three
-- tables the engine keys by itemname: menu.t_valuename holds the values a setting cycles
-- through, menu.t_vardisplay renders the current one beside the item, and menu.t_itemname
-- runs on every frame its item is active. External modules are required (main.lua:3996)
-- before menu.f_start() generates the menus (main.lua:4027), so everything registered
-- here is in place by the time the menu is built.

-- The Player Preferences that have a menu item.
--
--   item     the itemname, both in +system.def and in every engine table below
--   key      the [Options] Trials.<key> it persists to in config.ini
--   values   what it cycles through, in cycle order. Each is also the word written to
--            config.ini and the suffix of its menu.valuename.<item>_<value>. The first
--            is the default, and matches the default the readers above assume.
--   boolean  persisted as a Lua boolean rather than as its word, because
--            preferenceEnabled is what reads it back and `false` is that reader's own
--            spelling of off
--
--   changed  what to run once the new value has been persisted, for a preference the
--            match already running cannot pick up on its own
local MENU_PREFERENCES = {
	{item = 'trialadvancement',    key = 'Advancement',    values = {'autoadvance', 'repeat'}},
	{item = 'trialresetonsuccess', key = 'ResetOnSuccess', values = {'enabled', 'disabled'}, boolean = true},
	{item = 'trialslayout',        key = 'Layout',         values = {'vertical', 'horizontal'}},
	{item = 'trialstextboxes',     key = 'Textboxes',      values = {'show', 'hide'}},
}

-- The same four, keyed by itemname, for the lookups that start from one.
local MENU_PREFERENCE = {}
for _, pref in ipairs(MENU_PREFERENCES) do
	MENU_PREFERENCE[pref.item] = pref
end

-- The trials list is one submenu whose items are per-character, so it is filled in when
-- a match resolves rather than authored. Every entry carries the same itemname — which
-- is what the handler is registered under — and says which Trial it stands for on the
-- item itself.
local TRIALS_LIST_ITEM = 'trialslist'
local TRIALS_ENTRY_ITEM = 'trialsentry'

-- Which value of a preference is currently set, as an index into its `values`. The
-- engine's value items are index-based: menu[itemname] is the index, and everything
-- else follows from it.
local function preferenceIndex(pref)
	if pref.boolean then
		return preferenceEnabled(pref.key, true) and 1 or 2
	end
	local current = tostring(preference(pref.key, pref.values[1])):lower()
	for i, value in ipairs(pref.values) do
		if value == current then
			return i
		end
	end
	return 1
end

-- Points every value item at what config.ini currently says. Run at load, and again per
-- match for the reason syncPauseMenu gives.
local function syncPreferenceIndices()
	for _, pref in ipairs(MENU_PREFERENCES) do
		menu[pref.item] = preferenceIndex(pref)
	end
end

-- Persists one Player Preference to the module's config.ini.
--
-- saveIni rewrites the whole file from the table it was read into, so [Common] and
-- [Files] keep their values — but not the comments around them. config.ini as shipped
-- says so, because the first preference a player changes is what strips them.
local function writePreference(key, value)
	if type(trials.ini.Options) ~= 'table' then
		trials.ini.Options = {}
	end
	if type(trials.ini.Options.Trials) ~= 'table' then
		trials.ini.Options.Trials = {}
	end
	trials.ini.Options.Trials[key] = value
	-- Resolved here rather than held on the module, because saveIni writes the path it
	-- is given and does not search for one the way loadIni does. The authored path is
	-- the fallback: searchFile answers '' for a file it cannot find, and writing the
	-- preference where it was read from is better than writing it to the root.
	local path = normalizePath(trials.configPath)
	if path == '' then
		path = trials.configPath
	end
	local ok, err = pcall(saveIni, trials.ini, path)
	if not ok then
		print('Trials: could not write ' .. path .. ' (' .. tostring(err) .. ').')
	end
end

-- Catches the match already running up with a changed Textbox preference.
--
-- Nothing else needs one: Advancement and Reset on Success are read when a Trial is
-- completed, and Layout when the Steps are laid out. Whether a Trial's Textbox displaces
-- the Step block, though, is resolved when the Trial is selected — so without this the
-- setting would only take hold on the next Trial.
local function refreshTextbox()
	local m = trials.match
	if m == nil then
		return
	end
	m.textbox = trialTextbox(m, m.current)
	-- Only a display that is already showing this Trial follows immediately. One still
	-- lagging behind a Success catches up through syncDisplay, with the Trial it is
	-- lagging towards.
	if m.shownCurrent == m.current then
		local appearing = m.textbox and not m.shownTextbox
		m.shownTextbox = m.textbox
		-- A Textbox the player has just switched back on types its prose out from the
		-- beginning, rather than resuming wherever the reveal had got to before it was
		-- hidden. It has only now appeared; starting mid-sentence would read as a bug.
		if appearing then
			setProse(trials.textbox, m.shownText or '')
		end
		if trials.stepblock ~= nil then
			applyStepWindow(trials.stepblock, m.textbox)
		end
	end
end

-- Advancement and Reset on Success are read where they are used, so changing one needs
-- nothing beyond persisting it. The other two are read when a Trial is selected rather
-- than per frame, and so have to be caught up with by hand — which lives on the
-- descriptor rather than as a name test inside the shared handler.
MENU_PREFERENCE.trialstextboxes.changed = refreshTextbox
MENU_PREFERENCE.trialslayout.changed = applyStepLayout

-- The resolved [Trials Pause Menu], or nil on a build where the section never reached
-- the motif at all. One walk, because three readers below want the same one.
local function pauseMenuSection()
	local sec = motif.pause_menu ~= nil and motif.pause_menu.trials_pause_menu or nil
	if sec == nil or type(sec.menu) ~= 'table' then
		return nil
	end
	return sec
end

-- The words one value of a preference is shown as.
--
-- Read off the resolved motif, so a screenpack that spells them differently in its own
-- [Trials Pause Menu] wins by the engine's ordinary first-wins merge without this
-- knowing about it. The value itself stands in only for a build where the section never
-- reached the motif at all.
local function valuename(item, value)
	local sec = pauseMenuSection()
	local words = sec ~= nil and sec.menu.valuename or nil
	local v = type(words) == 'table' and words[item .. '_' .. value] or nil
	if v == nil or v == '' then
		return value
	end
	return v
end

-- Moves the match to one Trial from the menu.
--
-- selectTrial resolves everything that follows the Trial: the Steps, the Textbox window,
-- the progress and the per-Trial clock. The guard is why this exists rather than being
-- called directly — a list built for one character can outlive it across a Character
-- Change, and selectTrial does not check the index it is handed.
--
-- The placement is asked for rather than left to applySetup's own trigger, which is the
-- Trial having changed: picking the Trial already running is a restart, and a restart
-- that left the pair mid-stage would be the one entry in the list that did not start its
-- Trial where the author put it. Everything downstream is #49's — the banner wait, the
-- settled-Dummy wait, the fade, the camera.
local function jumpToTrial(index)
	local m = trials.match
	if m == nil or type(m.trials[index]) ~= 'table' then
		return
	end
	-- The Trial the player picked arrives with the fade, not in front of it.
	--
	-- The engine's pause menu fades back IN to the match before it unpauses
	-- (motif.go:3401), so a display that changed on the key press would show the new
	-- Trial's Steps standing over the old Trial's positions for the whole of that
	-- fade-in — the new Steps, the old pair, the old corner. Held instead, the screen
	-- comes back on the Trial the player was already looking at, darkens, and the new
	-- one arrives with the pair already placed for it.
	--
	-- The progress is held with it. resetProgress runs below whatever the display is
	-- doing, so without this the Trial being held on screen would visibly rewind to its
	-- first Step while the screen was still lit.
	m.shownStep = m.step
	selectTrial(index, true)
	m.reposRequest = true
end

-- Leaves the pause menu, the way its own Continue does: back to the root menu, then the
-- delay the engine gives a closing pause menu before the match resumes.
local function closePauseMenu()
	menu.currentMenu[1] = menu.currentMenu[2]
	menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
	return false
end

-- The submenu the trials list lives in, once menu.f_start has generated it.
--
-- Searched rather than looked up at the top level: where the list sits is the
-- screenpack's to decide, and the pre-refactor menu the legacy fold below reads put it
-- inside a submenu of its own.
local function trialsListMenu()
	local stack = {type(menu) == 'table' and menu.trials or nil}
	while #stack > 0 do
		local node = table.remove(stack)
		if type(node) == 'table' and type(node.submenu) == 'table' then
			local sub = node.submenu[TRIALS_LIST_ITEM]
			if type(sub) == 'table' and type(sub.items) == 'table' then
				return sub
			end
			for _, child in pairs(node.submenu) do
				stack[#stack + 1] = child
			end
		end
	end
	return nil
end

-- The items [Trials Pause Menu] declared under the list itself — its Back. Captured the
-- first time the list is filled in, because filling it in is what replaces them.
local trialsListTail = nil

-- Fills the trials list in with the Trials the selected character ships.
local function buildTrialsList()
	local sub = trialsListMenu()
	if sub == nil then
		return
	end
	if trialsListTail == nil then
		trialsListTail = sub.items
	end
	local m = trials.match
	local items = {}
	for i, trial in ipairs(m ~= nil and m.trials or {}) do
		items[i] = {
			itemname = TRIALS_ENTRY_ITEM,
			-- What a screenpack keys a per-item background off. Every entry shares one,
			-- because a screenpack cannot name a Trial it has never seen.
			paramname = TRIALS_ENTRY_ITEM,
			displayname = trial.title,
			vardisplay = '',
			-- The Trial the match is on draws in the menu's own selected style, which is
			-- what that style is for.
			selected = i == m.current,
			trial = i,
		}
	end
	-- Underneath, so a character shipping no Trials still leaves something to sit on:
	-- the engine indexes the active item unguarded, and an empty menu is a crash.
	for _, item in ipairs(trialsListTail) do
		items[#items + 1] = item
	end
	-- The tail is the screenpack's, so it can be missing — a folded legacy [Trials Info]
	-- that declared its list with no Back under it leaves nothing there. One is made
	-- rather than left to crash, worded from whatever the section does say.
	if #items == 0 then
		local sec = pauseMenuSection()
		local words = sec ~= nil and sec.menu.itemname or {}
		items[1] = {
			itemname = 'back',
			paramname = 'back',
			displayname = words[TRIALS_LIST_ITEM .. '_back'] or words.back or 'Back',
			vardisplay = '',
			selected = false,
		}
	end
	sub.items = items
	sub.item = 1
	sub.cursorPosY = 1
	sub.moveTxt = 0
end

-- The match, the Trial and the availability generation the menu was last caught up
-- with.
local menuMatch, menuTrial, menuGen = nil, nil, nil

-- Catches the pause menu up with the match that is running, and with the Trial it is on.
--
-- Neither can be settled at boot. The trials list is per-character and the menu is
-- generated once for the whole run. And the preference indices, though read out of
-- config.ini at load, are wiped by menu.f_trainingReset(), which sets every value item
-- in menu.t_valuename back to 1 — ours included — before a training match
-- (start.lua:1739). A Trials match entered after one would otherwise show the first
-- value of each setting rather than the setting.
local function syncPauseMenu()
	local m = trials.match
	if m == nil or type(menu) ~= 'table' then
		return
	end
	if menuMatch ~= m then
		menuMatch, menuTrial, menuGen = m, nil, nil
		syncPreferenceIndices()
		for _, item in ipairs(menu.t_vardisplayPointers or {}) do
			if MENU_PREFERENCE[item.itemname] ~= nil then
				item.vardisplay = menu.f_vardisplay(item.itemname)
			end
		end
	end
	-- The generation with the Trial: a round that thinned the list differently changed
	-- what the list should show even where the player did not move off their Trial
	-- (#52).
	if menuTrial ~= m.current or menuGen ~= m.availableGen then
		menuTrial, menuGen = m.current, m.availableGen
		buildTrialsList()
	end
end

-- LEGACY [Trials Info] --------------------------------------------------------------
-- The section rename is the one genuine breaking change in this refactor. The engine
-- matches a pause menu with ^(?i).*pause.*menu$ (motif.go:1335): [Trials Pause Menu]
-- matches and [Trials Info] does not, so a screenpack that customised the pre-refactor
-- menu would silently get the module's own instead of its own.
--
-- So a legacy section is folded into the pause menu here, and the promise made in #45
-- holds literally for one release. The rename is documented in README.md; this fold
-- goes away in a later one.
--
-- A screenpack carrying both sections has migrated and left the old one behind, so its
-- [Trials Pause Menu] wins outright and nothing is folded.
--
-- Written into the Lua `motif` table rather than through modifyMotif, which is what the
-- ticket suggested. modifyMotif reaches sys.motif on the Go side (script.go:5182), and
-- the Lua table menu.f_start actually reads is a snapshot taken once by loadMotif()
-- (main.lua:1179) and never refreshed from it — so a fold through modifyMotif would
-- change nothing the menu is built from.
trials.legacyPauseMenu = false

-- Values the pre-refactor section spelled differently from the module, legacy name to
-- current one. Reset on Success is the only case: its values are enabled and disabled,
-- and [Trials Info] wrote yes and no.
local LEGACY_VALUENAMES = {
	trialresetonsuccess_yes = 'trialresetonsuccess_enabled',
	trialresetonsuccess_no = 'trialresetonsuccess_disabled',
}

-- loadIni's keepMeta tables carry the authored key order in __order and, where a key is
-- both a scalar and a parent, its own scalar in __value — which is exactly the shape a
-- legacy `menu.itemname.menutrials` sitting above `menu.itemname.menutrials.trialslist`
-- takes. Flattened into the engine's own spelling, where the separator is an underscore
-- rather than a dot. Both halves of a legacy section are the same shape, so this reads
-- menu.itemname and menu.valuename alike.
local function flattenMenuKeys(src, prefix, out)
	if type(src) ~= 'table' then
		return out
	end
	for _, key in ipairs(src.__order or {}) do
		local v = src[key]
		local path = prefix == '' and key or (prefix .. '_' .. key)
		if type(v) == 'table' and not isValueList(v) then
			if v.__value ~= nil then
				out[#out + 1] = {key = path, value = strValue(v.__value, '')}
			end
			flattenMenuKeys(v, path, out)
		elseif v ~= nil then
			out[#out + 1] = {key = path, value = strValue(v, '')}
		end
	end
	return out
end

local function foldLegacyTrialsInfo()
	local legacy = screenpackIni.trials_info
	if type(legacy) ~= 'table' or type(legacy.menu) ~= 'table' then
		return
	end
	if type(screenpackIni.trials_pause_menu) == 'table' then
		return
	end
	local sec = pauseMenuSection()
	if sec == nil then
		return
	end

	-- Values merge: a legacy section that renames one setting's words should not blank
	-- the three it says nothing about. A legacy spelling is written under the module's
	-- key as well as its own, or the module's default would out-rank the screenpack's
	-- rename — which is backwards, and is what the fold exists to prevent.
	local folded = false
	if type(legacy.menu.valuename) == 'table' then
		if type(sec.menu.valuename) ~= 'table' then
			sec.menu.valuename = {}
		end
		for _, entry in ipairs(flattenMenuKeys(legacy.menu.valuename, '', {})) do
			sec.menu.valuename[entry.key] = entry.value
			if LEGACY_VALUENAMES[entry.key] ~= nil then
				sec.menu.valuename[LEGACY_VALUENAMES[entry.key]] = entry.value
			end
			folded = true
		end
	end

	-- Items replace: a legacy section is a whole menu, not an addition to one, and
	-- merging would show every item the two have in common twice. A section that renamed
	-- only the words falls through with the module's own menu intact, which is what it
	-- asked for.
	local items = flattenMenuKeys(legacy.menu.itemname, '', {})
	if #items > 0 then
		local itemname, order, depth, rank = {}, {}, {}, {}
		for i, entry in ipairs(items) do
			itemname[entry.key] = entry.value
			order[#order + 1] = entry.key
			depth[entry.key] = select(2, entry.key:gsub('_', ''))
			rank[entry.key] = i
		end
		-- The engine orders a menu's itemnames by depth, parents ahead of their children
		-- (script.go:4779), and menu.f_start depends on it: a child reached before its
		-- parent has no submenu to be inserted into. Authored order decides the rest.
		table.sort(order, function(a, b)
			if depth[a] ~= depth[b] then
				return depth[a] < depth[b]
			end
			return rank[a] < rank[b]
		end)
		sec.menu.itemname = itemname
		sec.menu.itemname_order = order
		folded = true
	end

	if folded then
		trials.legacyPauseMenu = true
		print('Trials: the screenpack still defines [Trials Info]. It has been read as ' ..
			'[Trials Pause Menu], which is the name to rename it to.')
	end
end

if trials.enabled then
	foldLegacyTrialsInfo()
end

-- Registration. Everything above is inert until these three tables carry it.
if trials.enabled and type(menu) == 'table' then
	for _, pref in ipairs(MENU_PREFERENCES) do
		local values = {}
		for i, value in ipairs(pref.values) do
			values[i] = {itemname = value, displayname = valuename(pref.item, value)}
		end
		menu.t_valuename[pref.item] = values
		menu.t_vardisplay[pref.item] = function()
			return menu.t_valuename[pref.item][menu[pref.item] or 1].displayname
		end
		menu.t_itemname[pref.item] = function(t, item, cursorPosY, moveTxt, sec)
			local changed, value = menu.f_valueChanged(t.items[item], sec)
			if changed then
				-- Spelled out rather than as `pref.boolean and ... or value`: the whole
				-- point of a boolean preference is that it can be false, and that idiom
				-- collapses a false to its fallback — every setting switched off would
				-- persist as the word for off and read back as on.
				local stored = value
				if pref.boolean then
					stored = value == pref.values[1]
				end
				writePreference(pref.key, stored)
				if pref.changed ~= nil then
					pref.changed()
				end
			end
			return true
		end
	end

	-- One entry of the trials list. Deliberately NOT registered under TRIALS_LIST_ITEM:
	-- menu.f_start only generates a submenu for an itemname menu.t_itemname has no
	-- handler for (menu.lua:456), so registering the list itself would leave it with
	-- nowhere to put the Trials.
	menu.t_itemname[TRIALS_ENTRY_ITEM] = function(t, item, cursorPosY, moveTxt, sec)
		if getInput(-1, sec.menu.done.key) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			jumpToTrial(t.items[item].trial)
			return closePauseMenu()
		end
		return true
	end

	-- Not in the module's own [Trials Pause Menu] — the trials list covers both — but
	-- the pre-refactor module shipped them, so a screenpack still listing them gets
	-- working items rather than an empty submenu the engine would index into.
	local function step(offset)
		return function(t, item, cursorPosY, moveTxt, sec)
			local m = trials.match
			if getInput(-1, sec.menu.done.key) and m ~= nil and m.total > 0 then
				sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
				jumpToTrial((m.current - 1 + offset) % m.total + 1)
				return closePauseMenu()
			end
			return true
		end
	end
	menu.t_itemname['nexttrial'] = step(1)
	menu.t_itemname['previoustrial'] = step(-1)

	-- After the value lists, since an index is an index into one. menu.f_start reads the
	-- values back through menu.t_vardisplay when it builds the items.
	syncPreferenceIndices()

	-- The engine clears every item's `selected` flag whenever a pause menu is reset,
	-- which is every time one closes (menu.f_reset, menu.lua:662), so which Trial the
	-- match is on is marked on the frames the list is actually drawn rather than once
	-- when it is filled in. menu.menu.loop is the hook menu.f_createMenu runs, and it
	-- runs for every pause menu in the game, so the mode is checked before anything is
	-- touched.
	hook.add('menu.menu.loop', 'trials', function()
		local sub = gameMode('trials') and trialsListMenu() or nil
		local m = trials.match
		if sub == nil or m == nil then
			return
		end
		for _, item in ipairs(sub.items) do
			item.selected = item.trial == m.current
		end
	end)
end

-- Writes the current Trial's Dummy settings to the maps trials.zss reads.
--
-- This is the whole of the module's dummy logic: the behaviour itself lives in ZSS,
-- and Lua only says which of it to run (docs/adr/0002). A Trial with nothing to say
-- still gets written, because the maps are shared state and the value sitting in them
-- is the previous Trial's until something replaces it.
--
-- Not called from selectTrial, because trials.zss clears these maps for the whole of
-- roundState 0 — anything written before the round starts is wiped. The loop applies
-- them on the first frame past that reset instead, and marks them stale when the round
-- state falls back to 0, so a restarted round writes them again.
local function applyDummy()
	local m = trials.match
	if m == nil then
		return
	end
	if roundState() < 1 then
		m.dummyTrial = nil
		return
	end
	if m.dummyTrial == m.current then
		return
	end
	-- A character with no Trial Definition reaches here too, and gets the same
	-- stand-still Dummy a Trial that names nothing would.
	local trial = m.trials[m.current]
	local d = type(trial) == 'table' and trial.dummy or defaultDummy
	-- player() moves the redirect every trigger reads through, exactly as the engine's
	-- own dummy handlers do (external/script/menu.lua:143). Without it mapSet would
	-- write onto whichever character the engine last left it pointing at.
	if not player(2) then
		return
	end
	for _, spec in ipairs(dummyVocabulary) do
		mapSet(spec.map, d[spec.field])
	end
	-- Put the redirect back on the Trials player, so nothing downstream inherits a
	-- redirect it did not ask for.
	player(1)
	-- dummyTrial is the Trial whose settings are in the maps, and dummy is the
	-- settings themselves. Both are recorded on the match rather than left implicit,
	-- and the artifact is written again here: a Trial's settings are resolved at load
	-- and written many seconds later, so a dump taken before this point shows only
	-- what the Trial Definition said, never that anything reached the Dummy.
	m.dummyTrial = m.current
	m.dummy = d
	trials.f_dumpState()
end

-- Puts one character on the life a Trial asked for, now rather than at the next
-- recovery tick.
--
-- 0 is the map's word for lifeMax, and means the same here. Red life goes with life
-- because trials.zss pins both from the same map: setting one and leaving the other
-- shows a full red-damage bar over the new total until the next recovery tick catches
-- up, which is the very lag this write exists to avoid.
local function setLifeNow(value)
	local v = value > 0 and value or lifeMax()
	setLife(v)
	setRedLife(v)
end

-- Where the two characters stand, in the coordinate space trials.zss will read them in.
--
-- Two conversions, and skipping either puts everybody in the wrong place:
--
--  * Stage values come out of the Lua stageVar raw, in the stage's own localcoord. (The
--    ZSS trigger of the same name converts them; this binding does not.) Dividing by
--    the stage's localcoord over 320 puts them in the 320-wide space the gap constants
--    below are written in, and the whole geometry is reasoned in from there.
--  * The engine then reads what is written here in the *Dummy's* space, because
--    TrialsReposition runs in her state: PosSet lands a value at `camera + V·localscl`
--    and Camera at `V·localscl`, where localscl is the game width over the character's
--    localcoord. A character authored at 640 therefore needs every number twice as
--    large to reach the same place, which is what charCoordX is for.
--
-- The corner itself is the screen edge, not the camera bound: half the stage's width
-- less its screen bound is where a character standing in the corner actually is. The
-- camera bound is where the camera goes, which is a different number.
local function positionsFor(pos, charCoordX)
	local localcoordX = stageVar('stageinfo.localcoord.x')
	local scale = localcoordX / 320
	if scale <= 0 then
		scale = 1
	end
	-- The stage's own start positions, which is where a Trial naming no position
	-- leaves them.
	local w = {
		playerx = stageVar('playerinfo.p1startx') / scale,
		playery = stageVar('playerinfo.p1starty') / scale,
		dummyx = stageVar('playerinfo.p2startx') / scale,
		dummyy = stageVar('playerinfo.p2starty') / scale,
		camerax = 0,
	}
	if pos.corner ~= '' then
		local cornerx, otherx
		if pos.corner == 'left' then
			w.camerax = stageVar('camera.boundleft') / scale
			cornerx = -(localcoordX / 2 - stageVar('bound.screenleft')) / scale
			otherx = cornerx + pos.gap
		else
			w.camerax = stageVar('camera.boundright') / scale
			cornerx = (localcoordX / 2 - stageVar('bound.screenright')) / scale
			otherx = cornerx - pos.gap
		end
		if pos.cornered == 'dummy' then
			w.dummyx, w.playerx = cornerx, otherx
		else
			w.playerx, w.dummyx = cornerx, otherx
		end
	elseif pos.spaced then
		-- No corner, so the gap is shared either side of centre stage rather than
		-- measured out from a wall.
		w.playerx = -pos.gap / 2
		w.dummyx = pos.gap / 2
	end
	-- The camera stays where the positions are measured from, and is not moved onto the
	-- pair's midpoint to "centre" it. A corner position is spelled as half a screen from
	-- the camera, so it only means the stage's wall while the camera is on the stage's
	-- bound — and the bound is the furthest the engine will let the camera go. Shift the
	-- camera past it to centre the pair and the corner stops being the corner: what the
	-- engine accepts is clamped back, and the pair lands short of the wall, toward centre
	-- stage. Framing is the fighting view's job, and it gets the camera back a frame
	-- later with the characters already where they belong.
	--
	-- Out of the 320-wide space and into the Dummy's, in one factor: the stage values
	-- divided into it above and the gap constants written in it are both carried.
	local coordScale = (charCoordX or 320) / 320
	if coordScale <= 0 then
		coordScale = 1
	end
	for k, v in pairs(w) do
		w[k] = v * coordScale
	end
	return w
end

-- Writes the current Trial's positions and life totals to the maps trials.zss reads.
--
-- Same shape and same timing as applyDummy, and for the same reason: trials.zss clears
-- _iksys_trialsReposition for the whole of roundState 0, so the write happens on the
-- first frame past it and again whenever the Trial changes or the round restarts.
--
-- The pre-refactor module drove this from its fade routine, which meant a Trial was
-- placed when the *previous* one was cleared. It happens at Trial start here.
-- One side's life, on whichever character the redirect currently sits on.
--
-- Life is the exception among the setup maps: trials.zss reads it in each character's
-- own life recovery block, so one map name carries both totals and each side gets its
-- own. 0 is the map's word for lifeMax.
--
-- Set as well as pinned, because the map only takes effect on the next recovery tick —
-- up to a second later, with the Trial already begun at the wrong life.
--
-- Split out because a Trial taken on without the pair moving still starts with the life
-- its author asked for: Reset on Success governs where the two stand, not what they
-- stand there with.
local function writeLifeSide(value)
	mapSet('_iksys_trialsSetLife', value)
	setLifeNow(value)
end

local function writeSetup(m)
	local trial = m.trials[m.current]
	local pos = type(trial) == 'table' and trial.positions or defaultPositions
	local life = type(trial) == 'table' and trial.life or defaultLife

	-- Every reposition map on the Dummy. TrialsReposition() is called from inside
	-- trials.zss's `teamSide = 2 && !isHelper` block and redirects out of there, so it
	-- reads P2's map array and nobody else's — and, being run by her, reads every
	-- value in her coordinate space, which is why the redirect comes first.
	if not player(2) then
		return
	end
	local w = positionsFor(pos, localCoordX())
	mapSet('_iksys_trialsCameraPosX', w.camerax)
	mapSet('_iksys_trialsPlayerPosX', w.playerx)
	mapSet('_iksys_trialsPlayerPosY', w.playery)
	mapSet('_iksys_trialsDummyPosX', w.dummyx)
	mapSet('_iksys_trialsDummyPosY', w.dummyy)
	writeLifeSide(life.dummy)
	mapSet('_iksys_trialsReposition', 1)
	-- Back on the Trials player, which is both where the player's own life is written
	-- and where everything downstream expects the redirect to be. Unconditional, the
	-- way applyDummy's is: leaving the redirect on the Dummy would hand every
	-- redirectable trigger the loop reaches after this the wrong character.
	player(1)
	writeLifeSide(life.player)

	-- What actually reached the two characters, recorded for the same reason the Dummy
	-- settings are: a Trial's positions are resolved at load and written many seconds
	-- later, and a dump taken before this point cannot tell the two apart.
	m.setupTrial = m.current
	m.reposRequest = false
	m.adoptTrial = nil
	-- The Steps and the counter change here, with the pair: after the banner, and behind
	-- the fade where there is one.
	syncDisplay(m)
	-- TrialsReposition leaves the camera on `view: free` at the position written above,
	-- which is what frames the pair while they are placed. Handing it back to the
	-- fighting view is a separate write, deliberately not in this one: done in the same
	-- tick, the fighting view recomputes from where the characters were *before* the
	-- PosSet and the framing is thrown away on the frame it was made for.
	m.cameraPending = true
	m.setup = {
		trial = m.current,
		corner = pos.corner,
		cornered = pos.cornered,
		gap = pos.gap,
		playerx = w.playerx,
		playery = w.playery,
		dummyx = w.dummyx,
		dummyy = w.dummyy,
		camerax = w.camerax,
		playerlife = life.player,
		dummylife = life.dummy,
		placed = true,
	}
	trials.f_dumpState()
end

-- Takes the Trial the match has moved on to WITHOUT placing the pair.
--
-- This is what Reset on Success off means. A Success does not move anybody: the next
-- Trial — or the same one again — begins from wherever the combo ended, with no fade
-- between the two, so a run reads as one continuous stretch of play.
--
-- Everything a placement does that is not a placement still happens: the life the Trial
-- asked for, and the Steps and counter catching up with the Trial the match is on. The
-- two things that only make sense around a move do not — the camera is left following
-- the pair it is already following, and there is no wait for a settling Dummy, because
-- she is not being taken out of whatever she is in.
local function adoptSetup(m)
	local trial = m.trials[m.current]
	local pos = type(trial) == 'table' and trial.positions or defaultPositions
	local life = type(trial) == 'table' and trial.life or defaultLife
	if not player(2) then
		return
	end
	-- Resolved in the Dummy's coordinate space while the redirect is still on her, the
	-- way writeSetup resolves it, so the record below reads the same whether the pair
	-- was placed or not.
	local w = positionsFor(pos, localCoordX())
	writeLifeSide(life.dummy)
	player(1)
	writeLifeSide(life.player)
	m.setupTrial = m.current
	m.adoptTrial = nil
	m.reposRequest = false
	m.settleWait = 0
	syncDisplay(m)
	-- Recorded like a placement, with `placed` saying it was not one. The positions are
	-- the ones this Trial resolved to and deliberately did not use: a dump that showed
	-- nothing here could not tell a Trial taken on in place from one whose placement had
	-- simply not run yet.
	m.setup = {
		trial = m.current,
		corner = pos.corner,
		cornered = pos.cornered,
		gap = pos.gap,
		playerx = w.playerx,
		playery = w.playery,
		dummyx = w.dummyx,
		dummyy = w.dummyy,
		camerax = w.camerax,
		playerlife = life.player,
		dummylife = life.dummy,
		placed = false,
	}
	trials.f_dumpState()
end

-- Hands the camera back to its ordinary fighting view, one frame after the pair was
-- placed at the earliest.
--
-- Until this runs the camera is exactly between the two characters and going nowhere,
-- which is the framing the reposition was for. Afterwards the engine follows them
-- again, from that position rather than from wherever the camera had drifted to.
local function flushCameraReset(m)
	if not m.cameraPending then
		return
	end
	if not player(2) then
		return
	end
	mapSet('_iksys_trialsCameraReset', 1)
	player(1)
	m.cameraPending = false
end

-- How long a Dummy who will not settle is waited for before the pair is placed anyway.
-- Long enough for a knockdown and a getup, short enough that a Dummy stuck in a state
-- that never hands control back cannot leave a Trial unplaced for the rest of the round.
local SETTLE_LIMIT = 180

-- Whether the Dummy is somewhere it is reasonable to move her from.
--
-- The Success banner runs on a timer and the knockdown that finished the Trial does
-- not, so the two routinely end out of step: the banner clears while she is still in
-- hitstun or on the floor, and repositioning then snatches her out of the combo that
-- just landed. Waiting for control means the pair is always placed standing.
--
-- Control rather than a state number, because the state a settled Dummy sits in is
-- whatever the Trial told her to do — a crouching Dummy is never in state 0 and a
-- jumping one only in passing.
local function dummySettled()
	if not player(2) then
		-- No Dummy to wait for.
		return true
	end
	local settled = alive() and moveType() ~= 'H' and ctrl()
	player(1)
	return settled
end

-- Notices the player asking to be put back where the Trial wants them.
--
-- The combination is *held*, which is what makes ordinary game inputs usable for it:
-- any one of them is something a player presses constantly, and all of them at once is
-- not. But holding it has to ask once rather than once a frame, or a player who keeps it
-- down for the length of the fade starts another reposition the moment the last one
-- lands. So the ask is the press, and it is latched until something acts on it — which
-- is also what stops it being lost while a hit Dummy settles.
local function readRepositionRequest(m)
	local r = trials.reposition
	local held = r ~= nil and r.enabled and #r.keys > 0
		and m.banner == nil and not paused() and player(1)
	if held then
		for _, key in ipairs(r.keys) do
			if inputTime(key) <= 0 then
				held = false
				break
			end
		end
	end
	if held and not m.reposHeld then
		m.reposRequest = true
	end
	m.reposHeld = held
end

-- Whether a reposition is worth fading for.
local function fadesReposition()
	return trials.reposition ~= nil
		and (trials.reposition.fadeoutTime > 0 or trials.reposition.fadeinTime > 0)
end

-- Places the current Trial's pair, and runs the fade that softens the move.
--
-- Three states, held on the match as `repos`:
--
--   nil    nothing running. A Trial change, or the player holding the reposition
--          combination, starts a cycle.
--   'out'  the screen is going dark and the write is waiting behind it, so the pair
--          moves while nobody can see them move.
--   'in'   they are placed, and the screen is coming back.
--
-- Same timing as applyDummy, and for the same reason: trials.zss clears the maps for
-- the whole of roundState 0, so nothing is written before the round is live and the
-- marker is dropped when the round state falls back, which places everything again on
-- a restart.
local function applySetup()
	local m = trials.match
	if m == nil then
		return
	end
	-- Common.Lua runs on every tick, pause menu open or not (system.go:2875), so without
	-- this a Trial picked out of the trials list would start its fade behind the menu the
	-- player picked it from — and wait on fadeActive() for the menu's own closing fade,
	-- which is the same one. Nothing moves while the match is paused; the frame it
	-- resumes is the frame this picks up.
	if paused() then
		return
	end
	if roundState() < 1 then
		-- The record goes with the marker. It says what is in the maps, and trials.zss
		-- has just cleared them. A half-run fade goes too, rather than resuming into a
		-- round that has started over.
		m.setupTrial = nil
		m.setup = nil
		m.repos = nil
		m.cameraPending = false
		m.settleWait = 0
		m.reposRequest = false
		m.reposHeld = false
		m.adoptTrial = nil
		-- A held display goes with the half-run fade that was going to release it. The
		-- round is starting over and the Trial it starts on is the one to draw, so a
		-- Trial frozen on screen waiting for a fade that will now never finish would
		-- otherwise be what the new round came back to.
		m.shownStep = nil
		return
	end

	if m.repos == 'out' then
		if not fadeActive() then
			-- The wait for a settled Dummy happens HERE, behind the fade, rather than in
			-- front of it. She is regularly still in the hitstun of the combo that just
			-- ended, so waiting before the fade means waiting on a LIT screen — up to
			-- SETTLE_LIMIT frames of live match between the player asking for a Trial and
			-- anything appearing to happen.
			--
			-- Picking a Trial out of the pause menu made that worst, because the menu
			-- runs its own closing fade and then fades back IN to the match before
			-- unpausing (motif.go:3401, ME_ClosingOut -> ME_ClosingIn). The player saw
			-- the screen darken, brighten again on the Trial they had just left, sit
			-- there while the Dummy settled, and only then start the fade they asked for.
			-- Behind the fade the same wait is a screen that was already dark.
			if not dummySettled() and (m.settleWait or 0) < SETTLE_LIMIT then
				m.settleWait = (m.settleWait or 0) + 1
				return
			end
			m.settleWait = 0
			writeSetup(m)
			m.repos = 'in'
			if trials.reposition.fadeinTime > 0 then
				fadeInInit(trials.reposition.fadein)
			end
		end
		return
	elseif m.repos == 'in' then
		if not fadeActive() then
			m.repos = nil
			-- The camera has framed the pair for the whole of the fade. Following
			-- resumes now, with the screen already back.
			flushCameraReset(m)
			-- The pair has just been moved out from under whatever the player was
			-- doing, so the combo count is re-read for the same reason clearBanner
			-- re-reads it: what landed before the fade is not the first hit of what
			-- comes after it.
			if player(1) then
				m.combo = comboCount()
			end
		end
		return
	end

	-- A placement with no fade behind it hands the camera back on the frame after it,
	-- which is the earliest the fighting view can see where the characters actually are.
	flushCameraReset(m)

	-- Nothing starts under a banner. Finishing a Trial moves the match onto the next
	-- one on the frame it is finished, so without this the pair would be repositioned
	-- while the player is still reading SUCCESS — the fade would fire *on* the success
	-- rather than after it. The move waits for the banner to go, and the guard above
	-- picks it up on the next frame.
	if m.banner ~= nil then
		return
	end
	readRepositionRequest(m)
	-- Reset on Success off: the Trial the Success moved the match to is taken on where
	-- the pair already stands, and nothing fades. Ahead of the guard below, because a
	-- repeated Trial is the same Trial and would fall straight through it — leaving the
	-- Steps reading as completed under a banner that has already gone.
	--
	-- A reposition the player asked for out-ranks it. Holding the combination, or picking
	-- a Trial out of the list, is a request to be put back; the preference is about what
	-- a Success does on its own.
	if m.adoptTrial ~= nil and not m.reposRequest then
		adoptSetup(m)
		return
	end
	if m.setupTrial == m.current and not m.reposRequest then
		m.settleWait = 0
		return
	end
	-- Something wants the pair moved, and the fade starts NOW — on the frame the request
	-- is noticed, not once the Dummy has settled. Everything that has to wait waits in
	-- the dark, in the 'out' branch above.
	--
	-- The first placement of a round goes straight in: there is nothing on screen yet
	-- to fade away from, and the round's own fade already covers it.
	if m.setupTrial ~= nil and fadesReposition() then
		m.repos = 'out'
		if trials.reposition.fadeoutTime > 0 then
			fadeOutInit(trials.reposition.fadeout)
		end
		return
	end
	-- No fade to hide it behind — the first placement of a round, or a screenpack that
	-- set both fade times to 0 asking for an instant cut. The wait for a settled Dummy
	-- is all there is, so it happens here.
	if not dummySettled() and (m.settleWait or 0) < SETTLE_LIMIT then
		m.settleWait = (m.settleWait or 0) + 1
		return
	end
	m.settleWait = 0
	writeSetup(m)
end

--;===========================================================
--; STEP VERIFICATION
--;===========================================================
-- A Step is verified against the engine's own state, once per frame, and never against
-- the inputs that produced it: what a Trial asks for is that a move *happened*, which
-- is a state number, not a joystick history. That is why a Trial Definition spells
-- states and animations and never commands.

-- What last hit the Dummy, as far as a Step's conditions are concerned.
--
-- A Step can name a state belonging to the player or to one of its helpers, and only
-- the player's own is readable directly. The helper's comes off the Dummy's hit
-- variables — they describe the character that was *hit*, so they are read through the
-- P2 redirect: getHitVar('playerid') names whoever landed the hit, and redirecting to
-- it gives the state and animation the Step's stateno and animno are matched against.
--
-- A projectile is a different thing entirely, and this is where the format's projid
-- comes from. Three engine facts decide it:
--
--   - a projectile's Hitdef carries `playerid = proj.owner().id`, and a helper only
--     owns its projectiles when it declared `ownprojectile`. The usual fireball — a
--     plain helper running a Projectile controller — hands ownership to the root, so
--     the redirect lands on the player, not on the helper whose state the move is.
--   - projVar cannot fill the gap. A projectile with the usual projremove is already
--     in ProjHit by the time Lua runs (globalTick precedes the Common.Lua call in
--     System.action), so getSingleProj finds nothing on the very frame the hit lands.
--   - projanim is not an identity either: a character commonly draws every one of its
--     fireballs with the same sprite (CVS Ryu spends 7050 on four different moves).
--
-- What does survive the hit and does identify the move is the projectile's own ID —
-- the Projectile controller's ProjID, which authors already give distinct values
-- because their own CNS counts projectiles with NumProjID. getHitVar('projid') is that
-- number, and -1 on a hit that was not a projectile's.
--
-- Returns empty fields on a frame with no hit, which read as "matches nothing" rather
-- than as "matches anything".
local function readAttacker()
	local out = {stateno = nil, anim = nil, projid = nil}
	if not player(2) then
		return out
	end
	if getHitVar('frame') then
		local id = getHitVar('playerid')
		local projid = getHitVar('projid')
		if projid >= 0 then
			out.projid = projid
		elseif playerId(id) then
			out.stateno = stateNo()
			out.anim = anim()
		end
	end
	-- Put the redirect back on the Trials player. Everything below reads the player's
	-- own state through it, and so does every other module the loop reaches after this.
	player(1)
	return out
end

-- Does a value satisfy one condition field of a Part?
--
-- Either the player's own reading or the attacker's counts, which is what lets a single
-- field cover a move performed by the player, by one of its helpers, or by a
-- projectile. A field the Part does not name is not a condition at all.
local function satisfies(list, own, theirs)
	if list == nil then
		return true
	end
	for _, want in ipairs(list) do
		if own == want or theirs == want then
			return true
		end
	end
	return false
end

-- Every character variable in a list of var/value pairs holds one of its declared
-- values. The one evaluator both keys in that format go through: a Step's
-- trialstep.X.validforvarvalpairs, which gates the whole Step rather than one of its
-- Parts, and a Trial's trial.showforvarvalpairs, which gates the whole Trial (#52).
--
-- Takes the pairs rather than the thing they came off, because the two callers hold
-- them under different names and neither has any business knowing the other's shape.
-- nil is ungated and holds trivially. Reads through whatever redirect the caller has
-- set: var() is P1's here in both cases.
local function varPairsHold(gate)
	if gate == nil then
		return true
	end
	for _, pair in ipairs(gate) do
		if not satisfies(pair.values, var(pair.var), nil) then
			return false
		end
	end
	return true
end

-- Which of the character's Trials are on offer this round, and the bookkeeping that
-- follows from the answer.
--
-- A Trial gated out by trial.showforvarvalpairs is not thinned at the point of use —
-- it is taken out of m.trials, so the Trial Counter, Advancement, All-Clear and the
-- pause menu's trials list all keep counting a plain array and none of them has to
-- know why a Trial is missing. Everything they index is a position in the AVAILABLE
-- list; the declared index is what survives the rebuild (see m.completed).
--
-- Once a round, and stale again the moment the round state falls back. docs/adr/0003
-- is why it is not once a match and not every frame.
--
-- Twice within that round, though, and the second reading is the one that stands: a
-- character can still be choosing the mode this gate reads through the whole of the
-- intro. cvsryu's groove helper seeds var(20) with `random%7` and copies its selection
-- to the root every frame until it destroys itself at `roundstate > 1` (groove.cns
-- 27-48, 113-121), so a reading taken while the announcement is still on screen is a
-- random groove as often as the player's own.
--
-- The provisional reading at roundState 1 is not wasted: applyDummy and applySetup run
-- straight after this and write from the Trial the match is on, so having the list
-- already thinned is what keeps the intro from placing the pair for a Trial that is not
-- on offer and correcting itself in front of the player.
local function applyAvailability(m)
	if m == nil then
		return
	end
	if roundState() < 1 then
		m.availableRound = nil
		return
	end
	-- 1 while the round is coming up, 2 once it is live. Anything past 2 is a round
	-- ending, which re-reads nothing: the answer for this round was settled at 2.
	local stage = roundState() >= 2 and 2 or 1
	if m.availableRound ~= nil and m.availableRound >= stage then
		return
	end
	-- var() reads through whichever character the engine last left the redirect on, so
	-- the gate is meaningless without this — it is the Trials player's variables the
	-- Trial Definition names. Nothing is resolved on a frame there is no P1 to read:
	-- the round is live, so this failing is a reason to wait rather than to answer
	-- wrongly and mark the answer fresh. The redirect is left where it is put, which
	-- is where the rest of the loop wants it anyway.
	if not player(1) then
		return
	end
	local before = m.trials
	local available = {}
	for _, trial in ipairs(m.declared) do
		if varPairsHold(trial.showfor) then
			available[#available + 1] = trial
		end
	end
	m.availableRound = stage

	-- The Trial the player is on, by declared index rather than by position: the
	-- position it sat at belongs to the list being replaced. Where it is still on offer
	-- they stay on it; where it has been gated out there is nowhere to stay, and the
	-- match falls back to the first available Trial.
	local held = before[m.current]
	local current = 1
	for i, trial in ipairs(available) do
		if held ~= nil and trial.index == held.index then
			current = i
			break
		end
	end

	local changed = #available ~= #before
	if not changed then
		for i, trial in ipairs(available) do
			if trial ~= before[i] then
				changed = true
				break
			end
		end
	end

	m.trials = available
	m.total = #available
	-- Recounted against the set now on offer. A Trial completed in another groove is
	-- still completed — m.completed keeps it — but it does not hold this set's
	-- All-Clear open, and it does not count towards it either.
	m.completedCount = 0
	for _, trial in ipairs(available) do
		if m.completed[trial.index] then
			m.completedCount = m.completedCount + 1
		end
	end
	-- All-Clear can be lost by a re-evaluation and never silently gained: a set that
	-- grew goes back to unfinished, and a set the player has in fact already completed
	-- does not fire a banner they did not earn. completeTrial is the only thing that
	-- turns it on.
	m.allclear = m.allclear and m.total > 0 and m.completedCount >= m.total

	if not changed then
		return
	end
	-- The list is a different list, so the trials list built from it is stale even when
	-- the player did not move.
	m.availableGen = m.availableGen + 1
	-- Resolves the Steps, the Textbox window and the per-Trial clock for wherever the
	-- player has landed. Unconditional on the position having changed: the same
	-- position in a rebuilt list is a different Trial.
	selectTrial(current)
	-- Written again for the reason applyDummy writes again: the gate is parsed at load
	-- and evaluated many seconds later, so a dump taken before this point shows what
	-- each Trial's pairs said and never which of them the character is actually being
	-- offered.
	trials.f_dumpState()
end

-- Whether the current Part registered this frame.
--
-- Three routes, one per kind of Step the format spells:
--
--   - a helper Part passes on state and animation alone, and a projectile Part on its
--     projid. The hit either produces is not the player's own, so there is no moveHit
--     to wait for.
--   - a throw, or a Part declaring hitcount = 0 — a taunt, a movement, a stance change
--     — passes on state alone: neither extends a combo.
--   - anything else has to land a hit of its own that takes the combo further than the
--     last Part left it.
--
-- The moveHit() test is new. The pre-refactor spelling was `movehit() and ...`, and
-- movehit() has always returned a number, which is truthy in Lua even at zero — so the
-- condition it was written to express has never actually been evaluated. Restoring it
-- is what stops a Part registering off a hit the player did not land, which is exactly
-- the case a Trial with a helper on screen runs into.
local function partRegisters(step, part, attacker, combo)
	if not satisfies(part.stateno, stateNo(), attacker.stateno) then
		return false
	end
	if not satisfies(part.animno, anim(), attacker.anim) then
		return false
	end
	-- Only ever satisfied by a projectile's hit: attacker.projid is nil on every other
	-- frame, and nil is not any of the numbers a Part can name. Passing nil as the
	-- player's own reading is what says so — a player has no projid of their own.
	if not satisfies(part.projid, nil, attacker.projid) then
		return false
	end
	if not varPairsHold(step.validfor) then
		return false
	end
	-- A counter-hit Part only counts when the engine says the hit countered. Tested
	-- here, before the hit count below has taken anything from it, so an ordinary hit
	-- leaves the Part exactly where it was rather than half-counted.
	if part.iscounterhit and part.hitcount ~= 0
		and not (comboCount() > 0 and moveCountered() > 0) then
		return false
	end
	-- A hit landed by something that is not the player does not raise the player's own
	-- moveHit, so there is nothing to wait for. A Part naming a projid says so on its
	-- own, whether or not the author also wrote the isproj flag.
	if part.ishelper or part.isproj or part.projid ~= nil then
		return true
	end
	return (moveHit() > 0 and comboCount() > combo) or part.isthrow or part.hitcount == 0
end

-- Whether the run is over: the player did something other than what the Step asked for.
--
-- A dropped combo is the signal, since that is what a wrong input produces. A Part
-- requiring no hit cannot drop, because there is no combo to lose. Inside a Part's
-- validfortickcount grace window the rule inverts: the run survives the combo ending
-- and is ended instead by a hit landing that was not the one the Step asked for.
local function dropped(m, part)
	if m.grace > 0 then
		return comboCount() > m.combo
	end
	return part.hitcount ~= 0 and comboCount() == 0
end

-- Fires Success for the Trial just finished, or All-Clear if that was the last one the
-- character had left, and moves the match on according to the Advancement preference.
local function completeTrial(m)
	local index = m.current
	-- Recorded against the DECLARED index, which is the one that survives the available
	-- list being rebuilt next round (#52, docs/adr/0003). completedCount counts only
	-- what is on offer, so it is the one that All-Clear is measured against.
	local declared = type(m.trials[index]) == 'table' and m.trials[index].index or index
	if not m.completed[declared] then
		m.completed[declared] = true
		m.completedCount = m.completedCount + 1
	end

	-- All-Clear is every Trial completed, not the end of the list reached: a player
	-- repeating one Trial, or jumping around them, finishes the set just as surely as
	-- one going straight through. It replaces the Success banner rather than following
	-- it, and fires once.
	local finished = m.completedCount >= m.total and m.total > 0 and not m.allclear
	if finished then
		m.allclear = true
	end
	-- What is on screen is the Trial just finished, and it stays there for the banner.
	-- Every Step of it reads as completed for as long as it does.
	m.shownComplete = true
	local banner = finished and 'allclear' or 'success'
	local e = trials.elements[banner]
	if e ~= nil then
		m.banner = banner
		m.bannerTimer = e.displaytime
		if e.snd[1] >= 0 then
			sndPlay(motif.Snd, e.snd[1], e.snd[2])
		end
	end

	-- selectTrial starts the next Trial's clock from zero, but the reading that belongs
	-- on screen for the length of the banner is the one the player just posted. It goes
	-- back to zero when the banner clears — or stays up for good on All-Clear, which is
	-- where both stopwatches stop.
	local finishTicks = m.trialTicks
	if m.allclear then
		-- All-Clear freezes where it is: the counter reads All-Clear and both timers
		-- stop. The Trial itself starts over, so it is still playable underneath.
		selectTrial(index)
	elseif autoAdvances() and m.total > 0 then
		selectTrial(index % m.total + 1)
	else
		selectTrial(index)
	end
	if m.banner ~= nil then
		m.trialTicks = finishTicks
	end
	-- Reset on Success decides what a finished Trial does to where the two characters
	-- stand, and it decides it for every Success — not only the ones that stay on the
	-- same Trial.
	--
	-- On, the request the mid-Trial combination latches is latched here, and the pair
	-- goes back to the next Trial's authored positions through the machinery already
	-- there: the banner wait, the settled-Dummy wait, the fade, the camera and the
	-- display lag all belong to it and none of them change. Unconditional on whether the
	-- Trial changed, because applySetup's own trigger is the Trial changing and a
	-- repeated Trial has not.
	--
	-- Off, the run carries straight on from wherever the combo ended: the next Trial is
	-- taken on in place, with no move and no fade between the two.
	if preferenceEnabled('ResetOnSuccess', true) then
		m.reposRequest = true
	else
		m.adoptTrial = m.current
	end
	trials.f_dumpState()
end

-- Moves past the Part the player has just satisfied, and past the Step and the Trial
-- when that Part was their last.
local function advancePart(m, step, part)
	m.part = m.part + 1
	m.partHits = 0
	m.partCombo = 0
	-- The next Part's grace window is the one the Part just completed declared: the
	-- format's validfortickcount says how long the run survives waiting for what comes
	-- after it.
	m.grace = part.validfortickcount or 0
	-- A Step that ends with the combo already over — a throw, a knockdown — leaves this
	-- at zero, which is what makes the follow-up's first hit read as the honest `1 > 0`.
	-- Whether the run survives the gap at all is validfortickcount's job, not this one's.
	m.combo = comboCount()
	if m.part <= #step.parts then
		return
	end

	-- Every Part done, so the Step is.
	m.part = 1
	m.step = m.step + 1
	if m.step > #m.steps then
		completeTrial(m)
	end
end

-- One frame of Step verification. Runs while the round is live and no banner is up.
local function verify()
	local m = trials.match
	local step = m.steps[m.step]
	if type(step) ~= 'table' or type(step.parts) ~= 'table' then
		return
	end
	local part = step.parts[m.part]
	if part == nil then
		return
	end
	-- Everything below reads the player's own state, so the redirect starts on them.
	if not player(1) then
		return
	end

	local attacker = readAttacker()
	local registers = partRegisters(step, part, attacker, m.combo)
	if not registers and dropped(m, part) then
		resetProgress(m)
		return
	end
	-- Spent after the drop test, not before it: a Part declaring validfortickcount = 1 is
	-- asking for one frame of protection, and spending that frame before anything
	-- consults the window would leave it with none.
	if m.grace > 0 then
		m.grace = m.grace - 1
	end
	if not registers then
		return
	end

	-- A Part asking for several hits counts them as the combo takes them. partCombo is
	-- the combo count when the Part first registered, so the difference is how far
	-- through its hits the player is.
	if part.hitcount >= 1 then
		if m.partHits == 0 then
			m.partCombo = comboCount()
		end
		if comboCount() - m.partHits == m.partCombo then
			m.partHits = m.partHits + 1
		end
	else
		m.partHits = 0
	end
	if m.partHits ~= part.hitcount then
		return
	end

	-- A multi-hit Part is finished only once the combo has actually taken all of them.
	if part.hitcount > 1 and comboCount() ~= m.partHits + m.partCombo - 1 then
		if dropped(m, part) then
			resetProgress(m)
		end
		return
	end
	advancePart(m, step, part)
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
	if not gameMode('trials') then
		return
	end
	-- A new match resolves its Trials again on the first frame of the loop, by which
	-- point the engine has finished selecting characters.
	trials.match = nil
	if type(trials.ini.Common) ~= 'table' then
		return
	end
	for section, values in pairs(trials.ini.Common) do
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
--; DRAWING
--;===========================================================

-- Substitutions follow the engine's own %i/%s convention (main.f_formatBySpec): %i is
-- the current Trial, %s the total.
--
-- Screenpacks written against the pre-refactor module wrote "Trial %s of %t", where %s
-- was the current Trial and %t the total. %t is not a printf verb, so string.format
-- rejects the whole string and f_formatBySpec hands back the format spec itself — the
-- counter would render "Trial %s of %t" on screen. A %t is an unambiguous marker for
-- that older convention, so read it that way rather than breaking every screenpack
-- that already ships one.
local function counterText(current, total)
	local fmt = strValue(cfgGet({'trials_mode', 'trialcounter', 'text'}), '')
	if fmt:find('%%t') then
		return main.f_formatBySpec(fmt:gsub('%%t', tostring(total)), {s = tostring(current), i = current})
	end
	return main.f_formatBySpec(fmt, {i = current, s = tostring(total)})
end

-- Where one Step sits relative to the player's progress, which is what decides the
-- element it is drawn with. Both Layouts ask the same question of the same index.
local function stepStatus(index, step)
	if index < step then
		return 'completed'
	elseif index == step then
		return 'current'
	end
	return 'upcoming'
end

-- How big one Glyph draws beside a given Step Status.
--
-- Two sizings, chosen by `glyphs.<layout>.scalewithtext`, and they are alternatives
-- rather than a base and a multiplier.
--
-- ON, which is the default: the engine's own movelist formula (menu.lua:891). The Glyph
-- is scaled so that its sprite height matches the height of the font drawing the Step,
-- times that element's own text scale. Both axes take the height ratio, so the sprite
-- keeps its proportions — and a Step Status a screenpack styles larger carries its
-- Glyphs up with it, which is what makes the run read as part of the Step. The derived
-- size REPLACES `glyphs.<layout>.scale`, exactly as the pre-refactor module's own
-- toggle did (old trials.lua:894); with this on, that key is not read.
--
-- OFF: `glyphs.<layout>.scale` is the size, as written, and nothing about the text
-- enters into it. This is what a screenpack sizing its Glyphs absolutely wants — the
-- pre-refactor default was an absolute 0.3125 — and it is the only way to draw Glyphs
-- at a size the words do not dictate.
--
-- ON but underivable takes the configured scale too, and for the same reason OFF does:
-- there is no font height to match, so `scale` is the only size anyone has stated. A
-- Glyph is a sprite and can always be drawn — treating an absent font as "cannot size"
-- took the icons down with the words (#59), which is a configuration a screenpack
-- really does write, because the pre-refactor horizontal Layout drew Glyphs and no text
-- at all.
--
-- What is measured is the FONT's height, not the Step's string: a Step whose text is
-- empty still sizes its Glyphs from the font its Step Status resolved, so a run does not
-- change size from one Step to the next.
--
-- nil only where the sprite itself cannot be sized, which is a token this screenpack
-- has no Glyph for. That one is skipped, exactly as menu.lua:887 skips it.
local function glyphScale(block, e, token)
	local g = type(motif.glyphs) == 'table' and motif.glyphs[token] or nil
	if g == nil or type(g.Size) ~= 'table' then
		return nil
	end
	local sprite = tonumber(g.Size[2]) or 0
	if sprite <= 0 then
		return nil
	end
	local gl = block.glyphs
	if gl.scalewithtext then
		local size = e.fontdef ~= nil and e.fontdef.Size or nil
		local height = size ~= nil and (tonumber(size[2]) or 0) or 0
		if height > 0 then
			local derived = height * e.scale[2] / sprite
			return derived, derived
		end
	end
	return gl.scale[1], gl.scale[2]
end

-- Walks one Step's Glyphs along a row, left to right, and returns how wide the run is.
--
-- With `fn`, each Glyph is handed back as it is reached, with how far along the run it
-- sits and how big it draws. Measuring and drawing are therefore the same walk, so a
-- run can never be measured one way and drawn another — which matters in the horizontal
-- Layout, where the measurement is what reserves the room the drawing then uses.
--
-- A token this screenpack has no Glyph for contributes nothing and does not break the
-- walk: it is skipped, exactly as menu.lua:887 skips it.
local function glyphRun(block, status, glyphs, fn)
	local gl = block.glyphs
	local e = block.text[status]
	local cache = gl.anims[status]
	local x = 0
	local drawn = 0
	for _, token in ipairs(glyphs) do
		local a = cache[token]
		local sx, sy = glyphScale(block, e, token)
		if a and sx ~= nil then
			if fn ~= nil then
				fn(a, x, sx, sy)
			end
			x = x + (tonumber(motif.glyphs[token].Size[1]) or 0) * sx + gl.spacing[1]
			drawn = drawn + 1
		end
	end
	-- Spacing sits between Glyphs, not after the last one.
	if drawn > 0 then
		x = x - gl.spacing[1]
	end
	return x
end

-- What one Step's Glyphs add to the width of its item in the horizontal Layout: the run
-- itself, plus the offset that holds it off the words.
--
-- A Step declaring no Glyphs adds nothing at all — not the offset either. That is what
-- keeps a text-only Trial flowing as though the feature were not there, rather than
-- laying out around a gap it never fills.
local function glyphWidth(block, status, step)
	local gl = block.glyphs
	if gl == nil or step.glyphs == nil or #step.glyphs == 0 then
		return 0
	end
	local width = glyphRun(block, status, step.glyphs)
	if width <= 0 then
		return 0
	end
	return gl.offset[1] + width
end

-- Draws one Step's Glyphs, as a run laid out from where that Step sits.
--
-- Where the run is anchored differs by Layout, because the two put a Step in a
-- different kind of place. Every vertical row starts at the block's origin, so the
-- offset is measured from there and the run stands as a column beside text of varying
-- length. A horizontal Step sits wherever the flow put it, so the offset is measured
-- from the end of that Step's own text and the run follows the words.
local function drawGlyphs(block, status, step, x, y)
	local gl = block.glyphs
	local glyphs = step.glyphs
	if gl == nil or glyphs == nil or #glyphs == 0 then
		return
	end
	local e = block.text[status]
	local width = glyphRun(block, status, glyphs)
	if width <= 0 then
		return
	end
	local anchor = block.pos[1] + gl.offset[1] + x
	if block.layout == 'horizontal' then
		anchor = anchor + textImgGetTextWidth(e.TextSpriteData, step.text) * e.scale[1]
	end
	-- Vertical only: see buildGlyphs. The horizontal run always grows right from the
	-- text it follows, which is the direction glyphWidth reserves room in.
	if block.layout ~= 'horizontal' then
		if gl.align == 0 then
			anchor = anchor - width / 2
		elseif gl.align == -1 then
			anchor = anchor - width
		end
	end
	local top = block.pos[2] + gl.offset[2] + y
	glyphRun(block, status, glyphs, function(a, dx, sx, sy)
		animSetScale(a, sx, sy)
		animSetPos(a, anchor + dx, top)
		-- Neither reset nor palfx here. animReset would clear the effect the Anim was
		-- built with (Anim.Reset calls palfx.clear, src/anim.go:2365), and animUpdate is
		-- what carries that effect through to the draw — it advances at most once per
		-- Anim per frame, so calling it before each of a Glyph's several draws costs
		-- nothing. animDraw snapshots the Anim, so the position just set is the one this
		-- draw uses even though the next Step moves the same Anim again.
		animUpdate(a)
		animDraw(a)
	end)
end

-- Draws one background piece, `dx, dy` from where it was built.
--
-- `sx` overrides the element's own x scale, which is how the horizontal body is
-- stretched to the width of the Step it sits under; without it the element draws at the
-- scale it was configured with.
--
-- Neither animReset nor animSetPalFX here, for the reason drawGlyphs skips both: Reset
-- would clear the palette effect the Anim was built with (src/anim.go:2365), and the
-- effect only reaches the draw through animUpdate, which advances at most once per Anim
-- per frame however many times it is called. animDraw snapshots the Anim, so one Anim
-- drawn once per Step lands each time at the position and scale set just before it.
local function drawArt(e, dx, dy, sx)
	if e == nil or e.AnimData == nil then
		return
	end
	local a = e.AnimData
	animSetPos(a, e.pos[1] + dx, e.pos[2] + dy)
	animSetScale(a, sx or e.scale[1], e.scale[2])
	animUpdate(a)
	animDraw(a)
end

-- The background under one Step in the vertical Layout: one sprite, drawn as authored,
-- where the row is.
local function drawStepBgVertical(block, status, x, y)
	local bg = block.stepbg ~= nil and block.stepbg[status] or nil
	if bg ~= nil then
		drawArt(bg.body, x, y)
	end
end

-- The background under one Step in the horizontal Layout: the arrow described in
-- buildStepBg, laid out from the left edge of the Step's own item.
--
-- `content` is what that Step actually renders — its text and its Glyphs together --
-- and the body is stretched to that plus the configured padding on each side. It is the
-- same number drawStepsHorizontal reserved room for, passed in rather than measured
-- again, so the artwork can never disagree with the layout drawn over it.
--
-- Sized by scale and not by tiling, which is what the pre-refactor module did despite
-- the comment above its own formula saying otherwise. It is why the shipped body sprite
-- is four units wide and uniform along x: anything with detail across it would smear.
--
-- A body with no sprite is skipped rather than divided by a zero width, so a Step Status
-- that configures only a head and a tail still gets them.
local function drawStepBgHorizontal(block, status, x, y, content)
	local bg = block.stepbg ~= nil and block.stepbg[status] or nil
	if bg == nil then
		return
	end
	local span = block.padding * 2 + content
	drawArt(bg.tail, x, y)
	if bg.bodyWidth > 0 then
		drawArt(bg.body, x + bg.tailWidth, y, span / bg.bodyWidth * bg.body.scale[1])
	end
	drawArt(bg.head, x + bg.tailWidth + span, y)
end

-- The Anim for one character's portrait, built once per character and cached.
--
-- charSpriteDraw is gone from the engine, which is what the pre-refactor module drew
-- this with. animGetPreloadedCharData is the replacement: it hands back an Anim over the
-- sprite the select screen already loaded for that character, so nothing is read off
-- disk here and a character with no such sprite simply returns nil.
--
-- The scale correction is the engine's own, from main.f_materializeCharCell
-- (main.lua:746): a portrait is authored in the CHARACTER's coordinate space, not in the
-- space it is being drawn in, so the ratio between the two is applied on top of whatever
-- scale the screenpack asked for. `portraitscale` is the character's own declared
-- correction and is part of the same product.
--
-- The engine's version divides into motif.info.localcoord because that is the space its
-- own select-screen cells resolve in. This one divides into the ELEMENT's localcoord,
-- which is the space this portrait actually draws in — the module's own 320x240 unless a
-- screenpack moved it. Taking the engine's constant here would size the portrait for a
-- space it is not in.
local function charPortrait(box, row)
	if row == nil or row.char_ref == nil then
		return nil
	end
	local cached = box.portraits[row.char_ref]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end
	local geo = box.portraitGeo
	local a = animGetPreloadedCharData(row.char_ref, box.portraitSpr[1], box.portraitSpr[2])
	if a == nil then
		box.portraits[row.char_ref] = false
		return nil
	end
	local lc = geo.localcoord
	local charLc = tonumber(row.localcoord) or lc[1]
	local correction = (tonumber(row.portraitscale) or 1) * lc[1] / (charLc > 0 and charLc or lc[1])
	animSetLocalcoord(a, lc[1], lc[2])
	animSetPos(a, geo.pos[1], geo.pos[2])
	animSetScale(a, geo.scale[1] * correction, geo.scale[2] * correction)
	animSetFacing(a, box.portraitFacing)
	animSetXShear(a, geo.xshear)
	animSetAngle(a, geo.angle)
	animSetXAngle(a, geo.xangle)
	animSetYAngle(a, geo.yangle)
	animSetProjection(a, geo.projection)
	animSetFocalLength(a, geo.focallength)
	animSetWindow(a, geo.window[1], geo.window[2], geo.window[3], geo.window[4])
	animSetLayerno(a, geo.layerno)
	box.portraits[row.char_ref] = a
	return a
end

-- The Textbox's title line.
--
-- Two spellings, told apart the way counterText tells its two apart: the pre-refactor
-- one spelled the Trial's number %s and its name %n, and the modern one follows the
-- engine's own substitution convention — %i for the number, %s for the name. The
-- presence of %n is what says which is meant, so an existing screenpack needs no edit
-- and a new one does not have to know the old spelling existed.
local function textboxTitle(m)
	local fmt = trials.textbox ~= nil and trials.textbox.title.text or ''
	local index = m.shownCurrent or m.current
	local trial = m.trials[index]
	local name = type(trial) == 'table' and trial.title or ''
	if fmt:find('%%n') then
		-- Rewritten onto the modern spelling rather than substituted into: %n becomes
		-- %s and the old %s becomes %i, and the name then goes through f_formatBySpec as
		-- an ARGUMENT like it does below.
		--
		-- Substituting the name into the format string instead looks simpler and is
		-- wrong twice over. gsub reads `%` in its replacement as a capture reference,
		-- and f_formatBySpec then runs string.format over the result, which reads a
		-- surviving `%` as a format spec of its own — so a Trial an author named
		-- "100% Damage" came out as "100%!D(MISSING)amage". A replacement FUNCTION is
		-- used here because its return value is taken literally, which is what makes
		-- one pass safe against both spellings at once regardless of order.
		return main.f_formatBySpec(fmt:gsub('%%([ns])', function(c)
			return c == 'n' and '%s' or '%i'
		end), {i = index, s = name})
	end
	return main.f_formatBySpec(fmt, {i = index, s = name})
end

-- The Textbox, when the Trial on screen carries one and the player has not hidden them.
--
-- Nothing is constructed per frame except a character's portrait Anim, and that only the
-- first time each character is seen.
local function drawTextbox(m)
	local box = trials.textbox
	if box == nil or not m.shownTextbox then
		return
	end
	local text = m.shownText or ''
	if text == '' then
		return
	end
	drawArt(box.bg, 0, 0)

	if box.portraitSource == 'char' then
		local a = charPortrait(box, m.charRow)
		if a ~= nil then
			animUpdate(a)
			animDraw(a)
		end
	else
		drawArt(box.portrait, 0, 0)
	end

	local title = box.title
	textImgSetText(title.TextSpriteData, textboxTitle(m))
	textImgDraw(title.TextSpriteData)

	-- Neither reset nor re-position here: textImgReset zeroes the tick count the typed
	-- reveal is measured against (src/font.go:1456), so resetting per frame would retype
	-- the first character forever. The reset belongs to the moment the Trial changes,
	-- which is where the reveal should start over — see syncDisplay.
	textImgUpdate(box.text.TextSpriteData)
	textImgDraw(box.text.TextSpriteData)

	drawArt(box.front, 0, 0)
end

-- Draws one Step, with the element for the Step Status it currently has.
--
-- Nothing is constructed here. Each row is the engine's own list idiom
-- (main.f_drawMenu, main.lua:3811): reset the element to the position it was built at,
-- add the row's offset, set the text, draw. The Step's Glyphs then draw beside it.
local function drawStep(block, status, step, x, y)
	local ts = block.text[status].TextSpriteData
	textImgReset(ts)
	textImgAddPos(ts, x, y)
	textImgSetText(ts, step.text)
	textImgDraw(ts)
	drawGlyphs(block, status, step, x, y)
end

-- The vertical Layout: one Step per row, stacked from the block's origin one spacing
-- apart, so advancing the Step index is all it takes for a row to move from upcoming to
-- current to completed.
local function drawStepsVertical(block, steps, step, shift)
	local spacing = block.spacing
	local first, last = 1, #steps

	-- Scroll only once the rows cannot all fit the window. Keeping one completed Step
	-- above the current one is what the pre-refactor module did, and it is what makes a
	-- long Trial read as progress rather than as a jump.
	--
	-- A negative spacing draws the list upward, which no window height can be reasoned
	-- about the same way, so that case simply never scrolls and lets the window clip.
	-- Measured from where the rows actually start, not from the window's top edge. The
	-- origin and the window are configured independently, so the space available to the
	-- list is what lies between them — taking the window's full height instead counts
	-- rows that fall off its bottom and reads them as fitting.
	local available = block.activeWindow[4] - (block.pos[2] + shift[2])
	if available > 0 and spacing[2] > 0 then
		-- n rows span n-1 spacings, so this is how many of them that space holds.
		local fit = math.floor(available / spacing[2]) + 1
		if #steps > fit then
			first = math.max(1, math.min(step - 1, #steps - fit + 1))
			-- One completed Step above the current one only where there is room for
			-- them. A window one or two rows deep still has to show the row the player
			-- is actually on, so the current Step wins over the pair above it.
			first = math.max(first, step - fit + 1)
			last = math.min(first + fit - 1, #steps)
		end
	end

	for i = first, last do
		local status = stepStatus(i, step)
		local x = shift[1] + spacing[1] * (i - first)
		local y = shift[2] + spacing[2] * (i - first)
		-- Before the text, which is the whole of what puts it behind: elements sharing
		-- a layer number draw in call order, and a background that drew after the words
		-- would cover them.
		drawStepBgVertical(block, status, x, y)
		drawStep(block, status, steps[i], x, y)
	end
end

-- The horizontal Layout: Steps flowed along a row from the block's origin, one spacing
-- apart, each one padded on both sides. A Step that would reach past the window's right
-- edge starts a new row instead, one vertical spacing down.
--
-- Measured, not guessed: a Step's width is its own text through the engine's
-- textImgGetTextWidth, times the scale of the element that draws it, exactly as the
-- engine's own movelist measures its lines (menu.lua:928), plus whatever its Glyphs add
-- beside it. Which element that is depends on the Step Status, so the row reflows as the
-- player advances — which is the point: a Step Status the screenpack styles at a
-- different scale takes a different amount of room, and pretending otherwise would leave
-- the row overlapping itself.
--
-- The background is part of that width and not decoration laid over it. One item spans
--
--     tail + padding + content + padding + head
--
-- with one spacing between items, so the head of one Step and the tail of the next
-- cannot overlap and a row wraps where the artwork actually ends. Content is text and
-- Glyphs together, which is the one place this departs from the pre-refactor module:
-- that one drew Glyphs alone in this Layout and sized its background to the Glyph line,
-- so a Trial Definition shipping no Glyphs would have collapsed to nothing here.
--
-- A Step Status with no background contributes no tail and no head, so a screenpack that
-- configures none lays its Steps out exactly as it did before this existed.
local function drawStepsHorizontal(block, steps, step, shift)
	local spacing = block.spacing
	local padding = block.padding
	local originX = block.pos[1] + shift[1]

	-- Where rows wrap. Measured from where they start rather than from the window's left
	-- edge, for the reason the vertical Layout measures its height that way: the origin
	-- and the window are configured independently.
	--
	-- An all-zero window is the engine's spelling of "do not clip" (textImgSetWindow
	-- ignores such a rect, src/font.go:915), and a row with nowhere to wrap runs off the
	-- side of the screen and stays there. So an unclipped block wraps at the edge of its
	-- own coordinate space, which is what "do not clip" means on screen.
	local right = block.activeWindow[3]
	if right <= 0 then
		right = block.localcoord[1]
	end
	local available = right - originX

	-- Lay the whole Trial out first: which row each Step lands on, and how far along it.
	-- The draw pass needs to know how many rows there are before it can decide which of
	-- them are on screen.
	local placement, rows, x = {}, 1, 0
	for i = 1, #steps do
		local status = stepStatus(i, step)
		local e = block.text[status]
		local bg = block.stepbg ~= nil and block.stepbg[status] or nil
		local content = textImgGetTextWidth(e.TextSpriteData, steps[i].text) * e.scale[1] +
			glyphWidth(block, status, steps[i])
		local lead = bg ~= nil and bg.tailWidth or 0
		local width = lead + padding * 2 + content + (bg ~= nil and bg.headWidth or 0)
		-- `x > 0` is what keeps a Step wider than the whole row from wrapping forever:
		-- it has nowhere to go, so it starts its own row and the window clips it.
		if x > 0 and available > 0 and x + width > available then
			rows = rows + 1
			x = 0
		end
		-- Kept rather than recomputed in the draw pass below: the background is sized
		-- from `content` and the text starts after `lead`, and a second measurement is a
		-- second chance for the two to disagree.
		placement[i] = {row = rows, x = x, status = status, content = content, lead = lead}
		x = x + width + spacing[1]
	end

	-- Scroll by rows once they no longer fit, the way the vertical Layout scrolls by
	-- Steps: keep one row above the one the player is on where there is room for it, and
	-- the row they are on wherever there is not.
	local first, last = 1, rows
	local availableY = block.activeWindow[4] - (block.pos[2] + shift[2])
	if availableY > 0 and spacing[2] > 0 and rows > 1 then
		local fit = math.floor(availableY / spacing[2]) + 1
		if rows > fit then
			-- The row of the Step the player is on, or of the last one when the Trial is
			-- finished and every Step reads as completed.
			local current = placement[math.max(1, math.min(step, #steps))].row
			first = math.max(1, math.min(current - 1, rows - fit + 1))
			first = math.max(first, current - fit + 1)
			last = math.min(first + fit - 1, rows)
		end
	end

	for i = 1, #steps do
		local at = placement[i]
		if at.row >= first and at.row <= last then
			local x = shift[1] + at.x
			local y = shift[2] + spacing[2] * (at.row - first)
			-- Before the text, for the reason the vertical Layout draws its plate first.
			drawStepBgHorizontal(block, at.status, x, y, at.content)
			drawStep(block, at.status, steps[i], x + at.lead + padding, y)
		end
	end
end

-- The Steps of the current Trial, drawn in whichever Layout the player has chosen.
local function drawSteps()
	local block = trials.stepblock
	local m = trials.match
	if block == nil or m == nil then
		return
	end
	-- The Trial on screen, which is not always the Trial the match is on: see
	-- syncDisplay. A finished one reads as finished all the way down, rather than as the
	-- next Trial's Step 1 highlighted over the Steps the player has just completed.
	local steps = m.shownSteps or m.steps
	-- shownStep is the progress frozen with a held Trial, so a Trial waiting behind a
	-- fade keeps the Step the player actually reached rather than the reset one the
	-- match has already moved to. nil on every ordinary frame.
	local step = m.shownComplete and #steps + 1 or (m.shownStep or m.step)
	if #steps == 0 then
		return
	end

	-- A Textbox displaces the whole block rather than being drawn over it.
	local shift = m.shownTextbox and block.shift or {0, 0}
	-- The panel first, under everything else the block draws. Deliberately not shifted
	-- with the block: a Rect's geometry is its window, and the with-Textbox variant of
	-- that window is what moves it — so a panel that also took the block's pos shift
	-- would move twice.
	if block.overlay ~= nil then
		rectDraw(block.overlay.RectData)
	end
	-- Behind the whole list, and drawn exactly once. The pre-refactor module updated and
	-- drew this same element twice per frame (old trials.lua:1133-1136), which on a
	-- translucent sprite is visible: it composited over itself and read darker than it
	-- was authored.
	drawArt(block.bg, shift[1], shift[2])
	if block.layout == 'horizontal' then
		drawStepsHorizontal(block, steps, step, shift)
	else
		drawStepsVertical(block, steps, step, shift)
	end
end

-- A stopwatch reading, mm:ss:cc.
--
-- framespercount is the engine's own name for how many ticks make one unit of a timer,
-- and means the same thing here as it does on an engine timer element; only the
-- direction differs.
local function timerText(fmt, ticks, framespercount)
	local seconds = math.max(0, ticks) / math.max(1, framespercount)
	local reading = string.format('%02d:%02d:%02d',
		math.floor(seconds / 60),
		math.floor(seconds % 60),
		math.floor(seconds % 1 * 100))
	return main.f_formatBySpec(fmt, {s = reading, i = math.floor(ticks)})
end

-- Draws one stopwatch and returns it advanced by a tick.
--
-- Deliberately shaped like main.f_drawTimer — timer first, element second, the advanced
-- timer back — so the two read alike even though the engine's counts down from a
-- configured start and this one counts up from zero. Its formula is not reusable;
-- its calling convention is.
local function drawTimer(timer, element, running)
	if element == nil then
		return timer
	end
	if running then
		timer = timer + 1
	end
	textImgReset(element.TextSpriteData)
	textImgSetText(element.TextSpriteData,
		timerText(element.text, timer, element.framespercount))
	textImgDraw(element.TextSpriteData)
	return timer
end

-- Takes the banner down and hands the match back to the player.
--
-- Both of the things frozen for its length come back here rather than at the next
-- verify: the restarted Trial's clock starts now, and the combo count is re-read so a
-- combo still running from the attempt that just finished cannot register as the first
-- hit of the new one. All-Clear keeps its finishing time, since nothing restarts.
local function clearBanner(m)
	m.banner = nil
	m.bannerTimer = 0
	if not m.allclear then
		m.trialTicks = 0
	end
	if player(1) then
		m.combo = comboCount()
	end
end

-- The standing reminder of the reposition combination.
--
-- Drawn for as long as the feature is usable and the screenpack gave it words: a
-- reminder of a combination that does nothing, or that the player cannot read, is
-- worse than none. Not drawn under a banner, which owns the screen while it is up.
local function drawReminder(m)
	local r = trials.reposition
	local e = trials.elements.trialresetreminder
	if r == nil or not r.enabled or #r.keys == 0 then
		return
	end
	if e == nil or e.text == '' or m.banner ~= nil then
		return
	end
	textImgReset(e.TextSpriteData)
	textImgSetText(e.TextSpriteData, e.text)
	textImgDraw(e.TextSpriteData)
end

-- The Success or All-Clear banner, for as long as its displaytime lasts.
local function drawBanner(m)
	local e = m.banner ~= nil and trials.elements[m.banner] or nil
	if e == nil then
		return
	end
	textImgReset(e.TextSpriteData)
	-- After the reset, which empties a Lua-made sprite: see buildBanner.
	textImgSetText(e.TextSpriteData, e.text)
	textImgDraw(e.TextSpriteData)
	m.bannerTimer = m.bannerTimer - 1
	if m.bannerTimer <= 0 then
		clearBanner(m)
	end
end

-- Runs once per frame during a Trials match, from the engine's Common.Lua `loop()`
-- (debug.lua:230). Sets text and draws — nothing is constructed here.
hook.add('loop#trials', 'trials', function()
	if not trials.enabled then
		return
	end
	if trials.match == nil then
		trials.match = resolveMatch()
		-- The backdrop starts from the top with the match, the way the engine resets a
		-- screen's own background when that screen is entered. Once per match and not
		-- per round: a round restart is the same session of the mode, and a scrolling
		-- background that jumped back on every retry would read as a glitch.
		if trials.background ~= nil then
			bgReset(trials.background)
		end
		selectTrial(trials.match.current)
		trials.f_dumpState()
	end
	-- Ahead of both of the below, and before the roundState gate: which Trials are on
	-- offer decides which Trial the match is on, and the Dummy settings and the pair's
	-- positions are written from that Trial. Resolving it second would write them from
	-- a Trial that is not offered and then correct itself in front of the player.
	applyAvailability(trials.match)
	-- Before the roundState gate below: the Dummy is configured during the intro, not
	-- once the round is live.
	applyDummy()
	applySetup()
	-- The trials list and the Player Preference values, both of which belong to the
	-- match rather than to the run. Cheap: it does nothing on a frame where neither the
	-- match nor the Trial has changed.
	syncPauseMenu()
	local m = trials.match
	if roundState() ~= 2 then
		-- A banner only counts down on a frame it is drawn on, and nothing draws outside
		-- a live round. Taking it down here keeps a round that ends mid-banner — the
		-- combo that finished the Trial being the one that KOs the Dummy, most of all —
		-- from carrying frozen verification into the next round.
		if m.banner ~= nil then
			clearBanner(m)
		end
		return
	end

	-- The mode's backdrop, behind everything below it. Both layers are drawn, at either
	-- end of the module's own elements, which is how every engine screen draws its own:
	-- layer 0 under them, layer 1 over. bgDraw steps the background as well as queueing
	-- it, so a background only animates on the frames it is on screen for.
	if trials.background ~= nil then
		bgDraw(trials.background, 0)
	end

	-- Verification before drawing, so a Step completed this frame is already drawn as
	-- completed rather than a frame late. It stops for the length of a banner: the
	-- Trial underneath has already restarted, and inputs still going in as the player
	-- reads SUCCESS should not count towards it.
	-- Verification stops for a banner, for a reposition, and for the gap between the
	-- two: a Trial has not started until its pair has been placed, and the wait for a
	-- settling Dummy sits in exactly that gap.
	if m.banner == nil and m.repos == nil and m.setupTrial == m.current then
		verify()
	end

	local counter = trials.elements.trialcounter
	if counter ~= nil then
		-- The Trial on screen, for the same reason the Steps use it: the counter should
		-- not read the next Trial's number over the SUCCESS for the one just finished.
		local shown = m.shownCurrent or m.current
		local text
		if m.total == 0 then
			text = strValue(cfgGet({'trials_mode', 'nodata', 'text'}), '')
		elseif m.allclear then
			-- The counter doubles as where All-Clear is stated once its banner is gone,
			-- which is why the key has always hung off the counter rather than off the
			-- banner. Falls back to the ordinary counter for a config that omits it.
			text = strValue(cfgGet({'trials_mode', 'trialcounter', 'allclear', 'text'}), '')
			if text == '' then
				text = counterText(shown, m.total)
			end
		else
			text = counterText(shown, m.total)
		end
		textImgSetText(counter.TextSpriteData, text)
		textImgDraw(counter.TextSpriteData)
	end

	-- Nothing to time for a character who ships no Trials: that spot on screen says so
	-- through the counter, and a stopwatch beside it would be counting nothing.
	if m.total > 0 then
		-- Both stopwatches stop for a banner and for good on All-Clear, so the time
		-- that finished the set is the time left on screen. They also stop while
		-- paused, which is what makes them a measure of play rather than of wall
		-- clock. A timer the player has switched off still runs — it is the readout
		-- that is hidden, not the clock, so switching it back on mid-match does not
		-- restart it.
		local running = m.banner == nil and not m.allclear and not paused()
		if preferenceEnabled('TotalTimer', true) then
			m.totalTicks = drawTimer(m.totalTicks, trials.elements.totaltrialtimer, running)
		elseif running then
			m.totalTicks = m.totalTicks + 1
		end
		if preferenceEnabled('TrialTimer', true) then
			m.trialTicks = drawTimer(m.trialTicks, trials.elements.currenttrialtimer, running)
		elseif running then
			m.trialTicks = m.trialTicks + 1
		end
	end

	drawTextbox(m)
	drawSteps()
	drawReminder(m)
	drawBanner(m)

	-- The backdrop's front layer, over everything the module has just drawn. A
	-- screenpack puts a frame or a foreground element here the same way it does on any
	-- other screen; nothing is drawn for it unless a [TrialsBg ...] section asks for
	-- layerno 1.
	if trials.background ~= nil then
		bgDraw(trials.background, 1)
	end
end)

--;===========================================================
--; DEBUG
--;===========================================================
-- The module's single test seam: one artifact describing its fully resolved state.
-- Every non-visual assertion reads this file. See the umbrella spec for why there is
-- exactly one of these and not one per concern.
--
-- Written through the module's own serializer rather than main.f_printTable, which
-- produces the same bytes but builds them with `txt = txt .. line` — a copy of
-- everything written so far, once per line. The dump is around half a megabyte, and in
-- the engine's own VM that quadratic growth measures ~150ms. f_dumpState runs on the
-- frame a Trial is completed, so the player wore all of it as a hitch on the hit that
-- closed the Trial out (#58). Buffered, the same dump takes under a millisecond.
--
-- io.open is called here rather than through main.f_fileWrite because that one
-- panicErrors on a missing target directory, which would kill the game rather than
-- skip a debug dump. Erroring instead leaves it to the pcall f_dumpState already has.

-- How many buffer entries one table.concat may span.
--
-- Not a tuning knob: gopher-lua's table.concat pushes every element it joins onto the
-- VM stack, and a dump this size overflows the registry long before it runs out of
-- entries. Joining in bounded blocks and then joining the blocks keeps every individual
-- concat small, and stays linear in total.
local CONCAT_CHUNK = 256

-- Joins buf[1..n] into one string, a block at a time, until one string is left.
local function joinChunked(buf, n)
	while n > 1 do
		local out, on = {}, 0
		for i = 1, n, CONCAT_CHUNK do
			on = on + 1
			out[on] = table.concat(buf, '', i, math.min(i + CONCAT_CHUNK - 1, n))
		end
		buf, n = out, on
	end
	return n == 1 and buf[1] or ''
end

-- Writes `t` to `path` in main.f_printTable's format, byte for byte.
--
-- The format is load-bearing — tools/check-trials-dump.py parses it, including the
-- `*table: 0x…` line that marks a table already printed elsewhere — so every branch
-- below mirrors main.lua:113 exactly. The only difference is where the pieces go: into
-- a buffer that is joined once at the end, rather than onto the end of a string that is
-- copied every time.
local function printTable(t, path)
	local buf, n = {}, 0
	local function put(s)
		n = n + 1
		buf[n] = s
	end
	local printed = {}
	local function walk(t, indent)
		if printed[tostring(t)] then
			put(indent) put('*') put(tostring(t)) put('\n')
			return
		end
		printed[tostring(t)] = true
		if type(t) ~= 'table' then
			put(indent) put(tostring(t)) put('\n')
			return
		end
		for pos, val in pairs(t) do
			local k = (type(pos) == 'string') and ('[' .. string.format('%q', pos) .. ']')
				or ('[' .. tostring(pos) .. ']')
			if type(val) == 'table' then
				put(indent) put(k) put(' => ') put(tostring(val)) put(' {\n')
				walk(val, indent .. string.rep(' ', string.len(k) + 6))
				put(indent) put(string.rep(' ', string.len(k) + 4)) put('}\n')
			elseif type(val) == 'string' then
				put(indent) put(k) put(' => "') put(val) put('"\n')
			else
				put(indent) put(k) put(' => ') put(tostring(val)) put('\n')
			end
		end
	end
	if type(t) == 'table' then
		put(tostring(t)) put(' {\n')
		walk(t, '  ')
		put('}\n')
	else
		walk(t, '  ')
	end
	local file = io.open(path, 'w+')
	if file == nil then
		error("could not open " .. path)
	end
	file:write(joinChunked(buf, n))
	file:close()
end

-- Where the dump lands, and what writes it — both as fields rather than as literals
-- inside f_dumpState, because both are seams. A tool driving this module headlessly
-- points the path somewhere that is not the engine's own dump and swaps the writer for
-- one that keeps the table, which is the only way to assert on resolved state without
-- reparsing half a megabyte of text. Neither is read anywhere else.
trials.dumpPath = 'debug/t_trials.txt'
trials.f_printTable = printTable

-- The parsed Steps of one Trial, flattened into scalars.
--
-- Copied and not referenced: the dump prints a table once and back-references it
-- everywhere else, and these same tables are reachable through `match` — referenced,
-- whichever side printed second would dump as an empty block and every assertion
-- against it would pass by default (#50).
--
-- Lists become strings, which is what makes them assertable at all: `stateno = 200|205`
-- reads as "200|205" here rather than as a nested table that the dump's own
-- back-referencing would then have to be reasoned about.
local function copySteps(steps)
	local function list(v)
		if v == nil then
			return ''
		end
		local parts = {}
		for i, n in ipairs(v) do
			parts[i] = tostring(n)
		end
		return table.concat(parts, '|')
	end
	local out = {}
	for i, step in ipairs(steps) do
		local parts = {}
		for j, part in ipairs(step.parts) do
			parts[j] = {
				stateno = list(part.stateno),
				animno = list(part.animno),
				projid = list(part.projid),
				hitcount = part.hitcount,
				isthrow = part.isthrow,
				iscounterhit = part.iscounterhit,
				ishelper = part.ishelper,
				isproj = part.isproj,
				validfortickcount = part.validfortickcount or -1,
			}
		end
		out[i] = {
			number = step.number,
			text = step.text,
			-- Flattened for the reason the Part lists above are: a list, not a table,
			-- is what makes the tokens assertable without reasoning about which side of
			-- the dump elided. Empty is a Step that declares no Glyphs, which is a
			-- supported Trial Definition and not a parse failure (#3).
			glyphs = table.concat(step.glyphs, '|'),
			glyphCount = #step.glyphs,
			partCount = #step.parts,
			parts = parts,
		}
	end
	return out
end

-- A list of var/value pairs, back in something close to how it was authored:
-- `12=0|2|4, 20=3` for `trial.showforvarvalpairs = 12, 0|2|4, 20, 3`. Empty for a
-- Trial or Step that is not gated at all.
--
-- A string rather than the parsed table, for the reason copySteps flattens its lists:
-- the dump prints a table once and back-references it thereafter, so a nested table is
-- a second path that elides to nothing an assertion would then pass against (#50).
local function varPairsText(gate)
	if gate == nil then
		return ''
	end
	local out = {}
	for i, pair in ipairs(gate) do
		local values = {}
		for j, v in ipairs(pair.values) do
			values[j] = tostring(v)
		end
		out[i] = tostring(pair.var) .. '=' .. table.concat(values, '|')
	end
	return table.concat(out, ', ')
end

-- Which Trials a match is currently offering, by their declared index: `1, 2, 5` for a
-- character whose third and fourth Trials are gated out of this mode (#52). Empty when
-- every declared Trial is gated out, which is the no-data case.
local function availableText(m)
	local out = {}
	for i, trial in ipairs(m.trials) do
		out[i] = tostring(trial.index or i)
	end
	return table.concat(out, ', ')
end

-- The Glyph geometry of one Step block, and what its Anim cache resolved to.
--
-- Counted rather than listed: the cache holds one entry per token the Trials of the
-- selected character use, and how many of them this screenpack knows is the whole of
-- what a dump can say about Glyphs without a screenshot.
local function glyphState(block)
	local gl = block.glyphs
	if gl == nil then
		return nil
	end
	-- One Step Status answers for all three: prepareGlyphs builds every token under
	-- each of them, so the three caches hold the same tokens and differ only in the
	-- palette effect their Anims carry.
	local known, unknown = 0, 0
	for _, a in pairs(gl.anims.current or {}) do
		if a == false then
			unknown = unknown + 1
		else
			known = known + 1
		end
	end
	return {
		offset = gl.offset,
		scale = gl.scale,
		-- Which of the two sizings is in force, and therefore whether `scale` above is
		-- being read at all. A run drawn at the wrong size is one or the other, and on
		-- screen they look identical.
		scalewithtext = gl.scalewithtext,
		spacing = gl.spacing,
		align = gl.align,
		layerno = gl.layerno,
		-- Copied for the reason the block's own localcoord is: it is the same table
		-- its elements carry, and the dump elides a table it has already printed.
		localcoord = {gl.localcoord[1], gl.localcoord[2]},
		known = known,
		unknown = unknown,
	}
end

-- The Step display's graphical layer as it resolved, for the Layout in use.
--
-- Widths and not sprite numbers: what a background element resolved to matters here only
-- inasmuch as it changes where a Step lands, and the width is the number that does. Zero
-- for a piece that was never configured, which is also what an unconfigured Step Status
-- reads as — the two are the same thing on screen and there is nothing to tell apart.
--
-- `art` says which file the block's own background came from, since a screenpack that
-- meant its own sff and got the module's would otherwise show up only as artwork nobody
-- recognises.
local function bgState(block)
	-- Where the block's background came from, or why there is not one. Four answers and
	-- not two, because "no background" has three quite different causes and only one of
	-- them is a choice: a screenpack that styled the Steps with nothing behind them, a
	-- block a screenpack repositioned so the module's own 320x240 artwork was dropped
	-- rather than drawn at the wrong scale (see buildArt), and a trials.sff that failed
	-- to load. On screen all three look identical, so naming them is the whole value.
	local function whichArt()
		local ours = artIsOurs(join(block.path, 'bg'), block.path)
		if block.bg ~= nil then
			return ours and 'module' or 'screenpack'
		end
		if not ours then
			return ''
		end
		if block.foreign then
			return 'dropped: the block was repositioned, so the module\'s own ' ..
				'artwork is in the wrong coordinate space'
		end
		if moduleArtTried and moduleArtSff == nil then
			return 'unavailable: ' .. trials.dir .. 'trials.sff did not load'
		end
		return ''
	end
	local out = {
		block = block.bg ~= nil,
		art = whichArt(),
		-- The panel behind the whole block. nil where no screenpack asked for one, which
		-- is what a stock install gets; its two windows are here because a panel in the
		-- wrong place and a panel that was never configured are the same blank screen.
		-- Copied for the reason every window in this dump is: the pair are frequently
		-- the same table, and the dump elides a table it has already printed.
		overlay = block.overlay ~= nil and {
			col = table.concat(block.overlay.col, ','),
			alpha = table.concat(block.overlay.alpha, ','),
			layerno = block.overlay.layerno,
			window = {block.overlay.window[1], block.overlay.window[2],
				block.overlay.window[3], block.overlay.window[4]},
			windowWithTextbox = {
				block.overlay.windowWithTextbox[1], block.overlay.windowWithTextbox[2],
				block.overlay.windowWithTextbox[3], block.overlay.windowWithTextbox[4]},
			activeWindow = {
				block.overlay.activeWindow[1], block.overlay.activeWindow[2],
				block.overlay.activeWindow[3], block.overlay.activeWindow[4]},
		} or nil,
	}
	for _, status in ipairs(STEP_STATUSES) do
		local bg = block.stepbg ~= nil and block.stepbg[status] or nil
		out[status] = {
			body = bg ~= nil and bg.bodyWidth or 0,
			tail = bg ~= nil and bg.tailWidth or 0,
			head = bg ~= nil and bg.headWidth or 0,
			-- The tint the Step Status draws its background under, flattened the way
			-- copySteps flattens a Part's lists: assertable without reasoning about
			-- which side of the dump elided the table.
			mul = bg ~= nil and table.concat(bg.palfx.mul, ',') or '',
		}
	end
	return out
end

-- The Textbox as it resolved: which of its five elements were configured, where its
-- prose wraps, and where a portrait comes from.
--
-- The prose itself is not here — it belongs to a Trial and is dumped with that Trial, in
-- `chars`. What this answers is the question a blank Textbox actually raises: whether it
-- was never configured, or configured and drawing nothing.
local function textboxState()
	local box = trials.textbox
	if box == nil then
		return nil
	end
	return {
		-- Copied for the reason every other localcoord in this dump is: it is one table
		-- the elements share, and the dump elides a table it has already printed.
		localcoord = {box.title.localcoord[1], box.title.localcoord[2]},
		titleText = box.title.text,
		titlePos = {box.title.pos[1], box.title.pos[2]},
		textPos = {box.text.pos[1], box.text.pos[2]},
		-- The window is doing two jobs — what the prose clips to and what it wraps
		-- inside — so a Textbox whose words run off the edge is diagnosable from here.
		textWindow = {box.text.window[1], box.text.window[2],
			box.text.window[3], box.text.window[4]},
		wrap = box.wrap,
		delay = box.delay,
		spacing = {box.spacing[1], box.spacing[2]},
		bg = box.bg ~= nil,
		front = box.front ~= nil,
		portraitSource = box.portraitSource,
		-- For a system portrait, whether the sprite resolved at all. For a character
		-- one there is nothing to resolve until a match names a character, so this
		-- reports how many have been built rather than a yes or no.
		portrait = box.portraitSource ~= 'char' and (box.portrait ~= nil) or nil,
		portraitsBuilt = box.portraits ~= nil and (function()
			local n = 0
			for _, v in pairs(box.portraits) do
				if v ~= false then n = n + 1 end
			end
			return n
		end)() or nil,
	}
end

-- The pause menu's items in the order the engine resolved them to, as one string. A
-- list, not a table, for the reason copySteps flattens Parts into one: it is what makes
-- an ordering assertable without reasoning about the dump's back-referencing.
local function pauseMenuItems()
	local sec = pauseMenuSection()
	local order = sec ~= nil and sec.menu.itemname_order or nil
	if type(order) ~= 'table' then
		return ''
	end
	return table.concat(order, '|')
end

-- The trials list as the module filled it in, entry by entry. The declared tail — its
-- Back — is named too, since a list that lost it is a list a character with no Trials
-- crashes on.
local function trialsListTitles()
	local sub = trialsListMenu()
	if sub == nil then
		return ''
	end
	local names = {}
	for i, item in ipairs(sub.items) do
		names[i] = item.itemname == TRIALS_ENTRY_ITEM and item.displayname or
			('<' .. item.itemname .. '>')
	end
	return table.concat(names, '|')
end

function trials.f_dumpState()
	if not gameOption('Debug.DumpLuaTables') then
		return
	end
	-- One row per playable character, so "detected / not detected" is assertable
	-- without launching a match.
	local chars = {}
	for _, t in ipairs(main.t_selChars) do
		if t.playable and t.def ~= nil then
			local row = {
				name = t.name,
				def = t.def,
				checked = t.trials ~= nil,
				trialsDef = false,
				trialCount = 0,
			}
			if type(t.trials) == 'table' then
				row.trialsDef = t.trials.def
				row.trialCount = #t.trials
				row.titles = {}
				-- One row per Trial: how many Steps it parsed to, the text of the
				-- first, and whether it carries a Textbox — which is what decides the
				-- window variant its Steps clip to.
				row.trials = {}
				for i, v in ipairs(t.trials) do
					row.titles[i] = v.title
					row.trials[i] = {
						title = v.title,
						stepCount = #v.steps,
						firstStepText = v.steps[1] ~= nil and v.steps[1].text or '',
						textbox = v.textbox ~= '',
						-- The modes this Trial is offered in, as authored: `12=0|2|4`
						-- per pair, comma-separated, and empty for a Trial that is
						-- always offered. Flattened to a string for the reason the
						-- Parts' lists are — a nested table here would be a second
						-- path the dump elides (#50).
						showfor = varPairsText(v.showfor),
						-- The values written to the shared training maps when this
						-- Trial starts, and the words they were resolved from — an
						-- empty word is a Trial that named nothing and took the
						-- default, which is what makes a leak visible here.
						dummy = v.dummy,
						-- Where this Trial stands the pair and what life it starts
						-- them with, resolved as far as a stage-free parse goes.
						positions = v.positions,
						life = v.life,
						-- What each Step actually verifies against, Part by Part.
						-- Copied out rather than referenced, for the same reason the
						-- Dummy settings below are: the dump elides a table it has
						-- already printed, and the parsed Steps are reachable again
						-- through `match` (#50).
						steps = copySteps(v.steps),
					}
				end
			end
			chars[#chars + 1] = row
		end
	end

	-- Element state as applied, since a TextSprite cannot be read back from Lua.
	local elements = {}
	for name, e in pairs(trials.elements) do
		elements[name] = {
			font = e.font,
			pos = e.pos,
			scale = e.scale,
			window = e.window,
			localcoord = e.localcoord,
			layerno = e.layerno,
		}
	end

	local ok, err = pcall(function() trials.f_printTable({
		dir = trials.dir,
		enabled = trials.enabled,
		language = trials.language,
		ini = trials.ini,
		-- Which file each Trials Config layer was read from, in merge order.
		layers = trials.layers,
		-- The resolved Trials Config, and the layer that won each leaf.
		config = trials.config,
		configSource = trials.configSource,
		elements = elements,
		-- The Step block's resolved geometry — the one the Layout preference selected,
		-- since that is the one being drawn. Rows are positioned from these every frame,
		-- so a layout that lands in the wrong place is diagnosable from here without a
		-- screenshot.
		steps = trials.stepblock ~= nil and {
			layout = trials.stepblock.layout,
			spacing = trials.stepblock.spacing,
			padding = trials.stepblock.padding,
			window = trials.stepblock.window,
			windowWithTextbox = trials.stepblock.windowWithTextbox,
			shiftWithTextbox = trials.stepblock.shift,
			-- Copied, not referenced: the dump elides a table it has already
			-- printed, and this one is usually the same table as `window`.
			activeWindow = {
				trials.stepblock.activeWindow[1], trials.stepblock.activeWindow[2],
				trials.stepblock.activeWindow[3], trials.stepblock.activeWindow[4],
			},
			-- Where the Glyphs accompanying a Step sit, and how many of the current
			-- Trial's tokens this screenpack actually has a Glyph for. `unknown` is the
			-- diagnosis a blank run needs: a Trial Definition written against another
			-- screenpack's vocabulary reads as a count here rather than as nothing on
			-- screen.
			glyphs = glyphState(trials.stepblock),
			-- What the Step display's graphical layer resolved to. Its widths are inputs
			-- to the row arithmetic above, so a background that failed to load reads
			-- here as the zero that made every row wrap early.
			bg = bgState(trials.stepblock),
		} or nil,
		chars = chars,
		-- The Textbox as it resolved. Not under `steps`, because it is not the Step
		-- block's: it is one element set both Layouts share, and what it displaces is
		-- decided by whichever Layout is in use rather than the other way round.
		textbox = textboxState(),
		-- The live match: which Trial and Step the player is on, how far through the
		-- current Step's Parts, and what has been completed. Copied scalar by scalar
		-- rather than dumping trials.match wholesale, so nothing here is a second path
		-- to a table printed under `chars` (#50).
		match = trials.match ~= nil and {
			char = trials.match.char,
			def = trials.match.def,
			-- `total` is what the Trial Counter reads and what All-Clear is measured
			-- against: the Trials currently ON OFFER. `declared` is how many the file
			-- spells. The two differ exactly where trial.showforvarvalpairs gated one
			-- out (#52), and a character every Trial of which is gated out reads
			-- total 0 with a non-zero declared — which is what tells that case apart
			-- from a character shipping no Trial Definition at all.
			total = trials.match.total,
			declared = #trials.match.declared,
			-- Whether the pairs have been evaluated for the round yet. False for the
			-- whole of roundState 0, where the character's own variables are not set
			-- and the list is still the unthinned one.
			-- Whether the pairs have been read at all this round, and whether the
			-- reading that stands has been taken — the one at roundState 2, as
			-- against the provisional one during the intro (docs/adr/0003). A
			-- thinner-than-declared offering with the first of these false would be
			-- a list nothing evaluated.
			availableResolved = (trials.match.availableRound or 0) >= 1,
			availableFinal = trials.match.availableRound == 2,
			-- The declared index of each Trial on offer, in the order they are offered.
			-- Flattened for the same reason showfor above is.
			available = availableText(trials.match),
			current = trials.match.current,
			step = trials.match.step,
			stepCount = #trials.match.steps,
			part = trials.match.part,
			partCount = trials.match.steps[trials.match.step] ~= nil
				and #trials.match.steps[trials.match.step].parts or 0,
			partHits = trials.match.partHits,
			combo = trials.match.combo,
			grace = trials.match.grace,
			textbox = trials.match.textbox,
			-- The prose actually on screen, and whether a Textbox is being drawn for it.
			-- Both are the Trial ON SCREEN, which across a Success is the finished one
			-- rather than the one the match has moved on to — and f_dumpState runs from
			-- completeTrial, which is inside exactly that lag. Anything comparing the two
			-- has to compare these with each other and not with `textbox` above, which is
			-- the match's Trial and legitimately a different one.
			shownTextbox = trials.match.shownTextbox == true,
			shownText = trials.match.shownText or '',
			completedCount = trials.match.completedCount,
			allclear = trials.match.allclear,
			banner = trials.match.banner or '',
			totalTicks = trials.match.totalTicks,
			trialTicks = trials.match.trialTicks,
			-- The Trial on screen, which lags the one the match is on across a Success
			-- (see syncDisplay). Dumped because "the wrong Trial is drawn" and "the
			-- wrong Trial is being played" look identical in a screenshot.
			shownTrial = trials.match.shownCurrent or trials.match.current,
			shownComplete = trials.match.shownComplete == true,
			-- The Step drawn on a held Trial, which across a pause-menu jump is the one
			-- the player actually reached rather than the reset one the match is on. 0
			-- on every ordinary frame, where the two are the same thing.
			shownStep = trials.match.shownStep or 0,
			advancement = autoAdvances() and 'autoadvance' or 'repeat',
			resetOnSuccess = preferenceEnabled('ResetOnSuccess', true),
			layout = tostring(preference('Layout', 'vertical')):lower(),
			textboxes = textboxesVisible() and 'show' or 'hide',
			totalTimer = preferenceEnabled('TotalTimer', true),
			trialTimer = preferenceEnabled('TrialTimer', true),
			-- Latched by a mid-Trial reposition and by Reset on Success, and cleared when
			-- the pair is placed. What tells "the preference is off" apart from "it is on
			-- and the placement has already happened".
			reposRequest = trials.match.reposRequest == true,
			-- Set by a Success while Reset on Success is off, and cleared when the Trial
			-- is taken on. What tells "waiting to be taken on in place" apart from
			-- "waiting to be placed".
			adoptPending = trials.match.adoptTrial ~= nil,
		} or nil,
		-- The pause menu as registered. Which items the section resolved to, and in what
		-- order, is what a screenpack edit and the legacy fold both change — and neither
		-- is visible anywhere else without a person watching the menu.
		pauseMenu = {
			registered = pauseMenuSection() ~= nil,
			items = pauseMenuItems(),
			legacy = trials.legacyPauseMenu,
			-- The trials list as filled in for the match, which is the one part of the
			-- menu the module builds rather than the engine.
			list = trialsListTitles(),
		},
		-- What is actually in the shared training maps, and the Trial it came from.
		--
		-- Copied scalar by scalar, not referenced: the dump elides a table it has
		-- already printed, and this is the very same table as that Trial's settings
		-- under `chars` above — referenced, it would dump as an empty block and every
		-- assertion against it would pass by default.
		dummyWritten = trials.match ~= nil and trials.match.dummy ~= nil and {
			trial = trials.match.dummyTrial,
			mode = trials.match.dummy.mode,
			guard = trials.match.dummy.guard,
			buttonjam = trials.match.dummy.buttonjam,
			authored = {
				mode = trials.match.dummy.authored.mode,
				guard = trials.match.dummy.authored.guard,
				buttonjam = trials.match.dummy.authored.buttonjam,
			},
		} or nil,
		-- What was actually written to the reposition and life maps, and the Trial it
		-- came from. Copied scalar by scalar rather than referenced, for the reason
		-- dummyWritten is: this is the same data as that Trial's `positions` and `life`
		-- under `chars` above, and the dump elides a table it has already printed.
		setupWritten = trials.match ~= nil and trials.match.setup ~= nil and {
			trial = trials.match.setup.trial,
			corner = trials.match.setup.corner,
			cornered = trials.match.setup.cornered,
			gap = trials.match.setup.gap,
			playerx = trials.match.setup.playerx,
			playery = trials.match.setup.playery,
			dummyx = trials.match.setup.dummyx,
			dummyy = trials.match.setup.dummyy,
			camerax = trials.match.setup.camerax,
			playerlife = trials.match.setup.playerlife,
			dummylife = trials.match.setup.dummylife,
			-- Whether the pair was actually moved there. False is a Trial taken on with
			-- Reset on Success off: the positions above are the ones it resolved to and
			-- deliberately did not use.
			placed = trials.match.setup.placed == true,
		} or nil,
		-- The mode's own backdrop. Three answers and not two: no [TrialsBgDef] anywhere
		-- (the stock install), one found and parsed, and one found that failed to parse
		-- — which on screen is the same nothing as the first.
		background = {
			def = trials.backgroundDef or '',
			-- Both, because a spr that resolves and one that does not are the same
			-- backdrop on screen: `spr` is what the section asked for, `sprResolved` is
			-- what searchFile found. Asked-for with nothing resolved is a typo.
			spr = trials.backgroundSpr or '',
			sprResolved = trials.backgroundSprResolved or '',
			declared = trials.backgroundDef ~= nil,
			loaded = trials.background ~= nil,
		},
		-- The select-screen effect, flattened the way copySteps flattens a Part's lists:
		-- assertable without reasoning about which side of the dump elided the table.
		-- `applied` is a live count and reads 0 outside the select screen, which is
		-- where a startup dump is written from.
		selectPalFX = trials.selectpalfx ~= nil and {
			add = table.concat(trials.selectpalfx.fx.add, ','),
			mul = table.concat(trials.selectpalfx.fx.mul, ','),
			sinadd = table.concat(trials.selectpalfx.fx.sinadd, ','),
			invertall = trials.selectpalfx.fx.invertall,
			color = trials.selectpalfx.fx.color,
			applied = (function()
				local n = 0
				for _ in pairs(trials.selectpalfx.applied) do n = n + 1 end
				return n
			end)(),
		} or nil,
		-- The mid-Trial reposition, as configured and as it stands. `phase` is empty
		-- unless a fade is running, which is the one part of this a startup dump
		-- cannot show.
		reposition = trials.reposition ~= nil and {
			enabled = trials.reposition.enabled,
			keys = table.concat(trials.reposition.keys, '+'),
			keyCount = #trials.reposition.keys,
			fadeout = trials.reposition.fadeoutTime,
			fadein = trials.reposition.fadeinTime,
			-- Whether an animation layer actually resolved onto each end of the fade.
			-- A `spr` naming a sprite the file has none of still fades, silently, and
			-- this is what tells that apart from a fade nobody asked to animate.
			fadeoutAnim = trials.reposition.fadeoutAnim == true,
			fadeinAnim = trials.reposition.fadeinAnim == true,
			reminder = trials.elements.trialresetreminder ~= nil
				and trials.elements.trialresetreminder.text or '',
			phase = trials.match ~= nil and trials.match.repos or '',
		} or nil,
		-- Which extension points the module actually registered. Cheaper to assert
		-- than to infer from behaviour, and it catches a hook silently not attaching.
		hooks = {
			launchFight = hook.lists['launchFight'] ~= nil
				and hook.lists['launchFight']['trials'] ~= nil,
			loop = hook.lists['loop#trials'] ~= nil
				and hook.lists['loop#trials']['trials'] ~= nil,
			addCharFiles = hook.lists['main.f_addChar.files'] ~= nil
				and hook.lists['main.f_addChar.files']['trials'] ~= nil,
			selectScreen = hook.lists['start.f_selectScreen'] ~= nil
				and hook.lists['start.f_selectScreen']['trials'] ~= nil,
			pauseMenuLoop = hook.lists['menu.menu.loop'] ~= nil
				and hook.lists['menu.menu.loop']['trials'] ~= nil,
		},
		-- Resolved on disk, so a mistyped path in config.ini shows up here rather
		-- than as a silently absent state file at match start.
		zssPath = normalizePath((trials.ini.Common or {}).States or ''),
	}, trials.dumpPath) end)
	if not ok then
		print('Trials: could not write debug dump (' .. tostring(err) .. ')')
	end
end

trials.f_dumpState()

return trials
