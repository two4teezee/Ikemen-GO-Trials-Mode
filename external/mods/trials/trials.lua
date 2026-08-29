-- ikemenversion: 1.0
--;===========================================================
--; TRIALS MODE
--;===========================================================
-- Universal trials module for Ikemen GO.
-- Config model: docs/adr/0001. Dummy namespace: docs/adr/0002. Vocabulary: CONTEXT.md.

local trials = {}

trials.dir = 'external/mods/trials/'
trials.sections = {'trials_mode', 'trialsbgdef'}

--;===========================================================
--; PATHS AND CONFIGURATION
--;===========================================================
local function normalizePath(path)
	if type(path) ~= 'string' or path == '' then
		return ''
	end
	return searchFile(path, {'', trials.dir, motif.def, 'data/'})
end

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

local function mergeLayer(dst, src, layer, source, prefix)
	for k, v in pairs(src) do
		local path = prefix == '' and k or (prefix .. '.' .. k)
		if k == '__order' then
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
				dst[k] = dst[k] ~= nil and {__value = dst[k]} or {}
			end
			if v[1] ~= nil then
				source[path] = layer
			end
			mergeLayer(dst[k], v, layer, source, path)
		elseif type(dst[k]) == 'table' and not isValueList(dst[k]) then
			dst[k].__value = v
			source[path] = layer
		else
			dst[k] = v
			source[path] = layer
		end
	end
end

