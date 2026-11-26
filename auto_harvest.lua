-- ============================================================================
-- GLOBAL ENGINE FORWARD DECLARATIONS (SAFETY FALLBACK)
-- ============================================================================
_G.checkAndDropIfFull = function(...)
    if checkAndDropIfFull then return checkAndDropIfFull(...) end
    return true
end
_G.updateInvPreview = function(...)
    if updateInvPreview then return updateInvPreview(...) end
end
-- ============================================================================
-- BOREN STORE - AUTO HARVEST PRO (STANDALONE SCRIPT)
-- File: script/script code/auto_harvest.lua
-- Repo: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- Fitur:
--   1. Multi-World Farm List (WORLD:DOOR:ITEM_ID) + Item ID Harvest (auto Block & Seed ID)
--   2. Multi-World Save Block/Seed Table (pilihan ALL / BLOCK / SEED) + Limit per World (10k/20k/Custom)
--      + Posisi drop rapi (skip White Door/Lock, otomatis pindah baris & tile)
--   3. Ignore Gems (blokir collect Gems ID 112 via onSendPacketRaw)
--   4. Mode 3-Zigzag Serpentine & 1-by-1
--   5. Auto Collect Block & Seed hasil harvest
--   6. Multi-World Save khusus Event / Mooncake dengan Limit Total Item
--   7. Custom List ID Item Event (Mooncake default 1058,1094,1096,1098,1828)
--   8. Unified Magni + Fuel Pack (1252 & 1746) + Gear Equip ID List (DCS 6840 / Harvester 1966/1830)
--   9. Opsional Take Floating (sapu sisa block/seed/event setelah pohon habis)
--  10. Dual UI: Dear ImGui Standalone Window + Native Growlauncher 5-Tab Menu
-- ============================================================================


local function sendPacketSafe(t, str)
    local fn = sendPacket or SendPacket
    if fn and type(fn) == "function" then
        local ok = pcall(fn, t, str)
        if ok then return true end
    end
    if growtopia and growtopia.sendPacket then
        local ok = pcall(growtopia.sendPacket, t, str)
        if ok then return true end
    end
    return false
end

local function resolveItemName(itemID)
    local id = tonumber(itemID) or 0
    if id <= 0 then return "None" end
    if getItemInfo and type(getItemInfo) == "function" then
        local ok, info = pcall(getItemInfo, id)
        if ok and info and info.name and info.name ~= "" then return tostring(info.name) end
    end
    if growtopia and growtopia.getItemName then
        local ok, nm = pcall(growtopia.getItemName, id)
        if ok and nm and nm ~= "" then return tostring(nm) end
    end
    return "ID " .. tostring(id)
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN HARVEST] `w" .. tostring(msg)) end
end

local function notifyMsg(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end
local HV = {
    id      = "harvest",
    label   = "Harvest",
    VERSION = "1.2.0",
    META    = {
        type    = "boren_gl_feature",
        id      = "harvest",
        label   = "Harvest",
        order   = 15,
        enabled = true,
    },
}

HV.CFG = {
    default_item_id    = 4584,          -- Block genap / Seed ganjil (auto pair)
    drop_threshold     = 200,           -- Default 200 block (permintaan user)
    default_save_limit = 20000,         -- Default limit save world
    default_ev_limit   = 10000,         -- Default limit event world
    ignore_gems        = true,          -- Blokir collect Gems (ID 112)
    ignore_take_drop   = true,          -- Ignore take block/seed saat drop di save/event world
    harvest_mode       = "1by1",        -- "1by1" (Default: Halus & Cepat 1 Tree) | "3zigzag"
    harvest_delay      = 70,
    step_delay         = 45,
    warp_delay         = 4500,
    use_modfly         = true,
    loop_enabled       = false,
    auto_collect       = true,
    collect_range      = 4,
    take_block         = true,          -- Opsi ambil block hasil panen sesuai ID
    take_seed          = true,          -- Opsi ambil seed hasil panen sesuai ID,
    event_ids_raw      = "1058,1094,1096,1098,1828", -- Mooncakes default
    event_threshold    = 150,
    gear_world         = "",            -- 1 world khusus Magni / Fuel Pack / Gear
    auto_magni_fuel    = false,         -- Auto ambil Magni (1252) & Fuel Pack (1746)
    fuel_target_amt    = 100,
    stop_if_no_fuel    = true,          -- Proteksi: stop aman jika Fuel Pack habis di tas & Gear World
    gear_equip_ids     = "6840, 1966",  -- List ID alat/gear to equip (DCS, Harvester, dll.)
    use_dcs_harvester  = false,          -- Default OFF: Gunakan DCS & Harvester (Hand/Back)
    take_floating      = true,          -- Sapu sisa block/seed/event setelah tree habis
}

HV.STATE = {
    enabled          = false,
    running          = false,
    status_text      = "Idle",
    rows             = {},              -- { { name="W", door="D", item_id=4584, status="Ready" }, ... }
    selected_idx     = 0,
    save_rows        = {},              -- { { name="W", door="D", save_type="ALL"|"BLOCK"|"SEED", limit=20000, count=0, status="Ready" }, ... }
    selected_save    = 0,
    event_rows       = {},              -- { { name="W", door="D", limit=10000, count=0, status="Ready" }, ... }
    selected_ev      = 0,
    in_save_world    = false,
    in_event_world   = false,
    anti_take        = false,
    is_dropping      = false,
    pending_drop_id  = 0,
    pending_drop_amt = 0,
    drop_confirmed   = false,
    need_fuel        = false,
    total_harvested  = 0,
    total_dropped    = 0,
    logs             = {},
    inv_preview      = { block = 0, seed = 0, ev = 0, fuel = 0 },
}

local HUB_REF = nil
local activeSub = "farms"

-- UI Buffers
local addFarmWorldBuf = ""
local addFarmItemBuf  = "4584"

local addSaveWorldBuf = ""
local addSaveTypeBuf  = "ALL"           -- "ALL" | "BLOCK" | "SEED"
local addSaveLimitBuf = "20000"

local addEventWorldBuf = ""
local addEventLimitBuf = "10000"

local uiNotice    = ""
local CACHED_PATH = nil

-- ============================================================================
-- 1. ITEM IDs & SAFE HELPERS
-- ============================================================================
local ITEM = {
    PUNCH     = 18,
    MAIN_DOOR = 6,
    DOOR      = 8,
    GEMS      = 112,
    MAGNI     = 1252,
    DCS       = 6840,
    HARVESTER = 1830,
    SORROWS   = 1966,
    FUEL_PACK = 1746,
}

local LOCK_OR_DOOR_IDS = {
    [6] = true, [8] = true, [12] = true, [30] = true, [60] = true, [202] = true, [204] = true,
    [206] = true, [224] = true, [226] = true, [242] = true, [544] = true, [546] = true,
    [1796] = true, [2810] = true, [4428] = true, [4802] = true, [4994] = true, [7188] = true,
}

local function trimStr(s)
    local res = tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return res
end

local function cleanWorldName(s)
    return trimStr(s):gsub("[^%w_]", ""):upper()
end

local function normalizeHarvestPair(itemID)
    local id = tonumber(itemID) or 4584
    if id <= 0 then id = 4584 end
    if id % 2 == 1 then return id - 1, id end
    return id, id + 1
end

local function addLog(msg)
    local clean = tostring(msg or ""):gsub("`[0-9a-zA-Z!]", "")
    local ts = ""
    if os and os.date then
        local okD, d = pcall(os.date, "[%H:%M:%S] ")
        if okD and d then ts = d end
    end
    local entry = ts .. "[HARVEST] " .. clean
    table.insert(HV.STATE.logs, 1, entry)
    if #HV.STATE.logs > 60 then table.remove(HV.STATE.logs) end
    if HUB_REF and HUB_REF.addLog then HUB_REF.addLog(entry) end
end

local function safeSleep(ms)
    local d = tonumber(ms) or 100
    if Sleep then pcall(Sleep, d)
    elseif sleep then pcall(sleep, d) end
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

-- ============================================================================
-- 2. PERSISTENCE (SAVE / LOAD KONFIGURASI & WORLD LISTS)
-- ============================================================================
local function isSystemWindows()
    if package and package.config and package.config:sub(1, 1) == "\\" then return true end
    if os and type(os.getenv) == "function" then
        local ok, env = pcall(os.getenv, "OS")
        if ok and env and tostring(env):lower():find("windows", 1, true) then return true end
    end
    return false
end

local function splitColons(str)
    local parts = {}
    for seg in (tostring(str or "") .. ":"):gmatch("([^:]*):") do
        table.insert(parts, trimStr(seg))
    end
    if #parts > 0 and parts[#parts] == "" then
        table.remove(parts)
    end
    return parts
end

local function getStorageCandidates(customFn)
    local fn = customFn or "boren_hub_harvest_data.txt"
    if isSystemWindows() then
        return { fn, "script/" .. fn, "script/dialog/harvest/" .. fn }
    end
    return {
        "/storage/emulated/0/Download/" .. fn,
        "/sdcard/Download/" .. fn,
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/" .. fn,
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/" .. fn,
        fn,
        "script/" .. fn,
        "script/dialog/harvest/" .. fn,
    }
end

