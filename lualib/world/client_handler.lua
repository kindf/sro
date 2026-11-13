local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"
local PlayerManager = require "world.player.player_manager"
local WorldHandler = require "world.world_service_handler"

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
    local leave = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {
        uid = player.uid,
    })
    for _, uid in ipairs(moveContent.leaves or {}) do
        PlayerManager:GetInstance():SendUidPacket(uid, leave)
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqMove", ReqMove)


--- 首次进入和切换场景共用：处理 Enter/Leave/RespEnter
local function ApplySceneChange(player, data, sceneId, sendResp)
    if not data or data.same then
        return
    end

    local pm = PlayerManager.GetInstance()

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

local function ReqEnter(player, req)
    local data = player:ChangeScene(req.sceneId)
    if not data then
        return
    end
    -- 首次进入/切场景共用同一套通知逻辑；只有显式切换才回 RespEnter
    ApplySceneChange(player, data, req.sceneId, true)
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqEnter", ReqEnter)