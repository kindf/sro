local Class = require "common.class"
local Scene = require "scene.scene"
local Logger = require "common.logger"
local ConfigRepository = require "common.config_repository"
local skynet = require "skynet"
local SceneSpawn = require "lualib.scene.scene_spawn"
local SceneGrid = require "lualib.scene.scene_grid"

---@class SceneManager
---@field scenes table<integer, Scene>
---@field playerSceneMap table<integer, Scene>
local SceneManager = Class("SceneManager")

function SceneManager:Ctor()
    self.scenes = {}
    self.playerSceneMap = {}
end

function SceneManager:Init()
    self.scenes = {}
    self.playerSceneMap = {}
end

--- 按配置懒创建场景
function SceneManager:GetScene(sceneId)
    ---@type Scene|nil
    local scene = self.scenes[sceneId]
    if scene then
        return scene
    end

    local cfg = ConfigRepository.Get("tbscenetable")[sceneId]
    if not cfg then
        Logger.Error("[SceneManager]GetScene: config not found id:%s", tostring(sceneId))
        return nil
    end

    scene = Scene.new(cfg)
    self.scenes[sceneId] = scene
    scene:LoadGrid(SceneGrid[sceneId])
    scene:InitSpawns(SceneSpawn[sceneId] or {})
    return scene
end

--- 进入/切换场景统一入口。
--- oldScene 为 nil 就是首次进入；oldScene == newScene 就是原地不动。
function SceneManager:ChangeScene(uid, newSceneId, attrs)
    local newScene = self:GetScene(newSceneId)
    if not newScene then
        return nil, "scene not found"
    end

    local oldScene = self.playerSceneMap[uid]
    if oldScene == newScene then
        return {
            same = true,
            oldUnit = nil,
            oldOthers = {},
            newUnit = newScene:GetUnit(uid),
            newOthers = {},
        }
    end

    local oldUnit, oldOthers
    if oldScene then
        oldUnit, oldOthers = oldScene:Leave(uid)
    end

    self:SetPlayerScene(uid, newScene)
    local newUnit, newOthers = newScene:Enter(uid, nil, nil, nil, attrs)

    return {
        same = false,
        oldUnit = oldUnit,
        oldOthers = oldOthers or {},
        newUnit = newUnit,
        newOthers = newOthers or {},
    }
end

function SceneManager:LeaveScene(uid)
    local scene = self.playerSceneMap[uid]
    if not scene then
        return nil, {}
    end
    self.playerSceneMap[uid] = nil
    return scene:Leave(uid)
end

function SceneManager:Move(uid, moveContent)
    local scene = self.playerSceneMap[uid]
    if scene then
        return scene:Move(uid, moveContent)
    else
        Logger.Error("[SceneManager]Move: Player with uid %s is not in any scene.", tostring(uid))
    end
end

function SceneManager:GetPlayerScene(uid)
    return self.playerSceneMap[uid]
end

function SceneManager:SetPlayerScene(uid, scene)
    self.playerSceneMap[uid] = scene
end

function SceneManager:RemovePlayerScene(uid)
    local oldScene = self.playerSceneMap[uid]
    if oldScene then
        oldScene:Leave(uid)
    end
    self.playerSceneMap[uid] = nil
end

function SceneManager:CastSkill(uid, req, now)
    local scene = self.playerSceneMap[uid]
    if not scene then
        Logger.Error("[SceneManager]CastSkill: Player with uid %s is not in any scene.", tostring(uid))
        return nil, "not in scene"
    end
    return scene:CastSkill(uid, req, now)
end

function SceneManager:Revice(uid, attrs)
    local scene = self.playerSceneMap[uid]
    if not scene then
        Logger.Error("[SceneManager]Revice: Player with uid %s is not in any scene.", tostring(uid))
        return nil, "not in scene"
    end
    local oldUnit, oldOthers = scene:Leave(uid)
    local newUnit, newOthers = scene:Enter(uid, nil, nil, nil, attrs)
    return {
        oldUnit = oldUnit,
        oldOthers = oldOthers or {},
        newUnit = newUnit,
        newOthers = newOthers or {},
    }
end

-- 推进一张地图的 AI、重生和 Buff，并将本轮事件提交给 world。
local function updateScene(scene, now)
    local events = scene:Update(now)
    if #events > 0 then
        skynet.send(".world", "lua", "scene_events", events)
    end
end

-- 单张地图的异常只中止该地图的本轮更新，下一轮继续调度所有地图。
function SceneManager:UpdateAI(now)
    for sceneId, scene in pairs(self.scenes) do
        local ok, err = xpcall(updateScene, debug.traceback, scene, now)
        if not ok then
            skynet.error(("[SceneManager] scene update failed sceneId:%s: %s"):format(sceneId, err))
        end
    end
end

-- 将预检或正式拾取路由到玩家当前的场景。
function SceneManager:Pickup(uid, targetUid, preview)
    local scene = self.playerSceneMap[uid]
    if not scene then
        return nil
    end

    return scene:Pickup(uid, targetUid, preview)
end

-- 在玩家当前位置生成背包掉落，返回掉落实体及其可见玩家。
function SceneManager:DropItem(uid, itemId, count)
    local scene = self.playerSceneMap[uid]
    if scene then
        return scene:DropItemAt(uid, itemId, count)
    end
end

function SceneManager:ApplyBuff(uid, buffId, now)
    local scene = self.playerSceneMap[uid]
    if not scene then
        Logger.Error("[SceneManager]Revice: Player with uid %s is not in any scene.", tostring(uid))
        return nil, "not in scene"
    end
    return scene:ApplyBuff(uid, buffId, now)
end

function SceneManager:SetAttr(uid, attrs, now)
    local scene = self.playerSceneMap[uid]
    if not scene then
        Logger.Error("[SceneManager]Revice: Player with uid %s is not in any scene.", tostring(uid))
        return nil, "not in scene"
    end
    return scene:SetAttr(uid, attrs, now)
end

---@type SceneManager
local GSceneManager = nil
function SceneManager.GetInstance()
    if not GSceneManager then
        GSceneManager = SceneManager.new()
    end
    return GSceneManager
end

return SceneManager
