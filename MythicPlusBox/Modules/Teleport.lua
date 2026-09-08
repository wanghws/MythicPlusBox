local addonName, ns = ...

local M = {}
ns:RegisterModule("teleport", M)

local SpellToMap

local function BuildSpellToMap()
    SpellToMap = {}
    for mapID, spellIDs in pairs(ns.DungeonTeleport or {}) do
        for _, spellID in ipairs(spellIDs) do
            SpellToMap[spellID] = mapID
        end
    end
end

-- Each new hover bumps the serial so only the newest refresh chain keeps
-- rescheduling; stale chains from earlier hovers die off instead of stacking
-- concurrent C_Timer loops against the same tooltip.
local tooltipSerial = 0

local function DrawTeleportTooltip(owner, spellID, header, serial, initial)
    if M.isLoadingScreen then return end
    if not initial and (serial ~= tooltipSerial or not GameTooltip:IsOwned(owner)) then
        return
    end
    local L = ns.L
    header(owner)

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(C_Spell.GetSpellName(spellID) or L["TELEPORT_TOOLTIP_TITLE"])
    if IsSpellKnown(spellID) then
        local cd = C_Spell.GetSpellCooldown(spellID)
        if not cd or not cd.startTime or not cd.duration then
            GameTooltip:AddLine(L["TELEPORT_UNKNOWN_COOLDOWN"], 1, 0, 0)
        elseif cd.duration == 0 then
            GameTooltip:AddLine(L["TELEPORT_READY"], 0, 1, 0)
        else
            GameTooltip:AddLine(SecondsToTime(math.ceil(cd.startTime + cd.duration - GetTime())), 1, 0, 0)
        end
    else
        GameTooltip:AddLine(L["TELEPORT_NOT_LEARNED"], 1, 0, 0)
    end
    GameTooltip:Show()

    C_Timer.After(1, function()
        DrawTeleportTooltip(owner, spellID, header, serial, false)
    end)
end

--- Opens a self-refreshing teleport tooltip (spell name + live cooldown) on
--- `owner`. `header` is handed the owner frame and must open GameTooltip on it,
--- either by replaying the frame's own OnEnter or by calling SetOwner itself.
function ns:ShowTeleportTooltip(owner, spellID, header)
    if not owner or not spellID then return end
    tooltipSerial = tooltipSerial + 1
    DrawTeleportTooltip(owner, spellID, header, tooltipSerial, true)
end

function ns:HideTeleportTooltip(owner)
    tooltipSerial = tooltipSerial + 1
    if owner and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

--- Header for frames that already own a tooltip of their own (Blizzard dungeon
--- icons): replay their OnEnter so our lines append to the native tooltip.
local function ReplayOwnerTooltip(owner)
    local onEnter = owner:GetScript("OnEnter")
    if onEnter then onEnter(owner) end
end

local function CreateDungeonButton(icon, mapID)
    if InCombatLockdown() then return end
    local spellID = ns:GetTeleportSpell(mapID)
    if not spellID then return end

    local button = icon.__MPBoxTeleport
    if not button then
        button = CreateFrame("Button", nil, icon, "InsecureActionButtonTemplate")
        button:SetAllPoints(icon)
        icon.__MPBoxTeleport = button
    end
    -- Registering both "AnyDown" and "AnyUp" fires the action twice per click
    -- (down + up); the second activation restarts the teleport cast with a
    -- fresh castGUID, which defeats the announce dedup and broadcasts twice.
    -- Register only the click type matching the user's cvar. Re-applied on
    -- every ChallengesFrame update so cvar changes are picked up.
    button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
    button:SetAttribute("type", "spell")
    button:SetAttribute("spell", spellID)
    button:SetScript("OnEnter", function() ns:ShowTeleportTooltip(icon, spellID, ReplayOwnerTooltip) end)
    button:SetScript("OnLeave", function() ns:HideTeleportTooltip(icon) end)
