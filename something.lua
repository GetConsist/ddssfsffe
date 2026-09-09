local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local environment = type(getgenv) == "function" and getgenv() or _G

if type(environment.__CONSIST_COMBAT_CLEANUP) == "function" then
    pcall(environment.__CONSIST_COMBAT_CLEANUP)
end

local consistLibrarySource = game:HttpGet(
    "https://raw.githubusercontent.com/GetConsist/Consist-UI-Library/refs/heads/main/src/ConsistLibrary.lua"
)

-- Keep every dropdown field and expanded dropdown menu at the same outline
-- brightness as the Consist sidebar/section borders.
consistLibrarySource = consistLibrarySource:gsub(
    "local menuStroke = stroke%(menu, THEMES%[activeThemeName%]%.stroke, 1, 0%.15%)",
    "local menuStroke = stroke(menu, THEMES[activeThemeName].stroke, 1, 0)"
)
consistLibrarySource = consistLibrarySource:gsub(
    "local fs = stroke%(field, THEMES%[activeThemeName%]%.stroke, 1, 0%.15%)",
    "local fs = stroke(field, THEMES[activeThemeName].stroke, 1, 0)"
)

local Consist = loadstring(consistLibrarySource)()

-- Roblox Drawing objects are rendered above every ScreenGui by most executors.
-- Keep visual overlays in their own ScreenGui so Consist can reliably stay on top.
local priorityOverlayGui = Instance.new("ScreenGui")
priorityOverlayGui.Name = "ConsistPriorityOverlay"
priorityOverlayGui.ResetOnSpawn = false
priorityOverlayGui.IgnoreGuiInset = true
priorityOverlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
priorityOverlayGui.DisplayOrder = math.max(0, Consist.Gui.DisplayOrder - 1)
priorityOverlayGui.Parent = Consist.Gui.Parent

local Combat = Consist:Page("Combat")
for _, child in ipairs(Combat.Frame:GetChildren()) do
    child:Destroy()
end
Combat.Layout.Left = 0
Combat.Layout.Right = 0
Combat.Frame.CanvasSize = UDim2.fromOffset(0, 0)

local runtimeAlive = true
local connections = {}
local drawings = {}
local camera = workspace.CurrentCamera
local mouse = LocalPlayer:GetMouse()

local DefaultModeBinds = {
    Camlock = Enum.KeyCode.Unknown,
    Mouselock = Enum.KeyCode.Unknown,
    Silent = Enum.KeyCode.Unknown,
}

local State = {
    SelectedMode = "Camlock",
    ModeEnabled = {
        Camlock = false,
        Mouselock = false,
        Silent = false,
    },
    ModeBinds = {
        Camlock = DefaultModeBinds.Camlock,
        Mouselock = DefaultModeBinds.Mouselock,
        Silent = DefaultModeBinds.Silent,
    },
    ModeBehavior = {
        Camlock = "Toggle",
        Mouselock = "Toggle",
        Silent = "Toggle",
    },
    Prediction = 0.035,
    Smoothness = 2.5,
    FovEnabled = false,
    FovAimOnly = false,
    FovRadius = 150,
    AimPart = "HumanoidRootPart",
    AdaptiveAim = false,
    AdaptiveStrength = 35,
    WallB = false,
    AutoSwap = false,
    TriggerB = false,
    SemiAutomatic = false,
    SemiAutomaticActive = false,
    SemiAutomaticBind = Enum.KeyCode.Unknown,
    FastShoot = false,
    FastShootRate = 0.05,
    WallCheck = false,
    DeadCheck = true,
    TeamCheck = false,
    ExcludedTeams = {},
    Noclip = false,
    AntiSeat = false,
    Jump = false,
    InfJump = false,
    MaxZoom = false,
    AntiAFK = false,
    AntiRiotShield = false,
    AutoPickup = false,
    AntiFence = false,
    Spinbot = false,
    SpinSpeed = 45,
    TweenClickTP = false,
    TweenClickBind = Enum.KeyCode.Unknown,
    TweenSpeed = 75,
    WalkSpeed = 16,
    VFly = false,
    VFlyBind = Enum.KeyCode.Unknown,
    VFlySpeed = 50,
    NoFog = false,
    NoBlur = false,
    DisableShadows = false,
    DisableTextures = false,
    LongShadows = false,
    LongShadowAmount = 5,
    MotionBlur = false,
    MotionBlurStrength = 5,
    HighReflections = false,
    Bloom = false,
    BloomStrength = 5,
    RealisticLighting = false,
    SmoothTransitions = false,
    CapturedBindingInput = nil,
}

local camTarget
local mouseTarget
local modeToggleControl
local modeKeybindDisplay
local heldMode
local teamControls = {}
local activeCapture
local adaptivePartCache = {}
local toggleControls = {}
local wallBCleanup
local wallBRefreshTeams
local fastShootCleanup
local triggerBCleanup
local PlayerFeatures = {}
local MovementFeatures = {}
local WorldFeatures = {}
local visualESP
local sectionTitleLabels = {}
local sectionStrokes = {}
local compactModeDots

local SectionTitleColors = {
    Light = Color3.fromRGB(79, 84, 93),
    Dark = Color3.fromRGB(185, 189, 197),
    Black = Color3.fromRGB(190, 194, 202),
}

local SectionStrokeColors = {
    -- Match the Consist sidebar stroke exactly in each theme.
    Light = Color3.fromRGB(226, 229, 234),
    Dark = Color3.fromRGB(39, 41, 47),
    Black = Color3.fromRGB(31, 33, 38),
}

local AimPartAliases = {
    HumanoidRootPart = {"HumanoidRootPart", "Torso"},
    Head = {"Head"},
    UpperTorso = {"UpperTorso", "Torso"},
    LeftArm = {"LeftUpperArm", "LeftLowerArm", "LeftHand", "Left Arm"},
    RightArm = {"RightUpperArm", "RightLowerArm", "RightHand", "Right Arm"},
    LeftLeg = {"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "Left Leg"},
    RightLeg = {"RightUpperLeg", "RightLowerLeg", "RightFoot", "Right Leg"},
}

local KeyLabels = {
    MouseButton1 = "LMB",
    MouseButton2 = "RMB",
    MouseButton3 = "MMB",
    Backspace = "BSP",
    Space = "SPC",
    Return = "ENT",
    Escape = "ESC",
    Delete = "DEL",
    Insert = "INS",
    Tab = "TAB",
    Home = "HOM",
    End = "END",
    PageUp = "PGU",
    PageDown = "PGD",
    CapsLock = "CAP",
    LeftShift = "LSH",
    RightShift = "RSH",
    LeftControl = "LCT",
    RightControl = "RCT",
    LeftAlt = "LAL",
    RightAlt = "RAL",
    Up = "UP",
    Down = "DWN",
    Left = "LFT",
    Right = "RGT",
}

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function shortKeyName(value)
    local name = tostring(value)
        :gsub("Enum%.KeyCode%.", "")
        :gsub("Enum%.UserInputType%.", "")
    if name == "Unknown" then
        return "Set"
    end
    return KeyLabels[name] or string.upper(name:sub(1, 3))
end

local function bindingFromInput(input)
    if input.UserInputType == Enum.UserInputType.Keyboard
        and input.KeyCode ~= Enum.KeyCode.Unknown then
        return input.KeyCode
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2
        or input.UserInputType == Enum.UserInputType.MouseButton3 then
        return input.UserInputType
    end
    return nil
end

local function inputMatches(input, binding)
    if typeof(binding) ~= "EnumItem" then
        return false
    end
    if binding.EnumType == Enum.KeyCode then
        return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == binding
    end
    return input.UserInputType == binding
end

local function inputIsOverApp(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.MouseButton2
        and input.UserInputType ~= Enum.UserInputType.MouseButton3 then
        return false
    end
    local position = UserInputService:GetMouseLocation()
    local topLeft = Consist.App.AbsolutePosition
    local size = Consist.App.AbsoluteSize
    return position.X >= topLeft.X
        and position.Y >= topLeft.Y
        and position.X <= topLeft.X + size.X
        and position.Y <= topLeft.Y + size.Y
end

local fastShootOriginals = setmetatable({}, {__mode = "k"})
local fastShootBackpacks = setmetatable({}, {__mode = "k"})
local fastShootCharacters = setmetatable({}, {__mode = "k"})
local fastShootMouseHeld = false
local fastShootGeneration = 0

local function getEquippedFastShootGun()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end
    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool") and object:GetAttribute("ToolType") == "Gun" then
            return object
        end
    end
    return nil
end

local function rememberFastShootAttribute(tool, attribute)
    local values = fastShootOriginals[tool]
    if not values then
        values = {}
        fastShootOriginals[tool] = values
    end
    if values[attribute] == nil then
        values[attribute] = {
            Value = tool:GetAttribute(attribute),
        }
    end
end

local function applyFastShootGun(tool)
    if not State.FastShoot
        or not tool
        or not tool:IsA("Tool")
        or tool:GetAttribute("ToolType") ~= "Gun" then
        return
    end

    local replacements = {
        AutoFire = not (
            State.SemiAutomatic
            and State.SemiAutomaticActive
            and (tool.Name == "AK-47" or tool.Name == "MP5")
        ),
        FireRate = State.FastShootRate,
        Range = 999999,
        AccurateRange = 999999,
        SpreadRadius = 0,
    }
    for attribute, value in pairs(replacements) do
        if tool:GetAttribute(attribute) ~= nil then
            rememberFastShootAttribute(tool, attribute)
            tool:SetAttribute(attribute, value)
        end
    end
end

local function scanFastShootContainer(container)
    if not container then
        return
    end
    for _, object in ipairs(container:GetChildren()) do
        applyFastShootGun(object)
    end
end

local function refreshFastShootGuns()
    scanFastShootContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scanFastShootContainer(LocalPlayer.Character)
end

local function stopFastShootHold()
    fastShootMouseHeld = false
    fastShootGeneration += 1
    local gun = getEquippedFastShootGun()
    if gun then
        pcall(function()
            gun:Deactivate()
        end)
    end
end

local function restoreFastShootGuns()
    for tool, attributes in pairs(fastShootOriginals) do
        if tool and tool.Parent then
            for attribute, original in pairs(attributes) do
                pcall(function()
                    tool:SetAttribute(attribute, original.Value)
                    if attribute == "AutoFire"
                        and State.SemiAutomatic
                        and State.SemiAutomaticActive
                        and (tool.Name == "AK-47" or tool.Name == "MP5") then
                        tool:SetAttribute("AutoFire", false)
                    end
                end)
            end
        end
        fastShootOriginals[tool] = nil
    end
end

local function pulseFastShootGun(tool, generation)
    if not State.FastShoot
        or not fastShootMouseHeld
        or generation ~= fastShootGeneration
        or tool ~= getEquippedFastShootGun()
        or tool:GetAttribute("IsReloading") == true then
        return
    end
    pcall(function()
        tool:Deactivate()
    end)
    task.wait(0.01)
    if State.FastShoot
        and fastShootMouseHeld
        and generation == fastShootGeneration
        and tool == getEquippedFastShootGun()
        and tool:GetAttribute("IsReloading") ~= true then
        pcall(function()
            tool:Activate()
        end)
    end
end

local function fastShootAmmoState(tool)
    return tostring(tool:GetAttribute("CurrentAmmo"))
        .. ":"
        .. tostring(tool:GetAttribute("Local_CurrentAmmo"))
end

local function startFastShootHold()
    fastShootGeneration += 1
    local generation = fastShootGeneration
    task.spawn(function()
        local currentGun
        local lastFireRate
        local lastAmmoState
        local lastProgress = os.clock()
        local lastPulse = 0

        while runtimeAlive
            and State.FastShoot
            and fastShootMouseHeld
            and generation == fastShootGeneration do
            local gun = getEquippedFastShootGun()
            if gun then
                applyFastShootGun(gun)
                local fireRate = gun:GetAttribute("FireRate")
                if gun ~= currentGun or fireRate ~= lastFireRate then
                    currentGun = gun
                    lastFireRate = fireRate
                    lastAmmoState = fastShootAmmoState(gun)
                    lastProgress = os.clock()
                    lastPulse = os.clock()
                    pcall(function()
                        gun:Activate()
                    end)
                end

                local now = os.clock()
                local ammoState = fastShootAmmoState(gun)
                if ammoState ~= lastAmmoState then
                    lastAmmoState = ammoState
                    lastProgress = now
                end

                if gun:GetAttribute("IsReloading") == true then
                    lastProgress = now
                elseif now - lastProgress >= 0.09 and now - lastPulse >= 0.09 then
                    lastPulse = now
                    lastProgress = now
                    pulseFastShootGun(gun, generation)
                    lastFireRate = gun:GetAttribute("FireRate")
                    lastAmmoState = fastShootAmmoState(gun)
                end
            else
                currentGun = nil
                lastFireRate = nil
                lastAmmoState = nil
                lastProgress = os.clock()
            end
            task.wait(0.01)
        end
    end)
end

local function setupFastShootBackpack(backpack)
    if not backpack or fastShootBackpacks[backpack] then
        return
    end
    fastShootBackpacks[backpack] = true
    scanFastShootContainer(backpack)
    connect(backpack.ChildAdded, function(object)
        if object:IsA("Tool") then
            applyFastShootGun(object)
            for _, delayTime in ipairs({0.05, 0.10, 0.25}) do
                task.delay(delayTime, function()
                    if runtimeAlive and object.Parent then
                        applyFastShootGun(object)
                    end
                end)
            end
        end
    end)
end

local function setupFastShootCharacter(character)
    if not character or fastShootCharacters[character] then
        return
    end
    fastShootCharacters[character] = true
    scanFastShootContainer(character)
    connect(character.ChildAdded, function(object)
        if object:IsA("Tool") then
            applyFastShootGun(object)
        end
    end)
end

local function setFastShootEnabled(enabled)
    State.FastShoot = enabled == true
    if State.FastShoot then
        setupFastShootBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
        setupFastShootCharacter(LocalPlayer.Character)
        refreshFastShootGuns()
    else
        stopFastShootHold()
        restoreFastShootGuns()
    end
end

connect(UserInputService.InputBegan, function(input, processed)
    if not State.FastShoot
        or processed
        or input.UserInputType ~= Enum.UserInputType.MouseButton1
        or inputIsOverApp(input)
        or fastShootMouseHeld then
        return
    end

    local gun = getEquippedFastShootGun()
    if gun
        and State.SemiAutomatic
        and State.SemiAutomaticActive
        and (gun.Name == "AK-47" or gun.Name == "MP5") then
        applyFastShootGun(gun)
        return
    end

    fastShootMouseHeld = true
    if gun then
        applyFastShootGun(gun)
        pcall(function()
            gun:Activate()
        end)
    end
    startFastShootHold()
end)

connect(UserInputService.InputEnded, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 and fastShootMouseHeld then
        stopFastShootHold()
    end
end)

connect(LocalPlayer.ChildAdded, function(object)
    if object:IsA("Backpack") then
        setupFastShootBackpack(object)
    end
end)

connect(LocalPlayer.CharacterAdded, function(character)
    stopFastShootHold()
    setupFastShootCharacter(character)
    task.defer(function()
        if runtimeAlive then
            setupFastShootBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
            refreshFastShootGuns()
        end
    end)
end)

setupFastShootBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
setupFastShootCharacter(LocalPlayer.Character)

fastShootCleanup = function()
    setFastShootEnabled(false)
end

do
local semiSavedAutoFire = setmetatable({}, {__mode = "k"})
local semiBackpacks = setmetatable({}, {__mode = "k"})
local semiCharacters = setmetatable({}, {__mode = "k"})

local function semiSupported(tool)
    return tool
        and tool:IsA("Tool")
        and (tool.Name == "AK-47" or tool.Name == "MP5")
end

-- The game's gun controller reads its weapon configuration through GetAttributes.
-- Keep the real Tool attribute synchronized too, but also override the returned
-- AutoFire value so full-auto controller loops see these two guns as semi-auto.
local semiOldNamecall
if type(hookmetamethod) == "function"
    and type(newcclosure) == "function"
    and type(getnamecallmethod) == "function" then
    semiOldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(object, ...)
        local method = getnamecallmethod()
        if method == "GetAttributes"
            and State.SemiAutomatic
            and State.SemiAutomaticActive
            and semiSupported(object) then
            local attributes = semiOldNamecall(object, ...)
            if type(attributes) == "table" then
                attributes = table.clone(attributes)
                attributes.AutoFire = false
            end
            return attributes
        end
        return semiOldNamecall(object, ...)
    end))
end

local function saveSemiAutoFire(tool)
    if semiSavedAutoFire[tool] == nil then
        semiSavedAutoFire[tool] = {Value = tool:GetAttribute("AutoFire")}
    end
end

local function applySemiTool(tool)
    if not State.SemiAutomatic or not State.SemiAutomaticActive or not semiSupported(tool) then
        return
    end
    if tool:GetAttribute("AutoFire") ~= nil then
        saveSemiAutoFire(tool)
        pcall(function()
            tool:SetAttribute("AutoFire", false)
        end)
    end
end

local function scanSemiContainer(container)
    if not container then
        return
    end
    for _, object in ipairs(container:GetChildren()) do
        applySemiTool(object)
    end
end

local function restoreSemiTools()
    for tool, saved in pairs(semiSavedAutoFire) do
        if tool and tool.Parent then
            pcall(function()
                if State.FastShoot then
                    tool:SetAttribute("AutoFire", true)
                    applyFastShootGun(tool)
                else
                    tool:SetAttribute("AutoFire", saved.Value)
                end
            end)
        end
        semiSavedAutoFire[tool] = nil
    end
end

local function refreshSemiTools()
    scanSemiContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scanSemiContainer(LocalPlayer.Character)
end

local function setSemiRuntimeActive(active)
    State.SemiAutomaticActive = State.SemiAutomatic and active == true
    if State.SemiAutomaticActive then
        stopFastShootHold()
        refreshSemiTools()
    else
        restoreSemiTools()
    end
end

local function setSemiAutomaticEnabled(enabled)
    State.SemiAutomatic = enabled == true
    setSemiRuntimeActive(State.SemiAutomatic)
end

local function setupSemiBackpack(backpack)
    if not backpack or semiBackpacks[backpack] then
        return
    end
    semiBackpacks[backpack] = true
    scanSemiContainer(backpack)
    connect(backpack.ChildAdded, function(object)
        if semiSupported(object) then
            task.defer(function()
                if runtimeAlive and object.Parent then
                    applySemiTool(object)
                end
            end)
        end
    end)
end

local function setupSemiCharacter(character)
    if not character or semiCharacters[character] then
        return
    end
    semiCharacters[character] = true
    scanSemiContainer(character)
    connect(character.ChildAdded, function(object)
        if semiSupported(object) then
            task.defer(function()
                if runtimeAlive and object.Parent then
                    applySemiTool(object)
                end
            end)
        end
    end)
end

connect(UserInputService.InputBegan, function(input, processed)
    if processed
        or activeCapture
        or State.CapturedBindingInput == input
        or UserInputService:GetFocusedTextBox()
        or inputIsOverApp(input)
        or not inputMatches(input, State.SemiAutomaticBind) then
        return
    end

    if State.SemiAutomatic then
        setSemiRuntimeActive(not State.SemiAutomaticActive)
    end
end)

connect(LocalPlayer.ChildAdded, function(object)
    if object:IsA("Backpack") then
        setupSemiBackpack(object)
    end
end)

connect(LocalPlayer.CharacterAdded, function(character)
    setupSemiCharacter(character)
    task.defer(function()
        if runtimeAlive then
            setupSemiBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
            if State.SemiAutomaticActive then
                refreshSemiTools()
            end
        end
    end)
end)

setupSemiBackpack(LocalPlayer:FindFirstChildOfClass("Backpack"))
setupSemiCharacter(LocalPlayer.Character)

semiAutomaticCleanup = function()
    State.SemiAutomatic = false
    State.SemiAutomaticActive = false
    restoreSemiTools()
end

MovementFeatures.SetSemiAutomatic = setSemiAutomaticEnabled
MovementFeatures.SetSemiAutomaticBind = function(binding)
    State.SemiAutomaticBind = binding
end
end

do
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local VirtualUser = game:GetService("VirtualUser")
local autoSwapPriorities = {
    M4A1 = 1,
    ["AK-47"] = 1,
    MP5 = 1,
    FAL = 1,
    ["Remington 870"] = 2,
    M9 = 3,
    Revolver = 4,
}
local autoSwapConnection
local autoSwapLastRun = 0

local function getAutoSwapWeapon()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        return nil
    end
    local weapons = {}
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool")
            and tool:GetAttribute("FireRate") ~= nil
            and (tool:GetAttribute("Local_ReloadSession") or 0) <= 0
            and tool.Name ~= "Taser"
            and tool.Name ~= "M700" then
            table.insert(weapons, tool)
        end
    end
    table.sort(weapons, function(a, b)
        return (autoSwapPriorities[a.Name] or 100)
            < (autoSwapPriorities[b.Name] or 100)
    end)
    return weapons[1]
end

local function setAutoSwapEnabled(enabled)
    State.AutoSwap = enabled == true
    if autoSwapConnection then
        autoSwapConnection:Disconnect()
        autoSwapConnection = nil
    end
    if not State.AutoSwap then
        return
    end

    autoSwapConnection = RunService.Heartbeat:Connect(function()
        if not runtimeAlive or not State.AutoSwap then
            return
        end
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local equipped = character and character:FindFirstChildOfClass("Tool")
        if not humanoid or not equipped then
            return
        end
        local ammo = equipped:GetAttribute("Local_CurrentAmmo")
        if ammo == nil then
            ammo = equipped:GetAttribute("CurrentAmmo")
        end
        if type(ammo) ~= "number" or ammo > 0 or os.clock() - autoSwapLastRun < 0.15 then
            return
        end
        local replacement = getAutoSwapWeapon()
        if replacement then
            autoSwapLastRun = os.clock()
            pcall(function()
                humanoid:EquipTool(replacement)
            end)
        end
    end)
end

local PhysicsService = game:GetService("PhysicsService")
local noclipConnection
local noclipExtraConnections = {}
local noclipPartConnections = {}
local noclipSavedCollisions = {}
local NoclipGroup = "ConsistGhost"
local noclipGroupReady = false
local noclipGroupAttempted = false
local maxZoomSaved
local starterMaxZoomSaved
local antiSeatConnection
local antiSeatHumanoid
local antiSeatStateEnabled
local jumpConnection
local jumpHumanoid
local jumpStateEnabled
local jumpBaseline
local jumpLastFire = 0
local antiAfkConnection
local riotConnection
local riotSaved = setmetatable({}, {__mode = "k"})
local pickupConnections = {}
local pickupItems = setmetatable({}, {__mode = "k"})
local pickupGeneration = 0
local fenceSaved = setmetatable({}, {__mode = "k"})
local fenceConnection
local spinConnection
local spinHumanoid
local spinSavedAutoRotate
local spinMover
local spinRoot

local function disconnectNoclipConnection(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function disconnectNoclipRuntimeConnections()
    disconnectNoclipConnection(noclipConnection)
    noclipConnection = nil
    for _, connection in ipairs(noclipExtraConnections) do
        disconnectNoclipConnection(connection)
    end
    table.clear(noclipExtraConnections)
end

local function disconnectNoclipPartConnections()
    for part, partConnections in pairs(noclipPartConnections) do
        for _, connection in ipairs(partConnections) do
            disconnectNoclipConnection(connection)
        end
        noclipPartConnections[part] = nil
    end
end

local function prepareNoclipCollisionGroup()
    if noclipGroupAttempted then
        return noclipGroupReady
    end
    noclipGroupAttempted = true
    local ok = pcall(function()
        local groups = PhysicsService:GetRegisteredCollisionGroups()
        local found = false
        for _, groupInfo in ipairs(groups) do
            local groupName = groupInfo.name or groupInfo.Name
            if groupName == NoclipGroup then
                found = true
                break
            end
        end
        if not found then
            PhysicsService:RegisterCollisionGroup(NoclipGroup)
        end
        groups = PhysicsService:GetRegisteredCollisionGroups()
        for _, groupInfo in ipairs(groups) do
            local groupName = groupInfo.name or groupInfo.Name
            if type(groupName) == "string" then
                PhysicsService:CollisionGroupSetCollidable(NoclipGroup, groupName, false)
            end
        end
        PhysicsService:CollisionGroupSetCollidable(NoclipGroup, NoclipGroup, false)
    end)
    noclipGroupReady = ok
    return noclipGroupReady
end

local function saveNoclipPartState(part)
    if not part or not part:IsA("BasePart") or noclipSavedCollisions[part] then
        return
    end
    noclipSavedCollisions[part] = {
        CanCollide = part.CanCollide,
        CollisionGroup = part.CollisionGroup,
    }
end

local function forceNoclipPart(part)
    if not part or not part:IsA("BasePart") or not part.Parent then
        return
    end
    saveNoclipPartState(part)
    pcall(function()
        part.CanCollide = false
    end)
    if noclipGroupReady then
        pcall(function()
            part.CollisionGroup = NoclipGroup
        end)
    end
end

local function bindNoclipPart(part)
    if not part or not part:IsA("BasePart") then
        return
    end
    forceNoclipPart(part)
    if noclipPartConnections[part] then
        return
    end
    local partConnections = {}
    table.insert(partConnections, part:GetPropertyChangedSignal("CanCollide"):Connect(function()
        if State.Noclip and part.Parent and part.CanCollide then
            pcall(function()
                part.CanCollide = false
            end)
        end
    end))
    if noclipGroupReady then
        table.insert(partConnections, part:GetPropertyChangedSignal("CollisionGroup"):Connect(function()
            if State.Noclip and part.Parent and part.CollisionGroup ~= NoclipGroup then
                pcall(function()
                    part.CollisionGroup = NoclipGroup
                end)
            end
        end))
    end
    noclipPartConnections[part] = partConnections
end

local function forceCharacterNoclip(character)
    if not character then
        return
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            bindNoclipPart(descendant)
        end
    end
end

local function restoreNoclipParts()
    for part, saved in pairs(noclipSavedCollisions) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = saved.CanCollide
            end)
            pcall(function()
                part.CollisionGroup = saved.CollisionGroup
            end)
        end
    end
    table.clear(noclipSavedCollisions)
end

local function stopNoclip()
    State.Noclip = false
    disconnectNoclipRuntimeConnections()
    disconnectNoclipPartConnections()
    restoreNoclipParts()
end

