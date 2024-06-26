--[[
== Bounty Script ==

Small UI at the left side of the screen 
to show the optimal bounty buy timings.

Installing: Move this file into Infinitode 2/scripts/game/
Version: 01/06/2024

Created By: Sprylos
Credits: largodream
--]]

-- imports
local CFG = import "Config"
local Label = import("ui.actors.Label")
local PaddedImageButton = import("ui.actors.PaddedImageButton")
local MainUiLayer = import("managers.UiManager$MainUiLayer")
local Render = import("events.game.Render")
local SystemsDispose = import("events.game.SystemsDispose")
local SystemsStateRestore = import("events.game.SystemsStateRestore")
local SystemsPostSetup = import("events.game.SystemsPostSetup")
local GameStateTick = import("events.game.GameStateTick")
local Listener = import("events.Listener")
local GameValueType = import("enums.GameValueType")
local modifierBuild = import("events.game.ModifierBuild")
local modifierSell = import("events.game.ModifierSell")
local GamePaused = import("events.game.GamePaused")
local GameResumed = import("events.game.GameResumed")
local GameValuesRecalculate = import("events.game.GameValuesRecalculate")
local ModifierType = import("enums.ModifierType")

-- upvalues
local keepForMax
local keepForMaxReached = false
local noFormatBountyBuys
local bountyBuys = {}
local bountyc = 0
local bounties = 0
local coins = 0
local lastDelta = 10
local LIGHT_GREEN = {}
local GREY = {}

local uiVars = {
    _noSyncCheck = true,
    uiNeedsUpdate = false,
    questsVisible = 0,
    active = true,
    uiLayer = nil,
    pauseUiLayer = nil,
    keepForMaxLabel = nil
}

local bountyGroup = nil
local bountyLabels = {}

-- euphos magic, find the true safe buy
local findSafe = function(i, buy, cost)
    local d = { buy }
    for g = 1, 5 do
        if d[g] == 0 then
            return d[g]
        end

        if (d[g] / 50) > coins then
            if math.floor((d[g] - cost) / 50) * i >= (coins * (i - 1)) then
                return d[g]
            end

            d[g + 1] = d[g] + 50
        else
            if math.floor((d[g] - cost) / 50) * i >= (math.ceil(d[g] / 50) * (i - 1)) then
                return d[g]
            end

            d[g + 1] = d[g] + 50
        end
    end
    return d[5]
end

-- return the best timings to buy the bounties in a table.
local getBountyBuys = function()
    local rv = {}
    local bountyModifierFactory = managers.ModifierManager:getFactory(ModifierType.BOUNTY)
    for i = 1, bounties do
        local cost, buy
        cost = bountyModifierFactory:getBuildPrice(SP, i - 1)

        if (cost * i) < (coins * 50) then
            buy = math.floor((math.ceil(cost * (i - 1) / 50) * 50) + cost)
        else
            buy = math.floor((math.ceil(coins * (i - 1) / i) * 50) + cost)
        end
        rv[i] = findSafe(i, buy, cost)
    end
    rv[bounties + 1] = -1
    return rv
end

local getDelta = function(delta)
    if delta > 500 then
        return 1
    elseif delta <= 500 and delta > 0 then
        return 0
    else
        return -1
    end
end

-- updates upvalues
local function calculateBountyBuys() -- -> Nothing
    -- calculate bounty buys
    bounties = SP.gameValue:getIntValue(GameValueType.MODIFIER_BOUNTY_COUNT)
    coins = SP.gameValue:getIntValue(GameValueType.MODIFIER_BOUNTY_VALUE)
    noFormatBountyBuys = getBountyBuys()
    keepForMax = coins * 50

    -- format bounty buys (ie "01 | 180")
    for i = 1, #noFormatBountyBuys - 1 do
        local ix
        if i < 10 then ix = '0' .. i else ix = i end
        bountyBuys[i] = ix .. " | " .. noFormatBountyBuys[i]
    end
end

