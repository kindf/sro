-- 在仓库根目录运行 lua tests/unit/test_scene_movement.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks = 0
package.loaded.skynet = {now = function() return ticks end, error = print}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
local Scene = require "scene.scene"
local Manager = require "scene.scene_manager"
local manager = Manager.GetInstance()
local scene = manager:GetScene(1)
local spawnDefs = require "scene.scene_spawn"
local uid = 7
local born = manager:ChangeScene(uid, 1)
assert(#born.newOthers == #spawnDefs[1], "spawn monsters must be visible on entry")
for i, def in ipairs(spawnDefs[1]) do
    local monster = scene:GetUnit(scene.spawns[i].uid)
    assert(monster.x == def.x and monster.z == def.z and not scene:IsBlocked(def.x, def.z))
    assert(monster.y == scene:GetHeight(monster.x, monster.z))
end

-- 走真实地图的一步，验证服务端坐标和回包高度一致。
local function move(map, id, x, z)
    return assert(map:Move(id, {common = 1, dx = x, dy = 0, dz = z, time = 0.1}))
end
local player = scene:GetUnit(uid)
local moved = move(scene, uid, player.x + 0.2, player.z)
assert(not moved.forced and moved.dy == scene.startPos[2] and player.y == moved.dy)
ticks = ticks + 20
local beforeWall, lastMove = player.token, player.lastMoveAt
assert(move(scene, uid, 149, 130).forced, "a single move must not cross the wall")
assert(player.token == beforeWall and player.lastMoveAt == lastMove, "blocked step must not credit movement time")

-- AI 追击、玩家离场和回出生点都走实际的场景更新流程。
local monster = scene:GetUnit(scene.spawns[1].uid)
ticks = ticks + 30
scene:Update(ticks / 100)
assert(monster.x ~= monster.spawnX or monster.z ~= monster.spawnZ, "monster must pursue")
manager:LeaveScene(uid)
for i = 1, 20 do
    ticks = ticks + 30
    scene:Update(ticks / 100)
end
assert(monster.state == "idle" and (monster.x - monster.spawnX)^2 + (monster.z - monster.spawnZ)^2 <= 0.25)
local events, oldX, oldZ = {}, monster.x, monster.z
assert(not monster:StepTo(scene, 151, 130, 0.3, events))
assert(#events == 0 and monster.x == oldX and monster.z == oldZ, "unreachable target must not move")

-- 中间的高台与缺失高度格都不可跨越，但四邻格路径可以绕行，并抵达准确的目标点。
local terrain = Scene.new({ID = 777, StartPos = {{0.5, 1, 1.5}}})
terrain:LoadGrid({
    minX = 0, maxX = 4, minZ = 0, maxZ = 3,
    width = 4, height = 3, cell = 1,
    cells = {100,100,100,100, 100,160,0,100, 100,100,100,100},
})
terrain:Enter(uid)
assert(move(terrain, uid, 3.25, 1.5).forced)
local path = assert(terrain:FindPath(0.5, 1.5, 3.25, 1.5))
local x, z = 0.5, 1.5
for _, point in ipairs(path) do
    assert(x ~= point.x or z ~= point.z, "path must omit the starting point")
    assert(terrain:CanWalk(x, z, point.x, point.z))
    x, z = point.x, point.z
end
assert(x == 3.25 and z == 1.5 and #path >= 5)
assert(not terrain:FindPath(0.5, 1.5, 3.25, 1.5, 1), "respect search budget")
terrain.grid.cells[6] = 140
local slope = move(terrain, uid, 1.5, 1.5)
assert(not slope.forced and slope.dy == 1.4, "forty-centimeter step is walkable")
assert(not terrain:FindPath(0.5, 1.5, 2.5, 1.5), "invalid height cell")
local adjacent = terrain:FindPath(0.5, 1.5, 1.5, 1.5)
assert(#adjacent == 1 and adjacent[1].x == 1.5)
local sameCell = terrain:FindPath(0.5, 1.5, 0.8, 1.5)
assert(#sameCell == 1 and sameCell[1].x == 0.8)

-- 一张地图临时报错时，其他地图仍发送事件；下一帧会重试失败的地图。
local isolated = Manager.new()
local failedTicks, healthyTicks, sent = 0, 0, {}
local logged
package.loaded.skynet.error = function(message) logged = message end
package.loaded.skynet.send = function(_, _, _, events) table.insert(sent, events[1]) end
isolated.scenes[10] = {Update = function()
    failedTicks = failedTicks + 1
    if failedTicks == 1 then error("temporary scene failure") end
    return {"recovered"}
end}
isolated.scenes[20] = {Update = function()
    healthyTicks = healthyTicks + 1
    return {"healthy"}
end}
isolated:UpdateAI(1)
assert(healthyTicks == 1 and #sent == 1 and sent[1] == "healthy")
assert(logged:find("sceneId:10", 1, true) and logged:find("temporary scene failure", 1, true))
isolated:UpdateAI(2)
assert(failedTicks == 2 and healthyTicks == 2 and #sent == 3)
print("OK scene movement: real spawns, AI, flat terrain, heights, walls and pathfinding")
