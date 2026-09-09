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
    AutoBhop = false,
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
local adaptivePartCache = setmetatable({}, {__mode = "k"})
local toggleControls = {}
local wallBCleanup
local wallBRefreshTeams
local wallBSetEnabled
local fastShootCleanup
local triggerBCleanup
local semiAutomaticCleanup
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
    if not Consist.Gui
        or Consist.Gui.Enabled == false
        or not Consist.App
        or Consist.App.Visible == false then
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
local fastShootBoundBackpack
local fastShootBoundCharacter
local fastShootBackpackConnection
local fastShootCharacterConnection
local fastShootMouseHeld = false
local fastShootGeneration = 0

local function getEquippedFastShootGun()
    local character = LocalPlayer.Character
    local object = character and character:FindFirstChildOfClass("Tool")
    if object and object:GetAttribute("ToolType") == "Gun" then
        return object
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

local function setFastShootAttribute(tool, attribute, value)
    local current = tool:GetAttribute(attribute)
    if current == nil then
        return
    end
    rememberFastShootAttribute(tool, attribute)
    if current ~= value then
        tool:SetAttribute(attribute, value)
    end
end

local function applyFastShootGun(tool)
    if not State.FastShoot
        or not tool
        or not tool:IsA("Tool")
        or tool:GetAttribute("ToolType") ~= "Gun" then
        return
    end

    local autoFire = not (
        State.SemiAutomatic
        and State.SemiAutomaticActive
        and (tool.Name == "AK-47" or tool.Name == "MP5")
    )

    setFastShootAttribute(tool, "AutoFire", autoFire)
    setFastShootAttribute(tool, "FireRate", 0.05)
    setFastShootAttribute(tool, "Range", 999999)
    setFastShootAttribute(tool, "AccurateRange", 999999)
    setFastShootAttribute(tool, "SpreadRadius", 0)
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
    return tool:GetAttribute("CurrentAmmo"), tool:GetAttribute("Local_CurrentAmmo")
end

local function startFastShootHold()
    fastShootGeneration += 1
    local generation = fastShootGeneration

    task.spawn(function()
        local currentGun
        local lastCurrentAmmo
        local lastLocalAmmo
        local lastProgress = os.clock()
        local lastPulse = 0

        while runtimeAlive
            and State.FastShoot
            and fastShootMouseHeld
            and generation == fastShootGeneration do
            local gun = getEquippedFastShootGun()
            local now = os.clock()

            if gun then
                if gun ~= currentGun then
                    currentGun = gun
                    applyFastShootGun(gun)
                    lastCurrentAmmo, lastLocalAmmo = fastShootAmmoState(gun)
                    lastProgress = now
                    lastPulse = now
                    pcall(function()
                        gun:Activate()
                    end)
                elseif gun:GetAttribute("FireRate") ~= 0.05 then
                    applyFastShootGun(gun)
                end

                local currentAmmo, localAmmo = fastShootAmmoState(gun)
                if currentAmmo ~= lastCurrentAmmo or localAmmo ~= lastLocalAmmo then
                    lastCurrentAmmo = currentAmmo
                    lastLocalAmmo = localAmmo
                    lastProgress = now
                end

                if gun:GetAttribute("IsReloading") == true then
                    lastProgress = now
                elseif now - lastProgress >= 0.11 and now - lastPulse >= 0.11 then
                    lastPulse = now
                    lastProgress = now
                    pulseFastShootGun(gun, generation)
                    lastCurrentAmmo, lastLocalAmmo = fastShootAmmoState(gun)
                end
            else
                currentGun = nil
                lastCurrentAmmo = nil
                lastLocalAmmo = nil
                lastProgress = now
            end

            task.wait(0.025)
        end
    end)
end

