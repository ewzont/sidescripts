-- Define the character
local character = game.Players.LocalPlayer.Character

-- Disable the "Client" script in the local character
character.Client.Disabled = true

-- Wait 0.25 seconds
wait(0.25)

-- Remove the specified events
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModBan = ReplicatedStorage.Events:FindFirstChild("ModBan")
local BanClient = ReplicatedStorage.Events:FindFirstChild("BanClient")
local Ban = ReplicatedStorage.Events:FindFirstChild("Ban")
local idontexploit = ReplicatedStorage.Events:FindFirstChild("idontexploit")

if ModBan then
    ModBan:Destroy()
end
if BanClient then
    BanClient:Destroy()
end
if Ban then
    Ban:Destroy()
end
if idontexploit then
    idontexploit:Destroy()
end

-- Wait 0.5 seconds again
wait(0.25)

-- Enable the "Client" script in the local character again
character.Client.Disabled = false
wait(.25)
