local addonName, ns = ...

local M = {}
ns:RegisterModule("keystoneList", M)

local REFRESH_INTERVAL = 3.0
local ICON_SIZE        = 42
local ICON_TEXT_GAP    = 8
local FALLBACK_ICON    = [[Interface\Icons\INV_Misc_Key_14]]

M.rows = {}

local function GetLibOpenRaid()
    return _G.LibStub and _G.LibStub("LibOpenRaid-1.0", true)
end

local function ClassColor(classID)
    if not classID then return { r = 1, g = 1, b = 1 } end
    local classFile = select(2, GetClassInfo(classID))
    return classFile and RAID_CLASS_COLORS[classFile] or { r = 1, g = 1, b = 1 }
end

local function LevelColor(level)
    local colors = ns.db.profile.colors.levelColors
    if not level or level <= 0 then return colors[0] end
    local add = level >= 15 and 1 or 0
    local idx = math.min(math.floor((math.max(level, 2) - 2) / 2), 5) + add
    return colors[idx] or colors[0]
end

local function EnsureFrame()
    if M.frame then return M.frame end
    local f = CreateFrame("Frame", "MythicPlusBoxKeystoneListFrame", UIParent, "BackdropTemplate")
    f:SetSize(320, 200)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ns.db.profile.keystoneList.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        local anchor = ns.db.profile.keystoneList.anchor
        anchor.point         = point
        anchor.relativeTo    = "UIParent"
        anchor.relativePoint = relativePoint
        anchor.x             = x
        anchor.y             = y
        if ns.RefreshOptionsUI then ns:RefreshOptionsUI() end
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0, 0, 0, 0.5)
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)

    M.frame = f
    M:ApplyAnchor()
    return f
end

function M:ApplyAnchor()
    if not self.frame then return end
    local a = ns.db.profile.keystoneList.anchor
    local relTo = _G[a.relativeTo] or UIParent
    self.frame:ClearAllPoints()
    self.frame:SetPoint(a.point, relTo, a.relativePoint, a.x, a.y)
end

local function CurrentFont()
    local cfg = ns.db.profile.keystoneList
    return ns:GetFont({
        name    = cfg.font.name,
        size    = cfg.font.size,
        outline = ns.db.profile.font.outline,
    })
end

--- Tooltip header for a row overlay: the keystone's dungeon plus a hint that
--- the row is clickable. Teleport spell name and cooldown are appended by
--- ns:ShowTeleportTooltip.
local function RowTooltipHeader(button)
    local L = ns.L
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns:GetDungeonName(button:GetParent().mapID, false))
    if button.spellKnown then
        GameTooltip:AddLine(L["TELEPORT_CLICK_HINT"], 0.6, 0.6, 0.6)
    end
end

-- The click-to-teleport overlay covers the whole row so the entire entry is a
-- teleport target, not just its icon. Action buttons cannot be created while
-- in combat, so creation is deferred to the next out-of-combat refresh
-- (PLAYER_REGEN_ENABLED triggers one).
local function EnsureTeleportButton(row)
    if row.teleport then return row.teleport end
    if InCombatLockdown() then return nil end

    local button = CreateFrame("Button", nil, row, "InsecureActionButtonTemplate")
    button:SetAllPoints(row)
    button:SetFrameLevel(row:GetFrameLevel() + 2)

    -- HIGHLIGHT-layer textures are shown by the frame itself on mouseover;
    -- ADD blending keeps the row's text readable through the glow.
    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(button)
    hl:SetColorTexture(1, 1, 1, 0.15)
    hl:SetBlendMode("ADD")

    button:SetScript("OnEnter", function(self)
        ns:ShowTeleportTooltip(self, self.spellID, RowTooltipHeader)
    end)
    button:SetScript("OnLeave", function(self)
        ns:HideTeleportTooltip(self)
    end)

    row.teleport = button
    return button
end

local function UpdateRowTeleport(row, cfg)
    -- Action attributes cannot be rewritten in combat: the overlay keeps
    -- whatever it was armed with before the pull and re-syncs afterwards.
    if InCombatLockdown() then return end

    local spellID, known = ns:GetTeleportSpell(row.mapID)
    -- An unlocked frame is being dragged, so the overlay must not swallow the
    -- clicks that move it.
    local usable = cfg.locked and spellID ~= nil
    local button = usable and EnsureTeleportButton(row) or row.teleport
    if not button then return end
    if not usable then
        button:Hide()
        return
    end

    button.spellID    = spellID
    button.spellKnown = known
    -- Match the user's cast-on-key-down cvar: registering both edges fires the
    -- cast twice, which restarts it and makes the teleport announce double up.
    button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
    button:SetAttribute("type",  known and "spell" or nil)
    button:SetAttribute("spell", known and spellID or nil)
    button:Show()
