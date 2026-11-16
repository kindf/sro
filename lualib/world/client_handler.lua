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

local function ReqEnter(player, req)
    local data = player:ChangeScene(req.sceneId)
    if not data then
        return
    end
    -- 首次进入/切场景共用同一套通知逻辑；只有显式切换才回 RespEnter
    PlayerManager.GetInstance():ApplySceneChange(player, data, req.sceneId, true)
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqEnter", ReqEnter)

---@param player Player
local function ReqCaskSkill(player, req)
    local data = player:CastSkill(req)
    if not data then
        return
    end

    -- 先回自己
    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespCastSkill", {
        code = data.code,
        targetUid = data.targetUid,
        damage = data.damage,
        targetHp = data.targetHp,
    }))

    -- 再回目标
    if data.code == 0 then
        local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitHp", {
            uid = req.targetUid,
            hp = data.targetHp,
            maxHp = data.maxHp,
        })
        PlayerManager:GetInstance():SendUidsPacket(data.receivers, packet)
    end

    if data.reward then
        if data.reward.baseExp > 0 or data.reward.jobExp > 0 then
            player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespExp", {
                uid = player.uid,
                baseExp = data.reward.baseExp,
                jobExp = data.reward.jobExp,
                totalBaseExp = data.reward.totalBaseExp ,
                totalJobExp = data.reward.totaljobExp,
                level = data.reward.level,
            }))
        end

        for _, drop in ipairs(data.reward.drops or {}) do
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", drop)
            PlayerManager:GetInstance():SendUidsPacket(data.reward.dropReceivers, packet)
        end
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqCastSkill", ReqCaskSkill)

---@param player Player
local function ReqRevive(player, req)
    local result = player:Revive()
    if not result then
        return
    end

    PlayerManager.GetInstance():ApplySceneChange(player, result, player.sceneId, false)

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespRevive", {
        uid = player.uid,
        x = result.newUnit.x,
        y = result.newUnit.y,
        z = result.newUnit.z,
        hp = result.newUnit.hp,
        maxHp = result.newUnit.maxHp,
    }))
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqRevive", ReqRevive)

---@param player Player
local function ReqPickup(player, req)
    local data = player:Pickup(req.targetUid)
    if not data then
        return
    end

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespPickup", {
        code = data.code,
        itemId = data.itemId or 0,
        count = data.count or 0,
    }))

    if data.code == 0 then
        local leave = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {
            uid = req.targetUid,
        })
        PlayerManager.GetInstance():SendUidsPacket(data.receivers, leave)
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqPickup", ReqPickup)