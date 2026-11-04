local Define = require "define.define"
local BattleContext = require "context.battle_context"
local EventHandler = require "util.event_handler"
local Debugger = require "debug.debugger"

local BattleBase = class("BattleBase")

function BattleBase:Ctor(frame, battleId, battleType)
    self.battleId = battleId     -- 战斗id
    self.battleType = battleType -- 战斗类型
    self.frame = frame           -- 帧
    self.dt = 1000 / self.frame  -- 帧间隔
    self.seed = os.time()        -- 随机种子
    self.originEntityId = 0      -- 实体id起始值

    self.entities = {}           -- 所有实体
    self.entityByType = {}       -- 按类型分组的实体
    self.updateEntities = {}     -- 需要更新的实体
    self.waitAddEntities = {}    -- 等待添加的实体
    self.waitRemoveEntities = {} -- 等待移除的实体
    self.waitAddSpawns = {}      -- 等待添加的spawn
    self.spawns = {}             -- 所有spawn

    self.frameTrigger = {}       -- 帧触发函数
    self.context = BattleContext.new()
    self.eventHandler = EventHandler.new()
    self.debugger = nil
end

function BattleBase:GenerateEntityId()
    self.originEntityId = self.originEntityId + 1
    return self.originEntityId
end

function BattleBase:_AddEntity(entity)
    self.entities[entity:GetId()] = entity
    local entityAllTypes = entity:GetEntityAllTypes()
    for _, v in ipairs(entityAllTypes) do
        self.entityByType[v] = self.entityByType[v] or {}
        table.insert(self.entityByType[v], entity)
    end
    if entity.Update then
        self.updateEntities[entity:GetId()] = entity
    end
    entity:OnEnter()
    self:FireEvent(Define.BATTLE_EVENT.BATTLE_ADD_ENTITY_EVENT, entity)
    self:_OnEntityAdd(entity)

    local action = entity:Pack()
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_ADD_ENTITY_ACTION, action)
end

function BattleBase:AddEntity(entity)
    self.waitAddEntities[entity:GetId()] = entity
end

function BattleBase:_OnEntityAdd(entity)
end

function BattleBase:_OnEntityRemove(_)
end

function BattleBase:RemoveEntity(entity)
    local entityId = entity:GetId()
    local entityAllTypes = entity:GetEntityAllTypes()
    for _, v in ipairs(entityAllTypes) do
        if self.entityByType[v] then
            self.entityByType[v][entityId] = nil
        end
    end
    self.entities[entityId] = nil
    self.waitRemoveEntities[entityId] = entity
    entity:OnLeave()
end

function BattleBase:Init(cfg)
    self:_OnInit(cfg)
    self:RegisterEventHandler(Define.BATTLE_EVENT.ENTITY_DEAD_EVENT, self, "_OnEntityDeadEvent", 10)
end

function BattleBase:_OnEntityDeadEvent(_, param)
    local entity = self:GetEntityById(param.entityId)
    if entity then
        self:RemoveEntity(entity)
    end
end

function BattleBase:_RemoveEntity(entity)
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_REMOVE_ENTITY_ACTION, {
        entityId = entity:GetId(),
    })
    if entity.Update then
        self.updateEntities[entity:GetId()] = nil
    end
    self:_OnEntityRemove(entity)
    self:FireEvent(Define.BATTLE_EVENT.ENTITY_REMOVE_EVENT, entity)
    entity:Destroy()
end

function BattleBase:RegisterEventHandler(eventType, target, handler, priority)
    self.eventHandler:RegisterEventHandler(eventType, target, handler, priority)
end

function BattleBase:FireEvent(eventType, param)
    self.eventHandler:FireEvent(eventType, param)
end

function BattleBase:_OnInit(_)
end

function BattleBase:OnDestroy()
end

function BattleBase:Destroy()
    self:_OnDestroy()
end