local aliases = {
	trials_mode = {
		{from = {'trialcounter', 'notrialsdata', 'text'}, to = {'nodata', 'text'}},
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
addLayer('config.ini', trials.configPath, false)
addLayer('screenpack', gameOption('Config.Motif'), false)

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

trials.config = {}
trials.configSource = {}

for _, section in ipairs(trials.sections) do
	trials.config[section] = {}
	for _, layer in ipairs(layers) do
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

-- Reads one Trials Config value by its dotted path.
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

-- Coerces a Trials Config value into a boolean, or `default` where it is unrecognised.
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
local function resolveFont(raw, font)
	local first = raw
	if type(raw) == 'table' then
		first = raw[1]
	end
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
local function sourceOf(path, key, origin)
	local own = trials.configSource[table.concat(path, '.') .. '.' .. key]
	if own ~= nil or origin == nil then
		return own
	end
	return trials.configSource[table.concat(origin, '.') .. '.' .. key]
end

local MODULE_LOCALCOORD = {320, 240}

local function sharedLocalcoord(path, own, ownSource, origin)
	local screen = {motif.info.localcoord[1], motif.info.localcoord[2]}
	local posSource = sourceOf(path, 'pos', origin)
	local ours = posSource == nil or posSource == 'defaults'
	local fallback = ours and MODULE_LOCALCOORD or screen

	if ownSource ~= nil and (ownSource ~= 'defaults' or ours) then
		return numList(own, fallback)
	end
	local sharedSource = trials.configSource['trials_mode.trials.localcoord']
	if sharedSource ~= nil and (sharedSource ~= 'defaults' or ours) then
		return numList(cfgGet({'trials_mode', 'trials', 'localcoord'}), fallback)
	end
	return {fallback[1], fallback[2]}
end

-- The geometry keys the three property structs share, resolved once.
local function elementGeometry(g, path, origin)
	local lc = sharedLocalcoord(path, g('localcoord'), sourceOf(path, 'localcoord', origin), origin)
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
		layerno = numList(g('layerno'), {0})[1],
	}
end

-- Returns a getter reading one element's keys out of the resolved Trials Config.
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
	font[8] = tonumber(g('font', 'height')) or font[8]
	local geo = elementGeometry(g, path, origin)

	local ts = textImgNew()
	local fnt = resolveFont(g('font'), font)
	if fnt ~= nil then
		textImgSetFont(ts, fnt)
	else
		print('Trials: ' .. table.concat(path, '.') .. '.font names no font this ' ..
			'screenpack has, so this element draws no text. Give it a font index from ' ..
			'the screenpack\'s [Files], e.g. font = 1, 0, 1.')
	end
	textImgSetBank(ts, font[2])
	textImgSetAlign(ts, font[3])
	textImgSetColor(ts, font[4], font[5], font[6], font[7])
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
	geo.fontdef = fnt ~= nil and fontGetDef(fnt) or nil
	geo.TextSpriteData = ts
	return geo
end

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

-- Whether an element's artwork is this module's or the screenpack's, by who wrote the key.
local function artIsOurs(path, origin)
	local src = sourceOf(path, 'anim', origin) or sourceOf(path, 'spr', origin)
	return src == nil or src == 'defaults'
end

-- One drawn element, built against whichever artwork its keys named.
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
	if sourceOf(path, 'spr', origin) == nil or sourceOf(path, 'spr', origin) == 'defaults' then
		print('Trials: ' .. table.concat(path, '.') .. '.anim names an action, and a ' ..
			'screenpack\'s actions cannot be reached from a Lua module. Spell it as ' ..
			'spr = group, index instead. Nothing is drawn for this element.')
		return nil
	end
	return buildAnim(path, motif.Sff, origin, frametime)
end

trials.f_buildText = buildText
trials.f_buildAnim = buildAnim
trials.f_buildArt = buildArt
trials.f_buildOverlay = buildOverlay

trials.elements = {}

local STEP_STATUSES = {'upcoming', 'current', 'completed'}

local STEP_LAYOUTS = {'vertical', 'horizontal'}

-- A palette effect, in the shape animSetPalFX takes.
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
local function buildStepBg(layout, status, origin, foreign)
	local path = {'trials_mode', status .. 'step', layout, 'bg'}
	local bg = {path = path, palfx = readPalFX(join(path, 'palfx'))}
	bg.body = buildArt(path, origin, foreign)
	if layout == 'horizontal' then
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

-- The Glyphs accompanying a Step, as configuration.
local function buildGlyphs(layout, origin, foreign)
	local path = {'trials_mode', 'glyphs', layout}
	local g = elementReader(path)
	local own = cfgGet(join(path, 'localcoord'))
	if own == nil then
		own = cfgGet(join(origin, 'localcoord'))
	end
	local lc = sharedLocalcoord(path, own, sourceOf(path, 'localcoord', origin), origin)
	-- An offset or spacing, its default converted into the space the block resolved into.
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
		spacing = length('spacing', {0, 0}),
		scale = numList(g('scale'), {1, 1}),
		scalewithtext = flagValue(g('scalewithtext'), true),
		align = numList(g('align'), {1})[1],
		layerno = numList(g('layerno'), {0})[1],
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
local function buildStepOverlay(block, origin)
	local path = join(origin, 'bg', 'overlay')
	if not flagValue(cfgGet(join(path, 'visible')), false) then
		return nil
	end
	local ov = buildOverlay(path, origin)
	local function copy(w)
		return {w[1], w[2], w[3], w[4]}
	end
	if sourceOf(path, 'alpha') == nil then
		ov.alpha = {0, 128}
		rectSetAlpha(ov.RectData, ov.alpha[1], ov.alpha[2])
	end
	-- A Rect's clip window, with an unclipped one spelled as the full localcoord rect.
	local function bounded(w)
		if w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0 then
			return {0, 0, ov.localcoord[1], ov.localcoord[2]}
		end
		return copy(w)
	end
	local ownWindow = sourceOf(path, 'window') ~= nil
	local ownWithTextbox = sourceOf(path, 'window.withtextbox') ~= nil
	ov.window = bounded(ownWindow and ov.window or block.window)
	if ownWithTextbox then
		ov.windowWithTextbox =
			bounded(numList(cfgGet(join(path, 'window', 'withtextbox')), ov.window))
	elseif ownWindow then
		ov.windowWithTextbox = copy(ov.window)
	else
		ov.windowWithTextbox = bounded(block.windowWithTextbox)
	end
	rectSetWindow(ov.RectData, ov.window[1], ov.window[2], ov.window[3], ov.window[4])
	ov.activeWindow = ov.window
	return ov
end

-- Builds the Step block.
local function buildStepBlock(layout)
	local path = {'trials_mode', 'trialsteps', layout}
	local g = elementReader(path)
	local block = {path = path, layout = layout, text = {}}

	for _, status in ipairs(STEP_STATUSES) do
		local e = buildText({'trials_mode', status .. 'step', layout, 'text'}, path)
		block.text[status] = e
		trials.elements[status .. 'step.' .. layout .. '.text'] = e
	end

	local posSource = sourceOf(path, 'pos')
	local foreign = posSource ~= nil and posSource ~= 'defaults'
	local lc = block.text.current.localcoord

	block.spacing = numList(g('spacing'), {0, 0})
	if foreign and sourceOf(path, 'spacing') == 'defaults' then
		block.spacing = {
			block.spacing[1] * lc[1] / MODULE_LOCALCOORD[1],
			block.spacing[2] * lc[2] / MODULE_LOCALCOORD[2],
		}
	end

	block.padding = numList(g('padding'), {0})[1]
	if foreign and sourceOf(path, 'padding') == 'defaults' then
		block.padding = block.padding * lc[1] / MODULE_LOCALCOORD[1]
	end

	local pos = numList(g('pos'), {0, 0})
	local posWithTextbox = numList(g('pos', 'withtextbox'), pos)
	block.shift = {posWithTextbox[1] - pos[1], posWithTextbox[2] - pos[2]}
	block.pos = pos
	block.localcoord = {lc[1], lc[2]}

	local full = {0, 0, lc[1], lc[2]}
	local function unclipped(w)
		return w[1] == 0 and w[2] == 0 and w[3] == 0 and w[4] == 0
	end
	local function copy(w)
		return {w[1], w[2], w[3], w[4]}
	end

	local window = numList(g('window'), {0, 0, 0, 0})
	if foreign and sourceOf(path, 'window') == 'defaults' then
		window = copy(full)
	end
	local windowWithTextbox = numList(g('window', 'withtextbox'), window)
	if foreign and sourceOf(path, 'window.withtextbox') == 'defaults' then
		windowWithTextbox = copy(window)
	end

	-- The unclipped variant of a clip window, as the full rect rather than as zeroes.
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
	block.foreign = foreign

	return block
end

-- Switches the Step block onto its with-Textbox or without-Textbox clip window.
local function applyStepWindow(block, withTextbox)
	local w = withTextbox and block.windowWithTextbox or block.window
	block.activeWindow = w
	for _, status in ipairs(STEP_STATUSES) do
		local e = block.text[status]
		textImgSetWindow(e.TextSpriteData, w[1], w[2], w[3], w[4])
		e.window = {w[1], w[2], w[3], w[4]}
	end
	-- Clips one background piece to the Step block's window.
	local function clip(e)
		if e ~= nil and e.AnimData ~= nil then
			animSetWindow(e.AnimData, w[1], w[2], w[3], w[4])
			e.window = {w[1], w[2], w[3], w[4]}
		end
	end
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

local glyphsWarned = false

-- The Anim one Glyph draws with, built and cached per token, Step Status and Layout.
local function glyphAnim(block, status, token)
	local gl = block.glyphs
	local cache = gl.anims[status]
	local cached = cache[token]
	if cached ~= nil then
		return cached ~= false and cached or nil
	end
	local g = type(motif.glyphs) == 'table' and motif.glyphs[token] or nil
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
	if asked > 0 and built == 0 and not glyphsWarned then
		glyphsWarned = true
		print('Trials: this screenpack has no Glyph sprites for any token these Trials ' ..
			'use — check [Files] glyphs. Steps still draw their text.')
	end
end

-- A stopwatch element.
local function buildTimer(name)
	local path = {'trials_mode', name}
	local e = buildText(path)
	e.text = strValue(cfgGet(join(path, 'text')), '%s')
	e.framespercount = math.max(1, numList(cfgGet(join(path, 'framespercount')), {60})[1])
	return e
end

-- Breaks `text` into lines no wider than `width`, by inserting newlines.
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
local function setProse(box, text)
	if box == nil then
		return
	end
	textImgReset(box.text.TextSpriteData)
	textImgSetText(box.text.TextSpriteData,
		box.wrap and wrapProse(box.text, text, box.wrapWidth) or text)
end

-- The Textbox.
local function buildTextbox()
	local path = {'trials_mode', 'textbox'}
	local g = elementReader(path)
	local box = {path = path}

	box.title = buildText(join(path, 'title'), path)
	box.title.text = strValue(g('title', 'text'), '')
	trials.elements['textbox.title'] = box.title

	box.text = buildText(join(path, 'text'), path)
	trials.elements['textbox.text'] = box.text

	box.wrap = flagValue(g('text', 'wrap'), true)
	local spacing = numList(g('text', 'spacing'), {0, 0})
	textImgSetTextSpacing(box.text.TextSpriteData, spacing[1], spacing[2])
	box.spacing = spacing
	box.delay = numList(g('text', 'delay'), {0})[1]
	textImgSetTextDelay(box.text.TextSpriteData, box.delay)

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

	box.portraitSource = strValue(g('portrait', 'source'), 'system'):lower()
	box.portraitPath = join(path, 'portrait')
	if box.portraitSource ~= 'char' then
		box.portrait = buildArt(box.portraitPath, path)
		if box.portrait ~= nil then
			trials.elements['textbox.portrait'] = box.portrait
		end
	else
		local pg = elementReader(box.portraitPath, path)
		box.portraitGeo = elementGeometry(pg, box.portraitPath, path)
		box.portraitSpr = numList(pg('spr'), {9000, 0})
		box.portraitFacing = numList(pg('facing'), {1})[1]
		box.portraits = {}
	end

	return box
end

-- Success and All-Clear share one shape.
local function buildBanner(name)
	local path = {'trials_mode', name}
	local e = buildText({'trials_mode', name, 'text'}, path)
	e.text = strValue(cfgGet(join(path, 'text', 'text')), '')
	e.displaytime = numList(cfgGet({'trials_mode', name, 'text', 'displaytime'}), {70})[1]
	if e.displaytime <= 0 then
		e.displaytime = 70
	end
	e.snd = numList(cfgGet({'trials_mode', name, 'snd'}), {-1, 0})
	return e
end

local INPUT_KEYS = {
	B = true, D = true, F = true, U = true, L = true, R = true,
	a = true, b = true, c = true, x = true, y = true, z = true, s = true,
	d = true, w = true, m = true,
}

-- The key combination that repositions the pair mid-Trial, as a list of input names.
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

-- One end of the reposition fade.
local function buildFade(name)
	local path = {'trials_mode', name}
	local col = numList(cfgGet(join(path, 'col')), {0, 0, 0})
	local snd = numList(cfgGet(join(path, 'snd')), {-1, 0})
	local time = math.max(0, numList(cfgGet(join(path, 'time')), {0})[1])
	local art = nil
	if time > 0 and (cfgGet(join(path, 'spr')) ~= nil or cfgGet(join(path, 'anim')) ~= nil) then
		art = buildArt(path, nil, false, time)
		if art ~= nil and sourceOf(path, 'pos') == nil
			and sourceOf(path, 'localcoord') == nil then
			local lc = artIsOurs(path, nil) and MODULE_LOCALCOORD
				or {motif.info.localcoord[1], motif.info.localcoord[2]}
			animSetLocalcoord(art.AnimData, lc[1], lc[2])
			art.localcoord = {lc[1], lc[2]}
		end
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
	trials.stepblocks = {}
	for _, layout in ipairs(STEP_LAYOUTS) do
		trials.stepblocks[layout] = buildStepBlock(layout)
	end
	trials.stepblock = trials.stepblocks[STEP_LAYOUTS[1]]
	trials.reposition = {
		enabled = not (cfgGet({'trials_mode', 'trialresetenabled'}) == false
			or strValue(cfgGet({'trials_mode', 'trialresetenabled'}), ''):lower() == 'false'),
		keys = repositionKeys(),
		fadeoutTime = math.max(0, numList(cfgGet({'trials_mode', 'fadeout', 'time'}), {0})[1]),
		fadeinTime = math.max(0, numList(cfgGet({'trials_mode', 'fadein', 'time'}), {0})[1]),
	}
	trials.reposition.fadeout, trials.reposition.fadeoutAnim = buildFade('fadeout')
	trials.reposition.fadein, trials.reposition.fadeinAnim = buildFade('fadein')
end

--;===========================================================
--; THE TRIALS BACKGROUND
--;===========================================================
if trials.enabled then
	local defPath = nil
	for _, layer in ipairs(layers) do
		if type(layer.ini.trialsbgdef) == 'table' then
			defPath = layer.path
		end
	end
	if defPath ~= nil then
		local sff = motif.Sff
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
		trials.backgroundSpr = authored
		trials.backgroundSprResolved = spr
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

local parseIniText, safeLoadText
do

-- strings.TrimSpace, near enough.
local function trim(s)
	return (s:gsub('^%s*(.-)%s*$', '%1'))
end

-- The last occurrence of `needle` in `s`, 1-based, or nil.
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

-- Splits a value on the commas outside quotes.
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

-- One code point, as UTF-8.
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

-- strconv.Unquote, as far as an ini value can reach it, with Go's own fallback.
local function unquote(s)
	local body = s:sub(2, -2)
	if s:sub(1, 1) ~= '"' or body:find('[\n\r]') then
		return body
	end
	local simple = {
		n = '\n', t = '\t', r = '\r', a = '\a', b = '\b', f = '\f', v = '\v',
		['\\'] = '\\', ['"'] = '"',
	}
	local out, i = {}, 1
	while i <= #body do
		local c = body:sub(i, i)
		if c ~= '\\' then
			if c == '"' then
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
				local width = (e == 'x' and 2) or (e == 'u' and 4) or 8
				local digits = body:sub(i + 2, i + 1 + width)
				if #digits ~= width or digits:find('%X') then
					return body
				end
				local n = tonumber(digits, 16)
				if e == 'x' then
					out[#out + 1] = string.char(n)
				else
					if (n >= 0xD800 and n <= 0xDFFF) or n > 0x10FFFF then
						return body
					end
					out[#out + 1] = utf8Char(n)
				end
				i = i + 2 + width
			else
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

-- strconv.ParseInt(s, 0, 64).
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
	if digits == '' or digits:find('.', 1, true) then
		return nil
	end
	local n = tonumber(digits, base)
	if n == nil then
		return nil
	end
	return sign * n
end

-- strconv.ParseFloat, which gopher-lua's tonumber is not.
local function parseFloat(s)
	local mantissa, exponent = s:match('^([^eE]*)[eE]([-+]?%d+)$')
	if mantissa == nil then
		mantissa = s
	end
	if not mantissa:match('^[-+]?%d*%.?%d*$') or mantissa:match('^[-+]?%.?$') then
		return nil
	end
	local n = tonumber(mantissa:find('.', 1, true) and mantissa or (mantissa .. '.0'))
	if n == nil then
		return nil
	end
	if exponent ~= nil then
		n = n * 10 ^ tonumber(exponent)
	end
	return n
end

-- One ini value as the engine types it.
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
	n = parseFloat(s)
	if n ~= nil then
		if n < 0 then
			return -math.floor(-n * 1000000 + 0.5) / 1000000
		end
		return math.floor(n * 1000000 + 0.5) / 1000000
	end
	return s
end

-- keepMeta's key order.
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

-- A dotted key written into its nested tables.
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

-- The lines of a file, however its author ended them.
local function iniLines(text)
	text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
	local lines = {}
	for line in (text .. '\n'):gmatch('([^\n]*)\n') do
		lines[#lines + 1] = line
	end
	return lines
end

-- The key name on one line, and where its value starts.
local function readKeyName(line)
	local quote = nil
	local head = line:sub(1, 1)
	if head == '"' then
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

-- The value starting at `from` on line `n`, and the last line it consumed.
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

-- A Trial Definition's sections, in the order the file declares them.
function parseIniText(text)
	local lines = iniLines(text)
	local sections = {}
	local current = {name = 'DEFAULT', keys = {}, values = {}}
	sections[1] = current
	local count = 1
	local n = 1
	while n <= #lines do
		local line = lines[n]:gsub('^%s+', '')
		local head = line:sub(1, 1)
		if line == '' or head == '#' or head == ';' then
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

-- A Trial Definition, as text.
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
local function trialTitle(section)
	local title = section:match('^[^,]*,%s*(.-)%s*$') or ''
	if title:find(';') then
		title = title:gsub('%s*;.*$', ''):gsub('%s*%]%s*$', '')
	end
	return (title:gsub('%s*$', ''))
end

-- Reads one Trial Definition value in the player's language.
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

-- One `trial.*` key as the author wrote it.
local function authoredWord(raw, key)
	local v = type(raw) == 'table' and raw[key] or nil
	if type(v) == 'table' and v.__value ~= nil then
		v = v.__value
	end
	return strValue(v, ''):lower():match('^%s*(.-)%s*$')
end

-- Says an authored value is unusable, then leaves the caller to fall back.
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

local defaultDummy = readDummy(nil)

local POSITION_WORDS = {
	['left-corner'] = {corner = 'left'},
	['right-corner'] = {corner = 'right'},
	close = {gap = 10},
	medium = {gap = 130},
	far = {gap = 260},
}

local DEFAULT_GAP = 130

-- Where a Trial stands the two characters.
local function readPositions(data, path, section)
	local raw = type(data) == 'table' and data.trial or nil
	local out = {corner = '', cornered = '', gap = DEFAULT_GAP, spaced = false,
		authored = {player = '', dummy = ''}}
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
local function readLife(data, path, section)
	local raw = type(data) == 'table' and data.trial or nil
	local out = {player = 0, dummy = 0, authored = {player = '', dummy = ''}}
	for _, side in ipairs({{field = 'player', key = 'playerlife'}, {field = 'dummy', key = 'dummylife'}}) do
		local word = authoredWord(raw, side.key)
		out.authored[side.field] = word
		if word ~= '' then
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

local CONDITION_KEYS = {
	'stateno', 'animno', 'projid', 'hitcount',
	'isthrow', 'iscounterhit', 'ishelper', 'isproj',
	'validfortickcount',
}

-- One Part's value of one condition field.
local function partValue(v, index)
	if type(v) == 'table' then
		if isValueList(v) then
			v = v[index]
		else
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

-- The numbers one Part will accept for a field.
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

-- loadIni already turns `true` and `false` into Lua booleans.
local function boolValue(v)
	if type(v) == 'boolean' then
		return v
	end
	return tostring(v or ''):lower() == 'true'
end

-- A list of var/value pairs — `12, 0|2|4` — every one of which must hold.
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

-- How many Parts a Step has.
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

-- One Part, fully resolved.
local function readPart(raw, index)
	return {
		stateno = alternatives(partValue(raw.stateno, index)),
		animno = alternatives(partValue(raw.animno, index)),
		projid = alternatives(partValue(raw.projid, index)),
		hitcount = math.max(0, math.floor(tonumber(partValue(raw.hitcount, index)) or 1)),
		isthrow = boolValue(partValue(raw.isthrow, index)),
		iscounterhit = boolValue(partValue(raw.iscounterhit, index)),
		ishelper = boolValue(partValue(raw.ishelper, index)),
		isproj = boolValue(partValue(raw.isproj, index)),
		validfortickcount = tonumber(partValue(raw.validfortickcount, index)),
	}
end

local glyphLengths = nil
local function glyphTokenLengths()
	if glyphLengths ~= nil then
		return glyphLengths
	end
	glyphLengths = {}
	local seen = {}
	if type(motif.glyphs) == 'table' then
		for token in pairs(motif.glyphs) do
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
			if c:match('%S') then
				unknown[c] = true
			end
			i = i + 1
		end
	end
	return out
end

-- The Steps of one Trial, in Step-number order, each with its Parts resolved.
local function readSteps(data, unknown)
	local raw = data.trialstep
	if type(raw) ~= 'table' then
		return {}
	end
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
			glyphs = readGlyphs(step.glyphs, unknown),
			parts = parts,
			validfor = readVarPairs(step.validforvarvalpairs),
		}
	end
	return steps
end

-- Parses a Trial Definition into its Trials, in the order the author wrote them.
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
	local unknown = {}
	for _, sec in ipairs(sections) do
		if sec.name:lower():match('^trialdef') then
			local name = sec.name
			local data = lowerKeys(sec.data)
			table.insert(list, {
				section = name,
				title = trialTitle(name),
				textbox = strValue(localized(type(data.trial) == 'table' and data.trial.textbox or nil), ''),
				steps = readSteps(data, unknown),
				dummy = readDummy(data, path, name),
				positions = readPositions(data, path, name),
				life = readLife(data, path, name),
				showfor = readVarPairs(type(data.trial) == 'table'
					and data.trial.showforvarvalpairs or nil),
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
	for i, trial in ipairs(list) do
		trial.index = i
	end
	return list, nil
end

-- Resolves the Trial Definition a character declares, through its own def file.
local function discoverChar(t)
	if type(t) ~= 'table' or t.trials ~= nil or not t.playable or t.def == nil then
		return
	end
	t.trials = false
	local def = safeLoadIni(t.def, true, false)
	if def == nil or type(def.files) ~= 'table' then
		return
	end
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
	list.def = path
	t.trials = list
end

-- Fires for characters added after the module loads.
hook.add('main.f_addChar.files', 'trials', discoverChar)

-- Reads every playable character's Trial Definition.
function trials.f_discoverAll()
	for _, t in ipairs(main.t_selChars) do
		discoverChar(t)
	end
end

if trials.enabled then
	trials.f_discoverAll()
end

--;===========================================================
--; SELECT SCREEN
--;===========================================================
if trials.enabled then
	trials.selectpalfx = {
		fx = readPalFX({'trials_mode', 'selscreenpalfx'}),
		neutral = {
			time = -1,
			add = {0, 0, 0},
			mul = {256, 256, 256},
			sinadd = {0, 0, 0, 0},
			invertall = 0,
			color = 256,
		},
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
-- The first of `candidates` the menu declares, to anchor an appended item on.
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
if trials.enabled then
main.t_itemname.trials = function(t, item)
	trials.f_discoverAll()

	if main.t_charDef[gameOption('Config.TrainingChar'):lower()] ~= nil then
		main.forceChar[2] = {main.t_charDef[gameOption('Config.TrainingChar'):lower()]}
	end

	main.cpuSide[2] = false

	main.roundTime = -1
	main.selectMenu[2] = true

	if gameOption('Config.TrainingStage') == '' then
		main.stageMenu = true
	end

	main.teamMenu[1].single = true
	main.teamMenu[2].single = true

	main.matchWins.draw = {0, 0}
	main.matchWins.simul = {0, 0}
	main.matchWins.single = {0, 0}
	main.matchWins.tag = {0, 0}

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
trials.match = nil

-- Who P1 picked, read out of start.p[1].t_selected and never written.
local function resolveMatch()
	local m = {
		declared = {}, trials = {}, total = 0, current = 1, steps = {},
		textbox = false, char = nil,
		step = 1, part = 1, combo = 0, partHits = 0, partCombo = 0, grace = 0,
		completed = {}, completedCount = 0, allclear = false,
		availableGen = 0,
		banner = nil, bannerTimer = 0,
		totalTicks = 0, trialTicks = 0,
	}
	local selected = start.p and start.p[1] and start.p[1].t_selected and start.p[1].t_selected[1]
	if selected ~= nil and selected.ref ~= nil then
		local char = main.t_selChars[selected.ref + 1]
		if type(char) == 'table' then
			m.char = char.name
			m.charRow = char
			if type(char.trials) == 'table' then
				m.declared = char.trials
				m.trials = char.trials
				m.total = #char.trials
				m.def = char.trials.def
			end
		end
	end
	return m
end

-- One Player Preference, out of the module's own config.ini.
local function preference(name, default)
	local opts = trials.ini.Options or {}
	if type(opts.Trials) ~= 'table' then
		return default
	end
	local v = opts.Trials[name]
	if v == nil or v == '' then
		return default
	end
	return v
end

-- The Textbox Player Preference.
local function textboxesVisible()
	return tostring(preference('Textboxes', 'show')):lower() ~= 'hide'
end

-- The Advancement Player Preference.
local function autoAdvances()
	return tostring(preference('Advancement', 'autoadvance')):lower() == 'autoadvance'
end

-- Whether a Player Preference is on, accepting the spellings a hand-edit can leave.
local function preferenceEnabled(name, default)
	local v = preference(name, default)
	if type(v) == 'boolean' then
		return v
	end
	local word = tostring(v):lower()
	return word ~= 'false' and word ~= 'no' and word ~= '0' and word ~= 'off'
end

-- The Layout Player Preference.
local function stepLayout()
	local word = tostring(preference('Layout', STEP_LAYOUTS[1])):lower()
	if trials.stepblocks ~= nil and trials.stepblocks[word] ~= nil then
		return word
	end
	return STEP_LAYOUTS[1]
end

-- Points the module at the block the Layout preference names.
local function applyStepLayout()
	local block = trials.stepblocks ~= nil and trials.stepblocks[stepLayout()] or nil
	if block == nil then
		return
	end
	trials.stepblock = block
	local m = trials.match
	applyStepWindow(block, m ~= nil and m.shownTextbox == true)
end

if trials.enabled then
	applyStepLayout()
end

-- Forgets progress through the current Trial and starts it over from its first Step.
local function resetProgress(m)
	m.step = 1
	m.part = 1
	m.partHits = 0
	m.partCombo = 0
	m.combo = 0
	m.grace = 0
end

-- Catches the screen up with the Trial the match is on.
local function syncDisplay(m)
	m.shownSteps = m.steps
	m.shownCurrent = m.current
	m.shownTextbox = m.textbox
	m.shownComplete = false
	m.shownStep = nil
	if trials.stepblock ~= nil then
		applyStepWindow(trials.stepblock, m.textbox)
	end
	local trial = m.trials[m.shownCurrent]
	m.shownText = type(trial) == 'table' and strValue(trial.textbox, '') or ''
	setProse(trials.textbox, m.shownText)
end

-- Whether the Trial at `index` shows a Textbox.
local function trialTextbox(m, index)
	local trial = m.trials[index]
	return type(trial) == 'table' and trial.textbox ~= nil and trial.textbox ~= ''
		and textboxesVisible()
end

-- Moves the match onto one Trial and resolves its Steps, window, progress and timer.
local function selectTrial(index, defer)
	local m = trials.match
	m.current = index
	local trial = m.trials[index]
	m.steps = type(trial) == 'table' and trial.steps or {}
	prepareGlyphs(m.steps)
	m.textbox = trialTextbox(m, index)
	resetProgress(m)
	m.trialTicks = 0
	if m.banner == nil and not defer then
		syncDisplay(m)
	end
end

--;===========================================================
--; PAUSE MENU
--;===========================================================

local MENU_PREFERENCES = {
	{item = 'trialadvancement',    key = 'Advancement',    values = {'autoadvance', 'repeat'}},
	{item = 'trialresetonsuccess', key = 'ResetOnSuccess', values = {'enabled', 'disabled'}, boolean = true},
	{item = 'trialslayout',        key = 'Layout',         values = {'vertical', 'horizontal'}},
	{item = 'trialstextboxes',     key = 'Textboxes',      values = {'show', 'hide'}},
}

local MENU_PREFERENCE = {}
for _, pref in ipairs(MENU_PREFERENCES) do
	MENU_PREFERENCE[pref.item] = pref
end

local TRIALS_LIST_ITEM = 'trialslist'
local TRIALS_ENTRY_ITEM = 'trialsentry'

-- Which value of a preference is currently set, as an index into its `values`.
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

-- Points every value item at what config.ini currently says.
local function syncPreferenceIndices()
	for _, pref in ipairs(MENU_PREFERENCES) do
		menu[pref.item] = preferenceIndex(pref)
	end
end

-- Persists one Player Preference to the module's config.ini.
local function writePreference(key, value)
	if type(trials.ini.Options) ~= 'table' then
		trials.ini.Options = {}
	end
	if type(trials.ini.Options.Trials) ~= 'table' then
		trials.ini.Options.Trials = {}
	end
	trials.ini.Options.Trials[key] = value
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
local function refreshTextbox()
	local m = trials.match
	if m == nil then
		return
	end
	m.textbox = trialTextbox(m, m.current)
	if m.shownCurrent == m.current then
		local appearing = m.textbox and not m.shownTextbox
		m.shownTextbox = m.textbox
		if appearing then
			setProse(trials.textbox, m.shownText or '')
		end
		if trials.stepblock ~= nil then
			applyStepWindow(trials.stepblock, m.textbox)
		end
	end
end

MENU_PREFERENCE.trialstextboxes.changed = refreshTextbox
MENU_PREFERENCE.trialslayout.changed = applyStepLayout

-- The resolved [Trials Pause Menu], or nil where the section never reached the motif.
local function pauseMenuSection()
	local sec = motif.pause_menu ~= nil and motif.pause_menu.trials_pause_menu or nil
	if sec == nil or type(sec.menu) ~= 'table' then
		return nil
	end
	return sec
end

-- The words one value of a preference is shown as.
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
local function jumpToTrial(index)
	local m = trials.match
	if m == nil or type(m.trials[index]) ~= 'table' then
		return
	end
	m.shownStep = m.step
	selectTrial(index, true)
	m.reposRequest = true
end

-- Leaves the pause menu, the way its own Continue does.
local function closePauseMenu()
	menu.currentMenu[1] = menu.currentMenu[2]
	menu.pauseExitDelay = gameOption('Input.PauseExitDelay')
	return false
end

-- The submenu the trials list lives in, once menu.f_start has generated it.
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
			paramname = TRIALS_ENTRY_ITEM,
			displayname = trial.title,
			vardisplay = '',
			selected = i == m.current,
			trial = i,
		}
	end
	for _, item in ipairs(trialsListTail) do
		items[#items + 1] = item
	end
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

local menuMatch, menuTrial, menuGen = nil, nil, nil

-- Catches the pause menu up with the match that is running.
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
	if menuTrial ~= m.current or menuGen ~= m.availableGen then
		menuTrial, menuGen = m.current, m.availableGen
		buildTrialsList()
	end
end

trials.legacyPauseMenu = false

local LEGACY_VALUENAMES = {
	trialresetonsuccess_yes = 'trialresetonsuccess_enabled',
	trialresetonsuccess_no = 'trialresetonsuccess_disabled',
}

-- loadIni's keepMeta tables flattened into the engine's underscore-separated menu keys.
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

	local items = flattenMenuKeys(legacy.menu.itemname, '', {})
	if #items > 0 then
		local itemname, order, depth, rank = {}, {}, {}, {}
		for i, entry in ipairs(items) do
			itemname[entry.key] = entry.value
			order[#order + 1] = entry.key
			depth[entry.key] = select(2, entry.key:gsub('_', ''))
			rank[entry.key] = i
		end
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

	-- One entry of the trials list.
	menu.t_itemname[TRIALS_ENTRY_ITEM] = function(t, item, cursorPosY, moveTxt, sec)
		if getInput(-1, sec.menu.done.key) then
			sndPlay(motif.Snd, sec.cursor.done.snd[1], sec.cursor.done.snd[2])
			jumpToTrial(t.items[item].trial)
			return closePauseMenu()
		end
		return true
	end

	-- Moves the match one Trial along, for a screenpack still listing Next/Previous Trial.
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

	syncPreferenceIndices()

	-- Marks which Trial the match is on, per frame, since a menu reset clears the flag.
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
	local trial = m.trials[m.current]
	local d = type(trial) == 'table' and trial.dummy or defaultDummy
	if not player(2) then
		return
	end
	for _, spec in ipairs(dummyVocabulary) do
		mapSet(spec.map, d[spec.field])
	end
	player(1)
	m.dummyTrial = m.current
	m.dummy = d
	trials.f_dumpState()
end

-- Puts one character on the life a Trial asked for, without waiting for a recovery tick.
local function setLifeNow(value)
	local v = value > 0 and value or lifeMax()
	setLife(v)
	setRedLife(v)
end

-- Where the two characters stand, in the coordinate space trials.zss reads them in.
local function positionsFor(pos, charCoordX)
	local localcoordX = stageVar('stageinfo.localcoord.x')
	local scale = localcoordX / 320
	if scale <= 0 then
		scale = 1
	end
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
		w.playerx = -pos.gap / 2
		w.dummyx = pos.gap / 2
	end
	local coordScale = (charCoordX or 320) / 320
	if coordScale <= 0 then
		coordScale = 1
	end
	for k, v in pairs(w) do
		w[k] = v * coordScale
	end
	return w
end

-- One side's life, on whichever character the redirect currently sits on.
local function writeLifeSide(value)
	mapSet('_iksys_trialsSetLife', value)
	setLifeNow(value)
end

local function writeSetup(m)
	local trial = m.trials[m.current]
	local pos = type(trial) == 'table' and trial.positions or defaultPositions
	local life = type(trial) == 'table' and trial.life or defaultLife

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
	player(1)
	writeLifeSide(life.player)

	m.setupTrial = m.current
	m.reposRequest = false
	m.adoptTrial = nil
	syncDisplay(m)
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
local function adoptSetup(m)
	local trial = m.trials[m.current]
	local pos = type(trial) == 'table' and trial.positions or defaultPositions
	local life = type(trial) == 'table' and trial.life or defaultLife
	if not player(2) then
		return
	end
	local w = positionsFor(pos, localCoordX())
	writeLifeSide(life.dummy)
	player(1)
	writeLifeSide(life.player)
	m.setupTrial = m.current
	m.adoptTrial = nil
	m.reposRequest = false
	m.settleWait = 0
	syncDisplay(m)
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

-- Hands the camera back to its ordinary fighting view once the pair has been placed.
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

local SETTLE_LIMIT = 180

-- Whether the Dummy is somewhere it is reasonable to move her from.
local function dummySettled()
	if not player(2) then
		return true
	end
	local settled = alive() and moveType() ~= 'H' and ctrl()
	player(1)
	return settled
end

-- Notices the player asking to be put back where the Trial wants them.
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
local function applySetup()
	local m = trials.match
	if m == nil then
		return
	end
	if paused() then
		return
	end
	if roundState() < 1 then
		m.setupTrial = nil
		m.setup = nil
		m.repos = nil
		m.cameraPending = false
		m.settleWait = 0
		m.reposRequest = false
		m.reposHeld = false
		m.adoptTrial = nil
		m.shownStep = nil
		return
	end

	if m.repos == 'out' then
		if not fadeActive() then
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
			flushCameraReset(m)
			if player(1) then
				m.combo = comboCount()
			end
		end
		return
	end

	flushCameraReset(m)

	if m.banner ~= nil then
		return
	end
	readRepositionRequest(m)
	if m.adoptTrial ~= nil and not m.reposRequest then
		adoptSetup(m)
		return
	end
	if m.setupTrial == m.current and not m.reposRequest then
		m.settleWait = 0
		return
	end
	if m.setupTrial ~= nil and fadesReposition() then
		m.repos = 'out'
		if trials.reposition.fadeoutTime > 0 then
			fadeOutInit(trials.reposition.fadeout)
		end
		return
	end
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

-- What last hit the Dummy, as far as a Step's conditions are concerned.
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
	player(1)
	return out
end

-- Does a value satisfy one condition field of a Part?.
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

-- Every variable in a list of var/value pairs holds one of its declared values.
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

-- Which of the character's Trials are on offer this round, and the bookkeeping it drives.
local function applyAvailability(m)
	if m == nil then
		return
	end
	if roundState() < 1 then
		m.availableRound = nil
		return
	end
	local stage = roundState() >= 2 and 2 or 1
	if m.availableRound ~= nil and m.availableRound >= stage then
		return
	end
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
	m.completedCount = 0
	for _, trial in ipairs(available) do
		if m.completed[trial.index] then
			m.completedCount = m.completedCount + 1
		end
	end
	m.allclear = m.allclear and m.total > 0 and m.completedCount >= m.total

	if not changed then
		return
	end
	m.availableGen = m.availableGen + 1
	selectTrial(current)
	trials.f_dumpState()
end

-- Whether the current Part registered this frame.
local function partRegisters(step, part, attacker, combo)
	if not satisfies(part.stateno, stateNo(), attacker.stateno) then
		return false
	end
	if not satisfies(part.animno, anim(), attacker.anim) then
		return false
	end
	if not satisfies(part.projid, nil, attacker.projid) then
		return false
	end
	if not varPairsHold(step.validfor) then
		return false
	end
	if part.iscounterhit and part.hitcount ~= 0
		and not (comboCount() > 0 and moveCountered() > 0) then
		return false
	end
	if part.ishelper or part.isproj or part.projid ~= nil then
		return true
	end
	return (moveHit() > 0 and comboCount() > combo) or part.isthrow or part.hitcount == 0
end

-- Whether the run is over.
local function dropped(m, part)
	if m.grace > 0 then
		return comboCount() > m.combo
	end
	return part.hitcount ~= 0 and comboCount() == 0
end

-- Fires Success, or All-Clear on the last Trial left, and moves the match on.
local function completeTrial(m)
	local index = m.current
	local declared = type(m.trials[index]) == 'table' and m.trials[index].index or index
	if not m.completed[declared] then
		m.completed[declared] = true
		m.completedCount = m.completedCount + 1
	end

	local finished = m.completedCount >= m.total and m.total > 0 and not m.allclear
	if finished then
		m.allclear = true
	end
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

	local finishTicks = m.trialTicks
	if m.allclear then
		selectTrial(index)
	elseif autoAdvances() and m.total > 0 then
		selectTrial(index % m.total + 1)
	else
		selectTrial(index)
	end
	if m.banner ~= nil then
		m.trialTicks = finishTicks
	end
	if preferenceEnabled('ResetOnSuccess', true) then
		m.reposRequest = true
	else
		m.adoptTrial = m.current
	end
	trials.f_dumpState()
end

-- Moves past the Part just satisfied, and past the Step and Trial when it was the last.
local function advancePart(m, step, part)
	m.part = m.part + 1
	m.partHits = 0
	m.partCombo = 0
	m.grace = part.validfortickcount or 0
	m.combo = comboCount()
	if m.part <= #step.parts then
		return
	end

	m.part = 1
	m.step = m.step + 1
	if m.step > #m.steps then
		completeTrial(m)
	end
end

-- One frame of Step verification.
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
	if not player(1) then
		return
	end

	local attacker = readAttacker()
	local registers = partRegisters(step, part, attacker, m.combo)
	if not registers and dropped(m, part) then
		resetProgress(m)
		return
	end
	if m.grace > 0 then
		m.grace = m.grace - 1
	end
	if not registers then
		return
	end

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

	if part.hitcount > 1 and comboCount() ~= m.partHits + m.partCombo - 1 then
		if dropped(m, part) then
			resetProgress(m)
		end
		return
	end
	advancePart(m, step, part)
end

-- Injects the module's [Common] files for the duration of a Trials match only.
hook.add("launchFight", "trials", function(common, t, data)
	if not gameMode('trials') then
		return
	end
	trials.match = nil
	if type(trials.ini.Common) ~= 'table' then
		return
	end
	for section, values in pairs(trials.ini.Common) do
		local key = section:lower()
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

-- The Trial Counter's text, with the engine's %i and %s filled in.
local function counterText(current, total)
	local fmt = strValue(cfgGet({'trials_mode', 'trialcounter', 'text'}), '')
	if fmt:find('%%t') then
		return main.f_formatBySpec(fmt:gsub('%%t', tostring(total)), {s = tostring(current), i = current})
	end
	return main.f_formatBySpec(fmt, {i = current, s = tostring(total)})
end

-- Where one Step sits relative to the player's progress, which decides how it is drawn.
local function stepStatus(index, step)
	if index < step then
		return 'completed'
	elseif index == step then
		return 'current'
	end
	return 'upcoming'
end

-- How big one Glyph draws beside a given Step Status.
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

-- Walks one Step's Glyphs along a row and returns how wide the run is.
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
	if drawn > 0 then
		x = x - gl.spacing[1]
	end
	return x
end

-- What one Step's Glyphs add to the width of its item in the horizontal Layout.
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
		animUpdate(a)
		animDraw(a)
	end)
end

-- Draws one background piece, `dx, dy` from where it was built.
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

-- The background under one Step in the vertical Layout.
local function drawStepBgVertical(block, status, x, y)
	local bg = block.stepbg ~= nil and block.stepbg[status] or nil
	if bg ~= nil then
		drawArt(bg.body, x, y)
	end
end

-- The background under one Step in the horizontal Layout.
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
local function textboxTitle(m)
	local fmt = trials.textbox ~= nil and trials.textbox.title.text or ''
	local index = m.shownCurrent or m.current
	local trial = m.trials[index]
	local name = type(trial) == 'table' and trial.title or ''
	if fmt:find('%%n') then
		return main.f_formatBySpec(fmt:gsub('%%([ns])', function(c)
			return c == 'n' and '%s' or '%i'
		end), {i = index, s = name})
	end
	return main.f_formatBySpec(fmt, {i = index, s = name})
end

-- The Textbox, when the Trial carries one and the player has not hidden it.
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

	textImgUpdate(box.text.TextSpriteData)
	textImgDraw(box.text.TextSpriteData)

	drawArt(box.front, 0, 0)
end

-- Draws one Step, with the element for the Step Status it currently has.
local function drawStep(block, status, step, x, y)
	local ts = block.text[status].TextSpriteData
	textImgReset(ts)
	textImgAddPos(ts, x, y)
	textImgSetText(ts, step.text)
	textImgDraw(ts)
	drawGlyphs(block, status, step, x, y)
end

-- The vertical Layout.
local function drawStepsVertical(block, steps, step, shift)
	local spacing = block.spacing
	local first, last = 1, #steps

	local available = block.activeWindow[4] - (block.pos[2] + shift[2])
	if available > 0 and spacing[2] > 0 then
		local fit = math.floor(available / spacing[2]) + 1
		if #steps > fit then
			first = math.max(1, math.min(step - 1, #steps - fit + 1))
			first = math.max(first, step - fit + 1)
			last = math.min(first + fit - 1, #steps)
		end
	end

	for i = first, last do
		local status = stepStatus(i, step)
		local x = shift[1] + spacing[1] * (i - first)
		local y = shift[2] + spacing[2] * (i - first)
		drawStepBgVertical(block, status, x, y)
		drawStep(block, status, steps[i], x, y)
	end
end

-- The horizontal Layout.
local function drawStepsHorizontal(block, steps, step, shift)
	local spacing = block.spacing
	local padding = block.padding
	local originX = block.pos[1] + shift[1]

	local right = block.activeWindow[3]
	if right <= 0 then
		right = block.localcoord[1]
	end
	local available = right - originX

	local placement, rows, x = {}, 1, 0
	for i = 1, #steps do
		local status = stepStatus(i, step)
		local e = block.text[status]
		local bg = block.stepbg ~= nil and block.stepbg[status] or nil
		local content = textImgGetTextWidth(e.TextSpriteData, steps[i].text) * e.scale[1] +
			glyphWidth(block, status, steps[i])
		local lead = bg ~= nil and bg.tailWidth or 0
		local width = lead + padding * 2 + content + (bg ~= nil and bg.headWidth or 0)
		if x > 0 and available > 0 and x + width > available then
			rows = rows + 1
			x = 0
		end
		placement[i] = {row = rows, x = x, status = status, content = content, lead = lead}
		x = x + width + spacing[1]
	end

	local first, last = 1, rows
	local availableY = block.activeWindow[4] - (block.pos[2] + shift[2])
	if availableY > 0 and spacing[2] > 0 and rows > 1 then
		local fit = math.floor(availableY / spacing[2]) + 1
		if rows > fit then
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
			drawStepBgHorizontal(block, at.status, x, y, at.content)
			drawStep(block, at.status, steps[i], x + at.lead + padding, y)
		end
	end
end

-- The Steps of the current Trial, in whichever Layout the player has chosen.
local function drawSteps()
	local block = trials.stepblock
	local m = trials.match
	if block == nil or m == nil then
		return
	end
	local steps = m.shownSteps or m.steps
	local step = m.shownComplete and #steps + 1 or (m.shownStep or m.step)
	if #steps == 0 then
		return
	end

	local shift = m.shownTextbox and block.shift or {0, 0}
	if block.overlay ~= nil then
		rectDraw(block.overlay.RectData)
	end
	drawArt(block.bg, shift[1], shift[2])
	if block.layout == 'horizontal' then
		drawStepsHorizontal(block, steps, step, shift)
	else
		drawStepsVertical(block, steps, step, shift)
	end
end

-- A stopwatch reading, mm:ss:cc.
local function timerText(fmt, ticks, framespercount)
	local seconds = math.max(0, ticks) / math.max(1, framespercount)
	local reading = string.format('%02d:%02d:%02d',
		math.floor(seconds / 60),
		math.floor(seconds % 60),
		math.floor(seconds % 1 * 100))
	return main.f_formatBySpec(fmt, {s = reading, i = math.floor(ticks)})
end

-- Draws one stopwatch and returns it advanced by a tick.
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
	textImgSetText(e.TextSpriteData, e.text)
	textImgDraw(e.TextSpriteData)
	m.bannerTimer = m.bannerTimer - 1
	if m.bannerTimer <= 0 then
		clearBanner(m)
	end
end

-- Runs once per frame during a Trials match, from the engine's Common.Lua `loop()`.
hook.add('loop#trials', 'trials', function()
	if not trials.enabled then
		return
	end
	if trials.match == nil then
		trials.match = resolveMatch()
		if trials.background ~= nil then
			bgReset(trials.background)
		end
		selectTrial(trials.match.current)
		trials.f_dumpState()
	end
	applyAvailability(trials.match)
	applyDummy()
	applySetup()
	syncPauseMenu()
	local m = trials.match
	if roundState() ~= 2 then
		if m.banner ~= nil then
			clearBanner(m)
		end
		return
	end

	if trials.background ~= nil then
		bgDraw(trials.background, 0)
	end

	if m.banner == nil and m.repos == nil and m.setupTrial == m.current then
		verify()
	end

	local counter = trials.elements.trialcounter
	if counter ~= nil then
		local shown = m.shownCurrent or m.current
		local text
		if m.total == 0 then
			text = strValue(cfgGet({'trials_mode', 'nodata', 'text'}), '')
		elseif m.allclear then
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

	if m.total > 0 then
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

	if trials.background ~= nil then
		bgDraw(trials.background, 1)
	end
end)

--;===========================================================
--; DEBUG
--;===========================================================

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

trials.dumpPath = 'debug/t_trials.txt'
trials.f_printTable = printTable

-- The parsed Steps of one Trial, flattened into scalars.
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
			glyphs = table.concat(step.glyphs, '|'),
			glyphCount = #step.glyphs,
			partCount = #step.parts,
			parts = parts,
		}
	end
	return out
end

-- A list of var/value pairs, back in something close to how it was authored.
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

-- Which Trials a match is currently offering, by their declared index.
local function availableText(m)
	local out = {}
	for i, trial in ipairs(m.trials) do
		out[i] = tostring(trial.index or i)
	end
	return table.concat(out, ', ')
end

-- The Glyph geometry of one Step block, and what its Anim cache resolved to.
local function glyphState(block)
	local gl = block.glyphs
	if gl == nil then
		return nil
	end
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
		scalewithtext = gl.scalewithtext,
		spacing = gl.spacing,
		align = gl.align,
		layerno = gl.layerno,
		localcoord = {gl.localcoord[1], gl.localcoord[2]},
		known = known,
		unknown = unknown,
	}
end

-- The Step display's graphical layer as it resolved, for the Layout in use.
local function bgState(block)
	-- Where the block's background came from, or which of the three reasons there is none.
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
			mul = bg ~= nil and table.concat(bg.palfx.mul, ',') or '',
		}
	end
	return out
end

-- The Textbox as it resolved.
local function textboxState()
	local box = trials.textbox
	if box == nil then
		return nil
	end
	return {
		localcoord = {box.title.localcoord[1], box.title.localcoord[2]},
		titleText = box.title.text,
		titlePos = {box.title.pos[1], box.title.pos[2]},
		textPos = {box.text.pos[1], box.text.pos[2]},
		textWindow = {box.text.window[1], box.text.window[2],
			box.text.window[3], box.text.window[4]},
		wrap = box.wrap,
		delay = box.delay,
		spacing = {box.spacing[1], box.spacing[2]},
		bg = box.bg ~= nil,
		front = box.front ~= nil,
		portraitSource = box.portraitSource,
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

-- The pause menu's items in the order the engine resolved them to.
local function pauseMenuItems()
	local sec = pauseMenuSection()
	local order = sec ~= nil and sec.menu.itemname_order or nil
	if type(order) ~= 'table' then
		return ''
	end
	return table.concat(order, '|')
end

-- The trials list as the module filled it in, entry by entry.
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
				row.trials = {}
				for i, v in ipairs(t.trials) do
					row.titles[i] = v.title
					row.trials[i] = {
						title = v.title,
						stepCount = #v.steps,
						firstStepText = v.steps[1] ~= nil and v.steps[1].text or '',
						textbox = v.textbox ~= '',
						showfor = varPairsText(v.showfor),
						dummy = v.dummy,
						positions = v.positions,
						life = v.life,
						steps = copySteps(v.steps),
					}
				end
			end
			chars[#chars + 1] = row
		end
	end

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
		layers = trials.layers,
		config = trials.config,
		configSource = trials.configSource,
		elements = elements,
		steps = trials.stepblock ~= nil and {
			layout = trials.stepblock.layout,
			spacing = trials.stepblock.spacing,
			padding = trials.stepblock.padding,
			window = trials.stepblock.window,
			windowWithTextbox = trials.stepblock.windowWithTextbox,
			shiftWithTextbox = trials.stepblock.shift,
			activeWindow = {
				trials.stepblock.activeWindow[1], trials.stepblock.activeWindow[2],
				trials.stepblock.activeWindow[3], trials.stepblock.activeWindow[4],
			},
			glyphs = glyphState(trials.stepblock),
			bg = bgState(trials.stepblock),
		} or nil,
		chars = chars,
		textbox = textboxState(),
		match = trials.match ~= nil and {
			char = trials.match.char,
			def = trials.match.def,
			total = trials.match.total,
			declared = #trials.match.declared,
			availableResolved = (trials.match.availableRound or 0) >= 1,
			availableFinal = trials.match.availableRound == 2,
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
			shownTextbox = trials.match.shownTextbox == true,
			shownText = trials.match.shownText or '',
			completedCount = trials.match.completedCount,
			allclear = trials.match.allclear,
			banner = trials.match.banner or '',
			totalTicks = trials.match.totalTicks,
			trialTicks = trials.match.trialTicks,
			shownTrial = trials.match.shownCurrent or trials.match.current,
			shownComplete = trials.match.shownComplete == true,
			shownStep = trials.match.shownStep or 0,
			advancement = autoAdvances() and 'autoadvance' or 'repeat',
			resetOnSuccess = preferenceEnabled('ResetOnSuccess', true),
			layout = tostring(preference('Layout', 'vertical')):lower(),
			textboxes = textboxesVisible() and 'show' or 'hide',
			totalTimer = preferenceEnabled('TotalTimer', true),
			trialTimer = preferenceEnabled('TrialTimer', true),
			reposRequest = trials.match.reposRequest == true,
			adoptPending = trials.match.adoptTrial ~= nil,
		} or nil,
		pauseMenu = {
			registered = pauseMenuSection() ~= nil,
			items = pauseMenuItems(),
			legacy = trials.legacyPauseMenu,
			list = trialsListTitles(),
		},
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
			placed = trials.match.setup.placed == true,
		} or nil,
		background = {
			def = trials.backgroundDef or '',
			spr = trials.backgroundSpr or '',
			sprResolved = trials.backgroundSprResolved or '',
			declared = trials.backgroundDef ~= nil,
			loaded = trials.background ~= nil,
		},
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
		reposition = trials.reposition ~= nil and {
			enabled = trials.reposition.enabled,
			keys = table.concat(trials.reposition.keys, '+'),
			keyCount = #trials.reposition.keys,
			fadeout = trials.reposition.fadeoutTime,
			fadein = trials.reposition.fadeinTime,
			fadeoutAnim = trials.reposition.fadeoutAnim == true,
			fadeinAnim = trials.reposition.fadeinAnim == true,
			reminder = trials.elements.trialresetreminder ~= nil
				and trials.elements.trialresetreminder.text or '',
			phase = trials.match ~= nil and trials.match.repos or '',
		} or nil,
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
		zssPath = normalizePath((trials.ini.Common or {}).States or ''),
	}, trials.dumpPath) end)
	if not ok then
		print('Trials: could not write debug dump (' .. tostring(err) .. ')')
	end
end

trials.f_dumpState()

return trials
