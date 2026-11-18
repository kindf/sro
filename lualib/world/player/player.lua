local Class = require "common.class"
local Logger = require "common.logger"
local socket = require "skynet.socket"
local skynet = require "skynet"
local ProtocolHelper = require "protocol.protocol_helper"
local ConfigRepository = require "common.config_repository"

---@class Player
---@field fd number
---@field account string
---@field uid number
local Player = Class("Player")

function Player:Ctor()
    self.fd = nil
    self.account = nil
    self.uid = nil
    self.sceneId = 1
    self.maxSlot = 100
    self.items = {}
end

function Player:SendPackage(package)
    if not self.fd then
        Logger.Warning("[Player]SendPackage failed, fd is nil. uid:%s", self.uid)
        return
    end
    local ok, err = pcall(socket.write, self.fd, package)
    if not ok then
        Logger.Warning("[Player]SendPackage failed, fd:%s uid:%s err:%s", tostring(self.fd), tostring(self.uid), tostring(err))
    end
end

function Player:OnBorn(sceneId)
    return self:ChangeScene(sceneId or self.sceneId or 1)
end

function Player:ChangeScene(sceneId)
    local ok, data = skynet.call(".scene", "lua", "change_scene", self.uid, sceneId)
    if not ok or not data then
        Logger.Error("[Player]ChangeScene failed. uid:%s sceneId:%s reason:%s", tostring(self.uid), tostring(sceneId), tostring(data))
        return nil
    end

    self.sceneId = sceneId
    return data
end

function Player:ReqMove(req)
    local resp = {}
    local common, dx, dy, dz, time = req.common, req.dx, req.dy, req.dz, req.time
    if not dx or not dy or not dz or not time or not common then
        Logger.Warning("[Player]ReqMove failed, invalid move content. uid:%s, req:%s", self.uid, tostring(req))
        return
    end
    local face = common & 0xFFFF
    local moving = (common >> 30) & 1
    local sceneId = (common >> 16) & 0x3FFF
    local ret, moveContent = skynet.call(".scene", "lua", "move", self.uid, {
        dx = dx,
        dy = dy,
        dz = dz,
        time = time,
        common = common,
    })
    if not ret or not moveContent then
        Logger.Warning("[Player]ReqMove failed, move operation failed. uid:%s, reason:%s", self.uid, moveContent)
        return
    end
    resp.dx, resp.dy, resp.dz, resp.time, resp.forced, resp.common, resp.uid = moveContent.dx, moveContent.dy, moveContent.dz, moveContent.time, moveContent.forced, common, self.uid
    
    local packet = ProtocolHelper.EncodePTCPacket("Scene.RespMove", resp)
    return packet, moveContent
end

function Player:CastSkill(req)
    local ok, result = skynet.call(".scene", "lua", "cast_skill", self.uid, {
        skillId = req.skillId,
        targetUid = req.targetUid,
    })
    if not ok or not result then
        return nil
    end
    return result
end

function Player:Revive()
    local ok, result = skynet.call(".scene", "lua", "revive", self.uid)
    if not ok or not result then
        return nil
    end
    return result
end

function Player:Pickup(targetUid)
    local ok, data = skynet.call(".scene", "lua", "pickup", self.uid, targetUid)
    if not ok or not data then
        return nil
    end
    return data
end

function Player:DropItemToScene(itemId, count)
    skynet.call(".scene", "lua", "drop_item", self.uid, itemId, count)
end


function Player:GetItemDef(itemId)
    return ConfigRepository.Get("tbitemtable")[itemId]
end

function Player:AddItem(itemId, count)
    local def = self:GetItemDef(itemId)
    local overlap = def and def.Overlap or 1
    local changed = {}

    for slot = 1, self.maxSlots do
        local item = self.items[slot]
        if item and item.itemId == itemId and item.count < overlap then
            local add = math.min(overlap - item.count, count)
            item.count = item.count + add
            count = count - add
            table.insert(changed, {slot = slot, itemId = itemId, count = item.count})
            if count == 0 then
                return changed
            end
        end
    end

    for slot = 1, self.maxSlots do
        if not self.items[slot] then
            local add = math.min(overlap, count)
            self.items[slot] = {itemId = itemId, count = add}
            count = count - add
            table.insert(changed, {slot = slot, itemId = itemId, count = add})
            if count == 0 then
                return changed
            end
        end
    end
    return nil, "bag full"
end

function Player:RemoveItem(slot, count)
    local item = self.items[slot]
    if not item or count <= 0 then
        return nil
    end

    local remove = math.min(item.count, count)
    item.count = item.count - remove
    if item.count == 0 then
        self.items[slot] = nil
    end

    return item.itemId, remove
end

function Player:UseItem(slot, count)
    local item = self.items[slot]
    if not item then
        return {code = 1} -- 没有物品
    end

    local def = self:GetItemDef(item.itemId)
    if not def or not def.CanUse then
        return {code = 2} -- 不可使用
    end

    local itemId, used = self:RemoveItem(slot, count)
    return {
        code = 0,
        slot = slot,
        itemId = itemId,
        count = used,
    }
end

function Player:SendItems()
    local list = {}
    for slot, item in pairs(self.items) do
        table.insert(list, {
            slot = slot,
            itemId = item.itemId,
            count = item.count,
        })
    end
    self:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespItems", {
        items = list,
    }))
end

function Player:SendItemUpdate(changed)
    for _, item in ipairs(changed or {} ) do
        self:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.ItemUpdate", item))
    end
end

return Player