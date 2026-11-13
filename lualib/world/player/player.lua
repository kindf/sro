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
    self.sceneId = 1
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

function Player:OnBorn(sceneId)
    return self:ChangeScene(sceneId or self.sceneId or 1)
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

return Player