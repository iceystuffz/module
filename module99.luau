--[[
	ScriptHubHandler.luau  --  one script for Delta's UI:
	  * ScriptHub search (ScriptBlox / RScripts / RoScripts / RobloxScripts / HaxHell) with engine button
	  * Music tab, Delta Logo (outline) tab, Colors/Themes tab, bold fonts
	Run it in your executor while Delta's UI is loaded. Re-running unloads the old copy first.
	Config is saved to ScriptHub/config.json.
]]
local Hub = (function()
local HttpService = game:GetService("HttpService")

local Hub = {}

local BASE = {
	ScriptBlox = "https://scriptblox.com",
	RScripts = "https://rscripts.net",
	RoScripts = "https://roscripts.io",
	RobloxScripts = "https://robloxscripts.com",
	HaxHell = "https://haxhell.com",
}

Hub.Engines = { "ScriptBlox", "RScripts", "RoScripts", "RobloxScripts", "HaxHell" }

local rq = (syn and syn.request) or request or http_request or (http and http.request)

---------------------------------------------------------------------
-- HTTP
---------------------------------------------------------------------

local function httpGet(url, headers)
	local body, status = nil, 0
	if type(rq) == "function" then
		local h = { ["User-Agent"] = "Roblox/Http/1.1", ["Accept"] = "application/json" }
		for k, v in pairs(headers or {}) do
			h[k] = v
		end
		local ok, r = pcall(rq, { Url = url, Method = "GET", Headers = h })
		if ok and r then
			body = r.Body or r.body
			status = r.StatusCode or r.Status or r.status_code or 0
		end
	end
	if type(body) ~= "string" or body == "" then
		local ok, r = pcall(function()
			return game:HttpGet(url)
		end)
		if ok and type(r) == "string" and r ~= "" then
			body, status = r, 0
		end
	end
	if type(body) ~= "string" or body == "" then
		return nil, status
	end
	return body, status
end

local function httpJson(url)
	local body, status = httpGet(url)
	if not body then
		return nil, status
	end
	local ok, dec = pcall(function()
		return HttpService:JSONDecode(body)
	end)
	if ok then
		return dec, status
	end
	return nil, status
end

---------------------------------------------------------------------
-- Per-engine field helpers (same logic as the original)
---------------------------------------------------------------------

local function isKey(engine, d)
	local v
	if engine == "RScripts" then
		v = d.keySystem
	elseif engine == "HaxHell" then
		local flags = type(d.flags) == "table" and d.flags or {}
		v = flags.keySystem
	else
		v = d.key
	end
	if v == nil and type(d.accessType) == "string" then
		v = d.accessType:lower() == "key"
	end
	if type(v) == "boolean" then
		return v
	elseif type(v) == "number" then
		return v ~= 0
	elseif type(v) == "string" then
		local s = v:lower()
		return s ~= ""
			and s ~= "false"
			and s ~= "0"
			and s ~= "none"
			and s ~= "n/a"
			and not s:find("no key", 1, true)
			and not s:find("keyless", 1, true)
	end
	return v ~= nil and v ~= false
end

local function getRaw(engine, d)
	-- returns source-or-url, isUrl
	if engine == "RScripts" then
		return d.rawScript or d.scriptLink or d.raw or "", true
	elseif engine == "RoScripts" then
		local url = d.loadstring or d.rawUrl or ""
		return url, type(url) == "string" and url:match("^https?://") ~= nil
	elseif engine == "RobloxScripts" then
		local source = d.script or ""
		if source ~= "" then
			return source, false
		end
		local url = d.rawScriptUrl or d.scriptLink or d.raw or ""
		return url, url ~= ""
	elseif engine == "HaxHell" then
		local links = type(d.links) == "table" and d.links or {}
		local src = type(d.source) == "table" and d.source or {}
		local s = links.raw or src.rawUrl or src.code or d.rawScriptUrl or d.script or ""
		return s, type(s) == "string" and s:match("^https?://") ~= nil
	end
	-- ScriptBlox
	return d.script or d.rawScript or d.scriptLink or d.raw or "", false
end

local function getGame(engine, d)
	if engine == "RScripts" then
		return d.game and d.game.title or "Unknown Game"
	end
	return d.game and d.game.name or "Unknown Game"
end

local function getPlaceId(engine, d)
	local p
	if engine == "ScriptBlox" then
		p = d.game and d.game.gameId
	elseif engine == "RScripts" then
		p = d.game and (d.game.placeId or (d.game.gameLink and d.game.gameLink:match("/games/(%d+)")))
	elseif engine == "HaxHell" or engine == "RoScripts" then
		p = (d.game and d.game.placeId) or d.placeId
	end
	return tonumber(p)
end

local function refererFor(engine)
	if engine == "RScripts" then
		return { Referer = BASE.RScripts }
	elseif engine == "RobloxScripts" then
		return { Referer = BASE.RobloxScripts }
	elseif engine == "HaxHell" then
		return { Referer = BASE.HaxHell }
	end
	return nil
end

local function buildInfo(engine, d, key)
	local stats = type(d.stats) == "table" and d.stats or {}
	local flags = type(d.flags) == "table" and d.flags or {}
	local views = tostring(d.views or d.viewCount or stats.views or 0)
	local likes = tostring(d.likes or d.likeCount or stats.likes or 0)
	local k = key and "Key" or "Keyless"

	if engine == "RoScripts" then
		if d.scriptType == "paid" then
			k = "Paid"
		end
	elseif engine == "RobloxScripts" and type(d.accessType) == "string" then
		local a = d.accessType:lower()
		if a == "paid" then
			k = "Paid"
		elseif a == "free" then
			k = "Free"
		end
	elseif engine == "HaxHell" and flags.isPaid == true then
		k = "Paid"
	end

	local patched = d.isPatched == true or d.patched == true or flags.patched == true
	local status = engine == "RobloxScripts" and "Published" or (patched and "Patched" or "Working")
	local info = string.format("%s | Views %s | Likes %s | %s", k, views, likes, status)

	local verified = false
	if engine == "RScripts" and d.discord and d.discord ~= "" then
		info = info .. " | Discord"
	elseif engine == "RobloxScripts" and d.author and d.author.verified == true then
		verified = true
		info = info .. " | Verified"
	elseif engine == "RoScripts" then
		if d.verified == true or (type(d.owner) == "table" and d.owner.verified == true) then
			verified = true
			info = info .. " | Verified"
		end
		if d.universal == true then
			info = info .. " | Universal"
		end
	elseif engine == "HaxHell" then
		if flags.verified == true or (type(d.author) == "table" and d.author.isScripterVerified == true) then
			verified = true
			info = info .. " | Verified"
		end
		if flags.mobileSupported == true then
			info = info .. " | Mobile"
		end
	end
	return info, tonumber(views) or 0, tonumber(likes) or 0, patched, verified
end

local function fullUrl(v, base)
	if type(v) ~= "string" or v == "" then
		return nil
	end
	if v:match("^https?://") then
		return v
	elseif v:sub(1, 2) == "//" then
		return "https:" .. v
	elseif v:sub(1, 1) == "/" then
		return base .. v
	end
	return base .. "/" .. v
end

local function getImage(engine, d)
	local g = type(d.game) == "table" and d.game or {}
	local list = {
		d.image, d.imageUrl, d.thumbnail, d.cover, d.coverImage, d.banner, d.img, d.icon,
		g.imgurl, g.imageUrl, g.image, g.thumbnail, g.iconUrl, g.icon, g.cover, g.gameLogo,
	}
	for _, v in ipairs(list) do
		local u = fullUrl(v, BASE[engine])
		if u then
			return u
		end
	end
	return nil
end

local function normalize(engine, d)
	local raw, isUrl = getRaw(engine, d)
	local key = isKey(engine, d)
	local info, views, likes, patched, verified = buildInfo(engine, d, key)
	local extra
	if engine == "RScripts" then
		extra = d.discord
	elseif engine == "RoScripts" then
		extra = d.marketplaceUrl or d.discordUrl
	end
	if type(extra) ~= "string" or extra == "" then
		extra = nil
	end
	return {
		engine = engine,
		title = d.title or d.name or "Untitled Script",
		game = getGame(engine, d),
		placeId = getPlaceId(engine, d),
		key = key,
		views = views,
		likes = likes,
		patched = patched,
		verified = verified,
		info = info,
		extra = extra,
		image = getImage(engine, d),
		raw = raw,
		rawIsUrl = isUrl,
		headers = refererFor(engine),
		raw_data = d,
	}
end

---------------------------------------------------------------------
-- Search
---------------------------------------------------------------------

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

Hub.httpGet = httpGet
Hub.BASE = BASE

function Hub.next(engine)
	for i, name in ipairs(Hub.Engines) do
		if name == engine then
			return Hub.Engines[(i % #Hub.Engines) + 1]
		end
	end
	return Hub.Engines[1]
end

function Hub.search(engine, query, page, trending)
	engine = BASE[engine] and engine or "ScriptBlox"
	query = trim(query)
	page = math.max(tonumber(page) or 1, 1)
	trending = engine == "ScriptBlox" and trending == true

	if engine == "RobloxScripts" and #query > 100 then
		query = query:sub(1, 100)
	elseif engine == "HaxHell" and query ~= "" and #query < 2 then
		return nil, "HaxHell search requires at least 2 characters"
	end

	local enc = HttpService:UrlEncode(query)
	local u
	if engine == "RScripts" then
		u = string.format("https://rscripts.net/api/v2/scripts?page=%d&orderBy=date&sort=desc", page)
		if query ~= "" then
			u = u .. "&q=" .. enc
		end
	elseif engine == "RoScripts" then
		if query == "" then
			u = string.format("https://api.roscripts.io/v1/scripts?page=%d&max=20&sortBy=updatedAt&order=desc", page)
		else
			u = string.format("https://api.roscripts.io/v1/scripts/search?q=%s&page=%d&max=20", enc, page)
		end
	elseif engine == "RobloxScripts" then
		page = math.min(page, 200)
		u = string.format("https://robloxscripts.com/api/v1/scripts?page=%d&limit=24&sort=newest", page)
		if query ~= "" then
			u = u .. "&q=" .. enc
		end
	elseif engine == "HaxHell" then
		if query == "" then
			u = string.format("https://haxhell.com/api/v1/scripts?page=%d&limit=24&sort=latest", page)
		else
			u = string.format("https://haxhell.com/api/v1/search/scripts?q=%s&page=%d&limit=24&sort=latest", enc, page)
		end
	elseif trending then
		u = string.format("https://scriptblox.com/api/script/fetch?page=%d", page)
	else
		u = string.format("https://scriptblox.com/api/script/search?q=%s&page=%d", enc, page)
	end

	local dec, status = httpJson(u)
	if status == 429 then
		return nil, "Rate limit reached. Try again shortly"
	elseif status == 503 then
		return nil, "API temporarily unavailable"
	elseif status ~= 0 and (status < 200 or status >= 300) then
		return nil, "Request failed (" .. tostring(status) .. ")"
	elseif not dec then
		return nil, "Request failed"
	end

	local arr, maxp, cur = nil, 1, page
	if engine == "RScripts" then
		arr = dec.scripts
		maxp = math.max(dec.info and dec.info.maxPages or 1, 1)
	elseif engine == "RoScripts" then
		local result = dec.result or {}
		local meta = dec.meta or {}
		arr = type(result.scripts) == "table" and result.scripts or {}
		local pages = tonumber(result.totalPages or meta.totalPages)
		maxp = math.max(math.floor(pages or 1), 1)
		cur = tonumber(result.page or meta.page) or page
	elseif engine == "RobloxScripts" or engine == "HaxHell" then
		arr = dec.data
		local pg = dec.pagination or {}
		local total = tonumber(pg.total or pg.totalItems)
		local limit = tonumber(pg.limit or pg.perPage) or 24
		local pages = tonumber(pg.totalPages or pg.pages or pg.lastPage)
		if not pages and total then
			pages = math.ceil(total / math.max(limit, 1))
		end
		cur = tonumber(pg.page or pg.currentPage) or page
		if engine == "RobloxScripts" then
			maxp = math.min(math.max(pages or 1, 1), 200)
		else
			if not pages then
				pages = pg.hasMore == true and (cur + 1) or cur
			end
			maxp = math.max(math.floor(pages or 1), 1)
		end
	else
		local r = dec.result or {}
		arr = r.scripts
		maxp = math.max(r.totalPages or 1, 1)
	end

	local scripts = {}
	for _, d in ipairs(arr or {}) do
		if type(d) == "table" then
			table.insert(scripts, normalize(engine, d))
		end
	end
	return { scripts = scripts, page = cur, maxPages = maxp, engine = engine }
end

---------------------------------------------------------------------
-- Run / copy
---------------------------------------------------------------------

function Hub.getSource(item)
	local src = item.raw
	if item.rawIsUrl then
		local body, status = httpGet(item.raw, item.headers)
		if not body then
			return nil, "failed to download script (" .. tostring(status) .. ")"
		end
		src = body
	end
	if type(src) ~= "string" or src == "" then
		return nil, "empty script source"
	end
	return src
end

function Hub.run(item)
	local src, err = Hub.getSource(item)
	if not src then
		return false, err
	end
	if type(loadstring) ~= "function" then
		return false, "loadstring unavailable"
	end
	local fn, cerr = loadstring(src, "@ScriptHubEntry")
	if type(fn) ~= "function" then
		return false, cerr or "compile failed"
	end
	local ok, rerr = pcall(fn)
	if not ok then
		return false, tostring(rerr)
	end
	return true
end

function Hub.copy(item)
	if type(setclipboard) ~= "function" then
		return false, "setclipboard unavailable"
	end
	local src
	local d = item.raw_data
	if item.engine == "RoScripts" and type(d.loadstring) == "string" and d.loadstring ~= "" then
		src = "loadstring(game:HttpGet(" .. string.format("%q", d.loadstring) .. "))()"
	else
		src = Hub.getSource(item)
	end
	if type(src) ~= "string" or src == "" then
		return false, "nothing to copy"
	end
	setclipboard(src)
	return true
end

return Hub
end)()

------------------------------------------------------------------
-- Services / session
------------------------------------------------------------------
print("[ScriptHub] starting...")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local genv = (getgenv and getgenv()) or _G
if type(genv.ScriptHubUnload) == "function" then
	pcall(genv.ScriptHubUnload)
end

local alive = true
local conns, made = {}, {}
local function C(c)
	conns[#conns + 1] = c
	return c
end
local function M(i)
	made[#made + 1] = i
	return i
end

local CFG = {
	DEFAULT_ENGINE = "ScriptBlox",
	THUMBNAILS = true, -- needs writefile + getcustomasset; PNG/JPG only
	DIR = "ScriptHub",
}

local function c3(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function dig(inst, ...)
	for _, n in ipairs({ ... }) do
		if not inst then
			return nil
		end
		inst = inst:FindFirstChild(n)
	end
	return inst
end

local function hexOf(c)
	return string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function fromHex(s)
	s = tostring(s or ""):gsub("#", ""):gsub("%s", "")
	if #s == 3 then
		s = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2)
	end
	if #s ~= 6 then
		return nil
	end
	local r, g, b = tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16)
	if r and g and b then
		return c3(r, g, b)
	end
	return nil
end

local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

------------------------------------------------------------------
-- Find the Delta UI (Scripthub frame lives directly under the main ScreenGui)
------------------------------------------------------------------
local function findHub()
	if typeof(genv.ScriptHubRoot) == "Instance" then
		return genv.ScriptHubRoot
	end
	local okS, scr = pcall(function()
		return script
	end)
	if okS and typeof(scr) == "Instance" and scr.Parent and scr.Parent.Name == "Holder" then
		local h = scr.Parent.Parent
		if h and h:FindFirstChild("Popup") then
			return h
		end
	end
	local roots = {}
	if type(gethui) == "function" then
		local ok, r = pcall(gethui)
		if ok and r then
			table.insert(roots, r)
		end
	end
	table.insert(roots, CoreGui)
	local lp = Players.LocalPlayer
	if lp and lp:FindFirstChild("PlayerGui") then
		table.insert(roots, lp.PlayerGui)
	end
	for _, root in ipairs(roots) do
		local ok, desc = pcall(function()
			return root:GetDescendants()
		end)
		if ok then
			for _, d in ipairs(desc) do
				if d.Name == "Scripthub" and d:IsA("Frame") and d:FindFirstChild("Holder")
					and d:FindFirstChild("Popup") and d:FindFirstChild("Searchbar") then
					return d
				end
			end
		end
	end
	return nil
end

local hub = findHub()
if not hub then
	return warn("[ScriptHub] Scripthub frame not found. Set getgenv().ScriptHubRoot = <the Scripthub frame> and run again.")
end
local gui = hub.Parent
local sidebar = gui and gui:FindFirstChild("Sidebar")
if not (gui and sidebar) then
	return warn("[ScriptHub] Could not find the Delta sidebar.")
end

------------------------------------------------------------------
-- Files / config
------------------------------------------------------------------
local fsOK = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local function ensureFolder(path)
	if type(makefolder) == "function" and type(isfolder) == "function" then
		pcall(function()
			if not isfolder(path) then
				makefolder(path)
			end
		end)
	end
end

local config = {}
if fsOK then
	pcall(function()
		ensureFolder(CFG.DIR)
		local p = CFG.DIR .. "/config.json"
		if isfile(p) then
			local ok, d = pcall(function()
				return HttpService:JSONDecode(readfile(p))
			end)
			if ok and type(d) == "table" then
				config = d
			end
		end
	end)
end

local saveQueued = false
local function saveConfig()
	if not fsOK or saveQueued then
		return
	end
	saveQueued = true
	task.delay(0.8, function()
		saveQueued = false
		pcall(function()
			ensureFolder(CFG.DIR)
			writefile(CFG.DIR .. "/config.json", HttpService:JSONEncode(config))
		end)
	end)
end

------------------------------------------------------------------
-- Theme engine: recolors the whole Delta UI by color "roles"
------------------------------------------------------------------
local Theme = {}
do
	local ROLES = { "bg", "surface", "surface2", "accent", "accentDim", "text", "dim" }
	Theme.ROLES = ROLES
	Theme.LABEL = {
		bg = "Background",
		surface = "Surface (rows, search bars)",
		surface2 = "Controls (buttons, sliders)",
		accent = "Accent",
		accentDim = "Accent tint (enabled rows)",
		text = "Text",
		dim = "Dim text",
	}
	local ANCHOR = {
		bg = c3(25, 26, 34),
		surface = c3(40, 43, 53),
		surface2 = c3(56, 61, 76),
		accentDim = c3(31, 51, 80),
		dim = c3(131, 140, 164),
		text = c3(255, 255, 255),
	}
	local DEFAULT = {
		bg = c3(24, 25, 33),
		surface = c3(38, 41, 50),
		surface2 = c3(51, 56, 70),
		accent = c3(34, 160, 255),
		accentDim = c3(31, 51, 80),
		text = c3(255, 255, 255),
		dim = c3(126, 139, 176),
	}
	Theme.DEFAULT = DEFAULT

	local function copyRoles(t)
		local o = {}
		for k, v in pairs(t) do
			o[k] = v
		end
		return o
	end
	Theme.copyRoles = copyRoles

	local function T(name, bg, sf, sf2, ac, acd, tx, dm)
		return {
			name = name,
			roles = {
				bg = c3(table.unpack(bg)),
				surface = c3(table.unpack(sf)),
				surface2 = c3(table.unpack(sf2)),
				accent = c3(table.unpack(ac)),
				accentDim = c3(table.unpack(acd)),
				text = c3(table.unpack(tx)),
				dim = c3(table.unpack(dm)),
			},
		}
	end

	Theme.list = {
		{ name = "Delta Default", identity = true, roles = copyRoles(DEFAULT) },
		T("Midnight Blue", { 10, 14, 28 }, { 18, 26, 48 }, { 30, 42, 72 }, { 79, 140, 255 }, { 20, 38, 80 }, { 235, 242, 255 }, { 120, 140, 185 }),
		T("Crimson", { 24, 10, 14 }, { 40, 16, 22 }, { 62, 26, 34 }, { 255, 59, 89 }, { 74, 20, 32 }, { 255, 240, 243 }, { 190, 120, 132 }),
		T("Emerald", { 8, 22, 18 }, { 14, 36, 30 }, { 24, 56, 46 }, { 46, 230, 150 }, { 14, 62, 44 }, { 230, 255, 244 }, { 110, 170, 148 }),
		T("Amethyst", { 20, 12, 32 }, { 32, 20, 52 }, { 50, 32, 80 }, { 170, 100, 255 }, { 48, 26, 84 }, { 245, 238, 255 }, { 150, 125, 195 }),
		T("Sunset", { 28, 14, 12 }, { 46, 24, 20 }, { 72, 38, 30 }, { 255, 128, 64 }, { 84, 40, 22 }, { 255, 244, 236 }, { 200, 140, 112 }),
		T("Ocean Teal", { 6, 22, 28 }, { 10, 38, 48 }, { 18, 60, 74 }, { 0, 200, 220 }, { 8, 60, 72 }, { 228, 250, 255 }, { 100, 160, 176 }),
		T("Rose Gold", { 26, 16, 20 }, { 42, 28, 34 }, { 66, 44, 52 }, { 255, 150, 170 }, { 84, 44, 56 }, { 255, 240, 244 }, { 196, 150, 162 }),
		T("Amoled Black", { 0, 0, 0 }, { 12, 12, 14 }, { 26, 26, 30 }, { 34, 160, 255 }, { 10, 34, 58 }, { 255, 255, 255 }, { 130, 134, 146 }),
		T("Nord", { 30, 34, 42 }, { 46, 52, 64 }, { 59, 66, 82 }, { 136, 192, 208 }, { 40, 62, 74 }, { 236, 239, 244 }, { 150, 160, 180 }),
		T("Dracula", { 30, 31, 41 }, { 40, 42, 54 }, { 68, 71, 90 }, { 189, 147, 249 }, { 58, 48, 88 }, { 248, 248, 242 }, { 130, 140, 180 }),
		T("Cyberpunk", { 14, 8, 26 }, { 26, 14, 46 }, { 44, 22, 78 }, { 255, 0, 200 }, { 70, 8, 60 }, { 240, 255, 255 }, { 150, 200, 230 }),
		T("Hacker Green", { 3, 10, 5 }, { 8, 22, 12 }, { 14, 40, 22 }, { 0, 255, 70 }, { 4, 56, 20 }, { 190, 255, 200 }, { 70, 150, 90 }),
		T("Gold Luxe", { 18, 16, 10 }, { 32, 28, 16 }, { 54, 46, 24 }, { 255, 200, 60 }, { 74, 58, 16 }, { 255, 248, 230 }, { 190, 172, 120 }),
		T("Slate Mint", { 22, 26, 30 }, { 34, 40, 46 }, { 52, 60, 70 }, { 120, 220, 170 }, { 30, 62, 52 }, { 238, 246, 244 }, { 140, 156, 170 }),
		T("Blood Moon", { 12, 4, 6 }, { 24, 8, 12 }, { 44, 14, 20 }, { 220, 20, 40 }, { 56, 8, 16 }, { 255, 225, 228 }, { 160, 90, 100 }),
	}

	Theme.identity = true
	Theme.name = "Delta Default"
	Theme.roles = copyRoles(DEFAULT)

	local orig = setmetatable({}, { __mode = "k" })
	local lastSet = setmetatable({}, { __mode = "k" })
	local cache, produced, rev = {}, {}, {}

	local function classify(c)
		local r, g, b = c.R, c.G, c.B
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		if mx < 0.03 then
			return nil
		end
		local s = (mx - mn) / mx
		if s >= 0.30 then
			return mx < 0.45 and "accentDim" or "accent"
		end
		if mx >= 0.80 then
			return "text"
		elseif mx >= 0.42 then
			return "dim"
		elseif mx >= 0.24 then
			return "surface2"
		elseif mx >= 0.17 then
			return "surface"
		end
		return "bg"
	end

	local function clamp01(x)
		return math.clamp(x, 0, 1)
	end

	local function mapColor(c)
		if Theme.identity then
			return c
		end
		local key = hexOf(c)
		local hit = cache[key]
		if hit then
			return hit
		end
		local role = classify(c)
		local out = c
		local roles = Theme.roles
		if role == "accent" then
			local h, s, v = Color3.toHSV(roles.accent)
			local _, os, ov = Color3.toHSV(c)
			out = Color3.fromHSV(h, clamp01(s + (os - 0.867)), clamp01(v + (ov - 1)))
		elseif role then
			local base, anchor = roles[role], ANCHOR[role]
			out = Color3.new(
				clamp01(base.R + (c.R - anchor.R)),
				clamp01(base.G + (c.G - anchor.G)),
				clamp01(base.B + (c.B - anchor.B))
			)
		end
		cache[key] = out
		if role then
			local ok = hexOf(out)
			produced[ok] = true
			rev[ok] = c
		end
		return out
	end
	Theme.map = mapColor

	local function mapAny(v)
		if typeof(v) == "Color3" then
			return mapColor(v)
		elseif typeof(v) == "ColorSequence" then
			if Theme.identity then
				return v
			end
			local kps = {}
			for _, k in ipairs(v.Keypoints) do
				kps[#kps + 1] = ColorSequenceKeypoint.new(k.Time, mapColor(k.Value))
			end
			return ColorSequence.new(kps)
		end
		return v
	end

	local function setProp(inst, prop, col)
		local l = lastSet[inst]
		if not l then
			l = {}
			lastSet[inst] = l
		end
		l[prop] = col
		pcall(function()
			inst[prop] = col
		end)
	end
	Theme.setRaw = setProp

	local function propsFor(inst)
		local list
		if inst:IsA("GuiObject") then
			list = { "BackgroundColor3" }
			if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
				table.insert(list, "TextColor3")
				if inst:IsA("TextBox") then
					table.insert(list, "PlaceholderColor3")
				end
				if inst.TextStrokeTransparency < 1 then
					table.insert(list, "TextStrokeColor3")
				end
			end
			if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
				local c = inst.ImageColor3
				local white = c.R > 0.92 and c.G > 0.92 and c.B > 0.92
				local sz = inst.AbsoluteSize
				if (not white) or (sz.X > 0 and sz.Y > 0 and sz.X <= 150 and sz.Y <= 150) then
					table.insert(list, "ImageColor3")
				end
			end
			if inst:IsA("ScrollingFrame") then
				table.insert(list, "ScrollBarImageColor3")
			end
		elseif inst:IsA("UIStroke") then
			list = { "Color" }
		elseif inst:IsA("UIGradient") then
			list = { "Color" }
		elseif inst:IsA("Color3Value") then
			list = { "Value" }
		end
		return list
	end

	local function isDynamic(_)
		return true
	end

	local function onChanged(inst, prop)
		if not alive then
			return
		end
		local rec = orig[inst]
		if not rec then
			return
		end
		local ok, cur = pcall(function()
			return inst[prop]
		end)
		if not ok or typeof(cur) ~= "Color3" then
			return
		end
		local l = lastSet[inst]
		if l and l[prop] == cur then
			return
		end
		local k = hexOf(cur)
		if produced[k] then
			rec[prop] = rev[k] or cur
			if l then
				l[prop] = cur
			end
			return
		end
		rec[prop] = cur
		setProp(inst, prop, mapColor(cur))
	end

	local function capture(inst, hookDyn)
		local props = propsFor(inst)
		if not props then
			return
		end
		local rec = orig[inst] or {}
		local added = false
		for _, p in ipairs(props) do
			if rec[p] == nil then
				local ok, v = pcall(function()
					return inst[p]
				end)
				if ok and (typeof(v) == "Color3" or typeof(v) == "ColorSequence") then
					rec[p] = v
					added = true
					if hookDyn and typeof(v) == "Color3" and isDynamic(inst) then
						C(inst:GetPropertyChangedSignal(p):Connect(function()
							onChanged(inst, p)
						end))
					end
				end
			end
		end
		if added then
			orig[inst] = rec
		end
	end

	local function scanNode(n, hookDyn)
		if n:GetAttribute("SH_NoTheme") then
			return
		end
		pcall(capture, n, hookDyn)
		for _, c in ipairs(n:GetChildren()) do
			scanNode(c, hookDyn)
		end
	end

	-- capture current colors of root's tree as "original" colors, then paint them
	function Theme.scan(root, hookDyn)
		scanNode(root, hookDyn)
		if not Theme.identity then
			local function paintNode(n)
				if n:GetAttribute("SH_NoTheme") then
					return
				end
				local rec = orig[n]
				if rec then
					for p, oc in pairs(rec) do
						setProp(n, p, mapAny(oc))
					end
				end
				for _, c in ipairs(n:GetChildren()) do
					paintNode(c)
				end
			end
			paintNode(root)
		end
	end

	-- clone shares the template's original colors (template must already be scanned)
	function Theme.adopt(clone, tpl)
		local a, b = tpl:GetDescendants(), clone:GetDescendants()
		table.insert(a, 1, tpl)
		table.insert(b, 1, clone)
		for i = 1, math.min(#a, #b) do
			local rec = orig[a[i]]
			if rec and not orig[b[i]] then
				local copy = {}
				for k, v in pairs(rec) do
					copy[k] = v
				end
				orig[b[i]] = copy
			end
		end
	end

	-- set a dynamic color from an ORIGINAL (default-palette) color
	function Theme.paint(inst, prop, origColor)
		if prop == "BackgroundColor3" then
			local fill = inst:FindFirstChild("SH_Fill")
			if fill then
				inst = fill
				prop = "ImageColor3"
			end
		end
		local rec = orig[inst]
		if not rec then
			rec = {}
			orig[inst] = rec
		end
		rec[prop] = origColor
		setProp(inst, prop, mapColor(origColor))
	end

	local token = 0
	function Theme.apply()
		token = token + 1
		local tok = token
		cache = {}
		local list = {}
		for inst in pairs(orig) do
			list[#list + 1] = inst
		end
		task.spawn(function()
			for i, inst in ipairs(list) do
				if tok ~= token or not alive then
					return
				end
				local rec = orig[inst]
				if rec then
					for p, oc in pairs(rec) do
						setProp(inst, p, mapAny(oc))
					end
				end
				if i % 900 == 0 then
					task.wait()
				end
			end
			if Theme.afterApply then
				pcall(Theme.afterApply)
			end
		end)
	end

	function Theme.restore()
		token = token + 1
		for inst, rec in pairs(orig) do
			for p, oc in pairs(rec) do
				pcall(function()
					inst[p] = oc
				end)
			end
		end
	end

	-- instance appeared after the initial scan (Delta clones / creates things at runtime)
	function Theme.adoptNew(inst)
		if orig[inst] then
			return
		end
		local props
		local okp = pcall(function()
			props = propsFor(inst)
		end)
		if not okp or not props then
			return
		end
		local rec = {}
		for _, p in ipairs(props) do
			local ok, v = pcall(function()
				return inst[p]
			end)
			if ok and typeof(v) == "Color3" then
				local k = hexOf(v)
				if produced[k] and not Theme.identity then
					rec[p] = rev[k] or v
					lastSet[inst] = lastSet[inst] or {}
					lastSet[inst][p] = v
				else
					rec[p] = v
					if not Theme.identity then
						setProp(inst, p, mapColor(v))
					end
				end
				C(inst:GetPropertyChangedSignal(p):Connect(function()
					onChanged(inst, p)
				end))
			elseif ok and typeof(v) == "ColorSequence" then
				rec[p] = v
				if not Theme.identity then
					setProp(inst, p, mapAny(v))
				end
			end
		end
		if next(rec) then
			orig[inst] = rec
		end
	end

	function Theme.set(def, silent)
		Theme.name = def.name
		Theme.identity = def.identity == true
		Theme.roles = copyRoles(def.roles)
		cache = {}
		Theme.apply()
		if not silent then
			config.theme = { name = def.name, roles = {} }
			for k, v in pairs(Theme.roles) do
				config.theme.roles[k] = hexOf(v)
			end
			saveConfig()
		end
		if Theme.onChange then
			pcall(Theme.onChange)
		end
	end

	function Theme.setRole(role, color)
		if Theme.identity or Theme.name ~= "Custom" then
			local base = copyRoles(Theme.roles)
			Theme.name = "Custom"
			Theme.identity = false
			Theme.roles = base
		end
		Theme.roles[role] = color
		cache = {}
		Theme.apply()
		config.theme = { name = "Custom", roles = {} }
		for k, v in pairs(Theme.roles) do
			config.theme.roles[k] = hexOf(v)
		end
		saveConfig()
		if Theme.onChange then
			pcall(Theme.onChange)
		end
	end

	function Theme.byName(n)
		for _, t in ipairs(Theme.list) do
			if t.name == n then
				return t
			end
		end
	end
end

------------------------------------------------------------------
-- Bold fonts for the whole Delta UI
------------------------------------------------------------------
local Fonts = { on = false }
do
	local origFF = setmetatable({}, { __mode = "k" })
	local function isText(i)
		return i:IsA("TextLabel") or i:IsA("TextButton") or i:IsA("TextBox")
	end
	function Fonts.bold(i)
		if not isText(i) then
			return
		end
		pcall(function()
			local ff = i.FontFace
			if origFF[i] == nil then
				origFF[i] = ff
			end
			local w = ff.Weight
			if w ~= Enum.FontWeight.Bold and w ~= Enum.FontWeight.ExtraBold and w ~= Enum.FontWeight.Heavy then
				i.FontFace = Font.new(ff.Family, Enum.FontWeight.Bold, ff.Style)
			end
		end)
	end
	function Fonts.set(on)
		Fonts.on = on
		if on then
			local list = gui:GetDescendants()
			task.spawn(function()
				for i, d in ipairs(list) do
					if not (alive and Fonts.on) then
						return
					end
					Fonts.bold(d)
					if i % 1200 == 0 then
						task.wait()
					end
				end
			end)
		else
			for i, ff in pairs(origFF) do
				pcall(function()
					i.FontFace = ff
				end)
			end
		end
	end
	function Fonts.restore()
		Fonts.on = false
		for i, ff in pairs(origFF) do
			pcall(function()
				i.FontFace = ff
			end)
		end
	end
end

------------------------------------------------------------------
-- UI primitives (built to look like Delta's own rows/controls)
------------------------------------------------------------------
local U = math.clamp(math.floor(gui.AbsoluteSize.Y / 42), 12, 30)
local PAD = math.floor(U * 0.9)

local S = {
	rowBg = c3(38, 41, 50),
	rowOn = c3(31, 51, 80),
	title = c3(255, 255, 255),
	desc = c3(126, 139, 176),
	swOn = c3(59, 139, 254),
	swOff = c3(61, 66, 81),
	knobOn = c3(254, 254, 254),
	knobOff = c3(136, 140, 151),
	track = c3(61, 66, 81),
	ctrl = c3(51, 56, 70),
	btn = c3(60, 137, 196),
	btnText = c3(140, 206, 255),
	corner = UDim.new(0, 10),
	font = Enum.Font.GothamBold,
	bold = Enum.Font.GothamBold,
}

pcall(function()
	local h = dig(gui, "Settings", "Holder")
	local row = h and (h:FindFirstChild("SettingSwitch") or h:FindFirstChild("SettingSwitchOn"))
	if row then
		local cr = row:FindFirstChildOfClass("UICorner")
		if cr then
			S.corner = cr.CornerRadius
		end
		local t = row:FindFirstChild("Title")
		if t and t:IsA("TextLabel") then
			S.font = Enum.Font.GothamBold
		end
	end
end)


------------------------------------------------------------------
-- Shape: same rounding as the Delta logo, as a real squircle
------------------------------------------------------------------
local TextService = game:GetService("TextService")
local ContentProvider = game:GetService("ContentProvider")

local function findDeltaIcon()
	local roots = {}
	if type(gethui) == "function" then
		local ok, r = pcall(gethui)
		if ok and r then
			table.insert(roots, r)
		end
	end
	table.insert(roots, CoreGui)
	local lp = Players.LocalPlayer
	if lp and lp:FindFirstChild("PlayerGui") then
		table.insert(roots, lp.PlayerGui)
	end
	local best, bestScore = nil, -math.huge
	for _, root in ipairs(roots) do
		for _, g in ipairs(root:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= gui and not g:FindFirstChild("Executor", true) then
				local buttons, count = {}, 0
				for _, d in ipairs(g:GetDescendants()) do
					if d:IsA("GuiObject") then
						count = count + 1
					end
					if d:IsA("ImageButton") then
						table.insert(buttons, d)
					end
				end
				if #buttons == 1 and count <= 12 then
					local b = buttons[1]
					local score = 0
					if b.Parent == g then
						score = score + 4
					end
					if type(b.Image) == "string" and b.Image ~= "" then
						score = score + 3
					end
					local sz = b.AbsoluteSize
					if sz.X > 0 and sz.Y > 0 then
						local ratio = sz.X / sz.Y
						if ratio >= 0.7 and ratio <= 1.3 then
							score = score + 3
						end
					end
					if score > bestScore then
						best, bestScore = b, score
					end
				end
			end
		end
	end
	return best
end

-- corner roundness taken from the Delta logo (as a fraction of the shorter side)
local ROUND = { ratio = 0.26 }
do
	local btn = findDeltaIcon()
	local cr
	if btn then
		local c = btn:FindFirstChildOfClass("UICorner") or btn:FindFirstChildWhichIsA("UICorner", true)
		cr = c and c.CornerRadius
		local m = math.min(btn.AbsoluteSize.X, btn.AbsoluteSize.Y)
		if cr then
			local r = cr.Scale > 0 and cr.Scale or (m > 0 and cr.Offset / m or nil)
			if r then
				ROUND.ratio = math.clamp(r, 0.14, 0.32)
			end
		end
	end
end

print("[ScriptHub] building UI...")
-- squircle mask (superellipse), generated as a PNG and used as a 9-slice
local SQ = { ok = false, asset = nil, size = 96, inset = 32 }
do
	local W, N, SS = SQ.size, 4.6, 4

	local CRC = {}
	for i = 0, 255 do
		local c = i
		for _ = 1, 8 do
			if bit32.band(c, 1) == 1 then
				c = bit32.bxor(bit32.rshift(c, 1), 0xEDB88320)
			else
				c = bit32.rshift(c, 1)
			end
		end
		CRC[i] = c
	end
	local function crc32(s)
		local c = 0xFFFFFFFF
		for i = 1, #s do
			c = bit32.bxor(CRC[bit32.band(bit32.bxor(c, s:byte(i)), 255)], bit32.rshift(c, 8))
		end
		return bit32.bxor(c, 0xFFFFFFFF)
	end
	local function u32(n)
		return string.char(
			bit32.band(bit32.rshift(n, 24), 255),
			bit32.band(bit32.rshift(n, 16), 255),
			bit32.band(bit32.rshift(n, 8), 255),
			bit32.band(n, 255)
		)
	end
	local function chunk(tag, data)
		return u32(#data) .. tag .. data .. u32(crc32(tag .. data))
	end
	local function adler32(s)
		local a, b = 1, 0
		for i = 1, #s do
			a = (a + s:byte(i)) % 65521
			b = (b + a) % 65521
		end
		return b * 65536 + a
	end

	local function buildPNG()
		local PX = {}
		for a = 0, 255 do
			PX[a] = string.char(255, 255, 255, a)
		end
		local rows = {}
		for y = 0, W - 1 do
			local row = { "\0" }
			for x = 0, W - 1 do
				local cnt = 0
				for sy = 0, SS - 1 do
					local py = (y + (sy + 0.5) / SS) / W * 2 - 1
					for sx = 0, SS - 1 do
						local px = (x + (sx + 0.5) / SS) / W * 2 - 1
						if math.abs(px) ^ N + math.abs(py) ^ N <= 1 then
							cnt = cnt + 1
						end
					end
				end
				row[#row + 1] = PX[math.floor(cnt / (SS * SS) * 255 + 0.5)]
			end
			rows[#rows + 1] = table.concat(row)
		end
		local raw = table.concat(rows)
		local blocks, pos, n = {}, 1, #raw
		while pos <= n do
			local part = raw:sub(pos, pos + 65534)
			pos = pos + #part
			local final = pos > n and 1 or 0
			local len = #part
			local nlen = bit32.band(bit32.bnot(len), 0xFFFF)
			blocks[#blocks + 1] = string.char(final, len % 256, math.floor(len / 256), nlen % 256, math.floor(nlen / 256)) .. part
		end
		local z = "\120\1" .. table.concat(blocks) .. u32(adler32(raw))
		local ihdr = u32(W) .. u32(W) .. string.char(8, 6, 0, 0, 0)
		return "\137PNG\r\n\26\n" .. chunk("IHDR", ihdr) .. chunk("IDAT", z) .. chunk("IEND", "")
	end

	if fsOK and type(getcustomasset) == "function" and config.squircle ~= false then
		pcall(function()
			ensureFolder(CFG.DIR)
			local path = CFG.DIR .. "/squircle_v1.png"
			if not isfile(path) then
				writefile(path, buildPNG())
			end
			local asset = getcustomasset(path)
			local probe = Instance.new("ImageLabel")
			probe.BackgroundTransparency = 1
			probe.ImageTransparency = 0.98
			probe.Size = UDim2.new(0, 4, 0, 4)
			probe.Position = UDim2.new(0.5, 0, 0.5, 0)
			probe.Image = asset
			probe.Parent = gui
			local t0 = os.clock()
			while not probe.IsLoaded and os.clock() - t0 < 2.5 do
				task.wait(0.05)
			end
			local loaded = probe.IsLoaded
			probe:Destroy()
			if loaded then
				SQ.ok, SQ.asset = true, asset
			end
		end)
	end
end

print("[ScriptHub] squircle shapes: " .. (SQ.ok and "on" or "off (using rounded corners)"))

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
		if o:IsA("GuiObject") and parent:IsA("GuiObject") and not (props and props.ZIndex) then
			o.ZIndex = parent.ZIndex + 1
		end
	end
	return o
end

local function corner(o, r)
	return mk("UICorner", { CornerRadius = r or S.corner }, o)
end

-- rounded surface: squircle image when available, otherwise a gentle UICorner
local function surface(o, h, color)
	if SQ.ok then
		o.BackgroundTransparency = 1
		local e = math.clamp(math.floor(h * ROUND.ratio * 1.6), 6, math.max(6, math.floor(h / 2)))
		mk("ImageLabel", {
			Name = "SH_Fill",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = SQ.asset,
			ImageColor3 = color,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(SQ.inset, SQ.inset, SQ.size - SQ.inset, SQ.size - SQ.inset),
			SliceScale = e / SQ.inset,
			Size = UDim2.new(1, 0, 1, 0),
		}, o)
	else
		o.BackgroundTransparency = 0
		o.BackgroundColor3 = color
		mk("UICorner", { CornerRadius = UDim.new(ROUND.ratio, 0) }, o)
	end
end

local function label(parent, props)
	local d = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = S.font,
		TextColor3 = S.title,
		TextSize = U,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Text = "",
	}
	for k, v in pairs(props or {}) do
		d[k] = v
	end
	return mk("TextLabel", d, parent)
end

local function nextOrder(holder, inst)
	local n = (holder:GetAttribute("SH_n") or 0) + 1
	holder:SetAttribute("SH_n", n)
	inst.LayoutOrder = n
end

local function rowFrame(holder, h, title)
	local f = mk("Frame", {
		Name = title or "Row",
		Size = UDim2.new(1, 0, 0, h),
		BackgroundColor3 = S.rowBg,
		BorderSizePixel = 0,
	}, holder)
	surface(f, h, S.rowBg)
	nextOrder(holder, f)
	if title then
		f:SetAttribute("SH_Title", title:lower())
	end
	return f
end

local function header(holder, txt)
	local f = mk("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, math.floor(U * 2.2)) }, holder)
	nextOrder(holder, f)
	f:SetAttribute("SH_Header", true)
	label(f, {
		Text = txt:upper(),
		Font = S.bold,
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.8),
		Position = UDim2.new(0, 6, 0, 0),
		Size = UDim2.new(1, -12, 1, 0),
		TextYAlignment = Enum.TextYAlignment.Bottom,
	})
	return f
end

local function pill(parent, txt, bg, fg, minW)
	local h = math.floor(U * 2.1)
	local size = math.floor(U * 0.85)
	local b = mk("TextButton", {
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 10, 0, h),
	}, parent)
	surface(b, h, bg or S.btn)
	label(b, {
		Name = "Label",
		Text = txt,
		Font = S.bold,
		TextSize = size,
		TextColor3 = fg or S.btnText,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.None,
		Size = UDim2.new(1, 0, 1, 0),
	})
	local ok, w = pcall(function()
		return TextService:GetTextSize(txt, size, S.bold, Vector2.new(10000, h)).X
	end)
	if not ok then
		w = #txt * size * 0.6
	end
	b.Size = UDim2.new(0, math.max(minW or 0, math.floor(w) + PAD * 2), 0, h)
	return b
end

local function pillText(b, t)
	local l = b:FindFirstChild("Label")
	if l then
		l.Text = t
	end
end

local function bindDrag(hit, onFrac, scroller)
	local dragging = false
	local function upd(input)
		local w = math.max(hit.AbsoluteSize.X, 1)
		onFrac(math.clamp((input.Position.X - hit.AbsolutePosition.X) / w, 0, 1))
	end
	C(hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			if scroller and scroller:IsA("ScrollingFrame") then
				scroller.ScrollingEnabled = false
			end
			upd(input)
			local ch
			ch = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if scroller and scroller:IsA("ScrollingFrame") then
						scroller.ScrollingEnabled = true
					end
					ch:Disconnect()
				end
			end)
		end
	end))
	C(UIS.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			upd(input)
		end
	end))
end

local function toggleRow(holder, title, desc, init, cb)
	local h = math.floor(U * 3.6)
	local f = rowFrame(holder, h, title)
	local w = -(PAD * 3 + math.floor(U * 2.8))
	label(f, {
		Name = "Title",
		Text = title,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, math.floor(h * 0.14)),
		Size = UDim2.new(1, w, 0, math.floor(U * 1.4)),
	})
	label(f, {
		Name = "Desc",
		Text = desc or "",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.78),
		Position = UDim2.new(0, PAD, 0, math.floor(h * 0.14) + math.floor(U * 1.5)),
		Size = UDim2.new(1, w, 0, math.floor(U * 1.1)),
	})
	local sw = mk("TextButton", {
		Name = "Switch",
		Text = "",
		AutoButtonColor = false,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -PAD, 0.5, 0),
		Size = UDim2.new(0, math.floor(U * 2.8), 0, math.floor(U * 1.5)),
	}, f)
	corner(sw, UDim.new(1, 0))
	local kd = math.floor(U * 1.1)
	local knob = mk("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, kd, 0, kd),
		BorderSizePixel = 0,
	}, sw)
	corner(knob, UDim.new(1, 0))
	local state = init and true or false
	local api = {}
	local function render()
		Theme.paint(sw, "BackgroundColor3", state and S.swOn or S.swOff)
		Theme.paint(knob, "BackgroundColor3", state and S.knobOn or S.knobOff)
		Theme.paint(f, "BackgroundColor3", state and S.rowOn or S.rowBg)
		knob.Position = state and UDim2.new(1, -(kd / 2 + 4), 0.5, 0) or UDim2.new(0, kd / 2 + 4, 0.5, 0)
	end
	function api.Set(v, silent)
		state = v and true or false
		render()
		if not silent and cb then
			cb(state)
		end
	end
	function api.Get()
		return state
	end
	C(sw.MouseButton1Click:Connect(function()
		api.Set(not state)
	end))
	render()
	return api, f
end

local function sliderRow(holder, title, min, max, init, fmtFn, cb, step)
	local h = math.floor(U * 4.4)
	local f = rowFrame(holder, h, title)
	label(f, {
		Text = title,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, math.floor(U * 0.55)),
		Size = UDim2.new(0.6, -PAD, 0, math.floor(U * 1.3)),
	})
	local val = label(f, {
		Font = S.bold,
		TextColor3 = S.desc,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.6, 0, 0, math.floor(U * 0.55)),
		Size = UDim2.new(0.4, -PAD, 0, math.floor(U * 1.3)),
	})
	local barH = math.max(6, math.floor(U * 0.5))
	local bar = mk("Frame", {
		Name = "Track",
		BackgroundColor3 = S.track,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD, 1, -math.floor(U * 1.3)),
		Size = UDim2.new(1, -PAD * 2, 0, barH),
	}, f)
	corner(bar, UDim.new(1, 0))
	local fill = mk("Frame", { BackgroundColor3 = S.swOn, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, bar)
	corner(fill, UDim.new(1, 0))
	local kd = math.floor(U * 1.1)
	local knob = mk("Frame", {
		BackgroundColor3 = S.knobOn,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, kd, 0, kd),
		Position = UDim2.new(0, 0, 0.5, 0),
	}, bar)
	corner(knob, UDim.new(1, 0))
	local hit = mk("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, math.floor(U * 2.6)),
	}, bar)
	local value = init
	local function setFrac(fr, silent)
		fr = math.clamp(fr, 0, 1)
		local v = min + (max - min) * fr
		if step then
			v = math.floor(v / step + 0.5) * step
			fr = (v - min) / (max - min)
		end
		value = v
		fill.Size = UDim2.new(fr, 0, 1, 0)
		knob.Position = UDim2.new(fr, 0, 0.5, 0)
		val.Text = fmtFn and fmtFn(v) or tostring(math.floor(v * 100 + 0.5) / 100)
		if not silent and cb then
			cb(v)
		end
	end
	bindDrag(hit, function(fr)
		setFrac(fr)
	end, holder)
	setFrac((init - min) / (max - min), true)
	local api = {}
	function api.Set(v, silent)
		setFrac((v - min) / (max - min), silent)
	end
	function api.Get()
		return value
	end
	return api, f
