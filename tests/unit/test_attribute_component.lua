-- 第 08 课。在项目根目录运行 lua tests/unit/test_attribute_component.lua。
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
        assert(pids[name], "未注册的协议 " .. name)
        return {name = name, body = body}
    end,
}

local loader = require "world.player.player_loader"
local players = require("world.player.player_manager").GetInstance()
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
require "world.client_handler"

-- 用进程内调用送达相同的场景命令，保留 world 与 scene 的返回值形式。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    return true, assert(commands[command], command)(...)
end

-- 经角色装载和进图请求建立在线玩家，保存服务端发给他的包。
local function connect(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

-- 取出本次动作唯一的一份指定消息，缺失或重复都提示具体协议。
local function singlePacket(role, name)
    local body
    for _, packet in ipairs(role.packets) do
        if packet.name == name then
            assert(not body, "重复收到 " .. name)
            body = packet.body
        end
    end
    return assert(body, "未收到 " .. name)
end

local hero, observer = connect(801), connect(802)
local scene = assert(scenes:GetPlayerScene(hero.uid))
assert(scenes:GetPlayerScene(observer.uid) == scene)
local attacker = assert(scene:GetUnit(hero.uid))
local a = assert(scene:AddMonster(5023, attacker.x, attacker.z))
local b = assert(scene:AddMonster(5023, attacker.x, attacker.z))
assert(a.uid ~= b.uid and a.hp == 44 and b.hp == 44)

-- 在同一场景推进一秒，核对实际命中、怪物身上的 HP 和旁观者的 HP 广播。
local function swing(label, target, damage, hp)
    ticks = ticks + 100
    hero.packets, observer.packets = {}, {}
    handlers["Scene.ReqCastSkill"](hero, {skillId = 1, targetUid = target.uid})
    local reply = singlePacket(hero, "Scene.RespCastSkill")
    assert(reply.code == 0 and reply.targetUid == target.uid and #reply.hits == 1)
    local hit = reply.hits[1]
    assert(hit.uid == target.uid and hit.damage == damage and reply.damage == damage,
        ("%s：预期伤害 %d，实际 %d"):format(label, damage, hit.damage))
    assert(target.hp == hp and reply.targetHp == hp and hit.hp == hp, label .. " 命中后 HP 错误")
    local packet = singlePacket(observer, "Scene.UnitHp")
    assert(packet.uid == target.uid and packet.hp == hp and packet.maxHp == 44)
    print(("%s：伤害 %d，目标剩 %d HP"):format(label, damage, hp))
end

-- 先从可见行为核对模板的 BaseDEF=1，旧服务端在这一击会打出 10。
swing("A 初始防御 1", a, 9, 35)
assert(b.hp == 44, "首次命中 A 时改变了 B 的 HP")

local AttributeComponent = require "scene.attribute_component"
local heroAttr = assert(attacker:GetComponent(AttributeComponent))
local aAttr, bAttr = assert(a:GetComponent(AttributeComponent)), assert(b:GetComponent(AttributeComponent))
assert(heroAttr.owner == attacker and aAttr.owner == a and bAttr.owner == b)
assert(heroAttr ~= aAttr and heroAttr ~= bAttr and aAttr ~= bAttr, "实体共用了同一属性组件")
assert(heroAttr.atk == 10 and heroAttr.def == 0 and aAttr.def == 1 and bAttr.def == 1)
local drop = scene:DropItem(101, 1, attacker.x, attacker.z)
assert(drop:GetComponent(AttributeComponent) == nil, "地面掉落不参与战斗属性结算")

-- 基础防御变更与 Buff 重算各自只作用于指定 UID，每一击沿用该目标实际剩余 HP。
assert(scene:SetAttr(b.uid, {def = 6}, ticks / 100).def == 6)
assert(aAttr.def == 1 and bAttr.def == 6)
swing("B 调到防御 6", b, 4, 40)
local buffId = 102301  -- 其效果 4008401 给平减防御属性 30 加 2。
assert(scene:ApplyBuff(a.uid, buffId, ticks / 100).attr.def == 3)
assert(aAttr.def == 3 and bAttr.def == 6)
swing("A 的 Buff 把防御加到 3", a, 7, 28)
swing("再打防御仍为 6 的 B", b, 4, 36)
ticks = math.ceil(a.buffs[buffId].expireAt * 100)
local expired = {}
scene:UpdateBuffs(ticks / 100, expired)
observer.packets = {}
players:OnSceneEvents(expired)
local restored = singlePacket(observer, "Scene.UnitAttr")
assert(restored.uid == a.uid and restored.def == 1 and not a.buffs[buffId])
assert(aAttr.def == 1 and bAttr.def == 6, "A 的 Buff 到期应只恢复 A 的防御")
assert(scene:SetAttr(a.uid, {def = 12}, ticks / 100).def == 12)
swing("A 的防御超过攻击", a, 1, 27)
assert(b.hp == 36 and bAttr.def == 6)

-- 反向受击。玩家从 world 同步防御，怪物从模板选技，world 分发场景事件。
hero.baseDef = 4
assert(hero:SyncAttr().def == 4 and heroAttr.def == 4 and attacker.hp == 1000)
local enemy = assert(scene:AddMonster(1002, attacker.x, attacker.z))
local events = {}
hero.packets, observer.packets = {}, {}
assert(enemy:TryCastSkills(scene, attacker, ticks / 100, events))
players:OnSceneEvents(events)
assert(attacker.hp == 994 and aAttr.def == 12 and bAttr.def == 6)
local hpPacket = singlePacket(observer, "Scene.UnitHp")
assert(hpPacket.uid == hero.uid and hpPacket.hp == 994 and hpPacket.maxHp == 1000)
print("怪物攻击防御 4 的玩家：伤害 6，玩家剩 994 HP")

-- 同一时刻模板技能仍在冷却。AI 锁定这名玩家，回退攻击也应扣除目标防御。
local now = ticks / 100
enemy:AddHatred(hero.uid, 1, now)
local fallback = {}
observer.packets = {}
enemy:UpdateAI(scene, now, fallback)
assert(#fallback == 1 and fallback[1].kind == "hp" and fallback[1].uid == hero.uid)
assert(attacker.hp == 948 and fallback[1].hp == 948, "回退攻击应对防御 4 的玩家造成 46 点伤害")
players:OnSceneEvents(fallback)
local fallbackHp = singlePacket(observer, "Scene.UnitHp")
assert(fallbackHp.uid == hero.uid and fallbackHp.hp == 948)
print("怪物回退攻击防御 4 的玩家：伤害 46，玩家剩 948 HP")

-- 模板 8586 的攻击、最大 HP 均不同于玩家默认值。只更新防御不能重置它们。
local large = assert(scene:AddMonster(8586, attacker.x, attacker.z))
local largeAttr = assert(large:GetComponent(AttributeComponent))
assert(largeAttr.atk == 5 and largeAttr.def == 1 and large.maxHp == 1234)
local result = assert(scene:SetAttr(large.uid, {def = 6}, ticks / 100))
assert(result.atk == 5 and result.def == 6 and result.maxHp == 1234 and result.hp == 1234)
assert(largeAttr.atk == 5 and largeAttr.def == 6 and large.maxHp == 1234 and large.hp == 1234)
print("OK attribute component")
