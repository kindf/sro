local SceneManager = require "scene.scene_manager"
local Handler = {}
local CMD = {}

function CMD.start()
    SceneManager.GetInstance():Init()
    return true
end

function CMD.change_scene(uid, sceneId)
    return SceneManager.GetInstance():ChangeScene(uid, sceneId)
end

function CMD.leave(uid)
    return SceneManager.GetInstance():LeaveScene(uid)
end

function CMD.move(uid, moveContent)
    return SceneManager.GetInstance():Move(uid, moveContent)
end

function CMD.get_unit(uid)
    local scene = SceneManager.GetInstance():GetPlayerScene(uid)
    if scene then
        return scene:GetUnit(uid)
    end
    return nil
end

Handler.CMD = CMD

return Handler