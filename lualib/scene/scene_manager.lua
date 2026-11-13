local Class = require "common.class"
local Scene = require "scene.scene"
local Logger = require "common.logger"
local ConfigRepository = require "common.config_repository"

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
    return scene
end

--- 进入/切换场景统一入口。
--- oldScene 为 nil 就是首次进入；oldScene == newScene 就是原地不动。
function SceneManager:ChangeScene(uid, newSceneId)
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
    local newUnit, newOthers = newScene:Enter(uid, nil, nil, nil)

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

---@type SceneManager
local GSceneManager = nil
function SceneManager.GetInstance()
    if not GSceneManager then
        GSceneManager = SceneManager.new()
    end
    return GSceneManager
end

return SceneManager