end

local function buttonRow(holder, title, desc, btnText, cb)
	local h = math.floor(U * 3.6)
	local f = rowFrame(holder, h, title)
	label(f, {
		Text = title,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, math.floor(h * 0.14)),
		Size = UDim2.new(0.6, -PAD, 0, math.floor(U * 1.4)),
	})
	label(f, {
		Text = desc or "",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.78),
		Position = UDim2.new(0, PAD, 0, math.floor(h * 0.14) + math.floor(U * 1.5)),
		Size = UDim2.new(0.6, -PAD, 0, math.floor(U * 1.1)),
	})
	local b = pill(f, btnText)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -PAD, 0.5, 0)
	C(b.MouseButton1Click:Connect(function()
		cb(b)
	end))
	return b, f
end

local function segmented(holder, title, options, current, cb)
	local h = math.floor(U * 5.4)
	local f = rowFrame(holder, h, title)
	label(f, {
		Text = title,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, math.floor(U * 0.5)),
		Size = UDim2.new(1, -PAD * 2, 0, math.floor(U * 1.3)),
	})
	local box = mk("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, PAD, 0, math.floor(U * 2.2)),
		Size = UDim2.new(1, -PAD * 2, 0, math.floor(U * 2.3)),
	}, f)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, math.floor(U * 0.5)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, box)
	local btns = {}
	local api = {}
	local function render()
		for key, b in pairs(btns) do
			local on = key == current
			Theme.paint(b, "BackgroundColor3", on and S.btn or S.ctrl)
			Theme.paint(b:FindFirstChild("Label"), "TextColor3", on and S.btnText or S.desc)
		end
	end
	for i, opt in ipairs(options) do
		local b = pill(box, opt.label, S.ctrl, S.desc)
		b.LayoutOrder = i
		btns[opt.key] = b
		C(b.MouseButton1Click:Connect(function()
			current = opt.key
			render()
			cb(opt.key)
		end))
	end
	function api.Set(key)
		current = key
		render()
	end
	render()
	return api, f
