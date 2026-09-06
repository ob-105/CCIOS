-- CCIOS updater.
-- Shared by install.lua (first install) and the in-game update flow
-- (manual "update" command, and boot.lua's optional check-on-boot).
--
-- The single source of truth for "what files make up CCIOS" is
-- manifest.json at the repo root. It's fetched fresh over HTTP every
-- time so file lists never have to be duplicated/kept in sync by hand.

local updater = {}

updater.REPO_RAW = "https://raw.githubusercontent.com/ob-105/CCIOS/main/"
updater.VERSION_FILE = "/ccios/version.json"

local function fetch(url)
    if not http then
        return nil, "http API is not enabled"
    end
    local response, err = http.get(url)
    if not response then
        return nil, err or "request failed"
    end
    local body = response.readAll()
    response.close()
    return body
end

-- Fetches and decodes manifest.json from the repo.
function updater.fetchManifest()
    local body, err = fetch(updater.REPO_RAW .. "manifest.json")
    if not body then
        return nil, err
    end
    local manifest = textutils.unserialiseJSON(body)
    if not manifest then
        return nil, "could not parse manifest.json"
    end
    return manifest
end

-- Returns the version string CCIOS believes is currently installed,
-- or nil if there's no record of one (e.g. very first install).
function updater.getInstalledVersion()
    if not fs.exists(updater.VERSION_FILE) then
        return nil
    end
    local file = fs.open(updater.VERSION_FILE, "r")
    local body = file.readAll()
    file.close()
    local data = textutils.unserialiseJSON(body)
    return data and data.version or nil
end

local function ensureDir(path)
    local dir = path:match("^(.*)/[^/]+$")
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
end

-- Downloads every file listed in `manifest` and writes it to its
-- destination path, then records the installed version. Returns
-- true, or false + an error message.
function updater.applyManifest(manifest, onProgress)
    for _, entry in ipairs(manifest.files) do
        if onProgress then
            onProgress(entry.dest)
        end
        local body, err = fetch(updater.REPO_RAW .. entry.src)
        if not body then
            return false, ("failed to fetch %s: %s"):format(entry.src, tostring(err))
        end
        ensureDir(entry.dest)
        local file = fs.open(entry.dest, "w")
        file.write(body)
        file.close()
    end

    ensureDir(updater.VERSION_FILE)
    local versionFile = fs.open(updater.VERSION_FILE, "w")
    versionFile.write(textutils.serialiseJSON({ version = manifest.version }))
    versionFile.close()

    return true
end

-- Checks the remote manifest against the installed version.
-- Returns: hasUpdate (bool), manifest (table or nil), err (string or nil)
function updater.checkForUpdate()
    local manifest, err = updater.fetchManifest()
    if not manifest then
        return false, nil, err
    end
    local installed = updater.getInstalledVersion()
    return installed ~= manifest.version, manifest, nil
end

return updater
