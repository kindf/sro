-- 第 07 课。从项目根目录运行 lua tests/unit/test_equipped_basic_attack.lua。
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
local combatAttributes = require "tests.support.combat_attributes"
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body)
        assert(pids[name], "协议没有注册消息 ID " .. name)
        return {name = name, body = body}
    end,
}

local loader = require "world.player.player_loader"
local players = require("world.player.player_manager").GetInstance()
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
require "world.client_handler"

-- 将 world 的场景调用送到真实命令处理器，保留 Skynet 调用的返回值形式。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    return true, assert(commands[command], command)(...)
end

-- 走角色装载路径并截取发送给该角色的包，技能 1 由出生配置授予。
local function connect(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet)
        table.insert(self.packets, packet)
    end
    players:AddPlayer(role.uid, role)
    return role
end

-- 校验一次请求或广播只有一个指定消息，再取其内容。
local function singlePacket(role, name)
    local body
    for _, packet in ipairs(role.packets) do
        if packet.name == name then
            assert(not body, "重复收到 " .. name)
            body = packet.body
        end
    end
    return assert(body, "没有收到 " .. name)
end

-- 从注册的客户端请求入口发起动作，只核对该次动作产生的回复。
local function request(role, action, body)
    role.packets = {}
    local name = "Scene.Req" .. action
    local handler = assert(handlers[name], "world 缺少协议处理器 " .. name)
    handler(role, body)
    return singlePacket(role, "Scene.Resp" .. action)
end

local hero, observer = connect(701), connect(702)

-- 两个角色正常请求同一地图，旁观者留在攻击者视野内。
local function enterMap(id)
    for _, role in ipairs({hero, observer}) do
        assert(request(role, "Enter", {sceneId = id}).sceneId == id)
    end
    assert(scenes:GetPlayerScene(hero.uid) == scenes:GetPlayerScene(observer.uid))
end

-- 每轮等待普攻 CD，用同模板满血目标核对攻击输入、回包、实际扣血与旁观者广播。
local function swing(label, monsterId, expectedAtk, expectedHp)
    ticks = ticks + 100
    local scene = scenes:GetPlayerScene(hero.uid)
    local unit = scene:GetUnit(hero.uid)
    local target = assert(scene:AddMonster(monsterId, unit.x, unit.z))
    assert(target.hp == expectedAtk + expectedHp and combatAttributes(target).def == 0, "目标初始 HP 或防御不符")
    observer.packets = {}
    local reply = request(hero, "CastSkill", {skillId = 1, targetUid = target.uid})
    assert(reply.code == 0 and #reply.hits == 1, label .. " 普攻失败，结果码 " .. tostring(reply.code))
    local hit = reply.hits[1]
    local actualAtk = hero:CalcAttr().atk
    local sceneAtk = combatAttributes(unit).atk
    assert(actualAtk == expectedAtk and sceneAtk == expectedAtk and hit.damage == expectedAtk,
        ("%s：预期攻击 %d，world 攻击 %d，场景攻击 %d，命中伤害 %d")
            :format(label, expectedAtk, actualAtk, sceneAtk, hit.damage))
    assert(reply.damage == hit.damage and reply.targetUid == target.uid and hit.uid == target.uid)
    assert(target.hp == expectedHp and reply.targetHp == expectedHp and hit.hp == expectedHp)
    local hp = singlePacket(observer, "Scene.UnitHp")
    assert(hp.uid == target.uid and hp.hp == expectedHp and hp.maxHp == target.maxHp)
    scene:Leave(target.uid)
    print(("%s  ATK=%d damage=%d HP=%d"):format(label, sceneAtk, hit.damage, target.hp))
end

-- 通过真实背包和协议穿脱，核对角色记录里的装备、背包归还及回复。
local function equip(itemId, equipSlot)
    local changed = assert(hero:AddItem(itemId, 1))
    local bagSlot = changed[1].slot
    local reply = request(hero, "EquipItem", {slot = bagSlot})
    assert(reply.code == 0 and reply.equipSlot == equipSlot and reply.itemId == itemId)
    assert(hero.equipment[equipSlot] == itemId and not hero.items[bagSlot])
end

local function unequip(itemId, equipSlot)
    local reply = request(hero, "UnequipItem", {equipSlot = equipSlot})
    assert(reply.code == 0 and reply.equipSlot == equipSlot and reply.itemId == itemId)
    assert(not hero.equipment[equipSlot])
    for _, item in pairs(hero.items) do
        if item.itemId == itemId and item.count == 1 then return end
    end
    error("卸装成功后背包未收到装备 " .. itemId)
end

local sword, wrist = 20000000, 10326003
enterMap(1)
swing("空手", 1001, 10, 11)
equip(sword, 1)
swing("只穿初心者短剑", 1001, 20, 1)
enterMap(4)
swing("带剑切到地图 4", 1001, 20, 1)
enterMap(1)
swing("带剑返回地图 1", 1001, 20, 1)

local map = scenes:GetPlayerScene(hero.uid)
local beforeRevive = map:GetUnit(hero.uid)
beforeRevive.dead, beforeRevive.hp = true, 0
assert(request(hero, "Revive", {}).uid == hero.uid)
assert(map:GetUnit(hero.uid) ~= beforeRevive, "复活应重建场景单位")
swing("带剑复活", 1001, 20, 1)

equip(wrist, 6)
swing("短剑和铁护腕", 1002, 35, 7)
unequip(sword, 1)
swing("只留铁护腕", 1002, 25, 17)
unequip(wrist, 6)
swing("全部卸下", 1001, 10, 11)
print("OK equipped basic attack")
