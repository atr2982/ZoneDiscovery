local ADDON = ...
local DB
local frame
local cells = {}
local COLS, ROWS = 20, 12
local GAP = 2
local ZONE_AREA_TOTALS = {
    [1412] = 14, -- Mulgore: Explore Mulgore
    [1413] = 25, -- The Barrens: Explore The Barrens
}
local ZONE_LOCATIONS = {
    [1412] = {
        -- WoW Forever coordinates; Classic coordinates do not line up with the redrawn map.
        { "Red Cloud Mesa", 49.8, 83.8 },
        { "Palemane Rock", 35.1, 64.3 },
        { "Bloodhoof Village", 47.0, 62.4 },
        { "Winterhoof Water Well", 53.4, 70.4 },
        { "The Rolling Plains", 68.0, 67.6 },
        { "The Venture Co. Mine", 60.3, 54.7 },
        { "Ravaged Caravan", 52.2, 51.0 },
        { "The Golden Plains", 52.1, 39.6 },
        { "Thunderhorn Water Well", 42.4, 49.8 },
        { "Bael'dun Digsite", 33.0, 50.5 },
        { "Red Rocks", 59.8, 29.3 },
        { "Windfury Ridge", 52.8, 18.2 },
        { "Wildmane Water Well", 41.8, 20.7 },
        { "Thunder Bluff", 35.4, 34.2 },
    },
    [1413] = {
        { "Grol'dom Farm", 56.0, 19.0 },
        { "Boulder Lode Mine", 62.0, 7.0 },
        { "Field of Giants", 46.0, 71.0 },
        { "Camp Taurajo", 46.0, 61.0 },
        { "Far Watch Post", 61.0, 21.0 },
        { "Bramblescar", 51.0, 58.0 },
        { "The Dry Hills", 40.0, 15.0 },
        { "The Forgotten Pools", 45.0, 24.0 },
        { "Northwatch Hold", 61.0, 55.0 },
        { "Ratchet", 63.0, 37.0 },
        { "Blackthorn Ridge", 42.0, 79.0 },
        { "The Sludge Fen", 55.0, 7.0 },
        { "The Mor'shan Rampart", 48.0, 7.0 },
        { "Dreadmist Peak", 48.0, 18.0 },
        { "The Crossroads", 52.0, 28.0 },
        { "Lushwater Oasis", 47.0, 39.0 },
        { "Agama'gor", 43.0, 48.0 },
        { "Honor's Stand", 37.0, 28.0 },
        { "The Stagnant Oasis", 56.0, 43.0 },
        { "The Merchant Coast", 64.0, 45.0 },
        { "Bael Modan", 48.0, 84.0 },
        { "Razorfen Kraul", 41.0, 88.0 },
        { "Razorfen Downs", 49.0, 92.0 },
        { "Thorn Hill", 57.0, 28.0 },
        { "Raptor Grounds", 56.0, 51.0 },
    },
}

-- Replace the development fallback tables above with the generated Forever dataset.
-- The data file is built from Forever client map geometry and Forever exploration criteria.
if ForeverZoneDiscoveryData then
    ZONE_AREA_TOTALS = {}
    ZONE_LOCATIONS = {}
    for mapID, zoneData in pairs(ForeverZoneDiscoveryData) do
        ZONE_AREA_TOTALS[mapID] = zoneData.total
        ZONE_LOCATIONS[mapID] = zoneData.locations
    end
end

local function CurrentMap()
    if C_Map and C_Map.GetBestMapForUnit then
        return C_Map.GetBestMapForUnit("player")
    end
    return nil
end

local function MapName(mapID)
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or (GetZoneText() or "Unknown zone")
end

local CHILD_CHECKLIST_MAPS = {
    [1453] = 1429, -- Stormwind City -> Elwynn Forest
    [1454] = 1411, -- Orgrimmar -> Durotar
    [1455] = 1426, -- Ironforge -> Dun Morogh
    [1456] = 1412, -- Thunder Bluff -> Mulgore
    [1457] = 1438, -- Darnassus -> Teldrassil
    [1458] = 1420, -- Undercity -> Tirisfal Glades
}

local function ChecklistMap(mapID)
    -- Capitals and interiors are child maps, but Forever's exploration criteria
    -- belong to the surrounding zone (for example Orgrimmar -> Durotar).
    local candidate = mapID
    if CHILD_CHECKLIST_MAPS[candidate] then return CHILD_CHECKLIST_MAPS[candidate] end
    for _ = 1, 8 do
        if candidate and ZONE_LOCATIONS[candidate] then return candidate end
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(candidate)
        local parent = info and info.parentMapID
        if not parent or parent == candidate then break end
        candidate = parent
    end
    return mapID
