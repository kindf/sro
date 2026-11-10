local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"

---@param player Player
local function ReqMove(player, req)
    Logger.Info("[ClientHandler]ReqMove: uid:%s, msg:%s", tostring(player.uid), tostring(req))
    player:ReqMove(req)
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqMove", ReqMove)