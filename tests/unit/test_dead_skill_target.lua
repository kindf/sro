-- 第 11 课。在项目根目录运行 lua tests/unit/test_dead_skill_target.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 0, {}
local skynet = {now = function() return ticks end}
package.loaded["skynet"] = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, fn) handlers[name] = fn end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local loader = require "world.player.player_loader"
local players = require("world.player.player_manager").GetInstance()
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local SkillComponent = require "scene.skill_component"
require "world.client_handler"

-- 仅替换服务传输，保留实际场景命令及 world 组包前的返回值。
local sceneResult
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then sceneResult = result end
    return true, result, reason
end

-- 从正常装载和入场入口创建玩家，分别保存每次操作收到的消息。
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

-- 按消息名取回包列表，用于核对施法回复、死亡与主动复活通知。
local function packets(role, name)
    local found = {}
    for _, packet in ipairs(role.packets) do
        if packet.name == name then table.insert(found, packet.body) end
    end
    return found
end

local priest, friend = enter(1101), enter(1102)
local scene = assert(scenes:GetPlayerScene(priest.uid))
local caster, ally = assert(scene:GetUnit(priest.uid)), assert(scene:GetUnit(friend.uid))
local skills = assert(caster:GetComponent(SkillComponent))
local enemy = assert(scene:AddMonster(1002, caster.x, caster.z))
assert(priest:LearnSkill(12) and priest:LearnSkill(10))

-- 从客户端请求入口施法，对照服务器内部结果和施法者收到的唯一一份回复。
local function cast(skillId, target)
    priest.packets, friend.packets, sceneResult = {}, {}, nil
    handlers["Scene.ReqCastSkill"](priest, {skillId = skillId, targetUid = target.uid})
    local replies = packets(priest, "Scene.RespCastSkill")
    assert(#replies == 1 and sceneResult and replies[1].code == sceneResult.code)
    assert(replies[1].targetUid == target.uid and sceneResult.targetUid == target.uid)
    return replies[1]
end

-- 拒绝必须发生在扣费、写冷却、分配施法号和广播之前。
local function denied(label, skillId, target)
    local hp, sp, last = target.hp, caster.sp, skills.lastCast
    local cooldown = caster.skillCooldown[skillId]
    local group0, group1 = caster.skillGroupReadyAtMs[0], caster.skillGroupReadyAtMs[1]
    local reply = cast(skillId, target)
    assert(reply.code == 1, ("%s：预期目标错误 1，实际 %s"):format(label, tostring(reply.code)))
    assert(#reply.hits == 0 and target.hp == hp and caster.sp == sp and skills.lastCast == last, label)
    assert(not sceneResult.castId and caster.skillCooldown[skillId] == cooldown, label)
    assert(caster.skillGroupReadyAtMs[0] == group0 and caster.skillGroupReadyAtMs[1] == group1, label)
    assert(#priest.packets == 1 and #friend.packets == 0, label .. " 仍产生战斗广播")
end

denied("复活术选活着的友方", 12, ally)

-- 两个目标都以 10 HP 进入战斗，死亡标记交给真正的伤害路径写入。
assert(scene:SetAttr(ally.uid, {maxHp = 10}, 0).hp == 10)
assert(scene:SetAttr(enemy.uid, {maxHp = 10}, 0).hp == 10)
local events = {}
assert(enemy:TryCastSkills(scene, ally, 0, events))
players:OnSceneEvents(events)
assert(ally.dead and ally.hp == 0 and #packets(friend, "Scene.UnitDead") == 1)
local attack = cast(1, enemy)
assert(attack.code == 0 and attack.damage == 10 and enemy.dead and enemy.hp == 0)
assert(sceneResult.dead and sceneResult.reward and #packets(priest, "Scene.UnitDead") == 1)
local attackId = sceneResult.castId

-- 跳过普攻冷却，在同一时刻逐个只改变技能或目标。
ticks = 100
denied("普攻选死亡敌方", 1, enemy)
denied("祝福选死亡友方", 10, ally)
denied("复活术选死亡敌方", 12, enemy)

-- 尸体只进入施法记录；受理本身不会产生一次打击、附加 Buff、死亡奖励或恢复 HP。
local function acceptCorpse(target, expectedSp, expectedId)
    local reply = cast(12, target)
    assert(reply.code == 0 and reply.damage == 0 and reply.targetHp == 0 and #reply.hits == 0)
    assert(sceneResult.cast.skillId == 12 and sceneResult.cast.targetUid == target.uid)
    assert(skills.lastCast == sceneResult.cast and sceneResult.castId == expectedId)
    assert(caster.sp == expectedSp and caster.skillCooldown[12] == ticks / 100)
    assert(scene:GetUnit(target.uid) == target and target.dead and target.hp == 0)
    assert(not sceneResult.dead and not sceneResult.reward and #(sceneResult.hits or {}) == 0)
    assert(#(sceneResult.buffs or {}) == 0 and not caster.buffs[100801] and not target.buffs[100801])
    assert(#priest.packets == 1 and #friend.packets == 0, "受理尸体时应只回复施法者，不广播效果")
end

acceptCorpse(ally, 50, attackId + 1)
assert(cast(12, ally).code == 4 and caster.sp == 50 and skills.lastCast.castId == attackId + 1)

-- 同类复活技能和“所有”目标类型沿用真实配置；怒爆原有锚点继续要求存活。
local definitions = require "gamedata.generated.tbskilltable"
local effects = require "gamedata.generated.tbskilleffecttable"
local function selects(skillId, target)
    local skill = definitions[skillId]
    local targets = scene:SelectSkillTargets(caster.uid, skill, effects[skill.EffectIDs[1]], target.uid)
    return targets ~= nil and targets[1] == target
end
assert(selects(300015, ally) and not selects(300015, caster))
assert(selects(5002, caster) and selects(5002, enemy))
assert(not selects(2, enemy))

-- 通过已有的主动复活命令重建同一 UID，此时对他再次释放技能 12 应因已存活被拒。
handlers["Scene.ReqRevive"](friend, {})
local aliveAgain = assert(scene:GetUnit(friend.uid))
assert(aliveAgain ~= ally and not aliveAgain.dead and aliveAgain.hp == aliveAgain.maxHp)
assert(aliveAgain.hp > 0 and #packets(friend, "Scene.RespRevive") == 1)
ticks = 200
denied("复活术再选同一名已复活玩家", 12, aliveAgain)

-- 模板 1147 对玩家中立。直接设置尸体夹具以单独验证非敌判定与仇恨副作用。
local neutral = assert(scene:AddMonster(1147, caster.x, caster.z))
assert(neutral.hp > 0 and not neutral.hatred[caster.uid])
neutral.hp, neutral.dead = 0, true
acceptCorpse(neutral, 0, attackId + 2)
assert(not neutral.hatred[caster.uid], "对中立尸体受理复活术不应新增仇恨")
print("OK dead skill target")
