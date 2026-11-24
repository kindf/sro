-- 第 14 课。在 SRO 根目录运行 lua tests/unit/test_skill_hit_height.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 1000, {}
local skynet = {now = function() return ticks end}
package.loaded.skynet = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Scene = require "scene.scene"
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
local SkillComponent = require "scene.skill_component"
require "world.client_handler"

-- 只替换服务传输。进图、施法和旁观者广播均经过原有处理函数。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    return true, result, reason
end

local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

-- pairs 的遍历顺序不固定；按 UID 排序可同时发现漏命中、误命中和重复条目。
local function uidList(uids)
    table.sort(uids)
    return "[" .. table.concat(uids, ",") .. "]"
end

-- 四个相邻格从左到右是施法者、左怪、打击中心、右怪。两怪的 XZ 距离永远都是 1 米。
-- 每次重建同样的场景，重放时只调整指定格的厘米高度。怪物坐标和血量都由 AddMonster 初始化。
local function replay(label, terrainCm, expectedIndexes, options)
    options = options or {}
    local scene = Scene.new({ID = 4, StartPos = {{0.5, terrainCm[1] / 100, 0.5}}})
    scene:LoadGrid({width = 4, height = 1, minX = 0, maxX = 4, minZ = 0, maxZ = 1,
        cell = 1, cells = terrainCm})
    scenes.scenes[4] = scene
    local hero, observer = enter(1401), enter(1402)
    local caster = assert(scene:GetUnit(hero.uid))
    assert(hero:LearnSkill(7) and scene:SetAttr(hero.uid, {maxSp = 500}, 0))
    caster.sp = 500
    assert(caster.y == terrainCm[1] / 100)

    local monsters = {
        assert(scene:AddMonster(1005, 1.5, 0.5)),
        assert(scene:AddMonster(1005, 3.5, 0.5)),
    }
    assert(monsters[1].y == terrainCm[2] / 100 and monsters[2].y == terrainCm[4] / 100)
    local point = {x = 2.5, y = options.pointY or terrainCm[3] / 100, z = 0.5}
    local req = {skillId = 7, targetUid = 0, castPoint = point}
    if options.legacy then
        local primary = assert(scene:AddMonster(1005, point.x, point.z))
        assert(primary.y == point.y)
        table.insert(monsters, primary)
        req = {skillId = 7, targetUid = primary.uid}
    end

    local beforeHp, candidates, wanted = {}, {}, {}
    for _, m in ipairs(monsters) do
        beforeHp[m.uid] = m.hp
        table.insert(candidates, m.uid)
    end
    for _, i in ipairs(expectedIndexes) do table.insert(wanted, monsters[i].uid) end
    hero.packets, observer.packets = {}, {}
    handlers["Scene.ReqCastSkill"](hero, req)
    local reply = assert(hero.packets[1], label .. " 缺少施法应答")
    assert(reply.name == "Scene.RespCastSkill" and reply.body.code == 0, label .. " 地面施法应受理")
    assert(reply.body.targetUid == req.targetUid and caster.sp == 368, label .. " 目标或 SP 错误")
    assert(caster.skillCooldown[7] == ticks / 100 and caster.skillGroupReadyAtMs[1] == ticks * 10 + 3000, label)
    local cast = assert(caster:GetComponent(SkillComponent).lastCast)
    assert(cast.castPoint.y == point.y and cast.targetUid == req.targetUid, label .. " 打击中心错误")

    local got, damage, notifications = {}, {}, {}
    for _, hit in ipairs(reply.body.hits) do
        table.insert(got, hit.uid)
        assert(hit.damage > 0 and hit.hp == scene:GetUnit(hit.uid).hp, label)
        damage[hit.uid] = hit.damage
    end
    local trace = ("%s：候选 %s → 命中 %s，应为 %s"):format(label, uidList(candidates), uidList(got), uidList(wanted))
    assert(uidList(got) == uidList(wanted), trace)
    for _, packet in ipairs(observer.packets) do
        if packet.name == "Scene.UnitHp" then
            assert(packet.body.hp == scene:GetUnit(packet.body.uid).hp, label)
            table.insert(notifications, packet.body.uid)
        end
    end
    assert(uidList(notifications) == uidList(wanted), label .. " 血量广播名单错误")
    for _, m in ipairs(monsters) do
        assert(m.hp == beforeHp[m.uid] - (damage[m.uid] or 0), label .. " 怪物血量和命中不一致")
    end
    print(trace)
end

-- 中心 Y=11、施法者 Y=8。命中以中心为准，恰好上下 6 米均会命中。
replay("正向边界", {800, 1700, 1100, 1701}, {1})
replay("负向边界", {800, 500, 1100, 499}, {1})
replay("全部超限", {800, 499, 1100, 1701}, {})
replay("旧请求以主目标为中心", {800, 1700, 1100, 499}, {1, 3}, {legacy = true})

-- 7 米目标减去略低于 1 米的协议 float。前例 float 减法舍入为 6，后例舍入为下一格。
replay("float 差值舍入到 6", {100, 700, 100, 701}, {1}, {pointY = 1 - 2^-24})
replay("float 差值舍入到 6 之后", {100, 700, 100, 701}, {}, {pointY = 1 - 5 * 2^-24})
print("OK skill hit height")
