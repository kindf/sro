local Define = {}

-- 实体类型
Define.ENTITY_TYPE = {
    ENTITY = 1,  -- 实体基类
    HERO = 2,    -- 英雄实体
    MONSTER = 3, -- 怪物实体
}

-- 组件类型
Define.COMPONENT_TYPE = {
    STATE_COMPONENT = 1, -- 状态组件
    FIGHT_COMPONENT = 2, -- 战斗组件
    BUFF_COMPONENT = 3,  -- BUFF组件
    SKILL_COMPONENT = 4, -- 技能组件
    ATTR_COMPONENT = 5,  -- 属性组件
    MOVE_COMPONENT = 6,  -- 移动组件
    AI_COMPONENT = 7,    -- AI组件
}

-- 性别
Define.SEX = {
    MALE = 1,   -- 男
    FEMALE = 2, -- 女
}

-- 职业
Define.CAREER = {
}

-- 实体注册的组件
Define.ENTITY_REGISTER_COMPONENT = {
    [Define.ENTITY_TYPE.HERO] = {
        Define.COMPONENT_TYPE.BUFF_COMPONENT,
        Define.COMPONENT_TYPE.ATTR_COMPONENT,
        Define.COMPONENT_TYPE.FIGHT_COMPONENT,
        Define.COMPONENT_TYPE.STATE_COMPONENT,
        Define.COMPONENT_TYPE.SKILL_COMPONENT,
        Define.COMPONENT_TYPE.MOVE_COMPONENT,
        Define.COMPONENT_TYPE.AI_COMPONENT,
    },
}

-- 实体组件更新顺序
Define.ENTITY_COMPONENT_UPDATE_ORDER = {
    [Define.ENTITY_TYPE.HERO] = {
        Define.COMPONENT_TYPE.BUFF_COMPONENT,
        Define.COMPONENT_TYPE.ATTR_COMPONENT,
        Define.COMPONENT_TYPE.FIGHT_COMPONENT,
        Define.COMPONENT_TYPE.STATE_COMPONENT,
        Define.COMPONENT_TYPE.SKILL_COMPONENT,
    },
}

-- 实体组件后更新顺序
Define.ENTITY_COMPONENT_POST_UPDATE_ORDER = {
    [Define.ENTITY_TYPE.HERO] = {
        Define.COMPONENT_TYPE.SKILL_COMPONENT,
        Define.COMPONENT_TYPE.MOVE_COMPONENT,
        Define.COMPONENT_TYPE.AI_COMPONENT,
    },
}

-- 战斗事件定义
Define.BATTLE_EVENT = {
    ENTITY_DEAD_EVENT = 1,                    -- 实体死亡
    BATTLE_FRAME_EVENT = 2,                   -- 战斗帧
    ENTITY_START_MOVE_EVENT = 3,              -- 实体开始移动
    ENTITY_STOP_MOVE_EVENT = 4,               -- 实体停止移动
    ENTITY_BEFORE_PERFORM_SKILL_EVENT = 5,    -- 实体准备释放技能
    ENTITY_AFTER_PERFORM_SKILL_EVENT = 6,     -- 实体释放技能后
    ENTITY_BEFORE_BE_PERFORM_SKILL_EVENT = 7, -- 实体被准备释放技能
    ENTITY_AFTER_BE_PERFORM_SKILL_EVENT = 8,  -- 实体被释放技能后
    ENTITY_SPELL_SKILL_EVENT = 9,             -- 实体释放技能
    ENTITY_ATTACK_HIT_EVENT = 10,             -- 实体攻击命中
    ENTITY_BEFORE_ATTACK_EVENT = 11,          -- 实体准备攻击
    ENTITY_BEFORE_BE_ATTACK_EVENT = 12,       -- 实体被准备攻击
    ENTITY_BEFORE_DO_DAMAGE_EVENT = 13,       -- 实体准备造成伤害
    ENTITY_BEFORE_DAMAGE_EVENT = 14,          -- 实体受到伤害前
    ENTITY_DAMAGE_INFO_EVENT = 15,            -- 实体伤害信息
    ENTITY_HEALTH_INFO_EVENT = 16,            -- 实体治疗信息
    ENTITY_ADD_BUFF_EFFECT_EVENT = 17,        -- 添加BUFF效果
    ENTITY_REMOVE_BUFF_EFFECT_EVENT = 18,     -- 移除BUFF效果
    ENTITY_AFTER_BORN_EVENT = 19,             -- 实体出生
    BATTLE_START_EVENT = 20,                  -- 战斗开始
    ENTITY_REMOVE_EVENT = 21,                 -- 移除实体
    BATTLE_ADD_ENTITY_EVENT = 22,             -- 添加实体

}

