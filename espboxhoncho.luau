-- name: HonchoESP
-- version: 1.0
-- author: betmon1904p

local workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local HIGHLIGHT_COLOR = Color3.fromRGB(0, 255, 0)
local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

local bossDefeated = false
local bossActive = false

local function isBossAlive()
    if not player then return false end
    local gui = player:FindFirstChild("PlayerGui")
    if gui then
        for _, obj in pairs(gui:GetDescendants()) do
            if obj.Name == "BossHealthBar" or obj.Name == "HonchoIndicator" then
                return true
            end
        end
    end
    local honcho = workspace:FindFirstChild("Honcho")
    if honcho and honcho:IsA("Model") then
        return true
    end
    return false
end

local function getTargetNumbersFromScreens()
    local targets = {}
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return targets end
    for _, obj in pairs(rooms:GetDescendants()) do
        if obj.Name == "ArchivesPackageDeposit" then
            local label = obj:FindFirstChild("Screen")
                and obj.Screen:FindFirstChild("Text")
                and obj.Screen.Text:FindFirstChild("Label")
            if label and label:IsA("TextLabel") then
                local text = label.Text
                if text ~= "" and text ~= "---" and string.match(text, "^%u%-%d+$") then
                    table.insert(targets, text)
                end
            end
        end
    end
    return targets
end

local function clearAllHighlights()
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return end
    for _, obj in pairs(rooms:GetDescendants()) do
        if obj.Name == "ArchivesStorageBox" then
            local existingHighlight = obj:FindFirstChild("DynamicGreenESP")
            if existingHighlight then
                existingHighlight:Destroy()
            end
        end
    end
end

local function doHonchoESP()
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then 
        clearAllHighlights()
        return 
    end

    local bossAlive = isBossAlive()
    
    if not bossAlive and bossActive then
        bossDefeated = true
        bossActive = false
        clearAllHighlights()
        print("[Cheesy] Босс побеждён, подсветка отключена")
        return
    end

    if bossDefeated then
        return
    end

    if bossAlive then
        bossActive = true
    end

    local targetNumbers = getTargetNumbersFromScreens()
    
    if #targetNumbers == 0 then
        clearAllHighlights()
        return
    end

    for _, obj in pairs(rooms:GetDescendants()) do
        if obj.Name == "ArchivesStorageBox" and obj:IsA("Model") then
            local boxLabel = obj:FindFirstChild("Handle")
                and obj.Handle:FindFirstChild("Label")
... (осталось: 43 строки)
