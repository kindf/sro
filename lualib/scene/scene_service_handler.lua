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

function CMD.change_scene(uid, sceneId, attrs)
    return SceneManager.GetInstance():ChangeScene(uid, sceneId, attrs)
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
function CMD.revive(uid, attrs)
    return SceneManager.GetInstance():Revice(uid, attrs)
end

-- 预检或领取目标掉落，由 world 在确认背包容量后发起正式领取。
function CMD.pickup(uid, targetUid, preview)
    return SceneManager.GetInstance():Pickup(uid, targetUid, preview)
end

-- 将背包物品生成到玩家所在场景，成功后 world 扣除物品。
function CMD.drop_item(uid, itemId, count)
    return SceneManager.GetInstance():DropItem(uid, itemId, count)
end

function CMD.apply_buff(uid, buffId)
    return SceneManager.GetInstance():ApplyBuff(uid, buffId, skynet.now() / 100)
end

function CMD.set_attr(uid, attrs)
    return SceneManager.GetInstance():SetAttr(uid, attrs, skynet.now() / 100)
end

Handler.CMD = CMD

return Handler
