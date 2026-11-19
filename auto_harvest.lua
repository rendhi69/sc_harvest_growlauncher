-- ============================================================================
-- BOREN STORE - AUTO HARVEST PRO (GROWLAUNCHER)
-- Repo: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- Fitur:
--   1. Multi-World Farm List + Item ID Harvest (auto Block & Seed ID)
--   2. Multi-World Save Block/Seed dengan Limit Item per World (mis. 10k/20k)
--   3. Ignore Gems (blokir collect ID 112)
--   4. Mode 3-Zigzag Serpentine & 1-by-1
--   5. Auto Collect Block & Seed hasil harvest
--   6. Multi-World Save khusus Event / Mooncake
--   7. Custom List ID Item Event (selain block & seed) -> drop ke Event World
--   8. Gear World khusus ambil Magni / DCS / Harvester / Fuel Pack (+ auto equip)
--   9. Opsional Take Floating (ambil sisa drop block/seed/event setelah tree habis)
-- ============================================================================

local HV = {
    VERSION = "1.0.0",
    CFG = {
        -- 1. Default Item ID Harvest (bisa isi Block ID genap atau Seed ID ganjil)
        default_item_id  = 4584,      -- Contoh: Pepper Tree (4584 block / 4585 seed)
        -- 2. Multi-World Save Block/Seed + Limit per World
        save_worlds_raw  = "",        -- Format: WORLD:DOOR,WORLD2:DOOR2
        save_limit       = 20000,     -- Maks item per Save World (0 = unlimited)
        drop_threshold   = 180,       -- Drop ke Save World saat tas >= nilai ini
        -- 3. Ignore Gems
        ignore_gems      = true,
        -- 4. Mode Zigzag
        harvest_mode     = "3zigzag", -- "3zigzag" | "1by1"
        harvest_delay    = 180,       -- ms
        step_delay       = 110,       -- ms
        warp_delay       = 4500,      -- ms
        use_modfly       = true,
        loop_enabled     = false,
        -- 5. Auto Collect
        auto_collect     = true,
        collect_range    = 4,         -- tile radius auto collect objek hasil harvest
        -- 6 & 7. Event / Mooncake Save Worlds + Custom Event Item IDs
        event_worlds_raw = "",        -- Format: EVWORLD:DOOR,EVWORLD2:DOOR2
        event_ids_raw    = "1058,1094,1096,1098,1828", -- Mooncakes default (bisa ditambah bebas)
        event_threshold  = 150,       -- Drop ke Event World saat salah satu item event >= nilai ini
        -- 8. Gear World (Magni / DCS / Harvester / Fuel Pack)
        gear_world       = "",        -- Format: GEARWORLD atau GEARWORLD:DOOR
        use_magni        = false,     -- Magnifying Glass (1252)
        use_dcs          = false,     -- Dreamcatcher Staff (6840)
        use_harvester    = false,     -- Harvester (1830) / Harvester of Sorrows (1966)
        harvester_id     = 1966,      -- 1966 = Harvester of Sorrows, 1830 = Harvester
        use_fuel_pack    = false,     -- Fuel Pack (1746)
        fuel_target_amt  = 100,       -- Target stok Fuel Pack yang diambil dari Gear World
        -- 9. Opsional Take Floating setelah tree habis
        take_floating    = true,
    },
    STATE = {
        running          = false,
        status           = "Idle",
        active_tab       = "farm",    -- "farm" | "save" | "event" | "gear" | "set" | "log"
        show_ui          = true,
        rows             = {},        -- { { name="W", door="D", item_id=4584, status="Ready" }, ... }
        selected_row     = 0,
        save_world_idx   = 1,
        event_world_idx  = 1,
        full_save_map    = {},        -- [worldName] = true
        full_event_map   = {},        -- [worldName] = true
        anti_take        = false,
        pending_drop_id  = 0,
        pending_drop_amt = 0,
        drop_confirmed   = false,
        need_fuel        = false,
        total_harvested  = 0,
        total_dropped    = 0,
        logs             = {},
        -- Buffer input UI (aman di OpenGL thread)
        in_farm_world    = "",
        in_farm_item     = "4584",
        in_save_world    = "",
        in_event_world   = "",
        in_event_ids     = "1058,1094,1096,1098,1828",
        in_gear_world    = "",
        in_save_limit    = "20000",
        inv_preview      = { block = 0, seed = 0, fuel = 0, ev = 0 },
    },
}