local function startNoclip()
    if noclipConnection and State.Noclip then
        return
    end
    disconnectNoclipRuntimeConnections()
    disconnectNoclipPartConnections()
    table.clear(noclipSavedCollisions)
    State.Noclip = true
    prepareNoclipCollisionGroup()

    local character = LocalPlayer.Character
    if character then
        forceCharacterNoclip(character)
        table.insert(noclipExtraConnections, character.DescendantAdded:Connect(function(descendant)
            if State.Noclip and descendant:IsA("BasePart") then
                task.defer(function()
                    if State.Noclip and descendant.Parent then
                        bindNoclipPart(descendant)
                    end
                end)
            end
        end))
    end

    local function enforceNoclip()
        if State.Noclip then
            forceCharacterNoclip(LocalPlayer.Character)
        end
    end

    local physicsSignal = RunService.Stepped
    pcall(function()
        if RunService.PreSimulation then
            physicsSignal = RunService.PreSimulation
        end
    end)
    noclipConnection = physicsSignal:Connect(enforceNoclip)
    if physicsSignal ~= RunService.Stepped then
        table.insert(noclipExtraConnections, RunService.Stepped:Connect(enforceNoclip))
    end
end

local function setNoclipEnabled(enabled)
    if enabled then
        startNoclip()
    else
        stopNoclip()
    end
end

local function restoreAntiSeatHumanoid()
    if antiSeatHumanoid and antiSeatHumanoid.Parent and antiSeatStateEnabled ~= nil then
        pcall(function()
            antiSeatHumanoid:SetStateEnabled(
                Enum.HumanoidStateType.Seated,
                antiSeatStateEnabled
            )
        end)
    end
    antiSeatHumanoid = nil
    antiSeatStateEnabled = nil
end

local function bindAntiSeatHumanoid(humanoid)
    if humanoid == antiSeatHumanoid then
        return
    end

    restoreAntiSeatHumanoid()
    antiSeatHumanoid = humanoid
    if not humanoid then
        return
    end

    local ok, enabled = pcall(function()
        return humanoid:GetStateEnabled(Enum.HumanoidStateType.Seated)
    end)
    antiSeatStateEnabled = ok and enabled or true

    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        humanoid.Sit = false
    end)
end

local function setAntiSeatEnabled(enabled)
    State.AntiSeat = enabled == true

    if antiSeatConnection then
        antiSeatConnection:Disconnect()
        antiSeatConnection = nil
    end

    restoreAntiSeatHumanoid()

    if not State.AntiSeat then
        return
    end

    antiSeatConnection = RunService.Heartbeat:Connect(function()
        if not runtimeAlive or not State.AntiSeat then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if humanoid ~= antiSeatHumanoid then
            bindAntiSeatHumanoid(humanoid)
        end

        if not humanoid then
            return
        end

        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        end)

        local seated = humanoid.Sit
            or humanoid.SeatPart ~= nil
            or humanoid:GetState() == Enum.HumanoidStateType.Seated

        if seated then
            pcall(function()
                humanoid.Sit = false
                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
        end
    end)
end

local function restoreJumpHumanoid()
    if jumpHumanoid and jumpHumanoid.Parent and jumpStateEnabled ~= nil then
        pcall(function()
            jumpHumanoid:SetStateEnabled(
                Enum.HumanoidStateType.Jumping,
                jumpStateEnabled
            )
        end)
    end
    jumpHumanoid = nil
    jumpStateEnabled = nil
    jumpBaseline = nil
end

local function bindJumpHumanoid(humanoid)
    if humanoid == jumpHumanoid then
        return
    end

    restoreJumpHumanoid()
    jumpHumanoid = humanoid
    jumpLastFire = 0

    if not humanoid then
        return
    end

    local ok, enabled = pcall(function()
        return humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
    end)
    jumpStateEnabled = ok and enabled or true

    jumpBaseline = {
        UseJumpPower = humanoid.UseJumpPower,
        JumpPower = humanoid.JumpPower > 1 and humanoid.JumpPower or 50,
        JumpHeight = humanoid.JumpHeight > 0.1 and humanoid.JumpHeight or 7.2,
    }
end

local function jumpVelocityFor(humanoid)
    local baseline = jumpBaseline
    if baseline and baseline.UseJumpPower then
        return math.max(1, baseline.JumpPower)
    end

    local height = baseline and baseline.JumpHeight or humanoid.JumpHeight
    if height <= 0.1 then
        height = 7.2
    end
    return math.sqrt(math.max(0, 2 * workspace.Gravity * height))
end

local function refreshJumpRuntime()
    if jumpConnection then
        jumpConnection:Disconnect()
        jumpConnection = nil
    end

    if not State.Jump and not State.InfJump then
        restoreJumpHumanoid()
        return
    end

    jumpConnection = RunService.Heartbeat:Connect(function()
        if not runtimeAlive or (not State.Jump and not State.InfJump) then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid ~= jumpHumanoid then
            bindJumpHumanoid(humanoid)
        end

        if not humanoid or humanoid.Health <= 0 then
            return
        end

        -- Keep jumping available even when the game's crouch/state script disables it.
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        end)

        if not UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or UserInputService:GetFocusedTextBox()
            or humanoid.SeatPart
            or humanoid.Sit then
            return
        end

        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return
        end

        if State.InfJump then
            -- Hold-friendly infinite jump: keep a smooth upward jump velocity while Space
            -- is held instead of waiting for separate jump pulses.
            local velocity = root.AssemblyLinearVelocity
            local riseSpeed = math.max(30, jumpVelocityFor(humanoid) * 0.70)
            if velocity.Y < riseSpeed then
                root.AssemblyLinearVelocity = Vector3.new(velocity.X, riseSpeed, velocity.Z)
            end
            pcall(function()
                humanoid.Jump = true
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
            return
        end

        -- Normal Jump mode only queues another jump once the character is grounded.
        -- Holding Space therefore behaves like holding jump on a baseplate: jump,
        -- land, immediately jump again. It never adds another impulse in mid-air.
        local state = humanoid:GetState()
        local groundedState = humanoid.FloorMaterial ~= Enum.Material.Air
            or state == Enum.HumanoidStateType.Landed
            or state == Enum.HumanoidStateType.Running
            or state == Enum.HumanoidStateType.RunningNoPhysics
        local grounded = groundedState and root.AssemblyLinearVelocity.Y <= 2

        if not State.Jump or not grounded then
            return
        end

        local now = os.clock()
        if now - jumpLastFire < 0.10 then
            return
        end
        jumpLastFire = now

        local beforeY = root.AssemblyLinearVelocity.Y
        pcall(function()
            humanoid.Jump = true
            humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
        end)

        -- Some crouch systems zero JumpPower/JumpHeight or immediately reject Humanoid.Jump.
        -- Only while grounded, supply the original jump impulse as a fallback.
        if root.AssemblyLinearVelocity.Y <= math.max(1, beforeY) then
            local velocity = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(
                velocity.X,
                jumpVelocityFor(humanoid),
                velocity.Z
            )
        end
    end)
end

local function setJumpEnabled(enabled)
    State.Jump = enabled == true
    refreshJumpRuntime()
end

local function setInfJumpEnabled(enabled)
    State.InfJump = enabled == true
    refreshJumpRuntime()
end

local function setMaxZoomEnabled(enabled)
    State.MaxZoom = enabled == true
    if State.MaxZoom then
        if maxZoomSaved == nil then
            maxZoomSaved = LocalPlayer.CameraMaxZoomDistance
            starterMaxZoomSaved = StarterPlayer.CameraMaxZoomDistance
        end
        LocalPlayer.CameraMaxZoomDistance = 1000000
        StarterPlayer.CameraMaxZoomDistance = 1000000
    else
        if maxZoomSaved ~= nil then
            LocalPlayer.CameraMaxZoomDistance = maxZoomSaved
            StarterPlayer.CameraMaxZoomDistance = starterMaxZoomSaved or maxZoomSaved
            maxZoomSaved = nil
            starterMaxZoomSaved = nil
        end
    end
end

local function setAntiAfkEnabled(enabled)
    State.AntiAFK = enabled == true
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    if State.AntiAFK then
        antiAfkConnection = LocalPlayer.Idled:Connect(function()
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(
                    Vector2.new(0, 0),
                    workspace.CurrentCamera and workspace.CurrentCamera.CFrame or CFrame.new()
                )
            end)
        end)
    end
end

local function restoreRiotShields()
    for shield, canQuery in pairs(riotSaved) do
        if shield and shield.Parent then
            pcall(function()
                shield.CanQuery = canQuery
            end)
        end
        riotSaved[shield] = nil
    end
end

local function setAntiRiotShieldEnabled(enabled)
    State.AntiRiotShield = enabled == true
    if riotConnection then
        riotConnection:Disconnect()
        riotConnection = nil
    end
    if not State.AntiRiotShield then
        restoreRiotShields()
        return
    end
    riotConnection = RunService.Heartbeat:Connect(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local shield = player.Character:FindFirstChild("RiotShieldPart", true)
                if shield and shield:IsA("BasePart") then
                    if riotSaved[shield] == nil then
                        riotSaved[shield] = shield.CanQuery
                    end
                    shield.CanQuery = false
                end
            end
        end
    end)
end

local function disconnectPickupConnections()
    for _, connection in ipairs(pickupConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(pickupConnections)
end

local function registerPickup(object)
    if object:IsA("Model")
        and object.Name ~= "Model"
        and object:GetAttribute("ToolName") then
        pickupItems[object] = true
    end
end

local function setAutoPickupEnabled(enabled)
    State.AutoPickup = enabled == true
    pickupGeneration += 1
    local generation = pickupGeneration
    disconnectPickupConnections()
    table.clear(pickupItems)
    if not State.AutoPickup then
        return
    end

    for _, object in ipairs(workspace:GetDescendants()) do
        registerPickup(object)
    end
    table.insert(pickupConnections, workspace.DescendantAdded:Connect(registerPickup))
    table.insert(pickupConnections, workspace.DescendantRemoving:Connect(function(object)
        pickupItems[object] = nil
    end))

    task.spawn(function()
        while runtimeAlive and State.AutoPickup and generation == pickupGeneration do
            local character = LocalPlayer.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            local giverPressed = remotes and remotes:FindFirstChild("GiverPressed")
            if root and backpack and giverPressed then
                for pickup in pairs(pickupItems) do
                    if pickup and pickup.Parent then
                        local primary = pickup.PrimaryPart
                        local toolName = pickup:GetAttribute("ToolName")
                        if primary
                            and type(toolName) == "string"
                            and not backpack:FindFirstChild(toolName)
                            and not (character and character:FindFirstChild(toolName))
                            and (primary.Position - root.Position).Magnitude < 12 then
                            pcall(function()
                                giverPressed:FireServer(pickup)
                            end)
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)
end

local function restoreFenceParts()
    for part, canTouch in pairs(fenceSaved) do
        if part and part.Parent then
            pcall(function()
                part.CanTouch = canTouch
            end)
        end
        fenceSaved[part] = nil
    end
end

local function setAntiFenceEnabled(enabled)
    State.AntiFence = enabled == true
    if fenceConnection then
        fenceConnection:Disconnect()
        fenceConnection = nil
    end
    if not State.AntiFence then
        restoreFenceParts()
        return
    end
    local fences = workspace:FindFirstChild("Prison_Fences")
    if not fences then
        return
    end
    for _, part in ipairs(fences:GetDescendants()) do
        if part:IsA("BasePart") then
            if fenceSaved[part] == nil then
                fenceSaved[part] = part.CanTouch
            end
            part.CanTouch = false
        end
    end
    fenceConnection = fences.DescendantAdded:Connect(function(part)
        if State.AntiFence and part:IsA("BasePart") then
            if fenceSaved[part] == nil then
                fenceSaved[part] = part.CanTouch
            end
            part.CanTouch = false
        end
    end)
end

local function destroySpinMover()
    if spinMover then
        pcall(function()
            spinMover:Destroy()
        end)
        spinMover = nil
    end
    spinRoot = nil
end

local function restoreSpinHumanoid()
    destroySpinMover()
    if spinHumanoid and spinHumanoid.Parent then
        spinHumanoid.AutoRotate = spinSavedAutoRotate == nil and true or spinSavedAutoRotate
    end
    spinHumanoid = nil
    spinSavedAutoRotate = nil
end

local function ensureSpinMover(root)
    if not root or not root.Parent then
        destroySpinMover()
        return nil
    end
    if spinMover and spinMover.Parent == root and spinRoot == root then
        return spinMover
    end

    destroySpinMover()
    local mover = Instance.new("BodyAngularVelocity")
    mover.Name = "ConsistSpinbotMover"
    mover.MaxTorque = Vector3.new(0, 1000000000, 0)
    mover.P = 100000
    mover.AngularVelocity = Vector3.new(0, math.rad(State.SpinSpeed), 0)
    mover.Parent = root
    spinMover = mover
    spinRoot = root
    return mover
end

local function setSpinbotEnabled(enabled)
    State.Spinbot = enabled == true
    if spinConnection then
        spinConnection:Disconnect()
        spinConnection = nil
    end
    restoreSpinHumanoid()
    if not State.Spinbot then
        return
    end

    spinConnection = RunService.Heartbeat:Connect(function()
        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")

        if humanoid ~= spinHumanoid then
            restoreSpinHumanoid()
            spinHumanoid = humanoid
            if spinHumanoid then
                spinSavedAutoRotate = spinHumanoid.AutoRotate
            end
        end

        if humanoid then
            humanoid.AutoRotate = false
        end

        local mover = ensureSpinMover(root)
        if mover then
            mover.AngularVelocity = Vector3.new(0, math.rad(State.SpinSpeed), 0)
        end
    end)
end

PlayerFeatures.Cleanup = function()
    setAutoSwapEnabled(false)
    setNoclipEnabled(false)
    setAntiSeatEnabled(false)
    setJumpEnabled(false)
    setInfJumpEnabled(false)
    setMaxZoomEnabled(false)
    setAntiAfkEnabled(false)
    setAntiRiotShieldEnabled(false)
    setAutoPickupEnabled(false)
    setAntiFenceEnabled(false)
    setSpinbotEnabled(false)
end

PlayerFeatures.SetAutoSwap = setAutoSwapEnabled
PlayerFeatures.SetNoclip = setNoclipEnabled
PlayerFeatures.SetAntiSeat = setAntiSeatEnabled
PlayerFeatures.SetJump = setJumpEnabled
PlayerFeatures.SetInfJump = setInfJumpEnabled
PlayerFeatures.SetMaxZoom = setMaxZoomEnabled
PlayerFeatures.SetAntiAFK = setAntiAfkEnabled
PlayerFeatures.SetAntiRiotShield = setAntiRiotShieldEnabled
PlayerFeatures.SetAutoPickup = setAutoPickupEnabled
PlayerFeatures.SetAntiFence = setAntiFenceEnabled
PlayerFeatures.SetSpinbot = setSpinbotEnabled

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.25)
    if State.Noclip then
        disconnectNoclipRuntimeConnections()
        disconnectNoclipPartConnections()
        table.clear(noclipSavedCollisions)
        startNoclip()
    end
    if State.MaxZoom then
        setMaxZoomEnabled(true)
    end
end)
end

do
local activeTweenTP
local tweenClickConnection
local walkSpeedConnection
local walkSpeedHumanoid
local savedWalkSpeed
local vFlyEntity = {
    isAlive = false,
    character = {},
}

local function refreshVFlyEntity()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")

    vFlyEntity.isAlive = humanoid ~= nil
        and root ~= nil
        and humanoid.Health > 0

    vFlyEntity.character.Humanoid = humanoid
    vFlyEntity.character.RootPart = root
end

local VehicleFly = {
    Enabled = false,
    Mode = "CFrame",
    Speed = State.VFlySpeed,
    welds = {},
    up = 0,
    down = 0,
    Connections = {},
}

local function cancelTweenTP()
    if activeTweenTP then
        pcall(function()
            activeTweenTP:Cancel()
        end)
        activeTweenTP = nil
    end
end

local function tweenToPosition(position)
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 or not position then
        return
    end

    cancelTweenTP()
    local destination = position + Vector3.new(0, 3, 0)
    local distance = (destination - root.Position).Magnitude
    if distance <= 0.1 or distance > 2000 then
        return
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    local target = CFrame.new(destination) * root.CFrame.Rotation
    activeTweenTP = TweenService:Create(
        root,
        TweenInfo.new(
            distance / math.max(5, State.TweenSpeed),
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.Out
        ),
        {CFrame = target}
    )
    local completedConnection
    completedConnection = activeTweenTP.Completed:Connect(function()
        if completedConnection then
            completedConnection:Disconnect()
            completedConnection = nil
        end
        activeTweenTP = nil
        if root and root.Parent then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    activeTweenTP:Play()
end

local function tweenClickBindHeld(clickInput)
    local binding = State.TweenClickBind
    if typeof(binding) ~= "EnumItem" then
        return false
    end
    if binding.EnumType == Enum.KeyCode then
        return binding ~= Enum.KeyCode.Unknown and UserInputService:IsKeyDown(binding)
    end
    if binding == Enum.UserInputType.MouseButton1 then
        return clickInput and clickInput.UserInputType == Enum.UserInputType.MouseButton1
    end
    if binding == Enum.UserInputType.MouseButton2
        or binding == Enum.UserInputType.MouseButton3 then
        return UserInputService:IsMouseButtonPressed(binding)
    end
    return false
end

local function setTweenClickEnabled(enabled)
    State.TweenClickTP = enabled == true
    if tweenClickConnection then
        tweenClickConnection:Disconnect()
        tweenClickConnection = nil
    end
    if not State.TweenClickTP then
        cancelTweenTP()
        return
    end
    tweenClickConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed
            or input.UserInputType ~= Enum.UserInputType.MouseButton1
            or UserInputService:GetFocusedTextBox()
            or inputIsOverApp(input)
            or not tweenClickBindHeld(input) then
            return
        end
        local character = LocalPlayer.Character
        local equipped = character and character:FindFirstChildOfClass("Tool")
        if equipped and equipped.Name == "tp tool" then
            return
        end
        if mouse and mouse.Target then
            tweenToPosition(mouse.Hit.Position)
        end
    end)
end

local function restoreWalkSpeed()
    if walkSpeedHumanoid and walkSpeedHumanoid.Parent and savedWalkSpeed ~= nil then
        walkSpeedHumanoid.WalkSpeed = savedWalkSpeed
    end
    walkSpeedHumanoid = nil
    savedWalkSpeed = nil
end

local function applyWalkSpeed()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid ~= walkSpeedHumanoid then
        restoreWalkSpeed()
        walkSpeedHumanoid = humanoid
        if walkSpeedHumanoid then
            savedWalkSpeed = walkSpeedHumanoid.WalkSpeed
        end
    end
    if humanoid then
        humanoid.WalkSpeed = State.WalkSpeed
    end
end

local function setWalkSpeed(value)
    State.WalkSpeed = math.clamp(math.floor(value + 0.5), 16, 32)

    if State.WalkSpeed == 16 then
        if walkSpeedConnection then
            walkSpeedConnection:Disconnect()
            walkSpeedConnection = nil
        end
        restoreWalkSpeed()
        return
    end

    applyWalkSpeed()
    if not walkSpeedConnection then
        walkSpeedConnection = RunService.Heartbeat:Connect(function()
            if runtimeAlive and State.WalkSpeed ~= 16 then
                applyWalkSpeed()
            end
        end)
    end
end

function VehicleFly:Clean(object)
    table.insert(self.Connections, object)
end

function VehicleFly:Enable()
    self.Enabled = true
    self.up, self.down = 0, 0

    self:Clean(UserInputService.InputBegan:Connect(function(input)
        if not UserInputService:GetFocusedTextBox() then
            if input.KeyCode == Enum.KeyCode.Space then
                self.up = 1
            elseif input.KeyCode == Enum.KeyCode.LeftControl then
                self.down = -1
            end
        end
    end))

    self:Clean(UserInputService.InputEnded:Connect(function(input)
        if not UserInputService:GetFocusedTextBox() then
            if input.KeyCode == Enum.KeyCode.Space then
                self.up = 0
            elseif input.KeyCode == Enum.KeyCode.LeftControl then
                self.down = 0
            end
        end
    end))

    if self.Mode == "Part" then
        local part = Instance.new("Part")
        part.Size = Vector3.new(50, 1, 50)
        part.Anchored = true
        part.CanQuery = false
        part.Transparency = 1

        self:Clean(part)

        self:Clean(task.spawn(function()
            while self.Enabled do
                refreshVFlyEntity()
                local seat = vFlyEntity.isAlive
                    and vFlyEntity.character.Humanoid
                    and vFlyEntity.character.Humanoid.SeatPart
                if seat then
                    part.CFrame = CFrame.new(
                        seat.Position - Vector3.new(0, 2.2 - (self.up + self.down), 0)
                    )
                    part.Parent = workspace
                else
                    part.Parent = nil
                end

                task.wait(0.05)
            end
        end))
    else
        local inCar = false
        local old

        self:Clean(RunService.PreSimulation:Connect(function(dt)
            refreshVFlyEntity()

            local seat = vFlyEntity.isAlive
                and vFlyEntity.character.Humanoid
                and vFlyEntity.character.Humanoid.SeatPart
            local root = seat and vFlyEntity.character.RootPart

            if root then
                if seat ~= old then
                    local carContainer = workspace:FindFirstChild("CarContainer")
                    inCar = carContainer
                        and seat:IsDescendantOf(carContainer)
                        and seat:IsA("VehicleSeat")

                    if inCar then
                        table.clear(self.welds)
                        local car = seat.Parent and seat.Parent.Parent
                        if car then
                            local wheels = car:FindFirstChild("Wheels")
                            if wheels then
                                for _, v in wheels:GetDescendants() do
                                    if v.Name == "Rotate" then
                                        local success = pcall(function()
                                            v.Enabled = false
                                        end)
                                        if success then
                                            table.insert(self.welds, v)
                                        end
                                    end
                                end
                            end
                        end
                    end

                    old = seat
                end

                if inCar then
                    local currentCamera = workspace.CurrentCamera
                    if not currentCamera then
                        return
                    end

                    root.AssemblyLinearVelocity = Vector3.new(0, 2.25, 0)
                    root.CFrame = CFrame.lookAlong(
                        root.Position,
                        currentCamera.CFrame.LookVector
                    ) + (
                        vFlyEntity.character.Humanoid.MoveDirection
                        + Vector3.new(0, self.up + self.down, 0)
                    ) * self.Speed * dt
                    currentCamera.CameraSubject = vFlyEntity.character.Humanoid
                end
            elseif old then
                for _, weld in self.welds do
                    pcall(function()
                        weld.Enabled = true
                    end)
                end
                table.clear(self.welds)
                old = nil
            end
        end))
    end
end

function VehicleFly:Disable()
    self.Enabled = false

    for _, v in self.Connections do
        if typeof(v) == "RBXScriptConnection" then
            v:Disconnect()
        elseif typeof(v) == "Instance" then
            v:Destroy()
        elseif typeof(v) == "thread" then
            task.cancel(v)
        end
    end
    table.clear(self.Connections)

    for _, weld in self.welds do
        pcall(function()
            weld.Enabled = true
        end)
    end
    table.clear(self.welds)
end

function VehicleFly:Toggle()
    if self.Enabled then
        self:Disable()
    else
        self:Enable()
    end
end

local function setVFlySpeed(value)
    State.VFlySpeed = math.clamp(math.floor(value + 0.5), 5, 90)
    VehicleFly.Speed = State.VFlySpeed
end

local function setVFlyEnabled(enabled)
    enabled = enabled == true
    State.VFly = enabled

    if enabled then
        if not VehicleFly.Enabled then
            VehicleFly.Speed = State.VFlySpeed
            VehicleFly:Enable()
        end
    elseif VehicleFly.Enabled then
        VehicleFly:Disable()
    end
end

connect(UserInputService.InputBegan, function(input, processed)
    if processed
        or activeCapture
        or State.CapturedBindingInput == input
        or UserInputService:GetFocusedTextBox()
        or inputIsOverApp(input)
        or not inputMatches(input, State.VFlyBind) then
        return
    end

    local enabled = not State.VFly
    setVFlyEnabled(enabled)
    local control = MovementFeatures.VFlyToggleControl
    if control then
        control:Set(enabled, true)
    end
end)

MovementFeatures.SetTweenClick = setTweenClickEnabled
MovementFeatures.SetTweenBind = function(binding)
    State.TweenClickBind = binding
end
MovementFeatures.SetTweenSpeed = function(value)
    State.TweenSpeed = math.clamp(math.floor(value + 0.5), 5, 140)
end
MovementFeatures.SetWalkSpeed = setWalkSpeed
MovementFeatures.SetVFly = setVFlyEnabled
MovementFeatures.SetVFlyBind = function(binding)
    State.VFlyBind = binding
end
MovementFeatures.SetVFlySpeed = setVFlySpeed
MovementFeatures.Cleanup = function()
    setTweenClickEnabled(false)
    setVFlyEnabled(false)
    if walkSpeedConnection then
        walkSpeedConnection:Disconnect()
        walkSpeedConnection = nil
    end
    restoreWalkSpeed()
end
end

do
local baseLighting = {
    GlobalShadows = Lighting.GlobalShadows,
    EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
    EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
    ShadowSoftness = Lighting.ShadowSoftness,
}

local angularSky = Lighting:FindFirstChildOfClass("Sky")
local createdAngularSky = false
local baseSunAngularSize = angularSky and angularSky.SunAngularSize or 21
local baseMoonAngularSize = angularSky and angularSky.MoonAngularSize or 11

local function getAngularSky()
    if angularSky and angularSky.Parent then
        return angularSky
    end

    angularSky = Lighting:FindFirstChildOfClass("Sky")
    if angularSky then
        return angularSky
    end

    angularSky = Instance.new("Sky")
    angularSky.Name = "ConsistAngularSky"
    angularSky.SunAngularSize = baseSunAngularSize
    angularSky.MoonAngularSize = baseMoonAngularSize
    angularSky.Parent = Lighting
    createdAngularSky = true
    return angularSky
end

local fogSaved
local atmosphereSaved = setmetatable({}, {__mode = "k"})
local blurSaved = setmetatable({}, {__mode = "k"})
local textureSaved = {}
local textureConnection
local textureGeneration = 0
local lightingConnection
local longShadowBaseClock
local shadowSavedGlobal
local motionBlurEffect
local bloomEffect
local realisticColorEffect
local motionBlurConnection
local lastMotionCameraCFrame
local motionBlurCurrent = 0
local bloomTransitionGeneration = 0
local realisticTransitionGeneration = 0
local applyLongShadows
local refreshLightingMix
local smoothTweenCache = setmetatable({}, {__mode = "k"})
local smoothClockTarget = Lighting.ClockTime
local smoothClockRendered = Lighting.ClockTime
local smoothClockInternalWrite = false
local smoothClockConnection
local smoothClockChangedConnection
local smoothClockDriver = {
    Source = Lighting.ClockTime,
    Velocity = 0,
    HasVelocity = false,
    LastExternalAt = os.clock(),
    LastIncoming = nil,
}

