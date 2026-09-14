-- Cheesy Addon: Honcho ESP for DOORS: The Archives
-- Author: betmon1904p
-- Version: 4.1
--
-- Features:
--   • Up to 5 colors per room
--   • Matching boxes and terminals share the same color
--   • Box assignments survive pickup/drop
--   • Box highlights are restored when dropped back into a room
--   • Supports rooms being loaded ahead of time
--   • Keeps rooms completely separate
--   • Event-based detection for immediate updates
--   • Full safety rescan every 5 seconds
--   • Does not constantly scan CurrentRooms every 0.2 seconds

cheesy.AddonInfo = {
    Name = "HonchoESP",
    Title = "Honcho ESP",
    Description = "Color-coded box and terminal ESP for The Archives",
    Game = "TheArchives",
}

------------------------------------------------------------
-- SERVICES
------------------------------------------------------------

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------

local SAFETY_SCAN_INTERVAL = 5

local DELIVERY_DISTANCE = 10

-- Maximum of 5 colors.
local COLORS = {
    Color3.fromRGB(0, 255, 0),     -- Green
    Color3.fromRGB(0, 170, 255),   -- Blue
    Color3.fromRGB(180, 80, 255),  -- Purple
    Color3.fromRGB(255, 150, 0),   -- Orange
    Color3.fromRGB(255, 60, 60),   -- Red
}

local OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

------------------------------------------------------------
-- STATE
------------------------------------------------------------

local espEnabled = false
local bossActive = false
local bossDefeated = false

local currentRooms = nil

--[[
    rooms[room] = {
        terminals = {
            [terminal] = terminalData
        },

        boxes = {
            [box] = boxData
        }
    }

    A boxData assignment is intentionally kept when a box
    temporarily leaves CurrentRooms because a player picked
    it up.
]]

local rooms = {}

local connections = {}

------------------------------------------------------------
-- CONNECTION MANAGEMENT
------------------------------------------------------------

local function disconnectAll()
    for _, connection in ipairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end

    table.clear(connections)
end

local function connect(signal, callback)
    local connection = signal:Connect(callback)

    table.insert(connections, connection)

    return connection
end

------------------------------------------------------------
-- OBJECT HELPERS
------------------------------------------------------------

local function getBoxLabel(box)
    local handle = box:FindFirstChild("Handle")

    if not handle then
        return nil
    end

    local labelFolder = handle:FindFirstChild("Label")

    if not labelFolder then
        return nil
    end

    local textFolder = labelFolder:FindFirstChild("Text")

    if not textFolder then
        return nil
    end

    local label = textFolder:FindFirstChild("Label")

    if label and label:IsA("TextLabel") then
        return label
    end

    return nil
end

local function getTerminalLabel(terminal)
    local screen = terminal:FindFirstChild("Screen")

    if not screen then
        return nil
    end

    local textFolder = screen:FindFirstChild("Text")

    if not textFolder then
        return nil
    end

    local label = textFolder:FindFirstChild("Label")

    if label and label:IsA("TextLabel") then
        return label
    end

    return nil
end

local function getWorldPosition(object)
    if not object then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        if object.PrimaryPart then
            return object.PrimaryPart.Position
        end

        return object:GetPivot().Position
    end

    return nil
end

local function isValidTarget(text)
    return text
        and text ~= ""
        and text ~= "---"
        and string.match(text, "^%u%-%d+$") ~= nil
end

------------------------------------------------------------
-- HIGHLIGHTS
------------------------------------------------------------

local function applyHighlight(object, color, name)
    if not object or not object.Parent then
        return
    end

    local highlight = object:FindFirstChild(name)

    if not highlight or not highlight:IsA("Highlight") then

        highlight = Instance.new("Highlight")

        highlight.Name = name
        highlight.FillTransparency = 0.3
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        highlight.Parent = object
    end

    highlight.FillColor = color
    highlight.OutlineColor = OUTLINE_COLOR
end

local function removeHighlight(object, name)
    if not object then
        return
    end

    local highlight = object:FindFirstChild(name)

    if highlight then
        highlight:Destroy()
    end
end

local function clearAllHighlights()
    for _, roomData in pairs(rooms) do

        for terminal in pairs(roomData.terminals) do
            if terminal and terminal.Parent then
                removeHighlight(
                    terminal,
                    "HonchoTerminalESP"
                )
            end
        end

        for box in pairs(roomData.boxes) do
            if box and box.Parent then
                removeHighlight(
                    box,
                    "HonchoBoxESP"
                )
            end
        end
    end
