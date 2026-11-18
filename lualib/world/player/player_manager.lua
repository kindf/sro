local Class = require "common.class"
local Player = require "world.player.player"
local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"


---@class PlayerManager
---@field players table<integer, Player>
---@field playersFdMap table<integer, Player>
---@field playersAccountMap table<string, Player>
---@field playersUidMap table<integer, Player>
local PlayerManager = Class("PlayerManager")

function PlayerManager:Ctor()
    self.players = {}
    self.playersFdMap = {}
    self.playersAccountMap = {}
    self.playersUidMap = {}
end

function PlayerManager:AddPlayer(id, player)
    local existingPlayer = self.players[id]
    if existingPlayer then
        Logger.Warning("[PlayerManager]AddPlayer: Player with id %s already exists. Replacing existing player.", tostring(id))
        self:RemovePlayer(id)
    end
    self.players[id] = player
    self.playersFdMap[player.fd] = player
    self.playersAccountMap[player.account] = player
    self.playersUidMap[player.uid] = player
end

function PlayerManager:RemovePlayer(id)
    local player = self.players[id]
    if player then
        self.players[id] = nil
        self.playersFdMap[player.fd] = nil
        self.playersAccountMap[player.account] = nil
        self.playersUidMap[player.uid] = nil
    end
end

function PlayerManager:PlayerSocketClose(fd)
    local player = self.playersFdMap[fd]
    if player then
        self:RemovePlayer(player.uid)
        Logger.Warning("[PlayerManager]PlayerSocketClose: fd:%s, uid:%s", tostring(fd), tostring(player.uid))
    end
end

function PlayerManager:PlayerSocketError(fd)
    local player = self.playersFdMap[fd]
    if player then
        self:RemovePlayer(player.uid)
        Logger.Warning("[PlayerManager]PlayerSocketError: fd:%s, uid:%s", tostring(fd), tostring(player.uid))
    end
end

---@return Player
function PlayerManager:GetPlayerByFd(fd)
    return self.playersFdMap[fd]
end

function PlayerManager:Broadcast(packet, exceptUids)
    for uid, player in pairs(self.playersUidMap) do
        if not exceptUids or not exceptUids[uid] then
            player:SendPackage(packet)
        end
    end
end

function PlayerManager:SendUidsPacket(uids, packet)
    for _, uid in pairs(uids) do
        self:SendUidPacket(uid, packet)
    end
end

function PlayerManager:SendUidPacket(uid, packet)
    local player = self.playersUidMap[uid]
    if player then
        player:SendPackage(packet)
    end
end

---@param player Player
function PlayerManager:ApplySceneChange(player, data, sceneId, sendResp)
    if not data or data.same then
        return
    end

    local pm = self

    -- 旧邻居看到 Leave
    if data.oldUnit then
        local leave = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {
            uid = player.uid,
        })
        for _, u in ipairs(data.oldOthers or {}) do
            pm:SendUidPacket(u.uid, leave)
        end
    end

    -- 自己看到新邻居
    for _, u in ipairs(data.newOthers or {}) do
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", u))
    end

    -- 新邻居看到自己
    local enter = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", data.newUnit)
    for _, u in ipairs(data.newOthers or {}) do
        pm:SendUidPacket(u.uid, enter)
    end

    -- 只有显式切场景才回 RespEnter
    if sendResp then
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespEnter", {
            sceneId = sceneId,
            x = data.newUnit.x,
            y = data.newUnit.y,
            z = data.newUnit.z,
        }))
    end
end

-- 按场景结算顺序广播，移动单位的快照仅发给刚进入其视野的玩家。
function PlayerManager:OnSceneEvents(events)
    for _, e in ipairs(events) do
        if e.kind == "move" then
            local m = e.result
            local packet = ProtocolHelper.EncodePTCPacket("Scene.RespMove", {
                common = 0,
                time = m.time,
                dx = m.dx,
                dy = m.dy,
                dz = m.dz,
                uid = e.uid,
            })
            self:SendUidsPacket(m.receivers, packet)

            if e.unit then
                local enter = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", e.unit)
                for _, neighbor in ipairs(m.enters) do
                    self:SendUidPacket(neighbor.uid, enter)
                end
            end

            local packet2 = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {uid = e.uid})
            for _, uid in ipairs(m.leaves or {}) do
                self:SendUidPacket(uid, packet2)
            end
        elseif e.kind == "hp" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitHp", {
                uid = e.uid,
                hp = e.hp,
                maxHp = e.maxHp
            })
            self:SendUidsPacket(e.receivers, packet)
        elseif e.kind == "dead" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitDead", {
                uid = e.uid,
            })
            self:SendUidsPacket(e.receivers, packet)
        elseif e.kind == "leave" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {uid = e.uid})
            self:SendUidsPacket(e.receivers, packet)
        elseif e.kind == "enter" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", e.unit)
            self:SendUidsPacket(e.receivers, packet)
        elseif e.kind == "buff" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitBuff", {
                uid = e.uid,
                buffId = e.buffId,
                duration = e.duration,
            })
            self:SendUidsPacket(e.receivers, packet)
        elseif e.kind == "attr" then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitAttr", {
                uid = e.uid, atk = e.atk, def = e.def,
                maxHp = e.maxHp, hp = e.hp,
                maxSp = e.maxSp, sp = e.sp,
            })
            self:SendUidsPacket(e.receivers, packet)
        end
    end
end

---@type PlayerManager
local GPlayerManager
function PlayerManager.GetInstance()
    if not GPlayerManager then
        GPlayerManager = PlayerManager.new()
    end
    return GPlayerManager
end

return PlayerManager
