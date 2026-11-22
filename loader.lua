-- ============================================================================
-- LOADER BOREN STORE - AUTO HARVEST PRO
-- ============================================================================
-- Mengambil dan menjalankan auto_harvest.lua langsung dari GitHub:
-- https://github.com/rendhi69/sc_harvest_growlauncher.git
-- ============================================================================

local RAW_URL = "https://raw.githubusercontent.com/rendhi69/sc_harvest_growlauncher/main/auto_harvest.lua"
local cacheBuster = tostring(math.floor((os and os.time and os.time()) or (os and os.clock and os.clock() * 1000) or math.random(100000, 999999)))
local fetchUrl = RAW_URL .. "?v=" .. cacheBuster

local function notifyUser(msg)
    if sendNotification then pcall(sendNotification, tostring(msg))
    elseif growtopia and growtopia.notify then pcall(growtopia.notify, tostring(msg)) end
end

local function logMsg(msg)
    if LogToConsole then pcall(LogToConsole, "`e[Harvest] `0" .. tostring(msg)) end
end

logMsg("Menghubungkan ke GitHub dan memuat auto_harvest.lua...")
notifyUser("Memuat BOREN STORE - AUTO HARVEST PRO...")

local content = nil
if fetch then
    local okFetch, res = pcall(fetch, fetchUrl)
    if okFetch and type(res) == "string" and res ~= "" and not res:match("^404") and not res:match("^<!DOCTYPE") then
        content = res
    end
end

if not content or content == "" then
    local localCandidates = {
        "/storage/emulated/0/Android/media/launcher.powerkuy.growlauncher/ScriptLua/auto_harvest.lua",
        "/storage/emulated/0/Android/data/launcher.powerkuy.growlauncher/files/ScriptLua/auto_harvest.lua",
        "/storage/emulated/0/Download/auto_harvest.lua",
        "script/auto_harvest.lua",
        "auto_harvest.lua",
    }
    for _, p in ipairs(localCandidates) do
        local okF, fh = pcall(io.open, p, "r")
        if okF and fh then
            local text = fh:read("*a")
            fh:close()
            if text and text ~= "" then
                content = text
                logMsg("Memuat skrip dari file lokal: " .. p)
                break
            end
        end
    end
end

if not content or content == "" then
    logMsg("`4Gagal memuat auto_harvest.lua! Periksa koneksi internet / file lokal.")
    notifyUser("Gagal load skrip!")
    return
end

local loaderFn = loadstring or load
local chunk, err = loaderFn(content)
if not chunk then
    logMsg("`4Error kompilasi script: " .. tostring(err))
    notifyUser("Syntax error!")
    return
end

logMsg("`2BOREN STORE - AUTO HARVEST PRO berhasil dimuat!")
notifyUser("Harvest Siap Digunakan!")
chunk()
