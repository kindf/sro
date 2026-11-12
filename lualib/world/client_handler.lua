local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"
local PlayerManager = require "world.player.player_manager"

---@param player Player
local function ReqMove(player, req)
    Logger.Info("[ClientHandler]ReqMove: uid:%s, msg:%s", tostring(player.uid), tostring(req))
    local packet, forced = player:ReqMove(req)
    if not packet then
        return
    end

    if forced then
        player:SendPackage(packet)
    else
        PlayerManager.GetInstance():Broadcast(packet, nil)
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqMove", ReqMove)