end

-- color picker row: swatch + hex box + R/G/B sliders
local function colorRow(holder, title, getFn, setFn)
	local h = math.floor(U * 10.2)
	local f = rowFrame(holder, h, title)
	label(f, {
		Text = title,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, math.floor(U * 0.6)),
		Size = UDim2.new(1, -(PAD * 3 + U * 9), 0, math.floor(U * 1.4)),
	})
	local sw = mk("Frame", {
		Name = "Swatch",
		BackgroundColor3 = getFn(),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(PAD * 2 + U * 6), 0, math.floor(U * 0.4)),
		Size = UDim2.new(0, math.floor(U * 2), 0, math.floor(U * 1.8)),
	}, f)
	sw:SetAttribute("SH_NoTheme", true)
	corner(sw, UDim.new(ROUND.ratio, 0))
	local box = mk("TextBox", {
		Name = "Hex",
		BackgroundColor3 = S.ctrl,
		BorderSizePixel = 0,
		Text = "#" .. hexOf(getFn()),
		TextColor3 = S.title,
		PlaceholderText = "#RRGGBB",
		Font = S.bold,
		TextSize = math.floor(U * 0.85),
		ClearTextOnFocus = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -PAD, 0, math.floor(U * 0.4)),
		Size = UDim2.new(0, math.floor(U * 6), 0, math.floor(U * 1.8)),
	}, f)
	corner(box, UDim.new(ROUND.ratio, 0))

	local channels = { { "R", "R" }, { "G", "G" }, { "B", "B" } }
	local sliders = {}
	local api = {}
	local building = true

	local function cur()
		return getFn()
	end
	local function refresh()
		local c = cur()
		sw.BackgroundColor3 = c
		box.Text = "#" .. hexOf(c)
		for i, ch in ipairs(channels) do
			sliders[i].set(c[ch[2]])
		end
	end
	local function push(c)
		sw.BackgroundColor3 = c
		box.Text = "#" .. hexOf(c)
		setFn(c)
	end

	for i, ch in ipairs(channels) do
		local y = math.floor(U * 2.8) + (i - 1) * math.floor(U * 2.3)
		label(f, {
			Text = ch[1],
			Font = S.bold,
			TextColor3 = S.desc,
			TextSize = math.floor(U * 0.85),
			Position = UDim2.new(0, PAD, 0, y),
			Size = UDim2.new(0, math.floor(U * 1.2), 0, math.floor(U * 1.8)),
		})
		local bar = mk("Frame", {
			BackgroundColor3 = S.track,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, PAD + math.floor(U * 1.5), 0, y + math.floor(U * 0.9)),
			Size = UDim2.new(1, -(PAD * 2 + math.floor(U * 1.5)), 0, math.max(6, math.floor(U * 0.45))),
		}, f)
		corner(bar, UDim.new(1, 0))
		local fill = mk("Frame", { BackgroundColor3 = S.swOn, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, bar)
		corner(fill, UDim.new(1, 0))
		local kd = math.floor(U * 1.0)
		local knob = mk("Frame", {
			BackgroundColor3 = S.knobOn,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.new(0, kd, 0, kd),
			Position = UDim2.new(0, 0, 0.5, 0),
		}, bar)
		corner(knob, UDim.new(1, 0))
		local hit = mk("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0, math.floor(U * 2.2)),
		}, bar)
		local s = {}
		function s.set(v)
			v = math.clamp(v, 0, 1)
			fill.Size = UDim2.new(v, 0, 1, 0)
			knob.Position = UDim2.new(v, 0, 0.5, 0)
		end
		sliders[i] = s
		bindDrag(hit, function(fr)
			if building then
				return
			end
			local c = cur()
			local r, g, b = c.R, c.G, c.B
			if i == 1 then
				r = fr
			elseif i == 2 then
				g = fr
			else
				b = fr
			end
			s.set(fr)
			push(Color3.new(r, g, b))
		end, holder)
	end

	C(box.FocusLost:Connect(function()
		local c = fromHex(box.Text)
		if c then
			push(c)
			refresh()
		else
			box.Text = "#" .. hexOf(cur())
		end
	end))

	building = false
	refresh()
	api.Refresh = refresh
	return api, f
