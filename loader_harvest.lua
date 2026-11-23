-- ============================================================================
-- LOADER BOREN STORE - AUTO HARVEST PRO (NATIVE UI GROWLAUNCHER)
-- File: loader_harvest.lua
-- ============================================================================
-- Skrip ini memuat antarmuka Native Menu bawaan Growlauncher (Auto Harvest Pro).
-- Mengambil file skrip terbaru langsung dari GitHub (sc_harvest_growlauncher)
-- atau fallback ke penyimpanan file lokal perangkat jika offline.
-- ============================================================================

local BASE_URL = "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/"
local TARGET_FILE = "auto_harvest.lua"

local function makeTag()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tostring(math.floor(tonumber(ms))) end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and tonumber(t) then return tostring(math.floor(tonumber(t))) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return tostring(math.floor(tonumber(c) * 1000)) end
    end
    return tostring(math.random(100000, 999999))
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[BOREN HARVEST PRO] `w" .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

logMsg("`9Menghubungkan ke GitHub dan memuat Auto Harvest Pro (Native UI)...")
notifyUser("Memuat Auto Harvest Pro (Native UI)...")

local code = nil
if fetch then
    local fetchUrl = BASE_URL .. TARGET_FILE .. "?v=" .. makeTag()
    local okF, res = pcall(fetch, fetchUrl)
    if okF and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        code = res
    end
end

if not code or code == "" then
    local localRoots = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/",
        "/storage/emulated/0/Download/",
        "script/script done dont edit/sc harvest/",
        "script/script code/harvest/",
        "script/",
        "",
    }
    for _, root in ipairs(localRoots) do
        local okO, f = pcall(io.open, root .. TARGET_FILE, "r")
        if okO and f then
            local txt = f:read("*a")
            f:close()
            if txt and txt ~= "" then code = txt; break end
        end
    end
end

if not code or code == "" then
    logMsg("`4Gagal memuat Auto Harvest Pro! Periksa koneksi internet / file lokal.")
    notifyUser("Gagal memuat Auto Harvest Pro!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(code)
if not chunk then
    logMsg("`4Error kompilasi script: " .. tostring(err))
    notifyUser("Error kompilasi Auto Harvest Pro!")
    return
end

local okRun, ret = pcall(chunk)
if not okRun then
    logMsg("`4Error menjalankan script: " .. tostring(ret))
    notifyUser("Error eksekusi Auto Harvest Pro!")
    return
end

logMsg("`2Auto Harvest Pro (Native UI) Berhasil Dimuat ke Growlauncher!")
notifyUser("Auto Harvest Pro Siap!")
