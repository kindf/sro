local Define = require("define.define")

local Debugger = class("Debugger")

function Debugger:Ctor(battle)
    self.battle = battle
end

function Debugger:Init()
    local battle = self.battle
    battle:RegisterEventHandler(Define.BATTLE_EVENT.BATTLE_ADD_ENTITY_EVENT, self, "OnAddEntity", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_REMOVE_EVENT, self, "OnRemoveEntity", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_ATTACK_HIT_EVENT, self, "OnAttackHitAction", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_DAMAGE_INFO_EVENT, self, "OnDamage", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_DEAD_EVENT, self, "OnEntityDead", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_START_MOVE_EVENT, self, "OnEntityStartMove", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_STOP_MOVE_EVENT, self, "OnEntityEndMove", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_SPELL_SKILL_EVENT, self, "OnBeforePerformSkill", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_ADD_BUFF_EFFECT_EVENT, self, "OnAddBuffEffect", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_REMOVE_BUFF_EFFECT_EVENT, self, "OnRemoveBuffEffect", 20)
    battle:RegisterEventHandler(Define.BATTLE_EVENT.BATTLE_FRAME_EVENT, self, "OnFrameIncrease", 20)
end

local function Log(...)
    print(string.format(...))
end

function Debugger:OnAddEntity(_, entity)
    Log("添加实体 实体id:%s", entity:GetId())
end

function Debugger:OnRemoveEntity(_, entity)
    Log("删除实体 实体id:%s", entity:GetId())
end

function Debugger:OnAttackHitAction(_, param)
    Log("攻击命中 攻击者id:%s, 技能id:%s, 技能等级:%s, 打击actionIdx:%s, 受击前buffId:%s, 受击后buffId:%s 被攻击者id:%s",
    param.attackerId,
    param.skillId,
    param.skillLevel,
    param.hitActionIdx,
    param.preBuffId,
    param.succBuffId,
    table.concat(param.targetIds, ","))
end

function Debugger:OnDamage(_, param)
    Log("受到伤害 攻击者id:%s, 目标id:%s, 伤害 = %s * %s * %s * (1 - %s) * math_max(0, 1 + %s) * math_max(0, 1 - %s) = %s, 总伤害:%s 实际伤害:%s",
    param.attacker,
    param.target,
    param.attack,
    param.skillDmgRate,
    param.cirtDmgRate,
    param.defSubRate,
    param.addDmg,
    param.subDmg,
    param.formulaDmg,
    param.dmg,
    param.finalDmg)
end

function Debugger:OnEntityDead(_, param)
    Log("实体死亡 实体id:%s", param.entityId)
end

function Debugger:OnFrameIncrease(_, param)
    Log("##################################### 第%s帧开始 #####################################", self.battle.context:GetFrameCount())
end

function Debugger:OnEntityStartMove(_, param)
    local entity = self.battle:GetEntityById(param)
    local pos = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    local targetPos = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetTargetPosition()
    Log("实体开始移动 实体id:%s 当前位置(%s, %s) 目标位置(%s, %s)",
    param,
    pos.x,
    pos.y,
    targetPos.x,
    targetPos.y)
end

function Debugger:OnEntityEndMove(_, param)
    local entity = self.battle:GetEntityById(param)
    local pos = entity:GetComponent(Define.COMPONENT_TYPE.MOVE_COMPONENT):GetPosition()
    Log("实体结束移动 实体id:%s 位置(%s, %s)",
    param,
    pos.x,
    pos.y)
end

function Debugger:OnBeforePerformSkill(_, param)
    local entity = param.performer
    local skillId = param.skillId
    local dur = param.dur
    Log("开始释放技能 实体id:%s 技能id:%s 持续时间:%s", entity:GetId(), skillId, dur)
end

function Debugger:OnAddBuffEffect(_, param)
    local cfg = param.effect:GetCfg()
    Log("添加buff效果 实体id:%s buff配置:%s",
    param.entity:GetId(),
    table.dump(cfg))
end

function Debugger:OnRemoveBuffEffect(_, param)
    local cfg = param.effect:GetCfg()
    Log("删除buff效果 实体id:%s buffId:%s",
    param.entity:GetId(),
    cfg.id)
end

return Debugger
