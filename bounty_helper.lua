--[[
The MIT License (MIT)

Copyright (c) 2024 Sprylos

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
--]]

--[[
== Bounty Script ==

Small UI at the left side of the screen
to show the optimal bounty buy timings.

Installing: Move this file into Infinitode 2/scripts/game/
Version: 04/08/2024

Created By: Sprylos
Credits: largodream
--]]

local logger = C.TLog:forTag("bounty_helper.lua")

-- upvalues

--- @type com.prineside.tdi2.utils.MaterialColor.class
local MC = C.MaterialColor

--- @type integer
local keepForMax
--- @type boolean
local keepForMaxReached = false
--- @type com.prineside.tdi2.ui.actors.Label
local keepForMaxLabel = nil

--- @type integer[]
local noFormatBountyBuys = {}
--- @type string[]
local bountyBuys = {}

local bountyc = 0
local bounties = 0
local coins = 0
local lastDelta = 10

--- @type com.prineside.tdi2.scene2d.Group?
local bountyGroup = nil
--- @type com.prineside.tdi2.ui.actors.Label[]
local bountyLabels = {}

local UIV = {
    _noSyncCheck = true,

    active = true,
    uiNeedsUpdate = false,
    questsVisible = 0,

    --- @type com.prineside.tdi2.managers.UiManager_UiLayer
    uiLayer = nil,
    --- @type com.prineside.tdi2.managers.UiManager_UiLayer
    pauseUiLayer = nil,
}

--- euphos magic, find the true safe buy
--- @param i integer bounty index
--- @param buy integer
--- @param cost integer
--- @return integer
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

--- return the best timings to buy the bounties in a table
--- @return integer[]
local getBountyBuys = function()
    local rv = {}
    local bountyModifierFactory = C.Game.i.modifierManager:getFactory(C.ModifierType.BOUNTY)
    for i = 1, bounties do
        local cost, buy
        cost = bountyModifierFactory:getBuildPrice(S, i - 1)

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

--- @param delta integer the money - cost difference
--- @return integer
local getDelta = function(delta)
    if delta > 500 then
        return 1
    elseif delta <= 500 and delta > 0 then
        return 0
    else
        return -1
    end
end

--- updates upvalues
--- @return nil
local function calculateBountyBuys()
    -- calculate bounty buys
    bounties = S.gameValue:getIntValue(C.GameValueType.MODIFIER_BOUNTY_COUNT)
    coins = S.gameValue:getIntValue(C.GameValueType.MODIFIER_BOUNTY_VALUE)
    noFormatBountyBuys = getBountyBuys()
    keepForMax = coins * 50

    -- format bounty buys (ie "01 | 180")
    for i = 1, #noFormatBountyBuys - 1 do
        local ix
        if i < 10 then ix = '0' .. i else ix = i end
        bountyBuys[i] = ix .. " | " .. noFormatBountyBuys[i]
    end
end

