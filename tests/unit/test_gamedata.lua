-- tests/unit/test_gamedata.lua
-- 用 LuaJIT 跑：
--   F:\RO\clientproj\Luajit64\luajit64.exe F:\RO\sro\tests\unit\test_gamedata.lua

package.path = "F:/RO/sro/?.lua;" .. package.path

local files = require "gamedata.generated.allconfigfiles"

-- 按文件名加载一张表。
local function get(name)
    return require("gamedata.generated." .. name)
end

local function check(cond, msg)
    if not cond then error("FAIL: " .. msg, 2) end
end

check(#files == 398, "table count " .. #files)

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

local entityTable = get("tbentitytable")
check(entityTable[1].Id == 1, "entity id")

local globalTable = get("tbglobaltable")
check(globalTable["105ActivitiesNum"] ~= nil, "global key")
check(globalTable["105ActivitiesNum"].Value == "1", "global value")

local bonusTable = get("tbserverbasebonustable")
check(bonusTable[1] ~= nil and bonusTable[1].ServerLevel ~= nil, "ordinal key")

print(string.format("OK tables=%d scene=585 entity=4294 global=1385 bonus=842", #files))