local function updateUI()
    uiVars.uiNeedsUpdate = false

    -- if disabled (with the button) or quest list is visible kill the bounty UI
    if uiVars.questsVisible == 1 or not uiVars.active then
        uiVars.uiLayer:getTable():clear()
        bountyLabels = nil
        bountyGroup = nil
        return
    end

    -- if the UI is dead, recreate it
    if bountyGroup == nil or bountyLabels == nil then
        uiVars.uiLayer:getTable():clear()
        bountyGroup = luajava.new(Group)
        bountyLabels = {}
        assert(bountyGroup)

        uiVars.keepForMaxLabel = Label("", managers.AssetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
        uiVars.keepForMaxLabel:setText("Keep: " .. keepForMax)
        uiVars.keepForMaxLabel:setPosition(40, -275)

        bountyGroup:addActor(uiVars.keepForMaxLabel)
        for i = 1, #bountyBuys do
            local label = Label("", managers.AssetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
            label:setText(bountyBuys[i])
            label:setPosition(40, -25 * i - 275)
            bountyLabels[i] = label
            bountyGroup:addActor(label)
        end
        uiVars.uiLayer:getTable():add(bountyGroup):expand():top():left():padLeft(40) --:size(320.0, 336.0)
    end

    local money = SP.gameState:getMoney()

    -- keep-label is red when below the value and blue when above
    local keepColor
    keepForMaxReached = money > keepForMax
    if keepForMaxReached then keepColor = "[#209cff]" else keepColor = "[#ff0000]" end
    uiVars.keepForMaxLabel:setText(keepColor .. "Keep: " .. keepForMax .. "[]")

    if bountyc > 0 then                                                -- with no bounties, there is no current one
        if bountyc ~= 1 then
            bountyLabels[bountyc - 1]:setText(bountyBuys[bountyc - 1]) -- reset the color
        end
        bountyLabels[bountyc]:setText("[#209cff]" .. bountyBuys[bountyc] .. "[]" .. " [CURRENT]")
    end

    if bountyc < #bountyBuys then -- with all bounties, there is no next one
        local color
        local delta = noFormatBountyBuys[bountyc + 1] - money
        if delta > 500 then
            color = "[#0fa200]"
            lastDelta = 1
        elseif delta <= 500 and delta > 0 then
            color = "[#e6e201]"
            lastDelta = 0
        else
            color = "[#ff0000]"
            lastDelta = -1
        end

        bountyLabels[bountyc + 1]:setText(color .. bountyBuys[bountyc + 1] .. "[]" .. " [NEXT]")
        if bountyc ~= #bountyBuys - 1 then
            bountyLabels[bountyc + 2]:setText(bountyBuys[bountyc + 2]) -- reset the color
        end
    end
end

local function initializeUI()
    if not SP.CFG.headless then
        calculateBountyBuys()

        -- makes sure the bounty help is visible at the start of the game
        managers.SettingsManager:setCustomValue(managers.SettingsManager.CustomValueType.UI_QUEST_LIST_VISIBLE, 0)
        uiVars.uiLayer = managers.UiManager:addLayer(MainUiLayer.SCREEN, 199, "bounty stats")
        uiVars.pauseUiLayer = managers.UiManager:addLayer(MainUiLayer.SCREEN, 200, "bounty toggle", true)

        Color = luajava.bindClass(GDXNS .. "graphics.Color")
        Group = luajava.bindClass(GDXNS .. "scenes.scene2d.Group")

        LIGHT_GREEN["P700"] = luajava.new(Color, 1755265279)
        LIGHT_GREEN["P800"] = luajava.new(Color, 1435185151)
        LIGHT_GREEN["P900"] = luajava.new(Color, 862527231)

        GREY["P700"] = luajava.new(Color, 1633772031)
        GREY["P800"] = luajava.new(Color, 1111638783)
        GREY["P900"] = luajava.new(Color, 555819519)

        SP.events:getListeners(Render):add(Listener(function(_)
            if uiVars.uiNeedsUpdate and uiVars.uiLayer ~= nil then
                updateUI()
            end
        end))
        uiVars.uiNeedsUpdate = true

        log("[Bounty Script] UI initialized")
    end
    log("[Bounty Script] State restored")
end


SP.events:getListeners(GameValuesRecalculate):addStateAffecting(Listener(function(event)
    if SP.gameValue:getIntValue(GameValueType.MODIFIER_BOUNTY_COUNT) ~= bounties or SP.gameValue:getIntValue(GameValueType.MODIFIER_BOUNTY_VALUE) ~= coins then
        calculateBountyBuys()
        bountyGroup = nil
        uiVars.uiNeedsUpdate = true
    end
end))

SP.events:getListeners(GameStateTick):addStateAffecting(Listener(function(event)
    if uiVars.uiLayer == nil or uiVars.pauseUiLayer == nil then
        return initializeUI()
    end

    local questsVisible = managers.SettingsManager:getCustomValue(managers.SettingsManager.CustomValueType
        .UI_QUEST_LIST_VISIBLE)
    if questsVisible ~= uiVars.questsVisible then
        uiVars.questsVisible = questsVisible
        uiVars.uiNeedsUpdate = true
        return
    end

    local cost = noFormatBountyBuys[bountyc + 1]
    local money = SP.gameState:getMoney()
    if cost == -1 or getDelta(cost - money) ~= lastDelta or money > keepForMax ~= keepForMaxReached then
        uiVars.uiNeedsUpdate = true
    end
end))

SP.events:getListeners(modifierBuild):addStateAffecting(Listener(function(event)
    if event:getModifier().type == ModifierType.BOUNTY then
        bountyc = bountyc + 1
        uiVars.uiNeedsUpdate = true
    end
end))

SP.events:getListeners(modifierSell):addStateAffecting(Listener(function(event)
    if event:getModifier().type == ModifierType.BOUNTY then
        bountyc = bountyc - 1
        uiVars.uiNeedsUpdate = true
    end
end))

UpdatePauseUi = function() -- global because it is used in the callback
    -- reset the button
    uiVars.pauseUiLayer:getTable():clear()
    -- create button
    local icon = managers.AssetManager:getDrawable("icon-modifier-bounty-research")
    local callback = luajava.createProxy("java.lang.Runnable", {
        run = function()
            uiVars.active = not uiVars.active
            updateUI()
            UpdatePauseUi()
        end
    })
    local button
    if uiVars.active then
        button = PaddedImageButton(icon, callback,
            LIGHT_GREEN["P800"], LIGHT_GREEN["P700"], LIGHT_GREEN["P900"])
    else
        button = PaddedImageButton(icon, callback,
            GREY["P800"], GREY["P700"], GREY["P900"])
    end
    button:setIconPosition(6, 6):setIconSize(40, 40)
    uiVars.pauseUiLayer:getTable():padRight(40):right():row()
    uiVars.pauseUiLayer:getTable():add(button):size(52):padTop(-400):padRight(-6)
end

SP.events:getListeners(SystemsPostSetup):addStateAffecting(Listener(function()
    SP.events:getListeners(SystemsDispose):addStateAffecting(Listener(function(_)
        if uiVars.uiLayer ~= nil then
            managers.UiManager:removeLayer(uiVars.uiLayer)
            uiVars.uiLayer = nil
        end
        if uiVars.pauseUiLayer ~= nil then
            managers.UiManager:removeLayer(uiVars.pauseUiLayer)
            uiVars.pauseUiLayer = nil
        end
    end))

    initializeUI()
end))

SP.events:getListeners(GamePaused):addStateAffecting(Listener(function(event)
    UpdatePauseUi()
    log("[Bounty Script] Created Pause UI")
end))

SP.events:getListeners(GameResumed):addStateAffecting(Listener(function(event)
    uiVars.pauseUiLayer:getTable():clear()
    log("[Bounty Script] Removed Pause UI")
end))

SP.events:getListeners(SystemsStateRestore):addStateAffecting(Listener(initializeUI))
