-- 第 12 课。在项目根目录运行 lua tests/unit/test_skill_range_point.lua。
package.path = "./lualib/?.lua;" .. package.path

-- 带 --wire 时只验证项目实际加载的协议描述符，须使用可加载 pb 的 Lua。
if arg[1] == "--wire" then
    local pb = require "pb"
    assert(pb.loadfile("protocol/pb/scene.pb"), "加载 scene.pb 失败")
    local name = "Scene.ReqCastSkill"
    local legacy = pb.decode(name, "\x08\x01\x10\x2a") -- skillId=1，targetUid=42
    assert(legacy.skillId == 1 and legacy.targetUid == 42 and legacy.castPoint == nil)
    for _, point in ipairs({{x = 0, y = 0, z = 0}, {x = -0.25, y = 1.5, z = 2.75}}) do
        local bytes = pb.encode(name, {skillId = 7, targetUid = 0, castPoint = point})
        local request = pb.decode(name, bytes)
        assert(request.skillId == 7 and request.targetUid == 0)
        local decoded = assert(request.castPoint, "scene.pb 没有传回 castPoint")
        assert(decoded.x == point.x and decoded.y == point.y and decoded.z == point.z)
    end
    print("OK skill range point wire")
    return
end

local ticks, handlers = 0, {}
local skynet = {now = function() return ticks end}
package.loaded.skynet = skynet
package.loaded["skynet.socket"] = {}
package.loaded["common.logger"] = {}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Scene = require "scene.scene"
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
local SkillComponent = require "scene.skill_component"
require "world.client_handler"

-- 仅替换服务传输；场景命令执行后保留 world 组包前的结果。
local sceneResult
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    local result, reason = assert(commands[command], command)(...)
    if command == "cast_skill" then sceneResult = result end
    return true, result, reason
end

-- 原点距施法者 1 米；远点取 14 米，超过暴风雪带玩家容差后的 13 米上限。
local mapId = 4
local scene = Scene.new({ID = mapId, StartPos = {{1, 0, 0}}})
scene:LoadGrid(nil)
scenes.scenes[mapId] = scene
local near = {x = 0, y = 0, z = 0}
local far = {x = 1, y = 0, z = 14}

-- 经正常进图命令装载角色，记录服务端发给他的消息。
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = mapId})
    return role
end

local hero, observer = enter(1201), enter(1202)
local caster = assert(scene:GetUnit(hero.uid))
local skills = assert(caster:GetComponent(SkillComponent))
local target = assert(scene:AddMonster(1005, near.x, near.z))
assert(hero:LearnSkill(7) and target.hp == 1491)
assert(scene:SetAttr(caster.uid, {maxSp = 1000}, 0) and caster.maxSp == 1000)
caster.sp = caster.maxSp

-- 返回 world 回复，并跟踪同一次请求的场景受理状态。
local function cast(skillId, point, targetUid)
    hero.packets, observer.packets, sceneResult = {}, {}, nil
    local req = {skillId = skillId, targetUid = targetUid or target.uid, castPoint = point}
    handlers["Scene.ReqCastSkill"](hero, req)
    local reply
    for _, packet in ipairs(hero.packets) do
        if packet.name == "Scene.RespCastSkill" then
            assert(not reply, "本次请求出现多份施法回复")
            reply = packet.body
        end
    end
    assert(reply and sceneResult and reply.code == sceneResult.code)
    return reply
end

