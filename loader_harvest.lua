-- ============================================================================
-- LOADER BOREN STORE - AUTO HARVEST PRO (COMPACT DIALOG)
-- File: loader_harvest.lua
-- ============================================================================
-- Memuat auto_harvest.lua (Compact Dialog version) langsung dari GitHub.
-- Fallback ke penyimpanan file lokal perangkat jika offline / fetch gagal.
-- Commands in-game: /hv  /harvest  /autoharvest  /boren  /menu
-- ============================================================================

local BASE_URL    = "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/"
local TARGET_FILE = "auto_harvest.lua"
local CDN_URL     = "https://cdn.jsdelivr.net/gh/rendhi69/sc_harvest_growlauncher@main/auto_harvest.lua"
local SCRIPT_TAG  = "[BOREN HARVEST]"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function logMsg(msg)
    if LogToConsole  then pcall(LogToConsole,  SCRIPT_TAG .. " " .. tostring(msg)) end
    if printConsole  then pcall(printConsole,  SCRIPT_TAG .. " " .. tostring(msg)) end
    if print         then pcall(print,         SCRIPT_TAG .. " " .. tostring(msg)) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local function makeTag()
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then return tostring(math.floor(tonumber(ms))) end
    end
    if os and os.time then
        local ok, t = pcall(os.time)
        if ok and tonumber(t) then return tostring(t) end
    end
    if os and os.clock then
        local ok, c = pcall(os.clock)
        if ok and tonumber(c) then return tostring(math.floor(tonumber(c) * 1000)) end
    end
    return tostring(math.random(100000, 999999))
end

local function tryFetch(url)
    if not fetch then return nil end
    local ok, res = pcall(fetch, url)
    if ok and type(res) == "string" and #res > 100
       and not res:match("^404")
       and not res:match("^<!DOCTYPE")
       and not res:match("^Not Found")
    then
        return res
    end
    return nil
end

local function tryReadFile(path)
    local ok, f = pcall(io.open, path, "r")
    if ok and f then
        local txt = f:read("*a"); f:close()
        if txt and #txt > 100 then return txt end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Step 1: Fetch dari GitHub (raw) + CDN fallback
-- ---------------------------------------------------------------------------
logMsg("`9Menghubungkan ke GitHub untuk memuat Auto Harvest Pro (Dialog)...")
notifyUser("Memuat Boren Auto Harvest Pro...")

local code = nil

-- GitHub raw (dengan cache-bust)
local rawUrl = BASE_URL .. TARGET_FILE .. "?v=" .. makeTag()
code = tryFetch(rawUrl)
if code then
    logMsg("`2Berhasil fetch dari GitHub raw!")
end

-- CDN fallback
if not code then
    logMsg("`eGitHub raw gagal, coba CDN jsDelivr...")
    code = tryFetch(CDN_URL .. "?v=" .. makeTag())
    if code then logMsg("`2Berhasil fetch dari CDN!") end
end

-- ---------------------------------------------------------------------------
-- Step 2: Fallback ke file lokal (Android path + Windows path)
-- ---------------------------------------------------------------------------
if not code then
    logMsg("`eFetch gagal, mencari file lokal...")
    local localPaths = {
        -- Android (Growlauncher ScriptLua folders)
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_harvest.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_harvest.lua",
        "/storage/emulated/0/Download/auto_harvest.lua",
        -- Relatif ke working dir script (Windows / Android sama)
        "script/dialog/harvest/auto_harvest.lua",
        "script/script code/harvest/auto_harvest.lua",
        "script/script code/auto_harvest.lua",
        "script/script done dont edit/sc harvest/auto_harvest.lua",
        "auto_harvest.lua",
    }
    for _, path in ipairs(localPaths) do
        code = tryReadFile(path)
        if code then
            logMsg("`aFile lokal ditemukan: " .. path)
            break
        end
    end
end

-- ---------------------------------------------------------------------------
-- Step 3: Kompilasi & Eksekusi
-- ---------------------------------------------------------------------------
if not code or code == "" then
    logMsg("`4GAGAL memuat Auto Harvest Pro! Periksa koneksi atau file lokal.")
    notifyUser("Gagal memuat Auto Harvest Pro!")
    return
end

local loaderFn = loadstring or load
if not loaderFn then
    logMsg("`4loadstring / load tidak tersedia di environment ini!")
    notifyUser("Error: loadstring tidak tersedia!")
    return
end

local chunk, compErr = loaderFn(code, "auto_harvest")
if not chunk then
    logMsg("`4Error kompilasi: " .. tostring(compErr))
    notifyUser("Error kompilasi Auto Harvest Pro!")
    return
end

local okRun, runRet = pcall(chunk)
if not okRun then
    logMsg("`4Error eksekusi: " .. tostring(runRet))
    notifyUser("Error eksekusi Auto Harvest Pro!")
    return
end

-- ---------------------------------------------------------------------------
-- Step 4: Konfirmasi sukses
-- ---------------------------------------------------------------------------
logMsg("`2Auto Harvest Pro (Compact Dialog) berhasil dimuat!")
logMsg("`wKetik `c/hv `watau `c/harvest `wdi chat game untuk membuka menu.")
notifyUser("Boren Auto Harvest Pro Siap! (/hv)")
