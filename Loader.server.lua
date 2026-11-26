--====================================================================
-- Shining Soul LOADER -- paste this ONCE into a Script inside
-- ServerScriptService, replacing the old full game script.
--
-- Every time you press Play, it downloads the LATEST game code
-- from GitHub and runs it. After this, code updates are pushed
-- by Muse to GitHub -- you never paste the big script again,
-- just Stop -> Play.
--
-- One-time Studio settings required:
--   1) Game Settings -> Security -> turn ON "HTTP Requests"
--      (Home tab -> Game Settings -> Security)
--   2) Click ServerScriptService in Explorer -> in Properties,
--      tick "LoadStringEnabled"
--====================================================================
local HttpService = game:GetService("HttpService")

local URL = "https://raw.githubusercontent.com/djmaxrv-hub/shining-soul-roblox/main/ShiningSoulServer.server.lua"

local ok, code = pcall(function()
	return HttpService:GetAsync(URL, true)
end)
if not ok then
	warn("[Loader] Download failed: " .. tostring(code))
	warn("[Loader] Check: Game Settings -> Security -> HTTP Requests is ON")
	return
end

local fn, err = loadstring(code)
if not fn then
	warn("[Loader] Compile failed: " .. tostring(err))
	warn("[Loader] Check: ServerScriptService -> Properties -> LoadStringEnabled is ON")
	return
end

print("[Loader] Latest game code loaded from GitHub, starting...")
fn()