end

------------------------------------------------------------
-- ROOM HELPERS
------------------------------------------------------------

local function getRoomForObject(object)
    if not currentRooms or not object then
        return nil
    end

    local current = object

    while current and current.Parent ~= currentRooms do
        current = current.Parent
    end

    if current and current.Parent == currentRooms then
        return current
    end

    return nil
end

local function getOrCreateRoom(room)
    if not room then
        return nil
    end

    if rooms[room] then
        return rooms[room]
    end

    rooms[room] = {
        terminals = {},
        boxes = {},
    }

    return rooms[room]
end

------------------------------------------------------------
-- TERMINALS
------------------------------------------------------------

local function refreshRoomTargets(room)
    local roomData = rooms[room]

    if not roomData then
        return
    end

    local terminalList = {}

    for terminal, data in pairs(roomData.terminals) do

        if terminal and terminal.Parent then

            table.insert(
                terminalList,
                terminal
            )

            local label = data.label

            if label and label.Parent then

                local text = label.Text

                if isValidTarget(text) then
                    data.target = text
                else
                    data.target = nil
                end

            else
                data.target = nil
            end

        else

            roomData.terminals[terminal] = nil
        end
    end

    --------------------------------------------------------
    -- Stable ordering gives terminals stable colors.
    --------------------------------------------------------

    table.sort(
        terminalList,
        function(a, b)
            return a:GetFullName() < b:GetFullName()
        end
    )

    for index, terminal in ipairs(terminalList) do

        local data = roomData.terminals[terminal]

        local colorIndex = math.min(
            index,
            #COLORS
        )

        data.colorIndex = colorIndex
        data.color = COLORS[colorIndex]

        if espEnabled and not bossDefeated then

            applyHighlight(
                terminal,
                data.color,
                "HonchoTerminalESP"
            )
        end
    end
end

local function findTerminal(room, target)
    local roomData = rooms[room]

    if not roomData then
        return nil
    end

    for terminal, data in pairs(roomData.terminals) do

        if data.target == target then
            return terminal
        end
    end

    return nil
end

------------------------------------------------------------
-- BOX ASSIGNMENT
------------------------------------------------------------

local function assignBox(box, room)
    local roomData = rooms[room]

    if not roomData then
        return
    end

    local data = roomData.boxes[box]

    if not data then
        return
    end

    --------------------------------------------------------
    -- IMPORTANT:
    --
    -- If this box was already assigned before being picked
    -- up, keep using that assignment.
    --
    -- The label does NOT need to be visible while the box
    -- is being carried.
    --------------------------------------------------------

    if data.terminal
        and data.terminal.Parent
        and data.target
        and data.color then

        if espEnabled and not bossDefeated then

            applyHighlight(
                box,
                data.color,
                "HonchoBoxESP"
            )
        end

        return
    end

    local label = getBoxLabel(box)

    if not label then
        return
    end

    local number = label.Text

    if not isValidTarget(number) then
        return
    end

    --------------------------------------------------------
    -- ONLY search for a matching terminal inside the
    -- box's own room.
    --------------------------------------------------------

    local terminal = findTerminal(
        room,
        number
    )

    if not terminal then
        return
    end

    local terminalData =
        roomData.terminals[terminal]

    if not terminalData then
        return
    end

    --------------------------------------------------------
    -- Save the assignment permanently for this room's
    -- lifetime.
    --------------------------------------------------------

    data.target = number
    data.terminal = terminal
    data.colorIndex = terminalData.colorIndex
    data.color = terminalData.color

    if espEnabled and not bossDefeated then
        applyHighlight(
            box,
            data.color,
            "HonchoBoxESP"
        )
    end
end

------------------------------------------------------------
-- ADD BOX
------------------------------------------------------------