end

local function CreateAll()
    if InCombatLockdown() then return end
    if not ChallengesFrame or not ChallengesFrame.DungeonIcons then return end
    if not ns.db.profile.teleport.enabled then return end
    for _, dungeonIcon in ipairs(ChallengesFrame.DungeonIcons) do
        CreateDungeonButton(dungeonIcon, dungeonIcon.mapID)
    end
end

local function TryInit()
    if not _G.ChallengesFrame then
        C_AddOns.LoadAddOn("Blizzard_ChallengesUI")
    end
    if not _G.ChallengesFrame then return end
    if M._hooked then return end
    M._hooked = true
    if type(ChallengesFrame.Update) == "function" then
        hooksecurefunc(ChallengesFrame, "Update", CreateAll)
    end
    CreateAll()
end

local function SafeSendChatMessage(msg, chatType)
    if not msg or msg == "" then return end
    msg = msg:gsub("\n", " "):gsub("[%z\1-\31\127]", ""):sub(1, 255)
    SendChatMessage(msg, chatType)
end

local function ShouldAnnounce()
    return IsInGroup() or IsInInstance()
end

function M:GenerateMessage(spellID)
    local mapID = SpellToMap and SpellToMap[spellID]
    if not mapID then return end
    local L = ns.L
    local link = C_Spell.GetSpellLink(spellID)
              or ("|cff71d5ff[" .. (C_Spell.GetSpellName(spellID) or "?") .. "]|r")
    local dungeonName = ns:GetDungeonName(mapID, false)
    local template = ns.db.profile.teleport.announceTemplate or L["TELEPORT_TEMPLATE_DEFAULT"]
    return (template:gsub("{spell}", link):gsub("{dungeon}", dungeonName))
end

function M:OnSpellCast(unit, spellID, castGUID)
    if unit ~= "player" then return end
    if not ns.db.profile.teleport.enabled then return end
    if not ShouldAnnounce() then return end
    -- Same cast can fire UNIT_SPELLCAST_START more than once (loading-screen
    -- edge cases, self-cast frame refreshes). Dedup by castGUID so a single
    -- cast only broadcasts once.
    if castGUID and castGUID == self._lastCastGUID then return end
    -- Defense in depth: a restarted cast carries a *new* castGUID (button
    -- double-activation, instant re-cast after cancel), so also suppress the
    -- same spell inside a short window. Teleport casts run ~10s, so 5s never
    -- swallows a legitimate separate cast announcement.
    local now = GetTime()
    if self._lastSpellID == spellID and now - (self._lastAnnounceAt or 0) < 5 then return end
    local msg = self:GenerateMessage(spellID)
    if not msg then return end
    self._lastCastGUID = castGUID
    self._lastSpellID = spellID
    self._lastAnnounceAt = now
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        SafeSendChatMessage(msg, "INSTANCE_CHAT")
    elseif IsInGroup() then
        SafeSendChatMessage(msg, "PARTY")
    end
end

function M:OnDBReady()
    BuildSpellToMap()
end

function M:OnPlayerLogin()
    TryInit()
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:RegisterEvent("LOADING_SCREEN_ENABLED")
    f:RegisterEvent("LOADING_SCREEN_DISABLED")
    -- Unit-filtered registration: UNIT_SPELLCAST_START otherwise fires for
    -- every party/raid/nameplate unit and runs this handler constantly.
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:SetScript("OnEvent", function(_, event, arg1, castGUID, spellID)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_ChallengesUI" then
            TryInit()
        elseif event == "LOADING_SCREEN_ENABLED" then
            M.isLoadingScreen = true
        elseif event == "LOADING_SCREEN_DISABLED" then
            M.isLoadingScreen = nil
        elseif event == "UNIT_SPELLCAST_START" then
            M:OnSpellCast(arg1, spellID, castGUID)
        end
    end)
end

function M:Refresh()
    CreateAll()
end
