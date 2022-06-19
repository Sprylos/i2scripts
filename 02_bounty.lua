-- functions
local roundToNearest
local findSafe
local getBountyBuys
local getDelta
local initialize
local drawListener
local setupListener
local disposeListener
local modifierSystemListener
local gameValueSystemListener
local gameStateSystemListener
local updateUi
local updatePauseUi

-- bounty stuff
local keepForMax
local keepForMaxReached = false
local noFormatBountyBuys
local bountyBuys = {}
local bountyc = 0
local bounties
local lastDelta = 10
local LIGHT_GREEN = {}
local GREY = {}

-- ui stuff
local Color
local Group
local Label
local uiLayer
local pauseUiLayer
local bountyGroup
local bountyLabels
local keepForMaxLabel
local uiVars = {
    _noSyncCheck = true,
    uiNeedsUpdate = false,
    questsVisible = 0,
    active = true
}



dofile("scripts/utils/binder.lua")

-- rounds the integer n to the nearest integer divisible my m
roundToNearest = function(n, m)
    local r = n % m
    if r + r >= m then return n + m - r else return n - r end
end

-- euphos magic, find the true safe buy
findSafe = function(i, buy, cost, coins)
    local d = { buy }
    for g = 1, 5 do
        if d[g] == 0 then
            return d[g]
        else
            if (d[g] / 50) > coins then
                if math.floor((d[g] - cost) / 50) * i >= (coins * (i - 1)) then
                    return d[g]
                else
                    d[g + 1] = d[g] + 50
                end
            else
                if math.floor((d[g] - cost) / 50) * i >= (math.ceil(d[g] / 50) * (i - 1)) then
                    return d[g]
                else
                    d[g + 1] = d[g] + 50
                end
            end
        end
    end
    return d[5]
end

-- return the best timings to buy the bounties in a table.
getBountyBuys = function(maxBounties, coins, difficulty)
    local rv = {}
    if difficulty < 100 then difficulty = 100
    elseif difficulty > 4500 then difficulty = 4500 end
    local difSlope = 1 + ((difficulty - 100) / 200)
    for i = 1, maxBounties do
        local val = math.floor((difSlope) * (1.60000002384186 ^ (1.15 * (i - 1)) * 180))
        local cost, buy
        if val < 500 then
            cost = roundToNearest(val, 5)
        elseif val < 5000 then
            cost = roundToNearest(val, 10)
        else
            cost = roundToNearest(val, 50)
        end
        if (cost * i) < (coins * 50) then
            buy = math.floor((math.ceil(cost * (i - 1) / 50) * 50) + cost)
        else
            buy = math.floor((math.ceil(coins * (i - 1) / i) * 50) + cost)
        end
        rv[i] = findSafe(i, buy, cost, coins)
    end
    rv[maxBounties + 1] = -1
    return rv
end

-- System Listeners

gameStateSystemListener = luajava.createProxy(GNS .. "systems.GameStateSystem$GameStateSystemListener", {
    -- ad the button in the pause menu
    gamePaused = function()
        updatePauseUi()
    end,
    -- remove the button
    gameResumed = function()
        pauseUiLayer:getTable():clear()
    end,
    affectsGameState = function() return false end,
    getConstantId = function() return 1 end
})

gameValueSystemListener = luajava.createProxy(GNS .. "systems.GameValueSystem$GameValueSystemListener", {
    -- in case the bounty count GV changes (ie through a core), we need to recalculate the bounty buys
    recalculated = function()
        if tonumber(SP.gameValue:getIntValue(enums.GameValueType.MODIFIER_BOUNTY_COUNT)) ~= bounties then
            bounties = tonumber(SP.gameValue:getIntValue(enums.GameValueType.MODIFIER_BOUNTY_COUNT))
            local coins = tonumber(SP.gameValue:getIntValue(enums.GameValueType.MODIFIER_BOUNTY_VALUE))
            local difficulty = tonumber(SP.gameState.averageDifficulty)
            noFormatBountyBuys = getBountyBuys(bounties, coins, difficulty)
            for i = 1, #noFormatBountyBuys - 1 do
                local ix
                if i < 10 then ix = '0' .. i else ix = i end
                bountyBuys[i] = ix .. " | " .. noFormatBountyBuys[i]
            end
            -- force recreation of the UI
            bountyLabels = nil
            bountyGroup = nil
            updateUi()
        end
    end,
    affectsGameState = function() return false end,
    getConstantId = function() return 1 end
})

