-- === HONCHO ESP (MOBILE) — ПЕРЕТАСКИВАЕМЫЕ КНОПКИ ===
-- Подходит для телефонов/планшетов
-- Кнопки можно двигать пальцем

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------
-- НАСТРОЙКИ
------------------------------------------------------------

local DELIVERY_DISTANCE = 10

local COLORS = {
    Color3.fromRGB(0, 255, 0),
    Color3.fromRGB(0, 170, 255),
    Color3.fromRGB(180, 80, 255),
    Color3.fromRGB(255, 150, 0),
    Color3.fromRGB(255, 60, 60),
}

local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

------------------------------------------------------------
-- СОСТОЯНИЕ
------------------------------------------------------------

local espEnabled = false
local currentRooms = nil
local rooms = {}
local connections = {}

------------------------------------------------------------
-- УПРАВЛЕНИЕ СОЕДИНЕНИЯМИ
------------------------------------------------------------

local function disconnectAll()
    for _, c in ipairs(connections) do
        if c then c:Disconnect() end
    end
    table.clear(connections)
end

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(connections, c)
    return c
end

------------------------------------------------------------
-- ХЕЛПЕРЫ ОБЪЕКТОВ
------------------------------------------------------------

local function getBoxLabel(box)
    local handle = box:FindFirstChild("Handle")
    if not handle then return nil end
    local labelFolder = handle:FindFirstChild("Label")
    if not labelFolder then return nil end
    local textFolder = labelFolder:FindFirstChild("Text")
    if not textFolder then return nil end
    local label = textFolder:FindFirstChild("Label")
    if label and label:IsA("TextLabel") then return label end
    return nil
end

local function getTerminalLabel(terminal)
    local screen = terminal:FindFirstChild("Screen")
    if not screen then return nil end
    local textFolder = screen:FindFirstChild("Text")
    if not textFolder then return nil end
    local label = textFolder:FindFirstChild("Label")
    if label and label:IsA("TextLabel") then return label end
    return nil
end

local function getWorldPosition(object)
    if not object then return nil end
    if object:IsA("BasePart") then return object.Position end
    if object:IsA("Model") then
        if object.PrimaryPart then return object.PrimaryPart.Position end
        return object:GetPivot().Position
    end
    return nil
end

local function isValidTarget(text)
    return text and text ~= "" and text ~= "---" and string.match(text, "^%u%-%d+$") ~= nil
end

------------------------------------------------------------
-- ПОДСВЕТКА
------------------------------------------------------------

local function applyHighlight(object, color, name)
    if not object or not object.Parent then return end
    local h = object:FindFirstChild(name)
    if not h or not h:IsA("Highlight") then
        h = Instance.new("Highlight")
        h.Name = name
        h.FillTransparency = 0.3
        h.OutlineTransparency = 0
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = object
    end
    h.FillColor = color
    h.OutlineColor = OUTLINE_COLOR
end

local function removeHighlight(object, name)
    if not object then return end
    local h = object:FindFirstChild(name)
    if h then h:Destroy() end
end

local function clearAllHighlights()
    for _, roomData in pairs(rooms) do
        for terminal in pairs(roomData.terminals) do
            if terminal and terminal.Parent then
                removeHighlight(terminal, "HonchoTerminalESP")
            end
        end
        for box in pairs(roomData.boxes) do
            if box and box.Parent then
                removeHighlight(box, "HonchoBoxESP")
            end
        end
    end
end

------------------------------------------------------------
-- ХЕЛПЕРЫ КОМНАТ
------------------------------------------------------------

local function getRoomForObject(object)
    if not currentRooms or not object then return nil end
    local current = object
    while current and current.Parent ~= currentRooms do
        current = current.Parent
    end
    if current and current.Parent == currentRooms then return current end
    return nil
end

local function getOrCreateRoom(room)
    if not room then return nil end
    if rooms[room] then return rooms[room] end
    rooms[room] = { terminals = {}, boxes = {} }
    return rooms[room]
end

------------------------------------------------------------
-- ТЕРМИНАЛЫ
------------------------------------------------------------