local function setSmoothProperty(instance, property, value, duration)
    if not instance or not instance.Parent then
        return
    end

    local perInstance = smoothTweenCache[instance]
    if not perInstance then
        perInstance = {}
        smoothTweenCache[instance] = perInstance
    end

    local oldTween = perInstance[property]
    if oldTween then
        pcall(function() oldTween:Cancel() end)
        perInstance[property] = nil
    end

    if not State.SmoothTransitions then
        pcall(function() instance[property] = value end)
        return
    end

    local tween = TweenService:Create(
        instance,
        TweenInfo.new(duration or 0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {[property] = value}
    )
    perInstance[property] = tween
    local completed
    completed = tween.Completed:Connect(function()
        if completed then
            completed:Disconnect()
            completed = nil
        end
        local current = smoothTweenCache[instance]
        if current and current[property] == tween then
            current[property] = nil
        end
    end)
    tween:Play()
end

local function cancelAllSmoothTweens()
    for _, perInstance in pairs(smoothTweenCache) do
        for property, tween in pairs(perInstance) do
            if tween then
                pcall(function() tween:Cancel() end)
            end
            perInstance[property] = nil
        end
    end
end

local function saveAtmosphere(atmosphere)
    if atmosphereSaved[atmosphere] then
        return
    end
    atmosphereSaved[atmosphere] = {
        Density = atmosphere.Density,
        Haze = atmosphere.Haze,
        Glare = atmosphere.Glare,
        Offset = atmosphere.Offset,
    }
end

local function applyNoFogAtmosphere(atmosphere)
    if not atmosphere or not atmosphere:IsA("Atmosphere") then
        return
    end
    saveAtmosphere(atmosphere)
    pcall(function() atmosphere.Density = 0 end)
    pcall(function() atmosphere.Haze = 0 end)
    pcall(function() atmosphere.Glare = 0 end)
end

local function setNoFogEnabled(enabled)
    State.NoFog = enabled == true
    if State.NoFog then
        if not fogSaved then
            fogSaved = {
                FogStart = Lighting.FogStart,
                FogEnd = Lighting.FogEnd,
            }
        end
        Lighting.FogStart = 1000000
        Lighting.FogEnd = 1000001
        for _, object in ipairs(Lighting:GetDescendants()) do
            if object:IsA("Atmosphere") then
                applyNoFogAtmosphere(object)
            end
        end
    else
        if fogSaved then
            pcall(function() Lighting.FogStart = fogSaved.FogStart end)
            pcall(function() Lighting.FogEnd = fogSaved.FogEnd end)
            fogSaved = nil
        end
        for atmosphere, saved in pairs(atmosphereSaved) do
            if atmosphere and atmosphere.Parent then
                pcall(function() atmosphere.Density = saved.Density end)
                pcall(function() atmosphere.Haze = saved.Haze end)
                pcall(function() atmosphere.Glare = saved.Glare end)
                pcall(function() atmosphere.Offset = saved.Offset end)
            end
            atmosphereSaved[atmosphere] = nil
        end
    end
end

local function applyNoBlurEffect(effect)
    if not effect or not effect:IsA("BlurEffect") then
        return
    end
    if effect == motionBlurEffect then
        effect.Enabled = false
        return
    end
    if blurSaved[effect] == nil then
        blurSaved[effect] = effect.Enabled
    end
    effect.Enabled = false
end

local function updateMotionBlurEnabledState()
    if motionBlurEffect then
        motionBlurEffect.Enabled = State.MotionBlur and not State.NoBlur
        if not motionBlurEffect.Enabled then
            motionBlurEffect.Size = 0
            motionBlurCurrent = 0
        end
    end
end

local function setNoBlurEnabled(enabled)
    State.NoBlur = enabled == true
    if State.NoBlur then
        for _, object in ipairs(Lighting:GetDescendants()) do
            if object:IsA("BlurEffect") then
                applyNoBlurEffect(object)
            end
        end
    else
        for effect, wasEnabled in pairs(blurSaved) do
            if effect and effect.Parent then
                pcall(function() effect.Enabled = wasEnabled end)
            end
            blurSaved[effect] = nil
        end
    end
    updateMotionBlurEnabledState()
end

local function setDisableShadowsEnabled(enabled)
    local nextState = enabled == true
    if nextState and not State.DisableShadows then
        shadowSavedGlobal = Lighting.GlobalShadows
    end
    State.DisableShadows = nextState

    if State.DisableShadows then
        Lighting.GlobalShadows = false
        if State.LongShadows and applyLongShadows then
            applyLongShadows()
        end
    else
        Lighting.GlobalShadows = shadowSavedGlobal == nil
            and baseLighting.GlobalShadows
            or shadowSavedGlobal
        shadowSavedGlobal = nil
        if State.LongShadows and applyLongShadows then
            applyLongShadows()
        end
    end

    if refreshLightingMix then
        refreshLightingMix()
    end
end

local function isWorldMaterialPart(object)
    if not object or not object.Parent or not object:IsA("BasePart") or not object:IsDescendantOf(workspace) then
        return false
    end

    local currentCamera = workspace.CurrentCamera
    if currentCamera and object:IsDescendantOf(currentCamera) then
        return false
    end

    local ancestor = object.Parent
    while ancestor and ancestor ~= workspace do
        if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
            return false
        end
        ancestor = ancestor.Parent
    end

    return true
end

local function saveTextureObject(object, generation)
    if not State.DisableTextures
        or generation ~= textureGeneration
        or textureSaved[object]
        or not isWorldMaterialPart(object) then
        return
    end

    local saved = {
        Material = object.Material,
    }
    pcall(function()
        saved.MaterialVariant = object.MaterialVariant
    end)
    textureSaved[object] = saved

    pcall(function()
        object.Material = Enum.Material.SmoothPlastic
    end)
    pcall(function()
        object.MaterialVariant = ""
    end)
end

local function restoreTextureObjects()
    local savedObjects = textureSaved
    textureSaved = {}

    for object, saved in pairs(savedObjects) do
        if object and object.Parent then
            pcall(function()
                object.Material = saved.Material
            end)
            if saved.MaterialVariant ~= nil then
                pcall(function()
                    object.MaterialVariant = saved.MaterialVariant
                end)
            end
        end
    end
end

local function setDisableTexturesEnabled(enabled)
    State.DisableTextures = enabled == true
    textureGeneration += 1
    local generation = textureGeneration

    if textureConnection then
        textureConnection:Disconnect()
        textureConnection = nil
    end

    if not State.DisableTextures then
        restoreTextureObjects()
        return
    end

    task.spawn(function()
        local descendants = workspace:GetDescendants()
        for index, object in ipairs(descendants) do
            if not runtimeAlive
                or not State.DisableTextures
                or generation ~= textureGeneration then
                break
            end
            if object:IsA("BasePart") then
                pcall(saveTextureObject, object, generation)
            end
            if index % 500 == 0 then
                task.wait()
            end
        end
    end)

    textureConnection = workspace.DescendantAdded:Connect(function(object)
        if State.DisableTextures and object:IsA("BasePart") then
            local addedGeneration = textureGeneration
            task.defer(function()
                if State.DisableTextures
                    and addedGeneration == textureGeneration
                    and object.Parent then
                    pcall(saveTextureObject, object, addedGeneration)
                end
            end)
        end
    end)
end

local function clockDelta(fromClock, toClock)
    local delta = (toClock - fromClock) % 24
    if delta > 12 then
        delta -= 24
    end
    return delta
end

local function writeSmoothClock(value)
    smoothClockRendered = value % 24
    smoothClockInternalWrite = true
    Lighting.ClockTime = smoothClockRendered
    smoothClockInternalWrite = false
end

local function setSmoothClockTarget(value)
    smoothClockTarget = value % 24
    if not State.SmoothTransitions then
        writeSmoothClock(smoothClockTarget)
    end
end

local function nearestLongShadowClock(baseClock, amount)
    local target
    if baseClock >= 6 and baseClock <= 12 then
        target = 6.35
    elseif baseClock > 12 and baseClock <= 18 then
        target = 17.65
    elseif baseClock < 6 then
        target = 6.35
    else
        target = 17.65
    end
    local alpha = 0.12 + ((math.clamp(amount, 1, 10) - 1) / 9) * 0.73
    return baseClock + ((target - baseClock) * alpha)
end

applyLongShadows = function()
    if State.LongShadows and not State.DisableShadows and longShadowBaseClock then
        local targetClock = nearestLongShadowClock(longShadowBaseClock, State.LongShadowAmount)
        setSmoothClockTarget(targetClock)
    elseif State.DisableShadows and longShadowBaseClock then
        setSmoothClockTarget(longShadowBaseClock)
    end
end

local function setLongShadowsEnabled(enabled)
    State.LongShadows = enabled == true
    if State.LongShadows then
        if longShadowBaseClock == nil then
            longShadowBaseClock = State.SmoothTransitions
                and smoothClockDriver.Source
                or Lighting.ClockTime
        end
        applyLongShadows()
    else
        if longShadowBaseClock ~= nil then
            setSmoothClockTarget(longShadowBaseClock)
            longShadowBaseClock = nil
        end
    end
end

local function setLongShadowAmount(value)
    State.LongShadowAmount = math.clamp(math.floor(value + 0.5), 1, 10)
    applyLongShadows()
end

local function ensureMotionBlurEffect()
    if motionBlurEffect and motionBlurEffect.Parent then
        return motionBlurEffect
    end
    motionBlurEffect = Instance.new("BlurEffect")
    motionBlurEffect.Name = "ConsistMotionBlur"
    motionBlurEffect.Size = 0
    motionBlurEffect.Enabled = false
    motionBlurEffect.Parent = Lighting
    return motionBlurEffect
end

local function setMotionBlurEnabled(enabled)
    State.MotionBlur = enabled == true
    lastMotionCameraCFrame = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or nil

    if not State.MotionBlur then
        motionBlurCurrent = 0
        if motionBlurEffect then
            motionBlurEffect:Destroy()
            motionBlurEffect = nil
        end
        return
    end

    ensureMotionBlurEffect()
    updateMotionBlurEnabledState()
end

local function setMotionBlurStrength(value)
    State.MotionBlurStrength = math.clamp(math.floor(value + 0.5), 1, 10)
end

local function ensureBloomEffect()
    if bloomEffect and bloomEffect.Parent then
        return bloomEffect
    end
    bloomEffect = Instance.new("BloomEffect")
    bloomEffect.Name = "ConsistBloom"
    bloomEffect.Enabled = false
    bloomEffect.Intensity = 0.10
    bloomEffect.Size = 18
    bloomEffect.Threshold = 1.65
    bloomEffect.Parent = Lighting
    return bloomEffect
end

local function updateBloom()
    local effect = ensureBloomEffect()
    local level = math.clamp(State.BloomStrength, 1, 10)
    local intensity = 0.025 + (level / 10) * 0.155
    local size = 14 + level * 0.8
    local threshold = 1.72 - (level / 10) * 0.12
    effect.Enabled = State.Bloom
    setSmoothProperty(effect, "Intensity", intensity, 0.22)
    setSmoothProperty(effect, "Size", size, 0.22)
    setSmoothProperty(effect, "Threshold", threshold, 0.22)
end

local function setBloomEnabled(enabled)
    State.Bloom = enabled == true
    bloomTransitionGeneration += 1
    local generation = bloomTransitionGeneration

    if not State.Bloom then
        if bloomEffect then
            if State.SmoothTransitions then
                local effect = bloomEffect
                setSmoothProperty(effect, "Intensity", 0, 0.20)
                task.delay(0.22, function()
                    if generation == bloomTransitionGeneration
                        and not State.Bloom
                        and effect == bloomEffect then
                        effect:Destroy()
                        bloomEffect = nil
                    end
                end)
            else
                bloomEffect:Destroy()
                bloomEffect = nil
            end
        end
        return
    end
    updateBloom()
end

local function setBloomStrength(value)
    State.BloomStrength = math.clamp(math.floor(value + 0.5), 1, 10)
    updateBloom()
end

local function ensureRealisticColorEffect()
    if realisticColorEffect and realisticColorEffect.Parent then
        return realisticColorEffect
    end
    realisticColorEffect = Instance.new("ColorCorrectionEffect")
    realisticColorEffect.Name = "ConsistRealisticLighting"
    realisticColorEffect.Enabled = false
    realisticColorEffect.Brightness = -0.01
    realisticColorEffect.Contrast = 0.08
    realisticColorEffect.Saturation = -0.025
    realisticColorEffect.TintColor = Color3.fromRGB(255, 252, 247)
    realisticColorEffect.Parent = Lighting
    return realisticColorEffect
end

refreshLightingMix = function()
    local specular = baseLighting.EnvironmentSpecularScale
    local diffuse = baseLighting.EnvironmentDiffuseScale
    local softness = baseLighting.ShadowSoftness
    if State.RealisticLighting then
        specular = math.max(specular, 0.72)
        diffuse = math.max(diffuse, 0.45)
        if not State.DisableShadows then
            softness = math.min(softness, 0.22)
        end
    end
    if State.HighReflections then
        specular = 1
    end
    setSmoothProperty(
        Lighting,
        "EnvironmentSpecularScale",
        math.clamp(specular, 0, 1),
        0.28
    )
    setSmoothProperty(
        Lighting,
        "EnvironmentDiffuseScale",
        math.clamp(diffuse, 0, 1),
        0.28
    )
    setSmoothProperty(
        Lighting,
        "ShadowSoftness",
        math.clamp(softness, 0, 1),
        0.28
    )
    if State.DisableShadows then
        Lighting.GlobalShadows = false
    end
end

local function setHighReflectionsEnabled(enabled)
    State.HighReflections = enabled == true
    refreshLightingMix()
end

local function setRealisticLightingEnabled(enabled)
    State.RealisticLighting = enabled == true
    realisticTransitionGeneration += 1
    local generation = realisticTransitionGeneration

    if State.RealisticLighting then
        local effect = ensureRealisticColorEffect()
        effect.Enabled = true
        if State.SmoothTransitions then
            effect.Brightness = 0
            effect.Contrast = 0
            effect.Saturation = 0
            effect.TintColor = Color3.new(1, 1, 1)
            setSmoothProperty(effect, "Brightness", -0.01, 0.28)
            setSmoothProperty(effect, "Contrast", 0.08, 0.28)
            setSmoothProperty(effect, "Saturation", -0.025, 0.28)
            setSmoothProperty(effect, "TintColor", Color3.fromRGB(255, 252, 247), 0.28)
        else
            effect.Brightness = -0.01
            effect.Contrast = 0.08
            effect.Saturation = -0.025
            effect.TintColor = Color3.fromRGB(255, 252, 247)
        end
    elseif realisticColorEffect then
        if State.SmoothTransitions then
            local effect = realisticColorEffect
            setSmoothProperty(effect, "Brightness", 0, 0.24)
            setSmoothProperty(effect, "Contrast", 0, 0.24)
            setSmoothProperty(effect, "Saturation", 0, 0.24)
            setSmoothProperty(effect, "TintColor", Color3.new(1, 1, 1), 0.24)
            task.delay(0.26, function()
                if generation == realisticTransitionGeneration
                    and not State.RealisticLighting
                    and effect == realisticColorEffect then
                    effect:Destroy()
                    realisticColorEffect = nil
                end
            end)
        else
            realisticColorEffect:Destroy()
            realisticColorEffect = nil
        end
    end
    refreshLightingMix()
end

local function setSunAngularSize(value)
    local maximum = math.max(1, baseSunAngularSize)
    local sky = getAngularSky()
    local target = math.clamp(math.floor(value + 0.5), 1, maximum)
    setSmoothProperty(sky, "SunAngularSize", target, 0.24)
end

local function setMoonAngularSize(value)
    local maximum = math.max(1, baseMoonAngularSize)
    local sky = getAngularSky()
    local target = math.clamp(math.floor(value + 0.5), 1, maximum)
    setSmoothProperty(sky, "MoonAngularSize", target, 0.24)
end

local function setSmoothTransitionsEnabled(enabled)
    State.SmoothTransitions = enabled == true
    smoothClockTarget = Lighting.ClockTime
    smoothClockRendered = Lighting.ClockTime

    if State.SmoothTransitions then
        smoothClockDriver.Source = State.LongShadows and longShadowBaseClock
            or Lighting.ClockTime
        smoothClockDriver.Velocity = 0
        smoothClockDriver.HasVelocity = false
        smoothClockDriver.LastExternalAt = os.clock()
        smoothClockDriver.LastIncoming = nil
        return
    end

    cancelAllSmoothTweens()
    smoothClockDriver.Source = Lighting.ClockTime
    smoothClockDriver.Velocity = 0
    smoothClockDriver.HasVelocity = false
    smoothClockDriver.LastIncoming = nil

    if State.LongShadows and not State.DisableShadows and longShadowBaseClock then
        setSmoothClockTarget(nearestLongShadowClock(longShadowBaseClock, State.LongShadowAmount))
    end
end

smoothClockChangedConnection = Lighting:GetPropertyChangedSignal("ClockTime"):Connect(function()
    if not runtimeAlive or not State.SmoothTransitions or smoothClockInternalWrite then
        return
    end

    local now = os.clock()
    local incoming = Lighting.ClockTime
    local displayed = smoothClockRendered
    local elapsed = math.max(now - smoothClockDriver.LastExternalAt, 1 / 240)
    local observedStep

    if smoothClockDriver.LastIncoming ~= nil then
        observedStep = clockDelta(smoothClockDriver.LastIncoming, incoming)
    else
        observedStep = clockDelta(displayed, incoming)
    end

    -- When Long Shadows is active, some games increment the currently rendered
    -- ClockTime while others write an absolute world time. Use whichever delta
    -- looks like the smaller real game tick so the shadow transform cannot
    -- contaminate the inferred day/night speed.
    if State.LongShadows and not State.DisableShadows then
        local fromDisplay = clockDelta(displayed, incoming)
        local fromSource = clockDelta(smoothClockDriver.Source, incoming)
        local candidate = math.abs(fromDisplay) <= math.abs(fromSource)
            and fromDisplay
            or fromSource
        if math.abs(candidate) < math.abs(observedStep) then
            observedStep = candidate
        end
    end

    if math.abs(observedStep) > 0.000001 and math.abs(observedStep) < 6 then
        local observedVelocity = math.clamp(observedStep / elapsed, -12, 12)
        if smoothClockDriver.HasVelocity then
            if smoothClockDriver.Velocity == 0
                or observedVelocity == 0
                or smoothClockDriver.Velocity * observedVelocity >= 0 then
                smoothClockDriver.Velocity =
                    smoothClockDriver.Velocity * 0.72 + observedVelocity * 0.28
            else
                smoothClockDriver.Velocity = observedVelocity
            end
        else
            smoothClockDriver.Velocity = observedVelocity
            smoothClockDriver.HasVelocity = true
        end
    end

    smoothClockDriver.LastExternalAt = now
    smoothClockDriver.LastIncoming = incoming

    -- Reject the game's visible time jump. From this point the RenderStepped
    -- driver advances the underlying time continuously between game ticks.
    writeSmoothClock(displayed)
end)

smoothClockConnection = RunService.RenderStepped:Connect(function(deltaTime)
    if not runtimeAlive or not State.SmoothTransitions then
        return
    end

    local dt = math.max(deltaTime, 0)
    if smoothClockDriver.HasVelocity then
        smoothClockDriver.Source =
            (smoothClockDriver.Source + smoothClockDriver.Velocity * dt) % 24
    end

    if State.LongShadows then
        longShadowBaseClock = smoothClockDriver.Source
    end

    local desiredClock = smoothClockDriver.Source
    if State.LongShadows and not State.DisableShadows then
        desiredClock = nearestLongShadowClock(
            smoothClockDriver.Source,
            State.LongShadowAmount
        )
    end

    -- Follow the continuously moving source rather than tweening to a stationary
    -- once-per-tick target. This keeps the sun, moon and shadow direction moving
    -- every rendered frame while still easing cleanly when an effect is toggled.
    local delta = clockDelta(smoothClockRendered, desiredClock)
    local alpha = 1 - math.exp(-dt * 18)
    writeSmoothClock(smoothClockRendered + delta * alpha)
end)

lightingConnection = Lighting.DescendantAdded:Connect(function(object)
    if State.NoFog and object:IsA("Atmosphere") then
        task.defer(function()
            if State.NoFog and object.Parent then
                applyNoFogAtmosphere(object)
            end
        end)
    elseif State.NoBlur and object:IsA("BlurEffect") then
        task.defer(function()
            if State.NoBlur and object.Parent then
                applyNoBlurEffect(object)
            end
        end)
    end
end)

motionBlurConnection = RunService.RenderStepped:Connect(function(deltaTime)
    if State.NoFog then
        Lighting.FogStart = 1000000
        Lighting.FogEnd = 1000001
    end
    if State.DisableShadows then
        Lighting.GlobalShadows = false
    end
    if State.LongShadows and not State.SmoothTransitions then
        applyLongShadows()
    end

    if not State.MotionBlur or State.NoBlur then
        lastMotionCameraCFrame = workspace.CurrentCamera and workspace.CurrentCamera.CFrame or nil
        updateMotionBlurEnabledState()
        return
    end

    local effect = ensureMotionBlurEffect()
    local currentCamera = workspace.CurrentCamera
    if not currentCamera then
        effect.Size = 0
        return
    end

    local currentCFrame = currentCamera.CFrame
    local target = 0
    if lastMotionCameraCFrame then
        local relative = lastMotionCameraCFrame:ToObjectSpace(currentCFrame)
        local rx, ry, rz = relative:ToOrientation()
        local safeDelta = math.max(deltaTime, 1 / 240)
        local angularSpeed = (math.abs(rx) + math.abs(ry) + math.abs(rz)) / safeDelta
        local cameraLinearSpeed = (currentCFrame.Position - lastMotionCameraCFrame.Position).Magnitude / safeDelta

        local character = LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local characterSpeed = root and root.AssemblyLinearVelocity.Magnitude or 0
        local movementSpeed = math.max(characterSpeed, cameraLinearSpeed)

        local movementBlur = 0
        if movementSpeed > 1 then
            movementBlur = 0.65 + math.clamp(movementSpeed / 50, 0, 1) * 1.70
        end
        local turnBlur = math.clamp(angularSpeed / 4, 0, 1) * 2.0
        local strengthScale = 0.55 + (State.MotionBlurStrength / 10) * 0.70
        target = math.clamp((movementBlur + turnBlur) * strengthScale, 0, 5.25)
    end
    lastMotionCameraCFrame = currentCFrame
    local response = target > motionBlurCurrent and 16 or 9
    local alpha = math.clamp(deltaTime * response, 0, 1)
    motionBlurCurrent += (target - motionBlurCurrent) * alpha
    effect.Size = motionBlurCurrent
    effect.Enabled = true
end)

WorldFeatures.SetNoFog = setNoFogEnabled
WorldFeatures.SetNoBlur = setNoBlurEnabled
WorldFeatures.SetDisableShadows = setDisableShadowsEnabled
WorldFeatures.SetDisableTextures = setDisableTexturesEnabled
WorldFeatures.SetLongShadows = setLongShadowsEnabled
WorldFeatures.SetLongShadowAmount = setLongShadowAmount
WorldFeatures.SetMotionBlur = setMotionBlurEnabled
WorldFeatures.SetMotionBlurStrength = setMotionBlurStrength
WorldFeatures.SetHighReflections = setHighReflectionsEnabled
WorldFeatures.SetBloom = setBloomEnabled
WorldFeatures.SetBloomStrength = setBloomStrength
WorldFeatures.SetRealisticLighting = setRealisticLightingEnabled
WorldFeatures.SetSmoothTransitions = setSmoothTransitionsEnabled
WorldFeatures.SetSunAngularSize = setSunAngularSize
WorldFeatures.SetMoonAngularSize = setMoonAngularSize
WorldFeatures.DefaultSunAngularSize = math.max(1, baseSunAngularSize)
WorldFeatures.DefaultMoonAngularSize = math.max(1, baseMoonAngularSize)
WorldFeatures.Cleanup = function()
    setSmoothTransitionsEnabled(false)
    cancelAllSmoothTweens()
    setNoFogEnabled(false)
    setNoBlurEnabled(false)
    setDisableShadowsEnabled(false)
    setDisableTexturesEnabled(false)
    setLongShadowsEnabled(false)
    setMotionBlurEnabled(false)
    setBloomEnabled(false)
    setRealisticLightingEnabled(false)
    setHighReflectionsEnabled(false)
    if textureConnection then
        textureConnection:Disconnect()
        textureConnection = nil
    end
    if lightingConnection then
        lightingConnection:Disconnect()
        lightingConnection = nil
    end
    if smoothClockConnection then
        smoothClockConnection:Disconnect()
        smoothClockConnection = nil
    end
    if smoothClockChangedConnection then
        smoothClockChangedConnection:Disconnect()
        smoothClockChangedConnection = nil
    end
    if motionBlurConnection then
        motionBlurConnection:Disconnect()
        motionBlurConnection = nil
    end
    if motionBlurEffect then
        motionBlurEffect:Destroy()
        motionBlurEffect = nil
    end
    if bloomEffect then
        bloomEffect:Destroy()
        bloomEffect = nil
    end
    if realisticColorEffect then
        realisticColorEffect:Destroy()
        realisticColorEffect = nil
    end
    Lighting.EnvironmentDiffuseScale = baseLighting.EnvironmentDiffuseScale
    Lighting.EnvironmentSpecularScale = baseLighting.EnvironmentSpecularScale
    Lighting.ShadowSoftness = baseLighting.ShadowSoftness
    Lighting.GlobalShadows = baseLighting.GlobalShadows

    if angularSky and angularSky.Parent then
        if createdAngularSky then
            angularSky:Destroy()
        else
            angularSky.SunAngularSize = baseSunAngularSize
            angularSky.MoonAngularSize = baseMoonAngularSize
        end
    end
    angularSky = nil
    createdAngularSky = false
end
end

local function installExternalKeybind(control, initialValue, onSelected)
    local row = control.Instance
    local visualButton
    for _, child in ipairs(row:GetChildren()) do
        if child:IsA("TextButton") and child.Text ~= "" then
            visualButton = child
            break
        end
    end
    assert(visualButton, "Consist keybind visual was not found")

    visualButton.Text = shortKeyName(initialValue)
    visualButton.Active = false

    local hit = Instance.new("TextButton")
    hit.Name = "ExternalKeybindHit"
    hit.AnchorPoint = visualButton.AnchorPoint
    hit.Position = visualButton.Position
    hit.Size = visualButton.Size
    hit.BackgroundTransparency = 1
    hit.BorderSizePixel = 0
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.ZIndex = visualButton.ZIndex + 1
    hit.Parent = row

    local api = {}

    function api:Set(value)
        control:Set(value, true)
        visualButton.Text = shortKeyName(value)
    end

    hit.MouseButton1Click:Connect(function()
        activeCapture = {
            Display = api,
            Visual = visualButton,
            Callback = onSelected,
        }
        visualButton.Text = "..."
    end)

    return api
end

local function resolveAimPart(character, selection)
    if not character then
        return nil
    end
    for _, partName in ipairs(AimPartAliases[selection] or {selection}) do
        local part = character:FindFirstChild(partName)
        if part and part:IsA("BasePart") then
            return part
        end
    end
    return character:FindFirstChild("HumanoidRootPart")
end

local function isModeActive(modeName)
    return runtimeAlive
        and State.SelectedMode == modeName
        and State.ModeEnabled[modeName] == true
end

local function clearTargets()
    camTarget = nil
    mouseTarget = nil
    table.clear(adaptivePartCache)
end

local function teamIsExcluded(player)
    return State.TeamCheck
        and player.Team ~= nil
        and State.ExcludedTeams[player.Team.Name] == true
end

local function validTarget(player)
    if not player or player == LocalPlayer or not player.Character then
        return false
    end
    local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid or (State.DeadCheck and humanoid.Health <= 0) then
        return false
    end
    if not player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    return not teamIsExcluded(player)
end

local function partVisible(part)
    camera = workspace.CurrentCamera
    if not camera or not part then
        return false
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = LocalPlayer.Character and {LocalPlayer.Character} or {}
    local result = workspace:Raycast(
        camera.CFrame.Position,
        part.Position - camera.CFrame.Position,
        params
    )
    return result == nil or result.Instance:IsDescendantOf(part.Parent)
end

local AdaptiveSelections = {
    "HumanoidRootPart",
    "Head",
    "UpperTorso",
    "LeftArm",
    "RightArm",
    "LeftLeg",
    "RightLeg",
}

local function getAimPart(character, screenAnchor, ignoreWallCheck)
    if not State.AdaptiveAim then
        return resolveAimPart(character, State.AimPart)
    end
    camera = workspace.CurrentCamera
    if not camera then
        return resolveAimPart(character, State.AimPart)
    end

    local bestPart
    local bestScore = math.huge
    local currentPart = adaptivePartCache[character]
    local currentScore = math.huge
    local seen = {}

    for _, selection in ipairs(AdaptiveSelections) do
        local part = resolveAimPart(character, selection)
        if part and not seen[part] then
            seen[part] = true
            local point, onScreen = camera:WorldToViewportPoint(part.Position)
            if onScreen and point.Z > 0 then
                local score = (Vector2.new(point.X, point.Y) - screenAnchor).Magnitude
                if State.WallCheck and not ignoreWallCheck and not partVisible(part) then
                    score += 100000
                end
                if score < bestScore then
                    bestScore = score
                    bestPart = part
                end
                if part == currentPart then
                    currentScore = score
                end
            end
        end
    end

    local switchResistance = math.clamp(State.AdaptiveStrength, 0, 100) * 0.9
    if currentPart
        and currentPart.Parent == character
        and currentScore < math.huge
        and bestScore + switchResistance >= currentScore then
        return currentPart
    end

    local selected = bestPart or resolveAimPart(character, State.AimPart)
    adaptivePartCache[character] = selected
    return selected
end

local function findTarget(screenAnchor, ignoreWallCheck)
    camera = workspace.CurrentCamera
    if not camera then
        return nil, nil
    end

    local bestPlayer
    local bestPart
    local bestDistance = State.FovRadius

    for _, player in ipairs(Players:GetPlayers()) do
        if validTarget(player) then
            local part = getAimPart(player.Character, screenAnchor, ignoreWallCheck)
            if part and (ignoreWallCheck or not State.WallCheck or partVisible(part)) then
                local point, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and point.Z > 0 then
                    local distance = (Vector2.new(point.X, point.Y) - screenAnchor).Magnitude
                    if distance < bestDistance then
                        bestDistance = distance
                        bestPlayer = player
                        bestPart = part
                    end
                end
            end
        end
    end

    return bestPlayer, bestPart
end

local setTriggerBEnabled
do
local triggerBConnection
local triggerBLastShot = 0
local triggerBLastGun
local triggerBPressed = false

local triggerMousePress
local triggerMouseRelease
local triggerMouseClick
pcall(function()
    triggerMousePress = environment.mouse1press or mouse1press
    triggerMouseRelease = environment.mouse1release or mouse1release
    triggerMouseClick = environment.mouse1click or mouse1click
end)

local triggerVirtualInput
pcall(function()
    triggerVirtualInput = game:GetService("VirtualInputManager")
end)

local function triggerBAmmo(tool)
    if not tool then
        return nil
    end

    local ammo = tool:GetAttribute("Local_CurrentAmmo")
    if type(ammo) ~= "number" then
        ammo = tool:GetAttribute("CurrentAmmo")
    end
    return type(ammo) == "number" and ammo or nil
end

local function getEquippedTriggerGun()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end

    for _, object in ipairs(character:GetChildren()) do
        if object:IsA("Tool")
            and (object:GetAttribute("ToolType") == "Gun"
                or object:GetAttribute("FireRate") ~= nil) then
            return object
        end
    end
    return nil
end

local function triggerBTarget()
    if not State.TriggerB then
        return nil, nil
    end

    camera = workspace.CurrentCamera
    if not camera then
        return nil, nil
    end

    local selected = State.SelectedMode
    if not isModeActive(selected) then
        return nil, nil
    end

    if selected == "Camlock" then
        local target = validTarget(camTarget) and camTarget or nil
        local part = target and getAimPart(target.Character, camera.ViewportSize / 2) or nil
        if target and part and (not State.WallCheck or partVisible(part)) then
            return target, part
        end
        return findTarget(camera.ViewportSize / 2, false)
    end

    local mousePosition = UserInputService:GetMouseLocation()
    if selected == "Mouselock" then
        local target = validTarget(mouseTarget) and mouseTarget or nil
        local part = target and getAimPart(target.Character, mousePosition) or nil
        if target and part and (not State.WallCheck or partVisible(part)) then
            return target, part
        end
        return findTarget(mousePosition, false)
    end

    if selected == "Silent" then
        return findTarget(mousePosition, State.WallB)
    end

    return nil, nil
end

local function releaseTriggerInput()
    if not triggerBPressed then
        return
    end
    triggerBPressed = false

    if type(triggerMouseRelease) == "function" then
        pcall(triggerMouseRelease)
        return
    end

    if triggerVirtualInput then
        local position = UserInputService:GetMouseLocation()
        pcall(function()
            triggerVirtualInput:SendMouseButtonEvent(
                math.floor(position.X),
                math.floor(position.Y),
                0,
                false,
                game,
                0
            )
        end)
    end
end

local function fireTriggerInput(gun)
    if type(triggerMouseClick) == "function" then
        pcall(triggerMouseClick)
        return
    end

    if type(triggerMousePress) == "function" and type(triggerMouseRelease) == "function" then
        triggerBPressed = true
        pcall(triggerMousePress)
        task.delay(0.012, function()
            if triggerBPressed then
                releaseTriggerInput()
            end
        end)
        return
    end

    if triggerVirtualInput then
        local position = UserInputService:GetMouseLocation()
        triggerBPressed = true
        pcall(function()
            triggerVirtualInput:SendMouseButtonEvent(
                math.floor(position.X),
                math.floor(position.Y),
                0,
                true,
                game,
                0
            )
        end)
        task.delay(0.012, function()
            if triggerBPressed then
                releaseTriggerInput()
            end
        end)
        return
    end

    if gun then
        pcall(function() gun:Activate() end)
        task.delay(0.012, function()
            if gun and gun.Parent then
                pcall(function() gun:Deactivate() end)
            end
        end)
    end
end

local function stopTriggerBGun()
    releaseTriggerInput()
    if triggerBLastGun and triggerBLastGun.Parent then
        pcall(function()
            triggerBLastGun:Deactivate()
        end)
    end
    triggerBLastGun = nil
end

setTriggerBEnabled = function(enabled)
    State.TriggerB = enabled == true
    triggerBLastShot = 0

    if triggerBConnection then
        triggerBConnection:Disconnect()
        triggerBConnection = nil
    end

    stopTriggerBGun()

    if not State.TriggerB then
        return
    end

    triggerBConnection = RunService.RenderStepped:Connect(function()
        if not runtimeAlive or not State.TriggerB then
            return
        end

        local targetPlayer, targetPart = triggerBTarget()
        if not targetPlayer or not targetPart then
            stopTriggerBGun()
            return
        end

        local gun = getEquippedTriggerGun()
        if not gun then
            stopTriggerBGun()
            return
        end

        local ammo = triggerBAmmo(gun)
        local reloadSession = gun:GetAttribute("Local_ReloadSession")
        if gun:GetAttribute("IsReloading") == true
            or (type(reloadSession) == "number" and reloadSession > 0)
            or (ammo ~= nil and ammo <= 0) then
            stopTriggerBGun()
            return
        end

        local fireRate = gun:GetAttribute("FireRate")
        if type(fireRate) ~= "number" or fireRate <= 0 then
            fireRate = 0.12
        end
        fireRate = math.clamp(fireRate, 0.03, 1)

        local now = os.clock()
        if now - triggerBLastShot < fireRate then
            return
        end

        triggerBLastShot = now
        triggerBLastGun = gun
        fireTriggerInput(gun)
    end)
end

triggerBCleanup = function()
    setTriggerBEnabled(false)
end
end

local mouseMoveRelative
pcall(function()
    mouseMoveRelative = environment.mousemoverel or mousemoverel
end)

local virtualInput
pcall(function()
    virtualInput = game:GetService("VirtualInputManager")
end)

local function moveMouse(dx, dy)
    if type(mouseMoveRelative) == "function" then
        pcall(mouseMoveRelative, dx, dy)
    elseif virtualInput then
        local current = UserInputService:GetMouseLocation()
        pcall(function()
            virtualInput:SendMouseMoveEvent(
                math.floor(current.X + dx),
                math.floor(current.Y + dy),
                game
            )
        end)
    end
end

local fovCircle = Instance.new("Frame")
fovCircle.Name = "FOVCircle"
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.BackgroundTransparency = 1
fovCircle.BorderSizePixel = 0
fovCircle.Visible = false
fovCircle.ZIndex = 1
fovCircle.Parent = priorityOverlayGui

local fovCircleCorner = Instance.new("UICorner")
fovCircleCorner.CornerRadius = UDim.new(1, 0)
fovCircleCorner.Parent = fovCircle

local fovCircleStroke = Instance.new("UIStroke")
fovCircleStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fovCircleStroke.Color = Color3.fromRGB(145, 174, 255)
fovCircleStroke.Thickness = 1
fovCircleStroke.Transparency = 0
fovCircleStroke.Parent = fovCircle

local function predictedPosition(part)
    if not part then
        return nil
    end
    local root = part.Parent and part.Parent:FindFirstChild("HumanoidRootPart")
    local velocity = root and root.AssemblyLinearVelocity or part.AssemblyLinearVelocity
    return part.Position + (velocity * State.Prediction)
end

local function rememberToggle(control)
    table.insert(toggleControls, control)
    return control
end

local function makeTitledSection(page, side, title)
    local section = page:Section({Side = side})
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "SectionTitle"
    titleLabel.Position = UDim2.fromOffset(10, 0)
    titleLabel.Size = UDim2.new(1, -20, 0, 26)
    titleLabel.BackgroundTransparency = 1
    titleLabel.BorderSizePixel = 0
    titleLabel.Font = Enum.Font.GothamMedium
    titleLabel.Text = title
    titleLabel.TextSize = 11
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextYAlignment = Enum.TextYAlignment.Center
    titleLabel.TextColor3 = SectionTitleColors[Consist:GetTheme()] or SectionTitleColors.Dark
    titleLabel.ZIndex = 7
    titleLabel.Parent = section.Frame

    local oldSectionStroke = section.Frame:FindFirstChild("ConsistSectionStroke")
        or section.Frame:FindFirstChildOfClass("UIStroke")
    if oldSectionStroke then
        oldSectionStroke.Enabled = false
    end

    local borderFrame = Instance.new("Frame")
    borderFrame.Name = "ConsistInnerSectionBorder"
    borderFrame.Position = UDim2.fromOffset(1, 1)
    borderFrame.Size = UDim2.new(1, -2, 1, -2)
    borderFrame.BackgroundTransparency = 1
    borderFrame.BorderSizePixel = 0
    borderFrame.Active = false
    borderFrame.ZIndex = 60
    borderFrame.Parent = section.Frame

    local sourceCorner = section.Frame:FindFirstChildOfClass("UICorner")
    local borderCorner = Instance.new("UICorner")
    borderCorner.CornerRadius = sourceCorner and sourceCorner.CornerRadius or UDim.new(0, 8)
    borderCorner.Parent = borderFrame

    local sectionStroke = Instance.new("UIStroke")
    sectionStroke.Name = "ConsistSectionStroke"
    sectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    sectionStroke.Thickness = 1
    sectionStroke.Transparency = 0
    sectionStroke.LineJoinMode = Enum.LineJoinMode.Round
    sectionStroke.Color = SectionStrokeColors[Consist:GetTheme()] or SectionStrokeColors.Dark
    sectionStroke.Parent = borderFrame

    section.ContentHeight = 26
    table.insert(sectionTitleLabels, titleLabel)
    table.insert(sectionStrokes, sectionStroke)
    return section
end

local lastSectionTitleTheme = Consist:GetTheme()
connect(RunService.Heartbeat, function()
    local currentTheme = Consist:GetTheme()
    if currentTheme == lastSectionTitleTheme then
        return
    end
    lastSectionTitleTheme = currentTheme
    local color = SectionTitleColors[currentTheme] or SectionTitleColors.Dark
    local strokeColor = SectionStrokeColors[currentTheme] or SectionStrokeColors.Dark
    for _, titleLabel in ipairs(sectionTitleLabels) do
        if titleLabel.Parent then
            titleLabel.TextColor3 = color
        end
    end
    for _, sectionStroke in ipairs(sectionStrokes) do
        if sectionStroke.Parent then
            sectionStroke.Color = strokeColor
            sectionStroke.Transparency = 0
        end
    end
    if compactModeDots and compactModeDots.Parent then
        compactModeDots.TextColor3 = color
    end
end)

do
local ModeSection = makeTitledSection(Combat, "Left", "Aim Type")
local setCombatModeLayout
ModeSection:Dropdown({
    Name = "Combat Type",
    Options = {"Camlock", "Mouselock", "Silent"},
    Default = State.SelectedMode,
    Callback = function(selected)
        if heldMode then
            State.ModeEnabled[heldMode] = false
            heldMode = nil
        end
        State.SelectedMode = selected
        clearTargets()
        if modeToggleControl then
            modeToggleControl:Set(State.ModeEnabled[selected], true)
        end
        if modeKeybindDisplay then
            modeKeybindDisplay:Set(State.ModeBinds[selected])
        end
        if setCombatModeLayout then
            setCombatModeLayout(selected)
        end
    end,
})

local modeBehaviorMenu = {
        {
            Name = "Toggle",
            Selected = function()
                return State.ModeBehavior[State.SelectedMode] == "Toggle"
            end,
            Action = function()
                if heldMode then
                    State.ModeEnabled[heldMode] = false
                end
                State.ModeBehavior[State.SelectedMode] = "Toggle"
                heldMode = nil
                clearTargets()
                if modeToggleControl then
                    modeToggleControl:Set(State.ModeEnabled[State.SelectedMode], true)
                end
            end,
        },
        {
            Name = "Hold",
            Selected = function()
                return State.ModeBehavior[State.SelectedMode] == "Hold"
            end,
            Action = function()
                local selectedMode = State.SelectedMode
                State.ModeBehavior[selectedMode] = "Hold"
                State.ModeEnabled[selectedMode] = false
                heldMode = nil
                clearTargets()
                if modeToggleControl then
                    modeToggleControl:Set(false, true)
                end
            end,
        },
}

modeToggleControl = ModeSection:Toggle({
    Name = "Toggle",
    Default = false,
    Menu = modeBehaviorMenu,
    Callback = function(value)
        State.ModeEnabled[State.SelectedMode] = value
        clearTargets()
    end,
})
rememberToggle(modeToggleControl)

local compactModeMenu
local compactModePalette = {
    Light = {
        Popup = Color3.fromRGB(243, 244, 247),
        Hover = Color3.fromRGB(233, 236, 241),
        Stroke = Color3.fromRGB(184, 189, 198),
        Text = Color3.fromRGB(79, 84, 93),
        Muted = Color3.fromRGB(132, 138, 148),
    },
    Dark = {
        Popup = Color3.fromRGB(23, 24, 28),
        Hover = Color3.fromRGB(34, 35, 41),
        Stroke = Color3.fromRGB(78, 81, 91),
        Text = Color3.fromRGB(205, 208, 214),
        Muted = Color3.fromRGB(141, 145, 154),
    },
    Black = {
        Popup = Color3.fromRGB(14, 15, 18),
        Hover = Color3.fromRGB(25, 26, 31),
        Stroke = Color3.fromRGB(68, 71, 81),
        Text = Color3.fromRGB(209, 212, 218),
        Muted = Color3.fromRGB(133, 137, 147),
    },
}

local function closeCompactModeMenu()
    if compactModeMenu then
        compactModeMenu:Destroy()
        compactModeMenu = nil
    end
end

local modeToggleRow = modeToggleControl.Instance.Parent
for _, child in ipairs(modeToggleRow:GetChildren()) do
    if child:IsA("TextButton") and child.Text ~= "" then
        compactModeDots = child:Clone()
        compactModeDots.Text = "..."
        compactModeDots.Parent = modeToggleRow
        child:Destroy()
        break
    end
end

assert(compactModeDots, "Consist toggle menu button was not found")
compactModeDots.Position = UDim2.fromOffset(198, 4)
compactModeDots.Size = UDim2.fromOffset(30, 24)
compactModeDots.TextSize = 12
compactModeDots.TextXAlignment = Enum.TextXAlignment.Center
compactModeDots.TextYAlignment = Enum.TextYAlignment.Center

compactModeDots.MouseButton1Click:Connect(function()
    if compactModeMenu then
        closeCompactModeMenu()
        return
    end

    local themeName = Consist:GetTheme()
    local palette = compactModePalette[themeName] or compactModePalette.Dark
    local menuWidth = 92
    local rowHeight = 17
    local menuHeight = 4 + (#modeBehaviorMenu * rowHeight)

    local menu = Instance.new("TextButton")
    menu.Name = "CompactModeMenu"
    menu.Size = UDim2.fromOffset(menuWidth, 0)
    menu.BackgroundColor3 = palette.Popup
    menu.BorderSizePixel = 0
    menu.Text = ""
    menu.AutoButtonColor = false
    menu.Active = true
    menu.ClipsDescendants = true
    menu.ZIndex = 1500
    local popupLayer = Consist.Gui:FindFirstChild("Overlay") or Consist.Gui
    menu.Parent = popupLayer

    local menuCorner = Instance.new("UICorner")
    menuCorner.CornerRadius = UDim.new(0, 6)
    menuCorner.Parent = menu

    local menuStroke = Instance.new("UIStroke")
    menuStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    menuStroke.Color = palette.Stroke
    menuStroke.Thickness = 1
    menuStroke.Transparency = 0
    menuStroke.Parent = menu

    local anchorPosition = compactModeDots.AbsolutePosition
    local layerPosition = popupLayer.AbsolutePosition
    local appPosition = Consist.App.AbsolutePosition
    local appSize = Consist.App.AbsoluteSize
    local appLeft = appPosition.X - layerPosition.X
    local appTop = appPosition.Y - layerPosition.Y
    local targetX = anchorPosition.X - layerPosition.X - menuWidth - 3
    local targetY = anchorPosition.Y - layerPosition.Y
    targetX = math.clamp(
        targetX,
        appLeft + 4,
        appLeft + appSize.X - menuWidth - 4
    )
    targetY = math.clamp(
        targetY,
        appTop + 4,
        appTop + appSize.Y - menuHeight - 4
    )
    menu.Position = UDim2.fromOffset(math.floor(targetX), math.floor(targetY))

    for index, item in ipairs(modeBehaviorMenu) do
        local selected = type(item.Selected) == "function" and item.Selected()
        local row = Instance.new("TextButton")
        row.Position = UDim2.fromOffset(2, 2 + (index - 1) * rowHeight)
        row.Size = UDim2.new(1, -4, 0, rowHeight)
        row.BackgroundColor3 = palette.Hover
        row.BackgroundTransparency = selected and 0 or 1
        row.BorderSizePixel = 0
        row.Text = ""
        row.AutoButtonColor = false
        row.ZIndex = 1501
        row.Parent = menu

        local rowCorner = Instance.new("UICorner")
        rowCorner.CornerRadius = UDim.new(0, 3)
        rowCorner.Parent = row

        local marker = Instance.new("Frame")
        marker.AnchorPoint = Vector2.new(0.5, 0.5)
        marker.Position = UDim2.new(0, 10, 0.5, 0)
        marker.Size = UDim2.fromOffset(2, 2)
        marker.BackgroundColor3 = selected and palette.Text or palette.Muted
        marker.BorderSizePixel = 0
        marker.ZIndex = 1502
        marker.Parent = row

        local markerCorner = Instance.new("UICorner")
        markerCorner.CornerRadius = UDim.new(1, 0)
        markerCorner.Parent = marker

        local rowLabel = Instance.new("TextLabel")
        rowLabel.Position = UDim2.fromOffset(18, 0)
        rowLabel.Size = UDim2.new(1, -22, 1, 0)
        rowLabel.BackgroundTransparency = 1
        rowLabel.BorderSizePixel = 0
        rowLabel.Font = Enum.Font.Gotham
        rowLabel.Text = item.Name
        rowLabel.TextColor3 = palette.Text
        rowLabel.TextSize = 8
        rowLabel.TextXAlignment = Enum.TextXAlignment.Left
        rowLabel.ZIndex = 1502
        rowLabel.Parent = row

        row.MouseEnter:Connect(function()
            row.BackgroundTransparency = 0
        end)
        row.MouseLeave:Connect(function()
            row.BackgroundTransparency = selected and 0 or 1
        end)
        row.MouseButton1Click:Connect(function()
            if type(item.Action) == "function" then
                item.Action()
            end
            closeCompactModeMenu()
        end)
    end

    compactModeMenu = menu
    TweenService:Create(
        menu,
        TweenInfo.new(0.10, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(menuWidth, menuHeight)}
    ):Play()
end)

connect(UserInputService.InputBegan, function(input)
    if not compactModeMenu
        or (input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch) then
        return
    end

    local point = input.Position
    local function contains(object)
        local position = object.AbsolutePosition
        local size = object.AbsoluteSize
        return point.X >= position.X
            and point.Y >= position.Y
            and point.X <= position.X + size.X
            and point.Y <= position.Y + size.Y
    end

    if contains(compactModeMenu) or contains(compactModeDots) then
        return
    end
    closeCompactModeMenu()
end)

local libraryKeybind = ModeSection:Keybind({
    Name = "Keybind",
    Default = State.ModeBinds.Camlock,
    ResetValue = function()
        return DefaultModeBinds[State.SelectedMode]
    end,
    Callback = function(value)
        local selectedMode = State.SelectedMode
        State.ModeBinds[selectedMode] = value
        if modeKeybindDisplay then
            task.defer(function()
                if runtimeAlive and modeKeybindDisplay then
                    modeKeybindDisplay:Set(value)
                end
            end)
        end
    end,
})

modeKeybindDisplay = installExternalKeybind(
    libraryKeybind,
    State.ModeBinds.Camlock,
    function(value)
        local selectedMode = State.SelectedMode
        State.ModeBinds[selectedMode] = value
    end
)

ModeSection:Slider({
    Name = "Prediction",
    Minimum = 0,
    Maximum = 0.20,
    Default = State.Prediction,
    Decimals = 3,
    Callback = function(value)
        State.Prediction = value
    end,
})

local smoothnessControl = ModeSection:Slider({
    Name = "Smoothness",
    Minimum = 1,
    Maximum = 10,
    Default = State.Smoothness,
    Decimals = 1,
    Callback = function(value)
        State.Smoothness = value
    end,
})

local FovSection = makeTitledSection(Combat, "Left", "FOV")
rememberToggle(FovSection:Toggle({
    Name = "FOV Circle",
    Default = false,
    Callback = function(value)
        State.FovEnabled = value
    end,
}))

rememberToggle(FovSection:Toggle({
    Name = "Aim Only",
    Default = false,
    Callback = function(value)
        State.FovAimOnly = value
    end,
}))

FovSection:Slider({
    Name = "FOV Size",
    Minimum = 25,
    Maximum = 600,
    Default = State.FovRadius,
    Callback = function(value)
        State.FovRadius = value
    end,
})

local CombatMiscSection = makeTitledSection(Combat, "Left", "Misc")
local semiAutomaticToggleControl = rememberToggle(CombatMiscSection:Toggle({
    Name = "Semi Automatic",
    Default = false,
    Callback = function(value)
        MovementFeatures.SetSemiAutomatic(value)
    end,
}))
MovementFeatures.SemiAutomaticToggleControl = semiAutomaticToggleControl

do
    local semiKeybindDisplay
    local semiKeybindControl = CombatMiscSection:Keybind({
        Name = "Keybind",
        Default = State.SemiAutomaticBind,
        ResetValue = function()
            return Enum.KeyCode.Unknown
        end,
        Callback = function(value)
            MovementFeatures.SetSemiAutomaticBind(value)
            if semiKeybindDisplay then
                task.defer(function()
                    if runtimeAlive and semiKeybindDisplay then
                        semiKeybindDisplay:Set(value)
                    end
                end)
            end
        end,
    })
    semiKeybindDisplay = installExternalKeybind(
        semiKeybindControl,
        State.SemiAutomaticBind,
        function(value)
            MovementFeatures.SetSemiAutomaticBind(value)
        end
    )
end

local normalModeHeight = ModeSection.ContentHeight
local normalFovY = FovSection.Y
local normalMiscY = CombatMiscSection.Y
setCombatModeLayout = function(selectedMode)
    local silent = selectedMode == "Silent"
    local removedHeight = silent and 44 or 0
    if not silent then
        smoothnessControl:SetVisible(true)
    end

    ModeSection.ContentHeight = normalModeHeight - removedHeight
    TweenService:Create(
        ModeSection.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, normalModeHeight - removedHeight)}
    ):Play()
    TweenService:Create(
        ModeSection.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, normalModeHeight - removedHeight)}
    ):Play()

    local fovY = normalFovY - removedHeight
    FovSection.Y = fovY
    TweenService:Create(
        FovSection.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(0, fovY)}
    ):Play()
    TweenService:Create(
        FovSection.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(0, fovY + 1)}
    ):Play()

    local miscY = normalMiscY - removedHeight
    CombatMiscSection.Y = miscY
    TweenService:Create(
        CombatMiscSection.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(0, miscY)}
    ):Play()
    TweenService:Create(
        CombatMiscSection.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(0, miscY + 1)}
    ):Play()

    local bottom = miscY + CombatMiscSection.ContentHeight + 10
    Combat.Layout.Left = bottom
    Combat.Frame.CanvasSize = UDim2.fromOffset(0, math.max(bottom, Combat.Layout.Right))

    if silent then
        task.delay(0.18, function()
            if runtimeAlive and State.SelectedMode == "Silent" then
                smoothnessControl:SetVisible(false)
            end
        end)
    end
