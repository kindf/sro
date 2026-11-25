-- 在项目根目录运行：lua tests/unit/test_combat_events.lua
-- 使用真实技能与怪物配置，在 socket 边界记录 world 发给各玩家的包。
package.path = "./lualib/?.lua;" .. package.path
package.loaded["skynet"] = {now = function() return 0 end}
package.loaded["skynet.socket"] = {}
package.loaded["pb"] = {}
package.loaded["common.logger"] = {
    Warning = function() end,
}
package.loaded["common.config_repository"] = {
    Get = function(name) return require("gamedata.generated." .. name) end,
}

local pids = require "protocol.pids"
local handlers = {}
package.loaded["protocol.protocol_helper"] = {
    RegisterPTCHandler = function(name, handler) handlers[name] = handler end,
    EncodePTCPacket = function(name, msg)
        assert(pids[name], "未定义协议 " .. name)
        return {name = name, msg = msg}
    end,
}

local Scene = require "scene.scene"
local combatAttributes = require "tests.support.combat_attributes"
local PlayerManager = require "world.player.player_manager"
local world = require("world.world_service_handler").CMD
require "world.client_handler"

local function prepareBasicAttack()
    local scene = Scene.new({ID = 1, StartPos = {{0, 0, 0}}})
    scene:LoadGrid(nil)

    local playerUid = 1
    local x, y, z = 0, 0, 0
    scene:Enter(playerUid, x, y, z)
    local caster = assert(scene:GetUnit(playerUid), "施法者未进入场景")
    local monster = assert(scene:AddMonster(1001, x, z), "无法从模板 1001 创建波利")

    assert(combatAttributes(caster).atk == 10 and caster.skillCooldown[1] == nil, "玩家首击输入不符")
    assert(monster.entityId == 1001 and monster.hp == 21 and monster.maxHp == 21
        and combatAttributes(monster).def == 0, "波利模板、初始 HP 或防御不符")
    assert(caster.x == monster.x and caster.y == monster.y and caster.z == monster.z,
        "玩家与目标应在同一点")

    return {
        scene = scene,
        caster = caster,
        monster = monster,
        request = {skillId = 1, skillLevel = 1, targetUid = monster.uid},
        now = 0,
    }
end