local function addBox(box)
    if not espEnabled then
        return
    end

    if not box:IsA("Model") then
        return
    end

    local room = getRoomForObject(box)

    if not room then
        return
    end

    local roomData = getOrCreateRoom(room)

    --------------------------------------------------------
    -- IMPORTANT:
    --
    -- If this box was already tracked, it most likely just
    -- got picked up and then dropped back into the room.
    --
    -- Do NOT create a new assignment.
    -- Restore the old one.
    --------------------------------------------------------

    if roomData.boxes[box] then

        assignBox(
            box,
            room
        )

        return
    end

    roomData.boxes[box] = {
        target = nil,
        terminal = nil,
        colorIndex = nil,
        color = nil,
    }

    local label = getBoxLabel(box)

    if label then

        connect(
            label:GetPropertyChangedSignal("Text"),
            function()

                if espEnabled and box.Parent then
                    local currentRoom =
                        getRoomForObject(box)

                    if currentRoom then
                        assignBox(
                            box,
                            currentRoom
                        )
                    end
                end
            end
        )
    end

    assignBox(
        box,
        room
    )

    --------------------------------------------------------
    -- Retry shortly after creation in case the game's
    -- hierarchy is still being built.
    --------------------------------------------------------

    task.delay(0.15, function()

        if espEnabled
            and box.Parent
            and roomData.boxes[box] then

            local currentRoom =
                getRoomForObject(box)

            if currentRoom then
                assignBox(
                    box,
                    currentRoom
                )
            end
        end
    end)
end

------------------------------------------------------------
-- REMOVE BOX
------------------------------------------------------------

local function removeBox(box, room)

    local roomData = rooms[room]

    if not roomData then
        return
    end

    --------------------------------------------------------
    -- DO NOT delete roomData.boxes[box] here.
    --
    -- A player picking up a box temporarily moves the box
    -- out of CurrentRooms.
    --
    -- We want the saved terminal/color assignment to survive
    -- that movement.
    --
    -- When the box is dropped back into a room, addBox()
    -- finds the existing data and restores the highlight.
    --------------------------------------------------------

    removeHighlight(
        box,
        "HonchoBoxESP"
    )

    -- Intentionally NOT doing:
    --
    -- roomData.boxes[box] = nil
end

------------------------------------------------------------
-- ADD TERMINAL
------------------------------------------------------------