end

local AimSection = makeTitledSection(Combat, "Right", "Aim Part")
AimSection:Dropdown({
    Name = "Aim Part",
    Options = {"Root", "Head", "Upper Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"},
    Default = "Root",
    Callback = function(value)
        local values = {
            Root = "HumanoidRootPart",
            Head = "Head",
            ["Upper Torso"] = "UpperTorso",
            ["Left Arm"] = "LeftArm",
            ["Right Arm"] = "RightArm",
            ["Left Leg"] = "LeftLeg",
            ["Right Leg"] = "RightLeg",
        }
        State.AimPart = values[value] or "HumanoidRootPart"
        clearTargets()
    end,
})

local setAdaptiveExpanded
local adaptiveToggleControl = rememberToggle(AimSection:Toggle({
    Name = "Adaptive Aim",
    Default = false,
    Callback = function(value)
        State.AdaptiveAim = value
        clearTargets()
        if setAdaptiveExpanded then
            setAdaptiveExpanded(value)
        end
    end,
}))

local adaptiveStrengthControl = AimSection:Slider({
    Name = "Adaptive Strength",
    Minimum = 0,
    Maximum = 100,
    Default = State.AdaptiveStrength,
    Suffix = "%",
    Callback = function(value)
        State.AdaptiveStrength = value
        table.clear(adaptivePartCache)
    end,
})

