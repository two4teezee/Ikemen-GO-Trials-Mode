-- ikemenversion: 1.0
--;===========================================================
--; TRIALS MODE
--;===========================================================
-- Universal trials module for Ikemen GO.
--
-- All module state lives in the local `trials` table below. Globals are touched only
-- at documented extension points: main.t_itemname.trials; the loop#trials, launchFight,
-- main.f_addChar.files and menu.menu.loop hooks; and the three pause-menu tables the
-- engine documents as appendable by an external module — menu.t_itemname,
-- menu.t_valuename and menu.t_vardisplay (menu.lua:8, :92, :338). Nothing is installed
-- onto `start`, and nothing on `menu` beyond those tables: that coupling is what made
-- the previous version unrecoverable across an engine update.
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
		return nil, 'file not found: ' .. tostring(path)
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
	-- table with, and f_printTable elides a table it has already printed, so the second
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
	geo.TextSpriteData = ts
	return geo
end

-- AnimationProperties -> Anim.
--
-- The `anim = N` branch is written the way the engine writes it, and will not fire on
-- a stock build: `AnimationTable`'s only fields are unexported, so the reflection in
-- toLValue hands Lua an empty `motif.AnimTable` and a screenpack's [Begin Action N] is
-- unreachable from a pure-Lua module. `spr = group, index` against an Sff is the route
-- that works, and is what the slices drawing anims (#42, #43, #44) should plan on. The
-- branch stays so that a build which does expose the table gets the engine's own
-- priority order for free.
local function buildAnim(path, sff, origin)
	local g = elementReader(path, origin)
	local geo = elementGeometry(g, path, origin)
	local anim = tonumber(g('anim'))
	local spr = numList(g('spr'), {-1, 0})

	local a = nil
	if anim ~= nil and anim >= 0 and type(motif.AnimTable) == 'table' and motif.AnimTable[anim] ~= nil then
		a = animNew(sff, motif.AnimTable[anim])
	elseif spr[1] >= 0 then
		a = animNew(sff, spr[1] .. ',' .. spr[2] .. ', 0,0, -1')
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

	-- Trials keeps its own key here: the engine has no per-element display time.
	geo.displaytime = numList(g('displaytime'), {-1})[1]
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

-- Exposed so the slices that add drawn elements build them the same way this one does,
-- rather than growing a second construction path: #37 and #41 (Step text), #42
-- (Glyphs), #43 (Textbox portraits and backgrounds), #44 (overlays and fades).
trials.f_buildText = buildText
trials.f_buildAnim = buildAnim
trials.f_buildOverlay = buildOverlay

trials.elements = {}

-- Where a Step sits relative to the player's progress. Each is styled independently,
-- from its own configuration block, and is one text element built once at load.
local STEP_STATUSES = {'upcoming', 'current', 'completed'}

-- Only the vertical Layout exists today. #41 adds the horizontal one along with the
-- branch that picks between them; until it lands, reading the Layout Player Preference
-- here would leave a player whose config.ini says `horizontal` with no Steps at all.
local STEP_LAYOUT = 'vertical'

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

-- One end of the reposition fade. Its animation layer arrives with the rest of the
-- presentation layer (#44); time and colour are the whole of it for now, and a time of
-- 0 means no fade at all, which fadeNew already treats as nothing to run.
local function buildFade(name)
	local col = numList(cfgGet({'trials_mode', name, 'col'}), {0, 0, 0})
	return fadeNew({
		time = math.max(0, numList(cfgGet({'trials_mode', name, 'time'}), {0})[1]),
		color = {col[1] or 0, col[2] or 0, col[3] or 0},
	})
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
	trials.stepblock = buildStepBlock(STEP_LAYOUT)
	-- Everything the mid-Trial reposition needs, resolved once. `keys` empty, or
	-- enabled false, is the feature switched off.
	trials.reposition = {
		-- On unless the config says otherwise. loadIni hands `false` back as a Lua
		-- boolean, and a screenpack writing the word is just as clear.
		enabled = not (cfgGet({'trials_mode', 'trialresetenabled'}) == false
			or strValue(cfgGet({'trials_mode', 'trialresetenabled'}), ''):lower() == 'false'),
		keys = repositionKeys(),
		fadeout = buildFade('fadeout'),
		fadein = buildFade('fadein'),
		fadeoutTime = math.max(0, numList(cfgGet({'trials_mode', 'fadeout', 'time'}), {0})[1]),
		fadeinTime = math.max(0, numList(cfgGet({'trials_mode', 'fadein', 'time'}), {0})[1]),
	}
end

--;===========================================================
--; TRIAL DEFINITION DISCOVERY
--;===========================================================

-- loadIni returns sections in a Lua table keyed by name, and a Lua table has no order,
-- so the authored Trial order cannot be recovered from it. Scan the file for its
-- section headers to get that back; every value still comes from loadIni.
--
-- The names have to come out byte-identical to loadIni's keys or the lookup misses, so
-- this reproduces go-ini's own rule rather than a tidier one: a header runs from the
-- opening bracket to the *last* closing bracket on the line, trimmed. That is why the
-- capture is greedy. A trailing `;comment` is therefore only dropped when it contains
-- no bracket of its own — which is exactly what go-ini does, and what the engine would
-- see for the same file.
local function sectionOrder(path)
	local ok, text = pcall(loadText, path)
	if not ok or type(text) ~= 'string' then
		return {}
	end
	local out = {}
	for line in text:gmatch('[^\r\n]+') do
		local name = line:match('^%s*%[(.*)%]')
		if name ~= nil then
			name = name:match('^%s*(.-)%s*$')
			if name ~= '' then
				table.insert(out, name)
			end
		end
	end
	return out
end

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
	'stateno', 'animno', 'hitcount',
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

-- trialstep.X.validforvarvalpairs = 12, 0|2|4 — a character variable and the values it
-- may hold, in pairs, all of which must hold for the Step to verify. Per Step and not
-- per Part, which is what the format documents.
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

-- The Steps of one Trial, in Step-number order, each with its Parts resolved.
--
-- loadIni splits `trialstep.1.text` into nested tables keyed by the literal string
-- '1' (setNestedLuaKey, src/script.go:450), so the list is a Lua hash and not an
-- array — # would report 0 and ipairs would stop immediately. Rebuild it by number.
local function readSteps(data)
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
			parts = parts,
			-- Gates the whole Step rather than one of its Parts, so it sits here.
			validfor = readVarPairs(step.validforvarvalpairs),
		}
	end
	return steps
end

-- Parses a Trial Definition into its Trials, in the order the author wrote them.
--
-- normalizeSections stays off so [TrialDef, <name>] survives and the title stays
-- readable; keepMeta is on for __order, which is what later slices read Steps back in
-- authored order with. go-ini merges same-named sections, so a duplicate Trial title
-- collapses into one section rather than being silently dropped — warn and keep the
-- first.
local function readTrialDefinition(path)
	local ini, err = safeLoadIni(path, false, true)
	if ini == nil then
		return nil, err
	end
	local list = {}
	local seen = {}
	for _, name in ipairs(sectionOrder(path)) do
		if name:lower():match('^trialdef') and ini[name] ~= nil then
			if seen[name] then
				print('Trials: duplicate Trial "' .. name .. '" in ' .. path .. ' — keeping the first.')
			else
				seen[name] = true
				-- Lowercased for the same reason Trials Config is: go-ini keeps key
				-- case as authored and the pre-refactor parser lowercased everything
				-- it read, so `TrialStep.1.Text` has always resolved.
				local data = lowerKeys(ini[name])
				table.insert(list, {
					section = name,
					title = trialTitle(name),
					-- Read here rather than at draw time so a Trial's Textbox is known
					-- before the first frame: it decides which window variant the Step
					-- block clips to. Drawing the Textbox itself is #43.
					textbox = strValue(localized(type(data.trial) == 'table' and data.trial.textbox or nil), ''),
					steps = readSteps(data),
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
					-- The section as parsed, kept for the keys no slice reads yet:
					-- trialstep.X.glyphs and showforvarvalpairs. Nothing on the
					-- per-frame path touches it.
					data = data,
				})
			end
		end
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
	local rel = def.files.trials
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
		trials = {}, total = 0, current = 1, steps = {}, textbox = false, char = nil,
		-- Progress. `step` and `part` are where the player is; `combo` is comboCount()
		-- as of the last Part completed, which is what makes the next hit tell itself
		-- apart from the one that has already been counted.
		step = 1, part = 1, combo = 0, partHits = 0, partCombo = 0, grace = 0,
		-- Which Trials have been completed at least once, and how many that is.
		-- All-Clear is the moment that count reaches the total (CONTEXT.md), which is
		-- not the same as walking off the end of the list.
		completed = {}, completedCount = 0, allclear = false,
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
			if type(char.trials) == 'table' then
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
	if trials.stepblock ~= nil then
		applyStepWindow(trials.stepblock, m.textbox)
	end
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
local function selectTrial(index)
	local m = trials.match
	m.current = index
	local trial = m.trials[index]
	m.steps = type(trial) == 'table' and trial.steps or {}
	m.textbox = trialTextbox(m, index)
	resetProgress(m)
	m.trialTicks = 0
	-- Nothing on screen changes yet while a banner is up: syncDisplay runs when the pair
	-- is placed. Selecting a Trial with nothing in the way — the start of a match, a
	-- Trial picked out of a menu — shows it at once.
	if m.banner == nil then
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
-- Layout is here and does nothing visible yet, on purpose: only the vertical Layout
-- exists (STEP_LAYOUT above), and #41 adds the horizontal one along with the branch that
-- picks between them. The setting persists in the meantime, so a player who switched it
-- before that lands finds it switched afterwards.
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
		m.shownTextbox = m.textbox
		if trials.stepblock ~= nil then
			applyStepWindow(trials.stepblock, m.textbox)
		end
	end
end

-- Advancement, Reset on Success and Layout are read where they are used, so changing one
-- needs nothing beyond persisting it. The Textbox preference is the exception, and the
-- exception lives on the descriptor rather than as a name test inside the shared handler.
MENU_PREFERENCE.trialstextboxes.changed = refreshTextbox

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
	selectTrial(index)
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

-- The match and the Trial the menu was last caught up with.
local menuMatch, menuTrial = nil, nil

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
		menuMatch, menuTrial = m, nil
		syncPreferenceIndices()
		for _, item in ipairs(menu.t_vardisplayPointers or {}) do
			if MENU_PREFERENCE[item.itemname] ~= nil then
				item.vardisplay = menu.f_vardisplay(item.itemname)
			end
		end
	end
	if menuTrial ~= m.current then
		menuTrial = m.current
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
	-- Life is the exception: trials.zss reads the map in each character's own life
	-- recovery block, so one map name carries both totals and each side gets its own.
	-- 0 is the map's word for lifeMax.
	--
	-- Set as well as pinned, because the map only takes effect on the next recovery
	-- tick — up to a second later, with the Trial already begun at the wrong life.
	mapSet('_iksys_trialsSetLife', life.dummy)
	setLifeNow(life.dummy)
	mapSet('_iksys_trialsReposition', 1)
	-- Back on the Trials player, which is both where the player's own life is written
	-- and where everything downstream expects the redirect to be. Unconditional, the
	-- way applyDummy's is: leaving the redirect on the Dummy would hand every
	-- redirectable trigger the loop reaches after this the wrong character.
	player(1)
	mapSet('_iksys_trialsSetLife', life.player)
	setLifeNow(life.player)

	-- What actually reached the two characters, recorded for the same reason the Dummy
	-- settings are: a Trial's positions are resolved at load and written many seconds
	-- later, and a dump taken before this point cannot tell the two apart.
	m.setupTrial = m.current
	m.reposRequest = false
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
		return
	end

	if m.repos == 'out' then
		if not fadeActive() then
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
	if m.setupTrial == m.current and not m.reposRequest then
		m.settleWait = 0
		return
	end
	-- Something wants the pair moved. It waits for the Dummy to be worth moving.
	if not dummySettled() and (m.settleWait or 0) < SETTLE_LIMIT then
		m.settleWait = (m.settleWait or 0) + 1
		return
	end
	m.settleWait = 0
	-- The first placement of a round goes straight in: there is nothing on screen yet
	-- to fade away from, and the round's own fade already covers it.
	if m.setupTrial ~= nil and fadesReposition() then
		m.repos = 'out'
		if trials.reposition.fadeoutTime > 0 then
			fadeOutInit(trials.reposition.fadeout)
		end
		return
	end
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
-- A Step can name a state belonging to the player, to one of its helpers, or to a
-- projectile, and only the player's own is readable directly. The rest comes off the
-- Dummy's hit variables — they describe the character that was *hit*, so they are read
-- through the P2 redirect: getHitVar('playerid') names whoever landed the hit, and
-- getHitVar('projid') is non-negative when it was a projectile, in which case there is
-- no state to compare against and the projectile's anim is what identifies it.
--
-- Returns empty fields on a frame with no hit, which read as "matches nothing" rather
-- than as "matches anything".
local function readAttacker()
	local out = {stateno = nil, anim = nil}
	if not player(2) then
		return out
	end
	if getHitVar('frame') then
		local id = getHitVar('playerid')
		local projid = getHitVar('projid')
		if projid >= 0 then
			if playerId(id) then
				-- A projectile with the usual remove = 1 is destroyed on the tick it
				-- connects, before this runs, and the engine hands back something that is
				-- not a number when it has none to read. Keep only a number.
				out.anim = tonumber(projVar(projid, 0, 'anim'))
			end
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

-- Every character variable a Step is gated on holds its declared value.
-- trialstep.X.validforvarvalpairs gates the whole Step, not one of its Parts.
local function varPairsHold(step)
	if step.validfor == nil then
		return true
	end
	for _, pair in ipairs(step.validfor) do
		if not satisfies(pair.values, var(pair.var), nil) then
			return false
		end
	end
	return true
end

-- Whether the current Part registered this frame.
--
-- Three routes, one per kind of Step the format spells:
--
--   - a helper or projectile Part passes on state and animation alone. The hit it
--     produces is not the player's own, so there is no moveHit to wait for.
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
	if not varPairsHold(step) then
		return false
	end
	-- A counter-hit Part only counts when the engine says the hit countered. Tested
	-- here, before the hit count below has taken anything from it, so an ordinary hit
	-- leaves the Part exactly where it was rather than half-counted.
	if part.iscounterhit and part.hitcount ~= 0
		and not (comboCount() > 0 and moveCountered() > 0) then
		return false
	end
	if part.ishelper or part.isproj then
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
	if not m.completed[index] then
		m.completed[index] = true
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
	-- Reset on Success. applySetup places the pair when the Trial it last placed is no
	-- longer the one the match is on, which covers every move to a *different* Trial and
	-- nothing else — so Advancement = repeat, and the All-Clear that stays on the Trial
	-- finishing the set, both leave the pair wherever the combo carried them. Latching
	-- the request the mid-Trial combination latches puts them back through the machinery
	-- already there: the banner wait, the settled-Dummy wait, the fade, the camera and
	-- the display lag all belong to it and none of them change.
	--
	-- Deliberately unconditional on whether the Trial changed. Where it did, applySetup
	-- was going to place the pair anyway and the request costs nothing; where it did not,
	-- this is the only thing that will.
	if preferenceEnabled('ResetOnSuccess', true) then
		m.reposRequest = true
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

-- The Steps of the current Trial, drawn in the vertical Layout.
--
-- Rows lay out from the block's origin, one spacing apart, each drawn with the element
-- for the Step Status it currently has — so advancing the Step index is all it takes
-- for a row to move from upcoming to current to completed.
--
-- Nothing is constructed here. Each row is the engine's own list idiom
-- (main.f_drawMenu, main.lua:3811): reset the element to the position it was built at,
-- add the row's offset, set the text, draw.
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
	local textbox = m.shownTextbox
	local step = m.shownComplete and #steps + 1 or m.step
	if #steps == 0 then
		return
	end

	local spacing = block.spacing
	local shift = textbox and block.shift or {0, 0}
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
		local status = 'upcoming'
		if i < step then
			status = 'completed'
		elseif i == step then
			status = 'current'
		end
		local ts = block.text[status].TextSpriteData
		textImgReset(ts)
		textImgAddPos(ts, shift[1] + spacing[1] * (i - first), shift[2] + spacing[2] * (i - first))
		textImgSetText(ts, steps[i].text)
		textImgDraw(ts)
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
		selectTrial(trials.match.current)
		trials.f_dumpState()
	end
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

	drawSteps()
	drawReminder(m)
	drawBanner(m)
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
-- The parsed Steps of one Trial, flattened into scalars.
--
-- Copied and not referenced: f_printTable prints a table once and back-references it
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
			partCount = #step.parts,
			parts = parts,
		}
	end
	return out
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
						-- Dummy settings below are: f_printTable elides a table it has
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

	local ok, err = pcall(function() main.f_printTable({
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
		-- The Step block's resolved geometry. Rows are positioned from these every
		-- frame, so a layout that lands in the wrong place is diagnosable from here
		-- without a screenshot.
		steps = trials.stepblock ~= nil and {
			layout = trials.stepblock.layout,
			spacing = trials.stepblock.spacing,
			window = trials.stepblock.window,
			windowWithTextbox = trials.stepblock.windowWithTextbox,
			shiftWithTextbox = trials.stepblock.shift,
			-- Copied, not referenced: f_printTable elides a table it has already
			-- printed, and this one is usually the same table as `window`.
			activeWindow = {
				trials.stepblock.activeWindow[1], trials.stepblock.activeWindow[2],
				trials.stepblock.activeWindow[3], trials.stepblock.activeWindow[4],
			},
		} or nil,
		chars = chars,
		-- The live match: which Trial and Step the player is on, how far through the
		-- current Step's Parts, and what has been completed. Copied scalar by scalar
		-- rather than dumping trials.match wholesale, so nothing here is a second path
		-- to a table printed under `chars` (#50).
		match = trials.match ~= nil and {
			char = trials.match.char,
			def = trials.match.def,
			total = trials.match.total,
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
		-- Copied scalar by scalar, not referenced: f_printTable elides a table it has
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
		-- under `chars` above, and f_printTable elides a table it has already printed.
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
			pauseMenuLoop = hook.lists['menu.menu.loop'] ~= nil
				and hook.lists['menu.menu.loop']['trials'] ~= nil,
		},
		-- Resolved on disk, so a mistyped path in config.ini shows up here rather
		-- than as a silently absent state file at match start.
		zssPath = normalizePath((trials.ini.Common or {}).States or ''),
	}, 'debug/t_trials.txt') end)
	if not ok then
		print('Trials: could not write debug dump (' .. tostring(err) .. ')')
	end
end

trials.f_dumpState()

return trials
