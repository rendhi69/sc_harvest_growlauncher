-- ============================================================================
-- BOREN STORE - DEDICATED FEATURE MANIFEST (HARVEST)
-- File: imgui_hub/manifest.lua
-- Repo: https://github.com/rendhi69/sc_harvest_growlauncher.git
-- ============================================================================

return {
    schema = "boren_gl_manifest_v1",
    core = {
        { key = "conn", path = "imgui_hub/conn_guard.lua", required = false },
    },
    features = {
        { id = "harvest", label = "Harvest", order = 15, path = "imgui_hub/mod_harvest.lua" },
    },
}