modifierSystemListener = luajava.createProxy(GNS .. "systems.ModifierSystem$ModifierSystemListener", {
    -- detect if a bounty was built...
    modifierBuilt = function(modifier, price)
        if modifier.type == enums.ModifierType.BOUNTY then
            bountyc = bountyc + 1
            uiVars.uiNeedsUpdate = true
        end
    end,
    -- or sold
    modifierSold = function(modifier, sellPrice)
        if modifier.type == enums.ModifierType.BOUNTY then
            bountyc = bountyc - 1
            uiVars.uiNeedsUpdate = true
        end
    end,
    affectsGameState = function() return false end,
    getConstantId = function() return 1 end
})


-- Functions and script system listeners -----------------------------------------------------------

-- 3 states: d>500 = 1; 500>d>0 = 0; 0>d = -1
getDelta = function(delta)
    if delta > 500 then return 1
    elseif delta <= 500 and delta > 0 then return 0
    else return -1 end
end

updateUi = function()
    uiVars.uiNeedsUpdate = false

    if SP._graphics == nil then return end -- No graphics - skipping
    -- if disabled (with the button) or quest list is visible kill the bounty UI
    if uiVars.questsVisible == 1 or not uiVars.active then
        uiLayer:getTable():clear()
        bountyLabels = nil
        bountyGroup = nil
        return
    end

    -- if the UI is dead, recreate it
    if bountyGroup == nil or bountyLabels == nil then
        bountyGroup = luajava.new(Group)
        bountyLabels = {}
        assert(bountyGroup)
        keepForMaxLabel = luajava.new(Label, "", managers.AssetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
        keepForMaxLabel:setText("Keep: " .. keepForMax)
        keepForMaxLabel:setPosition(40, -275)
        bountyGroup:addActor(keepForMaxLabel)
        for i = 1, #bountyBuys do
            local label = luajava.new(Label, "", managers.AssetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
            label:setText(bountyBuys[i])
            label:setPosition(40, -25 * i - 275)
            bountyLabels[i] = label
            bountyGroup:addActor(label)
        end
        uiLayer:getTable():add(bountyGroup):expand():top():left():padLeft(40) --:size(320.0, 336.0)
    end

    -- updating ui

    local money = SP.gameState:getMoney()

    -- keep-label is red when below the value and blue when above
    local keepColor
    keepForMaxReached = money > keepForMax
    if keepForMaxReached then keepColor = "[#209cff]" else keepColor = "[#ff0000]" end
    keepForMaxLabel:setText(keepColor .. "Keep: " .. keepForMax .. "[]")

    if bountyc > 0 then -- with no bounties, there is no current one
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

updatePauseUi = function()
    -- reset the button
    pauseUiLayer:getTable():clear()

    -- create button
    local PaddedImageButton = bind("ui.actors.PaddedImageButton")
    local icon = managers.AssetManager:getDrawable("icon-modifier-bounty-research")
    local callback = luajava.createProxy("java.lang.Runnable", {
        run = function()
            uiVars.active = not uiVars.active
            updateUi()
            updatePauseUi()
        end
    })
    local button
    if uiVars.active then
        button = luajava.new(PaddedImageButton, icon, callback,
            LIGHT_GREEN["P800"], LIGHT_GREEN["P700"], LIGHT_GREEN["P900"])
    else
        button = luajava.new(PaddedImageButton, icon, callback,
            GREY["P800"], GREY["P700"], GREY["P900"])
    end
    button:setIconPosition(6, 6):setIconSize(40, 40)
    pauseUiLayer:getTable():padRight(40):right():row()
    pauseUiLayer:getTable():add(button):size(52):padTop(-400):padRight(-6)
end

drawListener = function(batch, deltaTime)
    -- update the UI if certain requirements are met
    local questsVisible = managers.SettingsManager:getCustomValue(managers.SettingsManager.CustomValueType.UI_QUEST_LIST_VISIBLE)
    if questsVisible ~= uiVars.questsVisible then
        uiVars.questsVisible = questsVisible
        uiVars.uiNeedsUpdate = true
    end
    local cost = noFormatBountyBuys[bountyc + 1]
    if cost == -1 then uiVars.uiNeedsUpdate = true end
    local money = SP.gameState:getMoney()
    if uiVars.uiNeedsUpdate or getDelta(cost - money) ~= lastDelta or money > keepForMax ~= keepForMaxReached or
        uiLayer == nil then
        updateUi()
    end
end

-- Listens for state restoration (state being deserialized)
-- It is a proper place to restore bindings and recreate UI
-- You can also do that during runtime by checking whether the variable became empty with == nil
initialize = function()
    if SP._graphics ~= nil then
        -- makes sure the bounty help is visible at the start of the game
        managers.SettingsManager:setCustomValue(managers.SettingsManager.CustomValueType.UI_QUEST_LIST_VISIBLE, 0)

        -- calculate bounty buys
        bounties = tonumber(SP.gameValue:getIntValue(enums.GameValueType.MODIFIER_BOUNTY_COUNT))
        local coins = tonumber(SP.gameValue:getIntValue(enums.GameValueType.MODIFIER_BOUNTY_VALUE))
        local difficulty = tonumber(SP.gameState.averageDifficulty)
        noFormatBountyBuys = getBountyBuys(bounties, coins, difficulty)
        keepForMax = coins * 50

        -- format bounty buys (ie "01 | 180")
        for i = 1, #noFormatBountyBuys - 1 do
            local ix
            if i < 10 then ix = '0' .. i else ix = i end
            bountyBuys[i] = ix .. " | " .. noFormatBountyBuys[i]
        end

        local MainUiLayer = bind("managers.UiManager$MainUiLayer")
        Color = luajava.bindClass(GDXNS .. "graphics.Color")
        Group = luajava.bindClass(GDXNS .. "scenes.scene2d.Group")
        Label = luajava.bindClass(GDXNS .. "scenes.scene2d.ui.Label")

        LIGHT_GREEN["P700"] = luajava.new(Color, 1755265279)
        LIGHT_GREEN["P800"] = luajava.new(Color, 1435185151)
        LIGHT_GREEN["P900"] = luajava.new(Color, 862527231)

        GREY["P700"] = luajava.new(Color, 1633772031)
        GREY["P800"] = luajava.new(Color, 1111638783)
        GREY["P900"] = luajava.new(Color, 555819519)

        uiLayer = managers.UiManager:addLayer(MainUiLayer.SCREEN, 199, "bounty stats")
        pauseUiLayer = managers.UiManager:addLayer(MainUiLayer.SCREEN, 200, "bounty toggle", true)
    end
    uiVars.uiNeedsUpdate = true
end

setupListener = function()
    addEventHandler("SystemDispose", disposeListener)

    SP.modifier.listeners:add(modifierSystemListener)
    SP.gameState.listeners:add(gameStateSystemListener)
    SP.gameValue.listeners:add(gameValueSystemListener)

    initialize()
end

disposeListener = function()
    removeEventHandler("SystemDraw", drawListener)
    removeEventHandler("SystemPostSetup", setupListener)
    removeEventHandler("SystemDispose", disposeListener)
    removeEventHandler("StateRestored", initialize)

    SP.modifier.listeners:remove(modifierSystemListener)
    SP.gameState.listeners:remove(gameStateSystemListener)
    SP.gameValue.listeners:remove(gameValueSystemListener)

    if uiLayer ~= nil then
        managers.UiManager:removeLayer(uiLayer)
        uiLayer = nil
    end
    if pauseUiLayer ~= nil then
        managers.UiManager:removeLayer(pauseUiLayer)
        pauseUiLayer = nil
    end
end



addEventHandler("StateRestored", initialize)
addEventHandler("SystemPostSetup", setupListener)
addEventHandler("SystemDraw", drawListener)
