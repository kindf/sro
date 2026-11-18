local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"
local PlayerManager = require "world.player.player_manager"
local ConfigRepository = require "common.config_repository"

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
        local changed, err = player:AddItem(data.itemId, data.count)
        if not changed then
            player:DropItemToScene(data.itemId, data.count)
            player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespPickup", {
                code = 3,
                itemId = 0,
                count = 0
            }))
            return
        end
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespPickup", {
            code = 0, itemId = data.itemId, count = data.count
        }))
        player:SendItemUpdate(changed)
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqPickup", ReqPickup)

---@param player Player
local function ReqUseItem(player, req)
    local data = player:UseItem(req.slot, req.count)
    if not data then
        return
    end

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespUseItem", {
        code = data.code,
        itemId = data.itemId or 0,
        count = data.count or 0,
    }))

    if data.code == 0 then
        player:SendItems()

        local fn = ConfigRepository.Get("tbitemfunctiontable")[data.itemId]
        if fn and fn.ItemFunction == 1 then
            local buffId = fn.ItemFunctionValue and fn.ItemFunctionValue[1]
            if buffId then
                local buff = player:ApplyBuff(buffId)
                if buff then
                    local set = buff.receivers
                    local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitBuff", {
                        uid = player.uid, buffId = buffId, duration = buff.duration,
                    })
                    PlayerManager.GetInstance():SendUidsPacket(set, packet)

                    local attr = ProtocolHelper.EncodePTCPacket("Scene.UnitAttr", {
                        uid = player.uid,
                        atk = buff.attr.atk,
                        def = buff.attr.def,
                        maxHp = buff.attr.maxHp,
                        hp = buff.attr.hp,
                    })
                    PlayerManager.GetInstance():SendUidsPacket(set, attr)
                end
            end
        else
            Logger.Warning("[Item] item %s function %s not implemented",
                tostring(data.itemId), tostring(fn and fn.ItemFunction))
        end
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqUseItem", ReqUseItem)

---@param player Player
local function ReqDropItem(player, req)
    local itemId, count = player:RemoveItem(req.slot, req.count)
    if not itemId then
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespDropItem", {
            code = 1, itemId = 0, count = 0,
        }))
        return
    end

    local data = player:DropItemToScene(itemId, count)
    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespDropItem", {
        code = 0, itemId = itemId, count = count,
    }))
    player:SendItems()
    
    if data and data.unit then
        local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", data.unit)
        PlayerManager.GetInstance():SendUidsPacket(data.receivers, packet)
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqDropItem", ReqDropItem)

local function ReqEquipItem(player, req)
    local data = player:EquipItem(req.slot)
    if not data then return end

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespEquipItem", {
        code = data.code,
        equipSlot = data.equipSlot or 0,
        itemId = data.itemId or 0,
    }))

    if data.code == 0 then
        player:SendItems()

        local attr = player:SyncAttr()
        if attr then
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitAttr", {
                uid = attr.uid,
                atk = attr.atk,
                def = attr.def,
                maxHp = attr.maxHp,
                hp = attr.hp,
            })
            PlayerManager.GetInstance():SendUidsPacket(attr.receivers, packet)
        end
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqEquipItem", ReqEquipItem)

