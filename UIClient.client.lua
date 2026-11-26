--====================================================================
-- Shining Soul UI Client -- ONE-TIME SETUP (v5)
-- Paste this whole file into ONE LocalScript in StarterPlayerScripts:
--   Explorer -> StarterPlayerScripts -> + -> LocalScript
--   (delete the default line, paste this in -- only ever done once)
--
-- It does four jobs the server script cannot do by itself:
--   1) Forwards clicks: every GuiButton the server builds carries
--      "Act" / "Arg" attributes; clicks are sent to the server on
--      the UIEvent RemoteEvent (bag, equip, class, skills, music).
--   2) Forwards skill hotkeys: Q / E / R cast skills 1 / 2 / 3.
--   3) Plays background music: the server says which track to play
--      ("Calm" / "Battle" / "Off") and this script runs one looped
--      Sound in SoundService.
--   4) (v8) Forwards CHARGE input: hold left mouse / touch ->
--      ("Charge", "Begin"), release -> ("Charge", "Release").
--      The server validates a weapon tool is equipped before a
--      charge starts, so clicks on empty hands are ignored there.
--====================================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

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

-- Skill hotkeys (v5): Q / E / R -> cast skills 1 / 2 / 3.
-- gameProcessedEvent is true when the keystroke was already used by
-- the game or a text box (e.g. chatting), so casts never fire while
-- the player is typing.
local HOTKEYS = {
	[Enum.KeyCode.Q] = "1",
	[Enum.KeyCode.E] = "2",
	[Enum.KeyCode.R] = "3",
}
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	local arg = HOTKEYS[input.KeyCode]
	if arg then
		uiEvent:FireServer("CastSkill", arg)
	end
end)

-- Charge attacks (v8): HOLD left mouse / touch to charge, release
-- to fire the class charge attack. The press ALSO fires the tool's
-- normal Activated swing -- that is the intended wind-up (see the
-- server README: tier-0 release adds nothing because the swing
-- already happened). Known touch tradeoff: on touch devices a
-- camera-drag touch also sends Begin; the server still requires
-- an equipped weapon, and releasing the drag fires the charge.
local chargeHeld = false
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		if not chargeHeld then
			chargeHeld = true
			uiEvent:FireServer("Charge", "Begin")
		end
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		if chargeHeld then
			chargeHeld = false
			uiEvent:FireServer("Charge", "Release")
		end
	end
end)