adaptiveStrengthControl:SetVisible(false)
local collapsedAimHeight = 106
local adaptiveSliderSeparator
for _, child in ipairs(AimSection.Frame:GetChildren()) do
    if child:IsA("Frame")
        and child.Size.Y.Offset == 1
        and child.Position.Y.Offset == collapsedAimHeight - 1 then
        adaptiveSliderSeparator = child
        break
    end
end
if adaptiveSliderSeparator then
    adaptiveSliderSeparator.Visible = false
end
AimSection.ContentHeight = collapsedAimHeight
AimSection.Frame.Size = UDim2.fromOffset(258, collapsedAimHeight)
AimSection.Shadow.Size = UDim2.fromOffset(258, collapsedAimHeight)
Combat.Layout.Right = AimSection.Y + collapsedAimHeight + 10

local WallBSection = makeTitledSection(Combat, "Right", "Essentials")
rememberToggle(WallBSection:Toggle({
    Name = "Wall Bang",
    Default = false,
    Callback = function(value)
        State.WallB = value
    end,
}))

rememberToggle(WallBSection:Toggle({
    Name = "Auto Swap",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAutoSwap(value)
    end,
}))

rememberToggle(WallBSection:Toggle({
    Name = "Trigger Bot",
    Default = false,
    Callback = function(value)
        setTriggerBEnabled(value)
    end,
}))

local setFastShootExpanded
local fastShootMinimum = 0.01
local fastShootMaximum = 0.20
local fastShootStockRate = 0.05
local fastShootCurrentRate = fastShootStockRate
local fastShootSliderControl
local fastShootSliderUpdate

rememberToggle(WallBSection:Toggle({
    Name = "Fast Shoot",
    Default = false,
    Callback = function(value)
        setFastShootEnabled(value)
        if setFastShootExpanded then
            setFastShootExpanded(value)
        end
    end,
}))

fastShootSliderControl = WallBSection:Slider({
    Name = "Fire Rate",
    Minimum = fastShootMinimum,
    Maximum = fastShootMaximum,
    Default = fastShootStockRate,
    Decimals = 3,
    Callback = function(value)
        local rate = math.clamp(value, fastShootMinimum, fastShootMaximum)
        rate = math.floor(rate * 1000 + 0.5) / 1000
        if math.abs(rate - fastShootStockRate) <= 0.006 then
            rate = fastShootStockRate
        end
        fastShootCurrentRate = rate
        State.FastShootRate = rate
        if fastShootSliderControl and math.abs(fastShootSliderControl:Get() - rate) > 0.0004 then
            fastShootSliderControl:Set(rate, true)
        end
        if fastShootSliderUpdate then
            fastShootSliderUpdate(rate)
        end
        if State.FastShoot then
            refreshFastShootGuns()
            local gun = getEquippedFastShootGun()
            if gun then
                pcall(function()
                    gun:Deactivate()
                end)
                applyFastShootGun(gun)
                task.defer(function()
                    if runtimeAlive and State.FastShoot and gun.Parent then
                        applyFastShootGun(gun)
                        if fastShootMouseHeld then
                            pcall(function()
                                gun:Activate()
                            end)
                        end
                    end
                end)
            end
        end
    end,
})

local fastShootSliderHolder = fastShootSliderControl.Instance
local fastShootTrack
local fastShootValueLabel
for _, child in ipairs(fastShootSliderHolder:GetChildren()) do
    if child:IsA("Frame")
        and child.Position.Y.Offset == 27
        and child.Size.Y.Offset == 3 then
        fastShootTrack = child
    elseif child:IsA("TextLabel") and child.AnchorPoint.X == 1 then
        fastShootValueLabel = child
    end
end

assert(fastShootTrack and fastShootValueLabel, "Consist fire-rate slider visuals were not found")

local fastShootFill
for _, child in ipairs(fastShootTrack:GetChildren()) do
    if child:IsA("Frame")
        and child.AnchorPoint.X == 0
        and child.Size.Y.Scale == 1 then
        fastShootFill = child
        break
    end
end
assert(fastShootFill, "Consist fire-rate slider fill was not found")

local stockRateAlpha = (fastShootStockRate - fastShootMinimum)
    / (fastShootMaximum - fastShootMinimum)
local stockRateMarker = Instance.new("Frame")
stockRateMarker.Name = "StockRateMarker"
stockRateMarker.AnchorPoint = Vector2.new(0.5, 0.5)
stockRateMarker.Position = UDim2.new(stockRateAlpha, 0, 0.5, 0)
stockRateMarker.Size = UDim2.fromOffset(2, 7)
stockRateMarker.BackgroundColor3 = fastShootTrack.BackgroundColor3
stockRateMarker.BorderSizePixel = 0
stockRateMarker.ZIndex = 6
stockRateMarker.Parent = fastShootTrack

local function fireRateColor(rate)
    local red = Color3.fromRGB(232, 70, 76)
    local yellow = Color3.fromRGB(235, 190, 68)
    local green = Color3.fromRGB(72, 198, 112)
    if rate < fastShootStockRate then
        local alpha = (rate - fastShootMinimum)
            / math.max(0.001, fastShootStockRate - fastShootMinimum)
        return red:Lerp(yellow, math.clamp(alpha, 0, 1))
    elseif rate > fastShootStockRate then
        return yellow:Lerp(
            green,
            math.clamp(
                (rate - fastShootStockRate)
                    / math.max(0.001, fastShootMaximum - fastShootStockRate),
                0,
                1
            )
        )
    end
    return yellow
end

local fastShootSliderColor = fireRateColor(fastShootCurrentRate)
fastShootSliderUpdate = function(rate)
    fastShootSliderColor = fireRateColor(rate)
    fastShootValueLabel.Text = rate < 0.1
        and string.format("%.3fs", rate)
        or string.format("%.2fs", rate)
    fastShootFill.BackgroundColor3 = fastShootSliderColor
end

fastShootSliderUpdate(fastShootCurrentRate)
connect(RunService.Heartbeat, function()
    if runtimeAlive and fastShootFill.Parent then
        fastShootFill.BackgroundColor3 = fastShootSliderColor
        stockRateMarker.BackgroundColor3 = fastShootTrack.BackgroundColor3
    end
end)

local expandedWallBHeight = WallBSection.ContentHeight
local fastShootSliderHeight = 44
local collapsedWallBHeight = expandedWallBHeight - fastShootSliderHeight
local fastShootSliderSeparator
for _, child in ipairs(WallBSection.Frame:GetChildren()) do
    if child:IsA("Frame")
        and child.Size.Y.Offset == 1
        and child.Position.Y.Offset == collapsedWallBHeight - 1 then
        fastShootSliderSeparator = child
        break
    end
end

fastShootSliderControl:SetVisible(false)
if fastShootSliderSeparator then
    fastShootSliderSeparator.Visible = false
end
WallBSection.ContentHeight = collapsedWallBHeight
WallBSection.Frame.Size = UDim2.fromOffset(258, collapsedWallBHeight)
WallBSection.Shadow.Size = UDim2.fromOffset(258, collapsedWallBHeight)
Combat.Layout.Right = WallBSection.Y + collapsedWallBHeight + 10

local ChecksSection = makeTitledSection(Combat, "Right", "Checks")
rememberToggle(ChecksSection:Toggle({
    Name = "Wall Check",
    Default = false,
    Callback = function(value)
        State.WallCheck = value
        clearTargets()
    end,
}))

rememberToggle(ChecksSection:Toggle({
    Name = "Dead Check",
    Default = true,
    Callback = function(value)
        State.DeadCheck = value
        clearTargets()
    end,
}))

rememberToggle(ChecksSection:Toggle({
    Name = "Team Check",
    Default = false,
    Callback = function(value)
        State.TeamCheck = value
        if value
            and LocalPlayer.Team
            and string.lower(LocalPlayer.Team.Name) ~= "neutral" then
            State.ExcludedTeams[LocalPlayer.Team.Name] = true
            local control = teamControls[LocalPlayer.Team]
            if control then
                control:Set(true, true)
            end
        end
        if wallBRefreshTeams then
            wallBRefreshTeams()
        end
        clearTargets()
    end,
}))

local function addTeam(team)
    if teamControls[team] then
        return
    end
    if string.lower(team.Name) == "neutral" then
        State.ExcludedTeams[team.Name] = true
        return
    end
    local isOwnTeam = State.TeamCheck and team == LocalPlayer.Team
    State.ExcludedTeams[team.Name] = isOwnTeam
    teamControls[team] = rememberToggle(ChecksSection:Toggle({
        Name = "  " .. team.Name,
        Default = isOwnTeam,
        Callback = function(value)
            State.ExcludedTeams[team.Name] = value
            if wallBRefreshTeams then
                wallBRefreshTeams()
            end
            clearTargets()
        end,
    }))
end

for _, team in ipairs(Teams:GetTeams()) do
    addTeam(team)
end

connect(Teams.ChildAdded, function(child)
    if child:IsA("Team") then
        addTeam(child)
    end
end)

connect(LocalPlayer:GetPropertyChangedSignal("Team"), function()
    if LocalPlayer.Team and string.lower(LocalPlayer.Team.Name) ~= "neutral" then
        addTeam(LocalPlayer.Team)
        if State.TeamCheck then
            State.ExcludedTeams[LocalPlayer.Team.Name] = true
            local control = teamControls[LocalPlayer.Team]
            if control then
                control:Set(true, true)
            end
        end
    end
    if wallBRefreshTeams then
        wallBRefreshTeams()
    end
    clearTargets()
end)

local baseWallBY = WallBSection.Y
local baseChecksY = ChecksSection.Y
local adaptiveLayoutExtra = 0
local fastShootLayoutExtra = 0

local function moveRightSection(section, targetY)
    section.Y = targetY
    TweenService:Create(
        section.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(270, targetY)}
    ):Play()
    TweenService:Create(
        section.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.fromOffset(270, targetY + 1)}
    ):Play()
end

local function refreshRightSectionLayout()
    moveRightSection(WallBSection, baseWallBY + adaptiveLayoutExtra)
    moveRightSection(
        ChecksSection,
        baseChecksY + adaptiveLayoutExtra + fastShootLayoutExtra
    )
    local bottom = ChecksSection.Y + ChecksSection.ContentHeight + 10
    Combat.Layout.Right = bottom
    Combat.Frame.CanvasSize = UDim2.fromOffset(0, math.max(Combat.Layout.Left, bottom))
end

setFastShootExpanded = function(expanded)
    fastShootLayoutExtra = expanded and fastShootSliderHeight or 0
    if expanded then
        fastShootSliderControl:SetVisible(true)
    end
    if fastShootSliderSeparator then
        fastShootSliderSeparator.Visible = expanded
    end

    local targetHeight = collapsedWallBHeight + fastShootLayoutExtra
    WallBSection.ContentHeight = targetHeight
    TweenService:Create(
        WallBSection.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, targetHeight)}
    ):Play()
    TweenService:Create(
        WallBSection.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, targetHeight)}
    ):Play()
    refreshRightSectionLayout()

    if not expanded then
        task.delay(0.18, function()
            if runtimeAlive and not State.FastShoot then
                fastShootSliderControl:SetVisible(false)
            end
        end)
    end
end

setAdaptiveExpanded = function(expanded)
    local extra = expanded and 44 or 0
    adaptiveLayoutExtra = extra
    if expanded then
        adaptiveStrengthControl:SetVisible(true)
    end
    if adaptiveSliderSeparator then
        adaptiveSliderSeparator.Visible = expanded
    end

    TweenService:Create(
        AimSection.Frame,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, collapsedAimHeight + extra)}
    ):Play()
    TweenService:Create(
        AimSection.Shadow,
        TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, collapsedAimHeight + extra)}
    ):Play()

    AimSection.ContentHeight = collapsedAimHeight + extra
    refreshRightSectionLayout()

    if not expanded then
        task.delay(0.18, function()
            if runtimeAlive and not State.AdaptiveAim then
                adaptiveStrengthControl:SetVisible(false)
            end
        end)
    end
end
end

connect(UserInputService.InputBegan, function(input, processed)
    if activeCapture then
        local selected = bindingFromInput(input)
        if selected then
            local capture = activeCapture
            activeCapture = nil
            State.CapturedBindingInput = input
            capture.Display:Set(selected)
            capture.Callback(selected)
            task.defer(function()
                if State.CapturedBindingInput == input then
                    State.CapturedBindingInput = nil
                end
            end)
        end
        return
    end

    if UserInputService:GetFocusedTextBox() then
        return
    end

    local selectedMode = State.SelectedMode
    if State.CapturedBindingInput ~= input
        and not inputIsOverApp(input)
        and inputMatches(input, State.ModeBinds[selectedMode]) then
        if State.ModeBehavior[selectedMode] == "Hold" then
            heldMode = selectedMode
            State.ModeEnabled[selectedMode] = true
        else
            State.ModeEnabled[selectedMode] = not State.ModeEnabled[selectedMode]
        end
        clearTargets()
        modeToggleControl:Set(State.ModeEnabled[selectedMode], true)
    end
end)

local accentRefreshToken = 0
local function refreshEnabledToggleColors()
    for _, control in ipairs(toggleControls) do
        if control and control.Instance and control.Instance.Parent then
            control:Set(control:Get(), true)
        end
    end
end

connect(UserInputService.InputEnded, function(input)
    if heldMode and inputMatches(input, State.ModeBinds[heldMode]) then
        State.ModeEnabled[heldMode] = false
        clearTargets()
        if State.SelectedMode == heldMode then
            modeToggleControl:Set(false, true)
        end
        heldMode = nil
    end

    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.MouseButton2
        and input.UserInputType ~= Enum.UserInputType.MouseButton3
        and input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end

    accentRefreshToken += 1
    local token = accentRefreshToken
    for _, delayTime in ipairs({0.06, 0.35, 0.75}) do
        task.delay(delayTime, function()
            if runtimeAlive and token == accentRefreshToken then
                refreshEnabledToggleColors()
            end
        end)
    end
end)

connect(RunService.RenderStepped, function()
    if not runtimeAlive then
        return
    end

    camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local mousePosition = UserInputService:GetMouseLocation()
    local screenCenter = camera.ViewportSize / 2
    local fovCenter = State.SelectedMode == "Camlock" and screenCenter or mousePosition

    if fovCircle then
        local diameter = State.FovRadius * 2
        fovCircle.Position = UDim2.fromOffset(fovCenter.X, fovCenter.Y)
        fovCircle.Size = UDim2.fromOffset(diameter, diameter)
        fovCircle.Visible = State.FovEnabled
            and (not State.FovAimOnly or isModeActive(State.SelectedMode))
    end

    if isModeActive("Camlock") then
        if not validTarget(camTarget) then
            camTarget = nil
        end

        local part
        if camTarget then
            part = getAimPart(camTarget.Character, screenCenter)
            if State.WallCheck and not partVisible(part) then
                camTarget = nil
                part = nil
            end
        end
        if not camTarget then
            camTarget, part = findTarget(screenCenter)
        end

        local predicted = predictedPosition(part)
        if predicted then
            camera.CFrame = camera.CFrame:Lerp(
                CFrame.new(camera.CFrame.Position, predicted),
                math.clamp(1 / math.max(State.Smoothness, 1), 0.01, 1)
            )
        end
    else
        camTarget = nil
    end

    if isModeActive("Mouselock") then
        if not validTarget(mouseTarget) then
            mouseTarget = nil
        end

        local part
        if mouseTarget then
            part = getAimPart(mouseTarget.Character, mousePosition)
            if State.WallCheck and not partVisible(part) then
                mouseTarget = nil
                part = nil
            end
        end
        if not mouseTarget then
            mouseTarget, part = findTarget(mousePosition)
        end

        local predicted = predictedPosition(part)
        if predicted then
            local point, onScreen = camera:WorldToViewportPoint(predicted)
            if onScreen and point.Z > 0 then
                local delta = Vector2.new(point.X, point.Y) - mousePosition
                if delta.Magnitude > 1 then
                    local step = delta / math.max(State.Smoothness, 1)
                    if step.Magnitude > 42 then
                        step = step.Unit * 42
                    end
                    moveMouse(step.X, step.Y)
                end
            end
        end
    else
        mouseTarget = nil
    end
end)

if false then
local ScanRadius = 6
local TargetExpand = 7.4
local HugDistance = 7.5
local OriginScanner = {Cache = {}}
local scanOffsets = {
    Vector3.new(0, 1, 0),
    Vector3.new(1, 0, 0),
    Vector3.new(0.7, -0.5, -0.5),
    Vector3.new(-0.1, -0.8, -0.8),
    Vector3.new(-0.8, -0.5, -0.5),
    Vector3.new(-1, 0, 0),
    Vector3.new(-0.8, 0.4, 0.4),
    Vector3.new(0, 0.7, 0.7),
    Vector3.new(0.7, 0.5, 0.5),
    Vector3.new(0.7, 0, -0.8),
    Vector3.new(-0.1, 0, -1),
    Vector3.new(-0.8, 0, -0.8),
    Vector3.new(-0.8, 0, 0.7),
    Vector3.new(0, 0, 1),
    Vector3.new(0.7, 0, 0.7),
    Vector3.new(0.7, 0.4, -0.5),
    Vector3.new(-0.1, 0.7, -0.8),
    Vector3.new(-1, -0.1, 0),
    Vector3.new(-0.8, -0.5, 0.4),
    Vector3.new(0, -0.8, 0.7),
    Vector3.new(0.7, -0.6, 0.5),
    Vector3.new(0, -1, 0),
}

local normalOffsets = {}
for _, normal in ipairs(Enum.NormalId:GetEnumItems()) do
    table.insert(normalOffsets, Vector3.fromNormalId(normal))
end

local bulletRayParams = RaycastParams.new()
local bulletOverlapParams = OverlapParams.new()
bulletRayParams.FilterType = Enum.RaycastFilterType.Exclude
bulletOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
pcall(function()
    bulletRayParams.CollisionGroup = "ClientBullet"
    bulletOverlapParams.CollisionGroup = "ClientBullet"
end)

local function updateBulletIgnore()
    local ignored = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(ignored, player.Character)
        end
    end
    bulletRayParams.FilterDescendantsInstances = ignored
    bulletOverlapParams.FilterDescendantsInstances = ignored
end

local function pointIsOpen(position)
    local parts = workspace:GetPartBoundsInRadius(position, 0, bulletOverlapParams)
    for _, part in ipairs(parts) do
        if part.CanCollide
            and (part:GetClosestPointOnSurface(position) - position).Magnitude <= 0.0001 then
            return false
        end
    end
    return true
end

function OriginScanner:Find(origin, target, extra, targetPart, targetCharacter)
    if self.Cache[targetPart] then
        return table.unpack(self.Cache[targetPart])
    end

    local targetPositions = {}
    if pointIsOpen(target) then
        if extra and (origin - extra).Magnitude < HugDistance then
            self.Cache[targetPart] = {extra}
            return extra
        end
        table.insert(targetPositions, target)
    end

    local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
    if targetRoot then
        for _, offset in ipairs(normalOffsets) do
            local position = targetRoot.Position + offset * TargetExpand
            if pointIsOpen(position) then
                table.insert(targetPositions, position)
            end
        end
        for _, offset in ipairs(scanOffsets) do
            local position = targetRoot.Position + offset * (TargetExpand * 0.5)
            if pointIsOpen(position) then
                table.insert(targetPositions, position)
            end
        end
    end

    local originPositions = {origin}
    for _, multiplier in ipairs({1, 1.75}) do
        for _, offset in ipairs(scanOffsets) do
            local position = origin + offset * (ScanRadius * multiplier)
            if pointIsOpen(position) then
                table.insert(originPositions, position)
            end
        end
    end

    for _, hitboxPosition in ipairs(targetPositions) do
        for _, originPosition in ipairs(originPositions) do
            local ray = workspace:Raycast(
                hitboxPosition,
                originPosition - hitboxPosition,
                bulletRayParams
            )
            if not ray then
                self.Cache[targetPart] = {originPosition, hitboxPosition}
                return originPosition, hitboxPosition
            end
        end
    end

    return nil, nil
end

connect(RunService.RenderStepped, function()
    table.clear(OriginScanner.Cache)
end)

local gunFunctions = {}
local oldBullet

local function findGunFunctions()
    if type(getconnections) ~= "function"
        or not debug
        or type(debug.getupvalue) ~= "function"
        or type(debug.info) ~= "function" then
        return
    end

    local home = LocalPlayer.PlayerGui:FindFirstChild("Home")
    local hud = home and home:FindFirstChild("hud")
    local actionArea = hud and hud:FindFirstChild("ActionArea")
    if actionArea then
        for _, connection in ipairs(getconnections(actionArea.InputBegan)) do
            if connection.Function then
                gunFunctions.Shoot = debug.getupvalue(connection.Function, 2)
                if gunFunctions.Shoot then
                    gunFunctions.Bullet = debug.getupvalue(gunFunctions.Shoot, 16)
                    if gunFunctions.Bullet then
                        break
                    end
                end
            end
        end
    end
end

local function silentBulletHook(...)
    if not oldBullet then
        return nil
    end
    if not runtimeAlive or not isModeActive("Silent") then
        return oldBullet(...)
    end

    local args = table.pack(...)
    local origin = args[1]
    if typeof(origin) ~= "Vector3" then
        return oldBullet(...)
    end

    local targetPlayer, targetPart = findTarget(
        UserInputService:GetMouseLocation(),
        State.WallB
    )
    if not targetPlayer or not targetPart then
        return oldBullet(...)
    end

    args[2] = predictedPosition(targetPart) or targetPart.Position

    if not State.WallB then
        return oldBullet(table.unpack(args, 1, args.n))
    end

    updateBulletIgnore()
    local reverseRay = workspace:Raycast(
        args[2],
        origin - args[2],
        bulletRayParams
    )
    local forwardRay = workspace:Raycast(
        origin,
        args[2] - origin,
        bulletRayParams
    )

    if OriginScanner.Cache[targetPart] or reverseRay or forwardRay then
        local localRoot = LocalPlayer.Character
            and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local newOrigin, hitPosition
        if localRoot then
            newOrigin, hitPosition = OriginScanner:Find(
                localRoot.Position,
                args[2],
                reverseRay and reverseRay.Position + reverseRay.Normal * 0.01 or nil,
                targetPart,
                targetPlayer.Character
            )
        end

        if newOrigin then
            if debug
                and type(debug.getstack) == "function"
                and type(debug.setstack) == "function" then
                pcall(function()
                    local stack = debug.getstack(3)
                    if stack then
                        for index, value in ipairs(stack) do
                            if value == origin then
                                debug.setstack(3, index, newOrigin)
                            end
                        end
                    end
                end)
            end
            args[1] = newOrigin
            if hitPosition then
                return targetPart, hitPosition
            end
        else
            return targetPart, targetPart.Position
        end
    end

    return oldBullet(table.unpack(args, 1, args.n))
end

-- Bullet redirection is installed once by the shared Silent/WallB hook below.
-- Keeping a single hook avoids WallB replacing normal Silent at runtime.
end

local basicSilentOldIndex
pcall(function()
    if type(hookmetamethod) == "function" and type(newcclosure) == "function" then
        basicSilentOldIndex = hookmetamethod(game, "__index", newcclosure(function(object, key)
            if runtimeAlive
                and isModeActive("Silent")
                and not State.WallB
                and object == mouse
                and (key == "Hit" or key == "Target") then
                local _, part = findTarget(UserInputService:GetMouseLocation())
                if part then
                    if key == "Target" then
                        return part
                    end
                    local predicted = predictedPosition(part)
                    if predicted then
                        return CFrame.new(predicted)
                    end
                end
            end
            return basicSilentOldIndex(object, key)
        end))
    end
end)

do
local SETTINGS = {
    Enabled = true,
    Mode = "Mouse",
    Range = 150,
    TargetPlayers = true,
    TargetNPCs = false,
    TeamCheck = false,
    ForceHit = true,
    DeepScan = true,
    ScanRadius = 6,
    TargetExpand = 7.4,
    HugDistance = 7.5,
}

local cloneref = cloneref or function(object)
    return object
end
local playersService = cloneref(game:GetService("Players"))
local inputService = cloneref(game:GetService("UserInputService"))
local runService = cloneref(game:GetService("RunService"))
local localPlayer = playersService.LocalPlayer
local gameCamera = workspace.CurrentCamera

local hookFunction = hookfunction
local getConnections = getconnections
local debugGetUpvalue = debug.getupvalue
local debugGetStack = debug.getstack
local debugSetStack = debug.setstack
local debugInfo = debug.info

local function getMousePosition()
    if inputService.TouchEnabled then
        return gameCamera.ViewportSize / 2
    end
    return inputService:GetMouseLocation()
end

