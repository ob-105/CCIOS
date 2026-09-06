-- CCIOS manual update command.
-- Installed as /update.lua so users can just run `update` from the
-- shell (or from a future in-GUI terminal app) to check for and apply
-- CCIOS updates on demand, without waiting for the next boot check.

local ok, updater = pcall(dofile, "/ccios/kernel/updater.lua")
if not ok then
    printError("Could not load updater: " .. tostring(updater))
    return
end

print("Checking for updates...")
local hasUpdate, manifest, err = updater.checkForUpdate()

if err then
    printError("Update check failed: " .. err)
    return
end

if not hasUpdate then
    print(("CCIOS is up to date (%s)."):format(updater.getInstalledVersion() or manifest.version))
    return
end

print(("Update available: %s -> %s"):format(updater.getInstalledVersion() or "unknown", manifest.version))
io.write("Install it now? (y/n) ")
local answer = read()
if answer:lower() ~= "y" then
    print("Skipped.")
    return
end

local applyOk, applyErr = updater.applyManifest(manifest, function(dest)
    print("  " .. dest)
end)

if not applyOk then
    printError("Update failed: " .. applyErr)
    return
end

print("Updated. Rebooting...")
os.reboot()
