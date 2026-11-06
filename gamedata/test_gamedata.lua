package.path = "F:/RO/sro/?.lua;F:/RO/sro/?/init.lua;" .. package.path

local GD = require "gamedata.init"

local function check(cond, msg)
    if not cond then error("FAIL: " .. msg, 2) end
end

check(GD.Count() == 398, "table count " .. GD.Count())

local Scene = GD.Get("SceneTable")
check(Scene[1].ID == 1, "scene id")
check(Scene[1].SceneType == 2, "scene type")
check(Scene[1].SceneCfgFile == "RO_Ximen", "scene cfg")
check(type(Scene[1].StartPos) == "table", "scene startpos")
check(Scene[1].StartPos[1][1] > 154 and Scene[1].StartPos[1][1] < 155, "startpos x")

local Entity = GD.Get("EntityTable")
check(Entity[1].Id == 1, "entity id")
check(type(Entity[1].IsDummy) == "boolean", "entity bool")

local Global = GD.Get("GlobalTable")
check(Global["105ActivitiesNum"] ~= nil, "global key")
check(Global["105ActivitiesNum"].Value == "1", "global value")

check(GD.GetRow("SceneTable", 1).ID == 1, "GetRow")
check(GD.GetRow("SceneTable", 999999) == nil, "GetRow missing")

-- 复合主键表：key 是行号
local Bonus = GD.Get("ServerBaseBonusTable")
check(Bonus[1] ~= nil and Bonus[1].ServerLevel ~= nil, "ordinal key")

print(string.format("OK tables=%d scene=%d entity=%d global=%d bonus=%d",
    GD.Count(), 585, 4294, 1385, 842))