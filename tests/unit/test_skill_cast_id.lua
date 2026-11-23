-- 第 09 课。从项目根目录运行 lua tests/unit/test_skill_cast_id.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 0, {}
local skynet = {now = function() return ticks end}
package.loaded["skynet"] = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
local pids = require "protocol.pids"
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body)
        assert(pids[name], "缺少协议 ID " .. name)
        return {name = name, body = body}
    end,
}

local Scene = require "scene.scene"
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
require "world.client_handler"

-- 在真实场景命令返回时留存场景侧的结果，再把结果交回 world 走正常组包流程。
local observed
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then
        local uid, req = ...
        observed = {uid = uid, request = req, result = result}
    end
    return true, result, reason
end

-- 空白地图只放本次需要的目标，使范围施法恰好打到两只怪物。
local mapId = 4
local scene = Scene.new({ID = mapId, StartPos = {{0, 0, 0}}})
scene:LoadGrid(nil)
scenes.scenes[mapId] = scene
local hero = loader.LoadPlayer(901, "cast-id")
local observer = loader.LoadPlayer(902, "observer")
local replies, hpUpdates = {}, {}
function hero:SendPackage(packet)
    if packet.name == "Scene.RespCastSkill" then table.insert(replies, packet.body) end
end
function observer:SendPackage(packet)
    if packet.name == "Scene.UnitHp" then table.insert(hpUpdates, packet.body) end
end
players:AddPlayer(hero.uid, hero)
players:AddPlayer(observer.uid, observer)
handlers["Scene.ReqEnter"](hero, {sceneId = mapId})
handlers["Scene.ReqEnter"](observer, {sceneId = mapId})
local unit = assert(scene:GetUnit(hero.uid))
local target = assert(scene:AddMonster(1002, unit.x, unit.z))
assert(target.hp == 42)