end

local function bindFilter(input, holder)
	C(input:GetPropertyChangedSignal("Text"):Connect(function()
		local q = input.Text:lower()
		for _, c in ipairs(holder:GetChildren()) do
			if c:IsA("GuiObject") then
				if c:GetAttribute("SH_Header") then
					c.Visible = q == ""
				elseif c:GetAttribute("SH_Title") then
					c.Visible = q == "" or c:GetAttribute("SH_Title"):find(q, 1, true) ~= nil
				end
			end
		end
	end))
end

------------------------------------------------------------------
-- Panels + sidebar tabs
------------------------------------------------------------------
local OPEN_POS = UDim2.new(0.476246715, 0, 0.508232415, 0)
local CLOSED_POS = UDim2.new(0.4, 0, 0.508232415, 0)
local ORIG_PANELS = { "Executor", "Home", "Scripthub", "Settings", "Console" }
local ORIG_BUTTONS = { "Home", "Executor", "Scripthub", "Settings", "Console" }

local panels = {} -- key -> panel frame
local tabButtons = {} -- key -> sidebar button
local syncSidebar

local function makePanel(key, placeholder)
	local tpl = gui:FindFirstChild("Settings") or hub
	local p = tpl:Clone()
	p.Name = "SH_" .. key
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("LocalScript") or d:IsA("Script") then
			d:Destroy()
		end
	end
	p.Visible = false
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = CLOSED_POS
	p.Parent = gui
	M(p)
	local sort = p:FindFirstChild("Sort")
	if sort then
		sort:Destroy()
	end
	local sb = p:FindFirstChild("Searchbar")
	local input = sb and sb:FindFirstChild("Input")
	if sb then
		sb.AnchorPoint = Vector2.new(1, 0)
		sb.Position = UDim2.new(1, 0, 0, 0)
		sb.Size = UDim2.new(1, 0, sb.Size.Y.Scale, sb.Size.Y.Offset)
	end
	if input then
		input.PlaceholderText = placeholder
		input.Text = ""
	end
	local holder = p:FindFirstChild("Holder")
	for _, c in ipairs(holder:GetChildren()) do
		if not (c:IsA("UIListLayout") or c:IsA("UIPadding")) then
			c:Destroy()
		end
	end
	local ll = holder:FindFirstChildOfClass("UIListLayout") or mk("UIListLayout", {}, holder)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Padding = UDim.new(0, math.floor(U * 0.55))
	ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
	holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
	holder.CanvasSize = UDim2.new(0, 0, 0, 0)
	holder.ScrollingDirection = Enum.ScrollingDirection.Y
	holder.ScrollingEnabled = true
	holder.ScrollBarThickness = 5
	panels[key] = p
	return p, holder, input
