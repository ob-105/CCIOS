-- CCIOS installed-app discovery.
-- Scans /ccios/apps/<id>/manifest.json so the Start menu (and, later,
-- the app store) can list what's actually installed without anything
-- else having to hardcode app paths.

local appsModule = {}

function appsModule.discover(root)
    root = root or "/ccios/apps"
    local result = {}
    if not fs.isDir(root) then
        return result
    end

    for _, name in ipairs(fs.list(root)) do
        local dir = root .. "/" .. name
        local manifestPath = dir .. "/manifest.json"
        if fs.isDir(dir) and fs.exists(manifestPath) then
            local file = fs.open(manifestPath, "r")
            local body = file.readAll()
            file.close()

            local manifest = textutils.unserialiseJSON(body)
            if manifest and manifest.entry then
                local window = manifest.window or {}
                table.insert(result, {
                    id = manifest.id or name,
                    name = manifest.name or name,
                    entry = dir .. "/" .. manifest.entry,
                    width = window.width or 30,
                    height = window.height or 12,
                })
            end
        end
    end

    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

return appsModule
