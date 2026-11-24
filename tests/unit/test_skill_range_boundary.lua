-- 第 13 课。在项目根目录运行 lua tests/unit/test_skill_range_boundary.lua。
package.path = "./lualib/?.lua;" .. package.path

local ticks, handlers = 0, {}
local skynet = {now = function() return ticks end}
package.loaded.skynet = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, fn) handlers[name] = fn end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Scene = require "scene.scene"
local SkillComponent = require "scene.skill_component"
local commands = require("scene.scene_service_handler").CMD
local scenes = require("scene.scene_manager").GetInstance()
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
require "world.client_handler"

-- 将 world 的请求交给实际场景命令，保留组包前的场景结果。
local sceneResult
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then sceneResult = result end
    return true, result, reason
end

local scene = Scene.new({ID = 4, StartPos = {{0, 0, 0}}})
scene:LoadGrid(nil)
scenes.scenes[4] = scene

-- 两名同图玩家，一名施法，一名监听拒绝后是否误发战斗广播。
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

local hero, observer = enter(1301), enter(1302)
local caster = assert(scene:GetUnit(hero.uid))
local skills = assert(caster:GetComponent(SkillComponent))
assert(hero:LearnSkill(7))
assert(scene:SetAttr(hero.uid, {maxSp = 1000}, 0) and caster.maxSp == 1000)
caster.sp = 1000

-- 只用于正的正规 float。在相邻的 IEEE 754 位模式之间走一步，避免自定 epsilon。
local function adjacent(value, step)
    local bits = string.unpack("<I4", string.pack("<f", value))
    return (string.unpack("<f", string.pack("<I4", bits + step)))
end