end

local function AreaIDsAt(mapID, x, y)
    if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition then
        -- The Forever client expects a Vector2D position, not separate x/y values.
        local position
        if CreateVector2D then
            position = CreateVector2D(x, y)
        elseif Vector2D_Create then
            position = Vector2D_Create(x, y)
        end
        if not position then return nil end

        local ok, areas = pcall(C_MapExplorationInfo.GetExploredAreaIDsAtPosition, mapID, position)
        if not ok then return nil end
        if type(areas) == "number" then return { areas } end
        if type(areas) == "table" then return areas end
        return nil
    end
    return nil
end

local function IsExplored(mapID, x, y)
    local areas = AreaIDsAt(mapID, x, y)
    return areas and #areas > 0 or nil
end

local function LocationExplored(mapID, location)
    if not location[2] then return location[5] == true end
    local x, y = location[2] / 100, location[3] / 100
    -- A map pin is a landmark center, not necessarily the exact discovery trigger.
    -- Check a small ring around it so entering from any side is recognized.
    local offsets = {
        { 0, 0 }, { -0.025, 0 }, { 0.025, 0 }, { 0, -0.025 }, { 0, 0.025 },
        { -0.025, -0.025 }, { -0.025, 0.025 }, { 0.025, -0.025 }, { 0.025, 0.025 },
    }
    for _, offset in ipairs(offsets) do
        if IsExplored(mapID, x + offset[1], y + offset[2]) then return true end
    end
    return false
end

local function SetCell(cell, state, x, y)
    cell.state, cell.x, cell.y = state, x, y
    if state == true then
        cell.texture:SetColorTexture(0.18, 0.72, 0.26, 0.92)
    elseif state == false then
        cell.texture:SetColorTexture(0.78, 0.18, 0.16, 0.92)
    else
        cell.texture:SetColorTexture(0.35, 0.35, 0.35, 0.75)
    end
end

local function SetWaypoint(mapID, location)
    if location[4] then
        if C_Map and C_Map.OpenWorldMap then C_Map.OpenWorldMap(location[4]) end
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Zone Discovery: opened " .. tostring(location[1]))
        end
        return
    end
    local x, y = location[2] / 100, location[3] / 100
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local point = UiMapPoint.CreateFromCoordinates(mapID, x, y)
        local ok = pcall(C_Map.SetUserWaypoint, point)
        if ok and C_Map.OpenWorldMap then C_Map.OpenWorldMap(mapID) end
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Zone Discovery: %s — %.1f, %.1f", location[1], location[2], location[3]))
    end
end