end

local function sidebarBtn(name)
	for _, d in ipairs(sidebar:GetDescendants()) do
		if d.Name == name and d:IsA("GuiButton") then
			return d
		end
	end
end

local function addSidebarButton(key, glyph)
	local src = sidebarBtn("Console") or sidebarBtn("Scripthub") or sidebarBtn("Home")
	if not src then
		return nil
	end
	local b = src:Clone()
	b.Name = "SH_" .. key
	for _, d in ipairs(b:GetDescendants()) do
		if d:IsA("LocalScript") or d:IsA("Script") then
			d:Destroy()
		end
	end
	local img = b:FindFirstChildWhichIsA("ImageLabel")
	if img then
		local gl = Instance.new("TextLabel")
		gl.Name = "Glyph"
		gl.BackgroundTransparency = 1
		gl.AnchorPoint = img.AnchorPoint
		gl.Position = img.Position
		gl.Size = img.Size
		gl.ZIndex = img.ZIndex
		gl.Text = glyph
		gl.TextScaled = true
		gl.Font = Enum.Font.GothamBold
		gl.TextColor3 = c3(138, 145, 164)
		gl.Parent = b
		img:Destroy()
	end
	local tog = sidebarBtn("ToggleUI")
	local toLo = tog and tog.LayoutOrder or 0
	if tog and toLo > 0 then
		for _, d in ipairs(sidebar:GetChildren()) do
			if d:IsA("GuiButton") and d.LayoutOrder >= toLo then
				d.LayoutOrder = d.LayoutOrder + 1
			end
		end
		b.LayoutOrder = toLo
	elseif tog then
		tog.LayoutOrder = 500
		local n = 0
		for _, d in ipairs(sidebar:GetChildren()) do
			if d:GetAttribute("SH_Added") then
				n = n + 1
			end
		end
		b.LayoutOrder = 1 + n
	end
	b:SetAttribute("SH_Added", true)
	b.Parent = src.Parent
	M(b)
	tabButtons[key] = b
	return b
end

local tabTween = {}
local function openPanel(p)
	tabTween[p] = (tabTween[p] or 0) + 1
	p.Position = CLOSED_POS
	p.Visible = true
	TweenService:Create(p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = OPEN_POS }):Play()
end

local function closePanel(p, anim)
	if not p.Visible then
		return
	end
	tabTween[p] = (tabTween[p] or 0) + 1
	local tok = tabTween[p]
	if anim then
		TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = CLOSED_POS }):Play()
		task.delay(0.2, function()
			if tabTween[p] == tok and p.Parent then
				p.Visible = false
			end
		end)
	else
		p.Position = CLOSED_POS
		p.Visible = false
	end
end

local function showTab(key)
	for _, n in ipairs(ORIG_PANELS) do
		local p = gui:FindFirstChild(n)
		if p and p:IsA("GuiObject") then
			p.Visible = false
		end
	end
	for k, p in pairs(panels) do
		if k ~= key then
			closePanel(p, false)
		end
	end
	if panels[key] and not panels[key].Visible then
		openPanel(panels[key])
	end
	task.defer(syncSidebar)
end

local function closeOurTabs()
	for _, p in pairs(panels) do
		closePanel(p, false)
	end
	task.defer(syncSidebar)
end

local function registerTab(key, glyph)
	local b = addSidebarButton(key, glyph)
	if b then
		C(b.MouseButton1Click:Connect(function()
			if alive then
				showTab(key)
			end
		end))
	end
	return b
end

local activeValue = sidebar:FindFirstChild("ActiveColor")
local inactiveValue = sidebar:FindFirstChild("InactiveColor")

function syncSidebar()
	if not alive then
		return
	end
	local activeName
	for key, p in pairs(panels) do
		if p.Visible then
			activeName = "SH_" .. key
		end
	end
	if not activeName then
		for _, n in ipairs(ORIG_PANELS) do
			local p = gui:FindFirstChild(n)
			if p and p:IsA("GuiObject") and p.Visible then
				activeName = n
				break
			end
		end
	end
	local on = activeValue and activeValue.Value or Theme.map(c3(34, 160, 255))
	local off = inactiveValue and inactiveValue.Value or Theme.map(c3(41, 45, 58))
	local function paint(b)
		if not b then
			return
		end
		local isOn = b.Name == activeName
		Theme.setRaw(b, "BackgroundColor3", isOn and on or off)
		local gl = b:FindFirstChild("Glyph")
		if gl then
			Theme.setRaw(gl, "TextColor3", isOn and Theme.map(c3(255, 255, 255)) or Theme.map(c3(138, 145, 164)))
		end
	end
	for _, n in ipairs(ORIG_BUTTONS) do
		paint(sidebarBtn(n))
	end
	for _, b in pairs(tabButtons) do
		paint(b)
	end
end

local function hookOriginalButtons()
	for _, n in ipairs(ORIG_BUTTONS) do
		local b = sidebarBtn(n)
		if b then
			C(b.MouseButton1Click:Connect(function()
				if alive then
					closeOurTabs()
				end
			end))
		end
	end
	for _, n in ipairs(ORIG_PANELS) do
		local p = gui:FindFirstChild(n)
		if p and p:IsA("GuiObject") then
			C(p:GetPropertyChangedSignal("Visible"):Connect(function()
				task.defer(syncSidebar)
			end))
		end
	end
end

