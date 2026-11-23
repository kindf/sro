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
-- 每次施法仅回一份完整结果，然后依次同步伤害、状态和击杀奖励。
local function ReqCastSkill(player, req)
    local data = player:CastSkill(req)
    if not data then
        return
    end

    local hits = {}
    for _, h in ipairs(data.hits or {}) do
        table.insert(hits, {uid = h.uid, damage = h.damage, hp = h.hp, maxHp = h.maxHp})
    end
    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespCastSkill", {
        code = data.code,
        targetUid = data.targetUid,
        damage = data.damage,
        targetHp = data.targetHp,
        hits = hits,
    }))

    -- 再回目标
    if data.code == 0 then
        for _, h in ipairs(data.hits or {}) do
            -- 每个目标一条 UnitHp
            local hpPacket = ProtocolHelper.EncodePTCPacket("Scene.UnitHp", {
                uid = h.uid, hp = h.hp, maxHp = h.maxHp,
            })
            PlayerManager.GetInstance():SendUidsPacket(h.receivers, hpPacket)

            if h.dead then
                local deadPacket = ProtocolHelper.EncodePTCPacket("Scene.UnitDead", { uid = h.uid })
                PlayerManager.GetInstance():SendUidsPacket(h.deadReceivers, deadPacket)
            end
        end

        -- 2. 技能附带的 Buff
        for _, buff in ipairs(data.buffs or {}) do
            local set = buff.receivers

            local buffPacket = ProtocolHelper.EncodePTCPacket("Scene.UnitBuff", {
                uid = buff.uid,
                buffId = buff.buffId,
                duration = buff.duration,
            })
            PlayerManager.GetInstance():SendUidsPacket(set, buffPacket)

            local attrPacket = ProtocolHelper.EncodePTCPacket("Scene.UnitAttr", {
                uid = buff.uid,
                atk = buff.attr.atk,
                def = buff.attr.def,
                maxHp = buff.attr.maxHp,
                hp = buff.attr.hp,
                sp = buff.attr.sp,
                maxSp = buff.attr.maxSp,
            })
            PlayerManager.GetInstance():SendUidsPacket(set, attrPacket)
        end
    end

    if data.reward then
        if data.reward.baseExp > 0 or data.reward.jobExp > 0 then
            player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespExp", {
                uid = player.uid,
                baseExp = data.reward.baseExp,
                jobExp = data.reward.jobExp,
                totalBaseExp = data.reward.totalBaseExp,
                totalJobExp = data.reward.totalJobExp,
                level = data.reward.level,
            }))
        end

        for _, drop in ipairs(data.reward.drops or {}) do
            local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", drop.unit)
            PlayerManager.GetInstance():SendUidsPacket(drop.receivers, packet)
        end
    end
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqCastSkill", ReqCastSkill)

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

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespPickup", {
        code = data.code,
        itemId = data.itemId or 0,
        count = data.count or 0,
    }))

    if data.code == 0 then
        player:SendItemUpdate(data.changed)
        local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitLeave", {uid = req.targetUid})
        PlayerManager.GetInstance():SendUidsPacket(data.receivers, packet)
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
    local data = player:DropItem(req.slot, req.count)
    if not data then
        player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespDropItem", {
            code = 1, itemId = 0, count = 0,
        }))
        return
    end

    player:SendPackage(ProtocolHelper.EncodePTCPacket("Scene.RespDropItem", {
        code = 0, itemId = data.unit.entityId, count = data.unit.count,
    }))
    player:SendItems()
    
    local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitEnter", data.unit)
    PlayerManager.GetInstance():SendUidsPacket(data.receivers, packet)
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqDropItem", ReqDropItem)

local function SendEquipmentResult(player, responseName, data)
    if not data then
        return
    end

    player:SendPackage(ProtocolHelper.EncodePTCPacket(responseName, {
        code = data.code,
        equipSlot = data.equipSlot or 0,
        itemId = data.itemId or 0,
    }))
    if data.code ~= 0 then return end

    player:SendItems()
    local attr = player:SyncAttr()
    if attr then
        local packet = ProtocolHelper.EncodePTCPacket("Scene.UnitAttr", {
            uid = attr.uid, atk = attr.atk, def = attr.def,
            maxHp = attr.maxHp, hp = attr.hp,
        })
        PlayerManager.GetInstance():SendUidsPacket(attr.receivers, packet)
    end
end

local function ReqEquipItem(player, req)
    SendEquipmentResult(player, "Scene.RespEquipItem", player:EquipItem(req.slot))
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqEquipItem", ReqEquipItem)

local function ReqUnequipItem(player, req)
    SendEquipmentResult(player, "Scene.RespUnequipItem", player:UnequipItem(req.equipSlot))
end
ProtocolHelper.RegisterPTCHandler("Scene.ReqUnequipItem", ReqUnequipItem)