local function DebugCurrentPosition()
    local mapID = CurrentMap()
    if not mapID then
        print("Zone Discovery: current map unavailable")
        return
    end
    local position = C_Map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
    local x, y
    if position then
        if position.GetXY then
            x, y = position:GetXY()
        else
            x, y = position.x, position.y
        end
    end
    local areas = x and AreaIDsAt(mapID, x, y) or nil
    local values = {}
    if areas then
        for _, areaID in ipairs(areas) do values[#values + 1] = tostring(areaID) end
    end
    print(string.format("Zone Discovery: map=%s position=%s,%s areas=%s", tostring(mapID), x and string.format("%.1f", x * 100) or "?", y and string.format("%.1f", y * 100) or "?", #values > 0 and table.concat(values, ", ") or "none"))
end

local function BuildDynamicLocations(mapID)
    if not (C_Map and C_Map.GetMapChildrenInfo) then return nil end
    local children = C_Map.GetMapChildrenInfo(mapID, nil, true)
    if type(children) ~= "table" or #children == 0 then return nil end

    local seen = {}
    for y = 1, 20 do
        for x = 1, 30 do
            local areas = AreaIDsAt(mapID, (x - 0.5) / 30, (y - 0.5) / 20)
            if areas then
                for _, areaID in ipairs(areas) do seen[areaID] = true end
            end
        end
    end

    local overlap = 0
    for _, child in ipairs(children) do
        if child.mapID and seen[child.mapID] then overlap = overlap + 1 end
    end
    if overlap == 0 then return nil end

    local locations = {}
    for _, child in ipairs(children) do
        if child.mapID and child.name then
            locations[#locations + 1] = { child.name, nil, nil, child.mapID, seen[child.mapID] == true }
        end
    end
    return locations
end

local function Refresh()
    if not frame then return end
    local currentMapID = CurrentMap()
    local mapID = ChecklistMap(currentMapID)
    frame.mapID = mapID
    frame.title:SetText("Zone Discovery")
    if currentMapID and mapID ~= currentMapID then
        frame.zone:SetText(MapName(currentMapID) .. "  |  checklist: " .. MapName(mapID))
    else
        frame.zone:SetText(mapID and (MapName(mapID) .. "  |  " .. tostring(mapID)) or "Current zone unavailable")
    end
    local target = mapID and ZONE_AREA_TOTALS[mapID]
    local locations = mapID and ZONE_LOCATIONS[mapID]
    local dynamic = false
    if not locations and mapID then
        locations = BuildDynamicLocations(mapID)
        dynamic = locations ~= nil
    end
    local missing = {}
    local foundLocations = 0
    if locations then
        for _, location in ipairs(locations) do
            local discovered = LocationExplored(mapID, location)
            if discovered then
                foundLocations = foundLocations + 1
            else
                if location[2] then
                    missing[#missing + 1] = string.format("%s  (%.1f, %.1f)", location[1], location[2], location[3])
                else
                    missing[#missing + 1] = location[1]
                end
            end
        end
    end
    if target or dynamic then
        local total = target or #locations
        local label = dynamic and "Client map areas" or "Explore areas"
        frame.status:SetText(string.format("%s: %d / %d  |  %d remaining", label, foundLocations, total, total - foundLocations))
        if #missing == 0 then
            frame.missing:SetText("Zone discovery complete. All named areas detected.")
            frame.missing:SetTextColor(0.25, 0.9, 0.35)
        else
            frame.missing:SetText("Click a location to place a map marker:")
            frame.missing:SetTextColor(0.95, 0.35, 0.25)
        end
        for i, button in ipairs(frame.locationButtons) do button:Hide() end
        if #missing > 0 then
            frame.listScroll:Show()
            local row = 0
            for _, location in ipairs(locations) do
                local discovered = LocationExplored(mapID, location)
                if not discovered then
                    row = row + 1
                    local button = frame.locationButtons[row]
                    if not button then
                        button = CreateFrame("Button", nil, frame.listContent, "BackdropTemplate")
                        button:SetSize(380, 18)
                        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        button.text:SetPoint("LEFT", 10, 0)
                        button.text:SetTextColor(1, 0.3, 0.2)
                        frame.locationButtons[row] = button
                    end
                    button:SetPoint("TOPLEFT", 0, -(row - 1) * 22)
                    if location[2] then
                        button.text:SetText(string.format("%s  (%.1f, %.1f)", location[1], location[2], location[3]))
                    else
                        button.text:SetText(location[1])
                    end
                    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = false })
                    button:SetBackdropColor(0.07, 0.085, 0.12, 0.9)
                    button.accent = button.accent or button:CreateTexture(nil, "ARTWORK")
                    button.accent:SetColorTexture(0.78, 0.24, 0.16, 1)
                    button.accent:SetPoint("TOPLEFT", 0, 0)
                    button.accent:SetPoint("BOTTOMLEFT", 0, 0)
                    button.accent:SetWidth(3)
                    button:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(0.18, 0.14, 0.06, 0.98)
                        self.accent:SetColorTexture(1.0, 0.82, 0.25, 1)
                        self.text:SetTextColor(1.0, 0.86, 0.4)
                    end)
                    button:SetScript("OnLeave", function(self)
                        self:SetBackdropColor(0.07, 0.085, 0.12, 0.9)
                        self.accent:SetColorTexture(0.78, 0.24, 0.16, 1)
                        self.text:SetTextColor(1, 0.3, 0.2)
                    end)
                    button:SetScript("OnClick", function() SetWaypoint(mapID, location) end)
                    button:Show()
                end
            end
            frame.listContent:SetHeight(math.max(frame.listScroll:GetHeight(), row * 22))
            frame.listContent:SetWidth(frame.listScroll:GetWidth())
            frame.listScroll:SetVerticalScroll(0)
        else
            frame.listScroll:Hide()
        end
    else
        frame.listScroll:Hide()
        frame.status:SetText("No named exploration checklist is installed for this zone yet.")
        frame.missing:SetText("No named location data is installed for this zone yet.")
    end
end

local function CreateCell(parent, index)
    local b = CreateFrame("Button", nil, parent)
    b.texture = b:CreateTexture(nil, "ARTWORK")
    b.texture:SetAllPoints()
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local status = self.state == true and "Discovered" or self.state == false and "Not discovered" or "Unavailable"
        GameTooltip:SetText(status .. string.format("\nMap position: %.1f%%, %.1f%%", self.x * 100, self.y * 100))
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    cells[index] = b
end

local function Create()
    frame = CreateFrame("Frame", "ZoneDiscoveryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 480)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", tile = false })
    frame:SetBackdropColor(0.025, 0.035, 0.055, 0.97)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 18, -14)
    frame.title:SetTextColor(1.0, 0.82, 0.28)
    frame.title:SetShadowOffset(1, -1)
    frame.close = CreateFrame("Button", nil, frame)
    frame.close:SetSize(28, 28)
    frame.close:SetPoint("TOPRIGHT", -10, -10)
    frame.close.label = frame.close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.close.label:SetPoint("CENTER", 0, 0)
    frame.close.label:SetText("×")
    frame.close.label:SetTextColor(0.55, 0.6, 0.68)
    frame.close:SetScript("OnClick", function() frame:Hide() end)
    frame.close:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 0.82, 0.25) end)
    frame.close:SetScript("OnLeave", function(self) self.label:SetTextColor(0.55, 0.6, 0.68) end)
    frame.zone = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.zone:SetPoint("TOPLEFT", 18, -42)
    frame.zone:SetTextColor(0.65, 0.72, 0.82)
    frame.rule = frame:CreateTexture(nil, "ARTWORK")
    frame.rule:SetColorTexture(0.72, 0.48, 0.14, 0.8)
    frame.rule:SetPoint("TOPLEFT", 18, -62)
    frame.rule:SetSize(404, 1)
    frame.topLine = frame:CreateTexture(nil, "ARTWORK")
    frame.topLine:SetColorTexture(0.12, 0.15, 0.2, 1)
    frame.topLine:SetPoint("TOPLEFT", 0, -1)
    frame.topLine:SetPoint("TOPRIGHT", 0, -1)
    frame.topLine:SetHeight(1)
    frame.bottomLine = frame:CreateTexture(nil, "ARTWORK")
    frame.bottomLine:SetColorTexture(0.12, 0.15, 0.2, 1)
    frame.bottomLine:SetPoint("BOTTOMLEFT", 0, 1)
    frame.bottomLine:SetPoint("BOTTOMRIGHT", 0, 1)
    frame.bottomLine:SetHeight(1)
    frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.status:SetPoint("TOPLEFT", 18, -72)
    frame.status:SetTextColor(0.35, 0.95, 0.48)
    frame.status:SetShadowOffset(1, -1)
    frame.missing = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.missing:SetPoint("TOPLEFT", 18, -96)
    frame.missing:SetWidth(404)
    frame.missing:SetJustifyH("LEFT")
    frame.missing:SetSpacing(2)
    frame.listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.listScroll:SetPoint("TOPLEFT", 18, -116)
    frame.listScroll:SetPoint("BOTTOMRIGHT", -34, 40)
    frame.listScroll:EnableMouseWheel(true)
    frame.listScroll:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * 36)))
    end)
    frame.listContent = CreateFrame("Frame", nil, frame.listScroll)
    frame.listContent:SetSize(380, 1)
    frame.listScroll:SetScrollChild(frame.listContent)
    frame.listScroll:Hide()
    frame.locationButtons = {}
    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("BOTTOMLEFT", 18, 14)
    frame.hint:SetTextColor(0.48, 0.54, 0.64)
    frame.hint:SetText("Click a location to set a waypoint  |  /zd toggles")
    Refresh()
    -- CreateFrame starts visible by default; keep the first slash-command toggle predictable.
    frame:Hide()
end

local function Toggle()
    if not frame then Create() end
    if frame:IsShown() then frame:Hide() else Refresh(); frame:Show() end
end

SLASH_ZONEDISCOVERY1 = "/zd"
SlashCmdList.ZONEDISCOVERY = function(message)
    if message and string.lower(message) == "debug" then
        DebugCurrentPosition()
    else
        Toggle()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("MAP_EXPLORATION_UPDATED")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ZoneDiscoveryDB = ZoneDiscoveryDB or {}
        DB = ZoneDiscoveryDB
    elseif event ~= "ADDON_LOADED" and frame and frame:IsShown() then
        Refresh()
    end
end)