local function refreshRoomTargets(room)
    local roomData = rooms[room]
    if not roomData then return end

    local terminalList = {}
    for terminal, data in pairs(roomData.terminals) do
        if terminal and terminal.Parent then
            table.insert(terminalList, terminal)
            local label = data.label
            if label and label.Parent then
                local text = label.Text
                data.target = isValidTarget(text) and text or nil
            else
                data.target = nil
            end
        else
            roomData.terminals[terminal] = nil
        end
    end

    table.sort(terminalList, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)

    for index, terminal in ipairs(terminalList) do
        local data = roomData.terminals[terminal]
        local colorIndex = math.min(index, #COLORS)
        data.colorIndex = colorIndex
        data.color = COLORS[colorIndex]
        if espEnabled then
            applyHighlight(terminal, data.color, "HonchoTerminalESP")
        end
    end
end

local function findTerminal(room, target)
    local roomData = rooms[room]
    if not roomData then return nil end
    for terminal, data in pairs(roomData.terminals) do
        if data.target == target then return terminal end
    end
    return nil
end

------------------------------------------------------------
-- ЯЩИКИ
------------------------------------------------------------

local function assignBox(box, room)
    local roomData = rooms[room]
    if not roomData then return end
    local data = roomData.boxes[box]
    if not data then return end

    if data.terminal and data.terminal.Parent and data.target and data.color then
        if espEnabled then
            applyHighlight(box, data.color, "HonchoBoxESP")
        end
        return
    end

    local label = getBoxLabel(box)
    if not label then return end
    local number = label.Text
    if not isValidTarget(number) then return end

    local terminal = findTerminal(room, number)
    if not terminal then return end
    local terminalData = roomData.terminals[terminal]
    if not terminalData then return end

    data.target = number
    data.terminal = terminal
    data.colorIndex = terminalData.colorIndex
    data.color = terminalData.color

    if espEnabled then
        applyHighlight(box, data.color, "HonchoBoxESP")
    end
end

local function addBox(box)
    if not espEnabled then return end
    if not box:IsA("Model") then return end
    local room = getRoomForObject(box)
    if not room then return end
    local roomData = getOrCreateRoom(room)

    if roomData.boxes[box] then
        assignBox(box, room)
        return
    end

    roomData.boxes[box] = { target = nil, terminal = nil, colorIndex = nil, color = nil }

    local label = getBoxLabel(box)
    if label then
        connect(label:GetPropertyChangedSignal("Text"), function()
            if espEnabled and box.Parent then
                local currentRoom = getRoomForObject(box)
                if currentRoom then assignBox(box, currentRoom) end
            end
        end)
    end

    assignBox(box, room)

    task.delay(0.15, function()
        if espEnabled and box.Parent and roomData.boxes[box] then
            local currentRoom = getRoomForObject(box)
            if currentRoom then assignBox(box, currentRoom) end
        end
    end)
end

local function removeBox(box, room)
    local roomData = rooms[room]
    if not roomData then return end
    removeHighlight(box, "HonchoBoxESP")
end

------------------------------------------------------------
-- ТЕРМИНАЛЫ
------------------------------------------------------------

local function addTerminal(terminal)
    if not espEnabled then return end
    if terminal.Name ~= "ArchivesPackageDeposit" then return end
    local room = getRoomForObject(terminal)
    if not room then return end
    local roomData = getOrCreateRoom(room)
    if roomData.terminals[terminal] then return end

    local label = getTerminalLabel(terminal)
    if not label then
        task.delay(0.15, function()
            if espEnabled and terminal and terminal.Parent then
                addTerminal(terminal)
            end
        end)
        return
    end

    roomData.terminals[terminal] = {
        label = label,
        target = nil,
        colorIndex = 1,
        color = COLORS[1],
    }

    connect(label:GetPropertyChangedSignal("Text"), function()
        if not espEnabled then return end
        refreshRoomTargets(room)
        local currentRoomData = rooms[room]
        if not currentRoomData then return end
        for box in pairs(currentRoomData.boxes) do
            if box and box.Parent then assignBox(box, room) end
        end
    end)

    refreshRoomTargets(room)

    for box in pairs(roomData.boxes) do
        if box and box.Parent then assignBox(box, room) end
    end
end

local function removeTerminal(terminal, room)
    local roomData = rooms[room]
    if not roomData then return end
    removeHighlight(terminal, "HonchoTerminalESP")
    roomData.terminals[terminal] = nil
    refreshRoomTargets(room)
end

------------------------------------------------------------
-- СКАН
------------------------------------------------------------

local function scanRoom(room)
    if not room then return end
    local roomData = getOrCreateRoom(room)

    for _, object in ipairs(room:GetDescendants()) do
        if object.Name == "ArchivesPackageDeposit" then
            addTerminal(object)
        elseif object.Name == "ArchivesStorageBox" and object:IsA("Model") then
            addBox(object)
        end
    end

    refreshRoomTargets(room)

    for box in pairs(roomData.boxes) do
        if box and box.Parent then assignBox(box, room) end
    end
end

local function scanAllRooms()
    if not currentRooms then return end
    for _, room in ipairs(currentRooms:GetChildren()) do
        scanRoom(room)
    end
end

------------------------------------------------------------
-- ДОСТАВКА
------------------------------------------------------------

local function isBoxAtTerminal(box, terminal)
    if not box or not box.Parent then return false end
    if not terminal or not terminal.Parent then return false end
    local bp = getWorldPosition(box)
    local tp = getWorldPosition(terminal)
    if not bp or not tp then return false end
    return (bp - tp).Magnitude <= DELIVERY_DISTANCE
end

local function checkDeliveries()
    if not espEnabled then return end
    for room, roomData in pairs(rooms) do
        for box, data in pairs(roomData.boxes) do
            if not box then
                roomData.boxes[box] = nil
            elseif box.Parent then
                local currentRoom = getRoomForObject(box)
                if currentRoom and currentRoom == room and data.terminal and data.terminal.Parent then
                    if isBoxAtTerminal(box, data.terminal) then
                        removeHighlight(box, "HonchoBoxESP")
                        roomData.boxes[box] = nil
                    end
                end
            end
        end
    end
end

local function cleanupRooms()
    for room, roomData in pairs(rooms) do
        if not room or not room.Parent then
            for terminal in pairs(roomData.terminals) do
                removeHighlight(terminal, "HonchoTerminalESP")
            end
            for box in pairs(roomData.boxes) do
                removeHighlight(box, "HonchoBoxESP")
            end
            rooms[room] = nil
        end
    end
end

------------------------------------------------------------
-- СЛУШАТЕЛИ
------------------------------------------------------------

local function setupRoomListeners()
    if not currentRooms then return end

    connect(currentRooms.ChildAdded, function(room)
        if not espEnabled then return end
        task.delay(0.1, function()
            if espEnabled and room and room.Parent == currentRooms then
                scanRoom(room)
            end
        end)
    end)

    connect(currentRooms.DescendantAdded, function(object)
        if not espEnabled then return end
        if object.Name == "ArchivesStorageBox" and object:IsA("Model") then
            addBox(object)
        elseif object.Name == "ArchivesPackageDeposit" then
            addTerminal(object)
        end
    end)

    connect(currentRooms.DescendantRemoving, function(object)
        local room = getRoomForObject(object)
        if not room then return end
        local roomData = rooms[room]
        if not roomData then return end
        if roomData.boxes[object] then
            removeBox(object, room)
        elseif roomData.terminals[object] then
            removeTerminal(object, room)
        end
    end)
end

------------------------------------------------------------
-- СТАРТ / СТОП
------------------------------------------------------------

local function startESP()
    if espEnabled then return end
    espEnabled = true

    disconnectAll()
    table.clear(rooms)

    currentRooms = Workspace:FindFirstChild("CurrentRooms")
    if not currentRooms then
        warn("[HonchoESP] CurrentRooms не найдена. Ты в Архивах?")
        espEnabled = false
        return
    end

    scanAllRooms()
    setupRoomListeners()

    task.spawn(function()
        while espEnabled do
            checkDeliveries()
            cleanupRooms()
            task.wait(5)
            if espEnabled then scanAllRooms() end
        end
    end)

    print("[HonchoESP] ✅ ВКЛЮЧЕНО")
end

local function stopESP()
    if not espEnabled then return end
    espEnabled = false

    clearAllHighlights()
    disconnectAll()
    table.clear(rooms)
    currentRooms = nil

    print("[HonchoESP] ❌ ВЫКЛЮЧЕНО")
end

------------------------------------------------------------
-- МОБИЛЬНЫЙ GUI С ПЕРЕТАСКИВАЕМЫМИ КНОПКАМИ
------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HonchoESP_Mobile"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Главный контейнер
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 160, 0, 90)
mainFrame.Position = UDim2.new(0, 20, 0.5, -45)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
mainFrame.BackgroundTransparency = 0.2
mainFrame.BorderSizePixel = 2
mainFrame.BorderColor3 = Color3.fromRGB(0, 170, 255)
mainFrame.Active = true
mainFrame.Draggable = true -- Встроенное перетаскивание
mainFrame.Parent = screenGui

