-- CCIOS installer.
-- Run this on a CC:Tweaked computer or pocket computer to install
-- (or reinstall) CCIOS:
--
--   wget run https://raw.githubusercontent.com/ob-105/CCIOS/main/install.lua
--
-- Requires the `http` API to be enabled in the CC:Tweaked config.
-- File list and version come from manifest.json in the repo, the same
-- one the in-game updater (/ccios/kernel/updater.lua) uses, so this
-- script doesn't hardcode its own copy of "what files make up CCIOS".

local REPO_RAW = "https://raw.githubusercontent.com/ob-105/CCIOS/main/"

if not http then
    printError("CCIOS installer requires the `http` API.")
    printError("Ask a server admin to enable it in the CC:Tweaked config.")
    return
end

local function fetch(url)
    local response, err = http.get(url)
    if not response then
        return nil, err
    end
    local body = response.readAll()
    response.close()
    return body
end

local function ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

print("Fetching manifest...")
local manifestBody, manifestErr = fetch(REPO_RAW .. "manifest.json")
if not manifestBody then
    printError("Could not fetch manifest.json: " .. tostring(manifestErr))
    return
end

local manifest = textutils.unserialiseJSON(manifestBody)
if not manifest then
    printError("Could not parse manifest.json")
    return
end

print(("Installing CCIOS %s..."):format(manifest.version))

local failures = 0
for _, entry in ipairs(manifest.files) do
    io.write("  " .. entry.dest .. " ... ")
    local body, err = fetch(REPO_RAW .. entry.src)
    if not body then
        print("FAILED (" .. tostring(err) .. ")")
        failures = failures + 1
    else
        ensureDir(entry.dest)
        local file = fs.open(entry.dest, "w")
        file.write(body)
        file.close()
        print("ok")
    end
end

if failures > 0 then
    printError(("CCIOS install finished with %d failure(s)."):format(failures))
    return
end

ensureDir("/ccios/version.json")
local versionFile = fs.open("/ccios/version.json", "w")
versionFile.write(textutils.serialiseJSON({ version = manifest.version }))
versionFile.close()

print("CCIOS installed. Rebooting into CCIOS...")
os.reboot()
