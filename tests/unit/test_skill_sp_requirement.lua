-- 第 15 课：在 SRO 根目录运行 lua tests/unit/test_skill_sp_requirement.lua。
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

-- 替换服务传输，保留实际的 world、scene 命令、配置读取和广播。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    return true, result, reason
end

local arena = Scene.new({ID = 4, StartPos = {{0, 0, 0}}})
arena:LoadGrid(nil)
scenes.scenes[4] = arena
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

local hero, observer = enter(1501), enter(1502)
local caster = assert(arena:GetUnit(hero.uid))
local book = assert(caster:GetComponent(SkillComponent))
local target = assert(arena:AddMonster(1005, 1, 0))
assert(hero:LearnSkill(2) and hero:LearnSkill(610206) and hero:LearnSkill(210205, 8))

-- 每次给定施法前 SP，等过技能与组冷却，单独观察本次需求的边界。
local function cast(label, skillId, currentSp, expectedCost)
    ticks = ticks + 1000
    caster.sp = currentSp
    hero.packets, observer.packets = {}, {}
    local hp, last = target.hp, book.lastCast
    local cd, group = caster.skillCooldown[skillId], caster.skillGroupReadyAtMs[1]
    handlers["Scene.ReqCastSkill"](hero, {skillId = skillId, targetUid = target.uid})
    local reply = assert(hero.packets[1], label .. " 缺少施法回复")
    local body = reply.body
    local expected = currentSp >= expectedCost and 0 or 8
    assert(reply.name == "Scene.RespCastSkill" and body.targetUid == target.uid)
    assert(body.code == expected, ("%s：SP=%d，需求=%d，应返回 %d，实际 %s")
        :format(label, currentSp, expectedCost, expected, tostring(body.code)))
    if expected == 8 then
        assert(caster.sp == currentSp and hp == target.hp and #body.hits == 0, label)
        assert(book.lastCast == last and caster.skillCooldown[skillId] == cd, label)
        assert(caster.skillGroupReadyAtMs[1] == group and #hero.packets == 1 and #observer.packets == 0, label)
        return
    end
    assert(caster.sp == currentSp - expectedCost and caster.skillCooldown[skillId] == ticks / 100, label)
    assert(caster.skillGroupReadyAtMs[1] > ticks * 10 and book.lastCast.skillId == skillId, label)
    assert(not last or book.lastCast.castId == last.castId + 1, label)
    assert(#body.hits == 1 and body.hits[1].uid == target.uid and body.hits[1].damage > 0, label)
    assert(target.hp == hp - body.hits[1].damage and body.hits[1].hp == target.hp and not target.dead, label)
    local hpPackets = 0
    for _, packet in ipairs(observer.packets) do
        if packet.name == "Scene.UnitHp" then
            assert(packet.body.uid == target.uid and packet.body.hp == target.hp, label)
            hpPackets = hpPackets + 1
        end
    end
    assert(hpPackets == 1, label)
end

cast("怒爆刚好够", 2, 20, 20)
cast("怒爆少一点", 2, 19, 20)
cast("无 Buff 的回旋之刃", 610206, 9, 10)
cast("无 Buff 的回旋之刃", 610206, 10, 10)

-- 从普通服务入口加真实 Buff，以其 SkillUuid 检查费用修正只影响指定技能。
local axeBuff = 410218001
assert(hero:ApplyBuff(axeBuff))
cast("回旋之刃减半", 610206, 5, 5)
cast("回旋之刃减半仍少一点", 610206, 4, 5)
cast("回旋之刃的 Buff 不减少怒爆消耗", 2, 19, 20)
assert(hero:ApplyBuff(axeBuff))
cast("刷新同一 Buff 后只减半一次", 610206, 4, 5)
ticks = caster.buffs[axeBuff].expireAt * 100
arena:UpdateBuffs(ticks / 100, {})
assert(not caster.buffs[axeBuff])
cast("Buff 到期恢复原门槛", 610206, 5, 10)
cast("Buff 到期按原价结算", 610206, 10, 10)

-- 螺旋击刺要求长枪：先实际穿戴类型 4，再施放已学到八级的技能。
local spear = 8000003
local slot = assert(hero:AddItem(spear, 1))[1].slot
handlers["Scene.ReqEquipItem"](hero, {slot = slot})
assert(hero.equipment[1] == spear and hero:GetEquipDef(spear).WeaponId == 4)
assert(hero:ApplyBuff(411004001))
-- float32 中 60 × (1 - 6000 / 10000) 略小于 24；C++ 转整数得到 23。
cast("八级螺旋击刺单精度截断", 210205, 23, 23)
cast("八级螺旋击刺少一点", 210205, 22, 23)
print("OK skill SP requirement")