local entitylib = {
    isAlive = false,
    character = {},
    List = {},
    Connections = {},
    PlayerConnections = {},
    EntityThreads = {},
    Running = false,
    Events = setmetatable({}, {
        __index = function(self, index)
            self[index] = {
                Connections = {},
                Connect = function(event, callback)
                    table.insert(event.Connections, callback)
                    return {
                        Disconnect = function()
                            local position = table.find(event.Connections, callback)
                            if position then
                                table.remove(event.Connections, position)
                            end
                        end,
                    }
                end,
                Fire = function(event, ...)
                    for _, callback in ipairs(event.Connections) do
                        task.spawn(callback, ...)
                    end
                end,
                Destroy = function(event)
                    table.clear(event.Connections)
                    table.clear(event)
                end,
            }
            return self[index]
        end,
    }),
}

local function loopClean(value)
    for index, entry in pairs(value) do
        if type(entry) == "table" then
            loopClean(entry)
        end
        value[index] = nil
    end
end

local function waitForChildOfType(object, name, timeout, property, nameCheck)
    local expires = timeout == math.huge and math.huge or (os.clock() + timeout)
    repeat
        local result
        if property then
            local ok, value = pcall(function()
                return object[name]
            end)
            if ok then
                result = value
            end
        else
            result = object:FindFirstChildOfClass(name)
        end
        if result and nameCheck and result.Name ~= nameCheck then
            result = nil
        end
        if result then
            return result
        end
        task.wait()
    until expires ~= math.huge and expires < os.clock()
    return nil
end

entitylib.getEntity = function(character)
    for index, entity in ipairs(entitylib.List) do
        if entity.Player == character or entity.Character == character then
            return entity, index
        end
    end
    return nil, nil
end

entitylib.addEntity = function(character, player, teamFunction, spawnTime)
    if not character then
        return
    end
    entitylib.EntityThreads[character] = task.spawn(function()
        local humanoid = waitForChildOfType(character, "Humanoid", 10)
        if not humanoid then
            return
        end
        local rootPart = waitForChildOfType(
            humanoid,
            "RootPart",
            workspace.StreamingEnabled and math.huge or 10,
            true,
            "HumanoidRootPart"
        )
        if not rootPart then
            return
        end
        local head = character:WaitForChild("Head", 10) or rootPart

        local entity = {
            Connections = {},
            Character = character,
            Health = humanoid.Health,
            Head = head,
            Humanoid = humanoid,
            HumanoidRootPart = rootPart,
            HipHeight = humanoid.HipHeight
                + (rootPart.Size.Y / 2)
                + (humanoid.RigType == Enum.HumanoidRigType.R6 and 2 or 0),
            MaxHealth = humanoid.MaxHealth,
            NPC = player == nil,
            Player = player,
            RootPart = rootPart,
            SpawnTime = spawnTime or 0,
            TeamCheck = teamFunction,
        }

        if player == localPlayer then
            entitylib.character = entity
            entitylib.isAlive = true
            entitylib.Events.LocalAdded:Fire(entity)
        else
            entity.Targetable = entitylib.targetCheck(entity)
            for _, signal in ipairs(entitylib.getUpdateConnections(entity)) do
                table.insert(entity.Connections, signal:Connect(function()
                    entity.Health = humanoid.Health
                    entity.MaxHealth = humanoid.MaxHealth
                    entitylib.Events.EntityUpdated:Fire(entity)
                end))
            end
            table.insert(entitylib.List, entity)
            entitylib.Events.EntityAdded:Fire(entity)
        end

        entitylib.EntityThreads[character] = nil
    end)
end

entitylib.removeEntity = function(character, isLocal)
    if isLocal then
        if entitylib.isAlive then
            entitylib.isAlive = false
            for _, connection in ipairs(entitylib.character.Connections) do
                connection:Disconnect()
            end
            table.clear(entitylib.character.Connections)
            entitylib.Events.LocalRemoved:Fire(entitylib.character)
        end
        return
    end

    if character then
        if entitylib.EntityThreads[character] then
            task.cancel(entitylib.EntityThreads[character])
            entitylib.EntityThreads[character] = nil
        end
        local entity, index = entitylib.getEntity(character)
        if index and entity then
            for _, connection in ipairs(entity.Connections) do
                connection:Disconnect()
            end
            table.clear(entity.Connections)
            table.remove(entitylib.List, index)
            entitylib.Events.EntityRemoved:Fire(entity)
        end
    end
end

entitylib.refreshEntity = function(character, player, spawnTime)
    local entity = entitylib.getEntity(player)
    entitylib.removeEntity(character)
    entitylib.addEntity(character, player, entity and entity.TeamCheck or nil, spawnTime)
end

entitylib.addPlayer = function(player)
    if player.Character then
        entitylib.refreshEntity(player.Character, player)
    end
    entitylib.PlayerConnections[player] = {
        player.CharacterAdded:Connect(function(character)
            entitylib.refreshEntity(character, player, os.clock() + 0.4)
        end),
        player.CharacterRemoving:Connect(function(character)
            entitylib.removeEntity(character, player == localPlayer)
        end),
        player:GetPropertyChangedSignal("Team"):Connect(function()
            if player == localPlayer then
                local cloned = table.clone(entitylib.List)
                for _, entity in ipairs(cloned) do
                    if entity.Targetable ~= entitylib.targetCheck(entity) then
                        entitylib.refreshEntity(entity.Character, entity.Player)
                    end
                end
                table.clear(cloned)
            else
                local entity = entitylib.getEntity(player)
                if entity then
                    entitylib.refreshEntity(entity.Character, player)
                end
            end
        end),
    }
end

entitylib.removePlayer = function(player)
    if entitylib.PlayerConnections[player] then
        for _, connection in ipairs(entitylib.PlayerConnections[player]) do
            connection:Disconnect()
        end
        table.clear(entitylib.PlayerConnections[player])
        entitylib.PlayerConnections[player] = nil
    end
    entitylib.removeEntity(player)
end

entitylib.start = function()
    if entitylib.Running then
        entitylib.stop()
    end
    entitylib.Connections = {
        playersService.PlayerAdded:Connect(function(player)
            entitylib.addPlayer(player)
        end),
        playersService.PlayerRemoving:Connect(function(player)
            entitylib.removePlayer(player)
        end),
        workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            gameCamera = workspace.CurrentCamera or workspace:FindFirstChildWhichIsA("Camera")
        end),
    }
    for _, player in ipairs(playersService:GetPlayers()) do
        entitylib.addPlayer(player)
    end
    entitylib.Running = true
end

entitylib.stop = function()
    for _, connection in ipairs(entitylib.Connections) do
        connection:Disconnect()
    end
    for _, playerConnections in pairs(entitylib.PlayerConnections) do
        for _, connection in ipairs(playerConnections) do
            connection:Disconnect()
        end
        table.clear(playerConnections)
    end
    entitylib.removeEntity(nil, true)
    local cloned = table.clone(entitylib.List)
    for _, entity in ipairs(cloned) do
        entitylib.removeEntity(entity.Character)
    end
    for _, thread in pairs(entitylib.EntityThreads) do
        task.cancel(thread)
    end
    table.clear(entitylib.PlayerConnections)
    table.clear(entitylib.EntityThreads)
    table.clear(entitylib.Connections)
    table.clear(cloned)
    entitylib.Running = false
end

entitylib.kill = function()
    if entitylib.Running then
        entitylib.stop()
    end
    for _, event in pairs(entitylib.Events) do
        event:Destroy()
    end
    loopClean(entitylib)
end

entitylib.refresh = function()
    local cloned = table.clone(entitylib.List)
    for _, entity in ipairs(cloned) do
        entitylib.refreshEntity(entity.Character, entity.Player)
    end
    table.clear(cloned)
end

entitylib.getUpdateConnections = function(entity)
    local humanoid = entity.Humanoid
    local signals = {
        humanoid:GetPropertyChangedSignal("Health"),
        humanoid:GetPropertyChangedSignal("MaxHealth"),
    }
    pcall(function()
        table.insert(signals, entity.Character:GetAttributeChangedSignal("Trespassing"))
        table.insert(signals, entity.Character:GetAttributeChangedSignal("Hostile"))
    end)
    if entity.Player then
        table.insert(signals, entity.Player:GetAttributeChangedSignal("InnocentKills"))
    end
    return signals
end

entitylib.targetCheck = function(entity)
    if entity.NPC then
        return true
    end
    if not SETTINGS.TeamCheck then
        return true
    end
    if not entity.Player or not entity.Player.Team then
        return true
    end
    return State.ExcludedTeams[entity.Player.Team.Name] ~= true
end

entitylib.isVulnerable = function(entity, attackCheck)
    if SETTINGS.TeamCheck
        and entity.Player
        and entity.Player.Team
        and State.ExcludedTeams[entity.Player.Team.Name] == true then
        return false
    end
    if attackCheck
        and localPlayer.Team
        and localPlayer.Team.Name == "Guards"
        and entity.Player
        and entity.Player.Team
        and entity.Player.Team.Name == "Inmates" then
        if not (
            entity.Character:GetAttribute("Hostile")
            or entity.Character:GetAttribute("Trespassing")
        ) then
            return false
        end
    end
    return entity.Health > 0
        and entity.Humanoid:GetState() ~= Enum.HumanoidStateType.Dead
        and entity.SpawnTime < os.clock()
        and not entity.Character:FindFirstChildWhichIsA("ForceField")
end

entitylib.EntityMouse = function(settings)
    if entitylib.isAlive then
        local mouseLocation = settings.MouseOrigin or getMousePosition()
        local localPosition = settings.Origin or entitylib.character.HumanoidRootPart.Position
        local sortedEntities = {}
        for _, entity in ipairs(entitylib.List) do
            if not settings.Players and entity.Player then
                continue
            end
            if not settings.NPCs and entity.NPC then
                continue
            end
            if not entity.Targetable then
                continue
            end
            if not entity[settings.Part] then
                continue
            end
            local position, visible = gameCamera:WorldToViewportPoint(entity[settings.Part].Position)
            if not visible then
                continue
            end
            local magnitude = (mouseLocation - Vector2.new(position.X, position.Y)).Magnitude
            if magnitude > settings.Range then
                continue
            end
            if entitylib.isVulnerable(entity, settings.AttackCheck) then
                if settings.RangePosition then
                    local worldMagnitude = (
                        entity[settings.Part].Position - localPosition
                    ).Magnitude
                    if worldMagnitude > settings.RangePosition then
                        continue
                    end
                end
                table.insert(sortedEntities, {
                    Entity = entity,
                    Magnitude = magnitude,
                })
            end
        end
        table.sort(sortedEntities, function(first, second)
            return first.Magnitude < second.Magnitude
        end)
        for _, sorted in ipairs(sortedEntities) do
            table.clear(settings)
            table.clear(sortedEntities)
            return sorted.Entity
        end
        table.clear(sortedEntities)
    end
    table.clear(settings)
    return nil
end

entitylib.EntityPosition = function(settings)
    if entitylib.isAlive then
        local localPosition = settings.Origin or entitylib.character.HumanoidRootPart.Position
        local sortedEntities = {}
        for _, entity in ipairs(entitylib.List) do
            if not settings.Players and entity.Player then
                continue
            end
            if not settings.NPCs and entity.NPC then
                continue
            end
            if not entity.Targetable then
                continue
            end
            if not entity[settings.Part] then
                continue
            end
            local magnitude = (entity[settings.Part].Position - localPosition).Magnitude
            if magnitude > settings.Range then
                continue
            end
            if entitylib.isVulnerable(entity, settings.AttackCheck) then
                table.insert(sortedEntities, {
                    Entity = entity,
                    Magnitude = magnitude,
                })
            end
        end
        table.sort(sortedEntities, function(first, second)
            return first.Magnitude < second.Magnitude
        end)
        for _, sorted in ipairs(sortedEntities) do
            table.clear(settings)
            table.clear(sortedEntities)
            return sorted.Entity
        end
        table.clear(sortedEntities)
    end
    table.clear(settings)
    return nil
end

local function pointIsClear(position, params)
    local parts = workspace:GetPartBoundsInRadius(position, 0, params)
    for _, part in ipairs(parts) do
        if part.CanCollide
            and (part:GetClosestPointOnSurface(position) - position).Magnitude <= 0.0001 then
            return false
        end
    end
    return true
end

local OriginScanner = {Cache = {}}
local scanPositions = {
    Vector3.new(0, 1, 0), Vector3.new(1, 0, 0),
    Vector3.new(0.7, -0.5, -0.5), Vector3.new(-0.1, -0.8, -0.8),
    Vector3.new(-0.8, -0.5, -0.5), Vector3.new(-1, 0, 0),
    Vector3.new(-0.8, 0.4, 0.4), Vector3.new(0, 0.7, 0.7),
    Vector3.new(0.7, 0.5, 0.5), Vector3.new(1, 0, 0),
    Vector3.new(0.7, 0, -0.8), Vector3.new(-0.1, 0, -1),
    Vector3.new(-0.8, 0, -0.8), Vector3.new(-1, 0, 0),
    Vector3.new(-0.8, 0, 0.7), Vector3.new(0, 0, 1),
    Vector3.new(0.7, 0, 0.7), Vector3.new(1, 0, 0),
    Vector3.new(0.7, 0.4, -0.5), Vector3.new(-0.1, 0.7, -0.8),
    Vector3.new(-0.8, 0.4, -0.5), Vector3.new(-1, -0.1, 0),
    Vector3.new(-0.8, -0.5, 0.4), Vector3.new(0, -0.8, 0.7),
    Vector3.new(0.7, -0.6, 0.5), Vector3.new(0, -1, 0),
}

local normalOffsets = {}
for _, normal in ipairs(Enum.NormalId:GetEnumItems()) do
    table.insert(normalOffsets, Vector3.fromNormalId(normal))
end

local rayParams = RaycastParams.new()
local overlapParams = OverlapParams.new()
rayParams.CollisionGroup = "ClientBullet"
rayParams.FilterType = Enum.RaycastFilterType.Exclude
overlapParams.CollisionGroup = "ClientBullet"
overlapParams.FilterType = Enum.RaycastFilterType.Exclude
OriginScanner.Ray = rayParams
OriginScanner.Overlap = overlapParams

function OriginScanner:Scan(origin, target, extra, part, entity)
    if self.Cache[part] then
        return table.unpack(self.Cache[part])
    end
    local hitboxPositions = {}
    if pointIsClear(target, overlapParams) then
        if extra and (origin - extra).Magnitude < SETTINGS.HugDistance then
            self.Cache[part] = {extra}
            return extra
        end
        table.insert(hitboxPositions, target)
    end
    local scanOrigins = {origin}

    if entity and entity.RootPart then
        local rootPosition = entity.RootPart.Position
        for _, offset in ipairs(normalOffsets) do
            local position = rootPosition + offset * SETTINGS.TargetExpand
            if pointIsClear(position, overlapParams) then
                table.insert(hitboxPositions, position)
            end
        end
        for _, offset in ipairs(scanPositions) do
            local position = rootPosition + offset * (SETTINGS.TargetExpand * 0.5)
            if pointIsClear(position, overlapParams) then
                table.insert(hitboxPositions, position)
            end
        end
    end

    for _, offset in ipairs(scanPositions) do
        local position = origin + offset * SETTINGS.ScanRadius
        if pointIsClear(position, overlapParams) then
            table.insert(scanOrigins, position)
        end
    end
    if SETTINGS.DeepScan then
        for _, offset in ipairs(scanPositions) do
            local position = origin + offset * (SETTINGS.ScanRadius * 1.75)
            if pointIsClear(position, overlapParams) then
                table.insert(scanOrigins, position)
            end
        end
    end

    for _, hitboxPosition in ipairs(hitboxPositions) do
        for _, scanOrigin in ipairs(scanOrigins) do
            local ray = workspace:Raycast(
                hitboxPosition,
                scanOrigin - hitboxPosition,
                rayParams
            )
            if not ray then
                self.Cache[part] = {scanOrigin, hitboxPosition}
                return scanOrigin, hitboxPosition
            end
        end
    end
    return nil, nil
end

function OriginScanner:UpdateIgnore()
    local ignored = {}
    if localPlayer.Character then
        table.insert(ignored, localPlayer.Character)
    end
    for _, entity in ipairs(entitylib.List) do
        if entity.Character then
            table.insert(ignored, entity.Character)
        end
    end
    rayParams.FilterDescendantsInstances = ignored
    overlapParams.FilterDescendantsInstances = ignored
end

local gun = {}
local oldBullet
local wallBCacheConnection

local function findGunInternals()
    local gui = localPlayer.PlayerGui:WaitForChild("Home", 10)
    if not gui then
        return
    end
    gui = gui:FindFirstChild("hud")
    if not gui then
        return
    end
    gui = gui:FindFirstChild("ActionArea")
    if not gui then
        return
    end

    for _, connection in ipairs(getConnections(gui.InputBegan)) do
        if connection.Function then
            gun.Shoot = debugGetUpvalue(connection.Function, 2)
            if gun.Shoot then
                gun.Reload = debugGetUpvalue(gun.Shoot, 2)
                gun.Bullet = debugGetUpvalue(gun.Shoot, 16)
                if gun.Reload then
                    gun.PlaySound = debugGetUpvalue(gun.Reload, 3)
                end
                break
            end
        end
    end

    for _, connection in ipairs(getConnections(localPlayer.CharacterAdded)) do
        if connection.Function and debugInfo(connection.Function, "s"):find("GunController") then
            gun.ShootParams = debugGetUpvalue(connection.Function, 2)
            gun.Equip = debugGetUpvalue(connection.Function, 3)
            break
        end
    end

    for _, connection in ipairs(
        getConnections(localPlayer:GetAttributeChangedSignal("BackpackEnabled"))
    ) do
        if connection.Function then
            local upvalueTen = debugGetUpvalue(connection.Function, 10)
            if upvalueTen then
                gun.SwitchUpdate = debugGetUpvalue(upvalueTen, 5)
            end
            local upvalueEight = debugGetUpvalue(connection.Function, 8)
            if upvalueEight then
                gun.SwitchTable = debugGetUpvalue(upvalueEight, 2)
            end
            break
        end
    end
end

local function findVictim(origin, limit)
    if not entitylib.isAlive or not entitylib.character.RootPart then
        return nil, nil
    end
    local entity = entitylib["Entity" .. SETTINGS.Mode]({
        Range = SETTINGS.Mode == "Position"
            and math.min(SETTINGS.Range, limit or 1000)
            or SETTINGS.Range,
        RangePosition = limit,
        Part = "Head",
        Origin = origin,
        Players = SETTINGS.TargetPlayers,
        NPCs = SETTINGS.TargetNPCs,
    })
    if entity and entity.Head then
        return entity, entity.Head
    end
    return nil, nil
end

local function wallBBulletHook(...)
    if not oldBullet then
        return nil
    end
    if not runtimeAlive or not isModeActive("Silent") then
        return oldBullet(...)
    end

    local args = table.pack(...)
    local origin = args[1]
    if typeof(origin) ~= "Vector3" then
        return oldBullet(...)
    end

    -- Normal Silent: redirect the shot to the selected aim part without
    -- enabling any of WallB's origin scanning / through-wall behavior.
    if not State.WallB then
        local _, targetPart = findTarget(UserInputService:GetMouseLocation(), false)
        if not targetPart then
            return oldBullet(...)
        end

        args[2] = predictedPosition(targetPart) or targetPart.Position
        return oldBullet(table.unpack(args, 1, args.n))
    end

    -- WallB keeps its stronger origin scanning path, but it now shares this
    -- same hook instead of replacing the normal Silent hook.
    SETTINGS.Range = State.FovRadius
    SETTINGS.TeamCheck = State.TeamCheck

    if not gun.Shoot then
        return oldBullet(...)
    end

    local gunData = debugGetUpvalue(gun.Shoot, 10)
    local entity, targetPart = findVictim(
        origin,
        gunData and gunData.Range or 1000
    )
    if not entity or not targetPart then
        return oldBullet(...)
    end

    args[2] = predictedPosition(targetPart) or targetPart.Position

    if SETTINGS.Enabled and entitylib.isAlive and entitylib.character.RootPart then
        local reverseRay
        if not OriginScanner.Cache[targetPart] then
            reverseRay = workspace:Raycast(
                args[2],
                origin - args[2],
                OriginScanner.Ray
            )
        end

        if OriginScanner.Cache[targetPart]
            or reverseRay
            or workspace:Raycast(origin, args[2] - origin, OriginScanner.Ray) then
            local newOrigin, hit = OriginScanner:Scan(
                entitylib.character.RootPart.Position,
                args[2],
                reverseRay and reverseRay.Position + reverseRay.Normal * 0.01 or nil,
                targetPart,
                entity
            )

            if newOrigin then
                local stackLevel = 3
                local stack = debugGetStack(stackLevel)
                if stack then
                    for index, value in ipairs(stack) do
                        if value == origin then
                            debugSetStack(stackLevel, index, newOrigin)
                        end
                    end
                end
                args[1] = newOrigin
                if hit then
                    return targetPart, hit
                end
            elseif SETTINGS.ForceHit then
                return targetPart, targetPart.Position
            end
        end
    end

    return oldBullet(table.unpack(args, 1, args.n))
end

entitylib.start()

task.spawn(function()
    findGunInternals()
    local attempts = 0
    while runtimeAlive and not gun.Bullet and attempts < 60 do
        task.wait(0.5)
        findGunInternals()
        attempts += 1
    end

    if not runtimeAlive or not gun.Bullet then
        return
    end

    OriginScanner:UpdateIgnore()
    for _, eventName in ipairs({"EntityAdded", "LocalAdded"}) do
        entitylib.Events[eventName]:Connect(function()
            OriginScanner:UpdateIgnore()
        end)
    end

    wallBCacheConnection = runService.RenderStepped:Connect(function()
        table.clear(OriginScanner.Cache)
    end)

    oldBullet = hookFunction(gun.Bullet, wallBBulletHook)
end)

wallBCleanup = function()
    if wallBCacheConnection then
        wallBCacheConnection:Disconnect()
        wallBCacheConnection = nil
    end
    if entitylib.Running then
        entitylib.stop()
    end
end

wallBRefreshTeams = function()
    SETTINGS.TeamCheck = State.TeamCheck
    if entitylib.Running then
        entitylib.refresh()
    end
end
end

do
local ESP = {
    BoxMasterEnabled = false,
    BoxType = "2D",
    BoxEnabled = false,
    CornerBoxEnabled = false,
    BoxFillEnabled = false,
    TeamCheckEnabled = false,
    TeamColorEnabled = false,
    NameEnabled = false,
    DisplayNameEnabled = false,
    ItemEnabled = false,
    HostileEnabled = false,
    ForcefieldEnabled = false,
    TeamIndicatorEnabled = false,
    ThreeDBoxEnabled = false,
    TracersEnabled = false,
    TracerType = "Body",
    DistanceEnabled = false,
    HealthBarEnabled = false,
    HealthTextEnabled = false,
    BoxColor = Color3.fromRGB(255, 255, 255),
    BoxFillColor = Color3.fromRGB(255, 255, 255),
    TextColor = Color3.fromRGB(255, 255, 255),
    TracerColor = Color3.fromRGB(255, 255, 255),
    Drawings = {},
}

do
local edges3D = {
    {1, 2}, {2, 4}, {4, 3}, {3, 1},
    {5, 6}, {6, 8}, {8, 7}, {7, 5},
    {1, 5}, {2, 6}, {3, 7}, {4, 8},
}

local espFont = Enum.Font.RobotoMono

local espGui = priorityOverlayGui

local espRoot = Instance.new("Frame")
espRoot.Name = "Drawings"
espRoot.Size = UDim2.fromScale(1, 1)
espRoot.BackgroundTransparency = 1
espRoot.BorderSizePixel = 0
espRoot.ZIndex = 1
espRoot.Parent = espGui

local function guiTransparency(value)
    return 1 - math.clamp(tonumber(value) or 1, 0, 1)
end

