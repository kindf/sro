local Class = require "common.class"
local Logger = require "common.logger"
local socket = require "skynet.socket"

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

function Player:SendPackage(package)
    if not self.fd then
        Logger.Warning("[Player]SendPackage failed, fd is nil. uid:%s", self.uid)
        return
    end
    socket.write(self.fd, package)
end

return Player