do
    -- 对一份刚准备好的输入只施放一次，分别检查返回的命中与持有 HP 的目标对象。
    local function verifyFirstHit(sample)
        local result = sample.scene:CastSkill(sample.caster.uid, sample.request, sample.now)
        assert(result.code == 0, "首次普攻未成功，结果码 " .. tostring(result.code))
        assert(#result.hits == 1, "单体普攻应命中一个目标")
        local hit = result.hits[1]
        assert(hit.uid == sample.monster.uid, "请求命中的不是这次创建的波利")
        assert(hit.damage == 10 and hit.hp == 11 and sample.monster.hp == 11,
            "首击应造成 10 点伤害，命中记录和场景目标都应为 11 HP")
    end

    local runA = prepareBasicAttack()
    local runB = prepareBasicAttack()
    assert(runA.scene ~= runB.scene and runA.caster ~= runB.caster
        and runA.monster ~= runB.monster, "两份样本应各自创建场景和单位")

    verifyFirstHit(runA)
    assert(runB.monster.hp == 21, "打 A 时改变了 B 的初始 HP")
    assert(runB.caster.skillCooldown[1] == nil, "打 A 时改变了 B 玩家的冷却")

    verifyFirstHit(runB)
    assert(runA.monster.hp == 11, "打 B 时又改变了 A 的 HP")
    print(("OK independent first hits (A=%d, B=%d)"):format(runA.monster.hp, runB.monster.hp))
end

-- 为一份普攻样本保存经过的 tick。每次调用先推进指定步数，再用换算后的秒数施法。
local function makeTimedCast(sample)
    local startSeconds = sample.now
    local elapsedTicks = 0

    return function(deltaTicks)
        assert(math.type(deltaTicks) == "integer" and deltaTicks >= 0,
            "请传入非负整数 tick")
        elapsedTicks = elapsedTicks + deltaTicks
        local now = startSeconds + elapsedTicks / 100
        local result = sample.scene:CastSkill(sample.caster.uid, sample.request, now)
        return result, now
    end
end

do
    local sample = prepareBasicAttack()
    local castAfterTicks = makeTimedCast(sample)

    -- 用返回码、场景 HP 和上次成功时间共同判定该次请求的结果。
    local function checkCast(deltaTicks, expectedCode, expectedHp, expectedLastCast)
        local result, now = castAfterTicks(deltaTicks)
        local label = ("t=%.2fs"):format(now)
        local hp = sample.monster.hp
        assert(result.code == expectedCode,
            ("%s 预期结果码 %d，实际 %d"):format(label, expectedCode, result.code))
        assert(hp == expectedHp,
            ("%s 预期目标 HP %d，实际 %d"):format(label, expectedHp, hp))
        assert(sample.caster.skillCooldown[1] == expectedLastCast,
            label .. " 上次成功施法时间不符合预期")

        if expectedCode == 0 then
            assert(#result.hits == 1, label .. " 成功普攻应有一个命中")
            local hit = result.hits[1]
            assert(hit.uid == sample.monster.uid and hit.damage == 10 and hit.hp == hp,
                label .. " 命中目标、伤害或剩余 HP 错误")
        else
            assert(result.damage == 0 and (result.hits == nil or #result.hits == 0),
                label .. " 冷却期间不应产生伤害或命中")
        end
        print(("%s code=%d hp=%d"):format(label, result.code, hp))
    end

    -- 参数依次为：从上次请求起推进的 tick、结果码、剩余 HP、上次成功施法的秒数。
    checkCast(0,  0, 11, 0)
    checkCast(0,  4, 11, 0)
    checkCast(89, 4, 11, 0)
    checkCast(1,  0,  1, 0.90)
end

local scene = Scene.new({ID = 1, StartPos = {{0,0,0}}})
scene:LoadGrid(nil)
local manager = PlayerManager.GetInstance()

-- 创建在线收件人，保留该玩家真实收到的包及顺序。
local function connect(uid)
    local player = {uid = uid, fd = uid, account = tostring(uid), packets = {}}
    function player:SendPackage(packet)
        table.insert(self.packets, packet)
    end
    manager:AddPlayer(uid, player)
    scene:Enter(uid, 0, 0, 0)
    return player
end

-- 从指定收件箱取出一种协议的所有消息。
local function received(player, name)
    local found = {}
    for _, packet in ipairs(player.packets) do
        if packet.name == name then table.insert(found, packet.msg) end
    end
    return found
end

do
    local loader = require "world.player.player_loader"
    local scenes = require("scene.scene_manager").GetInstance()
    local commands = require("scene.scene_service_handler").CMD
    local skynet = require "skynet"
    local previousCall = skynet.call
    local castCalls = 0
    skynet.call = function(address, protocol, command, ...)
        assert(address == ".scene" and protocol == "lua")
        if command == "cast_skill" then castCalls = castCalls + 1 end
        return true, commands[command](...)
    end

    local arena = Scene.new({ID = 1, StartPos = {{0, 0, 0}}})
    arena:LoadGrid(nil)
    local function enter(fd)
        local role = loader.LoadPlayer(fd, tostring(fd))
        role.packets = {}
        function role:SendPackage(packet) table.insert(self.packets, packet) end
        assert(not manager.playersUidMap[role.uid], "两组用例复用了在线 UID " .. role.uid)
        manager:AddPlayer(role.uid, role)
        arena:Enter(role.uid, 0, 0, 0)
        scenes:SetPlayerScene(role.uid, arena)
        return role
    end
    local a, b = enter(501), enter(502)
    local target = assert(arena:AddMonster(1001, 0, 0))
    local function castAtTarget(role, skillId)
        local before = #received(role, "Scene.RespCastSkill")
        handlers["Scene.ReqCastSkill"](role, {skillId = skillId, targetUid = target.uid})
        local replies = received(role, "Scene.RespCastSkill")
        assert(#replies == before + 1, "每个请求应收到一份施法回复")
        return replies[#replies]
    end

    local caster = arena:GetUnit(a.uid)
    local denied = castAtTarget(a, 5)
    assert(denied.code == 9 and denied.targetUid == target.uid and denied.damage == 0
        and denied.targetHp == 0 and #denied.hits == 0, "未学冰箭术应明确拒绝")
    assert(not a:LearnSkill(87654321) and castAtTarget(a, 87654321).code == 9)
    a.learnedSkillLevels[5] = 0  -- 模拟原版的零级候选技能
    assert(castAtTarget(a, 5).code == 9, "零级也应拒绝")
    assert(castCalls == 0 and caster.sp == 100 and target.hp == 21)
    assert(next(caster.skillCooldown) == nil and next(caster.skillGroupReadyAtMs) == nil)
    assert(next(target.hatred) == nil and #b.packets == 0, "拒绝不能产生仇恨或旁观广播")

    assert(a:LearnSkill(5) and a:LearnSkill(5) and a.learnedSkillLevels[5] == 1)
    assert(castAtTarget(b, 5).code == 9 and castCalls == 0, "B 不能借用 A 的冰箭术")
    caster.dead = true
    assert(a:Revive() and arena:GetUnit(a.uid) ~= caster, "复活应重建场景单位")
    local allowed = castAtTarget(a, 5)
    assert(allowed.code == 0 and #allowed.hits == 1 and allowed.damage == 10)
    assert(castCalls == 1 and arena:GetUnit(a.uid).sp == 85 and target.hp == 11)
    local updates = received(b, "Scene.UnitHp")
    assert(#updates == 1 and updates[1].uid == target.uid and updates[1].hp == 11)
    assert(castAtTarget(b, 1).code == 0 and target.hp == 1, "B 的出生普攻应可用")

    for _, role in ipairs({a, b}) do
        scenes:LeaveScene(role.uid)
        manager:RemovePlayer(role.uid)
    end
    do
        local ambush = 500012
        local function replay(fd, rank, damage, hp, sp)
            local role = enter(fd)
            local caster = arena:GetUnit(role.uid)
            local target = assert(arena:AddMonster(1001, 0, 0))
            assert(combatAttributes(caster).atk == 10 and caster.sp == 100
                and target.hp == 21 and combatAttributes(target).def == 0)
            assert(role:LearnSkill(ambush) and role:LearnSkill(ambush, rank))
            assert(role:LearnSkill(ambush))  -- 再次授予一级应保留当前等级

            -- 直接给处理器多塞一个与实学相反的值，核对 world 只信角色记录。
            handlers["Scene.ReqCastSkill"](role, {
                skillId = ambush, targetUid = target.uid, skillLevel = 3 - rank,
            })
            local replies = received(role, "Scene.RespCastSkill")
            assert(#replies == 1 and replies[1].code == 0 and #replies[1].hits == 1)
            local hit = replies[1].hits[1]
            assert(hit.uid == target.uid and hit.damage == damage and hit.hp == hp
                and target.hp == hp and caster.sp == sp,
                ("伏击 Lv%d 实得伤害 %d，目标 HP %d，角色 SP %d")
                    :format(rank, hit.damage, target.hp, caster.sp))

            if rank == 2 then
                assert(not role:LearnSkill(ambush, 11) and role.learnedSkillLevels[ambush] == 2)
                assert(not role:LearnSkill(5, 2), "单级冰箭术没有第二个效果槽")
                local invalid = arena:CastSkill(role.uid, {
                    skillId = ambush, skillLevel = 11, targetUid = target.uid,
                }, 2)
                assert(invalid.code == 9 and target.hp == hp and caster.sp == sp)
                assert(caster.skillCooldown[ambush] == 0 and caster.skillGroupReadyAtMs[1] == 2000)

                -- 模板 9010 的首选技能 200004 是五级，怪物也要带对等级。
                local mob = assert(arena:AddMonster(9010, 0, 0))
                local beforeHp = caster.hp
                assert(mob:TryCastSkills(arena, caster, 2, {}))
                assert(mob.skillCooldown[200004] == 2 and mob.sp == 90 and caster.hp == beforeHp - 122)
                arena:Leave(mob.uid)
            end
            arena:Leave(target.uid)
            scenes:LeaveScene(role.uid)
            manager:RemovePlayer(role.uid)
        end

        replay(601, 1, 16, 5, 88)
        replay(602, 2, 17, 4, 86)
        local config = require "common.skill_config"
        local skills = require("common.config_repository").Get("tbskilltable")
        assert(config.GetEffectId(skills[ambush], 1) == 50001201)
        assert(config.GetEffectId(skills[ambush], 2) == 50001202)
        assert(config.GetEffectId(skills[ambush], 0) == nil)
        assert(config.GetEffectId(skills[10004], 1) == config.GetEffectId(skills[10004], 2)
            and config.GetEffectId(skills[10004], 2) == 1000403)
        print("OK ambush levels: Lv1 damage=16 HP=5 SP=88; Lv2 damage=17 HP=4 SP=86")
    end
    skynet.call = previousCall
    print("OK learned skills: denied before learning, allowed after learning")
end

local player, observer, newcomer = connect(1), connect(2), connect(3)
local first = assert(scene:AddMonster(1001, 0, 0))
local second = assert(scene:AddMonster(1002, 0, 0))
local now = 0
function player:CastSkill(req)
    return scene:CastSkill(self.uid, {
        skillId = req.skillId,
        skillLevel = 1,
        targetUid = req.targetUid,
    }, now)
end
local cast = handlers["Scene.ReqCastSkill"]
cast(player, {skillId = 1, targetUid = first.uid})
local responses = received(player, "Scene.RespCastSkill")
assert(#responses == 1 and responses[1].code == 0 and #responses[1].hits == 1)
assert(responses[1].damage > 0 and first.hp == first.maxHp - responses[1].damage)
assert(first.hatred[player.uid].threat == responses[1].damage)
assert(#received(observer, "Scene.UnitHp") == 1)
cast(player, {skillId = 1, targetUid = first.uid})
assert(received(player, "Scene.RespCastSkill")[2].code == 4)
assert(#received(observer, "Scene.UnitHp") == 1)

now = 1
cast(player, {skillId = 2, targetUid = first.uid})
responses = received(player, "Scene.RespCastSkill")
assert(#responses == 3 and #responses[3].hits == 2 and responses[3].hits[1].uid == first.uid)
assert(first.dead and second.dead and scene:GetUnit(player.uid).sp == 80)
assert(#received(player, "Scene.UnitDead") == 2 and #received(observer, "Scene.UnitDead") == 2)
local rewards = received(player, "Scene.RespExp")
assert(#rewards == 1 and rewards[1].totalJobExp == 77 and rewards[1].totalBaseExp == 95)

-- 怪物也使用相同结算，world 将结果按场景返回的可见范围广播。
local monster = assert(scene:AddMonster(1001, 0, 0))
local aiEvents = {}
local target = scene:GetUnit(observer.uid)
assert(monster:TryCastSkills(scene, target, now, aiEvents))
assert(#aiEvents >= 1 and aiEvents[1].kind == "hp" and target.hp < target.maxHp)
world.scene_events(aiEvents)
local hp = received(observer, "Scene.UnitHp")
assert(hp[#hp].uid == target.uid and hp[#hp].hp == target.hp)

-- 真实配置技能 3 附加 Buff，到期后的移除和重算应按次序送给同一批邻居。
local caster = scene:GetUnit(player.uid)
local endure = {skillId = 3, targetUid = player.uid}
for _, attemptTime in ipairs({1, 2.99}) do
    now = attemptTime
    cast(player, endure)
    local replies = received(player, "Scene.RespCastSkill")
    assert(replies[#replies].code == 4, "怒爆触发的组冷却应拦住霸体")
    assert(caster.sp == 80 and caster.buffs[10201] == nil, "冷却期间不应扣 SP 或附加霸体")
end

now = 3
cast(player, endure)
local replies = received(player, "Scene.RespCastSkill")
assert(replies[#replies].code == 0 and caster.sp == 65, "组冷却到期后霸体应成功并扣 15 SP")

local active = scene:GetUnit(player.uid).buffs[10201]
assert(active and active.expireAt > now)
local expire = {}
scene:UpdateBuffs(active.expireAt, expire)
world.scene_events(expire)
local buffs = received(observer, "Scene.UnitBuff")
assert(#buffs >= 2 and buffs[#buffs].buffId == 10201 and buffs[#buffs].duration == 0)
assert(observer.packets[#observer.packets].name == "Scene.UnitAttr")

-- 同一批事件覆盖持续可见、新进入、离开视野，以及 Buff 到期的有序广播。
player.packets, observer.packets, newcomer.packets = {}, {}, {}
world.scene_events({
    {kind = "move", uid = first.uid, unit = first:Pack(), result = {
        dx = 1, dy = 0, dz = 1, time = 0.3, receivers = {1}, enters = {{uid = 3}}, leaves = {2}}},
    {kind = "buff", uid = 1, buffId = 10201, duration = 0, receivers = {1}},
    {kind = "attr", uid = 1, atk = 10, def = 0, hp = 10, maxHp = 10, sp = 80, maxSp = 100, receivers = {1}},
    {kind = "leave", uid = second.uid, receivers = {2}},
})
assert(#player.packets == 3 and player.packets[1].name == "Scene.RespMove")
assert(player.packets[2].name == "Scene.UnitBuff" and player.packets[3].msg.sp == 80)
assert(#observer.packets == 2 and observer.packets[1].msg.uid == first.uid)
assert(observer.packets[2].name == "Scene.UnitLeave" and observer.packets[2].msg.uid == second.uid)
assert(#newcomer.packets == 1 and newcomer.packets[1].name == "Scene.UnitEnter")
assert(newcomer.packets[1].msg.entityId == 1001 and newcomer.packets[1].msg.uid == first.uid)
print("OK combat and scene events")