-- resize the sidebar buttons so all tabs fill the sidebar height (bigger buttons, small gaps)
local function fitSidebar()
	if not alive then
		return
	end
	local list = sidebar:FindFirstChildOfClass("UIListLayout")
	if not list then
		return
	end
	local btns = {}
	for _, d in ipairs(sidebar:GetChildren()) do
		if d:IsA("GuiButton") and d.Visible then
			if d:GetAttribute("SH_BX") == nil then
				d:SetAttribute("SH_BX", d.Size.X.Scale)
				d:SetAttribute("SH_BXo", d.Size.X.Offset)
				d:SetAttribute("SH_BY", d.Size.Y.Scale)
				d:SetAttribute("SH_BYo", d.Size.Y.Offset)
			end
			btns[#btns + 1] = d
		end
	end
	if #btns == 0 then
		return
	end
	if list:GetAttribute("SH_BP") == nil then
		list:SetAttribute("SH_BP", list.Padding.Scale)
		list:SetAttribute("SH_BPo", list.Padding.Offset)
	end
	local curF = sidebar:GetAttribute("SH_F") or 1
	local sbH = math.min(sidebar.AbsoluteSize.Y, gui.AbsoluteSize.Y)
	local avail = sbH * 0.96
	local curPad = list.Padding.Offset + list.Padding.Scale * sidebar.AbsoluteSize.Y
	local newPad = math.max(3, math.floor(gui.AbsoluteSize.Y * 0.008))
	local btnH = 0
	for _, d in ipairs(btns) do
		btnH = btnH + d.AbsoluteSize.Y
	end
	local base = btnH / curF
	if base <= 0 then
		return
	end
	local f = math.clamp((avail - newPad * (#btns - 1)) / base, 0.5, 1.6)
	if math.abs(f - curF) < 0.02 and math.abs(curPad - newPad) < 1 then
		return
	end
	sidebar:SetAttribute("SH_F", f)
	for _, d in ipairs(btns) do
		d.Size = UDim2.new(
			d:GetAttribute("SH_BX") * f,
			d:GetAttribute("SH_BXo") * f,
			d:GetAttribute("SH_BY") * f,
			d:GetAttribute("SH_BYo") * f
		)
	end
	list.Padding = UDim.new(0, newPad)
end

local function restoreSidebar()
	local list = sidebar:FindFirstChildOfClass("UIListLayout")
	for _, d in ipairs(sidebar:GetChildren()) do
		if d:IsA("GuiButton") and d:GetAttribute("SH_BX") ~= nil then
			d.Size = UDim2.new(d:GetAttribute("SH_BX"), d:GetAttribute("SH_BXo"), d:GetAttribute("SH_BY"), d:GetAttribute("SH_BYo"))
		end
	end
	if list and list:GetAttribute("SH_BP") ~= nil then
		list.Padding = UDim.new(list:GetAttribute("SH_BP"), list:GetAttribute("SH_BPo"))
	end
	sidebar:SetAttribute("SH_F", nil)
end

-- shared per-frame callbacks
local ticks = {}
C(RunService.Heartbeat:Connect(function(dt)
	for _, fn in ipairs(ticks) do
		fn(dt)
	end
end))

local function setupScriptHub()
local searchbar = hub:FindFirstChild("Searchbar")
local input = dig(hub, "Searchbar", "Input")
local holder = hub:FindFirstChild("Holder")
local template = dig(holder, "Reserved", "OldThumbnail")
local popup = hub:FindFirstChild("Popup")
local overlay = hub:FindFirstChild("DarkOverlay")
local buttons = dig(popup, "Buttons")
local closeBtn = popup and popup:FindFirstChild("ImageButton")

if not (input and holder and template and popup and buttons) then
	return warn("[ScriptHub] UI is missing Searchbar/Input, Holder/Reserved/OldThumbnail or Popup/Buttons.")
end

-- state ---------------------------------------------------------
local engine = Hub.BASE[CFG.DEFAULT_ENGINE] and CFG.DEFAULT_ENGINE or "ScriptBlox"
local query, page, maxPages = "", 0, 1
local loading, reqId = false, 0
local selected = nil

local DOMAIN = {
	ScriptBlox = "scriptblox.com",
	RScripts = "rscripts.net",
	RoScripts = "roscripts.io",
	RobloxScripts = "robloxscripts.com",
	HaxHell = "haxhell.com",
}

local function placeholder(msg)
	input.PlaceholderText = msg or ("Search on " .. DOMAIN[engine] .. "...")
end

local function setText(obj, text)
	if obj and (obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")) then
		obj.Text = tostring(text)
	end
end

local function fmt(n)
	n = tonumber(n) or 0
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

-- layout: 3 per row, bigger cards, scrollable ----------------------
local grid = holder:FindFirstChildOfClass("UIGridLayout")
local L = { cellH = 120, title = 22, para = 17, views = 14 }

local function computeLayout()
	local h = holder.AbsoluteSize.Y
	if h <= 0 then
		h = 400
	end
	L.cellH = math.clamp(math.floor(h / 4 - 10), 96, 230)
	L.title = math.clamp(math.floor(L.cellH * 0.24), 16, 40)
	L.para = math.clamp(math.floor(L.cellH * 0.19), 13, 32)
	L.views = math.clamp(math.floor(L.cellH * 0.15), 12, 26)
end

local function styleLabel(l, size, font)
	if not l then
		return
	end
	l.TextScaled = false
	l.TextWrapped = false
	l.TextSize = size
	l.Font = font
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
end

local function styleCard(c)
	local tf = dig(c, "Overlay", "Title")
	local t, p = dig(tf, "Title"), dig(tf, "Paragraph")
	if tf then
		tf.AnchorPoint = Vector2.new(0, 0)
		tf.Position = UDim2.new(0, 16, 0, 10)
		tf.Size = UDim2.new(1, -32, 0, L.title + L.para + 14)
	end
	if t then
		styleLabel(t, L.title, Enum.Font.GothamBold)
		t.AnchorPoint = Vector2.new(0, 0)
		t.Position = UDim2.new(0, 0, 0, 0)
		t.Size = UDim2.new(1, 0, 0, L.title + 6)
	end
	if p then
		styleLabel(p, L.para, Enum.Font.GothamBold)
		p.AnchorPoint = Vector2.new(0, 0)
		p.Position = UDim2.new(0, 0, 0, L.title + 8)
		p.Size = UDim2.new(1, 0, 0, L.para + 6)
	end
	local vf = dig(c, "Overlay", "Views")
	if vf then
		vf.AnchorPoint = Vector2.new(0, 1)
		vf.Position = UDim2.new(0, 16, 1, -10)
		vf.Size = UDim2.new(1, -32, 0, L.views + 8)
		local vt = vf:FindFirstChild("Title")
		if vt then
			styleLabel(vt, L.views, Enum.Font.GothamBold)
			vt.AnchorPoint = Vector2.new(0, 0)
			vt.Position = UDim2.new(0, 0, 0, 0)
			vt.Size = UDim2.new(1, 0, 1, 0)
		end
	end
end

local function applyLayout()
	computeLayout()
	if grid then
		grid.FillDirectionMaxCells = 3
		grid.FillDirection = Enum.FillDirection.Horizontal
		grid.CellPadding = UDim2.new(0, 10, 0, 10)
		grid.CellSize = UDim2.new(1 / 3, -10, 0, L.cellH)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
	end
	for _, c in ipairs(holder:GetChildren()) do
		if c:GetAttribute("SH_Card") then
			styleCard(c)
		end
	end
end

-- make sure it actually scrolls
holder.ScrollingEnabled = true
holder.ScrollingDirection = Enum.ScrollingDirection.Y
holder.ScrollBarThickness = 6
holder.ScrollBarImageColor3 = Color3.fromRGB(120, 130, 150)
holder.AutomaticCanvasSize = Enum.AutomaticSize.None
local function fixCanvas()
	if grid then
		holder.CanvasSize = UDim2.new(0, 0, 0, grid.AbsoluteContentSize.Y + 16)
	end
end
if grid then
	grid:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fixCanvas)
end
holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyLayout)
applyLayout()
fixCanvas()

-- thumbnails ----------------------------------------------------
local imgDir = CFG.DIR .. "/img"
local function hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

local function ensureFolders()
	if type(makefolder) ~= "function" or type(isfolder) ~= "function" then
		return
	end
	pcall(function()
		if not isfolder(CFG.DIR) then
			makefolder(CFG.DIR)
		end
		if not isfolder(imgDir) then
			makefolder(imgDir)
		end
	end)
end

local function loadThumb(item, imageObj)
	if not (CFG.THUMBNAILS and item.image) then
		return
	end
	if type(writefile) ~= "function" or type(getcustomasset) ~= "function" or type(isfile) ~= "function" then
		return
	end
	task.spawn(function()
		pcall(function()
			ensureFolders()
			local path = imgDir .. "/" .. hash(item.image) .. ".png"
			if not isfile(path) then
				local body = Hub.httpGet(item.image, { Referer = Hub.BASE[item.engine], Accept = "image/*" })
				if type(body) ~= "string" or #body < 16 then
					return
				end
				local isPng = body:sub(2, 4) == "PNG"
				local isJpg = body:sub(1, 2) == "\255\216"
				if not (isPng or isJpg) then
					return -- webp/html etc. can't be shown by Roblox
				end
				writefile(path, body)
			end
			local asset = getcustomasset(path)
			if imageObj and imageObj.Parent then
				imageObj.Image = asset
			end
		end)
	end)
end

-- popup ---------------------------------------------------------
local function openPopup(item)
	selected = item
	if overlay then
		overlay.BackgroundTransparency = 0.5
		overlay.Visible = true
	end
	popup.Visible = true
end

local function closePopup()
	popup.Visible = false
	if overlay then
		overlay.Visible = false
	end
end

if overlay then
	overlay.Visible = false
end

-- cards ---------------------------------------------------------
local function clearCards()
	for _, c in ipairs(holder:GetChildren()) do
		if c:GetAttribute("SH_Card") then
			c:Destroy()
		end
	end
end

local function makeCard(item, order)
	local c = template:Clone()
	Theme.adopt(c, template)
	c.Name = "SH_Card"
	c:SetAttribute("SH_Card", true)
	c.LayoutOrder = order
	c.Visible = true
	setText(dig(c, "Overlay", "Title", "Title"), item.title .. (item.verified and "  \226\156\148" or ""))
	setText(
		dig(c, "Overlay", "Title", "Paragraph"),
		item.game .. " | " .. (item.key and "Key" or "Keyless") .. (item.patched and " | Patched" or "")
	)
	local v = dig(c, "Overlay", "Title", "Verified")
	if v then
		v.Visible = false
	end
	setText(dig(c, "Overlay", "Views", "Title"), fmt(item.views) .. " Views")
	c.MouseButton1Click:Connect(function()
		openPopup(item)
	end)
	styleCard(c)
	c.Parent = holder
	loadThumb(item, c)
end

local cardCount = 0
local function load(reset)
	if not alive then
		return
	end
	if reset then
		reqId = reqId + 1
		page, maxPages, cardCount = 0, 1, 0
		loading = false
		clearCards()
		pcall(function()
			holder.CanvasPosition = Vector2.new(0, 0)
		end)
	end
	if loading or page >= maxPages then
		return
	end
	loading = true
	local id = reqId
	local nextPage = page + 1
	placeholder("Loading...")
	task.spawn(function()
		local res, err = Hub.search(engine, query, nextPage, query == "")
		if id ~= reqId then
			return
		end
		loading = false
		if not res then
			placeholder(err)
			warn("[ScriptHub] " .. tostring(err))
			return
		end
		page, maxPages = res.page, res.maxPages
		if #res.scripts == 0 and cardCount == 0 then
			placeholder("No scripts found")
			return
		end
		placeholder()
		for _, item in ipairs(res.scripts) do
			cardCount = cardCount + 1
			makeCard(item, cardCount)
		end
	end)
end

-- infinite scroll
holder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if holder.CanvasPosition.Y + holder.AbsoluteWindowSize.Y >= holder.AbsoluteCanvasSize.Y - 80 then
		load(false)
	end
end)

-- search + engine switch ----------------------------------------
input.FocusLost:Connect(function(enter)
	if enter and alive then
		query = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
		load(true)
	end
end)

local engBtn = Instance.new("TextButton")
engBtn.Name = "SH_Engine"
engBtn.AnchorPoint = Vector2.new(1, 0.5)
engBtn.Position = UDim2.new(1, -10, 0.5, 0)
engBtn.AutomaticSize = Enum.AutomaticSize.X
engBtn.Size = UDim2.new(0, 0, 0.66, 0)
engBtn.BackgroundColor3 = Color3.fromRGB(79, 164, 242)
engBtn.BorderSizePixel = 0
engBtn.TextColor3 = Color3.new(1, 1, 1)
engBtn.Font = Enum.Font.GothamBold
engBtn.TextScaled = false
engBtn.TextSize = math.clamp(math.floor(searchbar.AbsoluteSize.Y * 0.36), 14, 30)
engBtn.TextWrapped = false
engBtn.ZIndex = 10
engBtn.Text = engine
engBtn.Parent = searchbar
M(engBtn)
Instance.new("UICorner", engBtn).CornerRadius = UDim.new(0, 10)
local pad = Instance.new("UIPadding", engBtn)
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
Theme.scan(engBtn)

-- keep the text box from running underneath the button
local baseSize = input.Size
local function fitInput()
	local w = engBtn.AbsoluteSize.X + 24
	input.ClipsDescendants = true
	input.Size = UDim2.new(baseSize.X.Scale, baseSize.X.Offset - w, baseSize.Y.Scale, baseSize.Y.Offset)
end
engBtn:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitInput)
task.defer(fitInput)

engBtn.MouseButton1Click:Connect(function()
	if not alive then
		return
	end
	engine = Hub.next(engine)
	engBtn.Text = engine
	placeholder()
	load(true)
end)

-- popup buttons -------------------------------------------------
local function flash(btn, text)
	local lbl = btn and btn:FindFirstChild("Title")
	if not lbl then
		return
	end
	local old = lbl.Text
	lbl.Text = text
	task.delay(1.2, function()
		if lbl.Parent then
			lbl.Text = old
		end
	end)
end

local function safeName(s)
	return (tostring(s):gsub("[^%w%-_ ]", ""):gsub("%s+", "_")):sub(1, 40)
end

local function findEditorBox()
	local ex = hub.Parent and hub.Parent:FindFirstChild("Executor")
	if not ex then
		return nil
	end
	for _, d in ipairs(ex:GetDescendants()) do
		if d:IsA("TextBox") and d.Parent and d.Parent.Name == "Code" and d.Visible
			and d:IsDescendantOf(ex) then
			-- skip the hidden template copies in Reserved
			local inReserved = false
			local p = d.Parent
			while p and p ~= ex do
				if p.Name == "Reserved" then
					inReserved = true
					break
				end
				p = p.Parent
			end
			if not inReserved then
				return d
			end
		end
	end
	return nil
end

local b1, b2, b3, b4 = buttons:FindFirstChild("Button1"), buttons:FindFirstChild("Button2"),
	buttons:FindFirstChild("Button3"), buttons:FindFirstChild("Button4")

if b1 then
	b1.MouseButton1Click:Connect(function()
		if not alive or not selected then
			return
		end
		local ok, err = Hub.run(selected)
		flash(b1, ok and "EXECUTED" or "FAILED")
		if not ok then
			warn("[ScriptHub] " .. tostring(err))
		end
		if ok then
			closePopup()
		end
	end)
end

if b2 then
	b2.MouseButton1Click:Connect(function()
		if not alive or not selected then
			return
		end
		local src, err = Hub.getSource(selected)
		if not src then
			flash(b2, "FAILED")
			return warn("[ScriptHub] " .. tostring(err))
		end
		local box = findEditorBox()
		if box then
			box.Text = src
			flash(b2, "OPENED")
			closePopup()
		elseif type(setclipboard) == "function" then
			setclipboard(src)
			flash(b2, "NO EDITOR - COPIED")
		else
			flash(b2, "NO EDITOR")
		end
	end)
end

if b3 then
	b3.MouseButton1Click:Connect(function()
		if not alive or not selected then
			return
		end
		if type(writefile) ~= "function" then
			return flash(b3, "NO WRITEFILE")
		end
		local src, err = Hub.getSource(selected)
		if not src then
			flash(b3, "FAILED")
			return warn("[ScriptHub] " .. tostring(err))
		end
		ensureFolders()
		local ok = pcall(writefile, CFG.DIR .. "/" .. safeName(selected.title) .. ".lua", src)
		flash(b3, ok and "SAVED" or "FAILED")
	end)
end

if b4 then
	b4.MouseButton1Click:Connect(function()
		if not alive or not selected then
			return
		end
		local ok, err = Hub.copy(selected)
		flash(b4, ok and "COPIED" or "FAILED")
		if not ok then
			warn("[ScriptHub] " .. tostring(err))
		end
	end)
end

if closeBtn then
	closeBtn.MouseButton1Click:Connect(function()
		if alive then
			closePopup()
		end
	end)
end

-- first load when the tab is opened -----------------------------
placeholder()
hub:GetPropertyChangedSignal("Visible"):Connect(function()
	if hub.Visible and cardCount == 0 and not loading then
		load(true)
	end
end)
if hub.Visible then
	load(true)
end

	return function()
		clearCards()
		if overlay then
			overlay.Visible = false
		end
		popup.Visible = false
	end
end

------------------------------------------------------------------
-- MUSIC TAB
------------------------------------------------------------------
local function setupMusic()
	local panel, holder, input = makePanel("Music", "Add: asset ID, audio URL or file name (ScriptHub/Music)...")
	local MUSIC_DIR = CFG.DIR .. "/Music"

	local mc = type(config.music) == "table" and config.music or {}
	config.music = mc
	mc.volume = tonumber(mc.volume) or 0.6
	mc.speed = tonumber(mc.speed) or 1
	local tracks = {}
	if type(mc.tracks) == "table" then
		for _, t in ipairs(mc.tracks) do
			if type(t) == "table" and t.kind and t.src then
				tracks[#tracks + 1] = { name = tostring(t.name or t.src), kind = t.kind, src = tostring(t.src) }
			end
		end
	end
	local function persist()
		local list = {}
		for i, t in ipairs(tracks) do
			list[i] = { name = t.name, kind = t.kind, src = t.src }
		end
		mc.tracks = list
		saveConfig()
	end

	local snd = M(Instance.new("Sound"))
	snd.Name = "SH_MusicPlayer"
	snd.Volume = mc.volume
	snd.PlaybackSpeed = mc.speed
	snd.Looped = mc.loop == true
	snd.Parent = SoundService

	local cur = 0
	local rebuildList, playIndex
	local setStatus, setTitle

	-- ---------------------------------------------------------- now playing card
	header(holder, "Now playing")
	local h = math.floor(U * 11)
	local card = rowFrame(holder, h, "now playing")
	local titleL = label(card, {
		Text = "Nothing playing",
		Font = S.bold,
		TextSize = math.floor(U * 1.15),
		Position = UDim2.new(0, PAD, 0, math.floor(U * 0.7)),
		Size = UDim2.new(1, -PAD * 2, 0, math.floor(U * 1.6)),
	})
	local statusL = label(card, {
		Text = "Add a track below, or scan your music folder.",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.8),
		Position = UDim2.new(0, PAD, 0, math.floor(U * 2.4)),
		Size = UDim2.new(1, -PAD * 2, 0, math.floor(U * 1.2)),
	})
	function setTitle(t)
		titleL.Text = t
	end
	function setStatus(t)
		statusL.Text = t
	end

	local seekY = math.floor(U * 4.9)
	local seek = mk("Frame", {
		BackgroundColor3 = S.track,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD, 0, seekY),
		Size = UDim2.new(1, -PAD * 2, 0, math.max(6, math.floor(U * 0.5))),
	}, card)
	corner(seek, UDim.new(1, 0))
	local seekFill = mk("Frame", { BackgroundColor3 = S.swOn, BorderSizePixel = 0, Size = UDim2.new(0, 0, 1, 0) }, seek)
	corner(seekFill, UDim.new(1, 0))
	local kd = math.floor(U * 1.1)
	local seekKnob = mk("Frame", {
		BackgroundColor3 = S.knobOn,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, kd, 0, kd),
		Position = UDim2.new(0, 0, 0.5, 0),
	}, seek)
	corner(seekKnob, UDim.new(1, 0))
	local seekHit = mk("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, math.floor(U * 2.6)),
	}, seek)
	local tL = label(card, {
		Text = "0:00",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.8),
		Position = UDim2.new(0, PAD, 0, math.floor(U * 5.7)),
		Size = UDim2.new(0.5, -PAD, 0, math.floor(U * 1.2)),
	})
	local tR = label(card, {
		Text = "0:00",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.8),
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.5, 0, 0, math.floor(U * 5.7)),
		Size = UDim2.new(0.5, -PAD, 0, math.floor(U * 1.2)),
	})
	bindDrag(seekHit, function(fr)
		if snd.TimeLength > 0 then
			snd.TimePosition = fr * snd.TimeLength
		end
	end, holder)

	local btnRow = mk("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -math.floor(U * 0.7)),
		Size = UDim2.new(1, -PAD * 2, 0, math.floor(U * 2.4)),
	}, card)
	mk("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, math.floor(U * 0.7)),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, btnRow)
	local prevB = pill(btnRow, "Prev", S.ctrl, S.title)
	prevB.LayoutOrder = 1
	local playB = pill(btnRow, "Play", S.btn, S.btnText, math.floor(U * 6))
	playB.LayoutOrder = 2
	local nextB = pill(btnRow, "Next", S.ctrl, S.title)
	nextB.LayoutOrder = 3
	local stopB = pill(btnRow, "Stop", S.ctrl, S.title)
	stopB.LayoutOrder = 4

	-- ---------------------------------------------------------- audio logic
	local function extOf(s)
		s = tostring(s):lower()
		return s:match("%.(mp3)") or s:match("%.(ogg)") or s:match("%.(wav)") or s:match("%.(flac)") or "mp3"
	end

	local function resolve(tr)
		if tr.kind == "id" then
			return "rbxassetid://" .. tr.src
		end
		if type(getcustomasset) ~= "function" or not fsOK then
			return nil, "Needs writefile + getcustomasset"
		end
		if tr.kind == "file" then
			local ok, a = pcall(getcustomasset, tr.src)
			if ok and a then
				return a
			end
			return nil, "Could not load file"
		end
		if tr.kind == "url" then
			ensureFolder(CFG.DIR)
			ensureFolder(MUSIC_DIR)
			local path = MUSIC_DIR .. "/dl_" .. hash(tr.src) .. "." .. extOf(tr.src)
			if not isfile(path) then
				local body = Hub.httpGet(tr.src, { Accept = "*/*" })
				if type(body) ~= "string" or #body < 64 then
					return nil, "Download failed"
				end
				pcall(writefile, path, body)
			end
			local ok, a = pcall(getcustomasset, path)
			if ok and a then
				return a
			end
			return nil, "Could not load download"
		end
		return nil, "Unknown source"
	end

	local function nextIndex(dir)
		if #tracks == 0 then
			return 0
		end
		if mc.shuffle and dir > 0 and #tracks > 1 then
			local i
			repeat
				i = math.random(#tracks)
			until i ~= cur
			return i
		end
		local i = cur + dir
		if i > #tracks then
			i = 1
		elseif i < 1 then
			i = #tracks
		end
		return i
	end

	function playIndex(i)
		local tr = tracks[i]
		if not tr then
			return
		end
		cur = i
		setTitle(tr.name)
		setStatus("Loading...")
		rebuildList()
		task.spawn(function()
			local asset, err = resolve(tr)
			if not alive or cur ~= i then
				return
			end
			if not asset then
				setStatus(err or "Failed")
				return
			end
			snd:Stop()
			snd.SoundId = asset
			snd.TimePosition = 0
			snd:Play()
			local t0 = os.clock()
			while alive and cur == i and not snd.IsLoaded and os.clock() - t0 < 8 do
				task.wait(0.1)
			end
			if alive and cur == i then
				if snd.IsLoaded then
					setStatus("Playing  (" .. tr.kind .. ")")
				else
					setStatus("Failed to load (private or blocked asset?)")
				end
			end
		end)
	end

	C(snd.Ended:Connect(function()
		if not alive or mc.loop then
			return
		end
		local n = nextIndex(1)
		if n > 0 then
			playIndex(n)
		end
	end))

	C(playB.MouseButton1Click:Connect(function()
		if snd.IsPlaying then
			snd:Pause()
		elseif snd.TimePosition > 0 and snd.SoundId ~= "" then
			snd:Resume()
		elseif #tracks > 0 then
			playIndex(cur > 0 and cur or 1)
		end
	end))
	C(prevB.MouseButton1Click:Connect(function()
		local n = nextIndex(-1)
		if n > 0 then
			playIndex(n)
		end
	end))
	C(nextB.MouseButton1Click:Connect(function()
		local n = nextIndex(1)
		if n > 0 then
			playIndex(n)
		end
	end))
	C(stopB.MouseButton1Click:Connect(function()
		snd:Stop()
		setStatus("Stopped")
	end))

	local function fmtTime(t)
		t = math.max(0, math.floor(t))
		return string.format("%d:%02d", math.floor(t / 60), t % 60)
	end
	local lastPlayTxt = "Play"
	ticks[#ticks + 1] = function()
		if not alive or not panel.Visible then
			return
		end
		local len = snd.TimeLength
		if len > 0 then
			local fr = math.clamp(snd.TimePosition / len, 0, 1)
			seekFill.Size = UDim2.new(fr, 0, 1, 0)
			seekKnob.Position = UDim2.new(fr, 0, 0.5, 0)
			tL.Text = fmtTime(snd.TimePosition)
			tR.Text = fmtTime(len)
		end
		local txt = snd.IsPlaying and "Pause" or "Play"
		if txt ~= lastPlayTxt then
			lastPlayTxt = txt
			pillText(playB, txt)
		end
	end

	-- ---------------------------------------------------------- controls
	header(holder, "Controls")
	sliderRow(holder, "Volume", 0, 2, mc.volume, function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end, function(v)
		mc.volume = v
		snd.Volume = v
		saveConfig()
	end, 0.01)
	sliderRow(holder, "Speed", 0.25, 2, mc.speed, function(v)
		return string.format("%.2fx", v)
	end, function(v)
		mc.speed = v
		snd.PlaybackSpeed = v
		saveConfig()
	end, 0.05)
	toggleRow(holder, "Loop track", "Repeat the current track forever", mc.loop == true, function(on)
		mc.loop = on
		snd.Looped = on
		saveConfig()
	end)
	toggleRow(holder, "Shuffle", "Play a random track after each one", mc.shuffle == true, function(on)
		mc.shuffle = on
		saveConfig()
	end)

	-- ---------------------------------------------------------- playlist
	local function addTrack(kind, src, name, play)
		for i, t in ipairs(tracks) do
			if t.kind == kind and t.src == src then
				if play then
					playIndex(i)
				end
				return
			end
		end
		tracks[#tracks + 1] = { kind = kind, src = src, name = name or src }
		persist()
		rebuildList()
		if play then
			playIndex(#tracks)
		end
	end

	local function scanFolder()
		if type(listfiles) ~= "function" then
			setStatus("listfiles is not available in this executor")
			return
		end
		ensureFolder(CFG.DIR)
		ensureFolder(MUSIC_DIR)
		local ok, files = pcall(listfiles, MUSIC_DIR)
		if not ok or type(files) ~= "table" then
			setStatus("Could not read " .. MUSIC_DIR)
			return
		end
		local n = 0
		for _, p in ipairs(files) do
			p = tostring(p):gsub("\\", "/")
			local nm = p:match("([^/]+)$") or p
			local ext = nm:lower():match("%.(%w+)$")
			if (ext == "mp3" or ext == "ogg" or ext == "wav" or ext == "flac") and not nm:match("^dl_") then
				local exists = false
				for _, t in ipairs(tracks) do
					if t.src == p then
						exists = true
						break
					end
				end
				if not exists then
					tracks[#tracks + 1] = { kind = "file", src = p, name = (nm:gsub("%.%w+$", "")) }
					n = n + 1
				end
			end
		end
		persist()
		rebuildList()
		setStatus(string.format("Scan done: %d new file(s) in %s", n, MUSIC_DIR))
	end

	buttonRow(holder, "Music folder", "Put .mp3/.ogg/.wav files in " .. MUSIC_DIR, "Scan", function()
		scanFolder()
	end)
	buttonRow(holder, "Clear playlist", "Remove every track from the list", "Clear", function()
		snd:Stop()
		tracks = {}
		cur = 0
		persist()
		rebuildList()
		setTitle("Nothing playing")
		setStatus("Playlist cleared")
	end)

	header(holder, "Playlist")
	local plHeaderOrder = holder:GetAttribute("SH_n")

	function rebuildList()
		for _, c in ipairs(holder:GetChildren()) do
			if c:GetAttribute("SH_Track") then
				c:Destroy()
			end
		end
		holder:SetAttribute("SH_n", plHeaderOrder)
		if #tracks == 0 then
			local f = rowFrame(holder, math.floor(U * 3), nil)
			f:SetAttribute("SH_Track", true)
			label(f, {
				Text = "No tracks yet. Type an asset ID or URL in the box above, or press Scan.",
				TextColor3 = S.desc,
				TextSize = math.floor(U * 0.85),
				TextWrapped = true,
				Position = UDim2.new(0, PAD, 0, 0),
				Size = UDim2.new(1, -PAD * 2, 1, 0),
			})
			Theme.scan(f)
			return
		end
		for i, tr in ipairs(tracks) do
			local isCur = i == cur
			local f = rowFrame(holder, math.floor(U * 3.2), nil)
			f:SetAttribute("SH_Track", true)
			Theme.paint(f, "BackgroundColor3", isCur and S.rowOn or S.rowBg)
			label(f, {
				Text = string.format("%d.  %s", i, tr.name),
				Font = isCur and S.bold or S.font,
				Position = UDim2.new(0, PAD, 0, 0),
				Size = UDim2.new(1, -(PAD * 3 + math.floor(U * 4)), 1, 0),
			})
			local play = mk("TextButton", {
				Text = "",
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Size = UDim2.new(1, -(PAD * 2 + math.floor(U * 4)), 1, 0),
			}, f)
			C(play.MouseButton1Click:Connect(function()
				playIndex(i)
			end))
			local rm = pill(f, "Remove", S.ctrl, S.desc)
			rm.AnchorPoint = Vector2.new(1, 0.5)
			rm.Position = UDim2.new(1, -PAD, 0.5, 0)
			C(rm.MouseButton1Click:Connect(function()
				table.remove(tracks, i)
				if cur == i then
					snd:Stop()
					cur = 0
				elseif cur > i then
					cur = cur - 1
				end
				persist()
				rebuildList()
			end))
			Theme.scan(f)
		end
	end

	-- add by typing in the search box
	C(input.FocusLost:Connect(function(enter)
		if not (enter and alive) then
			return
		end
		local txt = input.Text:gsub("^%s+", ""):gsub("%s+$", "")
		input.Text = ""
		if txt == "" then
			return
		end
		local id = txt:match("^rbxassetid://(%d+)$") or txt:match("^(%d+)$") or txt:match("roblox%.com/[%w%-/]*/(%d+)")
		if id then
			addTrack("id", id, "Asset " .. id, true)
		elseif txt:match("^https?://") then
			local nm = txt:match("([^/]+)$") or txt
			nm = (nm:gsub("%?.*$", ""):gsub("%.%w+$", ""))
			addTrack("url", txt, nm ~= "" and nm or txt, true)
		else
			local path = MUSIC_DIR .. "/" .. txt
			if fsOK and isfile(path) then
				addTrack("file", path, (txt:gsub("%.%w+$", "")), true)
			else
				setStatus("Not found: " .. txt)
			end
		end
	end))

	rebuildList()
	Theme.scan(panel)
	registerTab("Music", "\226\153\170")

	return function()
		pcall(function()
			snd:Stop()
			snd:Destroy()
		end)
	end
end

------------------------------------------------------------------
-- DELTA LOGO OUTLINE TAB
------------------------------------------------------------------
local function setupLogo()
	local panel, holder, input = makePanel("Logo", "Search logo options...")
	bindFilter(input, holder)

	local lc = type(config.logo) == "table" and config.logo or {}
	config.logo = lc
	lc.mode = lc.mode or "rainbow" -- rainbow | custom | solid | original
	if lc.spin == nil then
		lc.spin = true
	end
	lc.speed = tonumber(lc.speed) or 120
	lc.reverse = lc.reverse == true
	lc.c1 = lc.c1 or "ff3b3b"
	lc.c2 = lc.c2 or "3b8bff"
	lc.c3 = lc.c3 or "3bff8b"

	local icon = { btn = nil, stroke = nil, grad = nil, corner = nil, madeStroke = false, orig = {} }

	local findIcon = findDeltaIcon

	local function attach(btn)
		icon.btn = btn
		local stroke = btn:FindFirstChildOfClass("UIStroke") or btn:FindFirstChildWhichIsA("UIStroke", true)
		icon.madeStroke = false
		if not stroke then
			stroke = Instance.new("UIStroke")
			stroke.Name = "SH_Stroke"
			stroke.Thickness = 2
			stroke.Color = c3(255, 255, 255)
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Parent = btn
			icon.madeStroke = true
		end
		icon.stroke = stroke
		icon.orig = {
			color = stroke.Color,
			thick = stroke.Thickness,
			trans = stroke.Transparency,
		}
		icon.corner = btn:FindFirstChildOfClass("UICorner") or btn:FindFirstChildWhichIsA("UICorner", true)
		icon.orig.radius = icon.corner and icon.corner.CornerRadius or nil
		local g = stroke:FindFirstChild("SH_Gradient")
		if not g then
			g = Instance.new("UIGradient")
			g.Name = "SH_Gradient"
			g.Enabled = false
			g.Parent = stroke
		end
		icon.grad = g
	end

	-- preview ring inside the panel
	local previewStroke, previewGrad
	local statusLabel

	local function col(k)
		return fromHex(lc[k]) or c3(255, 255, 255)
	end

	local function sequence()
		if lc.mode == "rainbow" then
			local kps = {}
			for i = 0, 6 do
				kps[#kps + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6 % 1, 1, 1))
			end
			kps[#kps] = ColorSequenceKeypoint.new(1, Color3.fromHSV(0, 1, 1))
			return ColorSequence.new(kps)
		end
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, col("c1")),
			ColorSequenceKeypoint.new(0.333, col("c2")),
			ColorSequenceKeypoint.new(0.666, col("c3")),
			ColorSequenceKeypoint.new(1, col("c1")),
		})
	end

	local function style(stroke, grad, isPreview)
		if not (stroke and grad) then
			return
		end
		if lc.mode == "original" and not isPreview then
			stroke.Color = icon.orig.color or c3(255, 255, 255)
			grad.Enabled = false
		elseif lc.mode == "solid" or (lc.mode == "original" and isPreview) then
			stroke.Color = lc.mode == "solid" and col("c1") or (icon.orig.color or c3(255, 255, 255))
			grad.Enabled = false
		else
			stroke.Color = c3(255, 255, 255)
			grad.Color = sequence()
			grad.Enabled = true
		end
	end

	local function applyShape(stroke)
		if not stroke then
			return
		end
		stroke.Thickness = lc.thick or icon.orig.thick or 2
		stroke.Transparency = lc.trans or icon.orig.trans or 0
	end

	local function applyAll()
		if icon.stroke and icon.stroke.Parent then
			style(icon.stroke, icon.grad, false)
			applyShape(icon.stroke)
			if icon.corner then
				if lc.round then
					icon.corner.CornerRadius = UDim.new(lc.round * 0.5, 0)
				elseif icon.orig.radius then
					icon.corner.CornerRadius = icon.orig.radius
				end
			end
		end
		if previewStroke then
			style(previewStroke, previewGrad, true)
			previewStroke.Thickness = math.max(2, (lc.thick or icon.orig.thick or 2) * 1.6)
			previewStroke.Transparency = lc.trans or 0
		end
	end

	local function refreshStatus()
		if statusLabel then
			statusLabel.Text = (icon.btn and icon.btn.Parent) and "Delta icon found. Changes apply live."
				or "Delta icon not found yet. Close and reopen Delta's menu, then it will attach."
		end
	end

	-- ------------------------------------------------------------ UI
	header(holder, "Preview")
	local pc = rowFrame(holder, math.floor(U * 8.4), "preview")
	local ring = mk("Frame", {
		Name = "Ring",
		BackgroundColor3 = c3(20, 22, 28),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, PAD, 0.5, 0),
		Size = UDim2.new(0, math.floor(U * 5.6), 0, math.floor(U * 5.6)),
	}, pc)
	ring:SetAttribute("SH_NoTheme", true)
	corner(ring, UDim.new(ROUND.ratio, 0))
	previewStroke = mk("UIStroke", { Thickness = 4, Color = c3(255, 255, 255), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ring)
	previewGrad = mk("UIGradient", {}, previewStroke)
	label(ring, {
		Text = "\206\148",
		Font = S.bold,
		TextSize = math.floor(U * 2.6),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
	})
	statusLabel = label(pc, {
		Text = "",
		TextColor3 = S.desc,
		TextSize = math.floor(U * 0.85),
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.None,
		TextYAlignment = Enum.TextYAlignment.Center,
		Position = UDim2.new(0, PAD * 2 + math.floor(U * 5.6), 0, 0),
		Size = UDim2.new(1, -(PAD * 3 + math.floor(U * 5.6)), 1, 0),
	})

	header(holder, "Outline style")
	segmented(holder, "Style", {
		{ key = "rainbow", label = "Rainbow" },
		{ key = "custom", label = "Custom" },
		{ key = "solid", label = "Solid" },
		{ key = "original", label = "Original" },
	}, lc.mode, function(k)
		lc.mode = k
		applyAll()
		saveConfig()
	end)
	toggleRow(holder, "Spin", "Rotate the gradient around the logo", lc.spin, function(on)
		lc.spin = on
		saveConfig()
	end)
	sliderRow(holder, "Spin speed", 0, 720, lc.speed, function(v)
		return string.format("%d deg/s", math.floor(v + 0.5))
	end, function(v)
		lc.speed = v
		saveConfig()
	end, 5)
	toggleRow(holder, "Reverse spin", "Spin the other direction", lc.reverse, function(on)
		lc.reverse = on
		saveConfig()
	end)

	header(holder, "Gradient colors")
	for i, k in ipairs({ "c1", "c2", "c3" }) do
		colorRow(holder, (i == 1) and "Color 1 (also used for Solid)" or ("Color " .. i), function()
			return col(k)
		end, function(c)
			lc[k] = hexOf(c)
			applyAll()
			saveConfig()
		end)
	end

	header(holder, "Shape")
	sliderRow(holder, "Outline thickness", 0, 10, lc.thick or 2, function(v)
		return string.format("%.1f", v)
	end, function(v)
		lc.thick = v
		applyAll()
		saveConfig()
	end, 0.5)
	sliderRow(holder, "Outline transparency", 0, 1, lc.trans or 0, function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end, function(v)
		lc.trans = v
		applyAll()
		saveConfig()
	end, 0.05)
	sliderRow(holder, "Roundness", 0, 1, lc.round or 1, function(v)
		return string.format("%d%%", math.floor(v * 100 + 0.5))
	end, function(v)
		lc.round = v
		applyAll()
		saveConfig()
	end, 0.05)
	buttonRow(holder, "Reset logo", "Restore Delta's original outline", "Reset", function()
		lc.mode = "original"
		lc.thick, lc.trans, lc.round = nil, nil, nil
		applyAll()
		saveConfig()
	end)

	-- ------------------------------------------------------------ animation
	local rot, timer = 0, 0
	ticks[#ticks + 1] = function(dt)
		if not alive then
			return
		end
		timer = timer + dt
		if timer > 2 then
			timer = 0
			if not (icon.btn and icon.btn.Parent) then
				local b = findIcon()
				if b then
					attach(b)
					applyAll()
				end
				refreshStatus()
			end
		end
		if lc.spin and (lc.mode == "rainbow" or lc.mode == "custom") then
			rot = (rot + (lc.reverse and -1 or 1) * lc.speed * dt) % 360
			if icon.grad and icon.grad.Parent then
				icon.grad.Rotation = rot
			end
			if panel.Visible and previewGrad then
				previewGrad.Rotation = rot
			end
		end
	end

	local b = findIcon()
	if b then
		attach(b)
	end
	refreshStatus()
	Theme.scan(panel)
	applyAll()
	registerTab("Logo", "\226\151\142")

	return function()
		if icon.stroke then
			pcall(function()
				if icon.madeStroke then
					icon.stroke:Destroy()
				else
					icon.stroke.Color = icon.orig.color
					icon.stroke.Thickness = icon.orig.thick
					icon.stroke.Transparency = icon.orig.trans
					if icon.grad then
						icon.grad:Destroy()
					end
				end
				if icon.corner and icon.orig.radius then
					icon.corner.CornerRadius = icon.orig.radius
				end
			end)
		end
	end
end

------------------------------------------------------------------
-- COLORS + THEMES TAB
------------------------------------------------------------------
local function setupColors()
	local panel, holder, input = makePanel("Colors", "Search themes and colors...")
	bindFilter(input, holder)

	header(holder, "Themes")
	local themeRows = {}
	local currentLbl

	local function refreshRows()
		for name, r in pairs(themeRows) do
			local sel = name == Theme.name
			Theme.paint(r.frame, "BackgroundColor3", sel and S.rowOn or S.rowBg)
			r.title.Font = sel and S.bold or S.font
		end
		if currentLbl then
			currentLbl.Text = "Current: " .. Theme.name
		end
	end

	local pickers = {}
	for _, def in ipairs(Theme.list) do
		local f = rowFrame(holder, math.floor(U * 3.4), def.name)
		local t = label(f, {
			Text = def.name,
			Position = UDim2.new(0, PAD, 0, 0),
			Size = UDim2.new(0.5, -PAD, 1, 0),
		})
		local sw = mk("Frame", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -PAD, 0.5, 0),
			Size = UDim2.new(0.5, -PAD, 0, math.floor(U * 1.8)),
		}, f)
		sw:SetAttribute("SH_NoTheme", true)
		mk("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, math.floor(U * 0.35)),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}, sw)
		for i, role in ipairs({ "bg", "surface", "surface2", "accent", "text" }) do
			local dot = mk("Frame", {
				BackgroundColor3 = def.roles[role],
				BorderSizePixel = 0,
				LayoutOrder = i,
				Size = UDim2.new(0, math.floor(U * 1.8), 0, math.floor(U * 1.8)),
			}, sw)
			corner(dot, UDim.new(math.min(ROUND.ratio + 0.12, 0.5), 0))
			mk("UIStroke", { Color = c3(255, 255, 255), Transparency = 0.8, Thickness = 1 }, dot)
		end
		local hit = mk("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = f.ZIndex + 5,
		}, f)
		C(hit.MouseButton1Click:Connect(function()
			if alive then
				Theme.set(def)
			end
		end))
		themeRows[def.name] = { frame = f, title = t }
	end

	local cur = rowFrame(holder, math.floor(U * 2.6), "current theme")
	currentLbl = label(cur, {
		Text = "",
		TextColor3 = S.desc,
		Font = S.bold,
		Position = UDim2.new(0, PAD, 0, 0),
		Size = UDim2.new(1, -PAD * 2, 1, 0),
	})

	header(holder, "Custom colors")
	for _, role in ipairs(Theme.ROLES) do
		local api = colorRow(holder, Theme.LABEL[role], function()
			return Theme.roles[role]
		end, function(c)
			Theme.setRole(role, c)
		end)
		pickers[#pickers + 1] = api
	end
	buttonRow(holder, "Reset colors", "Go back to Delta's original look", "Reset", function()
		Theme.set(Theme.list[1])
	end)

	header(holder, "Fonts")
	toggleRow(holder, "Bold fonts", "Make every text in the Delta UI bold", config.bold ~= false, function(on)
		config.bold = on
		Fonts.set(on)
		saveConfig()
	end)

	Theme.onChange = function()
		refreshRows()
		for _, p in ipairs(pickers) do
			p.Refresh()
		end
	end

	Theme.scan(panel)
	refreshRows()
	registerTab("Colors", "\226\151\144")
end

------------------------------------------------------------------
-- Build everything
------------------------------------------------------------------
local cleanups = {}
local function build(name, fn)
	local ok, res = xpcall(fn, function(e)
		return tostring(e) .. "\n" .. debug.traceback()
	end)
	if not ok then
		warn("[ScriptHub] " .. name .. " failed: " .. tostring(res))
	else
		print("[ScriptHub] " .. name .. " ready")
		if type(res) == "function" then
			cleanups[#cleanups + 1] = res
		end
	end
end

build("ScriptHub", setupScriptHub)
build("Music tab", setupMusic)
build("Logo tab", setupLogo)
build("Colors tab", setupColors)
hookOriginalButtons()

-- capture every color in the Delta UI (before any theme is applied)
local okScan, errScan = pcall(Theme.scan, gui, true)
if not okScan then
	warn("[ScriptHub] scan error: " .. tostring(errScan))
end

-- anything Delta creates later (cloned cards, editor tabs, popups...) gets themed too
local function underNoTheme(d)
	local p = d
	while p and p ~= gui do
		if p:GetAttribute("SH_NoTheme") then
			return true
		end
		p = p.Parent
	end
	return false
end
C(gui.DescendantAdded:Connect(function(d)
	if not alive then
		return
	end
	task.defer(function()
		if not (alive and d.Parent) or underNoTheme(d) then
			return
		end
		Theme.adoptNew(d)
		if Fonts.on then
			Fonts.bold(d)
		end
	end)
end))
Theme.afterApply = function()
	syncSidebar()
end

do
	local saved = config.theme
	if type(saved) == "table" and saved.name then
		local def = Theme.byName(saved.name)
		if saved.name == "Custom" and type(saved.roles) == "table" then
			local roles = Theme.copyRoles(Theme.DEFAULT)
			for k, v in pairs(saved.roles) do
				local c = fromHex(v)
				if c and roles[k] then
					roles[k] = c
				end
			end
			def = { name = "Custom", roles = roles }
		end
		if def then
			Theme.set(def, true)
		end
	end
end

if config.bold ~= false then
	Fonts.set(true)
end

local sbList = sidebar:FindFirstChildOfClass("UIListLayout")
if sbList then
	C(sbList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		task.defer(fitSidebar)
	end))
end
C(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	task.defer(fitSidebar)
end))
task.defer(fitSidebar)
task.defer(syncSidebar)
print("[ScriptHub] all done")

genv.ScriptHubUnload = function()
	if not alive then
		return
	end
	for _, fn in ipairs(cleanups) do
		pcall(fn)
	end
	pcall(Theme.restore)
	pcall(Fonts.restore)
	pcall(restoreSidebar)
	alive = false
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	for _, i in ipairs(made) do
		pcall(function()
			i:Destroy()
		end)
	end
	genv.ScriptHubUnload = nil
end
