-- CCIOS installer.
-- Run this on a CC:Tweaked computer or pocket computer to install
-- (or update) CCIOS:
--
--   wget run https://raw.githubusercontent.com/ob-105/CCIOS/main/install.lua
--
-- Requires the `http` API to be enabled in the CC:Tweaked config.

local REPO_RAW = "https://raw.githubusercontent.com/ob-105/CCIOS/main/"

-- source path in the repo (under src/) -> destination path on the computer
local FILES = {
    { "src/startup.lua",                 "/startup.lua" },
    { "src/ccios/kernel/wm.lua",         "/ccios/kernel/wm.lua" },
    { "src/ccios/kernel/boot.lua",       "/ccios/kernel/boot.lua" },
    { "src/ccios/apps/about/main.lua",     "/ccios/apps/about/main.lua" },
    { "src/ccios/apps/about/manifest.json","/ccios/apps/about/manifest.json" },
}

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

print("Installing CCIOS...")

local failures = 0
for _, pair in ipairs(FILES) do
    local src, dest = pair[1], pair[2]
    io.write("  " .. dest .. " ... ")
    local body, err = fetch(REPO_RAW .. src)
    if not body then
        print("FAILED (" .. tostring(err) .. ")")
        failures = failures + 1
    else
        ensureDir(dest)
        local file = fs.open(dest, "w")
        file.write(body)
        file.close()
        print("ok")
    end
end

if failures > 0 then
    printError(("CCIOS install finished with %d failure(s)."):format(failures))
else
    print("CCIOS installed. Rebooting into CCIOS...")
    os.reboot()
end
