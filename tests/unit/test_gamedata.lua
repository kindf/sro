-- 课程裁剪后的配置表冒烟测试。
-- 运行：lua tests/unit/test_gamedata.lua
package.path = "F:/RO/sro/?.lua;" .. package.path

local files = require "gamedata.generated.allconfigfiles"

local function get(name)
    return require("gamedata.generated." .. name)
end

local function has(name)
    for _, file in ipairs(files) do
        if file == name then
            return true
        end
    end
    return false
end

local function check(cond, msg)
    if not cond then error("FAIL: " .. msg, 2) end
end

check(#files >= 1, "table count " .. #files)

local sceneTable = get("tbscenetable")
check(sceneTable[1].ID == 1, "scene id")
check(sceneTable[1].SceneType == 2, "scene type")
check(sceneTable[1].SceneCfgFile == "RO_Ximen", "scene cfg")
check(type(sceneTable[1].StartPos) == "table", "scene startpos")

local rowCount = 0
for _ in pairs(sceneTable) do
    rowCount = rowCount + 1
end
check(rowCount == 585, "scene rows " .. rowCount)

-- 课程推进后加回来的表，存在才校验，避免测试随裁剪失效
if has("tbentitytable") then
    local entityTable = get("tbentitytable")
    check(entityTable[1].Id == 1, "entity id")
end

if has("tbglobaltable") then
    local globalTable = get("tbglobaltable")
    check(globalTable["105ActivitiesNum"] ~= nil, "global key")
end

print(string.format("OK tables=%d scene=%d", #files, rowCount))
