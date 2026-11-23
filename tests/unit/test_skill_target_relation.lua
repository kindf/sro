-- 第 10 课。在项目根目录运行 lua tests/unit/test_skill_target_relation.lua。
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
        assert(pids[name], "未知协议 " .. name)
        return {name = name, body = body}
    end,
}

local loader = require "world.player.player_loader"
local players = require("world.player.player_manager").GetInstance()
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local SkillComponent = require "scene.skill_component"
require "world.client_handler"

-- 调用实际的场景命令，保留 world 组包前的施法记录。
local sceneResult
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then sceneResult = result end
    return true, result, reason
end

-- 两名玩家经正常装载进入地图 4，在同一位置收取施法回包和旁观广播。
local function enter(fd)
    local player = loader.LoadPlayer(fd, tostring(fd))
    player.packets = {}
    function player:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(player.uid, player)
    handlers["Scene.ReqEnter"](player, {sceneId = 4})
    return player
end

local player, friend = enter(1001), enter(1002)
local scene = assert(scenes:GetPlayerScene(player.uid))
local caster, ally = assert(scene:GetUnit(player.uid)), assert(scene:GetUnit(friend.uid))
local enemy = assert(scene:AddMonster(1002, caster.x, caster.z))
local skills = assert(caster:GetComponent(SkillComponent))
assert(player:LearnSkill(10) and caster.sp == 100 and enemy.hp == 42)

-- 清空上一次的包后发请求，同时检查服务器与客户端都返回了本次指定的目标。
local function cast(skillId, target)
    sceneResult, player.packets, friend.packets = nil, {}, {}
    handlers["Scene.ReqCastSkill"](player, {skillId = skillId, targetUid = target.uid})
    local reply
    for _, packet in ipairs(player.packets) do
        if packet.name == "Scene.RespCastSkill" then
            assert(not reply, "一次施法收到了多份回复")
            reply = packet.body
        end
    end
    assert(reply and sceneResult and reply.code == sceneResult.code)
    assert(reply.targetUid == target.uid and sceneResult.targetUid == target.uid)
    return reply
end

-- 非法目标须在冷却、耗蓝、分配标识及广播之前返回。
local function denied(label, skillId, target)
    local hp, sp, lastCast = target.hp, caster.sp, skills.lastCast
    local cooldown, groupReady = caster.skillCooldown[skillId], caster.skillGroupReadyAtMs[1]
    local reply = cast(skillId, target)
    assert(reply.code == 1, ("%s：预期目标拒绝码 1，实际 %d"):format(label, reply.code))
    assert(reply.damage == 0 and #reply.hits == 0 and target.hp == hp and caster.sp == sp, label)
    assert(sceneResult.castId == nil and skills.lastCast == lastCast, label .. " 改变了施法记录")
    assert(caster.skillCooldown[skillId] == cooldown and caster.skillGroupReadyAtMs[1] == groupReady, label)
    assert(#player.packets == 1 and #friend.packets == 0, label .. " 拒绝时仍发送了战斗广播")
end

-- 从请求、施法记录、每目标命中和旁观者的 HP 广播核对实际受理对象。
local function allowed(label, skillId, target, damage, spCost)
    local hp, sp, previous = target.hp, caster.sp, skills.lastCast
    local reply = cast(skillId, target)
    assert(reply.code == 0 and #reply.hits == 1, label .. " 应受理并命中指定目标")
    local hit = reply.hits[1]
    assert(hit.uid == target.uid and hit.damage == damage and reply.damage == damage, label)
    assert(hit.hp == hp - damage and reply.targetHp == hit.hp and target.hp == hit.hp, label)
    assert(caster.sp == sp - spCost, label .. " 消耗 SP 错误")
    local record = assert(sceneResult.cast)
    assert(record.targetUid == target.uid and record.skillId == skillId and skills.lastCast == record)
    assert(record.castId == sceneResult.hits[1].castId)
    if previous then assert(record.castId == previous.castId + 1, label .. " 之前的拒绝占用了施法号") end
    local hpPackets = 0
    for _, packet in ipairs(friend.packets) do
        if packet.name == "Scene.UnitHp" then
            hpPackets = hpPackets + 1
            assert(packet.body.uid == target.uid and packet.body.hp == target.hp, label)
        end
    end
    assert(hpPackets == 1, label .. " 应只有一次血量广播")
end

-- 所有单位都在射程内，前两次拒绝后同一时刻对敌人普攻，应立刻成功。
denied("普攻选友方", 1, ally)
denied("普攻选自己", 1, caster)
allowed("普攻选敌方", 1, enemy, 10, 0)
assert(enemy.hp == 32 and ally.hp == 1000 and caster.hp == 1000)

-- 仍在第 0 秒。祝福首次选敌应拒绝，立即改选友方就能成功；冷却结束再选自己。
denied("祝福选敌方", 10, enemy)
allowed("祝福选友方", 10, ally, 0, 20)
ticks = 100
allowed("祝福选自己", 10, caster, 0, 20)
assert(caster.sp == 60 and enemy.hp == 32)

-- 5075 的阵营 10000 按原版取余后等同玩家的 0；1147 的阵营 2 对玩家中立。
-- 两只怪物直接使用真实模板的阵营和生命值。
local friendlyMonster = assert(scene:AddMonster(5075, caster.x, caster.z))
local neutralMonster = assert(scene:AddMonster(1147, caster.x, caster.z))
assert(friendlyMonster.hp == 434 and neutralMonster.hp == 5407)
ticks = 200
denied("普攻选友方怪物", 1, friendlyMonster)
allowed("祝福选友方怪物", 10, friendlyMonster, 0, 20)
ticks = 300
denied("普攻选中立怪物", 1, neutralMonster)
allowed("祝福选中立主目标", 10, neutralMonster, 0, 20)
assert(caster.sp == 20)

-- 10011 使用独立的技能和效果记录，也配置了 TargetType=2 的锁定型主目标。
assert(player:LearnSkill(10011))
denied("另一种友方技能选敌人", 10011, enemy)
allowed("另一种友方技能选玩家", 10011, ally, 0, 0)

-- 两只模板 1002 属于同一阵营。怪物模板技能不能对同阵营出手，能反向攻击玩家。
local otherMonster = assert(scene:AddMonster(1002, enemy.x, enemy.z))
local events = {}
assert(not enemy:TryCastSkills(scene, otherMonster, ticks / 100, events))
assert(#events == 0 and otherMonster.hp == 42 and not enemy:GetComponent(SkillComponent).lastCast)
local previousHp = ally.hp
assert(enemy:TryCastSkills(scene, ally, ticks / 100, events))
assert(#events == 1 and events[1].kind == "hp" and events[1].uid == ally.uid and ally.hp < previousHp)
print("OK skill target relation")