function BattleBase:_UpdateSpawns(dt)
    local remove = {}
    for k, v in pairs(self.spawns) do
        if v:Update(self, dt) then
            remove[k] = v
        end
    end

    for k, v in pairs(remove) do
        v:OnLeaveScene(self)
        self.spawns[k] = nil
    end
end

function BattleBase:_OnRun()
    local dt = self.dt
    -- local startTime = os.clock()
    while true do
        self:FireEvent(Define.BATTLE_EVENT.BATTLE_FRAME_EVENT, self.context:GetFrameCount())
        for k, v in pairs(self.waitAddEntities) do
            self:_AddEntity(v)
            self.waitAddEntities[k] = nil
        end
        for k, v in pairs(self.waitRemoveEntities) do
            self:_RemoveEntity(v)
            self.waitRemoveEntities[k] = nil
        end

        for k, v in pairs(self.waitAddSpawns) do
            self:_AddSpawnObj(v)
            self.waitAddSpawns[k] = nil
        end
        self.waitAddSpawns = {}

        self:_ProcessFrameTrigger()
        self:_OnFrame()

        for _, v in pairs(self.updateEntities) do
            v:Update(self, dt)
        end

        self:_UpdateSpawns(dt)

        for _, v in pairs(self.updateEntities) do
            v:PostUpdate(self, dt)
        end

        self.context:OnFrame()
        if self:_CheckEnd() then
            break
        end
    end
end

function BattleBase:_OnFrame()
end

function BattleBase:_ProcessFrameTrigger()
    local frame = self.context:GetFrameCount()
    local handlers = self.frameTrigger[frame]
    if not handlers then
        return
    end
    for _, v in pairs(handlers) do
        v(self)
    end
    self.frameTrigger[frame] = nil
end

function BattleBase:_AddSpawnObj(spawn)
    self.spawns[spawn:GetId()] = spawn
    spawn:OnEnterScene(self)
end

function BattleBase:AddSpawn(spawn)
    assert(spawn.Update, "加入的 spawn 必须实现 Update 方法")
    self.waitAddSpawns[spawn:GetId()] = spawn
    return true
end

function BattleBase:_CheckEnd()
    self.frameCount = (self.frameCount or 0) + 1
    return self.frameCount >= 1000
end

function BattleBase:_OnEnd()
end

function BattleBase:AddFrameTrigger(frame, handler)
    local handlerList = self.frameTrigger[frame] or {}
    table.insert(handlerList, handler)
    self.frameTrigger[frame] = handlerList
end

function BattleBase:GetAllEntity()
    return self.entities
end

function BattleBase:GetEntityByType(entityType)
    return self.entityByType[entityType]
end

function BattleBase:GetEntityById(entityId)
    return self.entities[entityId]
end

function BattleBase:_Start()
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_DETAIL_ACTION, {
        frame = self.frame,
        seed = self.seed,
        battleId = self.battleId,
        battleType = self.battleType
    })
    self:_OnStart()
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_READY_ACTION, {})
    self.context:OnStart()
    local nextFrame = self.context:GetFrameCount()
    self:AddFrameTrigger(nextFrame, function()
        for _, v in pairs(self.entities) do
            v:FireEvent(Define.BATTLE_EVENT.BATTLE_START_EVENT, {battle = self})
        end
    end)
end

function BattleBase:_OnStart()
end

function BattleBase:_OnDestroy()
end

function BattleBase:_End()
    self:AddFrameAction(Define.BATTLE_ACTION.BATTLE_END_ACTION, {})
    self:_OnEnd()
    self.context:OnEnd()
end

function BattleBase:Run()
    self:_Start()
    self:_OnRun()
    self:_End()
end

function BattleBase:AddFrameAction(actionId, action)
    self.context:AddFrameAction({
        actionId = actionId,
        action = action
    })
end

function BattleBase:GetExpireTime()
    return self.dt * self.context:GetFrameCount()
end

function BattleBase:SetDebugger()
    self.debugger = Debugger.new(self)
    self.debugger:Init()
end

return BattleBase
