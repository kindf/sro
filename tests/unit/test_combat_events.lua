-- 在项目根目录运行：lua tests/unit/test_combat_events.lua
-- 使用真实技能与怪物配置，在 socket 边界记录 world 发给各玩家的包。
package.path = "./lualib/?.lua;" .. package.path
package.loaded["skynet"] = {now = function() return 0 end}
package.loaded["skynet.socket"] = {}
package.loaded["pb"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}

local pids = require "protocol.pids"
local handlers = {}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, msg)
        assert(pids[name], "未定义协议 " .. name)
        return {name = name, msg = msg}
    end,
}

local Scene = require "scene.scene"
local PlayerManager = require "world.player.player_manager"
local world = require("world.world_service_handler").CMD
require "world.client_handler"

local scene = Scene.new({ID = 1, StartPos = {{0,0,0}}})
scene:LoadGrid(nil)
local manager = PlayerManager.GetInstance()

-- 创建在线收件人，保留该玩家真实收到的包及顺序。
local function connect(uid)
    local player = {uid = uid, fd = uid, account = tostring(uid), packets = {}}
    function player:SendPackage(packet)
        table.insert(self.packets, packet)
    end
    manager:AddPlayer(uid, player)
    scene:Enter(uid, 0, 0, 0)
    return player
end

-- 从指定收件箱取出一种协议的所有消息。
local function received(player, name)
    local found = {}
    for _, packet in ipairs(player.packets) do
        if packet.name == name then table.insert(found, packet.msg) end
    end
    return found
end

local player, observer, newcomer = connect(1), connect(2), connect(3)
local first = assert(scene:AddMonster(1001, 0, 0))
local second = assert(scene:AddMonster(1002, 0, 0))
local now = 0
function player:CastSkill(req)
    return scene:CastSkill(self.uid, req, now)
end
local cast = handlers["Scene.ReqCastSkill"]
cast(player, {skillId = 1, targetUid = first.uid})
local responses = received(player, "Scene.RespCastSkill")
assert(#responses == 1 and responses[1].code == 0 and #responses[1].hits == 1)
assert(responses[1].damage > 0 and first.hp == first.maxHp - responses[1].damage)
assert(first.hatred[player.uid].threat == responses[1].damage)
assert(#received(observer, "Scene.UnitHp") == 1)
cast(player, {skillId = 1, targetUid = first.uid})
assert(received(player, "Scene.RespCastSkill")[2].code == 4)
assert(#received(observer, "Scene.UnitHp") == 1)

now = 1
cast(player, {skillId = 2, targetUid = first.uid})
responses = received(player, "Scene.RespCastSkill")
assert(#responses == 3 and #responses[3].hits == 2 and responses[3].hits[1].uid == first.uid)
assert(first.dead and second.dead and scene:GetUnit(player.uid).sp == 80)
assert(#received(player, "Scene.UnitDead") == 2 and #received(observer, "Scene.UnitDead") == 2)
local rewards = received(player, "Scene.RespExp")
assert(#rewards == 1 and rewards[1].totalJobExp == 77 and rewards[1].totalBaseExp == 95)

-- 怪物也使用相同结算，world 将结果按场景返回的可见范围广播。
local monster = assert(scene:AddMonster(1001, 0, 0))
local aiEvents = {}
local target = scene:GetUnit(observer.uid)
assert(monster:TryCastSkills(scene, target, now, aiEvents))
assert(#aiEvents >= 1 and aiEvents[1].kind == "hp" and target.hp < target.maxHp)
world.scene_events(aiEvents)
local hp = received(observer, "Scene.UnitHp")
assert(hp[#hp].uid == target.uid and hp[#hp].hp == target.hp)

-- 真实配置技能 3 附加 Buff，到期后的移除和重算应按次序送给同一批邻居。
cast(player, {skillId = 3, targetUid = player.uid})
local active = scene:GetUnit(player.uid).buffs[10201]
assert(active and active.expireAt > now)
local expire = {}
scene:UpdateBuffs(active.expireAt, expire)
world.scene_events(expire)
local buffs = received(observer, "Scene.UnitBuff")
assert(#buffs >= 2 and buffs[#buffs].buffId == 10201 and buffs[#buffs].duration == 0)
assert(observer.packets[#observer.packets].name == "Scene.UnitAttr")

-- 同一批事件覆盖持续可见、新进入、离开视野，以及 Buff 到期的有序广播。
player.packets, observer.packets, newcomer.packets = {}, {}, {}
world.scene_events({
    {kind = "move", uid = first.uid, unit = first:Pack(), result = {
        dx = 1, dy = 0, dz = 1, time = 0.3, receivers = {1}, enters = {{uid = 3}}, leaves = {2}}},
    {kind = "buff", uid = 1, buffId = 10201, duration = 0, receivers = {1}},
    {kind = "attr", uid = 1, atk = 10, def = 0, hp = 10, maxHp = 10, sp = 80, maxSp = 100, receivers = {1}},
    {kind = "leave", uid = second.uid, receivers = {2}},
})
assert(#player.packets == 3 and player.packets[1].name == "Scene.RespMove")
assert(player.packets[2].name == "Scene.UnitBuff" and player.packets[3].msg.sp == 80)
assert(#observer.packets == 2 and observer.packets[1].msg.uid == first.uid)
assert(observer.packets[2].name == "Scene.UnitLeave" and observer.packets[2].msg.uid == second.uid)
assert(#newcomer.packets == 1 and newcomer.packets[1].name == "Scene.UnitEnter")
assert(newcomer.packets[1].msg.entityId == 1001 and newcomer.packets[1].msg.uid == first.uid)
print("OK combat and scene events")