end

local function GetRow(index)
    if M.rows[index] then return M.rows[index] end
    local row = CreateFrame("Frame", nil, M.frame)
    row:SetHeight(ICON_SIZE)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)
    row.icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    row.iconBorder = row:CreateTexture(nil, "BORDER")
    row.iconBorder:SetColorTexture(0, 0, 0, 0.6)
    row.iconBorder:SetPoint("TOPLEFT",     row.icon, "TOPLEFT",     -1, 1)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT",  1, -1)

    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.level:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
    row.level:SetJustifyH("CENTER")
    row.level:SetFont(CurrentFont())

    row.dungeon = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.dungeon:SetPoint("TOPLEFT",  row.icon, "TOPRIGHT", ICON_TEXT_GAP, -4)
    row.dungeon:SetPoint("RIGHT",    row,      "RIGHT",    -6, 0)
    row.dungeon:SetJustifyH("LEFT")
    row.dungeon:SetFont(CurrentFont())

    row.holder = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.holder:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", ICON_TEXT_GAP, 4)
    row.holder:SetPoint("RIGHT",      row,      "RIGHT",       -6, 0)
    row.holder:SetJustifyH("LEFT")
    row.holder:SetFont(CurrentFont())

    M.rows[index] = row
    return row
end

local function HideExtraRows(fromIndex)
    for i = fromIndex, #M.rows do
        if M.rows[i] then M.rows[i]:Hide() end
    end
end

local function PartyUnitIDs()
    local ids = { "player" }
    if IsInGroup(LE_PARTY_CATEGORY_HOME) and not IsInRaid() then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party" .. i
            if UnitExists(unit) then table.insert(ids, unit) end
        end
    end
    return ids
end

local function KeystoneForUnit(lib, unitId)
    if unitId == "player" then
        local _, _, classID = UnitClass("player")
        return {
            level          = C_MythicPlus.GetOwnedKeystoneLevel() or 0,
            challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0,
            classID        = classID,
        }
    end
    if lib and lib.GetKeystoneInfo then
        local info = lib.GetKeystoneInfo(unitId)
        if info then
            return {
                level          = info.level or 0,
                challengeMapID = info.challengeMapID or info.mapID or 0,
                classID        = info.classID,
                rating         = info.rating,
            }
        end
    end
    local _, _, classID = UnitClass(unitId)
    return { level = 0, challengeMapID = 0, classID = classID }
end

local function CollectPartyKeystones()
    local result = {}
    local lib = GetLibOpenRaid()
    local cfg = ns.db.profile.keystoneList
    for _, unitId in ipairs(PartyUnitIDs()) do
        local info = KeystoneForUnit(lib, unitId)
        local isPlayer = (unitId == "player")
        -- The player row is always kept (with a placeholder when they have no
        -- keystone) so unlocking the frame in solo previews still has content.
        if info.level > 0 or isPlayer then
            table.insert(result, {
                unitName       = UnitName(unitId) or unitId,
                level          = info.level,
                challengeMapID = info.challengeMapID,
                classID        = info.classID,
                rating         = info.rating,
                isPlayer       = isPlayer,
            })
        end
    end
    table.sort(result, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        return (a.unitName or "") < (b.unitName or "")
    end)
    return result
end

local function DungeonIconTexture(mapID)
    if not mapID or mapID == 0 then return FALLBACK_ICON end
    if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local _, _, _, tex = C_ChallengeMode.GetMapUIInfo(mapID)
        if tex and tex ~= 0 then return tex end
    end
    return FALLBACK_ICON
end