--- @return nil
local function createUI()
    UIV.uiLayer:getTable():clear()
    bountyGroup = C.Group.new()
    bountyLabels = {}

    keepForMaxLabel = C.Label.new("Keep: " .. keepForMax, C.Game.i.assetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
    keepForMaxLabel:setPosition(40, -275)
    bountyGroup:addActor(keepForMaxLabel)

    for i = 1, #bountyBuys do
        local label = C.Label.new(bountyBuys[i], C.Game.i.assetManager:getLabelStyle(CFG.FONT_SIZE_MEDIUM))
        label:setPosition(40, -25 * i - 275)

        bountyLabels[i] = label
        bountyGroup:addActor(label)
    end
    UIV.uiLayer:getTable():add(bountyGroup):expand():top():left():padLeft(40)
end

--- @return nil
local function updateUI()
    UIV.uiNeedsUpdate = false

    -- if disabled (with the button) or quest list is visible kill the bounty UI
    if UIV.questsVisible == 1 or not UIV.active then
        UIV.uiLayer:getTable():clear()
        bountyLabels = {}
        bountyGroup = nil
        return
    end

    -- if the UI is dead, recreate it
    if bountyGroup == nil or next(bountyLabels) == nil then
        createUI()
    end

    local money = S.gameState:getMoney()

    --- keep-label is red when below the value and blue when above
    --- @type string
    local keepColor
    if money > keepForMax then keepColor = "[#209cff]" else keepColor = "[#ff0000]" end
    keepForMaxLabel:setText(keepColor .. "Keep: " .. keepForMax .. "[]")

    if bountyc > 0 then                                                -- with no bounties, there is no current one
        if bountyc ~= 1 then
            bountyLabels[bountyc - 1]:setText(bountyBuys[bountyc - 1]) -- reset the color
        end
        bountyLabels[bountyc]:setText("[#209cff]" .. bountyBuys[bountyc] .. "[]" .. " [CURRENT]")
    end

    if bountyc >= #bountyBuys then -- with all bounties, there is no next one
        return
    end

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

local function initializeUI()
    if S.CFG.headless then
        return
    end

    calculateBountyBuys()

    -- makes sure the bounty help is visible at the start of the game
    C.Game.i.settingsManager:setCustomValue(C.SettingsManager.CustomValueType.UI_QUEST_LIST_VISIBLE, 0)
    UIV.uiLayer = C.Game.i.uiManager:addLayer(C.MainUiLayer.SCREEN, 199, "bounty stats")
    UIV.pauseUiLayer = C.Game.i.uiManager:addLayer(C.MainUiLayer.SCREEN, 200, "bounty toggle")

    S.events:getListeners(com.prineside.tdi2.events.game.Render.class):add(C.Listener(function()
        if UIV.uiNeedsUpdate and UIV.uiLayer ~= nil then
            updateUI()
        end
    end))
    UIV.uiNeedsUpdate = true

    logger:i("UI initialized")
end


S.events:getListeners(C.GameValuesRecalculate):addStateAffecting(C.Listener(function()
    if S.gameValue:getIntValue(C.GameValueType.MODIFIER_BOUNTY_COUNT) ~= bounties or S.gameValue:getIntValue(C.GameValueType.MODIFIER_BOUNTY_VALUE) ~= coins then
        calculateBountyBuys()
        bountyGroup = nil
        UIV.uiNeedsUpdate = true
    end
end))

S.events:getListeners(C.GameStateTick):addStateAffecting(C.Listener(function()
    if UIV.uiLayer == nil or UIV.pauseUiLayer == nil then
        return initializeUI()
    end

    local questsVisible = C.Game.i.settingsManager:getCustomValue(C.SettingsManager.CustomValueType
        .UI_QUEST_LIST_VISIBLE)
    if questsVisible ~= UIV.questsVisible then
        UIV.questsVisible = questsVisible
        UIV.uiNeedsUpdate = true
        return
    end

    local cost = noFormatBountyBuys[bountyc + 1]
    local money = S.gameState:getMoney()
    if cost == -1 or getDelta(cost - money) ~= lastDelta or money > keepForMax ~= keepForMaxReached then
        UIV.uiNeedsUpdate = true
    end
end))

S.events:getListeners(C.ModifierBuild):addStateAffecting(C.Listener(function(event)
    ---@cast event ModifierBuild

    if event:getModifier().type == C.ModifierType.BOUNTY then
        bountyc = bountyc + 1
        UIV.uiNeedsUpdate = true
    end
end))

S.events:getListeners(C.ModifierSell):addStateAffecting(C.Listener(function(event)
    ---@cast event ModifierSell

    if event:getModifier().type == C.ModifierType.BOUNTY then
        bountyc = bountyc - 1
        UIV.uiNeedsUpdate = true
    end
end))

UpdatePauseUi = function() -- global because it is used in the callback
    -- reset the button
    UIV.pauseUiLayer:getTable():clear()

    -- create button
    local icon = C.Game.i.assetManager:getDrawable("icon-modifier-bounty-research")
    local callback = C.Runnable({
        run = function()
            UIV.active = not UIV.active
            updateUI()
            UpdatePauseUi()
        end
    })

    local button = C.PaddedImageButton.new(icon, callback, C.Color.WHITE, C.Color.WHITE, C.Color.WHITE)
    if UIV.active then
        button:setColors(MC.LIGHT_GREEN.P800, MC.LIGHT_GREEN.P700, MC.LIGHT_GREEN.P900)
    else
        button:setColors(MC.GREY.P800, MC.GREY.P700, MC.GREY.P900)
    end

    button:setIconPosition(6, 6):setIconSize(40, 40)
    UIV.pauseUiLayer:getTable():padRight(40):right():row()
    UIV.pauseUiLayer:getTable():add(button):size(52):padTop(-400):padRight(-6)
end

S.events:getListeners(C.SystemsPostSetup):addStateAffecting(C.Listener(function()
    S.events:getListeners(C.SystemsDispose):addStateAffecting(C.Listener(function()
        if UIV.uiLayer ~= nil then
            C.Game.i.uiManager:removeLayer(UIV.uiLayer)
            UIV.uiLayer = nil
        end
        if UIV.pauseUiLayer ~= nil then
            C.Game.i.uiManager:removeLayer(UIV.pauseUiLayer)
            UIV.pauseUiLayer = nil
        end
    end))

    initializeUI()
end))

S.events:getListeners(C.GamePaused):addStateAffecting(C.Listener(function()
    UpdatePauseUi()
    logger:d("Created Pause UI")
end))

S.events:getListeners(C.GameResumed):addStateAffecting(C.Listener(function()
    UIV.pauseUiLayer:getTable():clear()
    logger:d("Removed Pause UI")
end))

S.events:getListeners(C.SystemsStateRestore):addStateAffecting(C.Listener(initializeUI))