local function addTerminal(terminal)
    if not espEnabled then
        return
    end

    if terminal.Name ~= "ArchivesPackageDeposit" then
        return
    end

    local room = getRoomForObject(terminal)

    if not room then
        return
    end

    local roomData = getOrCreateRoom(room)

    if roomData.terminals[terminal] then
        return
    end

    local label = getTerminalLabel(terminal)

    --------------------------------------------------------
    -- The terminal may exist before its UI.
    --------------------------------------------------------

    if not label then

        task.delay(0.15, function()

            if espEnabled
                and terminal
                and terminal.Parent then

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

    --------------------------------------------------------
    -- Watch terminal number changes.
    --------------------------------------------------------

    connect(
        label:GetPropertyChangedSignal("Text"),
        function()

            if not espEnabled then
                return
            end

            refreshRoomTargets(room)

            local currentRoomData =
                rooms[room]

            if not currentRoomData then
                return
            end

            for box in pairs(
                currentRoomData.boxes
            ) do

                if box and box.Parent then

                    assignBox(
                        box,
                        room
                    )
                end
            end
        end
    )

    refreshRoomTargets(room)

    --------------------------------------------------------
    -- Re-check existing boxes.
    --------------------------------------------------------

    for box in pairs(roomData.boxes) do

        if box and box.Parent then

            assignBox(
                box,
                room
            )
        end
    end
end

local function removeTerminal(
    terminal,
    room
)

    local roomData = rooms[room]

    if not roomData then
        return
    end

    removeHighlight(
        terminal,
        "HonchoTerminalESP"
    )

    roomData.terminals[terminal] = nil

    refreshRoomTargets(room)
end

------------------------------------------------------------
-- FULL ROOM SCAN
------------------------------------------------------------

local function scanRoom(room)

    if not room then
        return
    end

    local roomData =
        getOrCreateRoom(room)

    --------------------------------------------------------
    -- This is ONLY called:
    --
    --   1. When ESP starts
    --   2. When a new room loads
    --   3. Every 5 seconds as a safety check
    --   4. When the user presses Rescan
    --
    -- It is NOT running every frame.
    --------------------------------------------------------

    for _, object in ipairs(
        room:GetDescendants()
    ) do

        if object.Name ==
            "ArchivesPackageDeposit" then

            addTerminal(object)

        elseif object.Name ==
            "ArchivesStorageBox"
            and object:IsA("Model") then

            addBox(object)
        end
    end

    refreshRoomTargets(room)

    --------------------------------------------------------
    -- Re-check every known box.
    --------------------------------------------------------

    for box in pairs(
        roomData.boxes
    ) do

        if box and box.Parent then

            assignBox(
                box,
                room
            )
        end
    end
end

local function scanAllRooms()

    if not currentRooms then
        return
    end

    for _, room in ipairs(
        currentRooms:GetChildren()
    ) do

        scanRoom(room)
    end
end

------------------------------------------------------------
-- DELIVERY DETECTION
------------------------------------------------------------

local function isBoxAtTerminal(
    box,
    terminal
)

    if not box or not box.Parent then
        return false
    end

    if not terminal or not terminal.Parent then
        return false
    end

    local boxPosition =
        getWorldPosition(box)

    local terminalPosition =
        getWorldPosition(terminal)

    if not boxPosition
        or not terminalPosition then

        return false
    end

    return (
        boxPosition - terminalPosition
    ).Magnitude <= DELIVERY_DISTANCE
end

local function checkDeliveries()

    if not espEnabled
        or bossDefeated then

        return
    end

    for room, roomData in pairs(rooms) do

        for box, data in pairs(
            roomData.boxes
        ) do

            if not box then

                roomData.boxes[box] = nil

            elseif box.Parent then

                ------------------------------------------------
                -- IMPORTANT:
                --
                -- Only perform delivery detection while the
                -- box is actually inside a loaded room.
                --
                -- If a player is carrying it in their
                -- inventory/character, getRoomForObject()
                -- returns nil, so the assignment survives.
                ------------------------------------------------

                local currentRoom =
                    getRoomForObject(box)

                if currentRoom
                    and currentRoom == room
                    and data.terminal
                    and data.terminal.Parent then

                    if isBoxAtTerminal(
                        box,
                        data.terminal
                    ) then

                        removeHighlight(
                            box,
                            "HonchoBoxESP"
                        )

                        roomData.boxes[box] = nil
                    end
                end

            end
        end
    end
end

------------------------------------------------------------
-- SAFETY RESCAN
------------------------------------------------------------

local function safetyRescan()

    if not espEnabled
        or bossDefeated then

        return
    end

    --------------------------------------------------------
    -- Full reconciliation.
    --
    -- If an event was missed, or the game created something
    -- in an unusual order, this will find it.
    --------------------------------------------------------

    scanAllRooms()

    --------------------------------------------------------
    -- Repair missing Highlight instances without throwing
    -- away existing assignments.
    --------------------------------------------------------

    for _, roomData in pairs(rooms) do

        for terminal, data in pairs(
            roomData.terminals
        ) do

            if terminal
                and terminal.Parent
                and data.color then

                applyHighlight(
                    terminal,
                    data.color,
                    "HonchoTerminalESP"
                )
            end
        end

        for box, data in pairs(
            roomData.boxes
        ) do

            if box
                and box.Parent
                and data.terminal
                and data.color then

                ------------------------------------------------
                -- Only restore a box highlight when the box is
                -- back inside a loaded room.
                --
                -- While being carried, it remains tracked but
                -- doesn't need a Highlight.
                ------------------------------------------------

                local currentRoom =
                    getRoomForObject(box)

                if currentRoom then

                    applyHighlight(
                        box,
                        data.color,
                        "HonchoBoxESP"
                    )
                end
            end
        end
    end
end

------------------------------------------------------------
-- BOSS DETECTION
------------------------------------------------------------

local function isBossAlive()

    if not player then
        return false
    end

    local gui =
        player:FindFirstChild(
            "PlayerGui"
        )

    if gui then

        if gui:FindFirstChild(
            "BossHealthBar",
            true
        ) or gui:FindFirstChild(
            "HonchoIndicator",
            true
        ) then

            return true
        end
    end

    local honcho =
        Workspace:FindFirstChild(
            "Honcho"
        )

    return honcho ~= nil
        and honcho:IsA("Model")
end

------------------------------------------------------------
-- ROOM CLEANUP
------------------------------------------------------------

local function cleanupRooms()

    for room, roomData in pairs(
        rooms
    ) do

        --------------------------------------------------------
        -- Only delete tracking data when the actual ROOM has
        -- been unloaded.
        --
        -- A box leaving the room is NOT enough to delete it,
        -- because players can temporarily carry boxes away.
        --------------------------------------------------------

        if not room
            or not room.Parent then

            for terminal in pairs(
                roomData.terminals
            ) do

                removeHighlight(
                    terminal,
                    "HonchoTerminalESP"
                )
            end

            for box in pairs(
                roomData.boxes
            ) do

                removeHighlight(
                    box,
                    "HonchoBoxESP"
                )
            end

            rooms[room] = nil
        end
    end
end

------------------------------------------------------------
-- EVENT LISTENERS
------------------------------------------------------------

local function setupRoomListeners()

    if not currentRooms then
        return
    end

    --------------------------------------------------------
    -- NEW ROOM
    --------------------------------------------------------

    connect(
        currentRooms.ChildAdded,
        function(room)

            if not espEnabled then
                return
            end

            task.delay(
                0.1,
                function()

                    if espEnabled
                        and room
                        and room.Parent
                            == currentRooms then

                        scanRoom(room)
                    end
                end
            )
        end
    )

    --------------------------------------------------------
    -- NEW OBJECT
    --------------------------------------------------------

    connect(
        currentRooms.DescendantAdded,
        function(object)

            if not espEnabled then
                return
            end

            if object.Name ==
                "ArchivesStorageBox"
                and object:IsA("Model") then

                addBox(object)

            elseif object.Name ==
                "ArchivesPackageDeposit" then

                addTerminal(object)
            end
        end
    )

    --------------------------------------------------------
    -- REMOVED OBJECT
    --------------------------------------------------------

    connect(
        currentRooms.DescendantRemoving,
        function(object)

            local room =
                getRoomForObject(object)

            if not room then
                return
            end

            local roomData =
                rooms[room]

            if not roomData then
                return
            end

            if roomData.boxes[object] then

                ------------------------------------------------
                -- IMPORTANT:
                --
                -- Do NOT erase the box's tracking data.
                --
                -- The box may simply be getting picked up.
                ------------------------------------------------

                removeBox(
                    object,
                    room
                )

            elseif roomData.terminals[object] then

                removeTerminal(
                    object,
                    room
                )
            end
        end
    )
end

------------------------------------------------------------
-- START ESP
------------------------------------------------------------

local function startESP()

    disconnectAll()

    table.clear(rooms)

    bossActive = false
    bossDefeated = false

    currentRooms =
        Workspace:FindFirstChild(
            "CurrentRooms"
        )

    if not currentRooms then

        warn(
            "[Cheesy] CurrentRooms was not found."
        )

        return
    end

    --------------------------------------------------------
    -- Initial scan.
    --------------------------------------------------------

    scanAllRooms()

    --------------------------------------------------------
    -- Event-driven tracking.
    --------------------------------------------------------

    setupRoomListeners()

    --------------------------------------------------------
    -- SAFETY LOOP
    --------------------------------------------------------

    task.spawn(function()

        while espEnabled do

            local bossAlive =
                isBossAlive()

            if bossAlive then

                bossActive = true

            elseif bossActive then

                bossActive = false
                bossDefeated = true

                clearAllHighlights()

                break
            end

            checkDeliveries()

            cleanupRooms()

            task.wait(
                SAFETY_SCAN_INTERVAL
            )

            if espEnabled
                and not bossDefeated then

                safetyRescan()
            end
        end
    end)
end

------------------------------------------------------------
-- STOP ESP
------------------------------------------------------------

local function stopESP()

    clearAllHighlights()

    disconnectAll()

    table.clear(rooms)

    currentRooms = nil

    bossActive = false
    bossDefeated = false
end

------------------------------------------------------------
-- UI
------------------------------------------------------------

cheesy.Groupbox:AddToggle(
    "HonchoESPToggle",
    {
        Text = "Enable Honcho ESP",

        Tooltip =
            "Color-coded ESP for Archives boxes and terminals",

        Default = false,

        Func = function(on)

            espEnabled = on

            if on then

                print(
                    "[Cheesy] Honcho ESP enabled"
                )

                startESP()

            else

                print(
                    "[Cheesy] Honcho ESP disabled"
                )

                stopESP()
            end
        end
    }
)

cheesy.Groupbox:AddButton(
    {
        Text = "Rescan",

        Func = function()

            if not espEnabled then
                return
            end

            print(
                "[Cheesy] Rescanning Archives..."
            )

            scanAllRooms()

            print(
                "[Cheesy] Rescan complete."
            )
        end
    }
)

cheesy.Groupbox:AddDivider()

cheesy.Groupbox:AddLabel(
    {
        Text =
            "Matching boxes and terminals share the same color.",

        DoesWrap = true,
    }
)

cheesy.Groupbox:AddLabel(
    {
        Text =
            "Box highlights stay active when players carry or drop them.",

        DoesWrap = true,
    }
)

cheesy.Groupbox:AddLabel(
    {
        Text =
            "A safety rescan runs every 5 seconds to catch anything missed.",

        DoesWrap = true,
    }
)
	
print(
    "[Cheesy] Honcho ESP loaded!"
)