local function setupFastShootBackpack(backpack)
    if backpack == fastShootBoundBackpack then
        return
    end
    if fastShootBackpackConnection then
        fastShootBackpackConnection:Disconnect()
        fastShootBackpackConnection = nil
    end
    fastShootBoundBackpack = backpack
    if not backpack then
        return
    end

    scanFastShootContainer(backpack)
    fastShootBackpackConnection = backpack.ChildAdded:Connect(function(object)
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
    if character == fastShootBoundCharacter then
        return
    end
    if fastShootCharacterConnection then
        fastShootCharacterConnection:Disconnect()
        fastShootCharacterConnection = nil
    end
    fastShootBoundCharacter = character
    if not character then
        return
    end

    scanFastShootContainer(character)
    fastShootCharacterConnection = character.ChildAdded:Connect(function(object)
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
    if fastShootBackpackConnection then
        fastShootBackpackConnection:Disconnect()
        fastShootBackpackConnection = nil
    end
    if fastShootCharacterConnection then
        fastShootCharacterConnection:Disconnect()
        fastShootCharacterConnection = nil
    end
    fastShootBoundBackpack = nil
    fastShootBoundCharacter = nil
end

do
local semiSavedAutoFire = setmetatable({}, {__mode = "k"})
local semiBoundBackpack
local semiBoundCharacter
local semiBackpackConnection
local semiCharacterConnection
local semiCharacterRemovedConnection

local function semiSupported(tool)
    return tool
        and tool:IsA("Tool")
        and (tool.Name == "AK-47" or tool.Name == "MP5")
end

-- The game's gun controller reads its weapon configuration through GetAttributes.
-- Keep the real Tool attribute synchronized too, but also override the returned
-- AutoFire value so full-auto controller loops see these two guns as semi-auto.
local semiOldNamecall

local function uninstallSemiHook()
    if semiOldNamecall and type(hookmetamethod) == "function" then
        pcall(function()
            hookmetamethod(game, "__namecall", semiOldNamecall)
        end)
        semiOldNamecall = nil
    end
end

local function installSemiHook()
    if semiOldNamecall
        or type(hookmetamethod) ~= "function"
        or type(newcclosure) ~= "function"
        or type(getnamecallmethod) ~= "function" then
        return
    end

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

local function refreshSemiHookForEquipped()
    if not State.SemiAutomatic or not State.SemiAutomaticActive then
        uninstallSemiHook()
        return
    end

    local character = LocalPlayer.Character
    local equipped = character and character:FindFirstChildOfClass("Tool")
    if semiSupported(equipped) then
        installSemiHook()
    else
        uninstallSemiHook()
    end
end

local function setSemiRuntimeActive(active)
    State.SemiAutomaticActive = State.SemiAutomatic and active == true
    if State.SemiAutomaticActive then
        stopFastShootHold()
        refreshSemiTools()
        refreshSemiHookForEquipped()
    else
        restoreSemiTools()
        uninstallSemiHook()
    end
end

local function setSemiAutomaticEnabled(enabled)
    State.SemiAutomatic = enabled == true
    setSemiRuntimeActive(State.SemiAutomatic)
end

local function setupSemiBackpack(backpack)
    if backpack == semiBoundBackpack then
        return
    end
    if semiBackpackConnection then
        semiBackpackConnection:Disconnect()
        semiBackpackConnection = nil
    end
    semiBoundBackpack = backpack
    if not backpack then
        return
    end

    scanSemiContainer(backpack)
    semiBackpackConnection = backpack.ChildAdded:Connect(function(object)
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
    if character == semiBoundCharacter then
        return
    end
    if semiCharacterConnection then
        semiCharacterConnection:Disconnect()
        semiCharacterConnection = nil
    end
    if semiCharacterRemovedConnection then
        semiCharacterRemovedConnection:Disconnect()
        semiCharacterRemovedConnection = nil
    end
    semiBoundCharacter = character
    if not character then
        refreshSemiHookForEquipped()
        return
    end

    scanSemiContainer(character)
    semiCharacterConnection = character.ChildAdded:Connect(function(object)
        if semiSupported(object) then
            task.defer(function()
                if runtimeAlive and object.Parent then
                    applySemiTool(object)
                    refreshSemiHookForEquipped()
                end
            end)
        end
    end)
    semiCharacterRemovedConnection = character.ChildRemoved:Connect(function(object)
        if semiSupported(object) then
            task.defer(function()
                if runtimeAlive then
                    refreshSemiHookForEquipped()
                end
            end)
        end
    end)
    refreshSemiHookForEquipped()
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
                refreshSemiHookForEquipped()
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

    uninstallSemiHook()
    if semiBackpackConnection then
        semiBackpackConnection:Disconnect()
        semiBackpackConnection = nil
    end
    if semiCharacterConnection then
        semiCharacterConnection:Disconnect()
        semiCharacterConnection = nil
    end
    if semiCharacterRemovedConnection then
        semiCharacterRemovedConnection:Disconnect()
        semiCharacterRemovedConnection = nil
    end
    semiBoundBackpack = nil
    semiBoundCharacter = nil
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
local autoSwapLastRun = 0
local autoSwapConnections = {}
local autoSwapGunConnections = {}

local function disconnectAutoSwapList(list)
    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(list)
end

local function getAutoSwapWeapon()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then
        return nil
    end
    local best
    local bestPriority = math.huge
    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool")
            and tool:GetAttribute("FireRate") ~= nil
            and (tool:GetAttribute("Local_ReloadSession") or 0) <= 0
            and tool.Name ~= "Taser"
            and tool.Name ~= "M700" then
            local priority = autoSwapPriorities[tool.Name] or 100
            if priority < bestPriority then
                best = tool
                bestPriority = priority
            end
        end
    end
    return best
end

local function tryAutoSwap(tool)
    if not runtimeAlive or not State.AutoSwap then
        return
    end
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local equipped = character and character:FindFirstChildOfClass("Tool")
    if not humanoid or not equipped or (tool and equipped ~= tool) then
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
end

local function bindAutoSwapGun(tool)
    disconnectAutoSwapList(autoSwapGunConnections)
    if not State.AutoSwap or not tool or not tool:IsA("Tool") then
        return
    end

    for _, attribute in ipairs({"Local_CurrentAmmo", "CurrentAmmo"}) do
        autoSwapGunConnections[#autoSwapGunConnections + 1] =
            tool:GetAttributeChangedSignal(attribute):Connect(function()
                tryAutoSwap(tool)
            end)
    end
    task.defer(function()
        tryAutoSwap(tool)
    end)
end

local function bindAutoSwapCharacter(character)
    disconnectAutoSwapList(autoSwapConnections)
    disconnectAutoSwapList(autoSwapGunConnections)
    if not State.AutoSwap then
        return
    end

    autoSwapConnections[#autoSwapConnections + 1] = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
        task.defer(function()
            if runtimeAlive and State.AutoSwap then
                bindAutoSwapCharacter(newCharacter)
            end
        end)
    end)

    if not character then
        return
    end

    autoSwapConnections[#autoSwapConnections + 1] = character.ChildAdded:Connect(function(object)
        if object:IsA("Tool") then
            bindAutoSwapGun(object)
        end
    end)
    autoSwapConnections[#autoSwapConnections + 1] = character.ChildRemoved:Connect(function(object)
        if object:IsA("Tool") then
            task.defer(function()
                if runtimeAlive and State.AutoSwap then
                    bindAutoSwapGun(character:FindFirstChildOfClass("Tool"))
                end
            end)
        end
    end)
    bindAutoSwapGun(character:FindFirstChildOfClass("Tool"))
end

local function setAutoSwapEnabled(enabled)
    State.AutoSwap = enabled == true
    disconnectAutoSwapList(autoSwapConnections)
    disconnectAutoSwapList(autoSwapGunConnections)
    if State.AutoSwap then
        bindAutoSwapCharacter(LocalPlayer.Character)
    end
end

local PhysicsService = game:GetService("PhysicsService")
local noclipConnection
local noclipExtraConnections = {}
local noclipPartConnections = setmetatable({}, {__mode = "k"})
local noclipSavedCollisions = setmetatable({}, {__mode = "k"})
local NoclipGroup = "ConsistGhost"
local noclipGroupReady = false
local noclipGroupAttempted = false
local maxZoomSaved
local starterMaxZoomSaved
local antiSeatConnections = {}
local antiSeatHumanoid
local antiSeatStateEnabled
local jumpConnection
local jumpHumanoid
local jumpStateEnabled
local jumpBaseline
local jumpLastFire = 0
local jumpAccumulator = 0
local antiAfkConnection
local riotConnection
local riotSaved = setmetatable({}, {__mode = "k"})
local pickupConnections = {}
local pickupItems = setmetatable({}, {__mode = "k"})
local pickupGeneration = 0
local fenceSaved = setmetatable({}, {__mode = "k"})
local fenceConnection

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

local function unbindNoclipPart(part, restore)
    local partConnections = noclipPartConnections[part]
    if partConnections then
        for _, connection in ipairs(partConnections) do
            disconnectNoclipConnection(connection)
        end
        noclipPartConnections[part] = nil
    end

    local saved = noclipSavedCollisions[part]
    if restore and saved and part and part.Parent then
        pcall(function()
            part.CanCollide = saved.CanCollide
        end)
        pcall(function()
            part.CollisionGroup = saved.CollisionGroup
        end)
    end
    noclipSavedCollisions[part] = nil
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
    if State.Noclip then
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
        table.insert(noclipExtraConnections, character.DescendantRemoving:Connect(function(descendant)
            if State.Noclip and descendant:IsA("BasePart") then
                unbindNoclipPart(descendant, true)
            end
        end))
    end

    -- Keep the cached character parts non-collidable during physics. This only
    -- walks the small tracked character-part set; it does not rescan descendants.
    noclipConnection = RunService.PreSimulation:Connect(function()
        if not State.Noclip then
            return
        end
        for part in pairs(noclipSavedCollisions) do
            if part and part.Parent then
                if part.CanCollide then
                    pcall(function()
                        part.CanCollide = false
                    end)
                end
                if noclipGroupReady and part.CollisionGroup ~= NoclipGroup then
                    pcall(function()
                        part.CollisionGroup = NoclipGroup
                    end)
                end
            end
        end
    end)
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

local function disconnectAntiSeatConnections()
    for _, connection in ipairs(antiSeatConnections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    table.clear(antiSeatConnections)
end

local function ejectAntiSeatHumanoid(humanoid)
    if not State.AntiSeat or humanoid ~= antiSeatHumanoid or not humanoid.Parent then
        return
    end
    pcall(function()
        humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
        if humanoid.Sit
            or humanoid.SeatPart ~= nil
            or humanoid:GetState() == Enum.HumanoidStateType.Seated then
            humanoid.Sit = false
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end)
end

local function bindAntiSeatRuntime(humanoid)
    disconnectAntiSeatConnections()
    bindAntiSeatHumanoid(humanoid)
    if not humanoid or not State.AntiSeat then
        return
    end

    -- Seat prevention is event-driven. There is no reason to poll the humanoid
    -- 20 times per second when Roblox already exposes each relevant change.
    antiSeatConnections[#antiSeatConnections + 1] = humanoid.Seated:Connect(function(active)
        if active then
            task.defer(ejectAntiSeatHumanoid, humanoid)
        end
    end)
    antiSeatConnections[#antiSeatConnections + 1] = humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
        if humanoid.Sit then
            task.defer(ejectAntiSeatHumanoid, humanoid)
        end
    end)
    antiSeatConnections[#antiSeatConnections + 1] = humanoid.StateChanged:Connect(function(_, newState)
        if newState == Enum.HumanoidStateType.Seated then
            task.defer(ejectAntiSeatHumanoid, humanoid)
        end
    end)

    ejectAntiSeatHumanoid(humanoid)
end

local function setAntiSeatEnabled(enabled)
    State.AntiSeat = enabled == true
    disconnectAntiSeatConnections()
    restoreAntiSeatHumanoid()

    if State.AntiSeat then
        local character = LocalPlayer.Character
        bindAntiSeatRuntime(character and character:FindFirstChildOfClass("Humanoid"))
    end
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

    jumpAccumulator = 0
    jumpConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not runtimeAlive or (not State.Jump and not State.InfJump) then
            return
        end

        jumpAccumulator += math.max(deltaTime, 0)
        if jumpAccumulator < (1 / 60) then
            return
        end
        jumpAccumulator %= (1 / 60)

        -- Idle Jump/Inf Jump should be effectively free. Resolve character state
        -- only while Space is actually being held.
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space)
            or UserInputService:GetFocusedTextBox() then
            return
        end

        local character = LocalPlayer.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid ~= jumpHumanoid then
            bindJumpHumanoid(humanoid)
        end

        if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart or humanoid.Sit then
            return
        end

        -- Only force the Jumping state while the user is actually trying to jump.
        pcall(function()
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
        end)

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

local function applyRiotShield(shield)
    if not State.AntiRiotShield
        or not shield
        or not shield:IsA("BasePart")
        or shield.Name ~= "RiotShieldPart" then
        return
    end

    local belongsToOtherPlayer = false
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer
            and player.Character
            and shield:IsDescendantOf(player.Character) then
            belongsToOtherPlayer = true
            break
        end
    end
    if not belongsToOtherPlayer then
        return
    end

    if riotSaved[shield] == nil then
        riotSaved[shield] = shield.CanQuery
    end
    if shield.CanQuery then
        shield.CanQuery = false
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

    -- Scan once, then react only when a new shield part appears. The previous
    -- implementation recursively searched every player character every frame.
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local shield = player.Character:FindFirstChild("RiotShieldPart", true)
            if shield then
                applyRiotShield(shield)
            end
        end
    end

    riotConnection = workspace.DescendantAdded:Connect(function(object)
        if object.Name == "RiotShieldPart" and object:IsA("BasePart") then
            task.defer(function()
                if runtimeAlive and State.AntiRiotShield and object.Parent then
                    applyRiotShield(object)
                end
            end)
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

    table.insert(pickupConnections, workspace.DescendantAdded:Connect(registerPickup))
    table.insert(pickupConnections, workspace.DescendantRemoving:Connect(function(object)
        pickupItems[object] = nil
    end))

    -- Build the initial pickup index incrementally instead of walking the whole
    -- workspace in one frame.
    task.spawn(function()
        local descendants = workspace:GetDescendants()
        for index, object in ipairs(descendants) do
            if not runtimeAlive
                or not State.AutoPickup
                or generation ~= pickupGeneration then
                break
            end
            registerPickup(object)
            if index % 100 == 0 then
                task.wait()
            end
        end
    end)

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
                            and not (character and character:FindFirstChild(toolName)) then
                            local delta = primary.Position - root.Position
                            if delta:Dot(delta) < 144 then
                                pcall(function()
                                    giverPressed:FireServer(pickup)
                                end)
                            end
                        end
                    end
                end
            end
            task.wait(0.10)
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

local SpinBot = {
    Enabled = false,
    Mode = "BodyMover",
    Speed = 40,
    SpinX = false,
    SpinY = true,
    SpinZ = false,
    AngularVelocity = nil,
    _conn = nil
}

local function onSpinTick()
    if not SpinBot.Enabled then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root then return end

    if hum.Sit then return end

    if SpinBot.Mode == "RotVelocity" then
        hum.AutoRotate = false
        local original = root.AssemblyAngularVelocity
        root.AssemblyAngularVelocity = Vector3.new(
            SpinBot.SpinX and SpinBot.Speed or original.X,
            SpinBot.SpinY and SpinBot.Speed or original.Y,
            SpinBot.SpinZ and SpinBot.Speed or original.Z
        )
    elseif SpinBot.Mode == "CFrame" then
        hum.AutoRotate = false
        local val = math.rad((os.clock() * (20 * SpinBot.Speed)) % 360)
        local x, y, z = root.CFrame:ToOrientation()
        root.CFrame = CFrame.new(root.Position) * CFrame.Angles(
            SpinBot.SpinX and val or x,
            SpinBot.SpinY and val or y,
            SpinBot.SpinZ and val or z
        )
    elseif SpinBot.Mode == "BodyMover" then
        hum.AutoRotate = false
        if SpinBot.AngularVelocity and not SpinBot.AngularVelocity.Parent then
            pcall(function()
                SpinBot.AngularVelocity:Destroy()
            end)
            SpinBot.AngularVelocity = nil
        end
        if not SpinBot.AngularVelocity then
            SpinBot.AngularVelocity = Instance.new("BodyAngularVelocity")
        end
        SpinBot.AngularVelocity.Parent = root
        SpinBot.AngularVelocity.MaxTorque = Vector3.new(
            SpinBot.SpinX and math.huge or 0,
            SpinBot.SpinY and math.huge or 0,
            SpinBot.SpinZ and math.huge or 0
        )
        SpinBot.AngularVelocity.AngularVelocity = Vector3.new(
            SpinBot.Speed,
            SpinBot.Speed,
            SpinBot.Speed
        )
    end
end

SpinBot.Speed = State.SpinSpeed
SpinBot._conn = RunService.Heartbeat:Connect(onSpinTick)

function SpinBot:Toggle(state)
    self.Enabled = state
    if not state then
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.AutoRotate = true
            end
        end
        if self.AngularVelocity then
            self.AngularVelocity:Destroy()
            self.AngularVelocity = nil
        end
    end
end

function SpinBot:SetMode(mode)
    self.Mode = mode
    if self.AngularVelocity then
        self.AngularVelocity:Destroy()
        self.AngularVelocity = nil
    end
end

function SpinBot:Unload()
    self:Toggle(false)
    if self._conn then
        self._conn:Disconnect()
        self._conn = nil
    end
end

local function setSpinbotEnabled(enabled)
    State.Spinbot = enabled == true
    SpinBot:Toggle(State.Spinbot)
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
    SpinBot:Unload()
    State.Spinbot = false
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
PlayerFeatures.SetSpinSpeed = function(value)
    State.SpinSpeed = math.clamp(math.floor(value + 0.5), 1, 2000)
    SpinBot.Speed = State.SpinSpeed
end

connect(LocalPlayer.CharacterAdded, function()
    task.wait(0.25)
    if State.Noclip then
        disconnectNoclipRuntimeConnections()
        disconnectNoclipPartConnections()
        table.clear(noclipSavedCollisions)
        State.Noclip = false
        startNoclip()
    end
    if State.MaxZoom then
        setMaxZoomEnabled(true)
    end
    if State.AntiSeat then
        local character = LocalPlayer.Character
        bindAntiSeatRuntime(character and character:FindFirstChildOfClass("Humanoid"))
    end
    if State.Spinbot then
        SpinBot:Toggle(true)
    end
end)
end

do
local activeTweenTP
local tweenClickConnection
local VFlyLibrary = {}
VFlyLibrary.__index = VFlyLibrary

function VFlyLibrary.new()
    local self = setmetatable({}, VFlyLibrary)
    self.Players = game:GetService("Players")
    self.RunService = game:GetService("RunService")
    self.UserInputService = game:GetService("UserInputService")
    self.Workspace = game:GetService("Workspace")
    self.LocalPlayer = self.Players.LocalPlayer

    self.Connection = nil
    self.Enabled = false
    self.Speed = 100 -- Default VFly speed (Prison Life cars are fast)

    return self
end

function VFlyLibrary:Enable(speed)
    if self.Enabled then return end
    self.Enabled = true
    if speed then self.Speed = speed end

    -- Run on RenderStepped so camera movements are synced perfectly
    self.Connection = self.RunService.RenderStepped:Connect(function(dt)
        local char = self.LocalPlayer.Character
        if not char then return end

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local camera = self.Workspace.CurrentCamera

        if not humanoid or not camera then return end

        -- Vape Logic: Check if we are currently sitting in a VehicleSeat
        local seat = humanoid.SeatPart
        if not seat then return end -- Only fly if sitting in a car

        local moveDirection = Vector3.new()
        local lookVector = camera.CFrame.LookVector
        local rightVector = camera.CFrame.RightVector

        -- Read WASD inputs relative to the camera
        if self.UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDirection += lookVector end
        if self.UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDirection -= lookVector end
        if self.UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDirection -= rightVector end
        if self.UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDirection += rightVector end
        if self.UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDirection += Vector3.new(0, 1, 0) end
        if self.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or self.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then 
            moveDirection -= Vector3.new(0, 1, 0) 
        end

        -- Vape Movement: Teleport the seat (which drags the whole car)
        if moveDirection.Magnitude > 0 then
            moveDirection = moveDirection.Unit
            -- Speed is multiplied by dt * 60 to keep speed consistent across framerates
            seat.CFrame = seat.CFrame + (moveDirection * (self.Speed * dt * 60))
        end

        -- Prison Life Physics Bypass: Zero out the car's velocity to prevent flinging/rubberbanding
        seat.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        seat.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
end

function VFlyLibrary:Disable()
    self.Enabled = false
    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end
end

-- == Execution ==
-- Initialize the library
local vfly = VFlyLibrary.new()

-- The Consist UI handles the keybind. It intentionally starts unbound.

print("Prison Life VFly executed! Sit in a car and use the Consist V Fly keybind to toggle.")
print("Controls: WASD to move, Space to go up, Left Shift/Ctrl to go down.")

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

local Speed = {
    Enabled = false,
    SpeedValue = 16,
    AutoJump = false,
    _conn = nil
}

local function calculateMoveVector()
    local move = Vector3.zero
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + Vector3.new(0, 0, -1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move + Vector3.new(0, 0, 1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move + Vector3.new(-1, 0, 0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + Vector3.new(1, 0, 0) end

    if move.Magnitude > 0 then
        move = move.Unit
    end
    return move
end

local function onSpeedRenderStep()
    if not Speed.Enabled then return end

    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not hum or not root or hum.Health <= 0 then return end

    if hum:GetState() == Enum.HumanoidStateType.Climbing then return end

    local localMove = calculateMoveVector()
    if localMove == Vector3.zero then return end

    local currentCamera = workspace.CurrentCamera
    if not currentCamera then return end

    local camLook = currentCamera.CFrame.LookVector
    camLook = Vector3.new(camLook.X, 0, camLook.Z)
    if camLook.Magnitude <= 0 then return end
    camLook = camLook.Unit

    local camRight = currentCamera.CFrame.RightVector
    camRight = Vector3.new(camRight.X, 0, camRight.Z)
    if camRight.Magnitude <= 0 then return end
    camRight = camRight.Unit

    local worldMove = (camRight * localMove.X) + (camLook * -localMove.Z)
    if worldMove.Magnitude > 0 then
        worldMove = worldMove.Unit
    end

    local vel = root.AssemblyLinearVelocity
    root.AssemblyLinearVelocity = Vector3.new(
        worldMove.X * Speed.SpeedValue,
        vel.Y,
        worldMove.Z * Speed.SpeedValue
    )

    if Speed.AutoJump and hum.FloorMaterial ~= Enum.Material.Air then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

function Speed:Toggle(state)
    self.Enabled = state
    if state then
        if not self._conn then
            self._conn = RunService.RenderStepped:Connect(onSpeedRenderStep)
        end
    else
        if self._conn then
            self._conn:Disconnect()
            self._conn = nil
        end
    end
end

local function refreshSpeedRuntime()
    Speed.SpeedValue = State.WalkSpeed
    Speed.AutoJump = State.AutoBhop
    Speed:Toggle(State.WalkSpeed ~= 16 or State.AutoBhop)
end

local function setWalkSpeed(value)
    State.WalkSpeed = math.clamp(math.floor(value + 0.5), 16, 33)
    refreshSpeedRuntime()
end

local function setAutoBhopEnabled(enabled)
    State.AutoBhop = enabled == true
    refreshSpeedRuntime()
end

local function setVFlySpeed(value)
    State.VFlySpeed = math.clamp(math.floor(value + 0.5), 5, 90)
    vfly.Speed = State.VFlySpeed
end

local function setVFlyEnabled(enabled)
    enabled = enabled == true
    State.VFly = enabled

    if enabled then
        if not vfly.Enabled then
            vfly:Enable(State.VFlySpeed)
        end
    elseif vfly.Enabled then
        vfly:Disable()
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
MovementFeatures.SetAutoBhop = setAutoBhopEnabled
MovementFeatures.SetVFly = setVFlyEnabled
MovementFeatures.SetVFlyBind = function(binding)
    State.VFlyBind = binding
end
MovementFeatures.SetVFlySpeed = setVFlySpeed
MovementFeatures.Cleanup = function()
    setTweenClickEnabled(false)
    setVFlyEnabled(false)
    State.WalkSpeed = 16
    State.AutoBhop = false
    Speed.AutoJump = false
    Speed:Toggle(false)
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
local fogStartConnection
local fogEndConnection
local atmosphereSaved = setmetatable({}, {__mode = "k"})
local blurSaved = setmetatable({}, {__mode = "k"})
local textureSaved = {}
local textureConnection
local textureGeneration = 0
local lightingConnection
local longShadowBaseClock
local shadowSavedGlobal
local shadowEnforceConnection
local motionBlurEffect
local bloomEffect
local realisticColorEffect
local motionBlurConnection
local motionBlurAccumulator = 0
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
local smoothClockAccumulator = 0
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

    if fogStartConnection then
        fogStartConnection:Disconnect()
        fogStartConnection = nil
    end
    if fogEndConnection then
        fogEndConnection:Disconnect()
        fogEndConnection = nil
    end

    if State.NoFog then
        if not fogSaved then
            fogSaved = {
                FogStart = Lighting.FogStart,
                FogEnd = Lighting.FogEnd,
            }
        end
        Lighting.FogStart = 1000000
        Lighting.FogEnd = 1000001

        -- Reassert only when the game actually changes these values. The old
        -- implementation rewrote both Lighting properties every rendered frame.
        fogStartConnection = Lighting:GetPropertyChangedSignal("FogStart"):Connect(function()
            if State.NoFog and Lighting.FogStart ~= 1000000 then
                Lighting.FogStart = 1000000
            end
        end)
        fogEndConnection = Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function()
            if State.NoFog and Lighting.FogEnd ~= 1000001 then
                Lighting.FogEnd = 1000001
            end
        end)

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

    if shadowEnforceConnection then
        shadowEnforceConnection:Disconnect()
        shadowEnforceConnection = nil
    end

    if State.DisableShadows then
        Lighting.GlobalShadows = false
        -- Property-change enforcement replaces an unconditional per-frame write.
        shadowEnforceConnection = Lighting:GetPropertyChangedSignal("GlobalShadows"):Connect(function()
            if State.DisableShadows and Lighting.GlobalShadows then
                Lighting.GlobalShadows = false
            end
        end)
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
        if object and object.Parent and object:IsA("BasePart") then
            pcall(function()
                object.MaterialVariant = saved.MaterialVariant or ""
            end)
            pcall(function()
                object.Material = saved.Material
            end)
        end
    end
    table.clear(savedObjects)
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
            if index % 100 == 0 then
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
        smoothClockAccumulator = 0
        return
    end

    smoothClockAccumulator += math.max(deltaTime, 0)
    if smoothClockAccumulator < (1 / 60) then
        return
    end
    local dt = smoothClockAccumulator
    smoothClockAccumulator %= (1 / 60)
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
    local needsFrameWork = (State.LongShadows and not State.DisableShadows and not State.SmoothTransitions)
        or (State.MotionBlur and not State.NoBlur)

    if not needsFrameWork then
        motionBlurAccumulator = 0
        lastMotionCameraCFrame = nil
        return
    end

    motionBlurAccumulator += math.max(deltaTime, 0)
    if motionBlurAccumulator < (1 / 60) then
        return
    end
    deltaTime = motionBlurAccumulator
    motionBlurAccumulator %= (1 / 60)

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

local aimPartResolutionCache = setmetatable({}, {__mode = "k"})

local function resolveAimPart(character, selection)
    if not character then
        return nil
    end

    local cache = aimPartResolutionCache[character]
    if not cache then
        cache = {}
        aimPartResolutionCache[character] = cache
    end

    local cached = cache[selection]
    if cached and cached.Parent == character then
        return cached
    end

    local aliases = AimPartAliases[selection]
    if aliases then
        for _, partName in ipairs(aliases) do
            local part = character:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                cache[selection] = part
                return part
            end
        end
    else
        local part = character:FindFirstChild(selection)
        if part and part:IsA("BasePart") then
            cache[selection] = part
            return part
        end
    end

    local root = character:FindFirstChild("HumanoidRootPart")
    cache[selection] = root
    return root
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
    if wallBSetEnabled then
        wallBSetEnabled(State.WallB)
    end
end

local function teamIsExcluded(player)
    return State.TeamCheck
        and player.Team ~= nil
        and State.ExcludedTeams[player.Team.Name] == true
end

local TargetRuntime = {
    CharacterCache = setmetatable({}, {__mode = "k"}),
    VisibilityCache = setmetatable({}, {__mode = "k"}),
    VisibilityParams = RaycastParams.new(),
    VisibilityIgnore = {},
    VisibilityCharacter = nil,
    SilentPlayer = nil,
    SilentPart = nil,
    SilentAt = 0,
    SilentX = 0,
    SilentY = 0,
}
TargetRuntime.VisibilityParams.FilterType = Enum.RaycastFilterType.Exclude

local function getTargetCharacterParts(player)
    local character = player and player.Character
    if not character then
        return nil, nil, nil
    end

    local cached = TargetRuntime.CharacterCache[player]
    if not cached or cached.Character ~= character then
        cached = {
            Character = character,
            Humanoid = character:FindFirstChildOfClass("Humanoid"),
            Root = character:FindFirstChild("HumanoidRootPart"),
        }
        TargetRuntime.CharacterCache[player] = cached
    else
        if not cached.Humanoid or cached.Humanoid.Parent ~= character then
            cached.Humanoid = character:FindFirstChildOfClass("Humanoid")
        end
        if not cached.Root or cached.Root.Parent ~= character then
            cached.Root = character:FindFirstChild("HumanoidRootPart")
        end
    end

    return cached.Character, cached.Humanoid, cached.Root
end

local function validTarget(player)
    if not player or player == LocalPlayer then
        return false
    end
    local _, humanoid, root = getTargetCharacterParts(player)
    if not humanoid or not root or (State.DeadCheck and humanoid.Health <= 0) then
        return false
    end
    return not teamIsExcluded(player)
end

local function partVisible(part)
    camera = workspace.CurrentCamera
    if not camera or not part then
        return false
    end

    local now = os.clock()
    local cached = TargetRuntime.VisibilityCache[part]
    if cached and now - cached.Time < (1 / 120) then
        return cached.Visible
    end

    local localCharacter = LocalPlayer.Character
    if TargetRuntime.VisibilityCharacter ~= localCharacter then
        TargetRuntime.VisibilityCharacter = localCharacter
        table.clear(TargetRuntime.VisibilityIgnore)
        if localCharacter then
            TargetRuntime.VisibilityIgnore[1] = localCharacter
        end
        TargetRuntime.VisibilityParams.FilterDescendantsInstances = TargetRuntime.VisibilityIgnore
    end

    local result = workspace:Raycast(
        camera.CFrame.Position,
        part.Position - camera.CFrame.Position,
        TargetRuntime.VisibilityParams
    )
    local visible = result == nil or result.Instance:IsDescendantOf(part.Parent)
    TargetRuntime.VisibilityCache[part] = {Time = now, Visible = visible}
    return visible
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

local adaptiveCandidatesCache = setmetatable({}, {__mode = "k"})

local function getAdaptiveCandidates(character)
    local cached = adaptiveCandidatesCache[character]
    if cached then
        local valid = true
        for _, part in ipairs(cached) do
            if not part or part.Parent ~= character then
                valid = false
                break
            end
        end
        if valid then
            return cached
        end
    end

    local candidates = table.create(#AdaptiveSelections)
    for _, selection in ipairs(AdaptiveSelections) do
        local part = resolveAimPart(character, selection)
        if part and not table.find(candidates, part) then
            candidates[#candidates + 1] = part
        end
    end
    adaptiveCandidatesCache[character] = candidates
    return candidates
end

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

    for _, part in ipairs(getAdaptiveCandidates(character)) do
        local point, onScreen = camera:WorldToViewportPoint(part.Position)
        if onScreen and point.Z > 0 then
            local dx = point.X - screenAnchor.X
            local dy = point.Y - screenAnchor.Y
            local score = math.sqrt(dx * dx + dy * dy)
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

local targetPlayerList = {}
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        targetPlayerList[#targetPlayerList + 1] = player
    end
end

connect(Players.PlayerAdded, function(player)
    if player ~= LocalPlayer then
        targetPlayerList[#targetPlayerList + 1] = player
    end
end)

connect(Players.PlayerRemoving, function(player)
    local index = table.find(targetPlayerList, player)
    if index then
        table.remove(targetPlayerList, index)
    end
end)

local function findTarget(screenAnchor, ignoreWallCheck)
    camera = workspace.CurrentCamera
    if not camera then
        return nil, nil
    end

    local bestPlayer
    local bestPart
    local bestDistanceSquared = State.FovRadius * State.FovRadius

    for _, player in ipairs(targetPlayerList) do
        if validTarget(player) then
            local part = getAimPart(player.Character, screenAnchor, ignoreWallCheck)
            if part and (ignoreWallCheck or not State.WallCheck or partVisible(part)) then
                local point, onScreen = camera:WorldToViewportPoint(part.Position)
                if onScreen and point.Z > 0 then
                    local dx = point.X - screenAnchor.X
                    local dy = point.Y - screenAnchor.Y
                    local distanceSquared = dx * dx + dy * dy
                    if distanceSquared < bestDistanceSquared then
                        bestDistanceSquared = distanceSquared
                        bestPlayer = player
                        bestPart = part
                    end
                end
            end
        end
    end

    return bestPlayer, bestPart
end

local function findSilentTarget(screenAnchor)
    local now = os.clock()
    if TargetRuntime.SilentPlayer
        and validTarget(TargetRuntime.SilentPlayer)
        and TargetRuntime.SilentPart
        and TargetRuntime.SilentPart.Parent
        and now - TargetRuntime.SilentAt < (1 / 60)
        and math.abs(screenAnchor.X - TargetRuntime.SilentX) <= 2
        and math.abs(screenAnchor.Y - TargetRuntime.SilentY) <= 2 then
        return TargetRuntime.SilentPlayer, TargetRuntime.SilentPart
    end

    local player, part = findTarget(screenAnchor, false)
    TargetRuntime.SilentPlayer = player
    TargetRuntime.SilentPart = part
    TargetRuntime.SilentAt = now
    TargetRuntime.SilentX = screenAnchor.X
    TargetRuntime.SilentY = screenAnchor.Y
    return player, part
end

local setTriggerBEnabled
do
local triggerBConnection
local triggerBLastShot = 0
local triggerBLastGun
local triggerBPressed = false
local triggerBAccumulator = 0

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
    local object = character and character:FindFirstChildOfClass("Tool")
    if object
        and (object:GetAttribute("ToolType") == "Gun"
            or object:GetAttribute("FireRate") ~= nil) then
        return object
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
        if State.WallB then
            return findTarget(mousePosition, true)
        end
        return findSilentTarget(mousePosition)
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

    triggerBAccumulator = 0
    triggerBConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not runtimeAlive or not State.TriggerB then
            return
        end

        triggerBAccumulator += math.max(deltaTime, 0)
        if triggerBAccumulator < (1 / 60) then
            return
        end
        triggerBAccumulator %= (1 / 60)

        -- Do not run target acquisition at all unless there is a gun to fire.
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

        -- Target acquisition is the expensive part. Only do it on frames where
        -- the weapon is actually ready to fire instead of rescanning every frame.
        local targetPlayer, targetPart = triggerBTarget()
        if not targetPlayer or not targetPart then
            stopTriggerBGun()
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
task.spawn(function()
    while runtimeAlive do
        local currentTheme = Consist:GetTheme()
        if currentTheme ~= lastSectionTitleTheme then
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
        end
        task.wait(0.20)
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
        if wallBSetEnabled then
            wallBSetEnabled(value)
        end
        clearTargets()
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
    Name = "Trigger B",
    Default = false,
    Callback = function(value)
        setTriggerBEnabled(value)
    end,
}))

rememberToggle(WallBSection:Toggle({
    Name = "Fast Shoot",
    Default = false,
    Callback = function(value)
        setFastShootEnabled(value)
    end,
}))

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

    local mouseRelease = input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.MouseButton2
        or input.UserInputType == Enum.UserInputType.MouseButton3

    -- Only refresh toggle visuals after an actual UI click. The old version
    -- scheduled three full toggle refreshes after every keyboard/mouse release,
    -- including gunfire, which created a lot of needless tasks and UI writes.
    if not mouseRelease or not inputIsOverApp(input) then
        return
    end

    accentRefreshToken += 1
    local token = accentRefreshToken
    task.delay(0.05, function()
        if runtimeAlive and token == accentRefreshToken then
            refreshEnabledToggleColors()
        end
    end)
end)

connect(RunService.RenderStepped, function()
    if not runtimeAlive then
        return
    end

    local camActive = isModeActive("Camlock")
    local mouseActive = isModeActive("Mouselock")
    local selectedActive = isModeActive(State.SelectedMode)
    local fovVisible = State.FovEnabled and (not State.FovAimOnly or selectedActive)

    if not camActive and not mouseActive and not fovVisible then
        if fovCircle and fovCircle.Visible then
            fovCircle.Visible = false
        end
        camTarget = nil
        mouseTarget = nil
        return
    end

    camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local screenCenter = camera.ViewportSize / 2
    local mousePosition
    if mouseActive or (fovVisible and State.SelectedMode ~= "Camlock") then
        mousePosition = UserInputService:GetMouseLocation()
    end

    if fovCircle then
        if fovVisible then
            local fovCenter = State.SelectedMode == "Camlock" and screenCenter or mousePosition
            local diameter = State.FovRadius * 2
            fovCircle.Position = UDim2.fromOffset(fovCenter.X, fovCenter.Y)
            fovCircle.Size = UDim2.fromOffset(diameter, diameter)
            fovCircle.Visible = true
        elseif fovCircle.Visible then
            fovCircle.Visible = false
        end
    end

    if camActive then
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

    if mouseActive then
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

-- Normal Silent and Wall Bang share the bullet hook below. Avoiding a global
-- __index hook keeps Silent from adding overhead to every property lookup in the game.

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
        local _, targetPart = findSilentTarget(UserInputService:GetMouseLocation())
        if not targetPart then
            return oldBullet(...)
        end

        args[2] = predictedPosition(targetPart) or targetPart.Position
        return oldBullet(table.unpack(args, 1, args.n))
    end

    -- Wall Bang keeps its stronger origin scanning path. The origin cache only
    -- needs to live for this one shot; clearing it here removes the old
    -- RenderStepped cache-maintenance loop entirely.
    table.clear(OriginScanner.Cache)
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

wallBSetEnabled = function(enabled)
    SETTINGS.Enabled = enabled == true
    local shouldRun = SETTINGS.Enabled and isModeActive("Silent")

    if shouldRun then
        if not entitylib.Running then
            entitylib.start()
        end
        OriginScanner:UpdateIgnore()
    else
        table.clear(OriginScanner.Cache)
        if entitylib.Running then
            entitylib.stop()
        end
    end
end

local wallBHookTarget
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

    for _, eventName in ipairs({"EntityAdded", "LocalAdded"}) do
        entitylib.Events[eventName]:Connect(function()
            if State.WallB then
                OriginScanner:UpdateIgnore()
            end
        end)
    end

    wallBHookTarget = gun.Bullet
    oldBullet = hookFunction(gun.Bullet, wallBBulletHook)

    if State.WallB then
        wallBSetEnabled(true)
    end
end)

wallBCleanup = function()
    if entitylib.Running then
        entitylib.stop()
    end
    table.clear(OriginScanner.Cache)

    -- Restore the original bullet function on re-execution so repeated Consist
    -- test runs do not stack permanent hook wrappers.
    if wallBHookTarget and oldBullet and type(hookFunction) == "function" then
        pcall(function()
            hookFunction(wallBHookTarget, oldBullet)
        end)
    end
    wallBHookTarget = nil
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
    DisplayNameEnabled = true,
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

local healthFull = Color3.fromRGB(55, 255, 90)
local healthYellow = Color3.fromRGB(190, 255, 55)
local healthOrange = Color3.fromRGB(255, 175, 45)
local healthRed = Color3.fromRGB(255, 65, 65)
local black = Color3.new(0, 0, 0)
local drawState = setmetatable({}, {__mode = "k"})

local function getDrawState(object)
    local state = drawState[object]
    if not state then
        state = {}
        drawState[object] = state
    end
    return state
end

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

local function setVisible(object, visible)
    if object and object.Visible ~= visible then
        object.Visible = visible
    end
end

local function createSquare(filled, color, opacity, thickness)
    local object = Instance.new("Frame")
    object.BorderSizePixel = 0
    object.BackgroundColor3 = color
    object.BackgroundTransparency = filled and (1 - opacity) or 1
    object.Visible = false
    object.ZIndex = 1
    object.Parent = espRoot

    local outline
    if not filled then
        outline = Instance.new("UIStroke")
        outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        outline.Color = color
        outline.Thickness = thickness or 1
        outline.Transparency = 1 - opacity
        outline.Parent = object
    end

    return object, outline
end

local function createLine(color, thickness, opacity)
    local object = Instance.new("Frame")
    object.AnchorPoint = Vector2.new(0.5, 0.5)
    object.BorderSizePixel = 0
    object.BackgroundColor3 = color
    object.BackgroundTransparency = 1 - opacity
    object.Size = UDim2.fromOffset(0, thickness or 1)
    object.Visible = false
    object.ZIndex = 1
    object.Parent = espRoot
    return object
end

local function createText(color)
    local object = Instance.new("TextLabel")
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
    object.TextColor3 = color
    object.TextStrokeColor3 = black
    object.TextStrokeTransparency = 0.15
    object.TextTransparency = 0
    object.Visible = false
    object.ZIndex = 1
    object.Parent = espRoot
    return object
end

local function setSquare(object, x, y, width, height, color)
    width = math.max(0, width)
    height = math.max(0, height)
    local state = getDrawState(object)
    if state.X ~= x or state.Y ~= y then
        state.X = x
        state.Y = y
        object.Position = UDim2.fromOffset(x, y)
    end
    if state.Width ~= width or state.Height ~= height then
        state.Width = width
        state.Height = height
        object.Size = UDim2.fromOffset(width, height)
    end
    if color and object.BackgroundColor3 ~= color then
        object.BackgroundColor3 = color
        local outline = object:FindFirstChildOfClass("UIStroke")
        if outline then
            outline.Color = color
        end
    end
    setVisible(object, true)
end

local function setLine(object, x1, y1, x2, y2, thickness, color)
    local state = getDrawState(object)
    if state.X1 ~= x1
        or state.Y1 ~= y1
        or state.X2 ~= x2
        or state.Y2 ~= y2
        or state.Thickness ~= thickness then
        state.X1 = x1
        state.Y1 = y1
        state.X2 = x2
        state.Y2 = y2
        state.Thickness = thickness
        local dx = x2 - x1
        local dy = y2 - y1
        object.Position = UDim2.fromOffset((x1 + x2) * 0.5, (y1 + y2) * 0.5)
        object.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thickness)
        object.Rotation = math.deg(math.atan2(dy, dx))
    end
    if color and object.BackgroundColor3 ~= color then
        object.BackgroundColor3 = color
    end
    setVisible(object, true)
end

local function setText(meta, textValue, size, color)
    local object = meta.Object
    local changed = false

    if meta.Text ~= textValue then
        meta.Text = textValue
        object.Text = textValue
        changed = true
    end
    if meta.Size ~= size then
        meta.Size = size
        object.TextSize = size
        changed = true
    end
    if color and meta.Color ~= color then
        meta.Color = color
        object.TextColor3 = color
    end
    if changed or not meta.Bounds then
        meta.Bounds = object.TextBounds
    end
    setVisible(object, true)
    return meta.Bounds or Vector2.zero
end

local function ensureSquare(set, key, filled, color, opacity, thickness)
    local object = set[key]
    if not object then
        object = createSquare(filled, color, opacity, thickness)
        set[key] = object
    end
    return object
end

local function ensureLineArray(set, key, count, color, thickness, opacity)
    local list = set[key]
    if not list then
        list = table.create(count)
        set[key] = list
    end
    for index = #list + 1, count do
        list[index] = createLine(color, thickness, opacity)
    end
    return list
end

local function setTextPosition(meta, x, y)
    if meta.PosX ~= x or meta.PosY ~= y then
        meta.PosX = x
        meta.PosY = y
        meta.Object.Position = UDim2.fromOffset(x, y)
    end
end

local function ensureText(set, key, color)
    local meta = set[key]
    if not meta then
        meta = {
            Object = createText(color),
            Text = nil,
            Size = nil,
            Color = color,
            Bounds = nil,
        }
        set[key] = meta
    end
    return meta
end

local squareKeys = {
    "Box", "BoxOutline", "BoxFill", "HealthBarOutline", "HealthBarFill",
}
local textKeys = {
    "NameText", "HostileText", "ForcefieldText", "ItemText",
    "TeamText", "DistanceText", "HealthText",
}
local lineKeys = {
    "BodyTracer", "TracerMouse", "TracerTop", "TracerBottom",
}
local lineArrayKeys = {
    "ThreeDLines", "ThreeDOutlines", "CornerLines", "CornerOutlines",
}

local function hideSet(set)
    if set.Hidden then
        return
    end
    set.Hidden = true
    for _, key in ipairs(squareKeys) do
        setVisible(set[key], false)
    end
    for _, key in ipairs(textKeys) do
        local meta = set[key]
        if meta then
            setVisible(meta.Object, false)
        end
    end
    for _, key in ipairs(lineKeys) do
        setVisible(set[key], false)
    end
    for _, key in ipairs(lineArrayKeys) do
        local list = set[key]
        if list then
            for _, object in ipairs(list) do
                setVisible(object, false)
            end
        end
    end
end

local function destroySet(set)
    for _, key in ipairs(squareKeys) do
        local object = set[key]
        if object then
            object:Destroy()
            set[key] = nil
        end
    end
    for _, key in ipairs(textKeys) do
        local meta = set[key]
        if meta and meta.Object then
            meta.Object:Destroy()
        end
        set[key] = nil
    end
    for _, key in ipairs(lineKeys) do
        local object = set[key]
        if object then
            object:Destroy()
            set[key] = nil
        end
    end
    for _, key in ipairs(lineArrayKeys) do
        local list = set[key]
        if list then
            for _, object in ipairs(list) do
                object:Destroy()
            end
        end
        set[key] = nil
    end
    set.Character = nil
    set.Humanoid = nil
    set.Root = nil
    table.clear(set.Parts)
    table.clear(set.Stacked)
end

local function clearAllSets()
    for _, set in pairs(ESP.Drawings) do
        destroySet(set)
    end
    table.clear(ESP.Drawings)
end

local function destroySetObject(set, key)
    local object = set[key]
    if object then
        object:Destroy()
        set[key] = nil
    end
end

local function destroySetText(set, key)
    local meta = set[key]
    if meta then
        if meta.Object then
            meta.Object:Destroy()
        end
        set[key] = nil
    end
end

local function destroySetArray(set, key)
    local list = set[key]
    if list then
        for _, object in ipairs(list) do
            object:Destroy()
        end
        set[key] = nil
    end
end

local function trimInactiveESPObjects()
    for _, set in pairs(ESP.Drawings) do
        if not ESP.BoxEnabled then
            destroySetObject(set, "Box")
            destroySetObject(set, "BoxOutline")
        end
        if not (ESP.BoxFillEnabled and ESP.BoxMasterEnabled and ESP.BoxType ~= "Corner") then
            destroySetObject(set, "BoxFill")
        end
        if not ESP.CornerBoxEnabled then
            destroySetArray(set, "CornerLines")
            destroySetArray(set, "CornerOutlines")
        end
        if not ESP.ThreeDBoxEnabled then
            destroySetArray(set, "ThreeDLines")
            destroySetArray(set, "ThreeDOutlines")
        end
        if not (ESP.NameEnabled or ESP.DisplayNameEnabled) then
            destroySetText(set, "NameText")
        end
        if not ESP.HostileEnabled then destroySetText(set, "HostileText") end
        if not ESP.ForcefieldEnabled then destroySetText(set, "ForcefieldText") end
        if not ESP.ItemEnabled then destroySetText(set, "ItemText") end
        if not ESP.TeamIndicatorEnabled then destroySetText(set, "TeamText") end
        if not ESP.DistanceEnabled then destroySetText(set, "DistanceText") end
        if not ESP.HealthTextEnabled then destroySetText(set, "HealthText") end
        if not ESP.HealthBarEnabled then
            destroySetObject(set, "HealthBarOutline")
            destroySetObject(set, "HealthBarFill")
        end

        if not ESP.TracersEnabled or ESP.TracerType ~= "Body" then
            destroySetObject(set, "BodyTracer")
        end
        if not ESP.TracersEnabled or ESP.TracerType ~= "Mouse" then
            destroySetObject(set, "TracerMouse")
        end
        if not ESP.TracersEnabled or ESP.TracerType ~= "Top" then
            destroySetObject(set, "TracerTop")
        end
        if not ESP.TracersEnabled or ESP.TracerType ~= "Bottom" then
            destroySetObject(set, "TracerBottom")
        end
    end
end

function ESP:Unload()
    clearAllSets()
    if espGui and espGui.Parent then
        espGui:Destroy()
    end
end

local function ensureSet(player)
    local set = ESP.Drawings[player]
    if not set then
        set = {
            Player = player,
            Hidden = true,
            Character = nil,
            Humanoid = nil,
            Root = nil,
            Parts = {},
            NextPartRefresh = 0,
            BoundsRefreshAt = 0,
            BoundsMinOffset = nil,
            BoundsMaxOffset = nil,
            GeometryRefreshAt = 0,
            GeometryRootX = 0,
            GeometryRootY = 0,
            GeometryMinX = nil,
            GeometryMinY = nil,
            GeometryMaxX = nil,
            GeometryMaxY = nil,
            GeometryWas3D = false,
            WorldCorners = table.create(8),
            ScreenCorners = table.create(8),
            InFront = table.create(8),
            Stacked = table.create(6),
            ItemTextValue = nil,
            ItemCheckAt = 0,
            ForcefieldCheckAt = 0,
            HasForcefield = false,
        }
        ESP.Drawings[player] = set
    end
    return set
end

local function refreshCharacter(set, character, now, refreshParts)
    if set.Character ~= character then
        hideSet(set)
        set.Character = character
        set.Humanoid = nil
        set.Root = nil
        set.NextPartRefresh = 0
        set.BoundsRefreshAt = 0
        set.BoundsMinOffset = nil
        set.BoundsMaxOffset = nil
        set.GeometryRefreshAt = 0
        set.GeometryMinX = nil
        set.GeometryMinY = nil
        set.GeometryMaxX = nil
        set.GeometryMaxY = nil
        set.GeometryWas3D = false
        set.ItemTextValue = nil
        set.ItemCheckAt = 0
        set.ForcefieldCheckAt = 0
        set.HasForcefield = false
        table.clear(set.Parts)
    end

    if not character then
        return nil, nil
    end

    local humanoid = set.Humanoid
    if not humanoid or humanoid.Parent ~= character then
        humanoid = character:FindFirstChildOfClass("Humanoid")
        set.Humanoid = humanoid
    end

    local root = set.Root
    if not root or root.Parent ~= character then
        root = character:FindFirstChild("HumanoidRootPart")
        set.Root = root
    end

    if refreshParts and now >= set.NextPartRefresh then
        set.NextPartRefresh = now + 1
        table.clear(set.Parts)
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("BasePart") then
                set.Parts[#set.Parts + 1] = child
            end
        end
    end

    return humanoid, root
end

local function characterBounds(set, root, now)
    if set.BoundsMinOffset
        and set.BoundsMaxOffset
        and now < set.BoundsRefreshAt then
        local position = root.Position
        local minimum = position + set.BoundsMinOffset
        local maximum = position + set.BoundsMaxOffset
        return minimum.X, minimum.Y, minimum.Z, maximum.X, maximum.Y, maximum.Z
    end

    local minX
    local minY
    local minZ
    local maxX
    local maxY
    local maxZ

    for _, part in ipairs(set.Parts) do
        if part.Parent == set.Character then
            local size = part.Size
            local halfX = size.X * 0.5
            local halfY = size.Y * 0.5
            local halfZ = size.Z * 0.5
            local cframe = part.CFrame
            local right = cframe.RightVector
            local up = cframe.UpVector
            local look = cframe.LookVector

            local extentX = math.abs(right.X) * halfX
                + math.abs(up.X) * halfY
                + math.abs(look.X) * halfZ
            local extentY = math.abs(right.Y) * halfX
                + math.abs(up.Y) * halfY
                + math.abs(look.Y) * halfZ
            local extentZ = math.abs(right.Z) * halfX
                + math.abs(up.Z) * halfY
                + math.abs(look.Z) * halfZ

            local position = part.Position
            local partMinX = position.X - extentX
            local partMinY = position.Y - extentY
            local partMinZ = position.Z - extentZ
            local partMaxX = position.X + extentX
            local partMaxY = position.Y + extentY
            local partMaxZ = position.Z + extentZ

            if minX then
                minX = math.min(minX, partMinX)
                minY = math.min(minY, partMinY)
                minZ = math.min(minZ, partMinZ)
                maxX = math.max(maxX, partMaxX)
                maxY = math.max(maxY, partMaxY)
                maxZ = math.max(maxZ, partMaxZ)
            else
                minX, minY, minZ = partMinX, partMinY, partMinZ
                maxX, maxY, maxZ = partMaxX, partMaxY, partMaxZ
            end
        end
    end

    if minX then
        local rootPosition = root.Position
        set.BoundsMinOffset = Vector3.new(
            minX - rootPosition.X,
            minY - rootPosition.Y,
            minZ - rootPosition.Z
        )
        set.BoundsMaxOffset = Vector3.new(
            maxX - rootPosition.X,
            maxY - rootPosition.Y,
            maxZ - rootPosition.Z
        )
        set.BoundsRefreshAt = now + 0.05
    end

    return minX, minY, minZ, maxX, maxY, maxZ
end

local function worldToScreen(position)
    local point, onScreen = camera:WorldToViewportPoint(position)
    return point.X, point.Y, onScreen and point.Z > 0
end

local function screenBounds(set, min3X, min3Y, min3Z, max3X, max3Y, max3Z, need3D)
    local worldCorners = set.WorldCorners
    worldCorners[1] = Vector3.new(min3X, min3Y, min3Z)
    worldCorners[2] = Vector3.new(min3X, min3Y, max3Z)
    worldCorners[3] = Vector3.new(min3X, max3Y, min3Z)
    worldCorners[4] = Vector3.new(min3X, max3Y, max3Z)
    worldCorners[5] = Vector3.new(max3X, min3Y, min3Z)
    worldCorners[6] = Vector3.new(max3X, min3Y, max3Z)
    worldCorners[7] = Vector3.new(max3X, max3Y, min3Z)
    worldCorners[8] = Vector3.new(max3X, max3Y, max3Z)

    local cameraCFrame = camera.CFrame
    local cameraPosition = cameraCFrame.Position
    local cameraLook = cameraCFrame.LookVector
    local nearPlane = 0.5
    local minX
    local minY
    local maxX
    local maxY
    local screenCorners = set.ScreenCorners
    local inFront = set.InFront
    local frontCount = 0

    for index = 1, 8 do
        local corner = worldCorners[index]
        local front = (corner - cameraPosition):Dot(cameraLook) >= nearPlane
        inFront[index] = front
        if front then
            frontCount += 1
            local point = camera:WorldToViewportPoint(corner)
            local x = point.X
            local y = point.Y
            if need3D then
                local saved = screenCorners[index]
                if saved then
                    saved = Vector2.new(x, y)
                    screenCorners[index] = saved
                else
                    screenCorners[index] = Vector2.new(x, y)
                end
            end
            minX = minX and math.min(minX, x) or x
            minY = minY and math.min(minY, y) or y
            maxX = maxX and math.max(maxX, x) or x
            maxY = maxY and math.max(maxY, y) or y
        elseif need3D then
            screenCorners[index] = nil
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
                    local point = camera:WorldToViewportPoint(first + (second - first) * alpha)
                    local x = point.X
                    local y = point.Y
                    minX = minX and math.min(minX, x) or x
                    minY = minY and math.min(minY, y) or y
                    maxX = maxX and math.max(maxX, x) or x
                    maxY = maxY and math.max(maxY, y) or y
                end
            end
        end
    end

    return minX, minY, maxX, maxY, screenCorners, inFront
end

local function update3DBox(set, screenCorners, inFront, offsetX, offsetY)
    local outlines = ensureLineArray(set, "ThreeDOutlines", 12, black, 1.5, 0.5)
    local lines = ensureLineArray(set, "ThreeDLines", 12, ESP.BoxColor, 1.2, 1)
    offsetX = offsetX or 0
    offsetY = offsetY or 0

    for index, edge in ipairs(edges3D) do
        local first = screenCorners[edge[1]]
        local second = screenCorners[edge[2]]
        local visible = inFront[edge[1]] and inFront[edge[2]] and first and second
        if visible then
            local firstX = first.X + offsetX
            local firstY = first.Y + offsetY
            local secondX = second.X + offsetX
            local secondY = second.Y + offsetY
            setLine(outlines[index], firstX, firstY, secondX, secondY, 1.5, black)
            setLine(lines[index], firstX, firstY, secondX, secondY, 1.2, ESP.BoxColor)
        else
            setVisible(lines[index], false)
            setVisible(outlines[index], false)
        end
    end
end

local function updateCornerBox(set, minX, minY, maxX, maxY)
    local outlines = ensureLineArray(set, "CornerOutlines", 8, black, 3, 0.5)
    local lines = ensureLineArray(set, "CornerLines", 8, ESP.BoxColor, 1.5, 1)

    local width = maxX - minX
    local height = maxY - minY
    local length = math.max(2, math.min(width, height) * 0.25)

    local function draw(index, x1, y1, x2, y2)
        setLine(outlines[index], x1, y1, x2, y2, 3, black)
        setLine(lines[index], x1, y1, x2, y2, 1.5, ESP.BoxColor)
    end

    draw(1, minX, minY, minX + length, minY)
    draw(2, minX, minY, minX, minY + length)
    draw(3, maxX, minY, maxX - length, minY)
    draw(4, maxX, minY, maxX, minY + length)
    draw(5, minX, maxY, minX + length, maxY)
    draw(6, minX, maxY, minX, maxY - length)
    draw(7, maxX, maxY, maxX - length, maxY)
    draw(8, maxX, maxY, maxX, maxY - length)
end

local function getCharacterItems(set, now)
    if now < set.ItemCheckAt then
        return set.ItemTextValue
    end
    set.ItemCheckAt = now + 0.25

    local count = 0
    local names = set.ItemNames
    if not names then
        names = table.create(2)
        set.ItemNames = names
    end
    table.clear(names)

    for _, child in ipairs(set.Character:GetChildren()) do
        if child:IsA("Tool") then
            count += 1
            names[count] = child.Name
        end
    end

    set.ItemTextValue = count > 0 and table.concat(names, ", ") or nil
    return set.ItemTextValue
end

local function hasForcefield(set, now)
    if now >= set.ForcefieldCheckAt then
        set.ForcefieldCheckAt = now + 0.20
        set.HasForcefield = set.Character:FindFirstChildOfClass("ForceField") ~= nil
    end
    return set.HasForcefield
end

local espPlayers = {}
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        espPlayers[#espPlayers + 1] = player
    end
end

connect(Players.PlayerAdded, function(player)
    if player ~= LocalPlayer then
        espPlayers[#espPlayers + 1] = player
    end
end)

local namePulseFrom = Color3.fromRGB(255, 255, 255)
local namePulseTo = Color3.fromRGB(170, 0, 255)
local espHadActiveFeature = false
local espAccumulator = 0
local espUpdateInterval = 1 / 60
local lastEspFeatureSignature = -1

local function hidePlayerESP(player)
    local set = ESP.Drawings[player]
    if set then
        hideSet(set)
    end
end

connect(RunService.RenderStepped, function(deltaTime)
    if not runtimeAlive then
        return
    end

    local boxActive = ESP.BoxMasterEnabled
    local boxFillActive = ESP.BoxFillEnabled
        and boxActive
        and ESP.BoxType ~= "Corner"

    local anyFeature = boxActive
        or boxFillActive
        or ESP.NameEnabled
        or ESP.DisplayNameEnabled
        or ESP.ItemEnabled
        or ESP.HostileEnabled
        or ESP.ForcefieldEnabled
        or ESP.TeamIndicatorEnabled
        or ESP.TracersEnabled
        or ESP.DistanceEnabled
        or ESP.HealthBarEnabled
        or ESP.HealthTextEnabled

    if not anyFeature then
        if espHadActiveFeature then
            espHadActiveFeature = false
            clearAllSets()
        end
        return
    end
    espHadActiveFeature = true

    -- When a feature is switched off, destroy its no-longer-used GUI primitives
    -- once instead of retaining every ESP type a player has ever toggled.
    local tracerMode = ESP.TracerType == "Body" and 1
        or ESP.TracerType == "Mouse" and 2
        or ESP.TracerType == "Top" and 3
        or 4
    local featureSignature = tracerMode * 65536
        + (ESP.BoxEnabled and 1 or 0)
        + (ESP.CornerBoxEnabled and 2 or 0)
        + (ESP.ThreeDBoxEnabled and 4 or 0)
        + (boxFillActive and 8 or 0)
        + (ESP.NameEnabled and 16 or 0)
        + (ESP.DisplayNameEnabled and 32 or 0)
        + (ESP.ItemEnabled and 64 or 0)
        + (ESP.HostileEnabled and 128 or 0)
        + (ESP.ForcefieldEnabled and 256 or 0)
        + (ESP.TeamIndicatorEnabled and 512 or 0)
        + (ESP.TracersEnabled and 1024 or 0)
        + (ESP.DistanceEnabled and 2048 or 0)
        + (ESP.HealthBarEnabled and 4096 or 0)
        + (ESP.HealthTextEnabled and 8192 or 0)
    if featureSignature ~= lastEspFeatureSignature then
        lastEspFeatureSignature = featureSignature
        trimInactiveESPObjects()
    end

    -- 60 Hz keeps the overlay visually fluid while preventing high-FPS clients
    -- from doing identical ESP projection/UI work 140-240 times per second.
    espAccumulator = math.min(espAccumulator + math.max(deltaTime, 0), espUpdateInterval * 3)
    if espAccumulator < espUpdateInterval then
        return
    end
    espAccumulator -= espUpdateInterval

    camera = workspace.CurrentCamera
    if not camera then
        return
    end

    local now = os.clock()
    local cameraPosition = camera.CFrame.Position
    local viewport = camera.ViewportSize
    local mouseX = 0
    local mouseY = 0
    if ESP.TracersEnabled and ESP.TracerType == "Mouse" then
        local mousePosition = UserInputService:GetMouseLocation()
        mouseX = mousePosition.X
        mouseY = mousePosition.Y
    end

    local namePulseColor
    if ESP.NameEnabled or ESP.DisplayNameEnabled then
        namePulseColor = lerpColor(
            namePulseFrom,
            namePulseTo,
            (math.sin(now * 1.5) + 1) * 0.5
        )
    end

    local bodyFromX
    local bodyFromY
    if ESP.TracersEnabled and ESP.TracerType == "Body" then
        local localCharacter = LocalPlayer.Character
        local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
        if localRoot then
            bodyFromX, bodyFromY = worldToScreen(localRoot.Position)
        end
    end

    local needsBounds = boxActive
        or boxFillActive
        or ESP.NameEnabled
        or ESP.DisplayNameEnabled
        or ESP.ItemEnabled
        or ESP.HostileEnabled
        or ESP.ForcefieldEnabled
        or ESP.TeamIndicatorEnabled
        or ESP.DistanceEnabled
        or ESP.HealthBarEnabled
        or ESP.HealthTextEnabled

    local needsScale = ESP.NameEnabled
        or ESP.DisplayNameEnabled
        or ESP.ItemEnabled
        or ESP.HostileEnabled
        or ESP.ForcefieldEnabled
        or ESP.TeamIndicatorEnabled
        or ESP.DistanceEnabled
        or ESP.HealthBarEnabled
        or ESP.HealthTextEnabled

    local cullMargin = math.max(300, math.min(viewport.X, viewport.Y) * 0.25)

    for _, player in ipairs(espPlayers) do
        if ESP.TeamCheckEnabled
            and LocalPlayer.Team
            and player.Team == LocalPlayer.Team then
            hidePlayerESP(player)
            continue
        end

        local character = player.Character
        local set = ensureSet(player)
        local humanoid, root = refreshCharacter(set, character, now, needsBounds)
        if not character or not humanoid or humanoid.Health <= 0 or not root then
            hideSet(set)
            continue
        end

        -- One cheap root projection is shared by culling, geometry translation,
        -- and tracers. Expensive eight-corner body projection is refreshed at
        -- 30 Hz and translated smoothly between refreshes.
        local rootPoint = camera:WorldToViewportPoint(root.Position)
        if rootPoint.Z <= 0
            or rootPoint.X < -cullMargin
            or rootPoint.X > viewport.X + cullMargin
            or rootPoint.Y < -cullMargin
            or rootPoint.Y > viewport.Y + cullMargin then
            hideSet(set)
            continue
        end

        set.Hidden = false

        local distance
        local scale = 1
        if needsScale then
            distance = math.floor((cameraPosition - root.Position).Magnitude)
            if distance > 400 then
                scale = math.max(0.4, 1 - ((distance - 400) / 600) * 0.6)
            end
        end

        local minX
        local minY
        local maxX
        local maxY
        local screenCorners
        local inFront
        local geometryOffsetX = 0
        local geometryOffsetY = 0

        if needsBounds then
            local needs3DGeometry = ESP.ThreeDBoxEnabled
            local refreshGeometry = now >= set.GeometryRefreshAt
                or not set.GeometryMinX
                or (needs3DGeometry and not set.GeometryWas3D)

            if refreshGeometry then
                local min3X, min3Y, min3Z, max3X, max3Y, max3Z =
                    characterBounds(set, root, now)
                if not min3X then
                    hideSet(set)
                    continue
                end

                minX, minY, maxX, maxY, screenCorners, inFront = screenBounds(
                    set,
                    min3X,
                    min3Y,
                    min3Z,
                    max3X,
                    max3Y,
                    max3Z,
                    needs3DGeometry
                )

                if not minX or not minY or not maxX or not maxY then
                    hideSet(set)
                    continue
                end

                set.GeometryMinX = minX
                set.GeometryMinY = minY
                set.GeometryMaxX = maxX
                set.GeometryMaxY = maxY
                set.GeometryRootX = rootPoint.X
                set.GeometryRootY = rootPoint.Y
                set.GeometryRefreshAt = now + (1 / 30)
                set.GeometryWas3D = needs3DGeometry
            else
                geometryOffsetX = rootPoint.X - set.GeometryRootX
                geometryOffsetY = rootPoint.Y - set.GeometryRootY
                minX = set.GeometryMinX + geometryOffsetX
                minY = set.GeometryMinY + geometryOffsetY
                maxX = set.GeometryMaxX + geometryOffsetX
                maxY = set.GeometryMaxY + geometryOffsetY
                screenCorners = set.ScreenCorners
                inFront = set.InFront
            end

            local width = maxX - minX
            local height = maxY - minY
            if width > viewport.X * 10 or height > viewport.Y * 10 then
                hideSet(set)
                continue
            end

            if ESP.BoxEnabled then
                local outline = ensureSquare(set, "BoxOutline", false, black, 0.5, 1.5)
                local box = ensureSquare(set, "Box", false, ESP.BoxColor, 1, 1.5)
                setSquare(outline, minX - 1, minY - 1, width + 2, height + 2, black)
                setSquare(box, minX, minY, width, height, ESP.BoxColor)
            else
                setVisible(set.Box, false)
                setVisible(set.BoxOutline, false)
            end

            if boxFillActive then
                local fill = ensureSquare(set, "BoxFill", true, ESP.BoxFillColor, 0.6, 1)
                setSquare(fill, minX, minY, width, height, ESP.BoxFillColor)
            else
                setVisible(set.BoxFill, false)
            end

            if ESP.CornerBoxEnabled then
                updateCornerBox(set, minX, minY, maxX, maxY)
            elseif set.CornerLines then
                for index = 1, #set.CornerLines do
                    setVisible(set.CornerLines[index], false)
                    setVisible(set.CornerOutlines[index], false)
                end
            end

            if ESP.ThreeDBoxEnabled then
                update3DBox(set, screenCorners, inFront, geometryOffsetX, geometryOffsetY)
            elseif set.ThreeDLines then
                for index = 1, #set.ThreeDLines do
                    setVisible(set.ThreeDLines[index], false)
                    setVisible(set.ThreeDOutlines[index], false)
                end
            end

            if ESP.NameEnabled or ESP.DisplayNameEnabled then
                local name = ensureText(set, "NameText", ESP.TextColor)
                local size = math.max(6, math.floor(14 * scale))
                local bounds = setText(
                    name,
                    ESP.DisplayNameEnabled and player.DisplayName or player.Name,
                    size,
                    namePulseColor
                )
                setTextPosition(
                    name,
                    (minX + maxX) * 0.5,
                    minY - 5 * scale - bounds.Y * 0.5
                )
            elseif set.NameText then
                setVisible(set.NameText.Object, false)
            end

            local rightX = maxX + 4 * scale
            local gap = math.max(1, 4 * scale)
            local textSize = math.max(6, math.floor(13 * scale))
            local stacked = set.Stacked
            table.clear(stacked)

            if ESP.HostileEnabled
                and (character:GetAttribute("Hostile") == true
                    or player:GetAttribute("Hostile") == true) then
                local meta = ensureText(set, "HostileText", healthRed)
                setText(meta, "Hostile", textSize, healthRed)
                stacked[#stacked + 1] = meta
            elseif set.HostileText then
                setVisible(set.HostileText.Object, false)
            end

            if ESP.ForcefieldEnabled and hasForcefield(set, now) then
                local meta = ensureText(set, "ForcefieldText", healthOrange)
                setText(meta, "Forcefield", textSize, healthOrange)
                stacked[#stacked + 1] = meta
            elseif set.ForcefieldText then
                setVisible(set.ForcefieldText.Object, false)
            end

            local textColor = ESP.TextColor
            local tracerColor = ESP.TracerColor
            if ESP.TeamColorEnabled and player.Team then
                textColor = player.Team.TeamColor.Color
                tracerColor = textColor
            end

            if ESP.ItemEnabled then
                local itemText = getCharacterItems(set, now)
                if itemText then
                    local meta = ensureText(set, "ItemText", textColor)
                    setText(meta, itemText, textSize, textColor)
                    stacked[#stacked + 1] = meta
                elseif set.ItemText then
                    setVisible(set.ItemText.Object, false)
                end
            elseif set.ItemText then
                setVisible(set.ItemText.Object, false)
            end

            if ESP.TeamIndicatorEnabled then
                local teamText = player.Team and player.Team.Name or "Neutral"
                local teamColor = player.Team and player.Team.TeamColor.Color or ESP.TextColor
                local meta = ensureText(set, "TeamText", teamColor)
                setText(meta, teamText, textSize, teamColor)
                stacked[#stacked + 1] = meta
            elseif set.TeamText then
                setVisible(set.TeamText.Object, false)
            end

            if ESP.DistanceEnabled then
                distance = distance or math.floor((cameraPosition - root.Position).Magnitude)
                local meta = ensureText(set, "DistanceText", textColor)
                setText(meta, tostring(distance) .. "m", textSize, textColor)
                stacked[#stacked + 1] = meta
            elseif set.DistanceText then
                setVisible(set.DistanceText.Object, false)
            end

            local totalHeight = 0
            for _, meta in ipairs(stacked) do
                totalHeight += (meta.Bounds and meta.Bounds.Y or meta.Object.TextBounds.Y)
            end
            totalHeight += gap * math.max(0, #stacked - 1)

            local currentY = (minY + maxY) * 0.5 - totalHeight * 0.5
            for _, meta in ipairs(stacked) do
                local bounds = meta.Bounds or meta.Object.TextBounds
                setTextPosition(
                    meta,
                    rightX + bounds.X * 0.5,
                    currentY + bounds.Y * 0.5
                )
                currentY += bounds.Y + gap
            end

            local healthAlpha
            if ESP.HealthBarEnabled or ESP.HealthTextEnabled then
                healthAlpha = math.clamp(
                    humanoid.Health / math.max(humanoid.MaxHealth, 1),
                    0,
                    1
                )
            end

            local barWidth = math.max(2, 3 * scale)
            local barX = minX - barWidth - 5 * scale
            if ESP.HealthBarEnabled then
                local height = maxY - minY
                local outline = ensureSquare(set, "HealthBarOutline", true, black, 1, 1)
                local fill = ensureSquare(set, "HealthBarFill", true, healthFull, 1, 1)
                setSquare(outline, barX - 1, minY - 1, barWidth + 2, height + 2, black)
                local fillHeight = height * healthAlpha
                setSquare(
                    fill,
                    barX,
                    maxY - fillHeight,
                    barWidth,
                    fillHeight,
                    healthColor(healthAlpha)
                )
            else
                setVisible(set.HealthBarOutline, false)
                setVisible(set.HealthBarFill, false)
            end

            if ESP.HealthTextEnabled then
                local color = healthColor(healthAlpha)
                local meta = ensureText(set, "HealthText", color)
                local healthValue = math.floor(humanoid.Health)
                local bounds = setText(
                    meta,
                    "[" .. healthValue .. "]",
                    textSize,
                    color
                )
                setTextPosition(
                    meta,
                    barX - bounds.X * 0.5 - 4 * scale,
                    (minY + maxY) * 0.5
                )
            elseif set.HealthText then
                setVisible(set.HealthText.Object, false)
            end
        else
            -- Tracer-only mode skips all body-part bounds/projection work.
            setVisible(set.Box, false)
            setVisible(set.BoxOutline, false)
            setVisible(set.BoxFill, false)
            if set.NameText then setVisible(set.NameText.Object, false) end
            if set.HostileText then setVisible(set.HostileText.Object, false) end
            if set.ForcefieldText then setVisible(set.ForcefieldText.Object, false) end
            if set.ItemText then setVisible(set.ItemText.Object, false) end
            if set.TeamText then setVisible(set.TeamText.Object, false) end
            if set.DistanceText then setVisible(set.DistanceText.Object, false) end
            if set.HealthText then setVisible(set.HealthText.Object, false) end
            setVisible(set.HealthBarOutline, false)
            setVisible(set.HealthBarFill, false)
        end

        if ESP.TracersEnabled then
            local targetX = rootPoint.X
            local targetY = rootPoint.Y
            local targetVisible = rootPoint.Z > 0
            local tracerColor = ESP.TracerColor
            if ESP.TeamColorEnabled and player.Team then
                tracerColor = player.Team.TeamColor.Color
            end

            if targetVisible then
                if ESP.TracerType == "Body" and bodyFromX then
                    local line = set.BodyTracer
                    if not line then
                        line = createLine(tracerColor, 1.5, 1)
                        set.BodyTracer = line
                    end
                    setLine(line, bodyFromX, bodyFromY, targetX, targetY, 1.5, tracerColor)
                else
                    setVisible(set.BodyTracer, false)
                end

                if ESP.TracerType == "Mouse" then
                    local line = set.TracerMouse
                    if not line then
                        line = createLine(tracerColor, 1.5, 1)
                        set.TracerMouse = line
                    end
                    setLine(line, mouseX, mouseY, targetX, targetY, 1.5, tracerColor)
                else
                    setVisible(set.TracerMouse, false)
                end

                if ESP.TracerType == "Top" then
                    local line = set.TracerTop
                    if not line then
                        line = createLine(tracerColor, 1.5, 1)
                        set.TracerTop = line
                    end
                    setLine(line, viewport.X * 0.5, 0, targetX, targetY, 1.5, tracerColor)
                else
                    setVisible(set.TracerTop, false)
                end

                if ESP.TracerType == "Bottom" then
                    local line = set.TracerBottom
                    if not line then
                        line = createLine(tracerColor, 1.5, 1)
                        set.TracerBottom = line
                    end
                    setLine(
                        line,
                        viewport.X * 0.5,
                        viewport.Y,
                        targetX,
                        targetY,
                        1.5,
                        tracerColor
                    )
                else
                    setVisible(set.TracerBottom, false)
                end
            else
                setVisible(set.BodyTracer, false)
                setVisible(set.TracerMouse, false)
                setVisible(set.TracerTop, false)
                setVisible(set.TracerBottom, false)
            end
        else
            setVisible(set.BodyTracer, false)
            setVisible(set.TracerMouse, false)
            setVisible(set.TracerTop, false)
            setVisible(set.TracerBottom, false)
        end
    end
end)

connect(Players.PlayerRemoving, function(player)
    local playerIndex = table.find(espPlayers, player)
    if playerIndex then
        table.remove(espPlayers, playerIndex)
    end

    local set = ESP.Drawings[player]
    if set then
        destroySet(set)
        ESP.Drawings[player] = nil
    end
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
VisualMain:Dropdown({
    Name = "Name",
    Options = {"Display Name", "Username", "Both", "Off"},
    Default = "Display Name",
    Callback = function(value)
        ESP.NameEnabled = value == "Username" or value == "Both"
        ESP.DisplayNameEnabled = value == "Display Name" or value == "Both"
    end,
})
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
        PlayerFeatures.SetSpinSpeed(value)
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

task.spawn(function()
    while runtimeAlive and fill and fill.Parent do
        if stockSpeedMarker and stockSpeedMarker.Parent then
            stockSpeedMarker.BackgroundColor3 = track.BackgroundColor3
        end
        task.wait(0.25)
    end
end)
end

local VFlySection = makeTitledSection(MovementPage, "Right", "V Fly")
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

-- Slider color is updated only when the value changes; no per-frame UI write.
end
MovementFeatures.SetVFlySpeed(50)

local MovementSpeedSection = makeTitledSection(MovementPage, "Right", "Speed")
MovementSpeedSection:Slider({
    Name = "Walk Speed",
    Minimum = 16,
    Maximum = 33,
    Default = State.WalkSpeed,
    Decimals = 0,
    Callback = function(value)
        MovementFeatures.SetWalkSpeed(value)
    end,
})
rememberToggle(MovementSpeedSection:Toggle({
    Name = "Auto Bhop",
    Default = State.AutoBhop,
    Callback = function(value)
        MovementFeatures.SetAutoBhop(value)
    end,
}))
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
    runtimeAlive = false
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