-- 用客户端同一组字段发送请求。额外塞入的 ID 不应进入 world 转发的内部请求。
local function cast(skillId, targetUid)
    observed, replies, hpUpdates = nil, {}, {}
    handlers["Scene.ReqCastSkill"](hero, {skillId = skillId, targetUid = targetUid, castId = -99})
    assert(observed and observed.uid == hero.uid and observed.request.skillId == skillId)
    assert(observed.request.targetUid == targetUid and observed.request.castId == nil)
    local result = observed.result
    assert(#replies == 1 and replies[1].code == result.code and replies[1].targetUid == targetUid)
    assert(replies[1].castId == nil and replies[1].cast == nil, "施法标识应留在服务端")
    for _, hit in ipairs(replies[1].hits) do assert(hit.castId == nil) end
    local hits = result.hits or {}
    assert(#hpUpdates == #hits, "旁观者应为每个命中收到一条血量广播，拒绝施法时应为零条")
    for i, body in ipairs(hpUpdates) do
        local hit = hits[i]
        assert(body.uid == hit.uid and body.hp == hit.hp and body.maxHp == hit.maxHp)
        assert(body.castId == nil and body.cast == nil)
    end
    return result
end

-- 同一次成功受理的发起者、技能、原始目标及所有命中必须能用同一个 ID 对回去。
local function checkRecord(result, casterUid, skillId, effectId, targetUid)
    assert(math.type(result.castId) == "integer" and result.castId > 0,
        "施法已经成功，但场景结果缺少正整数 castId")
    local record = assert(result.cast, "场景结果缺少本次施法记录")
    assert(record.castId == result.castId and record.casterUid == casterUid)
    assert(record.skillId == skillId and record.skillLevel == 1 and record.effectId == effectId)
    assert(record.targetUid == targetUid and record.startedAt == ticks / 100)
    for _, hit in ipairs(result.hits) do
        assert(hit.castId == record.castId, "命中没有关联到自己的施法")
    end
    return record
end

local first = cast(1, target.uid)
assert(first.code == 0 and #first.hits == 1 and first.hits[1].damage == 10 and target.hp == 32)
local before = checkRecord(first, hero.uid, 1, 1, target.uid)
local SkillComponent = require "scene.skill_component"
local skills = assert(unit:GetComponent(SkillComponent))
assert(skills.lastCast == before)

local denied = cast(1, target.uid)
assert(denied.code == 4 and denied.cast == nil and denied.castId == nil and target.hp == 32)
assert(skills.lastCast == before, "冷却失败覆盖了上一次成功施法")

ticks = 100
local second = cast(1, target.uid)
assert(second.code == 0 and #second.hits == 1 and second.hits[1].damage == 10 and target.hp == 22)
local after = checkRecord(second, hero.uid, 1, 1, target.uid)
assert(after ~= before and skills.lastCast == after)
assert(after.castId == before.castId + 1, "中间只有一次冷却拒绝，不应消耗施法编号")
assert(first.castId == before.castId and first.hits[1].castId == before.castId and before.startedAt == 0)
print(("同一玩家普攻：第一次 ID=%d，冷却拒绝，第二次 ID=%d，目标剩 22 HP")
    :format(before.castId, after.castId))

-- 玩家与怪物在同一时刻各有独立的最近记录。怪物转出的血量事件也应带来源 ID。
local events = {}
assert(target:TryCastSkills(scene, unit, ticks / 100, events))
local monsterSkills = assert(target:GetComponent(SkillComponent))
local monsterCast = assert(monsterSkills.lastCast)
assert(monsterSkills ~= skills and monsterCast.castId > after.castId and skills.lastCast == after)
assert(monsterCast.casterUid == target.uid and monsterCast.skillId == 1000100201)
assert(monsterCast.targetUid == hero.uid and monsterCast.startedAt == after.startedAt)
assert(#events == 1 and events[1].kind == "hp" and events[1].uid == hero.uid)
assert(events[1].castId == monsterCast.castId and unit.hp == 990)

-- 复活会在同一 UID 下重建单位和组件，后续施法不能重用旧记录的编号。
unit.dead, unit.hp = true, 0
handlers["Scene.ReqRevive"](hero, {})
local rebuilt = assert(scene:GetUnit(hero.uid))
local rebuiltSkills = assert(rebuilt:GetComponent(SkillComponent))
assert(rebuilt ~= unit and rebuiltSkills ~= skills and rebuiltSkills.lastCast == nil)
local third = cast(1, target.uid)
assert(third.code == 0 and target.hp == 12)
local revivedCast = checkRecord(third, hero.uid, 1, 1, target.uid)
assert(revivedCast.castId > monsterCast.castId and rebuiltSkills.lastCast == revivedCast)

-- 一次怒爆命中两只怪，两条命中共用本次施法 ID，原始目标仍是客户端指定的那只。
scene:Leave(target.uid)
local primary = assert(scene:AddMonster(1005, rebuilt.x, rebuilt.z))
local neighbor = assert(scene:AddMonster(1005, rebuilt.x, rebuilt.z))
assert(hero:LearnSkill(2))
local splash = cast(2, primary.uid)
assert(splash.code == 0 and #splash.hits == 2)
assert(splash.hits[1].uid == primary.uid and splash.hits[2].uid == neighbor.uid)
local splashCast = checkRecord(splash, hero.uid, 2, 2, primary.uid)
assert(splashCast.castId > revivedCast.castId and rebuiltSkills.lastCast == splashCast)

-- 怒爆和伏击共用 2 秒组冷却。冷却结束后，同一时刻分别用 11 和 12 SP 释放一级伏击。
assert(hero:LearnSkill(500012))
ticks = ticks + 200
local hpBeforeAmbush = primary.hp
assert(hpBeforeAmbush > 0 and not primary.dead)
rebuilt.sp = 11
local noSp = cast(500012, primary.uid)
assert(noSp.code == 8 and noSp.castId == nil and noSp.cast == nil)
assert(rebuiltSkills.lastCast == splashCast and primary.hp == hpBeforeAmbush and rebuilt.sp == 11)
rebuilt.sp = 12
local ambush = cast(500012, primary.uid)
assert(ambush.code == 0 and #ambush.hits == 1 and primary.hp < hpBeforeAmbush and rebuilt.sp == 0)
local ambushCast = checkRecord(ambush, hero.uid, 500012, 50001201, primary.uid)
assert(ambushCast.castId == splashCast.castId + 1 and rebuiltSkills.lastCast == ambushCast)
print("OK skill cast IDs")
