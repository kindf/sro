-- 第 17 课。在项目根目录运行 lua tests/unit/test_basic_attack_cooldown.lua。
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
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, body) return {name = name, body = body} end,
}

local Scene = require "scene.scene"
local SkillComponent = require "scene.skill_component"
local scenes = require("scene.scene_manager").GetInstance()
local commands = require("scene.scene_service_handler").CMD
local players = require("world.player.player_manager").GetInstance()
local loader = require "world.player.player_loader"
require "world.client_handler"

-- 只替换服务传输和时钟。玩家请求仍经过 world、scene 命令和真实配置。
function skynet.call(address, protocol, command, ...)
    assert(address == ".scene" and protocol == "lua")
    return true, commands[command](...)
end

local arena = Scene.new({ID = 4, StartPos = {{0, 0, 0}}})
arena:LoadGrid(nil)
scenes.scenes[4] = arena
local function enter(fd)
    local role = loader.LoadPlayer(fd, tostring(fd))
    role.packets = {}
    function role:SendPackage(packet) table.insert(self.packets, packet) end
    players:AddPlayer(role.uid, role)
    handlers["Scene.ReqEnter"](role, {sceneId = 4})
    return role
end

local a, b = enter(1701), enter(1702)
local target = assert(arena:AddMonster(1005, 1, 0))
assert(b:LearnSkill(2) and b:LearnSkill(5))
b.aspd = 20000
assert(b:SyncAttr())

-- 用协议回包、场景 HP 与施法快照检查结果。失败请求也不得延后下一次成功。
local function cast(tick, role, skillId, expectedCode)
    assert(tick >= ticks)
    ticks = tick
    local observer = role == a and b or a
    role.packets, observer.packets = {}, {}
    local unit = assert(arena:GetUnit(role.uid))
    local skills = assert(unit:GetComponent(SkillComponent))
    local lastCast, hp, sp = skills.lastCast, target.hp, unit.sp
    local lastSuccess = unit.skillCooldown[skillId]
    handlers["Scene.ReqCastSkill"](role, {skillId = skillId, targetUid = target.uid})
    local reply = assert(role.packets[1], "缺少施法回包")
    local body = reply.body
    local label = ("tick=%d uid=%s 技能=%d 期望返回 %d，实际 %s")
        :format(tick, role.uid, skillId, expectedCode, tostring(body.code))
    assert(reply.name == "Scene.RespCastSkill" and body.code == expectedCode, label)
    if expectedCode == 0 then
        assert(skills.lastCast ~= lastCast and unit.skillCooldown[skillId] == tick / 100, label)
        assert(#body.hits == 1 and body.hits[1].uid == target.uid and body.damage > 0, label)
        assert(target.hp == hp - body.damage and body.hits[1].hp == target.hp, label)
    else
        assert(skills.lastCast == lastCast and unit.skillCooldown[skillId] == lastSuccess, label)
        assert(#body.hits == 0 and body.damage == 0 and target.hp == hp and unit.sp == sp, label)
        assert(#role.packets == 1 and #observer.packets == 0, label)
    end
end

-- A 入场空手，默认攻速 10000。B 双倍攻速 20000。首击同一时刻成功。
cast(0, a, 1, 0)
cast(0, b, 1, 0)
cast(0, b, 2, 0)  -- 怒爆开启第 1 组的 2 秒冷却，普攻属于组 0。
ticks = 10
assert(commands.set_attr(a.uid, {aspd = 20000}))
assert(commands.set_attr(b.uid, {aspd = 8000}))
cast(44, b, 1, 4)
cast(45, b, 1, 0)  -- 减速不推迟上一击的 450 ms 到期点。此击开始使用 1250 ms。
cast(45, a, 1, 4)
cast(89, a, 1, 4)
cast(90, a, 1, 0)  -- 提速不提前上一击的 900 ms 到期点。此击开始使用 450 ms。
cast(134, a, 1, 4)
cast(135, a, 1, 0)
cast(169, b, 1, 4)
cast(170, b, 1, 0)
cast(199, b, 5, 4)
cast(200, b, 5, 0)  -- 普攻的变速与多次请求均不影响怒爆留给冰箭术的组冷却。

-- 长枪类型 4 的普通新手动作在原版回退到武器键 0。穿脱前后的动作 Time 都是 0.9。
local spear = 8000003
local slot = assert(a:AddItem(spear, 1))[1].slot
handlers["Scene.ReqEquipItem"](a, {slot = slot})
assert(a.equipment[1] == spear)
cast(210, a, 1, 0)
handlers["Scene.ReqUnequipItem"](a, {equipSlot = 1})
assert(a.equipment[1] == nil)
cast(299, a, 1, 4)
cast(300, a, 1, 0)
cast(389, a, 1, 4)
cast(390, a, 1, 0)

-- 14500 给出约 620.69 ms，截断到 620 ms 后第 62 tick 可再次请求。
assert(commands.set_attr(a.uid, {aspd = 14500}))
cast(500, a, 1, 0)
cast(561, a, 1, 4)
cast(562, a, 1, 0)

-- 12000 的 float32 结果为 749.99993896484 ms。场景入口可直接验证 tick 之间的 749 ms。
assert(commands.set_attr(a.uid, {aspd = 12000}))
cast(700, a, 1, 0)
local req = {skillId = 1, skillLevel = 1, targetUid = target.uid}
assert(arena:CastSkill(a.uid, req, 7.748).code == 4)
assert(arena:CastSkill(a.uid, req, 7.749).code == 0, "原版单精度乘法并截断后应为 749 ms")

-- 把相同技能 1 交给怪物走场景施法入口，单独检验施法者类型这一条件。
local poring = assert(arena:AddMonster(1001, 0, 0))
local monsterReq = {skillId = 1, skillLevel = 1, targetUid = b.uid}
assert(arena:CastSkill(poring.uid, monsterReq, 8).code == 0)
assert(arena:CastSkill(poring.uid, monsterReq, 8.9).code == 4, "怪物套用了玩家空手动作")
assert(arena:CastSkill(poring.uid, monsterReq, 9).code == 0, "怪物应按技能表值 1 秒再次施放")
print("OK basic attack cooldown")
