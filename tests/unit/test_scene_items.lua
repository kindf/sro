-- 使用真实背包、场景命令及协议处理器，检查道具在背包与地面之间的转移。
package.path = "./lualib/?.lua;" .. package.path
local handlers, messages = {}, {}
local skynet = {now = function() return 0 end}
package.loaded["skynet"] = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Player = require "world.player.player"
local players = require("world.player.player_manager").GetInstance()
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
require "world.client_handler"

-- 模拟真实的场景分发返回值，保留实际实现中的路由、距离和掉落处理。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    return true, assert(commands[command])(...)
end

-- 在相同出生点注册玩家，并记录实际发给各个客户端的消息。
local function addPlayer(uid)
    local p = Player.new()
    p.uid, p.fd, p.account = uid, uid, tostring(uid)
    p.SendPackage = function(_, packet)
        table.insert(messages, {uid = uid, name = packet.name, body = packet.body})
    end
    players:AddPlayer(uid, p)
    assert(scenes:ChangeScene(uid, 4))
    return p
end

-- 返回指定客户端收到的某种协议；同一结果重复回包时立即失败。
local function singlePacket(uid, name)
    local found
    for _, message in ipairs(messages) do
        if message.uid == uid and message.name == name then
            assert(not found, "duplicate " .. name)
            found = message.body
        end
    end
    return found
end

local p, neighbor = addPlayer(1), addPlayer(2)
local scene = scenes:GetPlayerScene(p.uid)
local pos = scene:GetUnit(p.uid)
local itemId = 3055701
local overlap = p:GetItemDef(itemId).Overlap
assert(overlap > 2 and p:GetItemDef(101).Overlap == 0)
p.maxSlot = 2
assert(p:AddItem(itemId, overlap - 1))
assert(p:AddItem(101, 1))
local drop = scene:DropItem(itemId, 2, pos.x, pos.z)
handlers["Scene.ReqPickup"](p, {targetUid = drop.uid})
assert(singlePacket(1, "Scene.RespPickup").code == 3)
assert(not singlePacket(2, "Scene.UnitLeave"))
assert(p.items[1].count == overlap - 1 and scene:GetUnit(drop.uid) == drop)
assert(not p:AddItem(101, 1) and p.items[2].count == 1)

-- 丢弃超过格子数量时只丢出现有数量，新掉落对两个玩家可见。
messages = {}
handlers["Scene.ReqDropItem"](p, {slot = 2, count = 5})
local response = singlePacket(1, "Scene.RespDropItem")
assert(response.code == 0 and response.itemId == 101 and response.count == 1 and not p.items[2])
local newDrop = singlePacket(2, "Scene.UnitEnter")
assert(newDrop.uid == singlePacket(1, "Scene.UnitEnter").uid and scene:GetUnit(newDrop.uid))

-- 空出格子后，同一原始掉落可以完整拾取，一部分叠加、一部分进入新格子。
messages = {}
handlers["Scene.ReqPickup"](p, {targetUid = drop.uid})
assert(singlePacket(1, "Scene.RespPickup").code == 0 and not scene:GetUnit(drop.uid))
assert(singlePacket(2, "Scene.UnitLeave").uid == drop.uid)
assert(p.items[1].count == overlap and p.items[2].count == 1)

-- 第二人无法重复拾取；场景不存在时丢弃失败，背包数量不变。
messages = {}
handlers["Scene.ReqPickup"](neighbor, {targetUid = drop.uid})
assert(singlePacket(2, "Scene.RespPickup").code == 1 and next(neighbor.items) == nil)
scenes:LeaveScene(p.uid)
handlers["Scene.ReqDropItem"](p, {slot = 2, count = 1})
assert(singlePacket(1, "Scene.RespDropItem").code ~= 0 and p.items[2].count == 1)
print("OK scene_items")
