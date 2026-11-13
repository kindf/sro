local Class = require "common.class"
local Scene = require "scene.scene"
local Logger = require "common.logger"

---@class SceneManager
---@field scenes table<integer, Scene>
---@field playerSceneMap table<integer, Scene>
local SceneManager = Class("SceneManager")

function SceneManager:Ctor()
    self.scenes = {}
    self.playerSceneMap = {}
end

function SceneManager:Init()
    self.scenes[1] = Scene.new()
end

function SceneManager:EnterScene(uid, sceneId, x, y, z)
    local oldScene = self.playerSceneMap[uid]
    
    local newScene = self.scenes[sceneId]
    if not newScene then
        Logger.Error("[SceneManager]EnterScene: Scene with id %s does not exist.", tostring(sceneId))
        return
    end
    if oldScene then
        oldScene:Leave(uid)
    end
    self:SetPlayerScene(uid, newScene)
    return newScene:Enter(uid, x, y, z)
end

function SceneManager:LeaveScene(uid)
    return self:RemovePlayerScene(uid)
end

function SceneManager:Move(uid, moveContent)
    local scene = self.playerSceneMap[uid]
    if scene then
        return scene:Move(uid, moveContent)
    else
        Logger.Error("[SceneManager]Move: Player with uid %s is not in any scene.", tostring(uid))
    end
end

function SceneManager:GetScene(sceneId)
    return self.scenes[sceneId]
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