local character = game.Players.LocalPlayer.Character

if character:FindFirstChild("Client") then
    character.Client.Disabled = true
end
task.wait()

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

task.wait()

if character:FindFirstChild("Client") then
    character.Client.Disabled = false
end
task.wait()
