-- ============================================================================
-- LOADER BOREN STORE - AUTO HARVEST PRO v2.1.0 (COMPACT DIALOG)
-- File: loader_harvest.lua
-- Repo: https://github.com/rendhi69/sc_harvest_growlauncher
-- ============================================================================
-- 100% In-Game Growtopia Dialog murni (/hv /harvest /boren).
-- ONLINE-FIRST: Selalu mengunduh auto_harvest.lua terbaru dari GitHub / CDN.
-- Otomatis menimpa (sync) file lokal di HP / PC agar cache selalu update.
-- Multi-fallback (GitHub Raw, jsDelivr CDN, Fastly) bebas blokir ISP.
-- ============================================================================

local SCRIPT_TAG = "`5[BOREN HARVEST LOADER]`w"

local function logMsg(msg)
    local s = SCRIPT_TAG .. " " .. tostring(msg)
    if LogToConsole then pcall(LogToConsole, s) end
    if printConsole then pcall(printConsole, s) end
    if print        then pcall(print,        s) end
end

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local function makeAntiCacheTag()
    local t = ""
    if getTime then
        local ok, ms = pcall(getTime)
        if ok and tonumber(ms) then t = tostring(math.floor(tonumber(ms))) end
    end
    if t == "" and os and os.time then
        local ok, s = pcall(os.time)
        if ok and tonumber(s) then t = tostring(math.floor(tonumber(s))) end
    end
    if t == "" then
        t = tostring(math.random(100000, 999999))
    end
    return t
end

-- ============================================================================
-- DAFTAR LOKASI FILE LOKAL PERANGKAT (ANDROID & WINDOWS)
-- ============================================================================
local LOCAL_PATHS = {
    "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_harvest.lua",
    "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_harvest.lua",
    "/storage/emulated/0/Download/auto_harvest.lua",
    "script/dialog/harvest/auto_harvest.lua",
    "script/script code/harvest/auto_harvest.lua",
    "script/script code/auto_harvest.lua",
    "auto_harvest.lua",
}

-- ============================================================================
-- FAST CHAT INTERCEPTOR DI TINGKAT LOADER (/hv, /harvest, /autoharvest)
-- Mencegah munculnya 'Unknown command' di chat game sejak awal
-- ============================================================================
local function loaderFastPacketHook(arg1, arg2)
    local pStr = (type(arg2) == "string") and arg2 or ((type(arg1) == "string") and arg1 or nil)
    if not pStr or type(pStr) ~= "string" then return false end

    local lowerP = pStr:lower()
    if lowerP:find("/hv", 1, true) or lowerP:find("/harvest", 1, true) or lowerP:find("/autoharvest", 1, true) or lowerP:find("/boren", 1, true) or lowerP:find("/menu", 1, true) then
        if lowerP:find("action|input", 1, true) or lowerP:find("text|/", 1, true) or lowerP:find("action|chat", 1, true) or lowerP:sub(1, 1) == "/" then
            local cmd = lowerP:match("|text|(/[a-z0-9_]+)") or lowerP:match("text|(/[a-z0-9_]+)") or lowerP:match("(/[a-z0-9_]+)")
            if cmd == "/hv" or cmd == "/harvest" or cmd == "/autoharvest" or cmd == "/boren" or cmd == "/menu" then
                local openFn = _G.showHarvestMainDialog or (DLG and DLG.showHarvestMainDialog)
                if openFn then
                    pcall(openFn)
                    logMsg("`2Menu Dialog dibuka via chat: `e" .. tostring(cmd))
                else
                    notifyUser("Boren Auto Harvest sedang dimuat... ketik /hv lagi sebentar!")
                end
                return true
            end
        end
    end

    if pStr:find("action|dialog_return", 1, true) then
        local dn = pStr:match("dialog_name|([^\r\n]+)")
        if dn and dn:sub(1, 3) == "hv_" then
            local handler = _G.handleHarvestDialogReturn or handleHarvestDialogReturn
            if handler then
                pcall(handler, pStr)
                return true
            end
        end
    end

    return false
end

if addHook then
    pcall(addHook, loaderFastPacketHook, "onsendpacket")
    pcall(addHook, "onSendPacket", "boren_hv_loader_hook", loaderFastPacketHook)
    if applyHook then pcall(applyHook) end
end