-- ============================================================================
-- 1. ITEM IDs & SAFE HELPERS
-- ============================================================================
local function resolveItemID(name, fallback)
    if findItemID then
        local ok, id = pcall(findItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    if growtopia and growtopia.getItemID then
        local ok, id = pcall(growtopia.getItemID, name)
        if ok and tonumber(id) and tonumber(id) > 0 then return math.floor(tonumber(id)) end
    end
    return fallback
end

local ITEM = {
    PUNCH      = 18,
    GEMS       = 112,
    MAGNI      = resolveItemID("Magnifying Glass", 1252),
    DCS        = resolveItemID("Dreamcatcher Staff", 6840),
    HARVESTER  = resolveItemID("Harvester", 1830),
    SORROWS    = resolveItemID("Harvester of Sorrows", 1966),
    FUEL_PACK  = resolveItemID("Fuel Pack", 1746),
}

local function trimStr(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function cleanWorldName(s)
    return tostring(s or ""):gsub("%z", ""):gsub("`.", ""):gsub("^%s+", ""):gsub("%s+$", ""):upper()
end

-- Normalisasi ID harvest -> selalu kembalikan (blockID genap, seedID ganjil)
local function normalizeHarvestPair(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return 0, 0 end
    if id % 2 == 1 then return id - 1, id end
    return id, id + 1
end

local function addLogUI(msg)
    local clean = tostring(msg or ""):gsub("`.", "")
    local ts = ""
    if os and os.date then
        local ok, d = pcall(os.date, "%H:%M:%S")
        if ok and d then ts = "[" .. d .. "] " end
    end
    table.insert(HV.STATE.logs, 1, ts .. clean)
    if #HV.STATE.logs > 60 then table.remove(HV.STATE.logs) end
end

local function addLog(msg)
    addLogUI(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Boren Harvest] `w" .. tostring(msg or "")) end
end

local function safeSleep(ms)
    ms = math.max(10, tonumber(ms) or 50)
    local fn = sleep or CSleep
    if fn then pcall(fn, ms) end
end

local function runAsync(fn)
    if runCoroutine then pcall(runCoroutine, fn)
    else coroutine.resume(coroutine.create(fn)) end
end

-- ============================================================================
-- 2. PERSISTENCE (SAVE / LOAD KONFIGURASI & LIST WORLD)
-- ============================================================================
local CACHED_PATH = nil
local function getDataPath()
    if CACHED_PATH then return CACHED_PATH end
    if package and package.config and package.config:sub(1, 1) == "\\" then
        CACHED_PATH = "boren_harvest_data.txt"; return CACHED_PATH
    end
    local dirs = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
    }
    for _, d in ipairs(dirs) do
        local p = d .. "boren_harvest_data.txt"
        local ok, f = pcall(io.open, p, "a")
        if ok and f then f:close(); CACHED_PATH = p; return p end
    end
    CACHED_PATH = "boren_harvest_data.txt"
    return CACHED_PATH
end

local function parseWorldDoor(raw)
    local s = trimStr(raw):gsub("|", ":")
    if s == "" or s:sub(1, 1) == "#" then return nil end
    local w, d = s:match("^([^:]+):(.*)$")
    if w then
        w = cleanWorldName(w); d = cleanWorldName(d)
        return (w ~= "") and { name = w, door = d } or nil
    end
    local wn = cleanWorldName(s)
    return (wn ~= "") and { name = wn, door = "" } or nil
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
    local parts, st = {}, 1
    while true do
        local idx = s:find(":", st, true)
        if not idx then table.insert(parts, trimStr(s:sub(st))); break
        else table.insert(parts, trimStr(s:sub(st, idx - 1))); st = idx + 1 end
    end
    local w = cleanWorldName(parts[1] or "")
    if w == "" then return nil end
    local door = cleanWorldName(parts[2] or "")
    local iid = math.floor(tonumber(parts[3]) or tonumber(HV.CFG.default_item_id) or 4584)
    if iid <= 0 then iid = 4584 end
    return { name = w, door = door, item_id = iid, status = "Ready" }
end

local function parseEventIDSet()
    local map, list = {}, {}
    for tok in tostring(HV.CFG.event_ids_raw or ""):gmatch("[^,%s;|]+") do
        local id = math.floor(tonumber(tok) or 0)
        if id > 0 and not map[id] then
            map[id] = true
            table.insert(list, id)
        end
    end
    return map, list
end

function HV.saveData()
    local c = HV.CFG
    local lines = {
        "DEFID="   .. tostring(c.default_item_id),
        "SAVEW="   .. tostring(c.save_worlds_raw or ""),
        "SAVELIM=" .. tostring(c.save_limit),
        "DROPTH="  .. tostring(c.drop_threshold),
        "IGEMS="   .. (c.ignore_gems and "1" or "0"),
        "MODE="    .. tostring(c.harvest_mode),
        "HDELAY="  .. tostring(c.harvest_delay),
        "SDELAY="  .. tostring(c.step_delay),
        "MODFLY="  .. (c.use_modfly and "1" or "0"),
        "LOOP="    .. (c.loop_enabled and "1" or "0"),
        "ACOL="    .. (c.auto_collect and "1" or "0"),
        "EVW="     .. tostring(c.event_worlds_raw or ""),
        "EVIDS="   .. tostring(c.event_ids_raw or ""),
        "EVTH="    .. tostring(c.event_threshold),
        "GEARW="   .. tostring(c.gear_world or ""),
        "MAGNI="   .. (c.use_magni and "1" or "0"),
        "DCS="     .. (c.use_dcs and "1" or "0"),
        "HARV="    .. (c.use_harvester and "1" or "0"),
        "HARVID="  .. tostring(c.harvester_id),
        "FUEL="    .. (c.use_fuel_pack and "1" or "0"),
        "FUELAMT=" .. tostring(c.fuel_target_amt),
        "FLOAT="   .. (c.take_floating and "1" or "0"),
    }
    for _, r in ipairs(HV.STATE.rows) do
        table.insert(lines, string.format("ROW=%s:%s:%d|%s", r.name, r.door or "", r.item_id or c.default_item_id, r.status or "Ready"))
    end
    local ok, f = pcall(io.open, getDataPath(), "w")
    if ok and f then f:write(table.concat(lines, "\n")); f:close() end
end

function HV.loadData()
    local ok, f = pcall(io.open, getDataPath(), "r")
    if not ok or not f then return end
    local txt = f:read("*a"); f:close()
    if not txt or txt == "" then return end
    local c = HV.CFG
    HV.STATE.rows = {}
    for line in txt:gmatch("[^\r\n]+") do
        local k, v = line:match("^([A-Z]+)=(.*)$")
        if k == "DEFID" then c.default_item_id = tonumber(v) or 4584
        elseif k == "SAVEW" then c.save_worlds_raw = trimStr(v)
        elseif k == "SAVELIM" then c.save_limit = tonumber(v) or 20000
        elseif k == "DROPTH" then c.drop_threshold = tonumber(v) or 180
        elseif k == "IGEMS" then c.ignore_gems = (v ~= "0")
        elseif k == "MODE" and (v == "3zigzag" or v == "1by1") then c.harvest_mode = v
        elseif k == "HDELAY" then c.harvest_delay = tonumber(v) or 180
        elseif k == "SDELAY" then c.step_delay = tonumber(v) or 110
        elseif k == "MODFLY" then c.use_modfly = (v ~= "0")
        elseif k == "LOOP" then c.loop_enabled = (v == "1")
        elseif k == "ACOL" then c.auto_collect = (v ~= "0")
        elseif k == "EVW" then c.event_worlds_raw = trimStr(v)
        elseif k == "EVIDS" then c.event_ids_raw = trimStr(v)
        elseif k == "EVTH" then c.event_threshold = tonumber(v) or 150
        elseif k == "GEARW" then c.gear_world = trimStr(v)
        elseif k == "MAGNI" then c.use_magni = (v == "1")
        elseif k == "DCS" then c.use_dcs = (v == "1")
        elseif k == "HARV" then c.use_harvester = (v == "1")
        elseif k == "HARVID" then c.harvester_id = tonumber(v) or ITEM.SORROWS
        elseif k == "FUEL" then c.use_fuel_pack = (v == "1")
        elseif k == "FUELAMT" then c.fuel_target_amt = tonumber(v) or 100
        elseif k == "FLOAT" then c.take_floating = (v ~= "0")
        elseif k == "ROW" then
            local wd, st = v:match("^(.-)|(.*)$")
            local p = parseFarmRow(wd or v)
            if p then p.status = (st and st ~= "") and st or "Ready"; table.insert(HV.STATE.rows, p) end
        end
    end
    HV.STATE.in_farm_item  = tostring(c.default_item_id)
    HV.STATE.in_save_limit = tostring(c.save_limit)
    HV.STATE.in_event_ids  = tostring(c.event_ids_raw)
    HV.STATE.in_gear_world = tostring(c.gear_world)
end

-- ============================================================================
-- 3. GROWLAUNCHER WORLD, INVENTORY, MOVEMENT & OBJECT HELPERS
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
    for _, fn in ipairs({ getCurrentWorldName, GetWorldName, getWorld, getCurrentWorld }) do
        if type(fn) == "function" then
            local ok, res = pcall(fn)
            if ok and res ~= nil then
                if type(res) == "string" then
                    local nm = cleanWorldName(res)
                    if nm ~= "" then return nm end
                elseif type(res) == "table" or type(res) == "userdata" then
                    local okN, nm = pcall(function() return res.name or res.worldName end)
                    if okN and type(nm) == "string" and cleanWorldName(nm) ~= "" then return cleanWorldName(nm) end
                end
            end
        end
    end
    return ""
end

local function getTileSafe(tx, ty)
    if not getTile or tx < 0 or tx > 99 or ty < 0 or ty > 53 then return nil end
    local ok, t = pcall(getTile, tx, ty)
    return (ok and t) and t or nil
end

local function getInvCount(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return 0 end
    if growtopia and growtopia.checkInventoryCount then
        local ok, cnt = pcall(growtopia.checkInventoryCount, id)
        if ok and tonumber(cnt) then return math.floor(tonumber(cnt)) end
    end
    if getInventory then
        local ok, inv = pcall(getInventory)
        if ok and inv then
            local total = 0
            pcall(function()
                for _, it in pairs(inv) do
                    local iid = tonumber(it.id or it.itemid or it.itemID)
                    local amt = tonumber(it.amount or it.count) or 0
                    if iid == id then total = total + amt end
                end
            end)
            return total
        end
    end
    return 0
end

local function forEachWorldObject(fn)
    local getFn = getObjectList or getObjects or getWorldObjects
    if not getFn then return 0 end
    local ok, objs = pcall(getFn)
    if not ok or not objs then return 0 end
    local seen = 0
    pcall(function()
        for _, o in pairs(objs) do
            if o then
                local oid = tonumber(o.itemid or o.itemId or o.item_id)
                local uid = tonumber(o.id or o.oid or o.netid)
                local amt = tonumber(o.amount or o.count) or 1
                local px = (o.pos and tonumber(o.pos.x or o.pos[1])) or tonumber(o.x or o.posX)
                local py = (o.pos and tonumber(o.pos.y or o.pos[2])) or tonumber(o.y or o.posY)
                if oid and oid > 0 and uid and px and py then
                    seen = seen + 1
                    fn(oid, uid, amt, px, py)
                end
            end
        end
    end)
    return seen
end

local function setCollectCheats(enableCollect)
    HV.STATE.anti_take = not enableCollect
    if not editToggle then return end
    if HV.CFG.use_modfly then pcall(editToggle, "ModFly", true) end
    pcall(editToggle, "Anti Lava", true)
    pcall(editToggle, "Anti Collect", not enableCollect)
    pcall(editToggle, "Anti-Collect", not enableCollect)
    -- Jika Ignore Gems ON, matikan Auto Collect bawaan APK agar tidak ambil gems dan pakai packet collect terkontrol
    local apkAuto = enableCollect and HV.CFG.auto_collect and (not HV.CFG.ignore_gems)
    pcall(editToggle, "Auto Collect", apkAuto)
end

local unreachableMap = {}
local function moveSafeTo(tx, ty)
    if not HV.STATE.running then return false end
    tx = math.max(0, math.min(99, math.floor(tx or 0)))
    ty = math.max(0, math.min(53, math.floor(ty or 0)))
    local key = tx .. "," .. ty
    if unreachableMap[key] then return false end
    local cx, cy = getPlayerPos()
    if cx == tx and cy == ty then return true end
    local pFn = FindPath or findPath
    if not pFn then return false end
    if HV.CFG.use_modfly and editToggle then pcall(editToggle, "ModFly", true) end

    local dist = math.max(math.abs(cx - tx), math.abs(cy - ty))
    local okCall = pcall(pFn, tx, ty)
    if not okCall then unreachableMap[key] = true; return false end

    local maxW = (dist <= 3) and math.max(160, (tonumber(HV.CFG.step_delay) or 110) * 3) or math.max(1200, math.min(7000, dist * 160))
    local waited, lastX, lastY, stuck = 0, cx, cy, 0
    while waited < maxW and HV.STATE.running do
        local sl = (dist <= 3) and 25 or 50
        safeSleep(sl); waited = waited + sl
        local nx, ny = getPlayerPos()
        if nx == tx and ny == ty then safeSleep(HV.CFG.step_delay or 80); return true end
        if nx == lastX and ny == lastY then
            stuck = stuck + 1
            if stuck >= 6 then unreachableMap[key] = true; break end
        else
            stuck = 0; lastX, lastY = nx, ny
        end
    end
    local fx, fy = getPlayerPos()
    local arrived = (math.abs(fx - tx) <= 1 and math.abs(fy - ty) <= 1)
    if not arrived then unreachableMap[key] = true end
    return arrived
end

local function warpToWorld(wName, doorID)
    wName = cleanWorldName(wName); doorID = cleanWorldName(doorID)
    if wName == "" then return false end
    unreachableMap = {}
    if getCurrentWorldSafe() == wName and doorID == "" then return true end
    local joinStr = (doorID ~= "") and (wName .. "|" .. doorID) or wName
    for _ = 1, 3 do
        if not HV.STATE.running then return false end
        if sendPacket then pcall(sendPacket, 3, "action|join_request\nname|" .. joinStr .. "\ninvitedWorld|0\n")
        elseif growtopia and growtopia.warpTo then pcall(growtopia.warpTo, joinStr) end
        local w, lim = 0, math.max(4000, tonumber(HV.CFG.warp_delay) or 4500)
        while w < lim and HV.STATE.running do
            safeSleep(250); w = w + 250
            if getCurrentWorldSafe() == wName then safeSleep(600); return true end
        end
    end
    return getCurrentWorldSafe() == wName
end

local function punchTile(tx, ty)
    if not sendPacketRaw then return false end
    local p = getLocalSafe()
    local px = (p and (p.posX or (p.pos and p.pos.x))) or (tx * 32)
    local py = (p and (p.posY or (p.pos and p.pos.y))) or (ty * 32)
    return pcall(sendPacketRaw, false, {
        type = 3, value = ITEM.PUNCH, px = tx, py = ty, x = px, y = py,
        state = (px > tx * 32) and 48 or 32,
    })
end

local function collectNearbyAllowed(allowedSet, radiusTiles)
    if not HV.CFG.auto_collect or not sendPacketRaw then return end
    local px, py = getPlayerPos()
    local rPx = (radiusTiles or HV.CFG.collect_range or 4) * 32
    local p = getLocalSafe()
    local ppx = (p and (p.posX or (p.pos and p.pos.x))) or (px * 32)
    local ppy = (p and (p.posY or (p.pos and p.pos.y))) or (py * 32)
    forEachWorldObject(function(oid, uid, _, ox, oy)
        if not HV.STATE.running then return end
        if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
        if allowedSet[oid] then
            if math.abs(ox - ppx) <= rPx and math.abs(oy - ppy) <= rPx then
                pcall(sendPacketRaw, false, { type = 11, value = uid, x = ox, y = oy })
            end
        end
    end)
end

-- ============================================================================
-- 4. DROP ENGINE MULTI-WORLD DENGAN LIMIT ITEM PER WORLD + ANTI-TAKE
-- ============================================================================
local function buildDropDialogReturn(dlgText, fallbackID, dropAmt)
    local dName = dlgText:match("end_dialog|([^|\r\n]+)") or "drop_item"
    local embedLines, hasEmbed = {}, false
    for k, v in dlgText:gmatch("embed_data|([^|\r\n]+)|([^\r\n|]*)") do
        table.insert(embedLines, k .. "|" .. v)
        if k:lower():find("item", 1, true) then hasEmbed = true end
    end
    local countField = dlgText:match("add_text_input|([^|\r\n]+)|") or "count"
    local out = { "action|dialog_return", "dialog_name|" .. dName }
    if hasEmbed then
        for _, l in ipairs(embedLines) do table.insert(out, l) end
    else
        table.insert(out, "itemID|" .. tostring(fallbackID) .. "|")
    end
    table.insert(out, countField .. "|" .. tostring(dropAmt))
    return table.concat(out, "\n") .. "\n"
end

local function countDroppedObjectsInWorld(filterSet)
    local total = 0
    forEachWorldObject(function(oid, _, amt)
        if (not filterSet) or filterSet[oid] then
            total = total + (tonumber(amt) or 1)
        end
    end)
    return total
end

local function waitInvDropTo(itemID, targetMax, timeoutMs)
    local w = 0
    while w < (timeoutMs or 900) and HV.STATE.running do
        if getInvCount(itemID) <= targetMax then return true end
        safeSleep(60); w = w + 60
    end
    return getInvCount(itemID) <= targetMax
end

local function dropItemAllInCurrentWorld(itemID, label)
    local cur = getInvCount(itemID)
    if cur <= 0 then return true, 0 end
    setCollectCheats(false) -- Anti-Take ON!
    safeSleep(150)

    local droppedTotal = 0
    local shiftTries = 0
    while cur > 0 and HV.STATE.running and shiftTries < 12 do
        local batch = math.min(200, cur)
        local targetAfter = cur - batch
        HV.STATE.pending_drop_id  = itemID
        HV.STATE.pending_drop_amt = batch
        HV.STATE.drop_confirmed   = false
        HV.STATE.status = string.format("Drop %s (%d)...", tostring(label or itemID), batch)

        local ok = false
        if growtopia and growtopia.confirmDropItem then
            pcall(growtopia.confirmDropItem, itemID, batch)
            ok = waitInvDropTo(itemID, cur - 1, 700)
        end
        if not ok and sendPacket and HV.STATE.running then
            HV.STATE.drop_confirmed = false
            pcall(sendPacket, 2, "action|drop\n|itemID|" .. tostring(itemID))
            ok = waitInvDropTo(itemID, cur - 1, 950)
        end
        if not ok and sendPacket and HV.STATE.running then
            for _, dn in ipairs({ "drop", "drop_item" }) do
                pcall(sendPacket, 2, string.format("action|dialog_return\ndialog_name|%s\nitemID|%d|\ncount|%d\n", dn, itemID, batch))
                ok = waitInvDropTo(itemID, cur - 1, 650)
                if ok then break end
            end
        end

        HV.STATE.pending_drop_id  = 0
        HV.STATE.pending_drop_amt = 0

        local after = getInvCount(itemID)
        if after < cur then
            droppedTotal = droppedTotal + (cur - after)
            HV.STATE.total_dropped = HV.STATE.total_dropped + (cur - after)
            cur = after
            safeSleep(180)
        else
            -- Petak penuh -> geser 1 tile ke kanan/kiri lalu coba lagi
            shiftTries = shiftTries + 1
            local px, py = getPlayerPos()
            local nx = (px < 96) and (px + 1) or math.max(2, px - 2)
            moveSafeTo(nx, py)
            safeSleep(220)
        end
    end
    return (getInvCount(itemID) == 0), droppedTotal
end

-- Drop item ke daftar Multi-World Save (otomatis cek limit per world -> pindah next world!)
local function dropItemsToWorldList(itemIDs, worldsRaw, limitPerWorld, fullMap, isEvent, returnFarm)
    local toDrop = {}
    for _, id in ipairs(itemIDs) do
        if getInvCount(id) > 0 then table.insert(toDrop, id) end
    end
    if #toDrop == 0 then return true end

    local worlds = parseWorldList(worldsRaw)
    if #worlds == 0 then
        addLog("`4List " .. (isEvent and "Event Save World" or "Save World") .. " kosong!")
        return false
    end

    local filterSet = {}
    for _, id in ipairs(itemIDs) do filterSet[id] = true end
    local lim = math.max(0, math.floor(tonumber(limitPerWorld) or 0))
    local startIdx = isEvent and HV.STATE.event_world_idx or HV.STATE.save_world_idx
    if startIdx < 1 or startIdx > #worlds then startIdx = 1 end

    for offset = 0, #worlds - 1 do
        if not HV.STATE.running then return false end
        local idx = ((startIdx - 1 + offset) % #worlds) + 1
        local sw = worlds[idx]
        if not fullMap[sw.name] then
            HV.STATE.status = (isEvent and "Event Save: " or "Save: ") .. sw.name
            if warpToWorld(sw.name, sw.door) then
                setCollectCheats(false)
                safeSleep(350)

                local curInWorld = countDroppedObjectsInWorld(isEvent and nil or filterSet)
                if lim > 0 and curInWorld >= lim then
                    addLog(string.format("`e[%s] %s sudah mencapai limit (%d/%d) -> pindah next world!",
                        isEvent and "EventSave" or "Save", sw.name, curInWorld, lim))
                    fullMap[sw.name] = true
                else
                    local allCleared = true
                    for _, id in ipairs(toDrop) do
                        if not HV.STATE.running then return false end
                        if getInvCount(id) > 0 then
                            -- Cek limit lagi sebelum drop item berikutnya
                            if lim > 0 and countDroppedObjectsInWorld(isEvent and nil or filterSet) >= lim then
                                addLog(string.format("`e[Save] %s mencapai limit %d -> lanjut next save world!", sw.name, lim))
                                fullMap[sw.name] = true
                                allCleared = false
                                break
                            end
                            local okD = dropItemAllInCurrentWorld(id, id)
                            if not okD then
                                fullMap[sw.name] = true
                                allCleared = false
                                break
                            end
                        end
                    end

                    if isEvent then HV.STATE.event_world_idx = idx else HV.STATE.save_world_idx = idx end
                    if allCleared then
                        if returnFarm then
                            warpToWorld(returnFarm.name, returnFarm.door)
                            setCollectCheats(true)
                        end
                        return true
                    end
                end
            end
        end
    end

    addLog("`4Semua " .. (isEvent and "Event Save World" or "Save World") .. " penuh / mencapai limit!")
    return false
end

-- ============================================================================
-- 5. GEAR WORLD (AMBIL MAGNI / DCS / HARVESTER / FUEL PACK + AUTO EQUIP)
-- ============================================================================
local function equipItem(itemID)
    if not sendPacketRaw or getInvCount(itemID) <= 0 then return false end
    return pcall(sendPacketRaw, false, { type = 10, value = itemID })
end

local function ensureGearAndFuel(returnFarm)
    local c = HV.CFG
    local needed = {}
    if c.use_magni and getInvCount(ITEM.MAGNI) <= 0 then table.insert(needed, { id = ITEM.MAGNI, amt = 1, equip = true, name = "Magni" }) end
    if c.use_dcs and getInvCount(ITEM.DCS) <= 0 then table.insert(needed, { id = ITEM.DCS, amt = 1, equip = true, name = "DCS" }) end
    if c.use_harvester then
        local hid = (tonumber(c.harvester_id) == ITEM.HARVESTER) and ITEM.HARVESTER or ITEM.SORROWS
        if getInvCount(hid) <= 0 then table.insert(needed, { id = hid, amt = 1, equip = true, name = "Harvester" }) end
    end
    if c.use_fuel_pack and (getInvCount(ITEM.FUEL_PACK) <= 0 or HV.STATE.need_fuel) then
        local want = math.max(1, math.min(200, tonumber(c.fuel_target_amt) or 100))
        if getInvCount(ITEM.FUEL_PACK) < math.min(10, want) then
            table.insert(needed, { id = ITEM.FUEL_PACK, amt = want, equip = false, name = "Fuel Pack" })
        end
    end

    -- Jika fuel masih ada di tas saat butuh isi ulang, langsung pakai Fuel Pack
    if HV.STATE.need_fuel and c.use_fuel_pack and getInvCount(ITEM.FUEL_PACK) > 0 then
        equipItem(ITEM.FUEL_PACK)
        HV.STATE.need_fuel = false
        safeSleep(250)
    end

    if #needed == 0 then
        -- Pastikan gear yang dipilih terpakai
        if c.use_magni then equipItem(ITEM.MAGNI); safeSleep(150) end
        if c.use_dcs then equipItem(ITEM.DCS); safeSleep(150) end
        if c.use_harvester then equipItem((tonumber(c.harvester_id) == ITEM.HARVESTER) and ITEM.HARVESTER or ITEM.SORROWS); safeSleep(150) end
        return true
    end

    local gw = parseWorldDoor(c.gear_world)
    if not gw then
        addLog("`e[Gear] Gear World belum diisi — melewati pengambilan gear/fuel.")
        return true
    end

    HV.STATE.status = "Gear World: " .. gw.name
    addLog("[Gear] Mengambil perlengkapan dari " .. gw.name)
    if not warpToWorld(gw.name, gw.door) then
        addLog("`4[Gear] Gagal warp ke Gear World " .. gw.name)
        return false
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
            equipItem(req.id)
            safeSleep(200)
            addLog("`2[Gear] Berhasil ambil & equip " .. req.name)
        elseif req.id == ITEM.FUEL_PACK and getInvCount(ITEM.FUEL_PACK) > 0 then
            addLog("`2[Gear] Fuel Pack terambil: " .. getInvCount(ITEM.FUEL_PACK))
            if HV.STATE.need_fuel then equipItem(ITEM.FUEL_PACK); HV.STATE.need_fuel = false end
        end
    end

    if returnFarm then
        warpToWorld(returnFarm.name, returnFarm.door)
        setCollectCheats(true)
    end
    return true
end

-- ============================================================================
-- 6. HARVEST ENGINE (3-ZIGZAG / 1BY1 + TAKE FLOATING + AUTO DROP)
-- ============================================================================
local function isReadyTree(tx, ty, seedID)
    local t = getTileSafe(tx, ty)
    if not t then return false end
    if tonumber(t.fg) ~= seedID then return false end
    if t.readyharvest == true then return true end
    if tonumber(t.progress) and tonumber(t.progress) >= 1.0 then return true end
    return false
end

local function updateInvPreview(blockID, seedID, eventList)
    HV.STATE.inv_preview.block = getInvCount(blockID)
    HV.STATE.inv_preview.seed  = getInvCount(seedID)
    HV.STATE.inv_preview.fuel  = getInvCount(ITEM.FUEL_PACK)
    local evSum = 0
    for _, eid in ipairs(eventList) do evSum = evSum + getInvCount(eid) end
    HV.STATE.inv_preview.ev = evSum
end

local function checkAndDropIfFull(row, blockID, seedID, eventList, forceDrop)
    updateInvPreview(blockID, seedID, eventList)
    local th = math.max(20, math.min(200, tonumber(HV.CFG.drop_threshold) or 180))
    local eth = math.max(10, math.min(200, tonumber(HV.CFG.event_threshold) or 150))

    -- 1. Cek item Event (Mooncake & custom IDs) -> drop ke Event Save World
    local needEventDrop = false
    for _, eid in ipairs(eventList) do
        local cnt = getInvCount(eid)
        if (forceDrop and cnt > 0) or (cnt >= eth) then needEventDrop = true; break end
    end
    if needEventDrop and trimStr(HV.CFG.event_worlds_raw) ~= "" then
        if not dropItemsToWorldList(eventList, HV.CFG.event_worlds_raw, 0, HV.STATE.full_event_map, true, forceDrop and nil or row) then
            return false
        end
    end

    -- 2. Cek Block & Seed hasil harvest -> drop ke Multi-World Save (dengan limit!)
    local bCnt, sCnt = getInvCount(blockID), getInvCount(seedID)
    if (forceDrop and (bCnt > 0 or sCnt > 0)) or bCnt >= th or sCnt >= th then
        if not dropItemsToWorldList({ blockID, seedID }, HV.CFG.save_worlds_raw, HV.CFG.save_limit, HV.STATE.full_save_map, false, forceDrop and nil or row) then
            return false
        end
    end

    -- 3. Cek Fuel Pack jika Harvester kehabisan fuel
    if HV.STATE.need_fuel and HV.CFG.use_fuel_pack then
        ensureGearAndFuel(forceDrop and nil or row)
    end
    updateInvPreview(blockID, seedID, eventList)
    return true
end

-- Fitur #9: Opsional Take Floating (ambil semua block/seed/event yang jatuh setelah tree habis)
local function sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList)
    if not HV.CFG.take_floating then return true end
    HV.STATE.status = row.name .. " Take Floating..."
    addLog("[Floating] Menyapu sisa drop block/seed/event di " .. row.name)
    setCollectCheats(true)

    local foundAny = true
    local pass = 0
    while foundAny and pass < 6 and HV.STATE.running do
        foundAny = false
        pass = pass + 1
        local targets = {}
        forEachWorldObject(function(oid, uid, _, ox, oy)
            if HV.CFG.ignore_gems and oid == ITEM.GEMS then return end
            if allowedSet[oid] then
                table.insert(targets, { oid = oid, uid = uid, ox = ox, oy = oy, tx = math.floor((ox + 10) / 32), ty = math.floor((oy + 10) / 32) })
            end
        end)
        if #targets == 0 then break end
        foundAny = true
        for _, obj in ipairs(targets) do
            if not HV.STATE.running then return false end
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
    if blockID <= 0 then
        row.status = "Invalid ID"; HV.saveData(); return false
    end

    local eventMap, eventList = parseEventIDSet()
    local allowedSet = { [blockID] = true, [seedID] = true }
    for id in pairs(eventMap) do allowedSet[id] = true end

    -- Pastikan Gear / Fuel siap sebelum masuk farm
    if not ensureGearAndFuel(nil) then return false end

    row.status = "Warping..."
    HV.STATE.status = "Warp: " .. row.name
    if not warpToWorld(row.name, row.door) then
        row.status = "Inaccessible"; HV.saveData(); return false
    end
    setCollectCheats(true)
    safeSleep(500)

    local hDelay = math.max(90, tonumber(HV.CFG.harvest_delay) or 180)
    local goingRight = true

    -- Scan dari atas ke bawah (Y = 0..53) dengan pola Zigzag Serpentine (seperti Auto Plant)
    for y = 0, 53 do
        if not HV.STATE.running then return false end
        local hasReady = false
        for x = 0, 99 do
            if isReadyTree(x, y, seedID) then hasReady = true; break end
        end

        if hasReady then
            row.status = "Harvest Y=" .. tostring(y)
            HV.STATE.status = row.name .. " Y=" .. tostring(y)
            if HV.CFG.harvest_mode == "3zigzag" then
                local standX = goingRight and 1 or 98
                local step = goingRight and 3 or -3
                while (goingRight and standX <= 99) or ((not goingRight) and standX >= 0) do
                    if not HV.STATE.running then return false end
                    local xs = goingRight and { standX - 1, standX, standX + 1 } or { standX + 1, standX, standX - 1 }
                    local spots = {}
                    for _, bx in ipairs(xs) do
                        if bx >= 0 and bx <= 99 and isReadyTree(bx, y, seedID) then table.insert(spots, bx) end
                    end
                    if #spots > 0 then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        local moveX = (standX >= 0 and standX <= 99) and standX or spots[1]
                        if moveSafeTo(moveX, y) then
                            for _, bx in ipairs(spots) do
                                if not HV.STATE.running then return false end
                                if isReadyTree(bx, y, seedID) then
                                    punchTile(bx, y)
                                    HV.STATE.total_harvested = HV.STATE.total_harvested + 1
                                    safeSleep(hDelay)
                                end
                            end
                            collectNearbyAllowed(allowedSet, HV.CFG.collect_range)
                        end
                    end
                    standX = standX + step
                end
            else
                local x1, x2, st = goingRight and 0 or 99, goingRight and 99 or 0, goingRight and 1 or -1
                for bx = x1, x2, st do
                    if not HV.STATE.running then return false end
                    if isReadyTree(bx, y, seedID) then
                        if not checkAndDropIfFull(row, blockID, seedID, eventList, false) then return false end
                        if moveSafeTo(bx, y) then
                            punchTile(bx, y)
                            HV.STATE.total_harvested = HV.STATE.total_harvested + 1
                            safeSleep(hDelay)
                            collectNearbyAllowed(allowedSet, HV.CFG.collect_range)
                        end
                    end
                end
            end
            goingRight = not goingRight
        end
    end

    -- Fitur #9: Opsional sapu sisa drop floating setelah semua tree habis
    if HV.CFG.take_floating then
        if not sweepFloatingObjects(row, blockID, seedID, allowedSet, eventList) then return false end
    end

    -- Drop semua sisa tas sebelum lanjut world berikutnya
    if not checkAndDropIfFull(row, blockID, seedID, eventList, true) then return false end

    row.status = "Done"
    HV.saveData()
    addLog("`2[Selesai] Harvest " .. row.name .. " tuntas!")
    return true
end

local function mainLoop()
    HV.STATE.running = true
    HV.STATE.full_save_map = {}
    HV.STATE.full_event_map = {}
    addLog("Auto Harvest dimulai.")

    while HV.STATE.running do
        for _, row in ipairs(HV.STATE.rows) do
            if not HV.STATE.running then break end
            if row.status ~= "Done" and row.status ~= "Inaccessible" then
                if not processFarmWorld(row) then break end
                safeSleep(400)
            end
        end
        if not HV.STATE.running then break end
        if HV.CFG.loop_enabled and #HV.STATE.rows > 0 then
            for _, r in ipairs(HV.STATE.rows) do
                if r.status ~= "Inaccessible" then r.status = "Ready" end
            end
            HV.saveData()
            safeSleep(2500)
        else
            break
        end
    end

    HV.STATE.running = false
    setCollectCheats(true)
    HV.STATE.status = "Idle"
    addLog("Auto Harvest berhenti.")
end

function HV.start()
    if HV.STATE.running then return end
    if #HV.STATE.rows == 0 then
        addLog("`4Daftar Farm World kosong! Tambahkan world dulu.")
        HV.STATE.status = "List Kosong"
        return
    end
    runAsync(function()
        local ok, err = xpcall(mainLoop, function(e)
            return tostring(e) .. "\n" .. (debug and debug.traceback and debug.traceback() or "")
        end)
        if not ok then
            addLog("`4[Crash] " .. tostring(err))
            HV.STATE.running = false; HV.STATE.status = "Error"
        end
    end)
end

function HV.stop()
    HV.STATE.running = false
    HV.STATE.pending_drop_id = 0
    HV.STATE.status = "Stopped"
end

-- ============================================================================
-- 7. HOOKS: IGNORE GEMS (112), ANTI-TAKE, AUTO DROP DIALOG & FUEL DETECT
-- ============================================================================
local function onSendPacketRawHook(pkt)
    if not pkt or tonumber(pkt.type) ~= 11 then return false end
    -- Saat drop berlangsung, blokir semua collect (Anti-Take)
    if HV.STATE.anti_take then return true end
    -- Ignore Gems (ID 112)
    if HV.STATE.running and HV.CFG.ignore_gems then
        local uid = tonumber(pkt.value) or 0
        if uid > 0 then
            local isGem = false
            forEachWorldObject(function(oid, id)
                if id == uid and oid == ITEM.GEMS then isGem = true end
            end)
            if isGem then return true end
        end
    end
    return false
end

local function onVariantHook(var)
    if not var then return false end
    local fn = tostring(var.v1 or "")
    local v2 = tostring(var.v2 or "")
    -- Auto-confirm drop dialog
    if fn == "OnDialogRequest" and (HV.STATE.pending_drop_id or 0) > 0 then
        local low = v2:lower()
        if low:find("drop", 1, true) then
            if not HV.STATE.drop_confirmed then
                HV.STATE.drop_confirmed = true
                if sendPacket then
                    pcall(sendPacket, 2, buildDropDialogReturn(v2, HV.STATE.pending_drop_id, HV.STATE.pending_drop_amt))
                end
            end
            return true
        end
    end
    -- Deteksi pesan kehabisan fuel Harvester
    if fn == "OnConsoleMessage" or fn == "OnTextOverlay" then
        local low = v2:lower()
        if low:find("out of fuel", 1, true) or low:find("need fuel", 1, true) or low:find("no fuel", 1, true) then
            HV.STATE.need_fuel = true
        end
    end
    return false
end

-- ============================================================================
-- 8. COMPACT IMGUI UI + NATIVE GROWLAUNCHER MENU
-- ============================================================================
local function safeInput(id, curVal, maxLen)
    local s = tostring(curVal or "")
    local ok, r1, r2 = pcall(ImGui.InputText, id, s, maxLen or 256)
    if not ok then return false, s end
    if type(r1) == "boolean" and type(r2) == "string" then return (r1 or r2 ~= s), r2
    elseif type(r1) == "string" then return (r2 == true or r1 ~= s), r1
    elseif type(r2) == "string" and r2 ~= s then return true, r2 end
    return false, s
end

local function safeCheckbox(label, curVal)
    local ok, r1, r2 = pcall(ImGui.Checkbox, label, curVal)
    if not ok then return false, curVal end
    if type(r1) == "boolean" and type(r2) == "boolean" then return r1, r2
    elseif type(r1) == "boolean" and r1 ~= curVal then return true, r1 end
    return false, curVal
end

function onDrawImGui()
    if (not ImGui) or (not HV.STATE.show_ui) then return end
    pcall(function()
        if ImGui.SetNextWindowSize and ImVec2 then
            ImGui.SetNextWindowSize(ImVec2(430, 390), (ImGui.Cond and ImGui.Cond.FirstUseEver) or 4)
        end
        local opened = ImGui.Begin("BOREN HARVEST v" .. HV.VERSION)
        if opened then
            local st, c = HV.STATE, HV.CFG
            ImGui.Text(string.format("Status: %s | Tree: %d | Drop: %d", st.status, st.total_harvested, st.total_dropped))
            if not st.running then
                if ImGui.Button("START##hv") then HV.start() end
            else
                if ImGui.Button("STOP##hv") then HV.stop() end
            end
            ImGui.SameLine()
            for _, tb in ipairs({ { "farm", "Farm" }, { "save", "Save" }, { "event", "Event" }, { "gear", "Gear" }, { "set", "Set" }, { "log", "Log" } }) do
                if ImGui.Button((st.active_tab == tb[1] and ("[" .. tb[2] .. "]") or tb[2]) .. "##t_" .. tb[1]) then
                    st.active_tab = tb[1]
                end
                ImGui.SameLine()
            end
            ImGui.NewLine()
            ImGui.Separator()

            -- TAB 1: FARM LIST & ITEM ID
            if st.active_tab == "farm" then
                local chW, vW = safeInput("World:Door##fw", st.in_farm_world, 128)
                if chW then st.in_farm_world = vW end
                local chI, vI = safeInput("Item ID##fi", st.in_farm_item, 32)
                if chI then st.in_farm_item = vI end
                if ImGui.Button("+ Add Farm##af") then
                    local iid = tonumber(st.in_farm_item) or c.default_item_id
                    c.default_item_id = iid
                    local p = parseFarmRow(st.in_farm_world .. ":" .. tostring(iid))
                    if p then table.insert(st.rows, p); st.in_farm_world = ""; HV.saveData() end
                end
                ImGui.SameLine()
                if ImGui.Button("+ World Ini##acw") then
                    runAsync(function()
                        local cw = getCurrentWorldSafe()
                        if cw ~= "" then
                            local iid = tonumber(st.in_farm_item) or c.default_item_id
                            table.insert(st.rows, { name = cw, door = "", item_id = iid, status = "Ready" })
                            HV.saveData()
                            addLog("Tambah farm: " .. cw .. " (ID " .. iid .. ")")
                        end
                    end)
                end
                ImGui.SameLine()
                if ImGui.Button("Reset Status##rs") then
                    for _, r in ipairs(st.rows) do r.status = "Ready" end
                    HV.saveData()
                end
                ImGui.SameLine()
                if ImGui.Button("Clear##cf") then st.rows = {}; HV.saveData() end

                ImGui.Separator()
                ImGui.Text("Daftar Farm (" .. #st.rows .. "):")
                for i, r in ipairs(st.rows) do
                    local bID, sID = normalizeHarvestPair(r.item_id)
                    ImGui.Text(string.format("%d. %s%s | B:%d S:%d | %s", i, r.name, (r.door ~= "" and (":" .. r.door) or ""), bID, sID, r.status))
                    ImGui.SameLine()
                    if ImGui.Button("X##del_" .. i) then table.remove(st.rows, i); HV.saveData(); break end
                end

            -- TAB 2: MULTI-WORLD SAVE BLOCK/SEED + LIMIT
            elseif st.active_tab == "save" then
                ImGui.Text("Save Worlds (pisah koma, format WORLD:DOOR):")
                local chSW, vSW = safeInput("##sw_in", c.save_worlds_raw, 512)
                if chSW then c.save_worlds_raw = vSW; HV.saveData() end
                local chLim, vLim = safeInput("Limit Item/World##slim", st.in_save_limit, 32)
                if chLim then
                    st.in_save_limit = vLim
                    local n = tonumber(vLim)
                    if n and n >= 0 then c.save_limit = math.floor(n); HV.saveData() end
                end
                ImGui.Text("0 = tanpa limit. Contoh: 10000 atau 20000.")
                ImGui.Text("Drop saat tas >= " .. tostring(c.drop_threshold))
                ImGui.SameLine()
                if ImGui.Button("-20##dt1") then c.drop_threshold = math.max(20, c.drop_threshold - 20); HV.saveData() end
                ImGui.SameLine()
                if ImGui.Button("+20##dt2") then c.drop_threshold = math.min(200, c.drop_threshold + 20); HV.saveData() end
                if ImGui.Button("Reset Penuh Save World##rfs") then st.full_save_map = {}; st.save_world_idx = 1 end

            -- TAB 3: EVENT / MOONCAKE SAVE WORLD + CUSTOM EVENT IDS
            elseif st.active_tab == "event" then
                ImGui.Text("Event / Mooncake Save Worlds (WORLD:DOOR, ...):")
                local chEW, vEW = safeInput("##evw_in", c.event_worlds_raw, 512)
                if chEW then c.event_worlds_raw = vEW; HV.saveData() end
                ImGui.Text("List ID Item Event (pisah koma, selain block & seed):")
                local chEI, vEI = safeInput("##evi_in", c.event_ids_raw, 512)
                if chEI then c.event_ids_raw = vEI; HV.saveData() end
                ImGui.Text("Default Mooncake: 1058,1094,1096,1098,1828")
                ImGui.Text("Drop Event saat tas >= " .. tostring(c.event_threshold))
                ImGui.SameLine()
                if ImGui.Button("-20##et1") then c.event_threshold = math.max(10, c.event_threshold - 20); HV.saveData() end
                ImGui.SameLine()
                if ImGui.Button("+20##et2") then c.event_threshold = math.min(200, c.event_threshold + 20); HV.saveData() end

            -- TAB 4: GEAR WORLD (MAGNI / DCS / HARVESTER / FUEL PACK)
            elseif st.active_tab == "gear" then
                ImGui.Text("Gear World (format WORLD:DOOR):")
                local chGW, vGW = safeInput("##gw_in", c.gear_world, 128)
                if chGW then c.gear_world = vGW; HV.saveData() end
                local chM, vM = safeCheckbox("Ambil & Equip Magni (" .. ITEM.MAGNI .. ")", c.use_magni)
                if chM then c.use_magni = vM; HV.saveData() end
                local chD, vD = safeCheckbox("Ambil & Equip DCS (" .. ITEM.DCS .. ")", c.use_dcs)
                if chD then c.use_dcs = vD; HV.saveData() end
                local chH, vH = safeCheckbox("Ambil & Equip Harvester", c.use_harvester)
                if chH then c.use_harvester = vH; HV.saveData() end
                if c.use_harvester then
                    ImGui.SameLine()
                    local isSor = (tonumber(c.harvester_id) == ITEM.SORROWS)
                    if ImGui.Button(isSor and "Sorrows (1966)" or "Normal (1830)") then
                        c.harvester_id = isSor and ITEM.HARVESTER or ITEM.SORROWS
                        HV.saveData()
                    end
                end
                local chF, vF = safeCheckbox("Auto Ambil & Pakai Fuel Pack (" .. ITEM.FUEL_PACK .. ")", c.use_fuel_pack)
                if chF then c.use_fuel_pack = vF; HV.saveData() end
                ImGui.Text("Target Ambil Fuel: " .. tostring(c.fuel_target_amt))
                ImGui.SameLine()
                if ImGui.Button("-25##fa1") then c.fuel_target_amt = math.max(25, c.fuel_target_amt - 25); HV.saveData() end
                ImGui.SameLine()
                if ImGui.Button("+25##fa2") then c.fuel_target_amt = math.min(200, c.fuel_target_amt + 25); HV.saveData() end

            -- TAB 5: SETTINGS
            elseif st.active_tab == "set" then
                local chIG, vIG = safeCheckbox("Ignore Gems (112)", c.ignore_gems)
                if chIG then c.ignore_gems = vIG; HV.saveData() end
                local chAC, vAC = safeCheckbox("Auto Collect Block & Seed", c.auto_collect)
                if chAC then c.auto_collect = vAC; HV.saveData() end
                local chTF, vTF = safeCheckbox("Take Floating setelah tree habis", c.take_floating)
                if chTF then c.take_floating = vTF; HV.saveData() end
                local chLP, vLP = safeCheckbox("Loop Farm List", c.loop_enabled)
                if chLP then c.loop_enabled = vLP; HV.saveData() end
                local chMF, vMF = safeCheckbox("ModFly", c.use_modfly)
                if chMF then c.use_modfly = vMF; HV.saveData() end
                ImGui.Text("Mode: " .. c.harvest_mode)
                ImGui.SameLine()
                if ImGui.Button("Ganti Mode##gm") then
                    c.harvest_mode = (c.harvest_mode == "3zigzag") and "1by1" or "3zigzag"
                    HV.saveData()
                end
                ImGui.Text("Harvest Delay: " .. tostring(c.harvest_delay) .. "ms")
                ImGui.SameLine()
                if ImGui.Button("-20##hd1") then c.harvest_delay = math.max(90, c.harvest_delay - 20); HV.saveData() end
                ImGui.SameLine()
                if ImGui.Button("+20##hd2") then c.harvest_delay = math.min(500, c.harvest_delay + 20); HV.saveData() end

            -- TAB 6: LOGS
            else
                ImGui.Text(string.format("Tas -> B:%d | S:%d | Ev:%d | Fuel:%d", st.inv_preview.block, st.inv_preview.seed, st.inv_preview.ev, st.inv_preview.fuel))
                if ImGui.Button("Clear Log##cl") then st.logs = {} end
                ImGui.Separator()
                for i = 1, math.min(10, #st.logs) do
                    if ImGui.TextWrapped then ImGui.TextWrapped(st.logs[i]) else ImGui.Text(st.logs[i]) end
                end
            end
        end
        ImGui.End()
    end)
end
OnDrawImGui = onDrawImGui

-- Menu Native Growlauncher (ikon resmi terbukti muncul)
local function registerNativeMenu()
    if not addIntoModule then return end
    local js = nil
    if UserInterface and UserInterface.new then
        local okU, ui = pcall(UserInterface.new, "Auto Harvest", "PlayArrow")
        if okU and ui and ui.generateJSON then
            ui:addLabelApp("Boren Store - Auto Harvest v" .. HV.VERSION, "Storefront")
            ui:addButton("START HARVEST", "hv_btn_start")
            ui:addButton("STOP HARVEST", "hv_btn_stop")
            ui:addToggle("Tampilkan Panel ImGui", HV.STATE.show_ui, "hv_show_ui", false)
            ui:addToggle("Ignore Gems", HV.CFG.ignore_gems, "hv_igems", false)
            ui:addToggle("Take Floating", HV.CFG.take_floating, "hv_float", false)
            local okJ, out = pcall(function() return ui:generateJSON() end)
            if okJ and type(out) == "string" and out ~= "" then js = out end
        end
    end
    if not js then
        js = '{"sub_name":"Auto Harvest","icon":"PlayArrow","menu":[' ..
            '{"type":"labelapp","text":"Boren Store - Auto Harvest","icon":"Storefront"},' ..
            '{"type":"button","text":"START HARVEST","alias":"hv_btn_start"},' ..
            '{"type":"button","text":"STOP HARVEST","alias":"hv_btn_stop"},' ..
            '{"type":"toggle","text":"Tampilkan Panel ImGui","default":true,"alias":"hv_show_ui"},' ..
            '{"type":"toggle","text":"Ignore Gems","default":true,"alias":"hv_igems"},' ..
            '{"type":"toggle","text":"Take Floating","default":true,"alias":"hv_float"}]}'
    end
    if addCategory then pcall(addCategory, "Boren Harvest", "Storefront") end
    pcall(addIntoModule, js, "Boren Harvest")
end

local function handleVal(name, val)
    if name == "hv_btn_start" then HV.start()
    elseif name == "hv_btn_stop" then HV.stop()
    elseif name == "hv_show_ui" then HV.STATE.show_ui = (val == true)
    elseif name == "hv_igems" then HV.CFG.ignore_gems = (val == true); HV.saveData()
    elseif name == "hv_float" then HV.CFG.take_floating = (val == true); HV.saveData() end
end

function OnValue(a1, a2, a3)
    if type(a2) == "string" then handleVal(a2, a3)
    elseif type(a1) == "string" then handleVal(a1, a2) end
end
onValue         = OnValue
onVariant       = onVariantHook
OnVariant       = onVariantHook
onSendPacketRaw = onSendPacketRawHook
OnSendPacketRaw = onSendPacketRawHook

if addHook then
    pcall(addHook, onVariantHook, "onvariant")
    pcall(addHook, onSendPacketRawHook, "onsendpacketraw")
    pcall(addHook, onValue, "onvalue")
end

HV.loadData()
registerNativeMenu()
if setOnValue then
    for _, al in ipairs({ "hv_btn_start", "hv_btn_stop", "hv_show_ui", "hv_igems", "hv_float" }) do
        pcall(setOnValue, al, function(a1, a2, a3)
            if a2 == al then handleVal(al, a3)
            elseif a1 == al then handleVal(al, a2)
            else handleVal(al, a1) end
        end)
    end
end
if applyHook then pcall(applyHook) end

addLog("`2Boren Auto Harvest v" .. HV.VERSION .. " siap!")
return HV