-- 战斗action
-- Define.BATTLE_ACTION = {
--     BATTLE_DETAIL_ACTION = 1,              -- 战斗详情
--     BATTLE_READY_ACTION = 2,               -- 战斗准备
--     BATTLE_START_ACTION = 3,               -- 战斗开始
--     BATTLE_END_ACTION = 4,                 -- 战斗结束
--     ENTITY_START_MOVE_ACTION = 5,          -- 开始移动
--     ENTITY_STOP_MOVE_ACTION = 6,           -- 停止移动
--     ENTITY_PERFORM_SKILL_ACTION = 7,       -- 实体释放技能
--     ENTITY_UPDATE_HP_ACTION = 8,           -- 更新实体生命
--     ENTITY_UPDATE_MAX_HP_ACTION = 9,       -- 更新实体最大生命
--     ENTITY_UPDATE_MP_ACTION = 10,          -- 更新实体魔法
--     ENTITY_UPDATE_MAX_MP_ACTION = 11,      -- 更新实体最大魔法
--     ENTITY_ATTACK_HIT_ACTION = 12,         -- 实体攻击命中
--     ENTITY_BE_ATTACKED_HIT_ACTION = 13,    -- 实体被攻击命中
--     ENTITY_HEALTH_ACTION = 14,             -- 实体治疗
--     BATTLE_ADD_BUTTLE_ACTION = 15,         -- 添加子弹
--     BATTLE_REMOVE_BUTTLE_ACTION = 16,      -- 移除子弹
--     BATTLE_ADD_BOMB_ACTION = 17,           -- 添加爆炸
--     ENTITY_ADD_BUFF_EFFECT_ACTION = 18,    -- 添加BUFF效果
--     ENTITY_UPDATE_BUFF_EFFECT_ACTION = 19, -- 更新BUFF效果
--     ENTITY_REMOVE_BUFF_EFFECT_ACTION = 20, -- 移除BUFF效果
--     ENTITY_ADD_BUFF_ACTION = 21,           -- 添加BUFF
--     BATTLE_INIT_FORMATION_ACTION = 22,     -- 初始化阵型
--     BATTLE_REMOVE_ENTITY_ACTION = 23,      -- 移除实体
-- }
Define.BATTLE_ACTION = {
    BATTLE_DETAIL_ACTION = "战斗详情",
    BATTLE_READY_ACTION = "战斗准备",
    BATTLE_START_ACTION = "战斗开始",
    BATTLE_END_ACTION = "战斗结束",
    ENTITY_START_MOVE_ACTION = "开始移动",
    ENTITY_STOP_MOVE_ACTION = "停止移动",
    ENTITY_PERFORM_SKILL_ACTION = "实体释放技能",
    ENTITY_UPDATE_HP_ACTION = "更新实体生命",
    ENTITY_UPDATE_MAX_HP_ACTION = "更新实体最大生命",
    ENTITY_UPDATE_MP_ACTION = "更新实体MP",
    ENTITY_UPDATE_MAX_MP_ACTION = "更新实体最大MP",
    ENTITY_ATTACK_HIT_ACTION = "实体攻击命中",
    ENTITY_BE_ATTACKED_HIT_ACTION = "实体被攻击命中",
    ENTITY_HEALTH_ACTION = "实体治疗",
    BATTLE_ADD_BUTTLE_ACTION = "添加子弹",
    BATTLE_REMOVE_BUTTLE_ACTION = "移除子弹",
    BATTLE_ADD_BOMB_ACTION = "添加爆炸",
    ENTITY_ADD_BUFF_EFFECT_ACTION = "添加BUFF效果",
    ENTITY_UPDATE_BUFF_EFFECT_ACTION = "更新BUFF效果",
    ENTITY_REMOVE_BUFF_EFFECT_ACTION = "移除BUFF效果",
    ENTITY_ADD_BUFF_ACTION = "添加BUFF",
    BATTLE_INIT_FORMATION_ACTION = "初始化阵型",
    BATTLE_REMOVE_ENTITY_ACTION = "移除实体",
    BATTLE_ADD_ENTITY_ACTION = "添加实体",
}

