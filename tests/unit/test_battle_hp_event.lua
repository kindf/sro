-- 第 16A 课。在项目根目录运行 lua tests/unit/test_battle_hp_event.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 0, {}
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
local skillConfig = require "common.skill_config"
require "world.client_handler"

function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    return true, result, reason
end

local arena = Scene.new({ID = 4, StartPos = {{0, 0, 0}}})
arena:LoadGrid(nil)
scenes.scenes[4] = arena
local function enter(id)
    local role = loader.LoadPlayer(id, tostring(id))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

local hero, observer = enter(1611), enter(1612)
local caster = assert(arena:GetUnit(hero.uid))
local ally = assert(arena:GetUnit(observer.uid))
local a = assert(arena:AddMonster(1005, 1, 0))
local b = assert(arena:AddMonster(1005, 2, 0))
assert(hero:LearnSkill(7) and hero:LearnSkill(10))
assert(arena:SetAttr(caster.uid, {maxSp = 1000}, 0))
caster.sp = caster.maxSp

-- 每次请求都验证 world 回包及旁观者的最终 HP，包括成功但伤害为零的祝福。
local function cast(id, target, point, code, expectedHits)
    hero.packets, observer.packets = {}, {}
    ticks = ticks + 6000
    handlers["Scene.ReqCastSkill"](hero, {skillId = id, targetUid = target.uid, castPoint = point})
    local reply = assert(hero.packets[1], "缺少施法回复")
    assert(reply.name == "Scene.RespCastSkill" and reply.body.code == code, "施法返回码错误")
    assert(#reply.body.hits == #expectedHits, "命中目标数错误")
    local pending = {}
    for _, unit in ipairs(expectedHits) do pending[unit.uid] = unit end
    for _, packet in ipairs(observer.packets) do
        if packet.name == "Scene.UnitHp" then
            local body = packet.body
            local unit = assert(pending[body.uid], "多播或错播 UnitHp")
            assert(body.hp == unit.hp and body.maxHp == unit.maxHp, "应广播目标的最终血量")
            pending[body.uid] = nil
        end
    end
    assert(next(pending) == nil, "有命中目标缺少 UnitHp")
    return reply.body
end

local kind = "kActionHpChange"
local owner, previousHp, counts = {}, {}, {}
local pendingUnit, sceneCount = nil, 0
-- 只从公开订阅入口旁听。回调内立即读取 HP 和 AI 的上次受击记录，以辨别转发次序。
local function watchMonster(unit)
    previousHp[unit.uid], counts[unit.uid] = unit.hp, 0
    assert(unit.battleEvents, "怪物缺少 battleEvents，请先完成第 16A 课的挂载步骤")
    unit.battleEvents:Subscribe(kind, owner, function(event)
        assert(not pendingUnit, "上一段伤害还未到达场景监听器")
        assert(event.type == kind and event.entityUid == unit.uid, "受击消息送到了错误的单位")
        assert(event.firerUid == hero.uid and event.mercenaryUid == 0, "伤害来源错误")
        assert(event.hpChange < 0 and unit.hp - previousHp[unit.uid] == event.hpChange,
            "每段应在写入 HP 后同步通知实际差值")
        if unit == a then
            assert(unit.hp == 0 and not unit.dead, "致死段通知时 HP 应已归零，死亡标记应在通知返回后设置")
        end
        local hit = assert(unit.lastBeHit, "单位动态监听器运行时 AI 尚未记录受击")
        assert(hit.firerUid == event.firerUid and hit.hpChange == event.hpChange, "AI 的受击内容错误")
        previousHp[unit.uid] = unit.hp
        counts[unit.uid] = counts[unit.uid] + 1
        pendingUnit = {uid = unit.uid, delta = event.hpChange}
    end)
end
watchMonster(a)
watchMonster(b)
assert(arena.battleEvents, "场景缺少 battleEvents")
arena.battleEvents:Subscribe(kind, owner, function(event)
    assert(pendingUnit and pendingUnit.uid == event.entityUid and pendingUnit.delta == event.hpChange,
        "每段事件应先经过受击单位，再到场景动态监听器")
    assert(event.type == kind and event.firerUid == hero.uid and event.mercenaryUid == 0)
    pendingUnit, sceneCount = nil, sceneCount + 1
end)
local function unexpected() error("拒绝或零伤害触发了玩家的 HP 变化通知") end
ally.battleEvents:Subscribe(kind, owner, unexpected)
caster.battleEvents:Subscribe(kind, owner, unexpected)

local allyHp, initialHitA, initialHitB = ally.hp, a.lastBeHit, b.lastBeHit
cast(1, ally, nil, 1, {})
local blessing = cast(10, ally, nil, 0, {ally})
assert(blessing.damage == 0 and ally.hp == allyHp and sceneCount == 0 and not pendingUnit)
assert(a.lastBeHit == initialHitA and b.lastBeHit == initialHitB)

-- A 仅剩 1 HP；B 可吃满暴风雪全部段数。两者各有一条最终血量广播。
a.hp, previousHp[a.uid] = 1, 1
local effectId = skillConfig.GetEffectId(require("gamedata.generated.tbskilltable")[7], 1)
local segments = assert(require("gamedata.generated.tbskilleffecttable")[effectId].AttackCount[1])
assert(segments > 1, "本用例需要多段技能")
local blizzard = cast(7, a, {x = a.x, y = a.y, z = a.z}, 0, {a, b})
local damage = {}
for _, hit in ipairs(blizzard.hits) do damage[hit.uid] = hit.damage end
assert(damage[a.uid] > 1 and a.dead and a.hp == 0 and a.lastBeHit.hpChange == -1,
    "致死段须保留既有名义伤害回包，事件只报告实际扣掉的 1 HP")
assert(b.hp > 0 and damage[b.uid] == b.maxHp - b.hp)
assert(counts[a.uid] == 1 and counts[b.uid] == segments and sceneCount == 1 + segments and not pendingUnit,
    "死亡后应停止发事件，仍存活的目标应每段收到一次")

-- 撤掉两级动态监听器后再打一次。AI 静态处理和另一个场景监听器仍应收到此次普攻。
local otherOwner, remaining, oldSceneCount = {}, 0, sceneCount
local before = b.hp
arena.battleEvents:Subscribe(kind, otherOwner, function()
    error("同一 owner 重复订阅后仍调用了旧回调")
end)
arena.battleEvents:Subscribe(kind, otherOwner, function(event)
    assert(event.entityUid == b.uid and event.hpChange == b.hp - before)
    remaining = remaining + 1
end)
b.battleEvents:Unsubscribe(kind, owner)
arena.battleEvents:Unsubscribe(kind, owner)
local basic = cast(1, b, nil, 0, {b})
assert(basic.damage > 0 and b.lastBeHit.hpChange == -basic.damage and remaining == 1)
assert(counts[b.uid] == segments and sceneCount == oldSceneCount and not pendingUnit,
    "取消订阅的回调仍被调用")
print("OK battle HP event")
