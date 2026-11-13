local Class = require "common.class"
local Player = require "world.player.player"
local Logger = require "common.logger"

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

---@type PlayerManager
local GPlayerManager
function PlayerManager.GetInstance()
    if not GPlayerManager then
        GPlayerManager = PlayerManager.new()
    end
    return GPlayerManager
end

return PlayerManager