-- 实体能力
Define.ENTITY_ABILIT = {
    MOVE = 1,          -- 移动
    NORMAL_ATTACK = 2, -- 普通攻击
    SKILL_ATTACK = 3,  -- 技能攻击
    BE_TARGET = 4,     -- 被攻击
    BE_DAMAGE = 5,     -- 受到伤害
    BE_HEAL = 6,       -- 受到治疗
    AI = 7,            -- AI
    MAX = 7,
}

-- 实体属性
Define.ENTITY_ATTR = {
    MAX_HP = 1,           -- 最大生命
    ATT = 2,              -- 攻击
    DEF = 3,              -- 防御
    CRIT = 4,             -- 暴击
    CRIT_DAMAGE = 5,      -- 暴击伤害
    ADD_DAM = 6,          -- 加伤
    SUB_DAM = 7,          -- 减伤
    SPEED = 8,            -- 移动速度
    ATTACK_SPEED = 9,     -- 攻击速度
    MAX_MP = 12,          -- 最大魔法
    CURE_RATIO = 14,      -- 治疗效果
    CRIT_ADD = 15,        -- 暴击加成
    CRIT_DAMAGE_ADD = 16, -- 暴击伤害加成
    MAX_BASE_ATTR = 1000, -- 最大基础属性
    HP_RATIO = 1001,      -- 生命百分比
    ATT_RATIO = 1002,     -- 攻击百分比
    DEF_RATIO = 1003,     -- 防御百分比
    MSPEED_RATIO = 1008,  -- 移动速度百分比
    ASPEED_RATIO = 1009,  -- 攻击速度百分比
}

-- 实体状态
Define.ENTITY_STATE = {
    SKILL_STATE = 1,        -- 技能状态
    NORMAL_SKILL_STATE = 2, -- 普通攻击
}

-- 实体战斗状态
Define.ENTITY_BATTLE_STATE = {
    NORMAL_STATE = 0,  -- 普通状态
    DEAD_STATE = 1,    -- 死亡
    REMOVED_STATE = 2, -- 已移除
}

-- 实体关系
Define.ENTITY_RELATION_TYPE = {
    SELF = 1,    -- 自己
    ENEMIES = 2, -- 敌方
    FRIENDS = 3, -- 友方
    OTHERS = 4,  -- 出自己外其他
    ALL = 5,     -- 所有
    CAMP = 6,    -- 同阵营
}

-- 爆炸目标
Define.BOMB_TARGET_TYPE = {
    SELF = 1,   -- 自己
    TARGET = 2, -- 目标
}

Define.BUFF_EFFECT_TRIGGER_COND_TARGET_TYPE = {
    SELF = 1,     -- 自己
    ATTACKER = 2, -- 攻击者
    DEFENDER = 3, -- 防御者
}

Define.ENTITY_ATTR_SOURCE = {
    BASE = 1, -- 基础
    BUFF = 2, -- BUFF
}

Define.FSM_STATE = {
    SEARCH_TARGET_STATE = 1, -- 搜索目标状态
    MOVE_STATE = 2,          -- 移动状态
    ATTACK_STATE = 3,        -- 攻击状态
}

-- 技能目标
Define.SKILL_APPOINT_TYPE = {
    MOST_ATTACK = 0,  -- 最高攻击者
    LEAST_ATTACK = 1, -- 最低攻击者
    LEAST_HP = 2,     -- 最低生命者
    MOST_HP = 3,      -- 最高生命者
    LEAST_DEF = 4,    -- 最低防御者
    MOST_DEF = 5,     -- 最高防御者
    FARTHEST = 6,     -- 最远距离者
    CLOSEST = 7,      -- 最近距离者
}

return Define