-- Заголовок
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 25)
title.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
title.BackgroundTransparency = 0.3
title.Text = "🎯 HONCHO ESP"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = mainFrame

-- Кнопка ВКЛ
local onButton = Instance.new("TextButton")
onButton.Size = UDim2.new(0.45, 0, 0, 35)
onButton.Position = UDim2.new(0.025, 0, 0.35, 0)
onButton.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
onButton.Text = "ВКЛ"
onButton.TextColor3 = Color3.fromRGB(255, 255, 255)
onButton.TextScaled = true
onButton.Font = Enum.Font.GothamBold
onButton.Parent = mainFrame

-- Кнопка ВЫКЛ
local offButton = Instance.new("TextButton")
offButton.Size = UDim2.new(0.45, 0, 0, 35)
offButton.Position = UDim2.new(0.525, 0, 0.35, 0)
offButton.BackgroundColor3 = Color3.fromRGB(150, 0, 0)
offButton.Text = "ВЫКЛ"
offButton.TextColor3 = Color3.fromRGB(255, 255, 255)
offButton.TextScaled = true
offButton.Font = Enum.Font.GothamBold
offButton.Parent = mainFrame

-- Статус
local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, 0, 0, 18)
status.Position = UDim2.new(0, 0, 1, -18)
status.BackgroundTransparency = 1
status.Text = "Выключено"
status.TextColor3 = Color3.fromRGB(180, 180, 180)
status.TextScaled = true
status.Font = Enum.Font.Gotham
status.Parent = mainFrame

-- Функции кнопок
onButton.MouseButton1Click:Connect(function()
    startESP()
    status.Text = "Включено"
    status.TextColor3 = Color3.fromRGB(0, 255, 0)
end)

offButton.MouseButton1Click:Connect(function()
    stopESP()
    status.Text = "Выключено"
    status.TextColor3 = Color3.fromRGB(255, 100, 100)
end)

print("[HonchoESP] Мобильная версия загружена!")
print("   Перетаскивай панель пальцем")
print("   ВКЛ — включить подсветку")
print("   ВЫКЛ — выключить подсветку")