-- ============================================================================
-- 1. ONLINE-FIRST: FETCH DARI GITHUB RAW / JSDELIVR CDN RESMI
-- ============================================================================
local ONLINE_URLS = {
    -- 1. Direct Commit SHA (Instant bypass semua cache)
    "https://cdn.jsdelivr.net/gh/rendhi69/sc_harvest_growlauncher@f4c1e6597347f5eeeef267144c3fbb456b9866ce/auto_harvest.lua",
    "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/f4c1e6597347f5eeeef267144c3fbb456b9866ce/auto_harvest.lua",
    -- 2. Latest main branch
    "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/auto_harvest.lua",
    "https://cdn.jsdelivr.net/gh/rendhi69/sc_harvest_growlauncher@main/auto_harvest.lua",
    "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/refs/heads/main/auto_harvest.lua",
    "https://fastly.jsdelivr.net/gh/rendhi69/sc_harvest_growlauncher@main/auto_harvest.lua",
    "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/auto_harvest.lua?v=" .. makeAntiCacheTag(),
}

logMsg("`9Menghubungkan ke server untuk mengunduh Boren Auto Harvest Pro terbaru...")
notifyUser("Memuat Boren Auto Harvest Pro v2.1.0...")

local fetcher = fetch or (http and http.get) or (client and client.fetch) or (growtopia and growtopia.fetch)
local content = nil
local fetchedSource = ""

if fetcher then
    for _, u in ipairs(ONLINE_URLS) do
        local okFetch, res = pcall(fetcher, u)
        if okFetch and res then
            local body = nil
            if type(res) == "string" and #res > 1000 then
                body = res
            elseif type(res) == "table" and res.body and #res.body > 1000 then
                body = res.body
            end
            if body and not body:match("^404") and not body:match("^<!DOCTYPE") and not body:match("^Not Found") then
                content = body
                fetchedSource = u
                break
            end
        end
    end
end

-- ============================================================================
-- EKSEKUSI SUMBER ONLINE (JIKA BERHASIL)
-- ============================================================================
if content and #content > 1000 then
    logMsg("`2Berhasil mengunduh Auto Harvest Pro v2.1.0 (" .. tostring(#content) .. " bytes)!")

    -- Sinkronisasi otomatis ke file penyimpanan lokal agar cache HP tidak usang
    for _, p in ipairs(LOCAL_PATHS) do
        if p and p ~= "" then
            local okW, fW = pcall(io.open, p, "w")
            if okW and fW then
                pcall(function() fW:write(content) end)
                pcall(function() fW:close() end)
            end
        end
    end

    local loaderFn = loadstring or load
    local chunk, compErr = loaderFn(content, "auto_harvest")
    if chunk then
        local okRun, runErr = pcall(chunk)
        if okRun then
            logMsg("`2[ONLINE v2.1.0] Boren Auto Harvest Pro Berhasil Aktif!")
            notifyUser("`2[ONLINE v2.1.0] Boren Auto Harvest Siap! (/hv)")
            if _G.showHarvestMainDialog then pcall(_G.showHarvestMainDialog) end
            return
        else
            logMsg("`4Error runtime skrip online: " .. tostring(runErr))
        end
    else
        logMsg("`4Error kompilasi skrip online: " .. tostring(compErr))
    end
end

-- ============================================================================
-- 2. CADANGAN: JIKA ONLINE GAGAL / OFFLINE, FALLBACK KE FILE LOKAL
-- ============================================================================
logMsg("`4[PERINGATAN] Server online tidak merespon! Memuat cadangan file lokal...")
for _, p in ipairs(LOCAL_PATHS) do
    if p and p ~= "" then
        local okOpen, f = pcall(io.open, p, "r")
        if okOpen and f then
            local txt = f:read("*a")
            f:close()
            if txt and #txt > 1000 then
                logMsg("`6Memuat skrip cadangan lokal: " .. tostring(p))
                local loaderFn = loadstring or load
                local chunk, compErr = loaderFn(txt, "auto_harvest")
                if chunk then
                    local okRun, runErr = pcall(chunk)
                    if okRun then
                        logMsg("`3[LOKAL] Boren Auto Harvest Cadangan Lokal Berhasil Aktif!")
                        notifyUser("`4[LOKAL] File lokal dimuat (Bukan online terbaru)!")
                        if _G.showHarvestMainDialog then pcall(_G.showHarvestMainDialog) end
                        return
                    else
                        logMsg("`4Error runtime skrip lokal: " .. tostring(runErr))
                    end
                else
                    logMsg("`4Error kompilasi skrip lokal: " .. tostring(compErr))
                end
            end
        end
    end
end

logMsg("`4Gagal memuat Auto Harvest Pro dari server online maupun penyimpanan lokal!")
notifyUser("`4Gagal memuat Auto Harvest Pro!")