-- 射程错误须在资源、冷却、施法号和战斗广播之前返回。
local function denied(label, skillId, point, code, targetUid)
    local hp, sp, previous = target.hp, caster.sp, skills.lastCast
    local cooldown = caster.skillCooldown[skillId]
    local group = caster.skillGroupReadyAtMs[1]
    local reply = cast(skillId, point, targetUid)
    assert(reply.code == code, ("%s：预期 code=%d，实际 %s"):format(label, code, tostring(reply.code)))
    assert(reply.damage == 0 and #reply.hits == 0 and target.hp == hp and caster.sp == sp, label)
    assert(not sceneResult.castId and skills.lastCast == previous, label)
    assert(caster.skillCooldown[skillId] == cooldown and caster.skillGroupReadyAtMs[1] == group, label)
    assert(#hero.packets == 1 and #observer.packets == 0, label .. " 在拒绝后发出了战斗广播")
end

-- 核对受理、实际扣费、受击者和旁观广播。显式地面点单独留存落点快照。
local function allowed(label, skillId, point, expectedHits, targetUid)
    local hp, sp, previous = target.hp, caster.sp, skills.lastCast
    local reply = cast(skillId, point, targetUid)
    assert(reply.code == 0, ("%s：预期成功，实际 code=%s"):format(label, tostring(reply.code)))
    local spCost = skillId == 7 and 132 or 0
    assert(caster.sp == sp - spCost and caster.skillCooldown[skillId] == ticks / 100, label)
    local record = assert(sceneResult.cast)
    assert(record.skillId == skillId and skills.lastCast == record and sceneResult.castId == record.castId)
    if previous then assert(record.castId == previous.castId + 1, label .. " 拒绝请求占用了施法号") end
    if skillId == 7 and point then
        assert(record.targetUid == 0 and sceneResult.targetUid == 0 and reply.targetUid == 0, label)
        local p = assert(record.castPoint, label .. " 缺少落点快照")
        assert(p ~= point and p.x == point.x and p.y == point.y and p.z == point.z, label)
    elseif skillId == 1 and point then
        local p = assert(record.castPoint, label .. " 缺少单位施法点快照")
        assert(record.targetUid == target.uid and p.x == target.x and p.y == target.y and p.z == target.z,
            label .. " 应记录目标的服务器位置")
    end
    assert(#reply.hits == expectedHits and #sceneResult.hits == expectedHits, label)
    if expectedHits == 1 then
        local hit = reply.hits[1]
        assert(hit.uid == target.uid and hit.damage > 0 and hp - target.hp == hit.damage, label)
    else
        assert(target.hp == hp and reply.damage == 0, label .. " 空地施法改变了怪物血量")
    end
    local hpPackets = 0
    for _, packet in ipairs(observer.packets) do
        if packet.name == "Scene.UnitHp" then
            hpPackets = hpPackets + 1
            assert(packet.body.uid == target.uid and packet.body.hp == target.hp, label)
        end
    end
    assert(hpPackets == expectedHits, label .. " 实际命中数与血量广播数不同")
end

-- 真实移动命令更新同一个 UID 的场景位置和 AOI 网格。
local function moveTarget(point)
    local moved = assert(scene:Move(target.uid, {
        common = 0, dx = point.x, dy = point.y, dz = point.z, time = 1,
    }))
    assert(not moved.forced and target.x == point.x and target.z == point.z)
end

-- 近目标与远请求点并存时，点地技能超出射程，锁定技也会拒绝超远请求点。
denied("近目标、远施法点的暴风雪", 7, far, 3)
denied("近目标、远施法点的普攻", 1, far, 3)
allowed("近目标、近施法点的普攻", 1, near, 1)
allowed("近目标、近施法点的暴风雪", 7, near, 1)

-- 保持请求点为近点，只移动同一只怪。两项技能均已退出冷却。
ticks = 400
moveTarget(far)
denied("远目标、近施法点的普攻", 1, near, 3)
allowed("远目标、近施法点的暴风雪打在空地", 7, near, 0)

-- 目标留在远处，只改请求点；再将目标移回近处，远地仍不可选。
ticks = 800
denied("远目标、远施法点的暴风雪", 7, far, 3)
moveTarget(near)
denied("目标移回近点、施法点仍远的暴风雪", 7, far, 3)
allowed("旧格式普攻只传目标 UID", 1, nil, 1)
allowed("旧格式暴风雪沿用有效目标位置", 7, nil, 1)

-- 空地允许没有指定单位；没有落点或没有合法数值时，不能扣除下一发的 SP。
ticks = 1200
denied("目标 UID 为零且没有施法点", 7, nil, 1, 0)
denied("显式落点缺少 Y 坐标", 7, {x = 0, z = 0}, 3, 0)
denied("落点 Z 为 NaN", 7, {x = 0, y = 0, z = 0/0}, 3, 0)
denied("落点 X 为无穷大", 7, {x = math.huge, y = 0, z = 0}, 3, 0)
allowed("不指定单位也能点选原点，命中附近敌人", 7, near, 1, 0)
allowed("合法普攻请求点与单位位置不同", 1, {x = 1.5, y = 0, z = 0}, 1)

-- 怪物模板施法也只传目标 UID，仍可按玩家当前位置完成锁定攻击。
local events, hpBefore = {}, caster.hp
assert(target:TryCastSkills(scene, caster, ticks / 100, events))
assert(#events == 1 and events[1].kind == "hp" and events[1].uid == caster.uid)
assert(events[1].hp == caster.hp and caster.hp < hpBefore)
print("OK skill range point")