local function readStorageContent(customFn)
    local fn = customFn or "boren_hub_harvest_data.txt"
    -- 0. Coba baca dari saved:get jika tersedia
    if saved and saved.get and fn == "boren_hub_harvest_data.txt" then
        local ok, sVal = pcall(function() return saved:get("boren_harvest_hub_data", "") end)
        if ok and type(sVal) == "string" and (sVal:find("ROW=", 1, true) or #sVal > 15) then
            return sVal
        end
    end

    local candidates = getStorageCandidates(fn)
    -- 1. Baca via readFile native GrowLauncher jika tersedia
    if readFile and type(readFile) == "function" then
        for _, path in ipairs(candidates) do
            local ok, txt = pcall(readFile, path)
            if ok and type(txt) == "string" and (txt:find("ROW=", 1, true) or #txt > 10) then
                return txt
            end
        end
    end
    -- 2. Baca via io.open
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "r")
            if ok and f then
                local txt = nil
                pcall(function() txt = f:read("*a"); f:close() end)
                if txt and type(txt) == "string" and (txt:find("ROW=", 1, true) or #txt > 10) then
                    return txt
                end
            end
        end
    end
    -- 3. Fallback: baca file apa pun yang berhasil terbuka dan tidak kosong
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "r")
            if ok and f then
                local txt = nil
                pcall(function() txt = f:read("*a"); f:close() end)
                if txt and type(txt) == "string" and txt ~= "" then
                    return txt
                end
            end
        end
    end
    return nil
end

local function writeStorageContent(content, customFn)
    local fn = customFn or "boren_hub_harvest_data.txt"
    local candidates = getStorageCandidates(fn)
    local wroteAny = false

    -- 1. Tulis via native writeFile jika tersedia di engine
    if writeFile and type(writeFile) == "function" then
        for _, path in ipairs(candidates) do
            local ok = pcall(writeFile, path, content)
            if ok then wroteAny = true end
        end
    end
    if writeToLocal and type(writeToLocal) == "function" then
        pcall(writeToLocal, fn, content)
        wroteAny = true
    end

    -- 2. Tulis via io.open ke seluruh direktori yang dapat diakses (Download HP, media, local)
    if io and io.open then
        for _, path in ipairs(candidates) do
            local ok, f = pcall(io.open, path, "w")
            if ok and f then
                pcall(function()
                    f:write(content .. "\n")
                    f:close()
                end)
                wroteAny = true
            end
        end
    end

    -- 3. Simpan juga ke saved:set jika tersedia di Growlauncher
    if saved and saved.set and fn == "boren_hub_harvest_data.txt" then
        pcall(function()
            saved:set("boren_harvest_hub_data", content)
            if saved.save then saved:save() end
        end)
    end

    return wroteAny
end

local function getDataPath()
    local candidates = getStorageCandidates()
    for _, path in ipairs(candidates) do
        local ok, f = pcall(io.open, path, "r")
        if ok and f then f:close(); return path end
    end
    for _, path in ipairs(candidates) do
        local ok, f = pcall(io.open, path, "a")
        if ok and f then f:close(); return path end
    end
    return "boren_hub_harvest_data.txt"
end

local function parseWorldDoor(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    return { name = w, door = door }
end

local function parseWorldList(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,\r\n;]+") do
        local p = parseWorldDoor(tok)
        if p then table.insert(list, p) end
    end
    return list
end

local function parseFarmRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local iid = math.floor(tonumber(parts[3]) or tonumber(HV.CFG.default_item_id) or 4584)
    if iid <= 0 then iid = 4584 end
    return { name = w, door = door, item_id = iid, status = "Ready" }
end

local function parseSaveRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local stype = (parts[3] or "ALL"):upper()
    if stype ~= "BLOCK" and stype ~= "SEED" and stype ~= "ALL" then
        local n = tonumber(stype)
        if n then
            local lim = math.floor(n)
            return { name = w, door = door, save_type = "ALL", limit = lim, count = 0, status = "Ready" }
        end
        stype = "ALL"
    end
    local lim = tonumber(parts[4]) or tonumber(HV.CFG.default_save_limit) or 20000
    local cur = tonumber(parts[5]) or 0
    return { name = w, door = door, save_type = stype, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventRow(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local parts = splitColons(s)
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local lim = tonumber(parts[3]) or tonumber(HV.CFG.default_ev_limit) or 10000
    local cur = tonumber(parts[4]) or 0
    return { name = w, door = door, limit = math.max(0, math.floor(lim)), count = cur, status = "Ready" }
end

local function parseEventIDs()
    local map, list = {}, {}
    for tok in tostring(HV.CFG.event_ids_raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 and not map[id] then map[id] = true; table.insert(list, id) end
    end
    return list, map
end

local function parseEquipIDs(raw)
    local list = {}
    for tok in tostring(raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 then table.insert(list, id) end
    end
    return list
end

function HV.saveData()
    local c = HV.CFG
    local lines = {
        "DEFID="    .. tostring(c.default_item_id),
        "DROPTH="   .. tostring(c.drop_threshold or 200),
        "SAVELIM="  .. tostring(c.default_save_limit or 20000),
        "EVLIM="    .. tostring(c.default_ev_limit or 10000),
        "IGEMS="    .. (c.ignore_gems and "1" or "0"),
        "MODE="     .. tostring(c.harvest_mode),
        "HDELAY="   .. tostring(c.harvest_delay),
        "SDELAY="   .. tostring(c.step_delay),
        "MODFLY="   .. (c.use_modfly and "1" or "0"),
        "LOOP="     .. (c.loop_enabled and "1" or "0"),
        "ACOL="     .. (c.auto_collect and "1" or "0"),
        "EVIDS="    .. tostring(c.event_ids_raw or ""),
        "EVTH="     .. tostring(c.event_threshold),
        "GEARW="    .. tostring(c.gear_world or ""),
        "AMAGFUEL=" .. (c.auto_magni_fuel and "1" or "0"),
        "USEDCS="   .. (c.use_dcs_harvester and "1" or "0"),
        "GEAREQUIP=".. tostring(c.gear_equip_ids or ""),
        "FUELAMT="  .. tostring(c.fuel_target_amt),
        "STPFUEL="  .. (c.stop_if_no_fuel and "1" or "0"),
        "FLOAT="    .. (c.take_floating and "1" or "0"),
        "TAKEBLOCK=".. (c.take_block ~= false and "1" or "0"),
        "TAKESEED=" .. (c.take_seed ~= false and "1" or "0"),
        "IGNTAKEDROP=" .. (c.ignore_take_drop ~= false and "1" or "0"),
    }

    local farmBackupLines = {}
    for _, r in ipairs(HV.STATE.rows) do
        table.insert(lines, string.format("ROW=%s:%s:%d|%s", r.name, r.door or "", r.item_id or c.default_item_id, r.status or "Ready"))
        table.insert(farmBackupLines, string.format("%s:%s:%d", r.name, r.door or "", r.item_id or c.default_item_id))
    end

    local saveBackupLines = {}
    for _, r in ipairs(HV.STATE.save_rows) do
        table.insert(lines, string.format("SAVEROW=%s:%s:%s:%d:%d|%s", r.name, r.door or "", r.save_type or "ALL", r.limit or 20000, r.count or 0, r.status or "Ready"))
        table.insert(saveBackupLines, string.format("%s:%s:%s:%d", r.name, r.door or "", r.save_type or "ALL", r.limit or 20000))
    end

    for _, r in ipairs(HV.STATE.event_rows) do
        table.insert(lines, string.format("EVROW=%s:%s:%d:%d|%s", r.name, r.door or "", r.limit or 10000, r.count or 0, r.status or "Ready"))
    end

    local textContent = table.concat(lines, "\n")
    writeStorageContent(textContent, "boren_hub_harvest_data.txt")

    -- Backup cadangan agar world list tidak pernah hilang
    if #farmBackupLines > 0 then
        writeStorageContent(table.concat(farmBackupLines, "\n"), "boren_harvest_farms.txt")
    end
    if #saveBackupLines > 0 then
        writeStorageContent(table.concat(saveBackupLines, "\n"), "boren_harvest_storages.txt")
    end
end

function HV.loadData()
    local txt = readStorageContent()
    if not txt or txt == "" then return end
    local c = HV.CFG

    local loadedRows, loadedSaveRows, loadedEventRows = {}, {}, {}
    local legacySaveStr, legacyEventStr = "", ""

    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "DEFID" then c.default_item_id = tonumber(v) or 4584
        elseif k == "DROPTH" then c.drop_threshold = tonumber(v) or 200
        elseif k == "SAVELIM" then c.default_save_limit = tonumber(v) or 20000
        elseif k == "EVLIM" then c.default_ev_limit = tonumber(v) or 10000
        elseif k == "IGEMS" then c.ignore_gems = (v ~= "0")
        elseif k == "MODE" and (v == "teleport" or v == "3zigzag" or v == "1by1") then c.harvest_mode = v
        elseif k == "HDELAY" then c.harvest_delay = tonumber(v) or 180
        elseif k == "SDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "LOOP" then c.loop_enabled = (v == "1")
        elseif k == "ACOL" then c.auto_collect = (v ~= "0")
        elseif k == "EVIDS" then c.event_ids_raw = trimStr(v)
        elseif k == "EVTH" then c.event_threshold = tonumber(v) or 150
        elseif k == "GEARW" then c.gear_world = trimStr(v)
        elseif k == "AMAGFUEL" then c.auto_magni_fuel = (v == "1")
        elseif k == "USEDCS" then c.use_dcs_harvester = (v == "1")
        elseif k == "GEAREQUIP" then c.gear_equip_ids = trimStr(v)
        elseif k == "FUELAMT" then c.fuel_target_amt = tonumber(v) or 100
        elseif k == "STPFUEL" then c.stop_if_no_fuel = (v ~= "0")
        elseif k == "FLOAT" then c.take_floating = (v ~= "0")
        elseif k == "TAKEBLOCK" then c.take_block = (v ~= "0")
        elseif k == "TAKESEED"  then c.take_seed  = (v ~= "0")
        elseif k == "IGNTAKEDROP" then c.ignore_take_drop = (v ~= "0")
        elseif k == "MAGNI" or k == "FUEL" then if v == "1" then c.auto_magni_fuel = true end
        elseif k == "SAVEW" then legacySaveStr = trimStr(v)
        elseif k == "EVW" then legacyEventStr = trimStr(v)
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseFarmRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedRows, p) end
        elseif k == "SAVEROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseSaveRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedSaveRows, p) end
        elseif k == "EVROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseEventRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(loadedEventRows, p) end
        end
    end

    -- Migrasi format legacy ke list tables bila sebelumnya berupa string
    if #loadedSaveRows == 0 and legacySaveStr ~= "" then
        for _, sw in ipairs(parseWorldList(legacySaveStr)) do
            table.insert(loadedSaveRows, { name = sw.name, door = sw.door or "", save_type = "ALL", limit = c.default_save_limit, count = 0, status = "Ready" })
        end
    end
    if #loadedEventRows == 0 and legacyEventStr ~= "" then
        for _, ew in ipairs(parseWorldList(legacyEventStr)) do
            table.insert(loadedEventRows, { name = ew.name, door = ew.door or "", limit = c.default_ev_limit, count = 0, status = "Ready" })
        end
    end

    -- Fallback cadangan: Jika loadedRows kosong, coba baca dari boren_harvest_farms.txt
    if #loadedRows == 0 then
        local rawFarms = readStorageContent("boren_harvest_farms.txt")
        if rawFarms and rawFarms ~= "" then
            for line in rawFarms:gmatch("[^\r\n]+") do
                local p = parseFarmRow(line)
                if p then table.insert(loadedRows, p) end
            end
        end
    end

    -- Fallback cadangan: Jika loadedSaveRows kosong, coba baca dari boren_harvest_storages.txt
    if #loadedSaveRows == 0 then
        local rawSaves = readStorageContent("boren_harvest_storages.txt")
        if rawSaves and rawSaves ~= "" then
            for line in rawSaves:gmatch("[^\r\n]+") do
                local p = parseSaveRow(line)
                if p then table.insert(loadedSaveRows, p) end
            end
        end
    end

    -- Update state HANYA jika hasil load berisi data valid (JANGAN hapus antrean di memori jika file kosong!)
    if #loadedRows > 0 then
        HV.STATE.rows = loadedRows
    end
    if #loadedSaveRows > 0 then
        HV.STATE.save_rows = loadedSaveRows
    end
    if #loadedEventRows > 0 then
        HV.STATE.event_rows = loadedEventRows
    end

    addFarmItemBuf   = tostring(c.default_item_id)
    addSaveLimitBuf  = tostring(c.default_save_limit)
    addEventLimitBuf = tostring(c.default_ev_limit)
end

-- ============================================================================
-- 3. GAME API, CONN GUARD, MOVEMENT & OBJECT HELPERS
-- ============================================================================
local function getLocalSafe()
    if not getLocal then return nil end
    local ok, p = pcall(getLocal)
    return (ok and p) and p or nil
end

local function getPlayerPos()
    local p = getLocalSafe()
    if not p then return 0, 0 end
    local px = p.posX or (p.pos and p.pos.x) or 0
    local py = p.posY or (p.pos and p.pos.y) or 0
    return math.floor((px + 10) / 32), math.floor((py + 10) / 32)
end

local function getCurrentWorldSafe()
    if getCurrentWorldName and type(getCurrentWorldName) == "function" then
        local ok, n = pcall(getCurrentWorldName)
        if ok and n and type(n) == "string" and n ~= "" then
            local c = cleanWorldName(n)
            if c ~= "" and c ~= "EXIT" then return c end
        end
    end
    if getWorld and type(getWorld) == "function" then
        local ok, w = pcall(function()
            local obj = getWorld()
            if obj then
                if type(obj) == "string" then return obj end
                return obj.name
            end
        end)
        if ok and w and type(w) == "string" and w ~= "" then
            local c = cleanWorldName(w)
            if c ~= "" and c ~= "EXIT" then return c end
        end
    end
    if GetWorldName and type(GetWorldName) == "function" then
        local ok, n = pcall(GetWorldName)
        if ok and n and type(n) == "string" and n ~= "" then
            local c = cleanWorldName(n)
            if c ~= "" and c ~= "EXIT" then return c end
        end
    end
    if getLocal and type(getLocal) == "function" then
        local ok, w = pcall(function()
            local p = getLocal()
            if p then return p.world end
        end)
        if ok and w and type(w) == "string" and w ~= "" then
            local c = cleanWorldName(w)
            if c ~= "" and c ~= "EXIT" then return c end
        end
    end
    return "EXIT"
end
_G.getCurrentWorld = getCurrentWorldSafe
getCurrentWorld = getCurrentWorldSafe

local function getInvCount(itemID)
    if not itemID or itemID <= 0 then return 0 end
    local total = 0
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and type(inv) == "table" then
            for _, it in ipairs(inv) do
                local id = it.id or it.itemid or it.itemID
                local c  = it.count or it.amount or it.itemCount or 0
                if id and tonumber(id) == itemID then total = total + (tonumber(c) or 0) end
            end
            return total
        end
    end
    if findItem then
        local ok, c = pcall(findItem, itemID)
        if ok and tonumber(c) then return math.floor(tonumber(c)) end
    end
    return 0
end

local function setCollectCheats(enable)
    local v = enable == true
    if cheat and cheat.collect then pcall(cheat.collect, v) end
    if setCheat then pcall(setCheat, "collect", v) end
    if autoCollect then pcall(autoCollect, v) end
    if bot then
        pcall(function()
            if bot.auto_collect ~= nil then bot.auto_collect = v end
            if bot.collect ~= nil then bot.collect = v end
            if bot.anti_collect ~= nil then bot.anti_collect = not v end
        end)
    end
    if editToggle then
        pcall(editToggle, "Auto Collect", v)
        pcall(editToggle, "Anti Collect", not v)
        if HV.CFG.use_modfly ~= false and v then
            pcall(editToggle, "ModFly", true)
            pcall(editToggle, "Anti Lava", true)
            pcall(editToggle, "No Lava", true)
        end
    end
end

local function setConnWarping(isWarping)
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE then
        HUB_REF.conn.STATE.warping = (isWarping == true)
        if isWarping and HUB_REF.conn.touchActivity then pcall(HUB_REF.conn.touchActivity) end
    end
end

local function getTileSafe(x, y)
    if not getTile and not getTiles then return nil end
    if getTile then
        local ok, t = pcall(getTile, x, y)
        if ok and t then return t end
    end
    if getTiles then
        local ok, tiles = pcall(getTiles)
        if ok and type(tiles) == "table" then
            local idx = (y * 100) + x + 1
            if tiles[idx] then return tiles[idx] end
        end
    end
    return nil
end

local function forEachWorldObject(callback)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return end
    local ok, objs = pcall(getFn)
    if not ok or type(objs) ~= "table" then return end
    local container = objs
    pcall(function()
        if type(objs) == "table" and objs.objects then container = objs.objects end
    end)

    for _, o in pairs(container) do
        if type(o) == "table" or type(o) == "userdata" then
            local itemID = tonumber(o.itemid or o.itemId or o.itemID or o.item_id)
            local objUID = tonumber(o.id or o.oid or o.uid or o.objID)
            local amt    = tonumber(o.count or o.amount or 1) or 1
            local ox     = (o.pos and tonumber(o.pos.x)) or tonumber(o.posX or o.x) or 0
            local oy     = (o.pos and tonumber(o.pos.y)) or tonumber(o.posY or o.y) or 0
            if itemID and objUID then
                callback(itemID, objUID, amt, ox, oy)
            end
        end
    end
end

local function countDroppedObjectsInWorld(allowedSet)
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if (not allowedSet) or allowedSet[oid] then total = total + amt end
    end)
    return total
end

local function isTileBlocked(x, y)
    local t = getTileSafe(x, y)
    if not t then return true end
    local fg = tonumber(t.fg) or 0
    if fg > 0 and LOCK_OR_DOOR_IDS[fg] then return true end
    return false
end

local function moveSafeTo(tx, ty, exact)
    if not HV.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))

    local curPx, curPy = getPlayerPos()
    if exact then
        if curPx == tx and curPy == ty then return true end
    else
        if curPx and curPy and math.abs(curPx - tx) <= 1 and math.abs(curPy - ty) <= 1 then
            return true
        end
    end

    local sx, sy = tx, ty
    if not exact then
        local t = getTileSafe(tx, ty)
        if t and t.collidable then
            local tUp = getTileSafe(tx, ty - 1)
            if tUp and not tUp.collidable then sx, sy = tx, ty - 1 end
        end
    end

    local pFn = FindPath or findPath
    if not pFn then return false end
    if HV.CFG.use_modfly and editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end

    local startPx, startPy = getPlayerPos()
    local totalDist = math.max(math.abs((startPx or 0) - sx), math.abs((startPy or 0) - sy))

    if totalDist <= 3 then
        pcall(pFn, sx, sy)
        local maxWait = math.max(160, (tonumber(HV.CFG.step_delay) or 110) * 3)
        local waited = 0
        while waited < maxWait and HV.STATE.running do
            local px, py = getPlayerPos()
            if exact then
                if px == sx and py == sy then
                    safeSleep(HV.CFG.step_delay or 40)
                    return true
                end
            else
                if px and py and math.abs(px - sx) <= 1 and math.abs(py - sy) <= 1 then
                    safeSleep(HV.CFG.step_delay or 40)
                    return true
                end
            end
            safeSleep(25)
            waited = waited + 25
        end
        local fx, fy = getPlayerPos()
        if exact then
            return (fx == sx and fy == sy)
        else
            return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
        end
    end

    pcall(pFn, sx, sy)
    local maxWaitFar = math.max(2500, math.min(15000, totalDist * 180))
    local waitedFar = 0
    local lastPx, lastPy = startPx, startPy
    local stuckTicks = 0

    while waitedFar < maxWaitFar and HV.STATE.running do
        safeSleep(60)
        waitedFar = waitedFar + 60
        local nx, ny = getPlayerPos()
        if nx and ny then
            if exact then
                if nx == sx and ny == sy then
                    safeSleep(HV.CFG.step_delay or 50)
                    return true
                end
            else
                if math.abs(nx - sx) <= 1 and math.abs(ny - sy) <= 1 then
                    safeSleep(HV.CFG.step_delay or 50)
                    return true
                end
            end
            if nx == lastPx and ny == lastPy then
                stuckTicks = stuckTicks + 1
                if stuckTicks >= 10 then
                    pcall(pFn, sx, sy)
                    stuckTicks = 0
                end
            else
                stuckTicks = 0
                lastPx, lastPy = nx, ny
            end
        end
    end
    local fx, fy = getPlayerPos()
    if exact then
        return (fx == sx and fy == sy)
    else
        return (fx and fy and math.abs(fx - sx) <= 1 and math.abs(fy - sy) <= 1)
    end
end

local function isPlayerOnlineInWorld()
    local p = getLocalSafe()
    if not p then return false, "OFFLINE" end
    local w = getCurrentWorldSafe()
    if w == "" or w == "EXIT" then return false, "DISCONNECTED" end
    return true, w
end

local function waitForWorldTiles(maxWaitMs)
    local maxWait = maxWaitMs or 4000
    local elapsed = 0
    while elapsed < maxWait and HV.STATE.running do
        local onlineNow = isPlayerOnlineInWorld()
        if not onlineNow then return false end
        local t0 = getTileSafe(0, 0)
        local tSpawn = getTileSafe(2, 2)
        if t0 or tSpawn then return true end
        safeSleep(200)
        elapsed = elapsed + 200
    end
    return true
end

local function ensureHVOnlineInWorld(targetWorld, doorID)
    local maxWait = 25000
    local waited = 0
    while waited < maxWait and HV.STATE.running do
        local online, curW = isPlayerOnlineInWorld()
        if online and curW == targetWorld then
            return true
        end
        if not online then
            HV.STATE.status_text = "Menunggu Reconnect..."
            addLog(string.format("[Koneksi Terputus] Menunggu koneksi pulih sebelum masuk ke %s (%ds)...", targetWorld, math.floor(waited / 1000)))
            safeSleep(2000)
            waited = waited + 2000
        else
            return true
        end
    end
    local finalOnline = isPlayerOnlineInWorld()
    return finalOnline == true
end

local function warpToWorldInner(wName, doorID)
    doorID = doorID or ""
    if wName == "" then return false end
    wName = wName:upper():gsub("%s+", "")
    doorID = doorID:gsub("%s+", "")

    -- Cek status koneksi: jika sedang disconnect, tunggu reconnect dahulu
    local onlineInit, curInit = isPlayerOnlineInWorld()
    if not onlineInit then
        addLog(string.format("[Warp Ditahan] Player sedang offline/disconnect (World: '%s'). Menunggu reconnect sebelum warp ke %s...", curInit, wName))
        if not ensureHVOnlineInWorld(wName, doorID) then
            return false
        end
        if getCurrentWorldSafe() == wName then
            waitForWorldTiles(3000)
            return true
        end
    end

    if getCurrentWorldSafe() == wName and doorID == "" then return true end

    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    local warpDelay = math.max(4000, tonumber(HV.CFG.warp_delay) or 4500)

    for attempt = 1, 4 do
        if not HV.STATE.running then return false end
        local onlineNow, cur = isPlayerOnlineInWorld()
        if not onlineNow then
            addLog(string.format("[Warp DC] Terputus saat proses warp ke %s! Menunggu koneksi pulih...", wName))
            ensureHVOnlineInWorld(wName, doorID)
            cur = getCurrentWorldSafe()
            if cur == wName then
                waitForWorldTiles(3500)
                return true
            end
        end

        if cur ~= wName then
            addLog(string.format("`9[Warp] Warp ke %s (Percobaan %d/4)...", joinStr, attempt))
            local sent = sendPacketSafe(3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
            if not sent and growtopia and growtopia.warpTo then
                pcall(growtopia.warpTo, joinStr)
            end

            local elapsed = 0
            while elapsed < warpDelay and HV.STATE.running do
                safeSleep(250)
                elapsed = elapsed + 250
                local checkOnline, checkW = isPlayerOnlineInWorld()
                if checkOnline and checkW == wName then
                    safeSleep(500)
                    waitForWorldTiles(3500)
                    return true
                end
            end
        else
            waitForWorldTiles(2000)
            return true
        end
    end

    local finalOnline, finalW = isPlayerOnlineInWorld()
    if not finalOnline then
        addLog(string.format("[Warp DC] Gagal masuk ke %s karena koneksi terputus (bukan world inaccessible).", wName))
        return false
    end
    return finalW == wName
end

local function warpToWorld(wName, doorID)
    setConnWarping(true)
    local ok = warpToWorldInner(wName, doorID)
    setConnWarping(false)
    return ok
end

local function ensureHVOnline(row, resumeCollect)
    local conn = HUB_REF and HUB_REF.conn
    if not conn or not conn.ensureOnline then return true end
    local tw = row and row.name or ""
    local td = row and row.door or ""
    if not conn.needsReconnect(tw) then return true end
    HV.STATE.status_text = "RECONNECTING..."
    if row then row.status = "Reconnecting..." end
    local okOn = conn.ensureOnline({
        world     = tw,
        door      = td,
        isRunning = function() return HV.STATE.running end,
        onResume  = function() setCollectCheats(resumeCollect == true) end,
        warpFn    = function(w, d) return warpToWorld(w, d) end,
    })
    return okOn == true
end

local function punchTile(tx, ty)
    if not sendPacketRaw and not punch then return false end
    if HUB_REF and HUB_REF.conn and HUB_REF.conn.STATE and HUB_REF.conn.STATE.reconnecting then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    local state = (px > (tx * 32)) and 48 or 32
    if sendPacketRaw then
        pcall(sendPacketRaw, false, {
            type  = 3,
            value = 18,
            px    = tx,
            py    = ty,
            x     = px,
            y     = py,
            state = state,
        })
    end
    if punch then pcall(punch, tx, ty) end
    return true
end

local function collectNearbyAllowed(allowedSet, radiusTiles)
    if not HV.CFG.auto_collect then return end
    if HV.STATE.in_save_world or HV.STATE.in_event_world or HV.STATE.anti_take or HV.STATE.is_dropping then
        return
    end
    local px, py = getPlayerPos()
    local rad = radiusTiles or (tonumber(HV.CFG.collect_range) or 4)
    forEachWorldObject(function(oid, uid, _, ox, oy)
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if (not allowedSet) or allowedSet[oid] then
            local otx = math.floor((ox + 10) / 32)
            local oty = math.floor((oy + 10) / 32)
            if math.abs(otx - px) <= rad and math.abs(oty - py) <= rad then
                if sendPacketRaw then
                    pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
                end
                if collectObject then pcall(collectObject, uid)
                elseif CollectObject then pcall(CollectObject, uid) end
            end
        end
    end)
end

-- ============================================================================
-- 3. DIALOG & VARIANT HOOKS (AUTO CONFIRM DROP & DIALOG HANDLERS)
-- ============================================================================
local function parseDropDialogPacket(dlgText, fallbackID, dropAmt)
    local embedLines = {}
    local dName = dlgText:match("end_dialog|([^|\r\n]+)") or "drop_item"
    for k, v in dlgText:gmatch("embed_data|([^|\r\n]+)|([^\r\n|]*)") do
        table.insert(embedLines, k .. "|" .. v)
    end
    local countField = dlgText:match("add_text_input|([^|\r\n]+)|") or "count"
    local out = { "action|dialog_return", "dialog_name|" .. dName }
    for _, l in ipairs(embedLines) do table.insert(out, l) end
    if not dlgText:find("itemID|", 1, true) then
        table.insert(out, "itemID|" .. tostring(fallbackID) .. "|")
    end
    table.insert(out, countField .. "|" .. tostring(dropAmt))
    return table.concat(out, "\n") .. "\n"
end

local function extractDialogPayload(var)
    if not var then return nil end
    local v0 = tostring(var.v0 or var.v1 or var[0] or var[1] or "")
    local v1 = tostring(var.v1 or var.v2 or var[1] or var[2] or "")
    if v0 == "OnDialogRequest" then
        return (v1 ~= "" and v1) or tostring(var.v2 or var[2] or "")
    elseif v1 == "OnDialogRequest" then
        return tostring(var.v2 or var[2] or var[0] or "")
    else
        for _, k in ipairs({ 0, 1, 2, 3, "v0", "v1", "v2", "v3" }) do
            local val = tostring(var[k] or "")
            if val:find("end_dialog", 1, true) or val:find("add_text_input", 1, true) then
                return val
            end
        end
    end
    return nil
end

local function onVariantHook(var, pkt)
    if not var then return false end
    local ok, shouldBlock = pcall(function()
        local raw = extractDialogPayload(var)
        if raw and raw ~= "" and (raw:find("drop", 1, true) or raw:find("Drop", 1, true)) then
            local itmId = tonumber(raw:match("itemID|(%d+)")) or HV.STATE.pending_drop_id or 0
            local itmAmt = HV.STATE.pending_drop_amt or 200
            if itmAmt <= 0 then itmAmt = 200 end
            local dropPkt = parseDropDialogPacket(raw, itmId, itmAmt)
            if sendPacket then
                pcall(sendPacket, 2, dropPkt)
                HV.STATE.drop_confirmed = true
            end
            return true -- Consume and block native dialog from remaining open on screen
        end
        return false
    end)
    if ok and shouldBlock then return true end
    return false
end

local function onSendPacketRawHook(raw)
    if not HV.STATE.running then return end
    -- Blokir packet pickup (11) selama bot sedang drop atau berada di save/event world
    if raw and raw.type == 11 then
        if HV.STATE.in_save_world or HV.STATE.in_event_world or HV.STATE.is_dropping or HV.STATE.anti_take then
            return true
        end
        if HV.CFG.ignore_take_drop and (HV.STATE.in_save_world or HV.STATE.in_event_world) then
            return true
        end
    end
    if raw and raw.type == 10 and raw.value then
        if raw.value == ITEM.SORROWS or raw.value == ITEM.HARVESTER then
            if not HV.STATE.need_fuel then addLog("`2[Harvester] Berhasil equip Harvester!") end
        end
    end
    if HV.CFG.ignore_gems and raw and raw.type == 11 and raw.value then
        local targetUID = raw.value
        local isGems = false
        forEachWorldObject(function(oid, uid)
            if uid == targetUID and oid == ITEM.GEMS then isGems = true end
        end)
        if isGems then return true end
    end
end

local activeNativeDialogs = {}
_G.__BOREN_ACTIVE_NATIVE_DIALOGS = _G.__BOREN_ACTIVE_NATIVE_DIALOGS or {}

local function sanitizeDialogVal(s)
    local res = tostring(s or ""):gsub("[\r\n|]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return res
end

local function showClientDialog(dText)
    if not dText or dText == "" then return false end
    if growtopia and type(growtopia.sendDialog) == "function" then
        local ok = pcall(growtopia.sendDialog, dText)
        if ok then return true end
    end
    if sendVariant then
        local ok0 = pcall(sendVariant, { v0 = "OnDialogRequest", v1 = dText })
        if ok0 then return true end
        local ok1 = pcall(sendVariant, { v1 = "OnDialogRequest", v2 = dText })
        if ok1 then return true end
        local okNum = pcall(sendVariant, { [0] = "OnDialogRequest", [1] = dText })
        if okNum then return true end
    end
    if sendVariantList then
        local okList = pcall(sendVariantList, { [0] = "OnDialogRequest", [1] = dText })
        if okList then return true end
    end
    if sendDialog then
        pcall(sendDialog, dText)
        return true
    end
    return false
end

local function openNativeInputDialog(dialogId, title, fields, submitLabel, onSubmit)
    activeNativeDialogs[dialogId] = onSubmit
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS = _G.__BOREN_ACTIVE_NATIVE_DIALOGS or {}
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dialogId] = onSubmit
    local lines = {
        "set_default_color|`o",
        "add_label_with_icon|big|`cBOREN HARVEST - " .. sanitizeDialogVal(title) .. "|left|3802|",
        "add_spacer|small|",
    }
    for _, f in ipairs(fields or {}) do
        local fid = tostring(f.id or "f")
        local flb = sanitizeDialogVal(f.label or fid)
        local fdv = sanitizeDialogVal(f.default or "")
        local fln = tonumber(f.maxLen) or 48
        lines[#lines + 1] = string.format("add_text_input|%s|%s:|%s|%d|", fid, flb, fdv, fln)
    end
    lines[#lines + 1] = "add_spacer|small|"
    lines[#lines + 1] = "add_smalltext|`7Ketik dengan keyboard HP Anda lalu tekan tombol di bawah.|"
    lines[#lines + 1] = "end_dialog|" .. dialogId .. "|Batal|" .. sanitizeDialogVal(submitLabel or "Masukkan ke Form") .. "|"
    local dText = table.concat(lines, "\n")
    if HV and HV.STATE and HV.STATE.show_ui ~= nil then
        HV.STATE._saved_ui_state = HV.STATE.show_ui
        HV.STATE.show_ui = false
    end
    showClientDialog(dText)
end

local function onSendPacketHook(p1, p2)
    local packet = (type(p2) == "string") and p2 or ((type(p1) == "string") and p1 or nil)
    if not packet then return false end
    if packet:find("action|dialog_return", 1, true) then
        local dlgName = packet:match("dialog_name|([^\r\n|]+)")
        if dlgName then
            local cb = activeNativeDialogs[dlgName] or (_G.__BOREN_ACTIVE_NATIVE_DIALOGS and _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dlgName])
            if cb then
                activeNativeDialogs[dlgName] = nil
                if _G.__BOREN_ACTIVE_NATIVE_DIALOGS then _G.__BOREN_ACTIVE_NATIVE_DIALOGS[dlgName] = nil end
                local fields = {}
                for line in packet:gmatch("[^\r\n]+") do
                    local k, v = line:match("^([^|]+)|(.*)$")
                    if k and k ~= "" then
                        k = k:gsub("^%s+", ""):gsub("%s+$", "")
                        v = tostring(v or ""):gsub("|$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                        fields[k] = v
                    end
                end
                local btn = tostring(fields.buttonClicked or ""):lower()
                if btn ~= "batal" and btn ~= "cancel" and btn ~= "close" then
                    pcall(cb, fields)
                end
                if HV and HV.STATE and HV.STATE._saved_ui_state ~= nil then
                    HV.STATE.show_ui = HV.STATE._saved_ui_state
                    HV.STATE._saved_ui_state = nil
                elseif HV and HV.STATE and HV.STATE.show_ui ~= nil then
                    HV.STATE.show_ui = true
                end
                return true
            end
        end
    end
    return false
end

-- Registrasi Global & Engine Hooks
if AddHook then
    pcall(AddHook, "OnSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(AddHook, "OnVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(AddHook, "OnVariant", "boren_hv_var_hook2", onVariantHook)
    pcall(AddHook, "OnSendPacket", "boren_hv_send_hook", onSendPacketHook)
elseif addHook then
    pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    pcall(addHook, "onSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(addHook, "OnSendPacketRaw", "boren_hv_raw_hook", onSendPacketRawHook)
    pcall(addHook, onVariantHook, "onvariant")
    pcall(addHook, onVariantHook, "onvariantlist")
    pcall(addHook, "onVariant", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, "OnVariant", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, "onVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, "OnVariantList", "boren_hv_var_hook", onVariantHook)
    pcall(addHook, onSendPacketHook, "onsendpacket")
    pcall(addHook, "onSendPacket", "boren_hv_send_hook", onSendPacketHook)
    pcall(addHook, "OnSendPacket", "boren_hv_send_hook", onSendPacketHook)
end
onVariant = onVariantHook
OnVariant = onVariantHook
onVariantList = onVariantHook
OnVariantList = onVariantHook
onSendPacketRaw = onSendPacketRawHook
OnSendPacketRaw = onSendPacketRawHook
onSendPacket = onSendPacketHook
OnSendPacket = onSendPacketHook
if applyHook then pcall(applyHook) end
if ApplyHook then pcall(ApplyHook) end


-- ============================================================================
-- 4. DROP ENGINE (DROP DI KANAN DOOR ID, URUT & RAPI, MAX 4K PER TILE / SPOT KOSONG)
-- ============================================================================
local function getSpawnDoorPos()
    local px, py = getPlayerPos()
    if not px or not py then
        return 2, 2
    end
    px = math.floor(px)
    py = math.floor(py)

    -- 1. Cek tepat di posisi spawn bot
    local t0 = getTileSafe(px, py)
    if t0 then
        local fg0 = tonumber(t0.fg) or 0
        if fg0 == 6 or fg0 == 8 or fg0 == 12 or fg0 == 242 or LOCK_OR_DOOR_IDS[fg0] then
            return px, py
        end
    end

    -- 2. Cek radius 1-2 tile di sekitar spawn bot (karena saat spawn, bot bisa berdiri di samping door)
    local offsets = {
        {0, 0}, {0, 1}, {0, -1}, {1, 0}, {-1, 0},
        {1, 1}, {-1, 1}, {1, -1}, {-1, -1},
        {0, 2}, {0, -2}, {2, 0}, {-2, 0}
    }
    for _, off in ipairs(offsets) do
        local tx, ty = px + off[1], py + off[2]
        local t = getTileSafe(tx, ty)
        if t then
            local fg = tonumber(t.fg) or 0
            if fg == 6 or fg == 8 or fg == 12 or fg == 242 or LOCK_OR_DOOR_IDS[fg] then
                return tx, ty
            end
        end
    end

    return px, py
end

local function inspectTileDropped(tx, ty)
    local total = 0
    local itemCounts = {}
    forEachWorldObject(function(oid, uid, amt, ox, oy)
        local otx = math.floor((ox or 0) / 32)
        local oty = math.floor((oy or 0) / 32)
        if otx == tx and oty == ty then
            local count = tonumber(amt) or 1
            total = total + count
            if oid then itemCounts[oid] = (itemCounts[oid] or 0) + count end
        end
    end)
    return total, itemCounts
end

local function countDroppedOnTile(tx, ty)
    local total, _ = inspectTileDropped(tx, ty)
    return total
end

local function isTileCleanForDrop(tx, ty, doorX, doorY)
    if tx < 1 or tx > 97 or ty < 1 or ty > 53 then return false end
    if tx == doorX and ty == doorY then return false end
    if isTileBlocked(tx, ty) then return false end
    local t = getTileSafe(tx, ty)
    if t then
        local fg = tonumber(t.fg) or 0
        if LOCK_OR_DOOR_IDS[fg] then return false end
        if fg > 0 and t.collidable then return false end
    end
    return true
end

local function isTileCleanForStand(tx, ty, doorX, doorY)
    if tx < 1 or tx > 98 or ty < 1 or ty > 53 then return false end
    if tx == doorX and ty == doorY then return false end
    if isTileBlocked(tx, ty) then return false end
    local t = getTileSafe(tx, ty)
    if t then
        local fg = tonumber(t.fg) or 0
        if LOCK_OR_DOOR_IDS[fg] then return false end
        if fg > 0 and t.collidable then return false end
    end
    return true
end

local function faceLeft(standX, standY)
    if sendPacketRaw then
        pcall(sendPacketRaw, false, {
            type  = 0,
            pos   = { x = standX * 32, y = standY * 32 },
            x     = standX * 32,
            y     = standY * 32,
            state = 48 -- 48 = Flipped / Menghadap ke kiri
        })
    end
end

local function faceRight(standX, standY)
    if sendPacketRaw then
        pcall(sendPacketRaw, false, {
            type  = 0,
            pos   = { x = standX * 32, y = standY * 32 },
            x     = standX * 32,
            y     = standY * 32,
            state = 0 -- 0 = Normal / Menghadap ke kanan
        })
    end
end

local function moveToStand(standX, standY, faceDir)
    if not HV.STATE.running then return false end
    standX = math.max(1, math.min(98, math.floor(standX or 0)))
    standY = math.max(1, math.min(53, math.floor(standY or 0)))

    if editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end

    local curPx, curPy = getPlayerPos()
    if curPx == standX and curPy == standY then
        if faceDir == "right" then faceRight(standX, standY) else faceLeft(standX, standY) end
        return true
    end

    local pFn = FindPath or findPath
    if pFn then
        pcall(pFn, standX, standY)
        local waited = 0
        while waited < 800 and HV.STATE.running do
            safeSleep(30)
            waited = waited + 30
            local px, py = getPlayerPos()
            if px == standX and py == standY then
                if faceDir == "right" then faceRight(standX, standY) else faceLeft(standX, standY) end
                safeSleep(20)
                return true
            end
        end
    end

    moveSafeTo(standX, standY, true)
    if faceDir == "right" then faceRight(standX, standY) else faceLeft(standX, standY) end
    safeSleep(30)
    local fx, fy = getPlayerPos()
    return (fx == standX and fy == standY) or (fx and fy and math.abs(fx - standX) <= 1 and math.abs(fy - standY) <= 1)
end

local function executeDropBatch(itemID, batch)
    if not HV.STATE.running then return false, 0 end
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end
    batch = math.min(batch, math.min(200, cur))

    HV.STATE.is_dropping = true
    HV.STATE.anti_take = true
    HV.STATE.drop_confirmed = false
    HV.STATE.pending_drop_id = itemID
    HV.STATE.pending_drop_amt = batch

    setCollectCheats(false)
    safeSleep(20)

    -- Metode 1: Standard action|drop (memicu OnDialogRequest di server)
    if sendPacket then
        pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
    end

    -- Metode 2: C++ engine direct drop confirmation
    if growtopia and growtopia.confirmDropItem then
        pcall(growtopia.confirmDropItem, itemID, batch)
    end

    -- Metode 3: Standard packet drop_item / drop dialog return
    if sendPacket then
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop_item\nitemID|%d\ncount|%d\n", itemID, batch))
        pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|drop\nitemID|%d\ncount|%d\n", itemID, batch))
    end

    local waited = 0
    while waited < 650 and HV.STATE.running do
        safeSleep(30)
        waited = waited + 30
        if getInvCount(itemID) < cur or HV.STATE.drop_confirmed then
            break
        end
    end

    HV.STATE.pending_drop_id = 0
    HV.STATE.pending_drop_amt = 0
    HV.STATE.is_dropping = false
    if not (HV.STATE.in_save_world or HV.STATE.in_event_world) then
        HV.STATE.anti_take = false
    end

    local after = getInvCount(itemID)
    if after < cur then
        local delta = cur - after
        return true, delta
    end
    return false, 0
end

local function dropOntoTile(dropX, dropY, itemID, maxCanDrop, doorX, doorY)
    local existingOnTile, itemCounts = inspectTileDropped(dropX, dropY)
    if existingOnTile >= 4000 then
        return false, 0, true
    end

    -- Jika tile sudah ada item lain yang bukan itemID ini, geser ke spot berikutnya agar rapi
    for oid, _ in pairs(itemCounts) do
        if oid ~= itemID then
            return false, 0, true
        end
    end

    -- Tentukan posisi berdiri bot:
    -- 1. Berdiri di kanan dropX (dropX + 1) menghadap ke kiri (prioritas utama, rapi di kanan pintu)
    -- 2. Jika dropX + 1 terhalang tembok, berdiri di kiri (dropX - 1) menghadap kanan
    -- 3. Berdiri tepat di atas tile dropX
    local chosenStandX = nil
    local chosenFace = "left"

    if (dropX + 1) <= 98 and isTileCleanForStand(dropX + 1, dropY, doorX, doorY) then
        chosenStandX = dropX + 1
        chosenFace = "left"
    elseif (dropX - 1) >= 1 and (dropX - 1 ~= doorX or dropY ~= doorY) and isTileCleanForStand(dropX - 1, dropY, doorX, doorY) then
        chosenStandX = dropX - 1
        chosenFace = "right"
    elseif isTileCleanForStand(dropX, dropY, doorX, doorY) then
        chosenStandX = dropX
        chosenFace = "left"
    end

    if not chosenStandX then
        return false, 0, false
    end

    if not moveToStand(chosenStandX, dropY, chosenFace) then
        return false, 0, false
    end
    if chosenFace == "right" then faceRight(chosenStandX, dropY) else faceLeft(chosenStandX, dropY) end

    local droppedOnTile = 0
    local failCount = 0

    while HV.STATE.running and failCount < 2 do
        local curInv = getInvCount(itemID)
        if curInv <= 0 then
            return true, droppedOnTile, false
        end

        local tileSpace = 4000 - (existingOnTile + droppedOnTile)
        if tileSpace <= 0 then
            return true, droppedOnTile, true
        end

        local batch = math.min(200, math.min(curInv, tileSpace))
        if maxCanDrop and maxCanDrop > 0 then
            local remainQuota = maxCanDrop - droppedOnTile
            if remainQuota <= 0 then
                return true, droppedOnTile, false
            end
            batch = math.min(batch, remainQuota)
        end

        HV.STATE.status_text = string.format("Drop %d ke (%d,%d)...", batch, dropX, dropY)
        if chosenFace == "right" then faceRight(chosenStandX, dropY) else faceLeft(chosenStandX, dropY) end
        local ok, delta = executeDropBatch(itemID, batch)
        if ok and delta > 0 then
            droppedOnTile = droppedOnTile + delta
            HV.STATE.total_dropped = HV.STATE.total_dropped + delta
            failCount = 0
            safeSleep(100)
            if (existingOnTile + droppedOnTile) >= 4000 then
                return true, droppedOnTile, true
            end
        else
            failCount = failCount + 1
            safeSleep(120)
        end
    end

    local tileFull = (failCount >= 2) or ((existingOnTile + droppedOnTile) >= 4000)
    return (droppedOnTile > 0), droppedOnTile, tileFull
end

local dropOntoTileFromRight = dropOntoTile -- Alias backward compatibility

local function dropItemAllInCurrentWorld(itemID, label, maxQuota)
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end

    if editToggle then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(false)

    -- Deteksi titik spawn Door ID (lokasi bot mendarat saat warp)
    local doorX, doorY = getSpawnDoorPos()
    local totalDropped = 0

    -- ========================================================================
    -- PRIORITAS UTAMA: SEJAJAR DOOR ID (rowY = doorY) DARI KANAN DOOR (doorX + 1 .. 97)
    -- Bot berdiri di kanan tile menghadap kiri, drop urut rapi max 4000 item per spot.
    -- ========================================================================
    local startX = math.max(1, doorX + 1)
    for dropX = startX, 97 do
        if getInvCount(itemID) <= 0 or not HV.STATE.running then break end
        if maxQuota and maxQuota > 0 and totalDropped >= maxQuota then break end

        if isTileCleanForDrop(dropX, doorY, doorX, doorY) then
            local quotaLeft = (maxQuota and maxQuota > 0) and (maxQuota - totalDropped) or nil
            local ok, droppedAmt, tileFull = dropOntoTile(dropX, doorY, itemID, quotaLeft, doorX, doorY)
            if droppedAmt > 0 then
                totalDropped = totalDropped + droppedAmt
            end
        end
    end

    -- ========================================================================
    -- CADANGAN OPSIONAL: HANYA JIKA SEMUA TILE DI BARISAN DOOR SUDAH 100% PENUH (4K)
    -- atau terblokir, DAN bot MASIH memiliki sisa item di tas (getInvCount > 0)!
    -- Mengisi baris atas (doorY - 1 .. 1), lalu baris bawah (doorY + 1 .. 53)
    -- ========================================================================
    if getInvCount(itemID) > 0 and HV.STATE.running and (not maxQuota or totalDropped < maxQuota) then
        addLog(string.format("`e[Drop] Barisan Door ID (Y=%d) telah penuh! Mengisi baris atas sebagai cadangan...", doorY))
        local fallbackRows = {}
        for y = doorY - 1, 1, -1 do table.insert(fallbackRows, y) end
        for y = doorY + 1, 53 do table.insert(fallbackRows, y) end

        for _, rowY in ipairs(fallbackRows) do
            if getInvCount(itemID) <= 0 or not HV.STATE.running then break end
            if maxQuota and maxQuota > 0 and totalDropped >= maxQuota then break end

            for dropX = startX, 97 do
                if getInvCount(itemID) <= 0 or not HV.STATE.running then break end
                if maxQuota and maxQuota > 0 and totalDropped >= maxQuota then break end

                if isTileCleanForDrop(dropX, rowY, doorX, doorY) then
                    local quotaLeft = (maxQuota and maxQuota > 0) and (maxQuota - totalDropped) or nil
                    local ok, droppedAmt, tileFull = dropOntoTile(dropX, rowY, itemID, quotaLeft, doorX, doorY)
                    if droppedAmt > 0 then
                        totalDropped = totalDropped + droppedAmt
                    end
                end
            end
        end
    end

    HV.STATE.is_dropping = false
    if not (HV.STATE.in_save_world or HV.STATE.in_event_world) then
        HV.STATE.anti_take = false
    end
    local remaining = getInvCount(itemID)
    return (remaining == 0), totalDropped
end

local function dropToSaveWorlds(blockID, seedID, returnFarm)
    local bCnt = getInvCount(blockID)
    local sCnt = getInvCount(seedID)
    if bCnt <= 0 and sCnt <= 0 then return true end

    local rows = HV.STATE.save_rows
    if #rows == 0 then
        addLog("`e[Save World] World penyimpanan belum diatur (opsional) - tas penuh tapi panen tetap dilanjutkan.")
        return true
    end

    -- Kunci anti_take & in_save_world selama di Save World
    HV.STATE.in_save_world = true
    HV.STATE.anti_take = true
    setCollectCheats(false)

    local itemsToDrop = {}
    if bCnt > 0 then table.insert(itemsToDrop, { id = blockID, name = "Block", isBlock = true }) end
    if sCnt > 0 then table.insert(itemsToDrop, { id = seedID, name = "Seed", isBlock = false }) end

    for _, itm in ipairs(itemsToDrop) do
        local curAmt = getInvCount(itm.id)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    local t = (r.save_type or "ALL"):upper()
                    if itm.isBlock and (t == "ALL" or t == "BLOCK") then
                        targetRow = r; break
                    elseif (not itm.isBlock) and (t == "ALL" or t == "SEED") then
                        targetRow = r; break
                    end
                end
            end

            if not targetRow then
                addLog(string.format("`e[Save World] Semua world untuk %s sudah penuh / tidak tersedia - melanjutkan panen.", itm.name))
                break
            end

            HV.STATE.status_text = "Drop " .. itm.name .. " -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local filterSet = {}
                local t = (targetRow.save_type or "ALL"):upper()
                if t == "BLOCK" then filterSet[blockID] = true
                elseif t == "SEED" then filterSet[seedID] = true
                else filterSet[blockID] = true; filterSet[seedID] = true end

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(filterSet)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Save World] %s capai limit (%d/%d) -> lanjut next world!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local quotaLeft = (lim > 0) and math.max(0, lim - curInWorld) or nil
                    local okD = dropItemAllInCurrentWorld(itm.id, itm.name, quotaLeft)
                    local afterInWorld = countDroppedObjectsInWorld(filterSet)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Save World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itm.id)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        HV.STATE.in_save_world = false
        HV.STATE.anti_take = false
        setCollectCheats(true)
    else
        HV.STATE.in_save_world = false
        HV.STATE.anti_take = false
    end
    return true
end

local function dropToEventWorlds(returnFarm)
    local evList, evMap = parseEventIDs()
    local toDrop = {}
    for _, id in ipairs(evList) do
        if getInvCount(id) > 0 then table.insert(toDrop, id) end
    end
    if #toDrop == 0 then return true end

    local rows = HV.STATE.event_rows
    if #rows == 0 then
        addLog("`e[Event World] World Event belum diatur (opsional)     melewati drop event.")
        return true
    end

    -- Kunci anti_take & in_event_world selama di Event World
    HV.STATE.in_event_world = true
    HV.STATE.anti_take = true
    setCollectCheats(false)

    for _, itmID in ipairs(toDrop) do
        local curAmt = getInvCount(itmID)
        while curAmt > 0 and HV.STATE.running do
            local targetRow = nil
            for _, r in ipairs(rows) do
                if r.status ~= "Full" and r.status ~= "Inaccessible" then
                    targetRow = r; break
                end
            end

            if not targetRow then
                addLog("`e[Event World] Semua World Event penuh / tidak tersedia     drop event dilewati.")
                return true
            end

            HV.STATE.status_text = "Drop Event -> " .. targetRow.name
            if warpToWorld(targetRow.name, targetRow.door) then
                setCollectCheats(false)
                safeSleep(350)

                local lim = math.max(0, math.floor(tonumber(targetRow.limit) or 0))
                local curInWorld = countDroppedObjectsInWorld(evMap)
                targetRow.count = curInWorld

                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[Event World] %s capai limit total (%d/%d) -> pindah world event!", targetRow.name, curInWorld, lim))
                    targetRow.status = "Full"
                    HV.saveData()
                else
                    local quotaLeft = (lim > 0) and math.max(0, lim - curInWorld) or nil
                    local okD = dropItemAllInCurrentWorld(itmID, "Item " .. itmID, quotaLeft)
                    local afterInWorld = countDroppedObjectsInWorld(evMap)
                    targetRow.count = afterInWorld
                    if lim > 0 and afterInWorld >= lim then
                        targetRow.status = "Full"
                    end
                    HV.saveData()
                    if not okD then
                        targetRow.status = "Full"
                        HV.saveData()
                    end
                end
            else
                addLog("`4[Event World] Gagal warp ke " .. targetRow.name)
                targetRow.status = "Inaccessible"
                HV.saveData()
            end
            curAmt = getInvCount(itmID)
        end
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        HV.STATE.in_event_world = false
        HV.STATE.anti_take = false
        setCollectCheats(true)
    else
        HV.STATE.in_event_world = false
        HV.STATE.anti_take = false
    end
    return true
end

-- ============================================================================
-- 5. GEAR WORLD (MAGNI + FUEL TERPADU & LIST ID EQUIP ALAT)
-- ============================================================================
local function equipItem(itemID)
    if not sendPacketRaw or getInvCount(itemID) <= 0 then return false end
    return pcall(sendPacketRaw, false, { type = 10, value = itemID })
end

local function ensureGearAndFuel(returnFarm)
    local c = HV.CFG
    local needed = {}

    -- 1. Magni & Fuel Pack dijadikan satu
    if c.auto_magni_fuel then
        if getInvCount(ITEM.MAGNI) <= 0 then
            table.insert(needed, { id = ITEM.MAGNI, amt = 1, equip = true, name = "Magnifying Glass" })
        end
        local fuelCount = getInvCount(ITEM.FUEL_PACK)
        if HV.STATE.need_fuel and fuelCount > 0 then
            equipItem(ITEM.FUEL_PACK)
            HV.STATE.need_fuel = false
            safeSleep(250)
            fuelCount = getInvCount(ITEM.FUEL_PACK)
        end
        local targetFuel = math.max(1, math.min(200, tonumber(c.fuel_target_amt) or 100))
        if fuelCount < targetFuel or HV.STATE.need_fuel then
            table.insert(needed, { id = ITEM.FUEL_PACK, amt = targetFuel, equip = false, name = "Fuel Pack" })
        end
    end

    -- 2. Daftar ID Alat untuk Di-equip (DCS, Harvester, dll.) HANYA jika toggle Gunakan DCS aktif!
    local equipIDs = c.use_dcs_harvester and parseEquipIDs(c.gear_equip_ids) or {}
    for _, eqID in ipairs(equipIDs) do
        if getInvCount(eqID) <= 0 then
            table.insert(needed, { id = eqID, amt = 1, equip = true, name = "Gear " .. tostring(eqID) })
        end
    end

    -- Jika semua perlengkapan sudah ada di tas
    if #needed == 0 then
        if c.auto_magni_fuel and getInvCount(ITEM.MAGNI) > 0 then equipItem(ITEM.MAGNI); safeSleep(100) end
        if c.use_dcs_harvester then
            for _, eqID in ipairs(equipIDs) do if getInvCount(eqID) > 0 then equipItem(eqID); safeSleep(100) end end
        end
        return true
    end

    local gw = parseWorldDoor(c.gear_world)
    if not gw or trimStr(c.gear_world or "") == "" then
        -- Gear World opsional! Equip perlengkapan yang ada di tas bila tersedia
        if c.auto_magni_fuel and getInvCount(ITEM.MAGNI) > 0 then equipItem(ITEM.MAGNI); safeSleep(100) end
        if getInvCount(ITEM.FUEL_PACK) > 0 and HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(100) end
        if c.use_dcs_harvester then
            for _, eqID in ipairs(equipIDs) do if getInvCount(eqID) > 0 then equipItem(eqID); safeSleep(100) end end
        end
        return true
    end

    HV.STATE.status_text = "Gear World: " .. gw.name
    addLog("[Gear] Ambil perlengkapan / fuel di " .. gw.name)
    if not warpToWorld(gw.name, gw.door) then
        addLog("`e[Gear] Gagal warp ke Gear World " .. gw.name .. "     melanjutkan harvest (Gear World opsional).")
        return true
    end

    setCollectCheats(true)
    safeSleep(450)
    for _, req in ipairs(needed) do
        if not HV.STATE.running then return false end
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if not HV.STATE.running then return end
            if oid == req.id and getInvCount(req.id) < req.amt then
                if moveSafeTo(math.floor((ox + 10) / 32), math.floor((oy + 10) / 32)) then
                    if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy }) end
                    safeSleep(220)
                end
            end
        end)
        if req.equip and getInvCount(req.id) > 0 then
            equipItem(req.id); safeSleep(180)
            addLog("`2[Gear] Equip " .. req.name)
        elseif req.id == ITEM.FUEL_PACK and getInvCount(ITEM.FUEL_PACK) > 0 then
            addLog("`2[Gear] Fuel Pack terambil: " .. getInvCount(ITEM.FUEL_PACK))
            if HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false; safeSleep(200) end
        end
    end

    if c.auto_magni_fuel and c.stop_if_no_fuel and getInvCount(ITEM.FUEL_PACK) <= 0 and (gw and trimStr(c.gear_world or "") ~= "") then
        addLog("`4[Fuel Guard] Stok Fuel Pack habis di tas & Gear World     bot berhenti aman!")
        HV.STATE.status_text = "No Fuel Pack"
        return false
    end

    if returnFarm and HV.STATE.running then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 6. HARVEST ENGINE (PER-TREE TELEPORT + FAST TAKE + ZERO MISS AUDIT)
-- ============================================================================
local function isTileTreeReady(t)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 or (fg % 2 == 0) then return false end -- Pohon selalu bernilai ganjil (Seed ID)

    -- 1. Explicit ready flags (Growlauncher standard)
    if t.readyharvest == true or t.readyharvest == 1 or t.readyharvest == "true" then return true end
    if type(t.readyharvest) == "function" then
        local ok, r = pcall(t.readyharvest, t)
        if ok and (r == true or r == 1) then return true end
        local ok2, r2 = pcall(t.readyharvest)
        if ok2 and (r2 == true or r2 == 1) then return true end
    end

    if t.ready_to_harvest == true or t.ready_to_harvest == 1 or t.ready_to_harvest == "true" then return true end
    if t.ready_harvest == true or t.ready_harvest == 1 or t.ready_harvest == "true" then return true end
    if t.ready == true or t.ready == 1 or t.ready == "true" then return true end
    if t.isReady == true or t.is_ready == true then return true end

    -- 2. canHarvest / can_harvest (boolean / method)
    if t.canHarvest ~= nil then
        if type(t.canHarvest) == "function" then
            local ok, res = pcall(t.canHarvest, t)
            if ok and (res == true or res == 1) then return true end
        elseif t.canHarvest == true or t.canHarvest == 1 then
            return true
        end
    end
    if t.can_harvest ~= nil then
        if type(t.can_harvest) == "function" then
            local ok, res = pcall(t.can_harvest, t)
            if ok and (res == true or res == 1) then return true end
        elseif t.can_harvest == true or t.can_harvest == 1 then
            return true
        end
    end

    -- 3. Tile flag (Growtopia mature tree bit: 0x10 = 16 atau 0x20 = 32)
    local fl = tonumber(t.flag or t.flags)
    if fl and fl > 0 then
        if bit32 and bit32.band(fl, 0x10) ~= 0 then return true end
        if (fl % 32 >= 16) or (fl % 64 >= 32) then return true end
    end

    -- 4. Progress (>= 1.0 float atau >= 100 percentage)
    local prog = tonumber(t.progress)
    if prog and (prog >= 1.0 or prog >= 100) then return true end

    -- 5. Direct fruit count on tile
    local directFruits = tonumber(t.fruitcount or t.fruit_count or t.fruits or t.fruit) or 0
    if directFruits > 0 then return true end

    -- 6. Extra table / userdata (fruit count > 0 atau growth <= 0)
    if t.extra and (type(t.extra) == "table" or type(t.extra) == "userdata") then
        local okF, fCount = pcall(function()
            return tonumber(t.extra.fruitcount or t.extra.fruit_count or t.extra.fruits or t.extra.fruit)
        end)
        if okF and fCount and fCount > 0 then return true end

        local okG, growth = pcall(function()
            return tonumber(t.extra.growth or t.extra.time_left or t.extra.grow_time)
        end)
        if okG and growth and growth <= 0 then return true end
    end

    -- 7. Direct growth <= 0
    local directGrowth = tonumber(t.growth or t.time_left)
    if directGrowth and directGrowth <= 0 then return true end

    -- 8. Fallback GTPS / Private Server:
    -- Jika di world terdapat pohon seed yang ditanam (fg % 2 == 1), anggap siap dipanen
    return true
end

local function isReadyTree(tx, ty, seedID, blockID)
    local t = getTileSafe(tx, ty)
    if not t then return false end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 or (fg % 2 == 0) then return false end

    -- Cocokkan fg dengan seedID atau blockID bila disediakan
    local matchesID = false
    if seedID and seedID > 0 and fg == seedID then matchesID = true end
    if (not matchesID) and blockID and blockID > 0 and (fg == blockID or fg == blockID + 1) then matchesID = true end

    -- Jika ID diberikan dan tidak cocok dengan fg, bukan pohon target
    if (seedID and seedID > 0) and not matchesID then return false end

    return isTileTreeReady(t)
end

local function isTreeBroken(tx, ty, seedID, blockID)
    local t = getTileSafe(tx, ty)
    if not t then return true end
    local fg = tonumber(t.fg) or 0
    if fg <= 0 then return true end
    if seedID and seedID > 0 and fg ~= seedID and fg ~= blockID then
        return true
    end
    return not isTileTreeReady(t)
end

local function teleportToTree(tx, ty)
    if not HV.STATE.running then return false end
    if editToggle and HV.CFG.use_modfly ~= false then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end

    local curX, curY = getPlayerPos()
    if curX == tx and curY == ty then return true end

    local pFn = FindPath or findPath
    if pFn then
        pcall(pFn, tx, ty)
    end
    safeSleep(HV.CFG.step_delay or 40)
    return true
end

local function fastTakeAround(allowedSet, rad)
    if HV.STATE.in_save_world or HV.STATE.anti_take or HV.STATE.is_dropping then return end
    rad = rad or 3
    local px, py = getPlayerPos()
    if not px or not py then return end
    forEachWorldObject(function(oid, uid, amt, ox, oy)
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if (not allowedSet) or allowedSet[oid] then
            local otx = math.floor(((ox or 0) + 10) / 32)
            local oty = math.floor(((oy or 0) + 10) / 32)
            if math.abs(otx - px) <= rad and math.abs(oty - py) <= rad then
                if sendPacketRaw then
                    pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
                end
                if collectObject then pcall(collectObject, uid)
                elseif CollectObject then pcall(CollectObject, uid) end
            end
        end
    end)
end

-- Validasi pukulan pohon: memastikan pohon benar-benar telah dipanen (hancur), responsif dan cepat
local function harvestTreeTile(tx, ty, seedID, blockID, hDelay, allowedSet)
    if not isReadyTree(tx, ty, seedID, blockID) then return true end
    punchTile(tx, ty)
    local pDelay = math.max(35, math.min(120, tonumber(hDelay) or 60))
    safeSleep(pDelay)

    -- Verifikasi cepat: jika ada lag, punch sekali lagi agar 100% pecah
    if isReadyTree(tx, ty, seedID, blockID) then
        punchTile(tx, ty)
        safeSleep(30)
    end

    HV.STATE.total_harvested = HV.STATE.total_harvested + 1
    if allowedSet then fastTakeAround(allowedSet, 3) end
    return true
end

local function scanWorldReadyTrees(seedID, blockID)
    local trees = {}
    for ty = 1, 53 do
        for tx = 2, 97 do
            if isReadyTree(tx, ty, seedID, blockID) then
                table.insert(trees, { x = tx, y = ty })
            end
        end
    end
    -- Urutkan baris per baris (y=1..53) secara serpentine untuk minim jarak teleport antar pohon
    table.sort(trees, function(a, b)
        if a.y ~= b.y then
            return a.y < b.y
        end
        if (a.y % 2 == 1) then
            return a.x < b.x
        else
            return a.x > b.x
        end
    end)
    return trees
end

local function scanRemainingReadyTrees(seedID, blockID)
    return scanWorldReadyTrees(seedID, blockID)
end

local function updateInvPreview(blockID, seedID, eventList)
    HV.STATE.inv_preview.block = getInvCount(blockID)
    HV.STATE.inv_preview.seed  = getInvCount(seedID)
    HV.STATE.inv_preview.fuel  = getInvCount(ITEM.FUEL_PACK)
    local evSum = 0
    for _, eid in ipairs(eventList or {}) do evSum = evSum + getInvCount(eid) end
    HV.STATE.inv_preview.ev = evSum
end
_G.updateInvPreview = updateInvPreview

local function checkAndDropIfFull(row, blockID, seedID, eventList, forceDrop)
    updateInvPreview(blockID, seedID, eventList)
    local c = HV.CFG
    local th  = math.max(20, math.min(200, tonumber(c.drop_threshold) or 200))
    local eth = math.max(10, math.min(200, tonumber(c.event_threshold) or 150))

    -- 1. Cek Fuel Pack proaktif jika memakai harvester & fuel
    if (not forceDrop) and c.auto_magni_fuel and (HV.STATE.need_fuel or getInvCount(ITEM.FUEL_PACK) <= 0) then
        if not ensureGearAndFuel(row) then return false end
    end

    -- 2. Drop Item Event bila ada di tas
    local needEventDrop = false
    for _, eid in ipairs(eventList) do
        local cnt = getInvCount(eid)
        if (forceDrop and cnt > 0) or cnt >= eth then needEventDrop = true; break end
    end
    if needEventDrop and #HV.STATE.event_rows > 0 then
        pcall(dropToEventWorlds, forceDrop and nil or row)
    end

    -- 3. Drop Block & Seed
    local bCnt, sCnt = getInvCount(blockID), getInvCount(seedID)
    if (forceDrop and (bCnt > 0 or sCnt > 0)) or bCnt >= th or sCnt >= th then
        pcall(dropToSaveWorlds, blockID, seedID, forceDrop and nil or row)
    end

    updateInvPreview(blockID, seedID, eventList)
    return true
end
_G.checkAndDropIfFull = checkAndDropIfFull

local function harvest1By1Serpentine(row, seedID, blockID, hDelay, allowedSet, eventList)
    local pFn = FindPath or findPath
    local sDelay = math.max(25, math.min(100, tonumber(HV.CFG.step_delay) or 45))
    local pDelay = math.max(35, math.min(120, tonumber(hDelay) or 60))

    if editToggle and HV.CFG.use_modfly ~= false then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(true)

    -- 1. Scan semua baris Y yang memiliki pohon target siap panen
    local treeRows = {}
    for ty = 1, 53 do
        local count = 0
        for tx = 2, 97 do
            if isReadyTree(tx, ty, seedID, blockID) then
                count = count + 1
            end
        end
        if count > 0 then
            table.insert(treeRows, ty)
        end
    end

    if #treeRows == 0 then return true end

    local totalRows = #treeRows
    local rowIdx = 0

    for _, ty in ipairs(treeRows) do
        if not HV.STATE.running then return false end
        if not ensureHVOnline(row, true) then return false end

        rowIdx = rowIdx + 1
        local l2r = (rowIdx % 2 == 1)
        local startX = l2r and 2 or 97
        local endX   = l2r and 97 or 2
        local stepX  = l2r and 1 or -1

        -- Pindah ke awal baris secara mulus & responsif
        HV.STATE.status_text = string.format("Panen Baris %d/%d (Y: %d)...", rowIdx, totalRows, ty)
        moveSafeTo(startX, ty, false)
        safeSleep(sDelay)

        local x = startX
        while (l2r and x <= endX) or ((not l2r) and x >= endX) do
            if not HV.STATE.running then return false end
            if not ensureHVOnline(row, true) then return false end

            if isReadyTree(x, ty, seedID, blockID) then
                -- Cek tas & auto drop jika penuh
                checkAndDropIfFull(row, blockID, seedID, eventList, false)

                -- 1. Gerak langsung ke tile pohon (x, ty) secara presisi & halus
                local curPx, curPy = getPlayerPos()
                if curPx ~= x or curPy ~= ty then
                    if pFn then pcall(pFn, x, ty) end
                    safeSleep(sDelay)
                end

                -- 2. PUNCH pohon dengan pasti
                punchTile(x, ty)
                safeSleep(pDelay)

                -- Verifikasi cepat: punch lagi jika ada lag/delay
                if isReadyTree(x, ty, seedID, blockID) then
                    punchTile(x, ty)
                    safeSleep(30)
                end

                HV.STATE.total_harvested = HV.STATE.total_harvested + 1

                -- 3. AUTO COLLECT LANGSUNG DI TILE POHON
                fastTakeAround(allowedSet, 3)
            end

            x = x + stepX
        end

        -- Sapu sisa drop di akhir baris
        fastTakeAround(allowedSet, 4)
        safeSleep(sDelay)
    end

    return true
end

local function harvestAllTreesPerTree(row, seedID, blockID, hDelay, allowedSet, eventList)
    return harvest1By1Serpentine(row, seedID, blockID, hDelay, allowedSet, eventList)
end

local function auditAndFinishRemainingTrees(row, seedID, blockID, hDelay, allowedSet, eventList)
    local maxPasses = 2
    for pass = 1, maxPasses do
        if not HV.STATE.running then return false end
        local remaining = scanWorldReadyTrees(seedID, blockID)
        if #remaining == 0 then return true end

        addLog(string.format("`e[Audit Pohon] Ditemukan %d sisa pohon matang     membersihkan...", #remaining))
        HV.STATE.status_text = string.format("Audit %d sisa pohon...", #remaining)

        for _, tr in ipairs(remaining) do
            if not HV.STATE.running then return false end
            if not ensureHVOnline(row, true) then return false end
            if isReadyTree(tr.x, tr.y, seedID, blockID) then
                checkAndDropIfFull(row, blockID, seedID, eventList, false)
                moveSafeTo(tr.x, tr.y, false)
                safeSleep(30)
                punchTile(tr.x, tr.y)
                safeSleep(math.max(35, tonumber(hDelay) or 60))
                if isReadyTree(tr.x, tr.y, seedID, blockID) then
                    punchTile(tr.x, tr.y)
                    safeSleep(30)
                end
                fastTakeAround(allowedSet, 3)
            end
        end
        safeSleep(80)
    end
    return true
end

-- checkAndDropIfFull and updateInvPreview declared above

local function sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)
    if not HV.CFG.take_floating then return true end
    HV.STATE.status_text = row.name .. " Take Floating..."
    addLog("[Floating] Sapu sisa drop block/seed/event di " .. row.name)
    setCollectCheats(true)

    local pass = 0
    while pass < 6 and HV.STATE.running do
        pass = pass + 1
        if not ensureHVOnline(row, true) then return false end
        local targets = {}
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
            if allowedSet[oid] then
                table.insert(targets, { oid = oid, uid = uid, ox = ox, oy = oy, tx = math.floor((ox + 10) / 32), ty = math.floor((oy + 10) / 32) })
            end
        end)
        if #targets == 0 then break end
        for _, obj in ipairs(targets) do
            if not HV.STATE.running then return false end
            if not ensureHVOnline(row, true) then return false end
            if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
            if moveSafeTo(obj.tx, obj.ty) then
                if sendPacketRaw then pcall(sendPacketRaw, false, { type = 11, value = obj.uid, x = obj.ox, y = obj.oy }) end
                collectNearbyAllowed(allowedSet, 3)
                safeSleep(120)
            end
        end
    end
    return true
end

local function processFarmWorld(row)
    local blockID, seedID = normalizeHarvestPair(row.item_id or HV.CFG.default_item_id)
    if blockID <= 0 then row.status = "Invalid ID"; HV.saveData(); return false end

    local eventList, eventMap = parseEventIDs()
    local allowedSet = {}
    if HV.CFG.take_block ~= false then allowedSet[blockID] = true end
    if HV.CFG.take_seed ~= false then allowedSet[seedID] = true end
    for id in pairs(eventMap) do allowedSet[id] = true end

    if not ensureGearAndFuel(nil) then return false end

    row.status = "Warping..."
    HV.STATE.status_text = "Warp: " .. row.name
    addLog(string.format("`9[Warp] Memulai warp ke world %s...", row.name))

    if not warpToWorld(row.name, row.door) then
        local _hvOnline = isPlayerOnlineInWorld()
        if not _hvOnline then
            row.status = "DC/Retry"
            addLog("[Warp DC] Koneksi terputus saat warp ke " .. row.name .. " -- world ditahan, bukan Inaccessible.")
            HV.saveData()
            return false
        end
        row.status = "Inaccessible"; HV.saveData(); return false
    end

    if editToggle and HV.CFG.use_modfly ~= false then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(true)
    -- Pastikan world tiles telah termuat sempurna sebelum scan pohon
    waitForWorldTiles(4000)
    safeSleep(600)
    addLog(string.format("`2[Warp] Berhasil masuk ke world %s. Memeriksa pohon matang...", row.name))

    -- Auto-Detect: Cek pohon matang di world. Scan bertahap untuk akurasi maksimal.
    local initialReady = 0
    for testY = 1, 53 do
        for testX = 2, 97 do
            if isReadyTree(testX, testY, seedID, blockID) then
                initialReady = initialReady + 1
                if initialReady >= 2 then break end
            end
        end
        if initialReady >= 2 then break end
    end

    -- Jika pohon sesuai row.item_id tidak ditemukan, jalankan full auto-detect pohon matang di world
    if initialReady == 0 then
        local detectedCounts = {}
        for scY = 1, 53 do
            for scX = 2, 97 do
                local t = getTileSafe(scX, scY)
                if t and isTileTreeReady(t) then
                    local fg = tonumber(t.fg) or 0
                    if fg > 0 and (fg % 2 == 1) then -- hanya seed/tree (ganjil)
                        detectedCounts[fg] = (detectedCounts[fg] or 0) + 1
                    end
                end
            end
        end

        local bestFg, bestCnt = nil, 0
        for fg, cnt in pairs(detectedCounts) do
            if cnt > bestCnt then bestFg = fg; bestCnt = cnt end
        end

        if bestFg and bestCnt > 0 then
            blockID, seedID = normalizeHarvestPair(bestFg)
            row.item_id = blockID
            allowedSet[blockID] = (HV.CFG.take_block ~= false)
            allowedSet[seedID] = (HV.CFG.take_seed ~= false)
            HV.saveData()
            addLog(string.format("`a[Auto-Detect] Terdeteksi %d pohon %s di %s (Seed: %d, Block: %d)", bestCnt, resolveItemName(seedID), row.name, seedID, blockID))
        else
            addLog(string.format("`e[Auto-Detect] Tidak terdeteksi pohon matang yang siap panen di %s.", row.name))
        end
    else
        addLog(string.format("`a[Harvest] Menemukan pohon target %s di %s (Seed: %d, Block: %d)", resolveItemName(seedID), row.name, seedID, blockID))
    end

    local hDelay = math.max(35, tonumber(HV.CFG.harvest_delay) or 70)
    local mode = HV.CFG.harvest_mode or "1by1"

    if mode == "3zigzag" then
        -- Mode 3-Zigzag Klasik
        local treeRows = {}
        for testY = 1, 53 do
            local hasTree = false
            for testX = 2, 97 do
                if isReadyTree(testX, testY, seedID, blockID) then
                    hasTree = true
                    break
                end
            end
            if hasTree then
                table.insert(treeRows, testY)
            end
        end

        local rowCount = 0
        for _, ty in ipairs(treeRows) do
            if not HV.STATE.running then return false end
            rowCount = rowCount + 1
            local l2r = (rowCount % 2 == 1)
            local startX = l2r and 2 or 97
            local endX   = l2r and 97 or 2
            local stepX  = l2r and 1 or -1
            local py = ty + 1

            if not ensureHVOnline(row, true) then return false end
            local x = startX
            while (l2r and x <= endX) or ((not l2r) and x >= endX) do
                if not HV.STATE.running then return false end
                if not ensureHVOnline(row, true) then return false end

                local t1 = isReadyTree(x, ty, seedID, blockID)
                local t2 = isReadyTree(x + stepX, ty, seedID, blockID)
                local t3 = isReadyTree(x + (stepX * 2), ty, seedID, blockID)

                if t1 or t2 or t3 then
                    checkAndDropIfFull(row, blockID, seedID, eventList, false)
                    local standY = py
                    local tFloor = getTileSafe(x, py)
                    if tFloor and tFloor.collidable then standY = ty end
                    moveSafeTo(x, standY)
                    fastTakeAround(allowedSet, 4)

                    if t1 then harvestTreeTile(x, ty, seedID, blockID, hDelay, allowedSet) end
                    if t2 then harvestTreeTile(x + stepX, ty, seedID, blockID, hDelay, allowedSet) end
                    if t3 then harvestTreeTile(x + (stepX * 2), ty, seedID, blockID, hDelay, allowedSet) end

                    fastTakeAround(allowedSet, 4)
                    x = x + (stepX * 3)
                else
                    x = x + stepX
                end
            end
        end
        auditAndFinishRemainingTrees(row, seedID, blockID, hDelay, allowedSet, eventList)
    else
        -- Mode 1-By-1 Tree Serpentine (Default: Halus, Cepat, Auto Collect Tiap Pohon)
        harvest1By1Serpentine(row, seedID, blockID, hDelay, allowedSet, eventList)
        auditAndFinishRemainingTrees(row, seedID, blockID, hDelay, allowedSet, eventList)
    end

    -- Sapu sisa floating block / seed / event jika opsi take_floating aktif
    sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)

    -- Force drop semua hasil yang tersisa di tas sebelum pindah farm
    checkAndDropIfFull(row, blockID, seedID, eventList, true)

    local remainingTrees = #scanWorldReadyTrees(seedID, blockID)
    if not HV.STATE.running then
        row.status = "Ready"
        HV.saveData()
        addLog(string.format("`eWorld %s: Panen dihentikan sebelum selesai (Pohon tersisa: %d).", row.name, remainingTrees))
        return false
    end
    if remainingTrees == 0 and HV.STATE.total_harvested == 0 then
        row.status = "No Ready Trees"
        HV.saveData()
        addLog(string.format("`eWorld %s: Tidak ada pohon matang untuk dipanen.", row.name))
        return true
    end

    row.status = "Done"
    HV.saveData()
    addLog(string.format("`2World %s SELESAI dipanen (Pohon tersisa: %d)!", row.name, remainingTrees))
    return true
end

local function harvestLoopRunner()
    HV.STATE.running = true
    HV.STATE.enabled = true
    if editToggle and HV.CFG.use_modfly ~= false then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(true)
    addLog("`2Auto Harvest dimulai...")

    while HV.STATE.running do
        local allDone = true
        for i, row in ipairs(HV.STATE.rows) do
            if not HV.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" and row.status ~= "Invalid ID" then
                allDone = false
                HV.STATE.selected_idx = i
                local ok = processFarmWorld(row)
                if not ok and not HV.STATE.running then break end
                safeSleep(1000)
            end
        end

        if not HV.STATE.running then break end
        if allDone then
            if HV.CFG.loop_enabled and #HV.STATE.rows > 0 then
                addLog("`eSemua farm selesai, looping antrean diulang!")
                for _, r in ipairs(HV.STATE.rows) do
                    if r.status == "Done" then r.status = "Ready" end
                end
                HV.saveData()
                safeSleep(2000)
            else
                addLog("`2Semua antrean Farm Harvest telah selesai!")
                HV.STATE.status_text = "Done All"
                break
            end
        end
    end

    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Idle"
    HV.saveData()
    addLog("`eAuto Harvest berhenti.")
end

function HV.start()
    if HV.STATE.running then
        addLog("`eAuto Harvest sudah berjalan!")
        return false
    end

    if LogToConsole then pcall(LogToConsole, "`2[BOREN HARVEST] Start Auto Harvest dipicu!") end

    -- Jika daftar farm masih kosong, otomatis masukkan world aktif saat ini
    local curW = getCurrentWorldSafe()
    if #HV.STATE.rows == 0 then
        if curW and curW ~= "" and curW ~= "EXIT" then
            table.insert(HV.STATE.rows, { name = curW, door = "", item_id = HV.CFG.default_item_id, status = "Ready" })
            HV.saveData()
            addLog("`2[Auto] World aktif " .. curW .. " otomatis dimasukkan ke antrean farm!")
        else
            addLog("`4Daftar Farm kosong! Tambahkan world di tab Farm List atau masuk ke world farm.")
            notifyMsg("Daftar Farm kosong!")
            return false
        end
    end

    -- Selalu reset status world agar bisa langsung jalan tanpa tertahan status lama
    for _, r in ipairs(HV.STATE.rows) do
        if curW and r.name == curW then
            r.status = "Ready"
        elseif r.status == "Done" or r.status == "No Ready Trees" or r.status == "DC/Retry" then
            r.status = "Ready"
        end
    end
    HV.saveData()
    addLog("`a[Auto] Status antrean farm di-reset ke Ready!")

    HV.STATE.in_save_world = false
    HV.STATE.in_event_world = false
    HV.STATE.anti_take = false
    HV.STATE.is_dropping = false

    if editToggle and HV.CFG.use_modfly ~= false then
        pcall(editToggle, "ModFly", true)
        pcall(editToggle, "Anti Lava", true)
        pcall(editToggle, "No Lava", true)
    end
    setCollectCheats(true)

    -- Jalankan coroutine dengan pcall pelindung agar error tidak hilang diam-diam
    if runCoroutine then
        local okCoro, errCoro = pcall(runCoroutine, function()
            local okMain, errMain = pcall(harvestLoopRunner)
            if not okMain then
                HV.STATE.running = false
                HV.STATE.enabled = false
                addLog("`4[Runtime Error] " .. tostring(errMain))
                notifyMsg("Harvest Error: " .. tostring(errMain))
            end
        end)
        if not okCoro then
            HV.STATE.running = false
            addLog("`4[Coroutine Error] " .. tostring(errCoro))
            return false
        end
    else
        runAsync(harvestLoopRunner)
    end
    return true
end

function HV.stop()
    if not HV.STATE.running then
        HV.STATE.enabled = false
        return false
    end
    HV.STATE.running = false
    HV.STATE.enabled = false
    setCollectCheats(false)
    HV.STATE.status_text = "Stopping..."
    addLog("Menghentikan bot...")
    return true
end

function HV.init(hub)
    HUB_REF = hub
    HV.loadData()
end

-- ============================================================================

-- ============================================================================
-- 7. REFINED MODULAR COMPACT DIALOG SYSTEM FOR HARVEST (/hv /harvest /boren)
-- 100% Pure ASCII, 5-8 lines max per dialog, no vertical scrollbar
-- ============================================================================

local DLG = {
    farm_page    = 1,
    save_page    = 1,
}

-- ============================================================================
-- 0. MAIN DASHBOARD DIALOG (/hv /harvest)
-- ============================================================================
DLG.showHarvestMainDialog = function()
    local curW = getCurrentWorldSafe()
    if curW == "" then curW = "EXIT" end
    local isRun = HV.STATE.running
    local stBadge = isRun and "`2(Running)" or "`4(Stopped)"
    local fCount = #(HV.STATE.rows or {})
    local sCount = #(HV.STATE.save_rows or {})
    local harvCount = tonumber(HV.STATE.total_harvested) or 0
    local dropCount = tonumber(HV.STATE.total_dropped) or 0
    local modeTxt = (HV.CFG.harvest_mode == "teleport") and "`2(Teleport)" or ((HV.CFG.harvest_mode == "3zigzag") and "`b(3-Zigzag)" or "`e(1by1)")

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wBoren Auto Harvest Pro v2.2.0``|left|1830|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wStatus: %s `p- `wWorld: `b%s `p- `wMode: %s|left|", stBadge, curW, modeTxt),
        string.format("add_textbox|`wFarms: `2(%d) `p- `wSaves: `2(%d) `p- `wTrees: `2(%d) `p- `wDrops: `2(%d)|left|", fCount, sCount, harvCount, dropCount),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
    }
    if not isRun then
        lines[#lines+1] = "add_button|hv_btn_dlg_start|`wStart Auto Harvest `2(Ready)|noflags|0|0|"
    else
        lines[#lines+1] = "add_button|hv_btn_dlg_stop|`wStop Auto Harvest `4(Active)|noflags|0|0|"
    end
    lines[#lines+1] = string.format("add_button|hv_btn_dlg_add_cur_farm|`wAdd World Farm `2(%s)|noflags|0|0|", curW)
    lines[#lines+1] = "add_spacer|small|"
    lines[#lines+1] = string.format("add_button|hv_btn_dlg_farms|`wSetting Farm Multi-World `2(%d World)|noflags|0|0|", fCount)
    lines[#lines+1] = string.format("add_button|hv_btn_dlg_storage|`wSetting Storage Multi-World `2(%d World)|noflags|0|0|", sCount)
    lines[#lines+1] = "add_button|hv_btn_dlg_collect|`wSetting Collect, Ignore & Floating|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_dlg_settings|`wSetting Harvest Engine & Cheats|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_dlg_logs|`wLog Activity & Tas|noflags|0|0|"
    lines[#lines+1] = "add_spacer|small|"
    lines[#lines+1] = "add_button|hv_btn_dlg_close|`wClose|noflags|0|0|"
    lines[#lines+1] = "end_dialog|hv_main|Close||"
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 1. SETTING FARM MULTI-WORLD (HUB + SUB-DIALOGS)
-- ============================================================================
DLG.showHarvestFarmDialog = function()
    local fCount = #(HV.STATE.rows or {})
    local defItem = tonumber(HV.CFG.default_item_id) or 4584

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wSetting Farm Multi-World``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wTotal Registered: `2(%d World) `p- `wDefault Item: `b%d|left|", fCount, defItem),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_button|hv_btn_open_add_farm|`w1. Add Farm World `2(Manual)|noflags|0|0|",
        "add_button|hv_btn_open_batch_farm|`w2. Batch Add Farm World `2(Paste)|noflags|0|0|",
        string.format("add_button|hv_btn_open_list_farm|`w3. List Farm Worlds `2(%d World)|noflags|0|0|", fCount),
        "add_button|hv_btn_open_file_farm|`w4. Backup & File Manager|noflags|0|0|",
        "add_button|hv_btn_dlg_reset_farm_st|`wReset Status Farm `4(Semua Ready)|noflags|0|0|",
        "add_button|hv_btn_dlg_clear_farms|`wClear All Farm Worlds `4(Delete All)|noflags|0|0|",
        "add_spacer|small|",
        "add_button|hv_btn_dlg_back_main|`wBack|noflags|0|0|",
        "end_dialog|hv_farms|Close||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 1.1 Add Single Farm World
DLG.showHarvestAddFarmDialog = function()
    local curW = getCurrentWorldSafe()
    if curW == "" then curW = "EXIT" end
    local defItem = tonumber(HV.CFG.default_item_id) or 4584

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wAdd Farm World``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wMasukkan nama world farm & ID item harvest:|left|",
        "add_textbox|`p(Format: WORLD atau WORLD:DOOR atau WORLD:DOOR:ITEM_ID)|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_text_input|hv_in_farm_name|World Name||32|",
        "add_text_input|hv_in_farm_door|Door ID (Opsional)||16|",
        string.format("add_text_input|hv_in_farm_item|ID Item Harvest (Block/Seed)|%d|8|", defItem),
        "add_spacer|small|",
        "add_button|hv_btn_do_add_farm|`wSave Farm World `2(Add)|noflags|0|0|",
        string.format("add_button|hv_btn_add_cur_farm_sub|`wAdd Current World `2(%s)|noflags|0|0|", curW),
        "add_button|hv_btn_back_farms|`wBack|noflags|0|0|",
        "end_dialog|hv_add_farm|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 1.2 Batch Add Farm Worlds
DLG.showHarvestBatchFarmDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wBatch Add Farm Worlds``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wMasukkan daftar world dipisah spasi, koma atau enter:|left|",
        "add_textbox|`p(Format: FARM1 FARM2:DOOR FARM3:DOOR:4584)|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_text_input|hv_in_batch_farms|World List||80|",
        "add_checkbox|hv_chk_batch_farm_rep|Ganti seluruh daftar (Replace)|0|",
        "add_spacer|small|",
        "add_button|hv_btn_do_batch_farm|`wAdd All Worlds `2(Batch)|noflags|0|0|",
        "add_button|hv_btn_back_farms|`wBack|noflags|0|0|",
        "end_dialog|hv_batch_farm|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 1.3 List Farm Worlds (Paginated 5 per page)
DLG.showHarvestFarmListDialog = function(page)
    local list = HV.STATE.rows or {}
    local count = #list
    local perPage = 5
    local totalPages = math.max(1, math.ceil(count / perPage))
    page = math.max(1, math.min(totalPages, tonumber(page) or 1))
    DLG.farm_page = page

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wList Farm Worlds``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wTotal Registered: `2(%d World) `p- `wPage `2(%d/%d)|left|", count, page, totalPages),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
    }

    if count == 0 then
        lines[#lines+1] = "add_textbox|`4(Antrian world farm masih kosong. Silakan tambah world)|left|"
    else
        local startIdx = (page - 1) * perPage + 1
        local endIdx = math.min(count, startIdx + perPage - 1)
        for i = startIdx, endIdx do
            local item = list[i]
            local dName = (item.door and item.door ~= "") and item.door or "-"
            local st = (item.status == "Done") and "`2[DONE]" or ((item.status == "Warping...") and "`6[WARP]" or "`9[" .. tostring(item.status or "Ready") .. "]")
            lines[#lines+1] = string.format("add_textbox|`w#%d `b%s `p[Door: `e%s`p] `o[Item: %d] %s|left|", i, item.name, dName, item.item_id or HV.CFG.default_item_id, st)
            lines[#lines+1] = string.format("add_button|hv_btn_f_edit_%d|`wEdit `2(#%d)|noflags|0|0|", i, i)
            lines[#lines+1] = string.format("add_button|hv_btn_f_del_%d|`wDelete `4(#%d)|noflags|0|0|", i, i)
            lines[#lines+1] = "add_spacer|small|"
        end
    end

    lines[#lines+1] = "add_spacer|small|"
    if page > 1 then
        lines[#lines+1] = string.format("add_button|hv_btn_f_prev_%d|`w<< Prev Page `2(%d)|noflags|0|0|", page - 1, page - 1)
    end
    if page < totalPages then
        lines[#lines+1] = string.format("add_button|hv_btn_f_next_%d|`wNext Page >> `2(%d)|noflags|0|0|", page + 1, page + 1)
    end
    lines[#lines+1] = "add_button|hv_btn_dlg_clear_farms|`wClear All Worlds `4(Delete All)|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_back_farms|`wBack|noflags|0|0|"
    lines[#lines+1] = "end_dialog|hv_list_farm|Close||"
    showClientDialog(table.concat(lines, "\n"))
end

-- 1.4 Edit Farm World Entry
DLG.showHarvestFarmEditDialog = function(idx)
    idx = tonumber(idx) or 1
    local entry = (HV.STATE.rows or {})[idx]
    if not entry then return DLG.showHarvestFarmListDialog(1) end

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit Farm World #%d: %s``|left|18|", idx, entry.name),
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_text_input|hv_edit_f_name|World Name|%s|32|", entry.name or ""),
        string.format("add_text_input|hv_edit_f_door|Door ID (Opsional)|%s|16|", entry.door or ""),
        string.format("add_text_input|hv_edit_f_item|ID Item Harvest|%d|8|", entry.item_id or HV.CFG.default_item_id),
        string.format("add_checkbox|hv_edit_f_done|Sudah Selesai (DONE)|%d|", (entry.status == "Done") and 1 or 0),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_button|hv_btn_save_f_edit_%d|`wSave Changes `2(Save)|noflags|0|0|", idx),
        string.format("add_button|hv_btn_del_f_edit_%d|`wDelete World `4(Del)|noflags|0|0|", idx),
        "add_button|hv_btn_back_f_list|`wBack|noflags|0|0|",
        string.format("end_dialog|hv_edit_farm_%d|Cancel||", idx)
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 1.5 File & Backup Manager Farm
DLG.showHarvestFileFarmDialog = function()
    local fName = "boren_harvest_farms.txt"
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wBackup & File Manager Farm``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wSimpan atau muat daftar world farm dari file storage lokal:|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_text_input|hv_in_file_farm|Nama File|%s|40|", fName),
        "add_spacer|small|",
        "add_button|hv_btn_do_save_f_file|`wSave Queue ke File `2(Save)|noflags|0|0|",
        "add_button|hv_btn_do_load_f_file|`wLoad Queue dari File `2(Load)|noflags|0|0|",
        "add_button|hv_btn_back_farms|`wBack|noflags|0|0|",
        "end_dialog|hv_file_farm|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 2. SETTING STORAGE MULTI-WORLD (HUB + SUB-DIALOGS)
-- ============================================================================
DLG.showHarvestStorageDialog = function()
    local sCount = #(HV.STATE.save_rows or {})
    local defLimit = tonumber(HV.CFG.default_save_limit) or 20000
    local dropThresh = tonumber(HV.CFG.drop_threshold) or 200

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wSetting Storage Multi-World``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wTotal Save: `2(%d World) `p- `wDefault Limit: `2(%d)|left|", sCount, defLimit),
        string.format("add_textbox|`wDrop Threshold di Tas: `b%d Item|left|", dropThresh),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_button|hv_btn_open_add_save|`w1. Add Save World `2(Manual)|noflags|0|0|",
        "add_button|hv_btn_open_batch_save|`w2. Batch Add Save World `2(Paste)|noflags|0|0|",
        string.format("add_button|hv_btn_open_list_save|`w3. List Save Worlds `2(%d World)|noflags|0|0|", sCount),
        "add_button|hv_btn_open_limit_cfg|`w4. Custom Limit & Threshold Drop|noflags|0|0|",
        "add_button|hv_btn_open_file_save|`w5. Backup & File Manager|noflags|0|0|",
        "add_button|hv_btn_dlg_reset_save_st|`wReset Status Storage `4(Semua Ready)|noflags|0|0|",
        "add_button|hv_btn_dlg_clear_saves|`wClear All Save Worlds `4(Delete All)|noflags|0|0|",
        "add_spacer|small|",
        "add_button|hv_btn_dlg_back_main|`wBack|noflags|0|0|",
        "end_dialog|hv_storage|Close||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.1 Add Single Save World
DLG.showHarvestAddSaveDialog = function()
    local curW = getCurrentWorldSafe()
    if curW == "" then curW = "EXIT" end
    local defLimit = tonumber(HV.CFG.default_save_limit) or 20000

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wAdd Save World``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wMasukkan data world gudang penyimpanan hasil panen:|left|",
        "add_textbox|`p(Tipe: ALL = Block + Seed, BLOCK = Hanya Block, SEED = Hanya Seed)|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_text_input|hv_in_save_name|World Name||32|",
        "add_text_input|hv_in_save_door|Door ID (Opsional)||16|",
        "add_text_input|hv_in_save_type|Tipe Simpan (ALL/BLOCK/SEED)|ALL|8|",
        string.format("add_text_input|hv_in_save_limit|Max Limit Item (0 = Unlimited)|%d|10|", defLimit),
        "add_spacer|small|",
        "add_button|hv_btn_do_add_save|`wSave World `2(Add)|noflags|0|0|",
        string.format("add_button|hv_btn_add_cur_save_sub|`wAdd Current World `2(%s)|noflags|0|0|", curW),
        "add_button|hv_btn_back_storage|`wBack|noflags|0|0|",
        "end_dialog|hv_add_save|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.2 Batch Add Save Worlds
DLG.showHarvestBatchSaveDialog = function()
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wBatch Add Save Worlds``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wMasukkan daftar save world dipisah spasi, koma atau enter:|left|",
        "add_textbox|`p(Format: SAVE1:DOOR:ALL:20000 SAVE2:DOOR:BLOCK:50000)|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_text_input|hv_in_batch_saves|Save World List||80|",
        "add_checkbox|hv_chk_batch_save_rep|Ganti seluruh daftar (Replace)|0|",
        "add_spacer|small|",
        "add_button|hv_btn_do_batch_save|`wAdd All Worlds `2(Batch)|noflags|0|0|",
        "add_button|hv_btn_back_storage|`wBack|noflags|0|0|",
        "end_dialog|hv_batch_save|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.3 List Save Worlds (Paginated 5 per page)
DLG.showHarvestSaveListDialog = function(page)
    local list = HV.STATE.save_rows or {}
    local count = #list
    local perPage = 5
    local totalPages = math.max(1, math.ceil(count / perPage))
    page = math.max(1, math.min(totalPages, tonumber(page) or 1))
    DLG.save_page = page

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wList Save Worlds``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wTotal Registered: `2(%d World) `p- `wPage `2(%d/%d)|left|", count, page, totalPages),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
    }

    if count == 0 then
        lines[#lines+1] = "add_textbox|`4(Daftar Save World masih kosong. Silakan tambah gudang)|left|"
    else
        local startIdx = (page - 1) * perPage + 1
        local endIdx = math.min(count, startIdx + perPage - 1)
        for i = startIdx, endIdx do
            local item = list[i]
            local dName = (item.door and item.door ~= "") and item.door or "-"
            local limTxt = (tonumber(item.limit) and tonumber(item.limit) > 0) and tostring(item.limit) or "Unlim"
            local cntTxt = tostring(item.count or 0)
            local st = (item.status == "Full") and "`4[FULL]" or "`2[" .. tostring(item.status or "Ready") .. "]"
            lines[#lines+1] = string.format("add_textbox|`w#%d `b%s `p[Door: `e%s`p] `o[%s] `2(%s/%s) %s|left|", i, item.name, dName, item.save_type or "ALL", cntTxt, limTxt, st)
            lines[#lines+1] = string.format("add_button|hv_btn_s_edit_%d|`wEdit `2(#%d)|noflags|0|0|", i, i)
            lines[#lines+1] = string.format("add_button|hv_btn_s_del_%d|`wDelete `4(#%d)|noflags|0|0|", i, i)
            lines[#lines+1] = "add_spacer|small|"
        end
    end

    lines[#lines+1] = "add_spacer|small|"
    if page > 1 then
        lines[#lines+1] = string.format("add_button|hv_btn_s_prev_%d|`w<< Prev Page `2(%d)|noflags|0|0|", page - 1, page - 1)
    end
    if page < totalPages then
        lines[#lines+1] = string.format("add_button|hv_btn_s_next_%d|`wNext Page >> `2(%d)|noflags|0|0|", page + 1, page + 1)
    end
    lines[#lines+1] = "add_button|hv_btn_dlg_clear_saves|`wClear All Save Worlds `4(Delete All)|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_back_storage|`wBack|noflags|0|0|"
    lines[#lines+1] = "end_dialog|hv_list_save|Close||"
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.4 Edit Save World Entry
DLG.showHarvestSaveEditDialog = function(idx)
    idx = tonumber(idx) or 1
    local entry = (HV.STATE.save_rows or {})[idx]
    if not entry then return DLG.showHarvestSaveListDialog(1) end

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        string.format("add_label_with_icon|big|`wEdit Save World #%d: %s``|left|3802|", idx, entry.name),
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_text_input|hv_edit_s_name|World Name|%s|32|", entry.name or ""),
        string.format("add_text_input|hv_edit_s_door|Door ID (Opsional)|%s|16|", entry.door or ""),
        string.format("add_text_input|hv_edit_s_type|Tipe Simpan (ALL/BLOCK/SEED)|%s|8|", entry.save_type or "ALL"),
        string.format("add_text_input|hv_edit_s_limit|Max Limit Item (0 = Unlimited)|%d|10|", tonumber(entry.limit) or 20000),
        string.format("add_checkbox|hv_edit_s_full|Status Penuh (FULL)|%d|", (entry.status == "Full") and 1 or 0),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_button|hv_btn_save_s_edit_%d|`wSave Changes `2(Save)|noflags|0|0|", idx),
        string.format("add_button|hv_btn_del_s_edit_%d|`wDelete World `4(Del)|noflags|0|0|", idx),
        "add_button|hv_btn_back_s_list|`wBack|noflags|0|0|",
        string.format("end_dialog|hv_edit_save_%d|Cancel||", idx)
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.5 Custom Limit & Threshold Drop
DLG.showHarvestLimitConfigDialog = function()
    local dropThresh = tonumber(HV.CFG.drop_threshold) or 200
    local defLimit = tonumber(HV.CFG.default_save_limit) or 20000

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wCustom Limit & Drop Threshold``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wAtur batas kapasitas drop per world & batas isi tas:|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_text_input|hv_in_drop_threshold|Drop Threshold di Tas (Default 200)|%d|6|", dropThresh),
        string.format("add_text_input|hv_in_default_save_limit|Default Limit per Save World|%d|10|", defLimit),
        "add_spacer|small|",
        "add_button|hv_btn_preset_10k|`wPreset Limit: 10.000 `2(10k)|noflags|0|0|",
        "add_button|hv_btn_preset_20k|`wPreset Limit: 20.000 `2(20k)|noflags|0|0|",
        "add_button|hv_btn_preset_50k|`wPreset Limit: 50.000 `2(50k)|noflags|0|0|",
        "add_button|hv_btn_preset_unlimited|`wPreset Limit: Unlimited `2(Tanpa Batas)|noflags|0|0|",
        "add_spacer|small|",
        "add_button|hv_btn_save_limit_cfg|`wSave Config `2(Save)|noflags|0|0|",
        "add_button|hv_btn_back_storage|`wBack|noflags|0|0|",
        "end_dialog|hv_limit_cfg|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- 2.6 Backup & File Manager Storage
DLG.showHarvestFileSaveDialog = function()
    local fName = "boren_harvest_storages.txt"
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wBackup & File Manager Storage``|left|3802|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wSimpan atau muat daftar save world dari file storage lokal:|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_text_input|hv_in_file_save|Nama File|%s|40|", fName),
        "add_spacer|small|",
        "add_button|hv_btn_do_save_s_file|`wSave Queue ke File `2(Save)|noflags|0|0|",
        "add_button|hv_btn_do_load_s_file|`wLoad Queue dari File `2(Load)|noflags|0|0|",
        "add_button|hv_btn_back_storage|`wBack|noflags|0|0|",
        "end_dialog|hv_file_save|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 3. SETTING COLLECT, IGNORE & FLOATING
-- ============================================================================
DLG.showHarvestCollectDialog = function()
    local c = HV.CFG
    local ignGems = (c.ignore_gems ~= false) and 1 or 0
    local autoCol = (c.auto_collect ~= false) and 1 or 0
    local tkBlock = (c.take_block ~= false) and 1 or 0
    local tkSeed = (c.take_seed ~= false) and 1 or 0
    local tkFloat = (c.take_floating == true) and 1 or 0
    local ignDrop = (c.ignore_take_drop ~= false) and 1 or 0
    local cRange = tonumber(c.collect_range) or 4

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wSetting Collect, Ignore & Floating``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wKonfigurasi ignore gems, auto collect & anti retake saat drop:|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_checkbox|hv_chk_ignore_gems|Abaikan Gems ID 112 (Anti Tas Penuh Gems)|%d|", ignGems),
        string.format("add_checkbox|hv_chk_auto_collect|Auto Collect Hasil Harvest (Block & Seed)|%d|", autoCol),
        string.format("add_checkbox|hv_chk_take_block|Ambil Block Hasil Harvest|%d|", tkBlock),
        string.format("add_checkbox|hv_chk_take_seed|Ambil Seed Hasil Harvest|%d|", tkSeed),
        string.format("add_checkbox|hv_chk_take_floating|Take Floating Block & Seed di Farm World|%d|", tkFloat),
        string.format("add_checkbox|hv_chk_ignore_take_drop|Ignore Take saat Drop di Save World (Anti Retake)|%d|", ignDrop),
        string.format("add_text_input|hv_in_collect_range|Radius Collect di Sekitar Bot (1-6)|%d|4|", cRange),
        "add_spacer|small|",
        "add_button|hv_btn_save_collect_cfg|`wSave Collect Settings `2(Save)|noflags|0|0|",
        "add_button|hv_btn_dlg_back_main|`wBack|noflags|0|0|",
        "end_dialog|hv_collect|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 4. SETTING HARVEST ENGINE & CHEATS
-- ============================================================================
DLG.showHarvestSettingsDialog = function()
    local c = HV.CFG
    local isTele = (c.harvest_mode == "teleport") and 1 or 0
    local is3Z = (c.harvest_mode == "3zigzag") and 1 or 0
    local mFly = (c.use_modfly == true) and 1 or 0
    local loopEn = (c.loop_enabled == true) and 1 or 0
    local hDel = tonumber(c.harvest_delay) or 180
    local sDel = tonumber(c.step_delay) or 110
    local wDel = tonumber(c.warp_delay) or 4500

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wSetting Harvest Engine & Cheats``|left|32|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_textbox|`wKonfigurasi mode panen, kecepatan delay bot & cheat:|left|",
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        string.format("add_checkbox|hv_chk_mode_teleport|Mode Teleport Per-Tree (Cepat & Akurat)|%d|", isTele),
        string.format("add_checkbox|hv_chk_mode_zigzag|Mode 3-Zigzag Serpentine|%d|", is3Z),
        string.format("add_checkbox|hv_chk_modfly|Aktifkan Modfly (Terbang Tembus Rintangan)|%d|", mFly),
        string.format("add_checkbox|hv_chk_loop|Loop Antrean Farm Terus Menerus|%d|", loopEn),
        string.format("add_text_input|hv_in_harvest_delay|Delay Harvest / Punch (ms)|%d|6|", hDel),
        string.format("add_text_input|hv_in_step_delay|Delay Langkah / Gerak (ms)|%d|6|", sDel),
        string.format("add_text_input|hv_in_warp_delay|Delay Warp World (ms)|%d|6|", wDel),
        "add_spacer|small|",
        "add_button|hv_btn_save_settings_cfg|`wSave Settings `2(Save)|noflags|0|0|",
        "add_button|hv_btn_dlg_back_main|`wBack|noflags|0|0|",
        "end_dialog|hv_settings|Cancel||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- 5. LOG AKTIVITAS & TAS (COMPACT)
-- ============================================================================
DLG.showHarvestLogsDialog = function()
    local logs = HV.STATE.logs or {}
    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wLog Activity & Backpack``|left|32|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
    }
    if #logs == 0 then
        lines[#lines+1] = "add_textbox|`oBelum ada catatan aktivitas panen.|left|"
    else
        local startIdx = math.max(1, #logs - 6)
        for i = startIdx, #logs do
            local cleanLine = tostring(logs[i] or ""):gsub("[\r\n]+", " ")
            if #cleanLine > 60 then cleanLine = cleanLine:sub(1, 57) .. "..." end
            lines[#lines+1] = string.format("add_textbox|%s|left|", cleanLine)
        end
    end
    lines[#lines+1] = "add_textbox|`p------------------------------------------------------------|left|"
    lines[#lines+1] = "add_spacer|small|"
    lines[#lines+1] = "add_button|hv_btn_dlg_clear_logs|`wBersihkan Log|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_open_bag_view|`wLihat Isi Tas / Backpack `2(Bag)|noflags|0|0|"
    lines[#lines+1] = "add_button|hv_btn_dlg_back_main|`wBack|noflags|0|0|"
    lines[#lines+1] = "end_dialog|hv_logs|Close||"
    showClientDialog(table.concat(lines, "\n"))
end

DLG.showHarvestBagDialog = function()
    local curFarm = HV.STATE.rows[HV.STATE.selected_idx]
    local bID, sID = normalizeHarvestPair((curFarm and curFarm.item_id) or HV.CFG.default_item_id)
    local blockCount = getInvCount(bID)
    local seedCount = getInvCount(sID)
    local fuelCount = getInvCount(1746)
    local gemsCount = getInvCount(112)
    local dcsCount = getInvCount(6840)
    local harvCount = getInvCount(1830) + getInvCount(1966)

    local lines = {
        "set_default_color|`o",
        "add_quick_exit|",
        "add_label_with_icon|big|`wIsi Tas / Backpack``|left|18|",
        "add_spacer|small|",
        "add_textbox|`p------------------------------------------------------------|left|",
        string.format("add_textbox|`wBlock (#%d): `2%d item `p- `wSeed (#%d): `2%d item|left|", bID, blockCount, sID, seedCount),
        string.format("add_textbox|`wFuel Pack (#1746): `2%d `p- `wGems (#112): `e%d|left|", fuelCount, gemsCount),
        string.format("add_textbox|`wDCS (#6840): `2%d `p- `wHarvester: `2%d|left|", dcsCount, harvCount),
        "add_textbox|`p------------------------------------------------------------|left|",
        "add_spacer|small|",
        "add_button|hv_btn_refresh_bag_dlg|`wRefresh Tas `2(Update)|noflags|0|0|",
        "add_button|hv_btn_back_logs|`wBack|noflags|0|0|",
        "end_dialog|hv_bag|Close||"
    }
    showClientDialog(table.concat(lines, "\n"))
end

-- ============================================================================
-- COMPACT DIALOG PACKET RETURN HANDLER & PACKET HOOK
-- ============================================================================
local function handleHarvestDialogReturn(pkt)
    if not pkt or type(pkt) ~= "string" then return false end
    local fields = {}
    for line in pkt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([^|]+)|(.*)$")
        if k then
            v = v:gsub("^%s+", ""):gsub("%s+$", "")
            if v:sub(-1) == "|" then v = v:sub(1, -2) end
            fields[k] = v
        end
    end
    local dName = fields.dialog_name or pkt:match("dialog_name|([^|\r\n]+)") or ""
    local btn = fields.buttonClicked or pkt:match("buttonClicked|([^|\r\n]+)") or ""

    local function getVal(key)
        local val = fields[key] or pkt:match(key .. "|([^|\r\n]+)") or ""
        val = val:gsub("^%s+", ""):gsub("%s+$", "")
        if val:sub(-1) == "|" then val = val:sub(1, -2) end
        return val
    end
    local function getNum(key, default)
        local val = getVal(key)
        local n = tonumber(val:match("(%d+)"))
        return n or default
    end

    -- --- A. MAIN DIALOG ---
    if dName == "hv_main" or pkt:find("dialog_name|hv_main", 1, true) then
        if btn == "hv_btn_dlg_start" or pkt:find("buttonClicked|hv_btn_dlg_start", 1, true) then
            if not HV.STATE.running then HV.start() end
            DLG.showHarvestMainDialog()
            return true
        elseif btn == "hv_btn_dlg_stop" or pkt:find("buttonClicked|hv_btn_dlg_stop", 1, true) then
            HV.stop()
            DLG.showHarvestMainDialog()
            return true
        elseif btn == "hv_btn_dlg_add_cur_farm" or pkt:find("buttonClicked|hv_btn_dlg_add_cur_farm", 1, true) then
            local cw = getCurrentWorldSafe()
            if cw and cw ~= "" and cw ~= "EXIT" then
                local exists = false
                for _, w in ipairs(HV.STATE.rows or {}) do
                    if w.name == cw then exists = true; break end
                end
                if not exists then
                    table.insert(HV.STATE.rows, { name = cw, door = "", item_id = HV.CFG.default_item_id, status = "Ready" })
                    HV.saveData()
                    notifyMsg("World " .. cw .. " ditambahkan ke Farm List!")
                else
                    notifyMsg(cw .. " sudah ada di Farm List!")
                end
            end
            DLG.showHarvestMainDialog()
            return true
        elseif btn == "hv_btn_dlg_farms" or pkt:find("buttonClicked|hv_btn_dlg_farms", 1, true) then
            DLG.showHarvestFarmDialog()
            return true
        elseif btn == "hv_btn_dlg_storage" or pkt:find("buttonClicked|hv_btn_dlg_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        elseif btn == "hv_btn_dlg_collect" or pkt:find("buttonClicked|hv_btn_dlg_collect", 1, true) then
            DLG.showHarvestCollectDialog()
            return true
        elseif btn == "hv_btn_dlg_settings" or pkt:find("buttonClicked|hv_btn_dlg_settings", 1, true) then
            DLG.showHarvestSettingsDialog()
            return true
        elseif btn == "hv_btn_dlg_logs" or pkt:find("buttonClicked|hv_btn_dlg_logs", 1, true) then
            DLG.showHarvestLogsDialog()
            return true
        elseif btn == "hv_btn_dlg_close" or pkt:find("buttonClicked|hv_btn_dlg_close", 1, true) then
            return true
        end
        return true

    -- --- B. SETTING FARM MULTI-WORLD ---
    elseif dName == "hv_farms" or pkt:find("dialog_name|hv_farms", 1, true) then
        if btn == "hv_btn_open_add_farm" or pkt:find("buttonClicked|hv_btn_open_add_farm", 1, true) then
            DLG.showHarvestAddFarmDialog()
            return true
        elseif btn == "hv_btn_open_batch_farm" or pkt:find("buttonClicked|hv_btn_open_batch_farm", 1, true) then
            DLG.showHarvestBatchFarmDialog()
            return true
        elseif btn == "hv_btn_open_list_farm" or pkt:find("buttonClicked|hv_btn_open_list_farm", 1, true) then
            DLG.showHarvestFarmListDialog(1)
            return true
        elseif btn == "hv_btn_open_file_farm" or pkt:find("buttonClicked|hv_btn_open_file_farm", 1, true) then
            DLG.showHarvestFileFarmDialog()
            return true
        elseif btn == "hv_btn_dlg_reset_farm_st" or pkt:find("buttonClicked|hv_btn_dlg_reset_farm_st", 1, true) then
            for _, r in ipairs(HV.STATE.rows or {}) do r.status = "Ready" end
            HV.saveData()
            notifyMsg("Status antrean farm di-reset ke Ready!")
            DLG.showHarvestFarmDialog()
            return true
        elseif btn == "hv_btn_dlg_clear_farms" or pkt:find("buttonClicked|hv_btn_dlg_clear_farms", 1, true) then
            HV.STATE.rows = {}
            HV.saveData()
            notifyMsg("Semua farm world di-clear!")
            DLG.showHarvestFarmDialog()
            return true
        elseif btn == "hv_btn_dlg_back_main" or pkt:find("buttonClicked|hv_btn_dlg_back_main", 1, true) then
            DLG.showHarvestMainDialog()
            return true
        end
        return true

    -- Add Single Farm
    elseif dName == "hv_add_farm" or pkt:find("dialog_name|hv_add_farm", 1, true) then
        if btn == "hv_btn_do_add_farm" or pkt:find("buttonClicked|hv_btn_do_add_farm", 1, true) then
            local rawW = getVal("hv_in_farm_name"):upper():gsub("%s+", "")
            local wDoor = getVal("hv_in_farm_door"):gsub("%s+", "")
            local itm = getNum("hv_in_farm_item", HV.CFG.default_item_id)
            local wName = rawW
            if rawW:find(":") then
                local parts = {}
                for token in rawW:gmatch("[^:]+") do table.insert(parts, token) end
                wName = parts[1] or ""
                wDoor = parts[2] or wDoor
                if parts[3] and tonumber(parts[3]) then itm = tonumber(parts[3]) end
            end
            if wName and wName ~= "" and wName ~= "0" and wName ~= "EXIT" then
                local exists = false
                for _, w in ipairs(HV.STATE.rows or {}) do
                    if w.name == wName then exists = true; break end
                end
                if not exists then
                    table.insert(HV.STATE.rows, { name = wName, door = wDoor or "", item_id = itm, status = "Ready" })
                    HV.saveData()
                    notifyMsg("Farm World " .. wName .. " ditambahkan!")
                else
                    notifyMsg(wName .. " sudah ada di antrean!")
                end
            end
            DLG.showHarvestFarmDialog()
            return true
        elseif btn == "hv_btn_add_cur_farm_sub" or pkt:find("buttonClicked|hv_btn_add_cur_farm_sub", 1, true) then
            local cw = getCurrentWorldSafe()
            if cw and cw ~= "" and cw ~= "EXIT" then
                local exists = false
                for _, w in ipairs(HV.STATE.rows or {}) do
                    if w.name == cw then exists = true; break end
                end
                if not exists then
                    table.insert(HV.STATE.rows, { name = cw, door = "", item_id = HV.CFG.default_item_id, status = "Ready" })
                    HV.saveData()
                    notifyMsg("Farm World " .. cw .. " ditambahkan!")
                else
                    notifyMsg(cw .. " sudah ada di antrean!")
                end
            end
            DLG.showHarvestAddFarmDialog()
            return true
        elseif btn == "hv_btn_back_farms" or pkt:find("buttonClicked|hv_btn_back_farms", 1, true) then
            DLG.showHarvestFarmDialog()
            return true
        end
        return true

    -- Batch Add Farm
    elseif dName == "hv_batch_farm" or pkt:find("dialog_name|hv_batch_farm", 1, true) then
        if btn == "hv_btn_do_batch_farm" or pkt:find("buttonClicked|hv_btn_do_batch_farm", 1, true) then
            local raw = getVal("hv_in_batch_farms")
            local rep = (getVal("hv_chk_batch_farm_rep") == "1")
            if rep then HV.STATE.rows = {} end
            local added = 0
            for token in raw:gmatch("[^\r\n,;%s]+") do
                local p = parseFarmRow(token)
                if p and p.name ~= "" and p.name ~= "EXIT" then
                    local exists = false
                    for _, w in ipairs(HV.STATE.rows or {}) do
                        if w.name == p.name then exists = true; break end
                    end
                    if not exists then
                        table.insert(HV.STATE.rows, p)
                        added = added + 1
                    end
                end
            end
            HV.saveData()
            notifyMsg(string.format("%d Farm World ditambahkan!", added))
            DLG.showHarvestFarmDialog()
            return true
        elseif btn == "hv_btn_back_farms" or pkt:find("buttonClicked|hv_btn_back_farms", 1, true) then
            DLG.showHarvestFarmDialog()
            return true
        end
        return true

    -- List Farm Worlds
    elseif dName == "hv_list_farm" or pkt:find("dialog_name|hv_list_farm", 1, true) then
        local prevP = btn:match("hv_btn_f_prev_(%d+)")
        local nextP = btn:match("hv_btn_f_next_(%d+)")
        local editIdx = btn:match("hv_btn_f_edit_(%d+)")
        local delIdx = btn:match("hv_btn_f_del_(%d+)")

        if prevP then
            DLG.showHarvestFarmListDialog(tonumber(prevP))
            return true
        elseif nextP then
            DLG.showHarvestFarmListDialog(tonumber(nextP))
            return true
        elseif editIdx then
            DLG.showHarvestFarmEditDialog(tonumber(editIdx))
            return true
        elseif delIdx then
            local idx = tonumber(delIdx)
            if idx and HV.STATE.rows[idx] then
                table.remove(HV.STATE.rows, idx)
                HV.saveData()
                notifyMsg("Farm World #" .. idx .. " dihapus!")
            end
            DLG.showHarvestFarmListDialog(DLG.farm_page or 1)
            return true
        elseif btn == "hv_btn_dlg_clear_farms" or pkt:find("buttonClicked|hv_btn_dlg_clear_farms", 1, true) then
            HV.STATE.rows = {}
            HV.saveData()
            notifyMsg("Semua farm world di-clear!")
            DLG.showHarvestFarmListDialog(1)
            return true
        elseif btn == "hv_btn_back_farms" or pkt:find("buttonClicked|hv_btn_back_farms", 1, true) then
            DLG.showHarvestFarmDialog()
            return true
        end
        return true

    -- Edit Farm World
    elseif dName:find("^hv_edit_farm_(%d+)$") or pkt:find("dialog_name|hv_edit_farm_", 1, true) then
        local idx = tonumber(dName:match("^hv_edit_farm_(%d+)") or pkt:match("dialog_name|hv_edit_farm_(%d+)"))
        if not idx then
            idx = tonumber(btn:match("hv_btn_save_f_edit_(%d+)") or btn:match("hv_btn_del_f_edit_(%d+)"))
        end
        if idx and HV.STATE.rows[idx] then
            if btn:find("hv_btn_save_f_edit_") or pkt:find("buttonClicked|hv_btn_save_f_edit_", 1, true) then
                local newName = getVal("hv_edit_f_name"):upper():gsub("%s+", "")
                local newDoor = getVal("hv_edit_f_door"):gsub("%s+", "")
                local newItm = getNum("hv_edit_f_item", HV.CFG.default_item_id)
                local newDone = (getVal("hv_edit_f_done") == "1")
                if newName ~= "" and newName ~= "0" and newName ~= "EXIT" then
                    HV.STATE.rows[idx].name = newName
                    HV.STATE.rows[idx].door = newDoor
                    HV.STATE.rows[idx].item_id = newItm
                    HV.STATE.rows[idx].status = newDone and "Done" or "Ready"
                    HV.saveData()
                    notifyMsg("Farm #" .. idx .. " diupdate!")
                end
                DLG.showHarvestFarmListDialog(DLG.farm_page or 1)
                return true
            elseif btn:find("hv_btn_del_f_edit_") or pkt:find("buttonClicked|hv_btn_del_f_edit_", 1, true) then
                table.remove(HV.STATE.rows, idx)
                HV.saveData()
                notifyMsg("Farm #" .. idx .. " dihapus!")
                DLG.showHarvestFarmListDialog(DLG.farm_page or 1)
                return true
            end
        end
        if btn == "hv_btn_back_f_list" or pkt:find("buttonClicked|hv_btn_back_f_list", 1, true) then
            DLG.showHarvestFarmListDialog(DLG.farm_page or 1)
            return true
        end
        return true

    -- File Farm
    elseif dName == "hv_file_farm" or pkt:find("dialog_name|hv_file_farm", 1, true) then
        local fn = getVal("hv_in_file_farm")
        if fn == "" then fn = "boren_harvest_farms.txt" end
        if btn == "hv_btn_do_save_f_file" or pkt:find("buttonClicked|hv_btn_do_save_f_file", 1, true) then
            local lines = {}
            for _, r in ipairs(HV.STATE.rows or {}) do
                table.insert(lines, string.format("%s:%s:%d", r.name, r.door or "", r.item_id or HV.CFG.default_item_id))
            end
            local okW = safeWriteFile(fn, table.concat(lines, "\n"))
            if okW then notifyMsg(string.format("Antrean disimpan ke %s (%d world)", fn, #lines))
            else notifyMsg("Gagal menyimpan ke " .. fn) end
            DLG.showHarvestFileFarmDialog()
            return true
        elseif btn == "hv_btn_do_load_f_file" or pkt:find("buttonClicked|hv_btn_do_load_f_file", 1, true) then
            local content = safeReadFile(fn)
            if content and content ~= "" then
                local added = 0
                for token in content:gmatch("[^\r\n,;%s]+") do
                    local p = parseFarmRow(token)
                    if p and p.name ~= "" and p.name ~= "EXIT" then
                        table.insert(HV.STATE.rows, p)
                        added = added + 1
                    end
                end
                HV.saveData()
                notifyMsg(string.format("%d Farm dimuat dari %s!", added, fn))
            else
                notifyMsg("Gagal membaca file: " .. fn)
            end
            DLG.showHarvestFileFarmDialog()
            return true
        elseif btn == "hv_btn_back_farms" or pkt:find("buttonClicked|hv_btn_back_farms", 1, true) then
            DLG.showHarvestFarmDialog()
            return true
        end
        return true

    -- --- C. SETTING STORAGE MULTI-WORLD ---
    elseif dName == "hv_storage" or pkt:find("dialog_name|hv_storage", 1, true) then
        if btn == "hv_btn_open_add_save" or pkt:find("buttonClicked|hv_btn_open_add_save", 1, true) then
            DLG.showHarvestAddSaveDialog()
            return true
        elseif btn == "hv_btn_open_batch_save" or pkt:find("buttonClicked|hv_btn_open_batch_save", 1, true) then
            DLG.showHarvestBatchSaveDialog()
            return true
        elseif btn == "hv_btn_open_list_save" or pkt:find("buttonClicked|hv_btn_open_list_save", 1, true) then
            DLG.showHarvestSaveListDialog(1)
            return true
        elseif btn == "hv_btn_open_limit_cfg" or pkt:find("buttonClicked|hv_btn_open_limit_cfg", 1, true) then
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_open_file_save" or pkt:find("buttonClicked|hv_btn_open_file_save", 1, true) then
            DLG.showHarvestFileSaveDialog()
            return true
        elseif btn == "hv_btn_dlg_reset_save_st" or pkt:find("buttonClicked|hv_btn_dlg_reset_save_st", 1, true) then
            for _, r in ipairs(HV.STATE.save_rows or {}) do r.status = "Ready"; r.count = 0 end
            HV.saveData()
            notifyMsg("Status semua save world di-reset ke Ready!")
            DLG.showHarvestStorageDialog()
            return true
        elseif btn == "hv_btn_dlg_clear_saves" or pkt:find("buttonClicked|hv_btn_dlg_clear_saves", 1, true) then
            HV.STATE.save_rows = {}
            HV.saveData()
            notifyMsg("Semua save world di-clear!")
            DLG.showHarvestStorageDialog()
            return true
        elseif btn == "hv_btn_dlg_back_main" or pkt:find("buttonClicked|hv_btn_dlg_back_main", 1, true) then
            DLG.showHarvestMainDialog()
            return true
        end
        return true

    -- Add Single Save World
    elseif dName == "hv_add_save" or pkt:find("dialog_name|hv_add_save", 1, true) then
        if btn == "hv_btn_do_add_save" or pkt:find("buttonClicked|hv_btn_do_add_save", 1, true) then
            local rawW = getVal("hv_in_save_name"):upper():gsub("%s+", "")
            local wDoor = getVal("hv_in_save_door"):gsub("%s+", "")
            local sType = getVal("hv_in_save_type"):upper():gsub("%s+", "")
            if sType ~= "BLOCK" and sType ~= "SEED" then sType = "ALL" end
            local sLim = getNum("hv_in_save_limit", HV.CFG.default_save_limit)
            local wName = rawW
            if rawW:find(":") then
                local parts = {}
                for token in rawW:gmatch("[^:]+") do table.insert(parts, token) end
                wName = parts[1] or ""
                wDoor = parts[2] or wDoor
                if parts[3] then sType = parts[3]:upper() end
                if parts[4] and tonumber(parts[4]) then sLim = tonumber(parts[4]) end
            end
            if wName and wName ~= "" and wName ~= "0" and wName ~= "EXIT" then
                local exists = false
                for _, w in ipairs(HV.STATE.save_rows or {}) do
                    if w.name == wName then exists = true; break end
                end
                if not exists then
                    table.insert(HV.STATE.save_rows, { name = wName, door = wDoor or "", save_type = sType, limit = sLim, count = 0, status = "Ready" })
                    HV.saveData()
                    notifyMsg("Save World " .. wName .. " ditambahkan!")
                else
                    notifyMsg(wName .. " sudah ada di Save World!")
                end
            end
            DLG.showHarvestStorageDialog()
            return true
        elseif btn == "hv_btn_add_cur_save_sub" or pkt:find("buttonClicked|hv_btn_add_cur_save_sub", 1, true) then
            local cw = getCurrentWorldSafe()
            if cw and cw ~= "" and cw ~= "EXIT" then
                local exists = false
                for _, w in ipairs(HV.STATE.save_rows or {}) do
                    if w.name == cw then exists = true; break end
                end
                if not exists then
                    table.insert(HV.STATE.save_rows, { name = cw, door = "", save_type = "ALL", limit = HV.CFG.default_save_limit, count = 0, status = "Ready" })
                    HV.saveData()
                    notifyMsg("Save World " .. cw .. " ditambahkan!")
                else
                    notifyMsg(cw .. " sudah ada di Save World!")
                end
            end
            DLG.showHarvestAddSaveDialog()
            return true
        elseif btn == "hv_btn_back_storage" or pkt:find("buttonClicked|hv_btn_back_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        end
        return true

    -- Batch Add Save Worlds
    elseif dName == "hv_batch_save" or pkt:find("dialog_name|hv_batch_save", 1, true) then
        if btn == "hv_btn_do_batch_save" or pkt:find("buttonClicked|hv_btn_do_batch_save", 1, true) then
            local raw = getVal("hv_in_batch_saves")
            local rep = (getVal("hv_chk_batch_save_rep") == "1")
            if rep then HV.STATE.save_rows = {} end
            local added = 0
            for token in raw:gmatch("[^\r\n,;%s]+") do
                local p = parseSaveRow(token)
                if p and p.name ~= "" and p.name ~= "EXIT" then
                    local exists = false
                    for _, w in ipairs(HV.STATE.save_rows or {}) do
                        if w.name == p.name then exists = true; break end
                    end
                    if not exists then
                        table.insert(HV.STATE.save_rows, p)
                        added = added + 1
                    end
                end
            end
            HV.saveData()
            notifyMsg(string.format("%d Save World ditambahkan!", added))
            DLG.showHarvestStorageDialog()
            return true
        elseif btn == "hv_btn_back_storage" or pkt:find("buttonClicked|hv_btn_back_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        end
        return true

    -- List Save Worlds
    elseif dName == "hv_list_save" or pkt:find("dialog_name|hv_list_save", 1, true) then
        local prevP = btn:match("hv_btn_s_prev_(%d+)")
        local nextP = btn:match("hv_btn_s_next_(%d+)")
        local editIdx = btn:match("hv_btn_s_edit_(%d+)")
        local delIdx = btn:match("hv_btn_s_del_(%d+)")

        if prevP then
            DLG.showHarvestSaveListDialog(tonumber(prevP))
            return true
        elseif nextP then
            DLG.showHarvestSaveListDialog(tonumber(nextP))
            return true
        elseif editIdx then
            DLG.showHarvestSaveEditDialog(tonumber(editIdx))
            return true
        elseif delIdx then
            local idx = tonumber(delIdx)
            if idx and HV.STATE.save_rows[idx] then
                table.remove(HV.STATE.save_rows, idx)
                HV.saveData()
                notifyMsg("Save World #" .. idx .. " dihapus!")
            end
            DLG.showHarvestSaveListDialog(DLG.save_page or 1)
            return true
        elseif btn == "hv_btn_dlg_clear_saves" or pkt:find("buttonClicked|hv_btn_dlg_clear_saves", 1, true) then
            HV.STATE.save_rows = {}
            HV.saveData()
            notifyMsg("Semua save world di-clear!")
            DLG.showHarvestSaveListDialog(1)
            return true
        elseif btn == "hv_btn_back_storage" or pkt:find("buttonClicked|hv_btn_back_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        end
        return true

    -- Edit Save World Entry
    elseif dName:find("^hv_edit_save_(%d+)$") or pkt:find("dialog_name|hv_edit_save_", 1, true) then
        local idx = tonumber(dName:match("^hv_edit_save_(%d+)") or pkt:match("dialog_name|hv_edit_save_(%d+)"))
        if not idx then
            idx = tonumber(btn:match("hv_btn_save_s_edit_(%d+)") or btn:match("hv_btn_del_s_edit_(%d+)"))
        end
        if idx and HV.STATE.save_rows[idx] then
            if btn:find("hv_btn_save_s_edit_") or pkt:find("buttonClicked|hv_btn_save_s_edit_", 1, true) then
                local newName = getVal("hv_edit_s_name"):upper():gsub("%s+", "")
                local newDoor = getVal("hv_edit_s_door"):gsub("%s+", "")
                local newType = getVal("hv_edit_s_type"):upper():gsub("%s+", "")
                if newType ~= "BLOCK" and newType ~= "SEED" then newType = "ALL" end
                local newLim = getNum("hv_edit_s_limit", HV.CFG.default_save_limit)
                local newFull = (getVal("hv_edit_s_full") == "1")
                if newName ~= "" and newName ~= "0" and newName ~= "EXIT" then
                    HV.STATE.save_rows[idx].name = newName
                    HV.STATE.save_rows[idx].door = newDoor
                    HV.STATE.save_rows[idx].save_type = newType
                    HV.STATE.save_rows[idx].limit = newLim
                    HV.STATE.save_rows[idx].status = newFull and "Full" or "Ready"
                    HV.saveData()
                    notifyMsg("Save World #" .. idx .. " diupdate!")
                end
                DLG.showHarvestSaveListDialog(DLG.save_page or 1)
                return true
            elseif btn:find("hv_btn_del_s_edit_") or pkt:find("buttonClicked|hv_btn_del_s_edit_", 1, true) then
                table.remove(HV.STATE.save_rows, idx)
                HV.saveData()
                notifyMsg("Save World #" .. idx .. " dihapus!")
                DLG.showHarvestSaveListDialog(DLG.save_page or 1)
                return true
            end
        end
        if btn == "hv_btn_back_s_list" or pkt:find("buttonClicked|hv_btn_back_s_list", 1, true) then
            DLG.showHarvestSaveListDialog(DLG.save_page or 1)
            return true
        end
        return true

    -- Limit & Drop Threshold Dialog
    elseif dName == "hv_limit_cfg" or pkt:find("dialog_name|hv_limit_cfg", 1, true) then
        if btn == "hv_btn_preset_10k" or pkt:find("buttonClicked|hv_btn_preset_10k", 1, true) then
            HV.CFG.default_save_limit = 10000
            HV.saveData()
            notifyMsg("Default Save Limit diatur ke 10.000!")
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_preset_20k" or pkt:find("buttonClicked|hv_btn_preset_20k", 1, true) then
            HV.CFG.default_save_limit = 20000
            HV.saveData()
            notifyMsg("Default Save Limit diatur ke 20.000!")
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_preset_50k" or pkt:find("buttonClicked|hv_btn_preset_50k", 1, true) then
            HV.CFG.default_save_limit = 50000
            HV.saveData()
            notifyMsg("Default Save Limit diatur ke 50.000!")
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_preset_unlimited" or pkt:find("buttonClicked|hv_btn_preset_unlimited", 1, true) then
            HV.CFG.default_save_limit = 0
            HV.saveData()
            notifyMsg("Default Save Limit diatur ke Unlimited (0)!")
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_save_limit_cfg" or pkt:find("buttonClicked|hv_btn_save_limit_cfg", 1, true) then
            local dt = getNum("hv_in_drop_threshold", 200)
            if dt and dt >= 10 then HV.CFG.drop_threshold = dt end
            local dlim = getNum("hv_in_default_save_limit", 20000)
            if dlim and dlim >= 0 then HV.CFG.default_save_limit = dlim end
            HV.saveData()
            notifyMsg("Pengaturan Limit & Drop Threshold disimpan!")
            DLG.showHarvestLimitConfigDialog()
            return true
        elseif btn == "hv_btn_back_storage" or pkt:find("buttonClicked|hv_btn_back_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        end
        return true

    -- File Save
    elseif dName == "hv_file_save" or pkt:find("dialog_name|hv_file_save", 1, true) then
        local fn = getVal("hv_in_file_save")
        if fn == "" then fn = "boren_harvest_storages.txt" end
        if btn == "hv_btn_do_save_s_file" or pkt:find("buttonClicked|hv_btn_do_save_s_file", 1, true) then
            local lines = {}
            for _, r in ipairs(HV.STATE.save_rows or {}) do
                table.insert(lines, string.format("%s:%s:%s:%d", r.name, r.door or "", r.save_type or "ALL", tonumber(r.limit) or 20000))
            end
            local okW = safeWriteFile(fn, table.concat(lines, "\n"))
            if okW then notifyMsg(string.format("Daftar Save disimpan ke %s (%d world)", fn, #lines))
            else notifyMsg("Gagal menyimpan ke " .. fn) end
            DLG.showHarvestFileSaveDialog()
            return true
        elseif btn == "hv_btn_do_load_s_file" or pkt:find("buttonClicked|hv_btn_do_load_s_file", 1, true) then
            local content = safeReadFile(fn)
            if content and content ~= "" then
                local added = 0
                for token in content:gmatch("[^\r\n,;%s]+") do
                    local p = parseSaveRow(token)
                    if p and p.name ~= "" and p.name ~= "EXIT" then
                        table.insert(HV.STATE.save_rows, p)
                        added = added + 1
                    end
                end
                HV.saveData()
                notifyMsg(string.format("%d Save World dimuat dari %s!", added, fn))
            else
                notifyMsg("Gagal membaca file: " .. fn)
            end
            DLG.showHarvestFileSaveDialog()
            return true
        elseif btn == "hv_btn_back_storage" or pkt:find("buttonClicked|hv_btn_back_storage", 1, true) then
            DLG.showHarvestStorageDialog()
            return true
        end
        return true

    -- --- D. SETTING COLLECT, IGNORE & FLOATING ---
    elseif dName == "hv_collect" or pkt:find("dialog_name|hv_collect", 1, true) then
        if btn == "hv_btn_save_collect_cfg" or pkt:find("buttonClicked|hv_btn_save_collect_cfg", 1, true) then
            local igGems = getVal("hv_chk_ignore_gems")
            if igGems ~= "" then HV.CFG.ignore_gems = (igGems:find("1") ~= nil) end
            local autoCol = getVal("hv_chk_auto_collect")
            if autoCol ~= "" then HV.CFG.auto_collect = (autoCol:find("1") ~= nil) end
            local tkBlock = getVal("hv_chk_take_block")
            if tkBlock ~= "" then HV.CFG.take_block = (tkBlock:find("1") ~= nil) end
            local tkSeed = getVal("hv_chk_take_seed")
            if tkSeed ~= "" then HV.CFG.take_seed = (tkSeed:find("1") ~= nil) end
            local tkFloat = getVal("hv_chk_take_floating")
            if tkFloat ~= "" then HV.CFG.take_floating = (tkFloat:find("1") ~= nil) end
            local ignDrop = getVal("hv_chk_ignore_take_drop")
            if ignDrop ~= "" then HV.CFG.ignore_take_drop = (ignDrop:find("1") ~= nil) end
            local cRange = getNum("hv_in_collect_range", 4)
            if cRange and cRange >= 1 and cRange <= 8 then HV.CFG.collect_range = cRange end
            HV.saveData()
            notifyMsg("Pengaturan Collect & Ignore disimpan!")
            DLG.showHarvestCollectDialog()
            return true
        elseif btn == "hv_btn_dlg_back_main" or pkt:find("buttonClicked|hv_btn_dlg_back_main", 1, true) then
            DLG.showHarvestMainDialog()
            return true
        end
        return true

    -- --- E. SETTING HARVEST ENGINE & CHEATS ---
    elseif dName == "hv_settings" or pkt:find("dialog_name|hv_settings", 1, true) then
        if btn == "hv_btn_save_settings_cfg" or pkt:find("buttonClicked|hv_btn_save_settings_cfg", 1, true) then
            local isTele = getVal("hv_chk_mode_teleport")
            local is3z = getVal("hv_chk_mode_zigzag")
            if isTele ~= "" and isTele:find("1") then HV.CFG.harvest_mode = "teleport"
            elseif is3z ~= "" and is3z:find("1") then HV.CFG.harvest_mode = "3zigzag" end
            local mFly = getVal("hv_chk_modfly")
            if mFly ~= "" then HV.CFG.use_modfly = (mFly:find("1") ~= nil) end
            local lEn = getVal("hv_chk_loop")
            if lEn ~= "" then HV.CFG.loop_enabled = (lEn:find("1") ~= nil) end
            local hDel = getNum("hv_in_harvest_delay", 180)
            if hDel and hDel >= 60 then HV.CFG.harvest_delay = hDel end
            local sDel = getNum("hv_in_step_delay", 110)
            if sDel and sDel >= 40 then HV.CFG.step_delay = sDel end
            local wDel = getNum("hv_in_warp_delay", 4500)
            if wDel and wDel >= 2000 then HV.CFG.warp_delay = wDel end
            HV.saveData()
            notifyMsg("Pengaturan Engine & Delays disimpan!")
            DLG.showHarvestSettingsDialog()
            return true
        elseif btn == "hv_btn_dlg_back_main" or pkt:find("buttonClicked|hv_btn_dlg_back_main", 1, true) then
            DLG.showHarvestMainDialog()
            return true
        end
        return true

    -- --- F. LOGS & BAG ---
    elseif dName == "hv_logs" or pkt:find("dialog_name|hv_logs", 1, true) then
        if btn == "hv_btn_dlg_clear_logs" or pkt:find("buttonClicked|hv_btn_dlg_clear_logs", 1, true) then
            HV.STATE.logs = {}
            notifyMsg("Log aktivitas dibersihkan!")
            DLG.showHarvestLogsDialog()
            return true
        elseif btn == "hv_btn_open_bag_view" or pkt:find("buttonClicked|hv_btn_open_bag_view", 1, true) then
            DLG.showHarvestBagDialog()
            return true
        elseif btn == "hv_btn_dlg_back_main" or pkt:find("buttonClicked|hv_btn_dlg_back_main", 1, true) then
            DLG.showHarvestMainDialog()
            return true
        end
        return true

    elseif dName == "hv_bag" or pkt:find("dialog_name|hv_bag", 1, true) then
        if btn == "hv_btn_refresh_bag_dlg" or pkt:find("buttonClicked|hv_btn_refresh_bag_dlg", 1, true) then
            DLG.showHarvestBagDialog()
            return true
        elseif btn == "hv_btn_back_logs" or pkt:find("buttonClicked|hv_btn_back_logs", 1, true) then
            DLG.showHarvestLogsDialog()
            return true
        end
        return true
    end

    return false
end

_G.handleHarvestDialogReturn = handleHarvestDialogReturn

-- Enhanced onSendPacket Hook to intercept Chat commands and Dialog Returns
local orig_onSendPacketHook = onSendPacketHook
local function onSendPacketEnhancedHook(p1, p2)
    local intercepted = false
    local retVal = false

    local ok, err = pcall(function()
        local pStr = nil
        if type(p2) == "string" then pStr = p2
        elseif type(p1) == "string" then pStr = p1 end

        if pStr and type(pStr) == "string" then
            local lowerP = pStr:lower()
            -- Intersepsi Chat Commands (/hv, /harvest, /autoharvest, /boren, /menu)
            if lowerP:find("/hv", 1, true) or lowerP:find("/harvest", 1, true) or lowerP:find("/autoharvest", 1, true) or lowerP:find("/boren", 1, true) or lowerP:find("/menu", 1, true) then
                if lowerP:find("action|input", 1, true) or lowerP:find("text|/", 1, true) or lowerP:find("action|chat", 1, true) or lowerP:sub(1, 1) == "/" then
                    local cmd = lowerP:match("|text|(/[a-z0-9_]+)") or lowerP:match("text|(/[a-z0-9_]+)") or lowerP:match("(/[a-z0-9_]+)")
                    if cmd == "/hv" or cmd == "/harvest" or cmd == "/autoharvest" or cmd == "/boren" or cmd == "/menu" then
                        local openFn = _G.showHarvestMainDialog or (DLG and DLG.showHarvestMainDialog)
                        if openFn then
                            pcall(openFn)
                            if LogToConsole then pcall(LogToConsole, "`2[BOREN HARVEST] `wMenu Dialog dibuka via chat: `e" .. tostring(cmd)) end
                        end
                        intercepted = true
                        retVal = true
                        return
                    end
                end
            end

            -- Intersepsi Dialog Return Compact Harvest
            if pStr:find("action|dialog_return", 1, true) then
                local handler = _G.handleHarvestDialogReturn or handleHarvestDialogReturn
                if handler then
                    local hOk, hRet = pcall(handler, pStr)
                    if hOk and hRet then
                        intercepted = true
                        retVal = true
                        return
                    end
                end
            end
        end
    end)

    if intercepted then return retVal end

    if orig_onSendPacketHook then
        local oOk, oRet = pcall(orig_onSendPacketHook, p1, p2)
        if oOk then return oRet end
    end
end

onSendPacket = onSendPacketEnhancedHook
OnSendPacket = onSendPacketEnhancedHook
if addHook then
    pcall(addHook, onSendPacketEnhancedHook, "onsendpacket")
    pcall(addHook, "onSendPacket", "boren_hv_send_hook", onSendPacketEnhancedHook)
    pcall(addHook, "OnSendPacket", "boren_hv_send_hook", onSendPacketEnhancedHook)
    if applyHook then pcall(applyHook) end
end
-- 7. UI RENDERER (TERINTEGRASI DENGAN UI_KIT BOREN STORE HUB)
-- ============================================================================
local function uiKit()
    return HUB_REF and HUB_REF.ui_kit or nil
end

local function autoBtn(lbl)
    local ok, r = pcall(ImGui.Button, lbl)
    return ok and (r == true)
end

local function uiGap(px)
    local k = uiKit()
    if k and k.gap then k.gap(px); return end
    if ImGui and ImGui.Spacing then pcall(ImGui.Spacing) end
end

local function uiSection(title, skipTopSep)
    local k = uiKit()
    if k and k.section then k.section(title, skipTopSep); return end
    if not skipTopSep then ImGui.Separator() end
    if title and title ~= "" then ImGui.Text(title) end
end

local function uiSectionWithKetik(title, btnId, onKetikClick, skipTopSep)
    uiSection(title, skipTopSep)
end

local function uiOpenDialog(id, title, fields, submitLbl, onSubmit)
    activeNativeDialogs[id] = onSubmit
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS = _G.__BOREN_ACTIVE_NATIVE_DIALOGS or {}
    _G.__BOREN_ACTIVE_NATIVE_DIALOGS[id] = onSubmit

    local k = uiKit()
    if k and k.openInputDialog then
        k.openInputDialog(id, title, fields, submitLbl, onSubmit)
        return
    end
    openNativeInputDialog(id, title, fields, submitLbl, onSubmit)
end

local function uiEnableBtn(isOn, id)
    local k = uiKit()
    if k and k.enableBtn then return k.enableBtn(isOn, id) end
    return autoBtn((isOn and "ON##" or "OFF##") .. tostring(id))
end

local function uiToggleBtn(isOn, id, onLbl, offLbl)
    local k = uiKit()
    if k and k.toggleBtn then return k.toggleBtn(isOn, id, onLbl, offLbl) end
    return autoBtn(" " .. (isOn and (onLbl or "ON") or (offLbl or "OFF")) .. " ##" .. tostring(id))
end

local function uiTabBtn(label, isActive)
    local k = uiKit()
    if k and k.tabBtn then return k.tabBtn(label, isActive) end
    return autoBtn(isActive and ("[ " .. label .. " ]") or label)
end

local function uiNote(msg)
    if not msg or msg == "" then return end
    local k = uiKit()
    if k and k.coloredText and k.getPal then
        k.coloredText(k.getPal().textPurple, "Info: " .. tostring(msg))
    else
        ImGui.Text("Info: " .. tostring(msg))
    end
end

local function uiActionBar(id, w, buttons)
    local k = uiKit()
    if k and k.renderActionBar then return k.renderActionBar(id, w, buttons) end
    local hit = nil
    for i, b in ipairs(buttons) do
        if i > 1 then ImGui.SameLine() end
        if autoBtn(b.label) then hit = i end
    end
    return hit
end



local formRevision = 1

local function cleanInputStr(v)
    return tostring(v or ""):gsub("%z.*", "")
end

local function cleanDialogField(v)
    local s = tostring(v or ""):gsub("%z.*", "")
    s = s:gsub("[\r\n|]+$", ""):gsub("^[\r\n|]+", "")
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local lastDialogOpenAt = 0
local function safeInput(id, val, maxL, onKetikFn)
    local s = cleanInputStr(val)
    local uniqueId = tostring(id) .. "_" .. tostring(formRevision)
    local ok, r1, r2 = pcall(ImGui.InputText, uniqueId, s, maxL or 256)
    local changed = false
    local newVal = s

    if ok then
        if type(r1) == "boolean" and type(r2) == "string" then
            if r1 == true then
                changed = true
                newVal = cleanInputStr(r2)
            end
        elseif type(r1) == "string" and type(r2) == "boolean" then
            if r2 == true then
                changed = true
                newVal = cleanInputStr(r1)
            end
        end
    end

    -- Otomatis panggil Native Keyboard Dialog saat kolom form diketuk / disentuh
    if onKetikFn and ImGui then
        local clicked = false
        if ImGui.IsItemClicked then
            local okC, clk = pcall(ImGui.IsItemClicked, 0)
            if okC and clk then clicked = true end
        end
        if not clicked and ImGui.IsItemActivated then
            local okA, act = pcall(ImGui.IsItemActivated)
            if okA and act then clicked = true end
        end
        if clicked then
            local now = os.clock and os.clock() or os.time()
            if (now - lastDialogOpenAt) >= 0.8 then
                lastDialogOpenAt = now
                pcall(onKetikFn)
            end
        end
    end

    return changed, newVal
end

local function readClipLines()
    local k = uiKit()
    if k and k.readClipboardLines then return k.readClipboardLines() end
    local clip = ""
    if ImGui and ImGui.GetClipboardText then
        local ok, c = pcall(ImGui.GetClipboardText)
        if ok and type(c) == "string" then clip = c end
    end
    local out = {}
    for line in clip:gmatch("[^\r\n]+") do
        local s = trimStr(line); if s ~= "" then out[#out + 1] = s end
    end
    return out
end

local function availX()
    if ImGui and ImGui.GetContentRegionAvail then
        local ok, av = pcall(ImGui.GetContentRegionAvail)
        if ok and av then
            if type(av) == "number" and av > 40 then return av end
            local okX, x = pcall(function() return av.x end)
            if okX and type(x) == "number" and x > 40 then return x end
        end
    end
    return 480
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 1: FARM LIST
-- ----------------------------------------------------------------------------
local function renderFarmsSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Kontrol Auto Harvest", true)
    ImGui.Text("Status Bot  :"); ImGui.SameLine()
    if uiEnableBtn(st.enabled, "hv_en") then
        if st.enabled then HV.stop() else HV.start() end
    end
    ImGui.SameLine(); ImGui.Text("    Loop  :"); ImGui.SameLine()
    if uiToggleBtn(c.loop_enabled, "hv_lp") then
        c.loop_enabled = not c.loop_enabled; HV.saveData()
    end
    ImGui.SameLine()
    if autoBtn(" Reset ##hv_rst") then
        for _, r in ipairs(st.rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Semua status farm di-reset ke Ready."
    end
    ImGui.SameLine()
    if autoBtn(" Clear ##hv_clr") then
        st.rows = {}; st.selected_idx = 0; HV.saveData(); uiNotice = "Daftar farm dikosongkan."
    end

    uiGap(3)
    ImGui.Text("Take Block :"); ImGui.SameLine()
    if uiToggleBtn(c.take_block ~= false, "hv_tb_main") then
        c.take_block = not (c.take_block ~= false); HV.saveData()
    end
    ImGui.SameLine(); ImGui.Text("   Take Seed :"); ImGui.SameLine()
    if uiToggleBtn(c.take_seed ~= false, "hv_ts_main") then
        c.take_seed = not (c.take_seed ~= false); HV.saveData()
    end

    uiGap(3)
    ImGui.Text(string.format("Status: %s   |   Farm: %d   |   Tree: %d   |   Drop: %d",
        tostring(st.status_text), #st.rows, st.total_harvested, st.total_dropped))
    uiNote(uiNotice)

    uiSection("Daftar World Farm (" .. tostring(#st.rows) .. ")")

    if ImGui.BeginTable("BorenHarvestTable", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door ID")
        ImGui.TableSetupColumn("Block/Seed ID")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(c.default_item_id))
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.rows) do
                local bID, sID = normalizeHarvestPair(r.item_id)
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_idx == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvr" .. tostring(i)) then
                    st.selected_idx = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(string.format("%d / %d", bID, sID))
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikFarmForm()
        local wPre = cleanDialogField(addFarmWorldBuf)
        local iPre = cleanDialogField(addFarmItemBuf ~= "" and addFarmItemBuf or (c.default_item_id and tostring(c.default_item_id) or "4584"))
        uiOpenDialog("boren_hv_fform", "Input Form Farm", {
            { id = "f_world", label = "World Farm (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_item",  label = "Item ID (Block atau Seed)", default = iPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local rawW = vals.f_world or vals["f_world"] or ""
            if rawW == "" then
                for k, v in pairs(vals) do
                    if tostring(k):lower():find("world") then rawW = v; break end
                end
            end
            local rawI = vals.f_item or vals["f_item"] or ""
            if rawI == "" then
                for k, v in pairs(vals) do
                    if tostring(k):lower():find("item") then rawI = v; break end
                end
            end
            local wn = cleanDialogField(rawW):upper()
            local iidStr = cleanDialogField(rawI):gsub("[^0-9]", "")
            if wn ~= "" then
                addFarmWorldBuf = wn
            end
            if iidStr ~= "" then
                addFarmItemBuf = iidStr
                local n = tonumber(iidStr)
                if n and n > 0 then
                    c.default_item_id = math.floor(n)
                    HV.saveData()
                end
            end
            formRevision = formRevision + 1
            uiNotice = "Form World Farm terisi: " .. tostring(addFarmWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah World Farm Baru", "hv_ktk_w", ketikFarmForm)

    if ImGui.BeginTable("BorenHarvestAddW", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Item ID (Block/Seed)")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.56)))
        local chW, nvW = safeInput("##hv_add_w", addFarmWorldBuf, 256, ketikFarmForm)
        ImGui.PopItemWidth()
        if chW then addFarmWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(80, math.floor(w * 0.34)))
        local chI, nvI = safeInput("##hv_add_item", addFarmItemBuf, 64, ketikFarmForm)
        ImGui.PopItemWidth()
        if chI then
            addFarmItemBuf = nvI:gsub("[^0-9]", "")
            local n = tonumber(addFarmItemBuf)
            if n and n > 0 then c.default_item_id = math.floor(n); HV.saveData() end
        end
        ImGui.EndTable()
    end
    uiGap(4)

    local act = uiActionBar("BorenHarvestActs", w, {
        { label = "+ Tambah##hv_add", style = "accent" },
        { label = "World Ini##hv_cur" },
        { label = "Paste List##hv_pst" },
        { label = "Copy List##hv_cpy" },
        { label = "Hapus##hv_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addFarmWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World:DoorID dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            local p = nil
            if colons >= 2 then
                p = parseFarmRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local iid   = math.floor(tonumber(addFarmItemBuf) or tonumber(c.default_item_id) or 4584)
                if iid <= 0 then iid = 4584 end
                if wName ~= "" then p = { name = wName, door = dId, item_id = iid, status = "Ready" } end
            end
            if p then
                table.insert(st.rows, p); addFarmWorldBuf = ""; HV.saveData()
                uiNotice = "Tersimpan: " .. p.name .. " (ID " .. tostring(p.item_id) .. ")"
            end
        end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addFarmWorldBuf = curW .. ":"
            formRevision = formRevision + 1
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        for _, line in ipairs(readClipLines()) do
            local p = parseFarmRow(line)
            if p then table.insert(st.rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " world."

    elseif act == 4 then
        if ImGui and ImGui.SetClipboardText then
            local out = {}
            for _, r in ipairs(st.rows) do
                table.insert(out, string.format("%s:%s:%d", r.name, r.door or "", r.item_id or c.default_item_id))
            end
            pcall(ImGui.SetClipboardText, table.concat(out, "\n"))
            uiNotice = "Disalin " .. tostring(#out) .. " world ke clipboard."
        end

    elseif act == 5 then
        if st.selected_idx > 0 and st.rows[st.selected_idx] then
            table.remove(st.rows, st.selected_idx); st.selected_idx = 0; HV.saveData()
            uiNotice = "World terpilih dihapus."
        else
            uiNotice = "Pilih baris world di tabel dulu!"
        end
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 2: SAVE WORLD (LIST TABEL BLOCK & SEED + LIMIT CUSTOM)
-- ----------------------------------------------------------------------------
local function renderSaveSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar Save World Block & Seed (" .. tostring(#st.save_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestSaveTbl", 5) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Tipe")
        ImGui.TableSetupColumn("Limit (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.save_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("ALL")
            ImGui.TableSetColumnIndex(3); ImGui.Text("20.000")
            ImGui.TableSetColumnIndex(4); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.save_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_save == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hvsr" .. tostring(i)) then
                    st.selected_save = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                ImGui.TableSetColumnIndex(2); ImGui.Text(tostring(r.save_type or "ALL"))
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(3); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(4); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikSaveForm()
        local wPre = cleanDialogField(addSaveWorldBuf)
        local lPre = cleanDialogField(addSaveLimitBuf ~= "" and addSaveLimitBuf or "0")
        uiOpenDialog("boren_hv_sform", "Input Form Save World", {
            { id = "f_world", label = "Save World (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_lim",   label = "Limit per World (0 = Unlimited)", default = lPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local limStr = cleanDialogField(vals.f_lim or vals["f_lim"]):gsub("[^0-9]", "")
            if wn ~= "" then addSaveWorldBuf = wn end
            if limStr ~= "" then addSaveLimitBuf = limStr else addSaveLimitBuf = "0" end
            formRevision = formRevision + 1
            uiNotice = "Form Save World terisi: " .. tostring(addSaveWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah Save World Baru", "hv_ktk_sw", ketikSaveForm)

    if ImGui.BeginTable("BorenHarvestAddSwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Pilihan Tipe Simpan")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.48)))
        local chW, nvW = safeInput("##hv_add_sw", addSaveWorldBuf, 256, ketikSaveForm)
        ImGui.PopItemWidth()
        if chW then addSaveWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        if autoBtn((addSaveTypeBuf == "ALL" and "[ Gabung ]" or "Gabung") .. "##sw_t_all") then addSaveTypeBuf = "ALL" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "BLOCK" and "[ Block ]" or "Block") .. "##sw_t_blk") then addSaveTypeBuf = "BLOCK" end
        ImGui.SameLine()
        if autoBtn((addSaveTypeBuf == "SEED" and "[ Seed ]" or "Seed") .. "##sw_t_sd") then addSaveTypeBuf = "SEED" end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Limit per World (0 = Unlimited):")
    ImGui.SameLine()
    ImGui.PushItemWidth(math.max(80, math.floor(w * 0.28)))
    local chLim, nvLim = safeInput("##hv_sw_lim_in", addSaveLimitBuf, 16, ketikSaveForm)
    ImGui.PopItemWidth()
    if chLim then addSaveLimitBuf = nvLim:gsub("[^0-9]", "") end
    ImGui.SameLine()
    local isUnliSw = (addSaveLimitBuf == "0" or addSaveLimitBuf == "")
    if autoBtn(isUnliSw and "[ Unlimited ]##sw_unl" or "Unlimited##sw_unl") then
        addSaveLimitBuf = "0"
    end

    uiGap(4)
    local act = uiActionBar("BorenHarvestSaveActs", w, {
        { label = "+ Tambah##sw_add", style = "accent" },
        { label = "World Ini##sw_cur" },
        { label = "Paste List##sw_pst" },
        { label = "Reset Penuh##sw_rst_all" },
        { label = "Hapus##sw_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addSaveWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World Save dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseSaveRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addSaveLimitBuf) or 20000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, save_type = addSaveTypeBuf, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.save_rows, p); addSaveWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Save: " .. p.name .. " (" .. p.save_type .. " - " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addSaveWorldBuf = curW .. ":"
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addSaveLimitBuf) or 20000)
        for _, line in ipairs(readClipLines()) do
            local p = parseSaveRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, save_type = addSaveTypeBuf, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.save_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " save world."

    elseif act == 4 then
        for _, r in ipairs(st.save_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua save world di-reset ke Ready."

    elseif act == 5 then
        if st.selected_save > 0 and st.save_rows[st.selected_save] then
            table.remove(st.save_rows, st.selected_save); st.selected_save = 0; HV.saveData()
            uiNotice = "Save world terpilih dihapus."
        else uiNotice = "Pilih baris save world di tabel dulu!" end
    end

    uiGap(4)
    uiSection("Pengaturan Drop Tas (Default: 200 Block)")
    ImGui.Text("Drop saat tas penuh    : >= " .. tostring(c.drop_threshold or 200) .. " block")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_dt1") then c.drop_threshold = math.max(20, (c.drop_threshold or 200) - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_dt2") then c.drop_threshold = math.min(200, (c.drop_threshold or 200) + 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" Default 200 ##hv_dt_def") then c.drop_threshold = 200; HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 3: EVENT SAVE (LIST TABEL EVENT + LIMIT TOTAL)
-- ----------------------------------------------------------------------------
local function renderEventSub()
    local c, st = HV.CFG, HV.STATE
    local w = availX()

    uiSection("Daftar World Save Event & Mooncake (" .. tostring(#st.event_rows) .. ")", true)
    uiNote(uiNotice)

    if ImGui.BeginTable("BorenHarvestEventTbl", 4) then
        ImGui.TableSetupColumn("World")
        ImGui.TableSetupColumn("Door")
        ImGui.TableSetupColumn("Limit Total (Isi)")
        ImGui.TableSetupColumn("Status")
        ImGui.TableHeadersRow()

        if #st.event_rows == 0 then
            ImGui.TableNextRow()
            ImGui.TableSetColumnIndex(0); ImGui.Text("(Kosong)")
            ImGui.TableSetColumnIndex(1); ImGui.Text("-")
            ImGui.TableSetColumnIndex(2); ImGui.Text("10.000")
            ImGui.TableSetColumnIndex(3); ImGui.Text("Tambah di bawah")
        else
            for i, r in ipairs(st.event_rows) do
                ImGui.TableNextRow()
                ImGui.TableSetColumnIndex(0)
                local sel = (st.selected_ev == i)
                if autoBtn((sel and "> " or "") .. tostring(r.name) .. "##hver" .. tostring(i)) then
                    st.selected_ev = sel and 0 or i
                end
                ImGui.TableSetColumnIndex(1); ImGui.Text((r.door and r.door ~= "") and r.door or "-")
                local limStr = (r.limit == 0) and "Unli" or string.format("%d (%d)", r.limit, r.count or 0)
                ImGui.TableSetColumnIndex(2); ImGui.Text(limStr)
                ImGui.TableSetColumnIndex(3); ImGui.Text(tostring(r.status or "Ready"))
            end
        end
        ImGui.EndTable()
    end

    local function ketikEventForm()
        local wPre = cleanDialogField(addEventWorldBuf)
        local lPre = cleanDialogField(addEventLimitBuf ~= "" and addEventLimitBuf or "0")
        uiOpenDialog("boren_hv_eform", "Input Form Event World", {
            { id = "f_world", label = "World Event (Nama atau Nama:DoorID)", default = wPre, maxLen = 64 },
            { id = "f_lim",   label = "Limit Total Item (0 = Unlimited)", default = lPre, maxLen = 16 },
        }, "Masukkan ke Form", function(vals)
            local wn = cleanDialogField(vals.f_world or vals["f_world"]):upper()
            local limStr = cleanDialogField(vals.f_lim or vals["f_lim"]):gsub("[^0-9]", "")
            if wn ~= "" then addEventWorldBuf = wn end
            if limStr ~= "" then addEventLimitBuf = limStr else addEventLimitBuf = "0" end
            formRevision = formRevision + 1
            uiNotice = "Form Event World terisi: " .. tostring(addEventWorldBuf)
        end)
    end

    uiSectionWithKetik("Tambah Event World Baru", "hv_ktk_ew", ketikEventForm)

    if ImGui.BeginTable("BorenHarvestAddEwTbl", 2) then
        ImGui.TableSetupColumn("World:DoorID")
        ImGui.TableSetupColumn("Limit Total Item")
        ImGui.TableHeadersRow()
        ImGui.TableNextRow()
        ImGui.TableSetColumnIndex(0)
        ImGui.PushItemWidth(math.max(120, math.floor(w * 0.52)))
        local chW, nvW = safeInput("##hv_add_ew", addEventWorldBuf, 256, ketikEventForm)
        ImGui.PopItemWidth()
        if chW then addEventWorldBuf = nvW end

        ImGui.TableSetColumnIndex(1)
        ImGui.PushItemWidth(math.max(70, math.floor(w * 0.24)))
        local chLim, nvLim = safeInput("##hv_ew_lim_in", addEventLimitBuf, 16, ketikEventForm)
        ImGui.PopItemWidth()
        if chLim then addEventLimitBuf = nvLim:gsub("[^0-9]", "") end
        ImGui.EndTable()
    end

    uiGap(2)
    ImGui.Text("Limit per World (0 = Unlimited):")
    ImGui.SameLine()
    local isUnliEv = (addEventLimitBuf == "0" or addEventLimitBuf == "")
    if autoBtn(isUnliEv and "[ Unlimited ]##ew_unl" or "Unlimited##ew_unl") then
        addEventLimitBuf = "0"
    end

    uiGap(4)
    local act = uiActionBar("BorenHarvestEventActs", w, {
        { label = "+ Tambah##ew_add", style = "accent" },
        { label = "World Ini##ew_cur" },
        { label = "Paste List##ew_pst" },
        { label = "Reset Penuh##ew_rst_all" },
        { label = "Hapus##ew_del",    style = "muted" },
    })

    if act == 1 then
        local rawW = trimStr(addEventWorldBuf)
        if rawW == "" then
            uiNotice = "Isi World Event dulu!"
        else
            local norm = rawW:gsub("|", ":")
            local colons = 0
            for _ in norm:gmatch(":") do colons = colons + 1 end
            if colons >= 2 then
                p = parseEventRow(norm)
            else
                local wPart, dPart = norm:match("^([^:]+):(.*)$")
                local wName = trimStr(wPart or norm):upper()
                local dId   = trimStr(dPart or ""):upper()
                local lim   = math.floor(tonumber(addEventLimitBuf) or 10000)
                if lim < 0 then lim = 0 end
                if wName ~= "" then p = { name = wName, door = dId, limit = lim, count = 0, status = "Ready" } end
            end
        end
        if p then
            table.insert(st.event_rows, p); addEventWorldBuf = ""; HV.saveData()
            uiNotice = "Tersimpan Event: " .. p.name .. " (Limit " .. p.limit .. ")"
        else uiNotice = "Isi World:DoorID dulu!" end

    elseif act == 2 then
        local curW = getCurrentWorldSafe()
        if curW ~= "" and curW ~= "EXIT" then
            addEventWorldBuf = curW .. ":"
            uiNotice = "Terisi " .. curW .. ": (masukkan Door ID jika ada, lalu klik + Tambah)"
        else uiNotice = "Masuk ke world dulu!" end

    elseif act == 3 then
        local added = 0
        local defLim = math.floor(tonumber(addEventLimitBuf) or 10000)
        for _, line in ipairs(readClipLines()) do
            local p = parseEventRow(line)
            if not p then
                local p2 = parseWorldDoor(line)
                if p2 then p = { name = p2.name, door = p2.door, limit = defLim, count = 0, status = "Ready" } end
            end
            if p then table.insert(st.event_rows, p); added = added + 1 end
        end
        if added > 0 then HV.saveData() end
        uiNotice = "Paste berhasil: +" .. tostring(added) .. " event world."

    elseif act == 4 then
        for _, r in ipairs(st.event_rows) do r.status = "Ready" end
        HV.saveData(); uiNotice = "Status semua world event di-reset ke Ready."

    elseif act == 5 then
        if st.selected_ev > 0 and st.event_rows[st.selected_ev] then
            table.remove(st.event_rows, st.selected_ev); st.selected_ev = 0; HV.saveData()
            uiNotice = "Event world terpilih dihapus."
        else uiNotice = "Pilih baris event world di tabel dulu!" end
    end

    uiGap(4)
    local function ketikEventIdsDialog()
        local cur = cleanDialogField(c.event_ids_raw or "")
        uiOpenDialog("boren_hv_eids", "Input ID Item Event", {
            { id = "f_eids", label = "Daftar ID Item Event (pisah koma)", default = cur, maxLen = 256 },
        }, "Simpan ID Event", function(vals)
            local raw = cleanDialogField(vals.f_eids or vals["f_eids"])
            if raw ~= "" then
                c.event_ids_raw = raw
                formRevision = formRevision + 1
                HV.saveData()
                uiNotice = "ID Event diperbarui: " .. c.event_ids_raw
            end
        end)
    end

    uiSection("Daftar ID Item Event (Disimpan ke World Event)")
    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
    local chEI, vEI = safeInput("##hv_ei", c.event_ids_raw, 512, ketikEventIdsDialog)
    ImGui.PopItemWidth()
    if chEI then c.event_ids_raw = vEI; HV.saveData() end

    uiGap(2)
    ImGui.Text("Preset :")
    ImGui.SameLine()
    if autoBtn(" Mooncake (1058,1094,1096,1098,1828) ##hv_pmc") then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData(); uiNotice = "Preset Mooncake diterapkan."
    end
    ImGui.SameLine()
    if autoBtn(" Kosongkan ID ##hv_ceid") then
        c.event_ids_raw = ""; HV.saveData(); uiNotice = "List ID event dikosongkan."
    end

    uiGap(3)
    ImGui.Text("Drop Event saat tas    : >= " .. tostring(c.event_threshold) .. " item")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_et1") then c.event_threshold = math.max(10, c.event_threshold - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_et2") then c.event_threshold = math.min(200, c.event_threshold + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 4: GEAR & FUEL (TERPADU + LIST ID EQUIP ALAT)
-- ----------------------------------------------------------------------------
local function renderGearSub()
    local c = HV.CFG
    local w = availX()

    uiSection("Gudang Alat & Fuel (Gear World)", true)
    uiNote(uiNotice)

    local function ketikGearWorldDialog()
        local cur = cleanDialogField(c.gear_world or "")
        uiOpenDialog("boren_hv_gw", "Input World Ambil Gear", {
            { id = "gw", label = "Gear World (WORLD:DOOR)", default = cur, maxLen = 64 },
        }, "Simpan Gear World", function(v)
            local raw = cleanDialogField(v.gw or v["gw"]):upper()
            if raw ~= "" then
                c.gear_world = raw
                formRevision = formRevision + 1
                HV.saveData()
                uiNotice = "Gear World berhasil disimpan: " .. c.gear_world
            end
        end)
    end

    uiSectionWithKetik("World Penyimpanan Alat & Fuel (WORLD:DOOR)", "hv_ktk_gw", ketikGearWorldDialog)

    ImGui.PushItemWidth(math.max(160, math.floor(w * 0.72)))
    local chGW, vGW = safeInput("##hv_gw", c.gear_world, 128, ketikGearWorldDialog)
    ImGui.PopItemWidth()
    if chGW then c.gear_world = vGW; HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" World Ini ##hv_gwc") then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            c.gear_world = cw .. ":"
            HV.saveData(); uiNotice = "Terisi " .. cw .. ": (masukkan Door ID jika ada)"
        else uiNotice = "Masuk ke world dulu!" end
    end

    uiGap(4)
    uiSection("Auto Restock Magni & Fuel Pack")

    ImGui.Text("Ambil Magni (1252) & Fuel Pack (1746) :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_magni_fuel, "hv_amf") then
        c.auto_magni_fuel = not c.auto_magni_fuel; HV.saveData()
    end

    if c.auto_magni_fuel then
        uiGap(2)
        ImGui.Text("Target Stok Fuel Pack di Tas          : " .. tostring(c.fuel_target_amt) .. " pack")
        ImGui.SameLine()
        if autoBtn(" -25 ##hv_fa1") then c.fuel_target_amt = math.max(25, c.fuel_target_amt - 25); HV.saveData() end
        ImGui.SameLine()
        if autoBtn(" +25 ##hv_fa2") then c.fuel_target_amt = math.min(200, c.fuel_target_amt + 25); HV.saveData() end

        uiGap(2)
        ImGui.Text("Fuel Guard: Stop Bot jika Fuel Habis  :"); ImGui.SameLine()
        if uiToggleBtn(c.stop_if_no_fuel, "hv_stpf") then
            c.stop_if_no_fuel = not c.stop_if_no_fuel; HV.saveData()
        end
    end

    uiGap(4)
    uiSection("Equip DCS & Harvester (Hand / Back)")
    ImGui.Text("Gunakan DCS & Harvester :"); ImGui.SameLine()
    if uiToggleBtn(c.use_dcs_harvester, "hv_use_dcs") then
        c.use_dcs_harvester = not c.use_dcs_harvester
        HV.saveData()
    end

    if c.use_dcs_harvester then
        uiGap(2)
        ImGui.Text("List ID Item Equip (DCS, Harvester, dll. pisah koma):")
        local function ketikGearEquipDialog()
            local cur = cleanDialogField(c.gear_equip_ids or "")
            uiOpenDialog("boren_hv_geq", "Input List ID Equip", {
                { id = "eq", label = "List ID Equip Alat (pisah koma)", default = cur, maxLen = 128 },
            }, "Simpan ID Equip", function(v)
                local raw = cleanDialogField(v.eq or v["eq"])
                if raw ~= "" then
                    c.gear_equip_ids = raw
                    formRevision = formRevision + 1
                    HV.saveData()
                    uiNotice = "Equip IDs berhasil disimpan: " .. c.gear_equip_ids
                end
            end)
        end

        ImGui.PushItemWidth(math.max(160, math.floor(w * 0.96)))
        local chEq, vEq = safeInput("##hv_eq_ids", c.gear_equip_ids, 256, ketikGearEquipDialog)
        ImGui.PopItemWidth()
        if chEq then c.gear_equip_ids = vEq; HV.saveData() end

        uiGap(2)
        ImGui.Text("Preset Cepat :")
        ImGui.SameLine()
        if autoBtn(" DCS + Sorrows (6840, 1966) ##eq_p1") then
            c.gear_equip_ids = "6840, 1966"; HV.saveData(); uiNotice = "Preset DCS + Sorrows diterapkan."
        end
        ImGui.SameLine()
        if autoBtn(" DCS + Normal (6840, 1830) ##eq_p2") then
            c.gear_equip_ids = "6840, 1830"; HV.saveData(); uiNotice = "Preset DCS + Normal diterapkan."
        end
        ImGui.SameLine()
        if autoBtn(" Sorrows Saja (1966) ##eq_p3") then
            c.gear_equip_ids = "1966"; HV.saveData(); uiNotice = "Preset Sorrows saja diterapkan."
        end
    end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 5: SETTINGS
-- ----------------------------------------------------------------------------
local function renderSettingsSub()
    local c = HV.CFG

    uiSection("Pengaturan Navigasi & Collect", true)

    ImGui.Text("Ignore Gems (ID 112)       :"); ImGui.SameLine()
    if uiToggleBtn(c.ignore_gems, "hv_ig") then c.ignore_gems = not c.ignore_gems; HV.saveData() end

    uiGap(2)
    ImGui.Text("Ignore Take di Save/Event  :"); ImGui.SameLine()
    if uiToggleBtn(c.ignore_take_drop ~= false, "hv_itd") then
        c.ignore_take_drop = not (c.ignore_take_drop ~= false)
        HV.saveData()
    end

    uiGap(2)
    ImGui.Text("Auto Collect Block/Seed    :"); ImGui.SameLine()
    if uiToggleBtn(c.auto_collect, "hv_ac") then c.auto_collect = not c.auto_collect; HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Floating (Sapu Sisa)  :"); ImGui.SameLine()
    if uiToggleBtn(c.take_floating, "hv_tf") then c.take_floating = not c.take_floating; HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Block Sesuai ID       :"); ImGui.SameLine()
    if uiToggleBtn(c.take_block ~= false, "hv_tb") then c.take_block = not (c.take_block ~= false); HV.saveData() end

    uiGap(2)
    ImGui.Text("Take Seed Sesuai ID        :"); ImGui.SameLine()
    if uiToggleBtn(c.take_seed ~= false, "hv_ts") then c.take_seed = not (c.take_seed ~= false); HV.saveData() end

    uiGap(2)
    ImGui.Text("Mode Traversal             :"); ImGui.SameLine()
    if uiToggleBtn(c.harvest_mode == "3zigzag", "hv_md", "3-ZIGZAG", "1-BY-1") then
        c.harvest_mode = (c.harvest_mode == "3zigzag") and "1by1" or "3zigzag"; HV.saveData()
    end

    uiGap(2)
    ImGui.Text("ModFly (Tembus Rintangan)  :"); ImGui.SameLine()
    if uiToggleBtn(c.use_modfly, "hv_mf") then c.use_modfly = not c.use_modfly; HV.saveData() end

    uiGap(4)
    uiSection("Pacing Delay Riil (Milidetik)")

    ImGui.Text("Delay Harvest              : " .. tostring(c.harvest_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_hd1") then c.harvest_delay = math.max(90, c.harvest_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_hd2") then c.harvest_delay = math.min(500, c.harvest_delay + 20); HV.saveData() end

    uiGap(2)
    ImGui.Text("Delay Langkah Bot          : " .. tostring(c.step_delay) .. " ms")
    ImGui.SameLine()
    if autoBtn(" -20 ##hv_sd1") then c.step_delay = math.max(50, c.step_delay - 20); HV.saveData() end
    ImGui.SameLine()
    if autoBtn(" +20 ##hv_sd2") then c.step_delay = math.min(400, c.step_delay + 20); HV.saveData() end
end

-- ----------------------------------------------------------------------------
-- SUB-TAB 6: LOGS
-- ----------------------------------------------------------------------------
local function renderLogsSub()
    local st = HV.STATE
    local w = availX()

    uiSection("Live Preview Tas & Log Panen", true)
    ImGui.Text(string.format("Tas Saat Ini -> Block: %d | Seed: %d | Event: %d | Fuel: %d",
        st.inv_preview.block, st.inv_preview.seed, st.inv_preview.ev, st.inv_preview.fuel))

    uiGap(3)
    if autoBtn(" Bersihkan Log ##hv_clg") then st.logs = {} end
    ImGui.Separator()

    for i = 1, math.min(14, #st.logs) do
        if ImGui.TextWrapped then ImGui.TextWrapped(st.logs[i]) else ImGui.Text(st.logs[i]) end
    end
end


local function renderHarvestBody()
    local w = availX()
    local tabs = {
        { "farms", "Farm List" },
        { "save",  "Save World" },
        { "event", "Event Save" },
        { "gear",  "Gear & Fuel" },
        { "set",   "Settings" },
        { "logs",  "Logs" },
    }
    for i, tb in ipairs(tabs) do
        if i > 1 then ImGui.SameLine() end
        if uiTabBtn(tb[2], activeSub == tb[1]) then activeSub = tb[1] end
    end
    ImGui.Separator()
    if activeSub == "farms" then renderFarmsSub()
    elseif activeSub == "save" then renderSaveSub()
    elseif activeSub == "event" then renderEventSub()
    elseif activeSub == "gear" then renderGearSub()
    elseif activeSub == "set" then renderSettingsSub()
    else renderLogsSub() end
end

-- ============================================================================
-- 8. STANDALONE DEAR IMGUI WINDOW
-- ============================================================================
function onDrawImGui()
    if not HV.STATE.show_ui then return end
    if not ImGui or not ImGui.Begin then return end
    pcall(function()
        local winFlags = 2048 -- ImGuiWindowFlags_HorizontalScrollbar
        if ImGui.WindowFlags and ImGui.WindowFlags.HorizontalScrollbar then
            winFlags = tonumber(ImGui.WindowFlags.HorizontalScrollbar) or 2048
        end
        local MIN_CONTENT_W = 680
        if ImGui.SetNextWindowContentSize and ImVec2 then
            pcall(ImGui.SetNextWindowContentSize, ImVec2(MIN_CONTENT_W, 0))
        end
        local okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION, true, winFlags)
        if not okCall or opened == nil then
            okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION, winFlags)
        end
        if not okCall or opened == nil then
            okCall, opened = pcall(ImGui.Begin, "BOREN STORE - AUTO HARVEST PRO v" .. HV.VERSION)
        end
        if opened then
            if ImGui.Dummy and ImVec2 then pcall(ImGui.Dummy, ImVec2(MIN_CONTENT_W, 0.1)) end
            renderHarvestBody()
            ImGui.End()
        end
    end)
end
OnDrawImGui = onDrawImGui

-- ============================================================================
-- 9. NATIVE GROWLAUNCHER MULTI-TAB MENU & ONVALUE HANDLER
-- ============================================================================
local function createNativeUI(subName, icon)
    if UserInterface and UserInterface.new then
        local ok, ui = pcall(UserInterface.new, subName, icon or "PlayArrow")
        if ok and ui then return ui end
    end
    local dummy = { items = {} }
    function dummy:addLabelApp(t, ic) table.insert(self.items, string.format('{"type":"labelapp","text":"%s","icon":"%s"}', t, ic or "Storefront")) end
    function dummy:addButton(t, al) table.insert(self.items, string.format('{"type":"button","text":"%s","alias":"%s"}', t, al)) end
    function dummy:addToggleButton(t, d, al) table.insert(self.items, string.format('{"type":"toggle_button","text":"%s","default":%s,"alias":"%s"}', t, d and "true" or "false", al)) end
    function dummy:addToggle(t, d, al, ov) table.insert(self.items, string.format('{"type":"toggle","text":"%s","default":%s,"alias":"%s"}', t, d and "true" or "false", al)) end
    function dummy:addDivider() table.insert(self.items, '{"type":"divider"}') end
    function dummy:addLabel(t) table.insert(self.items, string.format('{"type":"label","text":"%s"}', t)) end
    function dummy:addInputString(t, v, l, h, ic, al) table.insert(self.items, string.format('{"type":"input_string","text":"%s","value":"%s","label":"%s","hint":"%s","icon":"%s","alias":"%s"}', t, v or "", l or "", h or "", ic or "Public", al)) end
    function dummy:addInputInt(t, v, l, h, ic, al) table.insert(self.items, string.format('{"type":"input_int","text":"%s","value":"%s","label":"%s","hint":"%s","icon":"%s","alias":"%s"}', t, tostring(v or "0"), l or "", h or "", ic or "FormatListNumbered", al)) end
    function dummy:addSlider(t, mn, mx, v, stp, f, al) table.insert(self.items, string.format('{"type":"slider","text":"%s","min":%d,"max":%d,"value":%d,"step":%d,"alias":"%s"}', t, mn, mx, v, stp or 1, al)) end
    function dummy:addDisplayList(t, s, al) table.insert(self.items, string.format('{"type":"display_list","text":"%s","style":"%s","alias":"%s"}', t, s or "Default", al)) end
    function dummy:generateJSON() return string.format('{"sub_name":"%s","icon":"%s","menu":[%s]}', subName, icon or "PlayArrow", table.concat(self.items, ",")) end
    return dummy
end

local function registerNativeHarvestUI()
    if not addCategory or not addIntoModule then return end

    -- TAB 1: START & FARM
    local uiFarm = createNativeUI("1. Start & Farm", "PlayArrow")
    uiFarm:addLabelApp("Boren Store - Auto Harvest v" .. HV.VERSION, "Storefront")
    uiFarm:addButton("    START HARVEST BOT", "hv_btn_start")
    uiFarm:addButton("    STOP HARVEST BOT", "hv_btn_stop")
    uiFarm:addToggleButton("    START /     STOP TOGGLE", HV.STATE.running, "hv_run_power")
    uiFarm:addToggle("Tampilkan Panel ImGui", HV.STATE.show_ui, "hv_show_ui", false)
    uiFarm:addDivider()
    uiFarm:addLabel("Tambah Antrean World Farm:")
    uiFarm:addInputString("Nama World Farm", HV.STATE.input_add_world, "World", "FARMWORLD", "Public", "hv_manual_world_input")
    uiFarm:addInputString("Door ID (Opsional)", HV.STATE.input_add_door, "Door ID", "Kosong = White Door", "DoorFront", "hv_manual_door_input")
    uiFarm:addInputInt("Block / Seed ID", tostring(HV.STATE.input_add_id or HV.CFG.default_item_id), "Item ID", "4584", "Category", "hv_manual_item_input")
    uiFarm:addButton("    Tambah Farm ke Antrean", "hv_btn_add_farm")
    uiFarm:addButton("     Tambah World Sekarang", "hv_btn_add_cur_farm")
    uiFarm:addButton("     Reset Status Antrean (Ready)", "hv_btn_reset_status")
    uiFarm:addButton("        Kosongkan Antrean Farm", "hv_btn_clear_farms")

    -- TAB 2: SAVE & LIMIT
    local uiSave = createNativeUI("2. Save & Limit", "Archive")
    uiSave:addLabelApp("Multi-World Save Table & Limit Drop", "Archive")
    uiSave:addLabel("Tambah World Save Baru:")
    uiSave:addInputString("Nama World Save", HV.STATE.input_save_w, "World", "SAVEBLOCK1", "CloudUpload", "hv_input_save_w")
    uiSave:addInputString("Door ID (Opsional)", HV.STATE.input_save_d, "Door ID", "Kosong = Door Utama", "DoorFront", "hv_input_save_d")
    uiSave:addInputInt("Limit Item World Ini (0 = Unlimited)", tostring(HV.STATE.input_save_lim or HV.CFG.default_save_limit), "Limit", "20000", "FormatListNumbered", "hv_input_save_lim")
    uiSave:addLabel("Tipe Simpan: " .. tostring(HV.STATE.input_save_type or "ALL"))
    uiSave:addButton("Tipe: ALL (Block + Seed)", "hv_btn_stype_all")
    uiSave:addButton("Tipe: BLOCK Saja", "hv_btn_stype_block")
    uiSave:addButton("Tipe: SEED Saja", "hv_btn_stype_seed")
    uiSave:addButton("    Tambah World Save ke List", "hv_btn_add_save")
    uiSave:addButton("     Tambah World Sekarang (Save)", "hv_btn_add_cur_save")
    uiSave:addButton("     Reset Penanda Penuh (Ready)", "hv_btn_reset_save_status")
    uiSave:addButton("        Kosongkan List Save World", "hv_btn_clear_save")
    uiSave:addDivider()
    uiSave:addLabel("Pengaturan Drop Tas (Default 200 Block):")
    uiSave:addSlider("Threshold Drop Tas", 50, 200, HV.CFG.drop_threshold or 200, 10, false, "hv_slider_drop_threshold")

    -- TAB 3: EVENT & MOONCAKE
    local uiEvent = createNativeUI("3. Event & Mooncake", "Celebration")
    uiEvent:addLabelApp("Save Khusus Event & Mooncake", "Celebration")
    uiEvent:addLabel("Tambah World Save Event:")
    uiEvent:addInputString("Nama World Event", HV.STATE.input_ev_w, "World", "WORLDEVENT1", "Event", "hv_input_ev_w")
    uiEvent:addInputString("Door ID (Opsional)", HV.STATE.input_ev_d, "Door ID", "Kosong = Door Utama", "DoorFront", "hv_input_ev_d")
    uiEvent:addInputInt("Limit Total Item Event (0 = Unli)", tostring(HV.STATE.input_ev_lim or HV.CFG.default_ev_limit), "Limit", "10000", "FormatListNumbered", "hv_input_ev_lim")
    uiEvent:addButton("    Tambah World Event ke List", "hv_btn_add_ev")
    uiEvent:addButton("     Tambah World Sekarang (Event)", "hv_btn_add_cur_ev")
    uiEvent:addButton("     Reset Penanda Event Penuh", "hv_btn_reset_ev_status")
    uiEvent:addButton("        Kosongkan List Event World", "hv_btn_clear_ev")
    uiEvent:addDivider()
    uiEvent:addLabel("List ID Item Event (Selain Block & Seed):")
    uiEvent:addInputString("ID Item Event (Koma)", HV.CFG.event_ids_raw or "", "Event IDs", "1058,1094,1096,1098,1828", "Stars", "hv_input_event_ids")
    uiEvent:addButton("     Preset Mooncake (5 Jenis)", "hv_btn_preset_mooncake")
    uiEvent:addSlider("Threshold Drop Event", 20, 200, HV.CFG.event_threshold or 150, 10, false, "hv_slider_event_threshold")

    -- TAB 4: GEAR & FUEL
    local uiGear = createNativeUI("4. Gear & Fuel", "Build")
    uiGear:addLabelApp("Gear World, Restock & Equip", "Build")
    uiGear:addLabel("World Ambil Alat & Fuel Pack:")
    uiGear:addInputString("Gear World (WORLD:DOOR)", HV.CFG.gear_world or "", "Gear World", "GEARWORLD:DOOR", "Home", "hv_input_gear_world")
    uiGear:addButton("     Pakai World Sekarang (Gear)", "hv_btn_add_cur_gear")
    uiGear:addDivider()
    uiGear:addLabel("Auto Restock Magni (1252) + Fuel Pack (1746):")
    uiGear:addToggle("Ambil Magni & Fuel Pack Otomatis", HV.CFG.auto_magni_fuel == true, "hv_toggle_magni_fuel", false)
    uiGear:addToggle("Stop Bot Jika Fuel Habis (Proteksi)", HV.CFG.stop_if_no_fuel ~= false, "hv_toggle_stop_no_fuel", false)
    uiGear:addSlider("Target Stok Fuel Pack di Tas", 25, 200, HV.CFG.fuel_target_amt or 100, 25, false, "hv_slider_fuel_target")
    uiGear:addDivider()
    uiGear:addLabel("List ID Gear yang Dipakai (Auto-Equip):")
    uiGear:addInputString("ID Gear (Koma)", HV.CFG.gear_equip_ids or "6840, 1966", "Gear IDs", "6840, 1966", "Settings", "hv_input_gear_equip_ids")
    uiGear:addButton("       Preset: DCS (6840) + Harvester (1966)", "hv_btn_gear_preset_both")
    uiGear:addButton("     Preset: Harvester Saja (1966)", "hv_btn_gear_preset_harv")
    uiGear:addButton("    Preset: DCS Saja (6840)", "hv_btn_gear_preset_dcs")

    -- TAB 5: PENGATURAN & DELAY
    local uiSet = createNativeUI("5. Pengaturan & Delay", "Tune")
    uiSet:addLabelApp("Pengaturan Navigasi & Kecepatan", "Tune")
    uiSet:addToggle("Abaikan Gems (Anti Penuh Tas)", HV.CFG.ignore_gems ~= false, "hv_toggle_ignore_gems", false)
    uiSet:addToggle("Ignore Take Drop di Save/Event", HV.CFG.ignore_take_drop ~= false, "hv_toggle_ignore_take_drop", false)
    uiSet:addToggle("Auto Collect Block & Seed", HV.CFG.auto_collect ~= false, "hv_toggle_auto_collect", false)
    uiSet:addToggle("Ambil Floating Item Sisa", HV.CFG.take_floating ~= false, "hv_toggle_take_floating", false)
    uiSet:addToggle("Mode Teleport Fast (OFF = 3-Zigzag)", HV.CFG.harvest_mode == "teleport", "hv_toggle_mode_teleport", false)
    uiSet:addToggle("Gunakan ModFly saat Bergerak", HV.CFG.use_modfly ~= false, "hv_toggle_modfly", false)
    uiSet:addToggle("Looping Ulang Semua Farm", HV.CFG.loop_enabled == true, "hv_toggle_loop", false)
    uiSet:addDivider()
    uiSet:addSlider("Delay Harvest (ms)", 90, 500, HV.CFG.harvest_delay or 180, 10, false, "hv_slider_harvest_delay")
    uiSet:addSlider("Delay Langkah Bot (ms)", 50, 400, HV.CFG.step_delay or 110, 10, false, "hv_slider_step_delay")
    uiSet:addSlider("Delay Warp Antar World (ms)", 1000, 10000, HV.CFG.warp_delay or 4500, 500, false, "hv_slider_warp_delay")

    pcall(addCategory, "Boren Harvest Pro", "Agriculture")
    pcall(addIntoModule, uiFarm:generateJSON(), "Boren Harvest Pro")
    pcall(addIntoModule, uiSave:generateJSON(), "Boren Harvest Pro")
    pcall(addIntoModule, uiEvent:generateJSON(), "Boren Harvest Pro")
    pcall(addIntoModule, uiGear:generateJSON(), "Boren Harvest Pro")
    pcall(addIntoModule, uiSet:generateJSON(), "Boren Harvest Pro")
end

local lastAliasEventTime = {}

local function handleUIValue(vtype, name, value)
    if type(vtype) == "string" and (name == nil or type(name) ~= "string" or (type(name) == "string" and vtype:sub(1, 3) == "hv_")) then
        value = name
        name = vtype
        vtype = 0
    end
    name = tostring(name or "")
    if name == "" then return end

    local now = safeClock()
    local isButton = (name:sub(1, 7) == "hv_btn_")
    if isButton then
        if lastAliasEventTime[name] and (now - lastAliasEventTime[name]) < 0.25 then
            return
        end
        lastAliasEventTime[name] = now
    end

    local val = value

    local c = HV.CFG
    local st = HV.STATE

    if name == "hv_btn_start" then
        HV.start()
    elseif name == "hv_btn_stop" then
        HV.stop()
    elseif name == "hv_run_power" then
        if val == true or val == "true" or val == 1 then HV.start() else HV.stop() end
    elseif name == "hv_show_ui" then
        st.show_ui = (val == true)
    -- FARM TAB
    elseif name == "hv_manual_world_input" then
        st.input_add_world = trimStr(val or "")
    elseif name == "hv_manual_door_input" then
        st.input_add_door = trimStr(val or "")
    elseif name == "hv_manual_item_input" then
        local n = tonumber(val)
        if n and n > 0 then st.input_add_id = tostring(math.floor(n)) end
    elseif name == "hv_btn_add_farm" then
        local w = cleanWorldName(st.input_add_world)
        if w ~= "" then
            local iid = tonumber(st.input_add_id) or c.default_item_id or 4584
            table.insert(st.rows, { name = w, door = cleanWorldName(st.input_add_door), item_id = iid, status = "Ready" })
            st.input_add_world = ""
            st.input_add_door  = ""
            HV.saveData()
            addLog("Farm ditambah: " .. w)
        end
    elseif name == "hv_btn_add_cur_farm" then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            local iid = tonumber(st.input_add_id) or c.default_item_id or 4584
            table.insert(st.rows, { name = cw, door = "", item_id = iid, status = "Ready" })
            HV.saveData()
            addLog("Farm saat ini ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_status" then
        for _, r in ipairs(st.rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua farm di-reset ke Ready.")
    elseif name == "hv_btn_clear_farms" then
        st.rows = {}
        HV.saveData()
        addLog("Daftar farm dikosongkan.")

    -- SAVE TAB
    elseif name == "hv_input_save_w" then
        st.input_save_w = trimStr(val or "")
    elseif name == "hv_input_save_d" then
        st.input_save_d = trimStr(val or "")
    elseif name == "hv_input_save_lim" then
        local n = tonumber(val)
        if n and n >= 0 then st.input_save_lim = tostring(math.floor(n)) end
    elseif name == "hv_btn_stype_all" then
        st.input_save_type = "ALL"
    elseif name == "hv_btn_stype_block" then
        st.input_save_type = "BLOCK"
    elseif name == "hv_btn_stype_seed" then
        st.input_save_type = "SEED"
    elseif name == "hv_btn_add_save" then
        local w = cleanWorldName(st.input_save_w)
        if w ~= "" then
            local lim = tonumber(st.input_save_lim) or c.default_save_limit or 20000
            table.insert(st.save_rows, { name = w, door = cleanWorldName(st.input_save_d), save_type = st.input_save_type or "ALL", limit = lim, count = 0, status = "Ready" })
            st.input_save_w = ""
            st.input_save_d = ""
            HV.saveData()
            addLog("Save World ditambah: " .. w .. " (" .. (st.input_save_type or "ALL") .. ")")
        end
    elseif name == "hv_btn_add_cur_save" then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            local lim = tonumber(st.input_save_lim) or c.default_save_limit or 20000
            table.insert(st.save_rows, { name = cw, door = "", save_type = st.input_save_type or "ALL", limit = lim, count = 0, status = "Ready" })
            HV.saveData()
            addLog("Save World aktif ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_save_status" then
        for _, r in ipairs(st.save_rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua save world di-reset.")
    elseif name == "hv_btn_clear_save" then
        st.save_rows = {}
        HV.saveData()
        addLog("Daftar save world dikosongkan.")
    elseif name == "hv_slider_drop_threshold" then
        local n = tonumber(val)
        if n and n >= 20 then c.drop_threshold = math.floor(n); HV.saveData() end

    -- EVENT TAB
    elseif name == "hv_input_ev_w" then
        st.input_ev_w = trimStr(val or "")
    elseif name == "hv_input_ev_d" then
        st.input_ev_d = trimStr(val or "")
    elseif name == "hv_input_ev_lim" then
        local n = tonumber(val)
        if n and n >= 0 then st.input_ev_lim = tostring(math.floor(n)) end
    elseif name == "hv_btn_add_ev" then
        local w = cleanWorldName(st.input_ev_w)
        if w ~= "" then
            local lim = tonumber(st.input_ev_lim) or c.default_ev_limit or 10000
            table.insert(st.event_rows, { name = w, door = cleanWorldName(st.input_ev_d), limit = lim, count = 0, status = "Ready" })
            st.input_ev_w = ""
            st.input_ev_d = ""
            HV.saveData()
            addLog("Event World ditambah: " .. w)
        end
    elseif name == "hv_btn_add_cur_ev" then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            local lim = tonumber(st.input_ev_lim) or c.default_ev_limit or 10000
            table.insert(st.event_rows, { name = cw, door = "", limit = lim, count = 0, status = "Ready" })
            HV.saveData()
            addLog("Event World aktif ditambah: " .. cw)
        end
    elseif name == "hv_btn_reset_ev_status" then
        for _, r in ipairs(st.event_rows) do r.status = "Ready" end
        HV.saveData()
        addLog("Status semua event world di-reset.")
    elseif name == "hv_btn_clear_ev" then
        st.event_rows = {}
        HV.saveData()
        addLog("Daftar event world dikosongkan.")
    elseif name == "hv_input_event_ids" then
        c.event_ids_raw = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_preset_mooncake" then
        c.event_ids_raw = "1058,1094,1096,1098,1828"
        HV.saveData()
        addLog("Preset Mooncake 5 jenis diterapkan.")
    elseif name == "hv_slider_event_threshold" then
        local n = tonumber(val)
        if n and n >= 10 then c.event_threshold = math.floor(n); HV.saveData() end

    -- GEAR TAB
    elseif name == "hv_input_gear_world" then
        c.gear_world = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_add_cur_gear" then
        local cw = getCurrentWorldSafe()
        if cw ~= "" and cw ~= "EXIT" then
            c.gear_world = cw .. ":"
            HV.saveData()
            addLog("Gear World diset ke: " .. cw)
        end
    elseif name == "hv_toggle_magni_fuel" then
        c.auto_magni_fuel = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_stop_no_fuel" then
        c.stop_if_no_fuel = (val == true)
        HV.saveData()
    elseif name == "hv_slider_fuel_target" then
        local n = tonumber(val)
        if n and n >= 10 then c.fuel_target_amt = math.floor(n); HV.saveData() end
    elseif name == "hv_input_gear_equip_ids" then
        c.gear_equip_ids = trimStr(val or "")
        HV.saveData()
    elseif name == "hv_btn_gear_preset_both" then
        c.gear_equip_ids = "6840, 1966"
        HV.saveData()
        addLog("Preset Gear: DCS + Harvester.")
    elseif name == "hv_btn_gear_preset_harv" then
        c.gear_equip_ids = "1966"
        HV.saveData()
        addLog("Preset Gear: Harvester Sorrows saja.")
    elseif name == "hv_btn_gear_preset_dcs" then
        c.gear_equip_ids = "6840"
        HV.saveData()
        addLog("Preset Gear: DCS saja.")

    -- SETTINGS TAB
    elseif name == "hv_toggle_ignore_gems" then
        c.ignore_gems = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_ignore_take_drop" then
        c.ignore_take_drop = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_auto_collect" then
        c.auto_collect = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_take_floating" then
        c.take_floating = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_mode_zigzag" then
        c.harvest_mode = (val == true) and "3zigzag" or "1by1"
        HV.saveData()
    elseif name == "hv_toggle_mode_teleport" then
        c.harvest_mode = (val == true) and "teleport" or "3zigzag"
        HV.saveData()
    elseif name == "hv_toggle_modfly" then
        c.use_modfly = (val == true)
        HV.saveData()
    elseif name == "hv_toggle_loop" then
        c.loop_enabled = (val == true)
        HV.saveData()
    elseif name == "hv_slider_harvest_delay" then
        local n = tonumber(val)
        if n and n >= 80 then c.harvest_delay = math.floor(n); HV.saveData() end
    elseif name == "hv_slider_step_delay" then
        local n = tonumber(val)
        if n and n >= 50 then c.step_delay = math.floor(n); HV.saveData() end
    elseif name == "hv_slider_warp_delay" then
        local n = tonumber(val)
        if n and n >= 1000 then c.warp_delay = math.floor(n); HV.saveData() end
    end
end
onValue = OnValue

function OnValue(a1, a2, a3)
    pcall(handleUIValue, a1, a2, a3)
end
onValue = OnValue
_G.OnValue = OnValue
_G.onValue = OnValue

-- Global hook setup
if setOnValue then
    local aliases = {
        "hv_btn_start", "hv_btn_stop", "hv_run_power", "hv_show_ui",
        "hv_manual_world_input", "hv_manual_door_input", "hv_manual_item_input",
        "hv_btn_add_farm", "hv_btn_add_cur_farm", "hv_btn_reset_status", "hv_btn_clear_farms",
        "hv_input_save_w", "hv_input_save_d", "hv_input_save_lim",
        "hv_btn_stype_all", "hv_btn_stype_block", "hv_btn_stype_seed",
        "hv_btn_add_save", "hv_btn_add_cur_save", "hv_btn_reset_save_status", "hv_btn_clear_save",
        "hv_slider_drop_threshold",
        "hv_input_ev_w", "hv_input_ev_d", "hv_input_ev_lim",
        "hv_btn_add_ev", "hv_btn_add_cur_ev", "hv_btn_reset_ev_status", "hv_btn_clear_ev",
        "hv_input_event_ids", "hv_btn_preset_mooncake", "hv_slider_event_threshold",
        "hv_input_gear_world", "hv_btn_add_cur_gear", "hv_toggle_magni_fuel", "hv_toggle_stop_no_fuel",
        "hv_slider_fuel_target", "hv_input_gear_equip_ids", "hv_btn_gear_preset_both", "hv_btn_gear_preset_harv", "hv_btn_gear_preset_dcs",
        "hv_toggle_ignore_gems", "hv_toggle_ignore_take_drop", "hv_toggle_auto_collect", "hv_toggle_take_floating",
        "hv_toggle_mode_zigzag", "hv_toggle_modfly", "hv_toggle_loop",
        "hv_slider_harvest_delay", "hv_slider_step_delay", "hv_slider_warp_delay",
    }
    for _, aliasName in ipairs(aliases) do
        pcall(setOnValue, aliasName, function(a1, a2, a3)
            if a2 == aliasName then
                OnValue(a1, a2, a3)
            elseif a1 == aliasName then
                OnValue(0, a1, a2)
            else
                OnValue(0, aliasName, a1)
            end
        end)
    end
end

-- Load persisted configuration & register Native Menu
HV.loadData()
registerNativeHarvestUI()

logMsg("`2BOREN HARVEST PRO v" .. HV.VERSION .. " SIAP! (/harvest)")
notifyMsg("BOREN HARVEST PRO Siap!")


-- ============================================================================
-- 9. INISIALISASI AWAL COMPACT DIALOG HARVEST
-- ============================================================================
_G.showHarvestMainDialog = DLG.showHarvestMainDialog
_G.DLG = DLG

-- Inisialisasi awal saat script di-Run (Standar In-Game Dialog)
logMsg("`5[BOREN HARVEST] `2Script Auto Harvest (In-Game Dialog) Aktif!")
if LogToConsole then
    pcall(LogToConsole, "`5[BOREN HARVEST] `2Ketik `c/hv `watau `c/harvest `wdi chat game untuk membuka Menu Form Dialog.")
end
if sendNotification then
    pcall(sendNotification, "Boren Auto Harvest Siap! Ketik /hv di chat game.")
end

-- Otomatis buka dialog saat pertama kali di-run via coroutine
local function openInitialHarvestDialog()
    safeSleep(200)
    local openFn = _G.showHarvestMainDialog or (DLG and DLG.showHarvestMainDialog)
    if openFn then pcall(openFn) end
end

if runCoroutine then
    pcall(runCoroutine, openInitialHarvestDialog)
elseif runThread then
    pcall(runThread, openInitialHarvestDialog)
else
    local openFn = _G.showHarvestMainDialog or (DLG and DLG.showHarvestMainDialog)
    if openFn then pcall(openFn) end
end

_G.HV = HV
return HV
