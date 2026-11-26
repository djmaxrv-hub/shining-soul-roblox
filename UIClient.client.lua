--====================================================================
-- Shining Soul UI Client -- ONE-TIME SETUP (v4)
-- Paste this whole file into ONE LocalScript in StarterPlayerScripts:
--   Explorer -> StarterPlayerScripts -> + -> LocalScript
--   (delete the default line, paste this in -- only ever done once)
--
-- It does two jobs the server script cannot do by itself:
--   1) Forwards clicks: every GuiButton the server builds carries
--      "Act" / "Arg" attributes; clicks are sent to the server on
--      the UIEvent RemoteEvent (bag open/close, equip, music...).
--   2) Plays background music: the server says which track to play
--      ("Calm" / "Battle" / "Off") and this script runs one looped
--      Sound in SoundService.
--====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local uiEvent = ReplicatedStorage:WaitForChild("UIEvent")

-- Music tracks: key -> SoundId (must match what the server sends)
local MUSIC_TRACKS = {
	Calm = "rbxassetid://1837070127",   -- APM "Prima Bossa Nova" (calm)
	Battle = "rbxassetid://9043754347", -- APM "Caged Animal" (battle)
}

local musicSound = Instance.new("Sound")
musicSound.Name = "ShiningBGM"
musicSound.Looped = true
musicSound.Volume = 0.35
musicSound.Parent = SoundService

uiEvent.OnClientEvent:Connect(function(act, arg)
	if act ~= "Music" then return end
	local trackId = MUSIC_TRACKS[arg]
	if trackId then
		if musicSound.SoundId ~= trackId then
			musicSound.SoundId = trackId
		end
		if not musicSound.IsPlaying then
			musicSound:Play()
		end
	else -- "Off" or unknown: stop
		musicSound:Stop()
	end
end)

-- Button click forwarding (hooks existing buttons and every button
-- created later -- the bag grid is rebuilt by the server often)
local hooked = {}
local function hookButton(obj)
	if not obj:IsA("GuiButton") then return end
	if hooked[obj] then return end
	hooked[obj] = true
	obj.Activated:Connect(function()
		local act = obj:GetAttribute("Act")
		if act then
			uiEvent:FireServer(act, obj:GetAttribute("Arg"))
		end
	end)
	obj.Destroying:Connect(function()
		hooked[obj] = nil
	end)
end

local playerGui = player:WaitForChild("PlayerGui")
for _, descendant in ipairs(playerGui:GetDescendants()) do
	hookButton(descendant)
end
playerGui.DescendantAdded:Connect(hookButton)
