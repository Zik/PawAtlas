-- Run from the repository root: lua5.1 tools/check.lua [addon-directory] [version-tag]
-- Checks source files or an extracted release without executing addon code.
assert(_VERSION == "Lua 5.1", "This check requires Lua 5.1")
local root, tag = arg[1] or ".", arg[2]
local runtime = { Core = true, Data = true, Libs = true, Locales = true, Media = true, UI = true }

local function read(path)
    local file, err = io.open(root .. "/" .. path, "rb")
    assert(file, err)
    local text = file:read("*a")
    file:close()
    return text:gsub("^\239\187\191", "")
end

local function safePath(path)
    assert(not path:match("^/") and not path:find(":", 1, true), "Invalid path: " .. path)
    for part in path:gmatch("[^/]+") do
        assert(part ~= ".." and part ~= ".", "Invalid path: " .. path)
    end
    return path
end

local tracked, luaCount = {}, 0
local listing = assert(io.popen("git ls-files", "r"))
for path in listing:lines() do
    path = path:gsub("\r$", "")
    tracked[path] = true
    local directory = path:match("^([^/]+)/")
    if runtime[directory] or path == "PawAtlas.toc" or path:match("^[^/]+%-LICENSE%.txt$") then
        local source = read(safePath(path))
        if path:match("%.lua$") then
            assert(loadstring(source, "@" .. path))
            luaCount = luaCount + 1
        end
    end
end
listing:close()
assert(tracked["PawAtlas.toc"] and luaCount > 0, "No tracked addon files; run from the repository root")

local version, icon, entries = nil, nil, 0
for line in (read("PawAtlas.toc") .. "\n"):gmatch("([^\n]*)\n") do
    line = line:match("^%s*(.-)%s*$")
    local value = line:match("^## Version:%s*(.+)$")
    if value then
        assert(not version, "Duplicate TOC version")
        version = value
    end
    icon = line:match("^## IconTexture:%s*(.+)$") or icon
    if line ~= "" and not line:match("^#") then
        local path = safePath(line:gsub("\\", "/"))
        assert(tracked[path], "Untracked TOC entry: " .. path)
        read(path)
        entries = entries + 1
    end
end
assert(entries > 0, "Empty TOC")
local major, minor, patch = (version or ""):match("^(%d+)%.(%d+)%.(%d+)$")
assert(major and not major:match("^0%d") and not minor:match("^0%d") and not patch:match("^0%d"),
    "TOC version must be MAJOR.MINOR.PATCH without leading zeroes")
local prerelease = false
if tag and tag ~= "v" .. version then
    local base, suffix = tag:match("^v(%d+%.%d+%.%d+)(.+)$")
    local channel, number = (suffix or ""):match("^[.-](%a+)(.*)$")
    assert(base == version and (channel == "alpha" or channel == "beta" or channel == "rc")
        and (number == "" or number:match("^%.[1-9]%d*$")),
        "Tag must match v" .. version .. " with optional alpha, beta or rc suffix")
    prerelease = true
end
assert(icon, "Missing TOC icon")
local iconPath = icon:gsub("\\", "/"):match("^Interface/AddOns/PawAtlas/(.+)$")
assert(iconPath and tracked[iconPath], "Invalid or untracked TOC icon")
read(safePath(iconPath))

if root == "." then
    local output = os.getenv("GITHUB_OUTPUT")
    if output then
        local file = assert(io.open(output, "a"))
        file:write("version=", version, "\n")
        file:write("prerelease=", tostring(prerelease), "\n")
        file:close()
    end
end
print(("Lua 5.1: %d files passed; TOC, resources and version %s passed (%s)"):format(luaCount, version, root))