local function newDrawing(drawingType, properties)
    local state = {}
    local object
    local outline

    if drawingType == "Text" then
        object = Instance.new("TextLabel")
        object.AutomaticSize = Enum.AutomaticSize.XY
        object.Size = UDim2.fromOffset(0, 0)
        object.AnchorPoint = Vector2.new(0.5, 0.5)
        object.BackgroundTransparency = 1
        object.BorderSizePixel = 0
        object.Font = espFont
        pcall(function()
            object.FontFace = Font.new(
                Font.fromEnum(espFont).Family,
                Enum.FontWeight.SemiBold,
                Enum.FontStyle.Normal
            )
        end)
        object.TextWrapped = false
        object.RichText = false
    else
        object = Instance.new("Frame")
        object.BorderSizePixel = 0
        if drawingType == "Line" then
            object.AnchorPoint = Vector2.new(0.5, 0.5)
        else
            outline = Instance.new("UIStroke")
            outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            outline.Parent = object
        end
    end

    object.Name = drawingType
    object.Visible = false
    object.ZIndex = 1
    object.Parent = espRoot

    local function refreshLineGeometry()
        local from = state.From or Vector2.zero
        local to = state.To or from
        local delta = to - from
        local midpoint = from + delta * 0.5
        object.Position = UDim2.fromOffset(midpoint.X, midpoint.Y)
        object.Size = UDim2.fromOffset(delta.Magnitude, state.Thickness or 1)
        object.Rotation = math.deg(math.atan2(delta.Y, delta.X))
    end

    local function refreshTextStroke()
        object.TextStrokeTransparency = state.Outline == true
            and math.clamp(guiTransparency(state.Transparency) + 0.15, 0, 1)
            or 1
    end

    local function refreshAll()
        if drawingType == "Line" then
            refreshLineGeometry()
            object.BackgroundColor3 = state.Color or Color3.new(1, 1, 1)
            object.BackgroundTransparency = guiTransparency(state.Transparency)
        elseif drawingType == "Square" then
            local position = state.Position or Vector2.zero
            local size = typeof(state.Size) == "Vector2" and state.Size or Vector2.zero
            local filled = state.Filled == true
            object.Position = UDim2.fromOffset(position.X, position.Y)
            object.Size = UDim2.fromOffset(math.max(0, size.X), math.max(0, size.Y))
            object.BackgroundColor3 = state.Color or Color3.new(1, 1, 1)
            object.BackgroundTransparency = filled and guiTransparency(state.Transparency) or 1
            outline.Enabled = not filled
            outline.Color = state.Color or Color3.new(1, 1, 1)
            outline.Thickness = state.Thickness or 1
            outline.Transparency = guiTransparency(state.Transparency)
        else
            local position = state.Position or Vector2.zero
            object.AnchorPoint = state.Center == false and Vector2.zero or Vector2.new(0.5, 0.5)
            object.Position = UDim2.fromOffset(position.X, position.Y)
            object.Text = tostring(state.Text or "")
            object.TextSize = tonumber(state.Size) or 13
            object.TextColor3 = state.Color or Color3.new(1, 1, 1)
            object.TextTransparency = guiTransparency(state.Transparency)
            object.TextStrokeColor3 = state.OutlineColor or Color3.new()
            refreshTextStroke()
        end
        object.Visible = state.Visible == true
        object.ZIndex = math.max(1, tonumber(state.ZIndex) or 1)
    end

    local function applyProperty(key)
        if drawingType == "Line" then
            if key == "From" or key == "To" or key == "Thickness" then
                refreshLineGeometry()
            elseif key == "Color" then
                object.BackgroundColor3 = state.Color or Color3.new(1, 1, 1)
            elseif key == "Transparency" then
                object.BackgroundTransparency = guiTransparency(state.Transparency)
            elseif key == "Visible" then
                object.Visible = state.Visible == true
            elseif key == "ZIndex" then
                object.ZIndex = math.max(1, tonumber(state.ZIndex) or 1)
            end
            return
        end

        if drawingType == "Square" then
            if key == "Position" then
                local position = state.Position or Vector2.zero
                object.Position = UDim2.fromOffset(position.X, position.Y)
            elseif key == "Size" then
                local size = typeof(state.Size) == "Vector2" and state.Size or Vector2.zero
                object.Size = UDim2.fromOffset(math.max(0, size.X), math.max(0, size.Y))
            elseif key == "Color" then
                local color = state.Color or Color3.new(1, 1, 1)
                object.BackgroundColor3 = color
                outline.Color = color
            elseif key == "Filled" then
                local filled = state.Filled == true
                object.BackgroundTransparency = filled and guiTransparency(state.Transparency) or 1
                outline.Enabled = not filled
            elseif key == "Transparency" then
                local transparency = guiTransparency(state.Transparency)
                object.BackgroundTransparency = state.Filled == true and transparency or 1
                outline.Transparency = transparency
            elseif key == "Thickness" then
                outline.Thickness = state.Thickness or 1
            elseif key == "Visible" then
                object.Visible = state.Visible == true
            elseif key == "ZIndex" then
                object.ZIndex = math.max(1, tonumber(state.ZIndex) or 1)
            end
            return
        end

        if key == "Position" then
            local position = state.Position or Vector2.zero
            object.Position = UDim2.fromOffset(position.X, position.Y)
        elseif key == "Center" then
            object.AnchorPoint = state.Center == false and Vector2.zero or Vector2.new(0.5, 0.5)
        elseif key == "Text" then
            object.Text = tostring(state.Text or "")
        elseif key == "Size" then
            object.TextSize = tonumber(state.Size) or 13
        elseif key == "Color" then
            object.TextColor3 = state.Color or Color3.new(1, 1, 1)
        elseif key == "Transparency" then
            object.TextTransparency = guiTransparency(state.Transparency)
            refreshTextStroke()
        elseif key == "Outline" then
            refreshTextStroke()
        elseif key == "OutlineColor" then
            object.TextStrokeColor3 = state.OutlineColor or Color3.new()
        elseif key == "Visible" then
            object.Visible = state.Visible == true
        elseif key == "ZIndex" then
            object.ZIndex = math.max(1, tonumber(state.ZIndex) or 1)
        end
    end

    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == "_GuiDrawing" then
                return true
            elseif key == "Instance" then
                return object
            elseif key == "TextBounds" and drawingType == "Text" then
                return object and object.TextBounds or Vector2.zero
            elseif key == "Remove" then
                return function()
                    if object then
                        object:Destroy()
                        object = nil
                    end
                end
            end
            return state[key]
        end,
        __newindex = function(_, key, value)
            if state[key] == value then
                return
            end
            state[key] = value
            if object then
                applyProperty(key)
            end
        end,
    })

    for property, value in pairs(properties or {}) do
        state[property] = value
    end
    state.Visible = false
    refreshAll()
    return proxy
end

local healthFull = Color3.fromRGB(55, 255, 90)
local healthYellow = Color3.fromRGB(190, 255, 55)
local healthOrange = Color3.fromRGB(255, 175, 45)
local healthRed = Color3.fromRGB(255, 65, 65)

local function lerpColor(first, second, alpha)
    return Color3.new(
        first.R + (second.R - first.R) * alpha,
        first.G + (second.G - first.G) * alpha,
        first.B + (second.B - first.B) * alpha
    )
end

local function healthColor(alpha)
    if alpha >= 0.70 then
        return lerpColor(healthYellow, healthFull, (alpha - 0.70) / 0.30)
    elseif alpha >= 0.65 then
        return healthYellow
    elseif alpha >= 0.50 then
        return lerpColor(healthOrange, healthYellow, (alpha - 0.50) / 0.15)
    elseif alpha >= 0.45 then
        return healthOrange
    elseif alpha >= 0.15 then
        return lerpColor(healthRed, healthOrange, (alpha - 0.15) / 0.30)
    end
    return healthRed
end

local function createESPDrawings()
    local set = {
        Box = newDrawing("Square", {
            Color = ESP.BoxColor,
            Thickness = 1.5,
            Filled = false,
            Transparency = 1,
        }),
        BoxOutline = newDrawing("Square", {
            Color = Color3.new(),
            Thickness = 1.5,
            Filled = false,
            Transparency = 0.5,
        }),
        BoxFill = newDrawing("Square", {
            Color = ESP.BoxFillColor,
            Thickness = 1,
            Filled = true,
            Transparency = 0.6,
        }),
        NameText = newDrawing("Text", {
            Color = ESP.TextColor,
            Size = 14,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        HostileText = newDrawing("Text", {
            Color = healthRed,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        ForcefieldText = newDrawing("Text", {
            Color = healthOrange,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        ItemText = newDrawing("Text", {
            Color = ESP.TextColor,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        TeamText = newDrawing("Text", {
            Color = ESP.TextColor,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        DistanceText = newDrawing("Text", {
            Color = ESP.TextColor,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        HealthBarOutline = newDrawing("Square", {
            Color = Color3.new(),
            Thickness = 1,
            Filled = true,
            Transparency = 1,
        }),
        HealthBarBack = newDrawing("Square", {
            Color = Color3.new(),
            Thickness = 1,
            Filled = true,
            Transparency = 1,
        }),
        HealthBarFill = newDrawing("Square", {
            Color = healthFull,
            Thickness = 1,
            Filled = true,
            Transparency = 1,
        }),
        HealthText = newDrawing("Text", {
            Color = ESP.TextColor,
            Size = 13,
            Center = true,
            Outline = true,
            OutlineColor = Color3.new(),
            Font = espFont,
            Transparency = 1,
        }),
        BodyTracer = newDrawing("Line", {
            Color = ESP.TracerColor,
            Thickness = 1.5,
            Transparency = 1,
        }),
        TracerMouse = newDrawing("Line", {
            Color = ESP.TracerColor,
            Thickness = 1.5,
            Transparency = 1,
        }),
        TracerTop = newDrawing("Line", {
            Color = ESP.TracerColor,
            Thickness = 1.5,
            Transparency = 1,
        }),
        TracerBottom = newDrawing("Line", {
            Color = ESP.TracerColor,
            Thickness = 1.5,
            Transparency = 1,
        }),
        ThreeDLines = {},
        ThreeDOutlines = {},
        CornerLines = {},
        CornerOutlines = {},
    }

    for index = 1, 12 do
        set.ThreeDOutlines[index] = newDrawing("Line", {
            Color = Color3.new(),
            Thickness = 1.5,
            Transparency = 0.5,
        })
        set.ThreeDLines[index] = newDrawing("Line", {
            Color = ESP.BoxColor,
            Thickness = 1.2,
            Transparency = 1,
        })
    end
    for index = 1, 8 do
        set.CornerOutlines[index] = newDrawing("Line", {
            Color = Color3.new(),
            Thickness = 3,
            Transparency = 0.5,
        })
        set.CornerLines[index] = newDrawing("Line", {
            Color = ESP.BoxColor,
            Thickness = 1.5,
            Transparency = 1,
        })
    end
    return set
end

local function hideESPDrawings(set)
    for _, name in ipairs({
        "Box", "BoxOutline", "BoxFill", "NameText", "HostileText",
        "ForcefieldText", "ItemText", "TeamText", "DistanceText",
        "HealthBarOutline", "HealthBarBack", "HealthBarFill", "HealthText",
        "BodyTracer", "TracerMouse", "TracerTop", "TracerBottom",
    }) do
        set[name].Visible = false
    end
    for _, groupName in ipairs({
        "ThreeDLines", "ThreeDOutlines", "CornerLines",
        "CornerOutlines",
    }) do
        for _, drawing in ipairs(set[groupName]) do
            drawing.Visible = false
        end
    end
end

function ESP:Unload()
    for _, set in pairs(self.Drawings) do
        hideESPDrawings(set)
        for _, drawing in pairs(set) do
            if typeof(drawing) == "table" and drawing._GuiDrawing then
                drawing:Remove()
            elseif typeof(drawing) == "table" then
                for _, nested in ipairs(drawing) do
                    nested:Remove()
                end
            else
                drawing:Remove()
            end
        end
    end
    table.clear(self.Drawings)
    if espGui then
        espGui:Destroy()
    end
end

local function characterBounds(character)
    local minimum
    local maximum

    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") then
            local half = part.Size * 0.5
            local cframe = part.CFrame
            local right = cframe.RightVector
            local up = cframe.UpVector
            local look = cframe.LookVector

            local extentX = math.abs(right.X) * half.X
                + math.abs(up.X) * half.Y
                + math.abs(look.X) * half.Z
            local extentY = math.abs(right.Y) * half.X
                + math.abs(up.Y) * half.Y
                + math.abs(look.Y) * half.Z
            local extentZ = math.abs(right.Z) * half.X
                + math.abs(up.Z) * half.Y
                + math.abs(look.Z) * half.Z

            local position = part.Position
            local partMinimum = Vector3.new(
                position.X - extentX,
                position.Y - extentY,
                position.Z - extentZ
            )
            local partMaximum = Vector3.new(
                position.X + extentX,
                position.Y + extentY,
                position.Z + extentZ
            )

            if minimum then
                minimum = Vector3.new(
                    math.min(minimum.X, partMinimum.X),
                    math.min(minimum.Y, partMinimum.Y),
                    math.min(minimum.Z, partMinimum.Z)
                )
                maximum = Vector3.new(
                    math.max(maximum.X, partMaximum.X),
                    math.max(maximum.Y, partMaximum.Y),
                    math.max(maximum.Z, partMaximum.Z)
                )
            else
                minimum = partMinimum
                maximum = partMaximum
            end
        end
    end

    return minimum, maximum
end

local function worldToScreen(position)
    local point, onScreen = camera:WorldToViewportPoint(position)
    return Vector2.new(point.X, point.Y), onScreen
end

local function screenBounds(worldCorners, need3D)
    local cameraCFrame = camera.CFrame
    local cameraPosition = cameraCFrame.Position
    local cameraLook = cameraCFrame.LookVector
    local nearPlane = 0.5
    local minimum
    local maximum
    local cornerPoints = need3D and table.create(8) or nil
    local cornerInFront = need3D and table.create(8) or nil
    local frontCount = 0

    local function includePoint(point)
        if minimum then
            minimum = Vector2.new(
                math.min(minimum.X, point.X),
                math.min(minimum.Y, point.Y)
            )
            maximum = Vector2.new(
                math.max(maximum.X, point.X),
                math.max(maximum.Y, point.Y)
            )
        else
            minimum = point
            maximum = point
        end
    end

    for index = 1, 8 do
        local corner = worldCorners[index]
        local inFront = (corner - cameraPosition):Dot(cameraLook) >= nearPlane
        if need3D then
            cornerInFront[index] = inFront
        end
        if inFront then
            frontCount += 1
            local point = worldToScreen(corner)
            if need3D then
                cornerPoints[index] = point
            end
            includePoint(point)
        end
    end

    if frontCount > 0 and frontCount < 8 then
        for _, edge in ipairs(edges3D) do
            local first = worldCorners[edge[1]]
            local second = worldCorners[edge[2]]
            local firstDepth = (first - cameraPosition):Dot(cameraLook) - nearPlane
            local secondDepth = (second - cameraPosition):Dot(cameraLook) - nearPlane
            if (firstDepth >= 0) ~= (secondDepth >= 0) then
                local denominator = firstDepth - secondDepth
                if math.abs(denominator) > 0.000001 then
                    local alpha = firstDepth / denominator
                    includePoint(worldToScreen(first + (second - first) * alpha))
                end
            end
        end
    end

    return minimum, maximum, cornerPoints, cornerInFront
end

local function update3DBox(set, corners, inFront, color)
    for index, edge in ipairs(edges3D) do
        local visible = inFront[edge[1]]
            and inFront[edge[2]]
            and corners[edge[1]]
            and corners[edge[2]]
        local line = set.ThreeDLines[index]
        local outline = set.ThreeDOutlines[index]
        if visible then
            line.From = corners[edge[1]]
            line.To = corners[edge[2]]
            line.Color = color
            line.Visible = true
            outline.From = line.From
            outline.To = line.To
            outline.Visible = true
        else
            line.Visible = false
            outline.Visible = false
        end
    end
end

local function updateCornerBox(set, minimum, maximum, color)
    local width = maximum.X - minimum.X
    local height = maximum.Y - minimum.Y
    local length = math.max(2, math.min(width, height) * 0.25)
    local topLeft = minimum
    local topRight = Vector2.new(maximum.X, minimum.Y)
    local bottomLeft = Vector2.new(minimum.X, maximum.Y)
    local bottomRight = maximum

    local function setLine(index, from, to)
        local line = set.CornerLines[index]
        local outline = set.CornerOutlines[index]
        line.From = from
        line.To = to
        line.Color = color
        line.Visible = true
        outline.From = from
        outline.To = to
        outline.Visible = true
    end

    setLine(1, topLeft, topLeft + Vector2.new(length, 0))
    setLine(2, topLeft, topLeft + Vector2.new(0, length))
    setLine(3, topRight, topRight - Vector2.new(length, 0))
    setLine(4, topRight, topRight + Vector2.new(0, length))
    setLine(5, bottomLeft, bottomLeft + Vector2.new(length, 0))
    setLine(6, bottomLeft, bottomLeft - Vector2.new(0, length))
    setLine(7, bottomRight, bottomRight - Vector2.new(length, 0))
    setLine(8, bottomRight, bottomRight - Vector2.new(0, length))
end

local espPlayers = {}
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        table.insert(espPlayers, player)
    end
end

connect(Players.PlayerAdded, function(player)
    if player ~= LocalPlayer then
        table.insert(espPlayers, player)
    end
end)

local espItemCache = setmetatable({}, {__mode = "k"})

local function getCharacterItems(character, now)
    local cached = espItemCache[character]
    if cached and now - cached.Time < 0.20 then
        return cached.Text
    end

    local itemCount = 0
    local itemNames = table.create(2)
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            itemCount += 1
            itemNames[itemCount] = child.Name
        end
    end

    local textValue = itemCount > 0 and table.concat(itemNames, ", ") or nil
    espItemCache[character] = {
        Time = now,
        Text = textValue,
    }
    return textValue
end

local namePulseFrom = Color3.fromRGB(255, 255, 255)
local namePulseTo = Color3.fromRGB(170, 0, 255)
local espHadActiveFeature = false

local function hidePlayerESP(player)
    local set = ESP.Drawings[player]
    if set then
        hideESPDrawings(set)
    end
end

connect(RunService.RenderStepped, function()
    if not runtimeAlive then
        return
    end

    local anyFeature = ESP.BoxEnabled
        or ESP.CornerBoxEnabled
        or ESP.BoxFillEnabled
        or ESP.NameEnabled
        or ESP.DisplayNameEnabled
        or ESP.ItemEnabled
        or ESP.HostileEnabled
        or ESP.ForcefieldEnabled
        or ESP.TeamIndicatorEnabled
        or ESP.ThreeDBoxEnabled
        or ESP.TracersEnabled
        or ESP.DistanceEnabled
        or ESP.HealthBarEnabled
        or ESP.HealthTextEnabled

    if not anyFeature then
        if espHadActiveFeature then
            espHadActiveFeature = false
            for _, set in pairs(ESP.Drawings) do
                hideESPDrawings(set)
            end
        end
        return
    end
    espHadActiveFeature = true

    camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local clock = os.clock()
    local mousePosition = ESP.TracersEnabled and ESP.TracerType == "Mouse"
        and (UserInputService:GetMouseLocation() - GuiService:GetGuiInset())
        or Vector2.zero
    local cameraPosition = camera.CFrame.Position
    local viewport = camera.ViewportSize
    local namePulseColor
    if ESP.NameEnabled or ESP.DisplayNameEnabled then
        namePulseColor = lerpColor(
            namePulseFrom,
            namePulseTo,
            (math.sin(clock * 1.5) + 1) * 0.5
        )
    end

    local bodyTracerFrom
    if ESP.TracersEnabled and ESP.TracerType == "Body" then
        local localCharacter = LocalPlayer.Character
        local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
        if localRoot then
            bodyTracerFrom = worldToScreen(localRoot.Position)
        end
    end

    for _, player in ipairs(espPlayers) do
        if ESP.TeamCheckEnabled
            and LocalPlayer.Team
            and player.Team == LocalPlayer.Team then
            hidePlayerESP(player)
            continue
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not character or not humanoid or humanoid.Health <= 0 or not root then
            hidePlayerESP(player)
            continue
        end

        local set = ESP.Drawings[player]
        if not set then
            set = createESPDrawings()
            ESP.Drawings[player] = set
        end

        local minimum3D, maximum3D = characterBounds(character)
        if not minimum3D or not maximum3D then
            hideESPDrawings(set)
            continue
        end

        local worldCorners = {
            Vector3.new(minimum3D.X, minimum3D.Y, minimum3D.Z),
            Vector3.new(minimum3D.X, minimum3D.Y, maximum3D.Z),
            Vector3.new(minimum3D.X, maximum3D.Y, minimum3D.Z),
            Vector3.new(minimum3D.X, maximum3D.Y, maximum3D.Z),
            Vector3.new(maximum3D.X, minimum3D.Y, minimum3D.Z),
            Vector3.new(maximum3D.X, minimum3D.Y, maximum3D.Z),
            Vector3.new(maximum3D.X, maximum3D.Y, minimum3D.Z),
            Vector3.new(maximum3D.X, maximum3D.Y, maximum3D.Z),
        }
        local minimum, maximum, corners, inFront = screenBounds(worldCorners, ESP.ThreeDBoxEnabled)
        if not minimum or not maximum then
            hideESPDrawings(set)
            continue
        end

        local width = maximum.X - minimum.X
        local height = maximum.Y - minimum.Y
        if width > viewport.X * 10 or height > viewport.Y * 10 then
            hideESPDrawings(set)
            continue
        end

        local distance = math.floor((cameraPosition - root.Position).Magnitude)
        local scale = 1
        if distance > 400 then
            scale = math.max(0.4, 1 - ((distance - 400) / 600) * 0.6)
        end

        local textColor = ESP.TextColor
        local boxColor = ESP.BoxColor
        local tracerColor = ESP.TracerColor
        if ESP.TeamColorEnabled and player.Team then
            textColor = player.Team.TeamColor.Color
            tracerColor = textColor
        end

        if ESP.BoxEnabled then
            set.Box.Size = Vector2.new(width, height)
            set.Box.Position = minimum
            set.Box.Color = boxColor
            set.Box.Visible = true
            set.BoxOutline.Size = Vector2.new(width + 2, height + 2)
            set.BoxOutline.Position = minimum - Vector2.new(1, 1)
            set.BoxOutline.Visible = true
        else
            set.Box.Visible = false
            set.BoxOutline.Visible = false
        end

        if ESP.BoxFillEnabled and (ESP.BoxEnabled or ESP.ThreeDBoxEnabled) then
            set.BoxFill.Size = Vector2.new(width, height)
            set.BoxFill.Position = minimum
            set.BoxFill.Visible = true
        else
            set.BoxFill.Visible = false
        end

        if ESP.CornerBoxEnabled then
            updateCornerBox(set, minimum, maximum, boxColor)
        else
            for index = 1, 8 do
                set.CornerLines[index].Visible = false
                set.CornerOutlines[index].Visible = false
            end
        end

        if ESP.ThreeDBoxEnabled then
            update3DBox(set, corners, inFront, boxColor)
        else
            for index = 1, 12 do
                set.ThreeDLines[index].Visible = false
                set.ThreeDOutlines[index].Visible = false
            end
        end

        if ESP.NameEnabled or ESP.DisplayNameEnabled then
            set.NameText.Size = math.max(6, math.floor(14 * scale))
            set.NameText.Text = ESP.DisplayNameEnabled and player.DisplayName or player.Name
            set.NameText.Color = namePulseColor
            set.NameText.Position = Vector2.new(
                (minimum.X + maximum.X) * 0.5,
                minimum.Y - 5 * scale - set.NameText.TextBounds.Y / 2
            )
            set.NameText.Visible = true
        else
            set.NameText.Visible = false
        end

        local rightX = maximum.X + 4 * scale
        local gap = math.max(1, 4 * scale)
        local stacked = {}

        if ESP.HostileEnabled
            and (character:GetAttribute("Hostile") == true
                or player:GetAttribute("Hostile") == true) then
            set.HostileText.Size = math.max(6, math.floor(13 * scale))
            set.HostileText.Text = "Hostile"
            set.HostileText.Visible = true
            table.insert(stacked, set.HostileText)
        else
            set.HostileText.Visible = false
        end

        if ESP.ForcefieldEnabled and character:FindFirstChildOfClass("ForceField") then
            set.ForcefieldText.Size = math.max(6, math.floor(13 * scale))
            set.ForcefieldText.Text = "Forcefield"
            set.ForcefieldText.Visible = true
            table.insert(stacked, set.ForcefieldText)
        else
            set.ForcefieldText.Visible = false
        end

        if ESP.ItemEnabled then
            local itemText = getCharacterItems(character, clock)
            if itemText then
                set.ItemText.Size = math.max(6, math.floor(13 * scale))
                set.ItemText.Text = itemText
                set.ItemText.Color = textColor
                set.ItemText.Visible = true
                table.insert(stacked, set.ItemText)
            else
                set.ItemText.Visible = false
            end
        else
            set.ItemText.Visible = false
        end

        if ESP.TeamIndicatorEnabled then
            set.TeamText.Size = math.max(6, math.floor(13 * scale))
            set.TeamText.Text = player.Team and player.Team.Name or "Neutral"
            set.TeamText.Color = player.Team and player.Team.TeamColor.Color or ESP.TextColor
            set.TeamText.Visible = true
            table.insert(stacked, set.TeamText)
        else
            set.TeamText.Visible = false
        end

        if ESP.DistanceEnabled then
            set.DistanceText.Size = math.max(6, math.floor(13 * scale))
            set.DistanceText.Text = tostring(distance) .. "m"
            set.DistanceText.Color = textColor
            set.DistanceText.Visible = true
            table.insert(stacked, set.DistanceText)
        else
            set.DistanceText.Visible = false
        end

        local totalHeight = 0
        for _, textObject in ipairs(stacked) do
            totalHeight += textObject.TextBounds.Y
        end
        totalHeight += gap * math.max(0, #stacked - 1)
        local currentY = (minimum.Y + maximum.Y) * 0.5 - totalHeight * 0.5
        for _, textObject in ipairs(stacked) do
            local bounds = textObject.TextBounds
            textObject.Position = Vector2.new(
                rightX + bounds.X * 0.5,
                currentY + bounds.Y * 0.5
            )
            currentY += bounds.Y + gap
        end

        local healthAlpha = math.clamp(
            humanoid.Health / math.max(humanoid.MaxHealth, 1),
            0,
            1
        )
        local barWidth = math.max(2, 3 * scale)
        local barX = minimum.X - barWidth - 5 * scale
        if ESP.HealthBarEnabled then
            -- One solid black backing rectangle acts as both the border and the
            -- empty-health background. The fill sits directly one pixel inside
            -- it, so there is no floating gap between the outline and bar.
            set.HealthBarOutline.Size = Vector2.new(barWidth + 2, height + 2)
            set.HealthBarOutline.Position = Vector2.new(barX - 1, minimum.Y - 1)
            set.HealthBarOutline.Visible = true
            set.HealthBarBack.Visible = false
            local fillHeight = height * healthAlpha
            set.HealthBarFill.Size = Vector2.new(barWidth, fillHeight)
            set.HealthBarFill.Position = Vector2.new(barX, maximum.Y - fillHeight)
            set.HealthBarFill.Color = healthColor(healthAlpha)
            set.HealthBarFill.Visible = true
        else
            set.HealthBarOutline.Visible = false
            set.HealthBarBack.Visible = false
            set.HealthBarFill.Visible = false
        end

        if ESP.HealthTextEnabled then
            set.HealthText.Size = math.max(6, math.floor(13 * scale))
            set.HealthText.Text = "[" .. math.floor(humanoid.Health) .. "]"
            set.HealthText.Color = healthColor(healthAlpha)
            set.HealthText.Position = Vector2.new(
                barX - set.HealthText.TextBounds.X * 0.5 - 4 * scale,
                (minimum.Y + maximum.Y) * 0.5
            )
            set.HealthText.Visible = true
        else
            set.HealthText.Visible = false
        end

        if ESP.TracersEnabled then
            local targetScreen, targetVisible = worldToScreen(root.Position)
            if targetVisible then
                if ESP.TracerType == "Body" then
                    if bodyTracerFrom then
                        set.BodyTracer.From = bodyTracerFrom
                        set.BodyTracer.To = targetScreen
                        set.BodyTracer.Color = tracerColor
                        set.BodyTracer.Visible = true
                    else
                        set.BodyTracer.Visible = false
                    end
                else
                    set.BodyTracer.Visible = false
                end

                set.TracerMouse.Visible = ESP.TracerType == "Mouse"
                if set.TracerMouse.Visible then
                    set.TracerMouse.From = mousePosition
                    set.TracerMouse.To = targetScreen
                    set.TracerMouse.Color = tracerColor
                end

                set.TracerTop.Visible = ESP.TracerType == "Top"
                if set.TracerTop.Visible then
                    set.TracerTop.From = Vector2.new(viewport.X * 0.5, 0)
                    set.TracerTop.To = targetScreen
                    set.TracerTop.Color = tracerColor
                end

                set.TracerBottom.Visible = ESP.TracerType == "Bottom"
                if set.TracerBottom.Visible then
                    set.TracerBottom.From = Vector2.new(viewport.X * 0.5, viewport.Y)
                    set.TracerBottom.To = targetScreen
                    set.TracerBottom.Color = tracerColor
                end
            else
                set.BodyTracer.Visible = false
                set.TracerMouse.Visible = false
                set.TracerTop.Visible = false
                set.TracerBottom.Visible = false
            end
        else
            set.BodyTracer.Visible = false
            set.TracerMouse.Visible = false
            set.TracerTop.Visible = false
            set.TracerBottom.Visible = false
        end
    end
end)

connect(Players.PlayerRemoving, function(player)
    local playerIndex = table.find(espPlayers, player)
    if playerIndex then
        table.remove(espPlayers, playerIndex)
    end

    local set = ESP.Drawings[player]
    if not set then
        return
    end
    for _, drawing in pairs(set) do
        if typeof(drawing) == "table" and drawing._GuiDrawing then
            drawing:Remove()
        elseif typeof(drawing) == "table" then
            for _, nested in ipairs(drawing) do
                nested:Remove()
            end
        else
            drawing:Remove()
        end
    end
    ESP.Drawings[player] = nil
end)
end

local Visual = Consist:Page("Visual")
for _, child in ipairs(Visual.Frame:GetChildren()) do
    child:Destroy()
end
Visual.Layout.Left = 0
Visual.Layout.Right = 0
Visual.Frame.CanvasSize = UDim2.fromOffset(0, 0)

local VisualMain = makeTitledSection(Visual, "Left", "Main")
rememberToggle(VisualMain:Toggle({
    Name = "Username",
    Default = false,
    Callback = function(value)
        ESP.NameEnabled = value
    end,
}))
rememberToggle(VisualMain:Toggle({
    Name = "Display Name",
    Default = false,
    Callback = function(value)
        ESP.DisplayNameEnabled = value
    end,
}))
rememberToggle(VisualMain:Toggle({
    Name = "Team",
    Default = false,
    Callback = function(value)
        ESP.TeamIndicatorEnabled = value
    end,
}))
rememberToggle(VisualMain:Toggle({
    Name = "Distance",
    Default = false,
    Callback = function(value)
        ESP.DistanceEnabled = value
    end,
}))

local VisualTracers = makeTitledSection(Visual, "Left", "Tracers")
rememberToggle(VisualTracers:Toggle({
    Name = "Tracers",
    Default = false,
    Callback = function(value)
        ESP.TracersEnabled = value
    end,
}))
VisualTracers:Dropdown({
    Name = "Tracer Type",
    Options = {"Body", "Mouse", "Top", "Bottom"},
    Default = ESP.TracerType,
    Callback = function(value)
        ESP.TracerType = value
    end,
})

local VisualIndicators = makeTitledSection(Visual, "Left", "Indicators")
rememberToggle(VisualIndicators:Toggle({
    Name = "Item",
    Default = false,
    Callback = function(value)
        ESP.ItemEnabled = value
    end,
}))
rememberToggle(VisualIndicators:Toggle({
    Name = "Hostile",
    Default = false,
    Callback = function(value)
        ESP.HostileEnabled = value
    end,
}))
rememberToggle(VisualIndicators:Toggle({
    Name = "Forcefield",
    Default = false,
    Callback = function(value)
        ESP.ForcefieldEnabled = value
    end,
}))

local VisualBox = makeTitledSection(Visual, "Right", "Box")
local setBoxTypeLayout
local function refreshBoxMode()
    ESP.BoxEnabled = ESP.BoxMasterEnabled and ESP.BoxType == "2D"
    ESP.ThreeDBoxEnabled = ESP.BoxMasterEnabled and ESP.BoxType == "3D"
    ESP.CornerBoxEnabled = ESP.BoxMasterEnabled and ESP.BoxType == "Corner"
end

rememberToggle(VisualBox:Toggle({
    Name = "Box",
    Default = false,
    Callback = function(value)
        ESP.BoxMasterEnabled = value
        refreshBoxMode()
    end,
}))
VisualBox:Dropdown({
    Name = "Box Type",
    Options = {"2D", "3D", "Corner"},
    Default = ESP.BoxType,
    Callback = function(value)
        ESP.BoxType = value
        refreshBoxMode()
        if setBoxTypeLayout then
            setBoxTypeLayout(value)
        end
    end,
})
local boxFillControl = rememberToggle(VisualBox:Toggle({
    Name = "Box Fill",
    Default = false,
    Callback = function(value)
        ESP.BoxFillEnabled = value
    end,
}))
local boxStreakControl = rememberToggle(VisualBox:Toggle({
    Name = "Box Streak",
    Default = false,
}))

local VisualHealth = makeTitledSection(Visual, "Right", "Health")
rememberToggle(VisualHealth:Toggle({
    Name = "Health Bar",
    Default = false,
    Callback = function(value)
        ESP.HealthBarEnabled = value
    end,
}))
rememberToggle(VisualHealth:Toggle({
    Name = "Health Text",
    Default = false,
    Callback = function(value)
        ESP.HealthTextEnabled = value
    end,
}))

local VisualMisc = makeTitledSection(Visual, "Right", "Misc")
rememberToggle(VisualMisc:Toggle({
    Name = "Team Check",
    Default = false,
    Callback = function(value)
        ESP.TeamCheckEnabled = value
    end,
}))
rememberToggle(VisualMisc:Toggle({
    Name = "Team Color",
    Default = false,
    Callback = function(value)
        ESP.TeamColorEnabled = value
    end,
}))

local expandedBoxHeight = VisualBox.ContentHeight
local boxFillRow = boxFillControl.Instance.Parent
local boxStreakRow = boxStreakControl.Instance.Parent
local boxFillY = boxFillRow.Position.Y.Offset
local boxStreakY = boxStreakRow.Position.Y.Offset
local hiddenFillHeight = math.max(1, boxStreakY - boxFillY)
local collapsedBoxHeight = expandedBoxHeight - hiddenFillHeight
local normalHealthY = VisualHealth.Y
local normalMiscY = VisualMisc.Y
local boxStreakSeparator

for _, child in ipairs(VisualBox.Frame:GetChildren()) do
    if child:IsA("Frame")
        and child.Size.Y.Offset == 1
        and child.Position.Y.Offset == boxStreakY - 1 then
        boxStreakSeparator = child
        break
    end
end

setBoxTypeLayout = function(boxType)
    local showFill = boxType ~= "Corner"
    local removedHeight = showFill and 0 or hiddenFillHeight

    boxFillControl:SetVisible(showFill)
    boxStreakRow.Position = UDim2.fromOffset(0, showFill and boxStreakY or boxFillY)
    if boxStreakSeparator then
        boxStreakSeparator.Visible = showFill
    end

    local boxHeight = showFill and expandedBoxHeight or collapsedBoxHeight
    VisualBox.ContentHeight = boxHeight
    TweenService:Create(
        VisualBox.Frame,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, boxHeight)}
    ):Play()
    TweenService:Create(
        VisualBox.Shadow,
        TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Size = UDim2.fromOffset(258, boxHeight)}
    ):Play()

    for _, data in ipairs({
        {Section = VisualHealth, Y = normalHealthY},
        {Section = VisualMisc, Y = normalMiscY},
    }) do
        local targetY = data.Y - removedHeight
        data.Section.Y = targetY
        TweenService:Create(
            data.Section.Frame,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.fromOffset(270, targetY)}
        ):Play()
        TweenService:Create(
            data.Section.Shadow,
            TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {Position = UDim2.fromOffset(270, targetY + 1)}
        ):Play()
    end

    local rightBottom = VisualMisc.Y + VisualMisc.ContentHeight + 10
    Visual.Layout.Right = rightBottom
    Visual.Frame.CanvasSize = UDim2.fromOffset(0, math.max(Visual.Layout.Left, rightBottom))
end

setBoxTypeLayout(ESP.BoxType)

visualESP = ESP
end

local PlayerPage = Consist:Page("Player")
for _, child in ipairs(PlayerPage.Frame:GetChildren()) do
    child:Destroy()
end
PlayerPage.Layout.Left = 0
PlayerPage.Layout.Right = 0
PlayerPage.Frame.CanvasSize = UDim2.fromOffset(0, 0)

local PlayerMain = makeTitledSection(PlayerPage, "Left", "Main")
rememberToggle(PlayerMain:Toggle({
    Name = "Noclip",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetNoclip(value)
    end,
}))
rememberToggle(PlayerMain:Toggle({
    Name = "Anti Seat",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAntiSeat(value)
    end,
}))
rememberToggle(PlayerMain:Toggle({
    Name = "Jump",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetJump(value)
    end,
}))
rememberToggle(PlayerMain:Toggle({
    Name = "Inf Jump",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetInfJump(value)
    end,
}))
rememberToggle(PlayerMain:Toggle({
    Name = "Max Zoom",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetMaxZoom(value)
    end,
}))
rememberToggle(PlayerMain:Toggle({
    Name = "Anti AFK",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAntiAFK(value)
    end,
}))

local PlayerSpin = makeTitledSection(PlayerPage, "Left", "Spin")
rememberToggle(PlayerSpin:Toggle({
    Name = "Spinbot",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetSpinbot(value)
    end,
}))
PlayerSpin:Slider({
    Name = "Spin Speed",
    Minimum = 1,
    Maximum = 2000,
    Default = State.SpinSpeed,
    Decimals = 0,
    Callback = function(value)
        State.SpinSpeed = math.floor(value + 0.5)
    end,
})

local PlayerUtility = makeTitledSection(PlayerPage, "Right", "Utility")
rememberToggle(PlayerUtility:Toggle({
    Name = "Anti Riot Shield",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAntiRiotShield(value)
    end,
}))
rememberToggle(PlayerUtility:Toggle({
    Name = "Auto Pickup",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAutoPickup(value)
    end,
}))
rememberToggle(PlayerUtility:Toggle({
    Name = "Anti Fence",
    Default = false,
    Callback = function(value)
        PlayerFeatures.SetAntiFence(value)
    end,
}))

local MovementPage = Consist:Page("Movement")
for _, child in ipairs(MovementPage.Frame:GetChildren()) do
    child:Destroy()
end
MovementPage.Layout.Left = 0
MovementPage.Layout.Right = 0
MovementPage.Frame.CanvasSize = UDim2.fromOffset(0, 0)

local TweenTPSection = makeTitledSection(MovementPage, "Left", "Tween Click TP")
local tweenToggleControl = rememberToggle(TweenTPSection:Toggle({
    Name = "Toggle",
    Default = false,
    Callback = function(value)
        MovementFeatures.SetTweenClick(value)
    end,
}))
MovementFeatures.TweenToggleControl = tweenToggleControl

local tweenKeybindDisplay
local tweenKeybindControl = TweenTPSection:Keybind({
    Name = "Keybind",
    Default = State.TweenClickBind,
    ResetValue = function()
        return Enum.KeyCode.Unknown
    end,
    Callback = function(value)
        MovementFeatures.SetTweenBind(value)
        if tweenKeybindDisplay then
            task.defer(function()
                if runtimeAlive and tweenKeybindDisplay then
                    tweenKeybindDisplay:Set(value)
                end
            end)
        end
    end,
})
tweenKeybindDisplay = installExternalKeybind(
    tweenKeybindControl,
    State.TweenClickBind,
    function(value)
        MovementFeatures.SetTweenBind(value)
    end
)

do
local tweenSpeedMinimum = 5
local tweenSpeedMaximum = 140
local tweenSpeedStock = 75
local tweenSpeedUpdate
local tweenSpeedControl
tweenSpeedControl = TweenTPSection:Slider({
    Name = "Tween Speed",
    Minimum = tweenSpeedMinimum,
    Maximum = tweenSpeedMaximum,
    Default = State.TweenSpeed,
    Decimals = 0,
    Callback = function(value)
        local speed = math.clamp(math.floor(value + 0.5), tweenSpeedMinimum, tweenSpeedMaximum)
        if math.abs(speed - tweenSpeedStock) <= 5 then
            speed = tweenSpeedStock
        end
        MovementFeatures.SetTweenSpeed(speed)
        if tweenSpeedControl and math.abs(tweenSpeedControl:Get() - speed) > 0.01 then
            tweenSpeedControl:Set(speed, true)
        end
        if tweenSpeedUpdate then
            tweenSpeedUpdate(State.TweenSpeed)
        end
    end,
})

local holder = tweenSpeedControl.Instance
local track
local valueLabel
for _, child in ipairs(holder:GetChildren()) do
    if child:IsA("Frame")
        and child.Position.Y.Offset == 27
        and child.Size.Y.Offset == 3 then
        track = child
    elseif child:IsA("TextLabel") and child.AnchorPoint.X == 1 then
        valueLabel = child
    end
end

local fill
if track then
    for _, child in ipairs(track:GetChildren()) do
        if child:IsA("Frame")
            and child.AnchorPoint.X == 0
            and child.Size.Y.Scale == 1 then
            fill = child
            break
        end
    end
end

local stockSpeedMarker
if track then
    local stockAlpha = (tweenSpeedStock - tweenSpeedMinimum)
        / (tweenSpeedMaximum - tweenSpeedMinimum)
    stockSpeedMarker = Instance.new("Frame")
    stockSpeedMarker.Name = "StockTweenSpeedMarker"
    stockSpeedMarker.AnchorPoint = Vector2.new(0.5, 0.5)
    stockSpeedMarker.Position = UDim2.new(stockAlpha, 0, 0.5, 0)
    stockSpeedMarker.Size = UDim2.fromOffset(2, 7)
    stockSpeedMarker.BackgroundColor3 = track.BackgroundColor3
    stockSpeedMarker.BorderSizePixel = 0
    stockSpeedMarker.ZIndex = 6
    stockSpeedMarker.Parent = track
end

local function tweenSpeedColor(speed)
    local blue = Color3.fromRGB(72, 139, 238)
    local green = Color3.fromRGB(64, 194, 116)
    local yellow = Color3.fromRGB(235, 190, 68)
    local orange = Color3.fromRGB(238, 126, 51)
    local red = Color3.fromRGB(199, 48, 56)
    if speed <= 40 then
        return blue:Lerp(green, math.clamp((speed - 5) / 35, 0, 1))
    elseif speed <= 75 then
        return green:Lerp(yellow, math.clamp((speed - 40) / 35, 0, 1))
    elseif speed < 90 then
        return yellow:Lerp(orange, math.clamp((speed - 75) / 15, 0, 1))
    end
    return red
end

local currentTweenColor = tweenSpeedColor(State.TweenSpeed)
tweenSpeedUpdate = function(speed)
    currentTweenColor = tweenSpeedColor(speed)
    if fill then
        fill.BackgroundColor3 = currentTweenColor
    end
    if valueLabel then
        valueLabel.Text = tostring(speed)
    end
end
tweenSpeedUpdate(State.TweenSpeed)

connect(RunService.Heartbeat, function()
    if runtimeAlive and fill and fill.Parent then
        fill.BackgroundColor3 = currentTweenColor
        if stockSpeedMarker and stockSpeedMarker.Parent then
            stockSpeedMarker.BackgroundColor3 = track.BackgroundColor3
        end
    end
end)
end

local VFlySection = makeTitledSection(MovementPage, "Right", "Vehicle Fly")
local vFlyToggleControl = rememberToggle(VFlySection:Toggle({
    Name = "Toggle",
    Default = State.VFly,
    Callback = function(value)
        MovementFeatures.SetVFly(value)
    end,
}))
MovementFeatures.VFlyToggleControl = vFlyToggleControl

do
    local vFlyKeybindDisplay
    local vFlyKeybindControl = VFlySection:Keybind({
        Name = "Keybind",
        Default = State.VFlyBind,
        ResetValue = function()
            return Enum.KeyCode.Unknown
        end,
        Callback = function(value)
            MovementFeatures.SetVFlyBind(value)
            if vFlyKeybindDisplay then
                task.defer(function()
                    if runtimeAlive and vFlyKeybindDisplay then
                        vFlyKeybindDisplay:Set(value)
                    end
                end)
            end
        end,
    })
    vFlyKeybindDisplay = installExternalKeybind(
        vFlyKeybindControl,
        State.VFlyBind,
        function(value)
            MovementFeatures.SetVFlyBind(value)
        end
    )
end

do
local vFlySpeedMinimum = 5
local vFlySpeedMaximum = 90
local vFlySpeedUpdate
local vFlySpeedControl
vFlySpeedControl = VFlySection:Slider({
    Name = "Speed",
    Minimum = vFlySpeedMinimum,
    Maximum = vFlySpeedMaximum,
    Default = State.VFlySpeed,
    Decimals = 0,
    Callback = function(value)
        local speed = math.clamp(
            math.floor(value + 0.5),
            vFlySpeedMinimum,
            vFlySpeedMaximum
        )
        MovementFeatures.SetVFlySpeed(speed)
        if vFlySpeedUpdate then
            vFlySpeedUpdate(State.VFlySpeed)
        end
    end,
})

local holder = vFlySpeedControl.Instance
local track
local valueLabel
for _, child in ipairs(holder:GetChildren()) do
    if child:IsA("Frame")
        and child.Position.Y.Offset == 27
        and child.Size.Y.Offset == 3 then
        track = child
    elseif child:IsA("TextLabel") and child.AnchorPoint.X == 1 then
        valueLabel = child
    end
end

local fill
if track then
    for _, child in ipairs(track:GetChildren()) do
        if child:IsA("Frame")
            and child.AnchorPoint.X == 0
            and child.Size.Y.Scale == 1 then
            fill = child
            break
        end
    end
end

local function vFlySpeedColor(speed)
    local normal = Color3.fromRGB(72, 139, 238)
    local yellow = Color3.fromRGB(235, 190, 68)
    local orange = Color3.fromRGB(238, 126, 51)
    local red = Color3.fromRGB(199, 48, 56)

    if speed <= 55 then
        return normal
    elseif speed < 60 then
        return normal:Lerp(yellow, math.clamp((speed - 55) / 5, 0, 1))
    elseif speed <= 75 then
        return yellow
    elseif speed <= 80 then
        return yellow:Lerp(orange, math.clamp((speed - 75) / 5, 0, 1))
    end
    return orange:Lerp(red, math.clamp((speed - 80) / 10, 0, 1))
end

local currentVFlyColor = vFlySpeedColor(State.VFlySpeed)
vFlySpeedUpdate = function(speed)
    currentVFlyColor = vFlySpeedColor(speed)
    if fill then
        fill.BackgroundColor3 = currentVFlyColor
    end
    if valueLabel then
        valueLabel.Text = tostring(speed)
    end
end
vFlySpeedUpdate(State.VFlySpeed)

connect(RunService.Heartbeat, function()
    if runtimeAlive and fill and fill.Parent then
        fill.BackgroundColor3 = currentVFlyColor
    end
end)
end
MovementFeatures.SetVFlySpeed(50)

local MovementSpeedSection = makeTitledSection(MovementPage, "Right", "Speed")
MovementSpeedSection:Slider({
    Name = "Walk Speed",
    Minimum = 16,
    Maximum = 32,
    Default = State.WalkSpeed,
    Decimals = 0,
    Callback = function(value)
        MovementFeatures.SetWalkSpeed(value)
    end,
})
MovementFeatures.SetWalkSpeed(State.WalkSpeed)

local WorldPage = Consist:Page("World")
for _, child in ipairs(WorldPage.Frame:GetChildren()) do
    child:Destroy()
end
WorldPage.Layout.Left = 0
WorldPage.Layout.Right = 0
WorldPage.Frame.CanvasSize = UDim2.fromOffset(0, 0)

local SceneCleanupSection = makeTitledSection(WorldPage, "Left", "Anti Effects")
rememberToggle(SceneCleanupSection:Toggle({
    Name = "No Fog",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetNoFog(value)
    end,
}))
rememberToggle(SceneCleanupSection:Toggle({
    Name = "No Blur",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetNoBlur(value)
    end,
}))
rememberToggle(SceneCleanupSection:Toggle({
    Name = "Disable Shadows",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetDisableShadows(value)
    end,
}))
rememberToggle(SceneCleanupSection:Toggle({
    Name = "Disable Textures",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetDisableTextures(value)
    end,
}))

local VisualEffectsSection = makeTitledSection(WorldPage, "Right", "Visual Effects")
local relayoutVisualEffects
local longShadowSlider
local motionBlurSlider
local bloomSlider
local longShadowToggle
local motionBlurToggle
local highReflectionsToggle
local bloomToggle
local realisticLightingToggle

longShadowToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "Long Shadows",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetLongShadows(value)
        if relayoutVisualEffects then
            relayoutVisualEffects()
        end
    end,
}))

longShadowSlider = VisualEffectsSection:Slider({
    Name = "Shadow Length",
    Minimum = 1,
    Maximum = 10,
    Default = 5,
    Decimals = 0,
    Callback = function(value)
        local snapped = math.clamp(math.floor(value + 0.5), 1, 10)
        WorldFeatures.SetLongShadowAmount(snapped)
        if longShadowSlider and math.abs(longShadowSlider:Get() - snapped) > 0.01 then
            longShadowSlider:Set(snapped, true)
        end
    end,
})

motionBlurToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "Motion Blur",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetMotionBlur(value)
        if relayoutVisualEffects then
            relayoutVisualEffects()
        end
    end,
}))

motionBlurSlider = VisualEffectsSection:Slider({
    Name = "Motion Blur Strength",
    Minimum = 1,
    Maximum = 10,
    Default = 5,
    Decimals = 0,
    Callback = function(value)
        local snapped = math.clamp(math.floor(value + 0.5), 1, 10)
        WorldFeatures.SetMotionBlurStrength(snapped)
        if motionBlurSlider and math.abs(motionBlurSlider:Get() - snapped) > 0.01 then
            motionBlurSlider:Set(snapped, true)
        end
    end,
})

highReflectionsToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "High Reflections",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetHighReflections(value)
    end,
}))

bloomToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "Bloom",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetBloom(value)
        if relayoutVisualEffects then
            relayoutVisualEffects()
        end
    end,
}))

bloomSlider = VisualEffectsSection:Slider({
    Name = "Bloom Strength",
    Minimum = 1,
    Maximum = 10,
    Default = 5,
    Decimals = 0,
    Callback = function(value)
        local snapped = math.clamp(math.floor(value + 0.5), 1, 10)
        WorldFeatures.SetBloomStrength(snapped)
        if bloomSlider and math.abs(bloomSlider:Get() - snapped) > 0.01 then
            bloomSlider:Set(snapped, true)
        end
    end,
})

realisticLightingToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "Realistic Lighting",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetRealisticLighting(value)
    end,
}))

local smoothTransitionsToggle = rememberToggle(VisualEffectsSection:Toggle({
    Name = "Smooth Transitions",
    Default = false,
    Callback = function(value)
        WorldFeatures.SetSmoothTransitions(value)
    end,
}))

local AngularSection = makeTitledSection(WorldPage, "Right", "Angular Sizes")
AngularSection:Slider({
    Name = "Moon Angular Size",
    Minimum = 1,
    Maximum = WorldFeatures.DefaultMoonAngularSize,
    Default = WorldFeatures.DefaultMoonAngularSize,
    Decimals = 0,
    Callback = function(value)
        WorldFeatures.SetMoonAngularSize(value)
    end,
})
AngularSection:Slider({
    Name = "Sun Angular Size",
    Minimum = 1,
    Maximum = WorldFeatures.DefaultSunAngularSize,
    Default = WorldFeatures.DefaultSunAngularSize,
    Decimals = 0,
    Callback = function(value)
        WorldFeatures.SetSunAngularSize(value)
    end,
})

local function findSectionSeparator(section, row)
    local target = row.Position.Y.Offset + row.Size.Y.Offset - 1
    local best
    local bestDistance = math.huge
    for _, child in ipairs(section.Frame:GetChildren()) do
        if child:IsA("Frame") and child.Size.Y.Offset == 1 and child ~= row then
            local distance = math.abs(child.Position.Y.Offset - target)
            if distance < bestDistance and distance <= 3 then
                best = child
                bestDistance = distance
            end
        end
    end
    return best
end

local visualRows = {
    {Row = longShadowToggle.Instance.Parent, Visible = function() return true end},
    {Row = longShadowSlider.Instance, Visible = function() return State.LongShadows end},
    {Row = motionBlurToggle.Instance.Parent, Visible = function() return true end},
    {Row = motionBlurSlider.Instance, Visible = function() return State.MotionBlur end},
    {Row = highReflectionsToggle.Instance.Parent, Visible = function() return true end},
    {Row = bloomToggle.Instance.Parent, Visible = function() return true end},
    {Row = bloomSlider.Instance, Visible = function() return State.Bloom end},
    {Row = realisticLightingToggle.Instance.Parent, Visible = function() return true end},
    {Row = smoothTransitionsToggle.Instance.Parent, Visible = function() return true end},
}
for _, item in ipairs(visualRows) do
    item.Separator = findSectionSeparator(VisualEffectsSection, item.Row)
end

local angularBaseX = 270
relayoutVisualEffects = function()
    local y = 26
    for _, item in ipairs(visualRows) do
        local row = item.Row
        if row then
            local visible = item.Visible()
            row.Visible = visible
            if item.Separator then
                item.Separator.Visible = visible
            end
            if visible then
                row.Position = UDim2.fromOffset(row.Position.X.Offset, y)
                if item.Separator then
                    item.Separator.Position = UDim2.fromOffset(
                        item.Separator.Position.X.Offset,
                        y + row.Size.Y.Offset - 1
                    )
                end
                y += row.Size.Y.Offset
            end
        end
    end

    VisualEffectsSection.ContentHeight = y
    VisualEffectsSection.Frame.Size = UDim2.fromOffset(258, y)
    VisualEffectsSection.Shadow.Size = UDim2.fromOffset(258, y)

    local angularY = VisualEffectsSection.Y + y + 10
    AngularSection.Y = angularY
    AngularSection.Frame.Position = UDim2.fromOffset(angularBaseX, angularY)
    AngularSection.Shadow.Position = UDim2.fromOffset(angularBaseX, angularY + 1)

    local rightBottom = angularY + AngularSection.ContentHeight + 10
    WorldPage.Layout.Right = rightBottom
    WorldPage.Frame.CanvasSize = UDim2.fromOffset(0, math.max(WorldPage.Layout.Left, rightBottom))
end

relayoutVisualEffects()

local originalDestroy = Consist.Destroy
local function cleanup()
    if not runtimeAlive then
        return
    end
    if fastShootCleanup then
        pcall(fastShootCleanup)
    end
    if triggerBCleanup then
        pcall(triggerBCleanup)
    end
    if semiAutomaticCleanup then
        pcall(semiAutomaticCleanup)
    end
    if PlayerFeatures.Cleanup then
        pcall(PlayerFeatures.Cleanup)
    end
    if MovementFeatures.Cleanup then
        pcall(MovementFeatures.Cleanup)
    end
    if WorldFeatures.Cleanup then
        pcall(WorldFeatures.Cleanup)
    end
    runtimeAlive = false
    closeCompactModeMenu()
    if wallBCleanup then
        pcall(wallBCleanup)
    end
    if visualESP then
        pcall(function()
            visualESP:Unload()
        end)
    end
    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    for _, drawing in ipairs(drawings) do
        pcall(function()
            drawing:Remove()
        end)
    end
    clearTargets()
end

environment.__CONSIST_COMBAT_CLEANUP = cleanup

function Consist:Destroy()
    cleanup()
    originalDestroy(self)
end

Consist.CombatState = State
Consist.VisualESP = visualESP
Consist:SelectPage("Combat")

return Consist