-- 每个样本至少间隔 10 秒，断言失败只能来自本次准入，沿途核对资源、冷却、施法号。
local function playerCast(label, id, target, x, z, expected)
    ticks = ticks + 1000
    hero.packets, observer.packets, sceneResult = {}, {}, nil
    local sp, last = caster.sp, skills.lastCast
    local cd, group = caster.skillCooldown[id], caster.skillGroupReadyAtMs[1]
    local hp = target and target.hp
    handlers["Scene.ReqCastSkill"](hero, {
        skillId = id, targetUid = target and target.uid or 0, castPoint = {x = x, y = 0, z = z},
    })
    local reply = assert(hero.packets[1], label .. " 无回复")
    assert(reply.name == "Scene.RespCastSkill" and sceneResult and reply.body.code == sceneResult.code)
    assert(reply.body.code == expected, ("%s：应返回 %d，实际 %d"):format(label, expected, reply.body.code))
    if expected == 0 then
        assert(skills.lastCast == sceneResult.cast and sceneResult.castId == skills.lastCast.castId, label)
        if last then assert(sceneResult.castId == last.castId + 1, label .. " 上次拒绝占用了施法号") end
        assert(caster.skillCooldown[id] == ticks / 100, label)
        if id == 7 then
            assert(caster.sp == sp - 132 and #reply.body.hits == 0 and #observer.packets == 0, label)
        else
            assert(caster.sp == sp and target.hp < hp and reply.body.hits[1].uid == target.uid, label)
        end
    else
        assert(sceneResult.castId == nil and skills.lastCast == last and caster.sp == sp, label)
        assert(caster.skillCooldown[id] == cd and caster.skillGroupReadyAtMs[1] == group, label)
        assert(not target or target.hp == hp, label)
        assert(#reply.body.hits == 0 and #hero.packets == 1 and #observer.packets == 0, label)
    end
end

-- 玩家地面技能 7：7 米基础上限 + 6 米玩家容差。三个点都可以直接写进协议 float。
playerCast("暴风雪：13 的前一格", 7, nil, adjacent(13, -1), 0, 0)
playerCast("暴风雪：正好 13", 7, nil, 13, 0, 0)
playerCast("暴风雪：13 的后一格", 7, nil, adjacent(13, 1), 0, 3)

-- 原版 float 点积在这两组输入分别舍入到 169、169.0000152587890625。
-- 直接用 Lua double 会错拒第一组；只在开方后转 float 会错放第二组。
playerCast("二维距离：点积舍入后正好在边界", 7, nil, 13, 1 / 1024, 0)
playerCast("二维距离：点积舍入后刚过边界", 7, nil, 13, 3 / 1024, 3)
assert(caster.sp == 604)

-- 锁定普攻分别核对目标实际位置和上报点；目标 1002 的移动容差与玩家通用容差不同。
local near = assert(scene:AddMonster(1002, 1, 0))
local moving = assert(scene:AddMonster(1002, 2.5, 0))
local far = assert(scene:AddMonster(1002, 6, 0))
playerCast("普攻：目标近、报点正好 7.5", 1, near, 7.5, 0, 0)
playerCast("普攻：目标近、报点刚过 7.5", 1, near, adjacent(7.5, 1), 0, 3)
playerCast("普攻：目标位于吟唱移动容差内", 1, moving, 1, 0, 0)
playerCast("普攻：即使报点近也不能给远目标加 6 米", 1, far, 1, 0, 3)

-- 原式输入为 1.5 米射程、1002 的模板速度、299 毫秒和零半径。独立算得 float 上限位模式 0x4049e83e。
local singingLimit = 3.154799938201904296875
local atLimit = assert(scene:AddMonster(1002, singingLimit, 0))
local pastLimit = assert(scene:AddMonster(1002, adjacent(singingLimit, 1), 0))
playerCast("普攻：1002 的动态上限等号", 1, atLimit, 1, 0, 0)
playerCast("普攻：1002 的动态上限后一格", 1, pastLimit, 1, 0, 3)

-- 同一份 1222 模板在 4.5 和 5.25 米各放一只。它的 10222 外观定义了一个居中、半径为 1 的碰撞体。
local largeNear = assert(scene:AddMonster(1222, 4.5, 0))
local largeFar = assert(scene:AddMonster(1222, 5.25, 0))
playerCast("普攻：1222 的半径使 4.5 米可达", 1, largeNear, 1, 0, 0)
playerCast("普攻：1222 加上半径仍够不到 5.25 米", 1, largeFar, 1, 0, 3)

-- 模板 27100 已配置下列技能。让怪物留在原点，移动活玩家，经 AI 共用的场景入口施法。
local monster = assert(scene:AddMonster(27100, 0, 0))
local monsterSkill = 1002710004
local configured = false
for _, entry in ipairs(monster.skillIds) do
    if entry[1] == monsterSkill and entry[2] == 1 then configured = true end
end
assert(configured, "怪物模板缺少一级近限技能")
local monsterSkills = assert(monster:GetComponent(SkillComponent))
local function monsterCast(label, distance, expected, reportedX)
    ticks = ticks + 1000
    local moved = assert(scene:Move(hero.uid, {common = 0, dx = distance, dy = 0, dz = 0, time = 1}))
    assert(not moved.forced and caster.x == distance and caster.z == 0, label .. " 玩家未到指定点")
    local hp, sp, last = caster.hp, monster.sp, monsterSkills.lastCast
    local cd = monster.skillCooldown[monsterSkill]
    local result = scene:CastSkill(monster.uid, {
        skillId = monsterSkill, skillLevel = 1, targetUid = hero.uid,
        castPoint = reportedX and {x = reportedX, y = 0, z = 0},
    }, ticks / 100)
    assert(result.code == expected, ("%s：应返回 %d，实际 %d"):format(label, expected, result.code))
    assert(monster.sp == sp, label .. " 怪物技能耗蓝错误")
    if expected == 0 then
        assert(result.hits[1].uid == hero.uid and caster.hp < hp and monsterSkills.lastCast == result.cast, label)
        assert(monster.skillCooldown[monsterSkill] == ticks / 100, label)
    else
        assert(not result.castId and monsterSkills.lastCast == last and caster.hp == hp, label)
        assert(monster.skillCooldown[monsterSkill] == cd, label)
    end
end

-- 怪物施法使用 0 容差，真实效果的闭区间为 [2, 9]。
monsterCast("怪物下限外", adjacent(2, -1), 3)
monsterCast("怪物下限等号", 2, 0)
monsterCast("怪物下限内", adjacent(2, 1), 0)
monsterCast("怪物上限内", adjacent(9, -1), 0)
monsterCast("怪物上限等号", 9, 0)
monsterCast("怪物上限外", adjacent(9, 1), 3)

-- 报点固定在怪物的合法上限 9 米。目标玩家用 100 毫秒和跑速 4.6，实际位置上限约为 10.02 米。
assert(caster.hp > 10 and not caster.dead)
monsterCast("目标玩家在 10 米，报点 9 米", 10, 0, 9)
monsterCast("目标玩家在 10.125 米，报点仍为 9 米", 10.125, 3, 9)
print("OK skill range boundary")