local function LayoutRows()
    local L = ns.L
    local cfg = ns.db.profile.keystoneList
    local path, size, outline = ns:GetFont({ name = cfg.font.name, size = cfg.font.size, outline = ns.db.profile.font.outline })
    local useAbbr = ns.db.profile.score and ns.db.profile.score.useAbbreviation

    local list = CollectPartyKeystones()
    local rowH  = ICON_SIZE
    local gap   = math.max(cfg.rowSpacing or 4, 4)
    local pad   = 8

    local levelSize = math.max(math.floor(ICON_SIZE * 0.55), size + 2)
    for i, entry in ipairs(list) do
        local row = GetRow(i)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT", M.frame, "TOPLEFT", pad, -pad)
        else
            row:SetPoint("TOPLEFT", M.rows[i - 1], "BOTTOMLEFT", 0, -gap)
        end
        row:SetPoint("RIGHT", M.frame, "RIGHT", -pad, 0)
        row:SetHeight(rowH)
        row:Show()

        row.icon:SetTexture(DungeonIconTexture(entry.challengeMapID))
        row.iconBorder:Show()

        row.level:SetFont(path, levelSize, "THICKOUTLINE")
        row.dungeon:SetFont(path, size, outline)
        row.holder:SetFont(path, size, outline)

        if entry.level > 0 then
            row.level:SetText("|c" .. LevelColor(entry.level) .. "+" .. entry.level .. "|r")
            row.dungeon:SetText(ns:GetDungeonName(entry.challengeMapID, useAbbr))
        else
            row.level:SetText("|cff9d9d9d-|r")
            row.dungeon:SetText("|cff9d9d9d" .. L["KEYSTONE_NONE"] .. "|r")
        end

        local c = ClassColor(entry.classID)
        row.holder:SetText(string.format("|cff%02x%02x%02x%s|r",
            c.r * 255, c.g * 255, c.b * 255,
            Ambiguate(entry.unitName or "?", "short")))

        row.mapID = entry.challengeMapID
        UpdateRowTeleport(row, cfg)
    end

    HideExtraRows(#list + 1)
    local rowCount = math.max(#list, 1)
    M.frame:SetHeight(pad * 2 + rowH * rowCount + gap * math.max(rowCount - 1, 0))
end

local function ShouldShow(cfg)
    if not cfg.enabled then return false end
    -- Unlocked: keep the frame on screen so the user can drag it into place,
    -- even outside a party or dungeon (a "self keystone" preview row is shown).
    if not cfg.locked then return true end
    if not IsInGroup(LE_PARTY_CATEGORY_HOME) then return false end
    if IsInRaid() then return false end
    if M.inActiveRun then return false end
    return true
end

function M:Refresh()
    if not self.frame then return end
    local cfg = ns.db.profile.keystoneList
    if not ShouldShow(cfg) then self.frame:Hide(); return end
    self.frame:Show()
    self.frame:EnableMouse(not cfg.locked)
    -- Backdrop is only visible while the frame is unlocked so users have a
    -- visual target to click and drag. In normal play the list floats with
    -- no frame around it.
    if cfg.locked then
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
    else
        self.frame:SetBackdropColor(0, 0, 0, 0.5)
        self.frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
    end
    self:ApplyAnchor()
    LayoutRows()
end

function M:OnPlayerLogin()
    EnsureFrame()

    local lib = GetLibOpenRaid()
    if lib and lib.RequestKeystoneDataFromParty then
        lib.RequestKeystoneDataFromParty()
    end
    if lib and lib.RegisterCallback then
        lib.RegisterCallback(M, "KeystoneUpdate", "OnKeystoneUpdate")
    end

    local f = CreateFrame("Frame")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("CHALLENGE_MODE_RESET")
    -- Teleport overlays cannot be created or re-armed during combat; refresh
    -- once the lockdown lifts so they come back without waiting on a roster
    -- or bag event.
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "CHALLENGE_MODE_START" then
            M.inActiveRun = true
            M:Refresh()
        elseif event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET" then
            M.inActiveRun = false
            M:Refresh()
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- Roster updates arrive in bursts while a group forms; debounce so
            -- one settled update sends a single keystone comm request instead
            -- of one per event.
            if M._rosterPending then return end
            M._rosterPending = true
            C_Timer.After(1, function()
                M._rosterPending = nil
                local l = GetLibOpenRaid()
                if l and l.RequestKeystoneDataFromParty then
                    l.RequestKeystoneDataFromParty()
                end
                M:Refresh()
            end)
        elseif event == "PLAYER_ENTERING_WORLD" then
            local _, instanceType = GetInstanceInfo()
            local activeLevel = C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo
                                and C_ChallengeMode.GetActiveKeystoneInfo() or 0
            M.inActiveRun = (instanceType == "party" and activeLevel > 0) or false
            M:Refresh()
        else
            M:Refresh()
        end
    end)

    local accum = 0
    self.frame:SetScript("OnUpdate", function(_, elapsed)
        accum = accum + elapsed
        if accum >= REFRESH_INTERVAL then
            accum = 0
            M:Refresh()
        end
    end)

    M:Refresh()
end

function M:OnKeystoneUpdate()
    M:Refresh()
end
