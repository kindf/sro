local SceneManager = require "scene.scene_manager"
local skynet = require "skynet"
local Handler = {}
local CMD = {}

function CMD.start()
    SceneManager.GetInstance():Init()
    skynet.fork(function()
        while true do
            skynet.sleep(30)
            SceneManager.GetInstance():UpdateAI(skynet.now() / 100)
        end
    end)
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

-- 使用技能
function CMD.cast_skill(uid, req)
    return SceneManager.GetInstance():CastSkill(uid, req, skynet.now() / 100)
end

-- 复活
function CMD.revive(uid)
    return SceneManager.GetInstance():Revice(uid)
end

function CMD.pickup(uid, targetUid)
    return SceneManager.GetInstance():Pickup(uid, targetUid)
end

Handler.CMD = CMD

return Handler