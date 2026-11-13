local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"
local PlayerManager = require "world.player.player_manager"

---@param player Player
local function ReqMove(player, req)
    Logger.Info("[ClientHandler]ReqMove: uid:%s, msg:%s", tostring(player.uid), tostring(req))
    local packet, moveContent = player:ReqMove(req)
    if not packet then
        return
    end

        -- 自己先更新
    player:SendPackage(packet)
    if moveContent.forced then
        return
    end

    -- 进入视野
    for _, u in ipairs(moveContent.enters or {}) do
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", u))

        local selfEnter = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", {
            uid = player.uid, x = moveContent.dx, y = moveContent.dy, z = moveContent.dz,
        })
        PlayerManager:GetInstance():SendUidPacket(u.uid, selfEnter)
    end

    -- 还在视野内：移动
    PlayerManager:GetInstance():SendUidsPacket(moveContent.receivers, packet)

    -- 离开视野
    for _, u in ipairs(moveContent.leaves or {}) do
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", u))
        PlayerManager:GetInstance():SendUidsPacket(u.uid, ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {
            uid = player.uid, x = moveContent.dx, y = moveContent.dy, z = moveContent.dz,
        }))
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqMove", ReqMove)