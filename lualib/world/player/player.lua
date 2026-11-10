local Class = require "common.class"
local Logger = require "common.logger"
local socket = require "skynet.socket"
local skynet = require "skynet"
local ProtocolHelper = require "protocol.protocol_helper"

---@class Player
---@field fd number
---@field account string
---@field uid number
local Player = Class("Player")

function Player:Ctor()
    self.fd = nil
    self.account = nil
    self.uid = nil
end

function Player:OnBorn()
    skynet.send(".scene", "lua", "enter", self.uid, 1, 0, 0, 0)
end

function Player:SendPackage(package)
    if not self.fd then
        Logger.Warning("[Player]SendPackage failed, fd is nil. uid:%s", self.uid)
        return
    end
    socket.write(self.fd, package)
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
        time = time
    })
    if not ret then
        Logger.Warning("[Player]ReqMove failed, move operation failed. uid:%s, reason:%s", self.uid, moveContent)
        return
    end
    if moveContent then
        resp.common = face | moving << 30 | sceneId << 16
        resp.time = moveContent.time
        resp.dx = moveContent.dx
        resp.dy = moveContent.dy
        resp.dz = moveContent.dz
    end
    
    local packet = ProtocolHelper.EncodePTCPacket("Scene.RespMove", resp)
    self:SendPackage(packet)
end

return Player