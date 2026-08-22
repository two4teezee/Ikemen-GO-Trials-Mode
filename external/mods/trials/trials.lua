-- ikemenversion: 1.0
--;===========================================================
--; TRIALS MODE
--;===========================================================
-- Universal trials module for Ikemen GO.
--
-- All module state lives in the local `trials` table below. Globals are touched only
-- at documented extension points: main.t_itemname.trials, and the loop#trials,
-- launchFight and main.f_addChar.files hooks. Nothing is installed onto `start` or
-- `menu` — that coupling is what made the previous version unrecoverable across an
-- engine update.
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
				dst[k] = {}
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

-- Which layer supplied one of an element's keys, or nil if none did.
local function sourceOf(path, key)
	return trials.configSource[table.concat(path, '.') .. '.' .. key]
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
local function sharedLocalcoord(path, own, ownSource)
	local screen = {motif.info.localcoord[1], motif.info.localcoord[2]}

	-- Whose coordinates are these? A position the module shipped is written in the
	-- module's space; one a screenpack wrote is written in the screenpack's. Nothing
	-- else distinguishes them — an existing integration sets `trialcounter.pos` and no
	-- localcoord at all, and so does this module, so the *absence* of a localcoord
	-- means two different things depending on who left it out.
	local posSource = sourceOf(path, 'pos')
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
	return fallback
end

-- Shared prelude for every element: the geometry keys the three property structs have
-- in common, resolved once so the mappers below read as the setter chain they are.
local function elementGeometry(g, path)
	local lc = sharedLocalcoord(path, g('localcoord'), sourceOf(path, 'localcoord'))
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
local function elementReader(path)
	return function(...)
		return cfgGet(join(path, ...))
	end
end

-- TextProperties -> TextSprite.
local function buildText(path)
	local g = elementReader(path)
	local font = numList(g('font'), {-1, 0, 0, 255, 255, 255, 255, -1})
	-- Trials has always spelled the font height as its own key; the engine puts it in
	-- the 8th font slot. The dedicated key wins when both are present.
	font[8] = tonumber(g('font', 'height')) or font[8]
	local geo = elementGeometry(g, path)

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
local function buildAnim(path, sff)
	local g = elementReader(path)
	local geo = elementGeometry(g, path)
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
local function buildOverlay(path)
	local g = elementReader(path)
	local geo = elementGeometry(g, path)
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

if trials.enabled then
	trials.elements.trialcounter = buildText({'trials_mode', 'trialcounter'})
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
				table.insert(list, {
					section = name,
					title = trialTitle(name),
					data = ini[name],
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
	local m = {trials = {}, total = 0, current = 1, char = nil}
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

-- Runs once per frame during a Trials match, from the engine's Common.Lua `loop()`
-- (debug.lua:230). Sets text and draws — nothing is constructed here.
hook.add('loop#trials', 'trials', function()
	if not trials.enabled then
		return
	end
	if trials.match == nil then
		trials.match = resolveMatch()
		trials.f_dumpState()
	end
	if roundState() ~= 2 then
		return
	end
	local counter = trials.elements.trialcounter
	if counter == nil then
		return
	end
	if trials.match.total > 0 then
		textImgSetText(counter.TextSpriteData, counterText(trials.match.current, trials.match.total))
	else
		textImgSetText(counter.TextSpriteData, strValue(cfgGet({'trials_mode', 'nodata', 'text'}), ''))
	end
	textImgDraw(counter.TextSpriteData)
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
				for i, v in ipairs(t.trials) do
					row.titles[i] = v.title
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
		chars = chars,
		match = trials.match,
		-- Which extension points the module actually registered. Cheaper to assert
		-- than to infer from behaviour, and it catches a hook silently not attaching.
		hooks = {
			launchFight = hook.lists['launchFight'] ~= nil
				and hook.lists['launchFight']['trials'] ~= nil,
			loop = hook.lists['loop#trials'] ~= nil
				and hook.lists['loop#trials']['trials'] ~= nil,
			addCharFiles = hook.lists['main.f_addChar.files'] ~= nil
				and hook.lists['main.f_addChar.files']['trials'] ~= nil,
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
