local BaseComponent = require "component.base_component"
local Define = require "define.define"
local MoveComponent = class("MoveComponent", BaseComponent)

function MoveComponent:Ctor()
    BaseComponent.Ctor(self)
    self.position = { x = 0, y = 0 }
    self.startPosition = { x = 0, y = 0 }
    self.target = { x = 0, y = 0 }
    self.currentPathLen = 0
    self.currentPathMoved = 0
    self.moving = false
    self.direction = { x = 0, y = 0 }
    self.nextUpdateTime = 0
end

function MoveComponent:_Reset()
    self.startPosition.x = 0
    self.startPosition.y = 0
    self.target.x = 0
    self.target.y = 0
    self.currentPathLen = 0
    self.currentPathMoved = 0
end

function MoveComponent:OnAttach(battle)
    self.position.x = 0
    self.position.y = 0
    self.target.x = 0
    self.target.y = 0
end

function MoveComponent:MoveToPos(battle, x, y)
    local stateComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.MOVE) then
        return false
    end
    self:_Reset()
    self.startPosition.x = self.position.x
    self.startPosition.y = self.position.y
    self.target.x = x
    self.target.y = y
    self.currentPathLen = ((self.position.x - self.target.x) ^ 2 + (self.position.y - self.target.y) ^ 2) ^ 0.5
    self.currentPathMoved = 0
    self.moving = true
    battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_START_MOVE_ACTION, {
        entityId = self.owner:GetId(),
        targetPos = { x = math.floor(x), y = math.floor(y) },
        speed = attrComponent:GetAttr(Define.ENTITY_ATTR.SPEED),
    })
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_START_MOVE_EVENT, self.owner:GetId())
    return true
end

function MoveComponent:SetPosition(x, y)
    self.position.x = x
    self.position.y = y
end

function MoveComponent:SetDirection(x, y)
    self.direction.x = x
    self.direction.y = y
end

function MoveComponent:GetDirection()
    return self.direction
end

function MoveComponent:GetTargetPosition()
    return self.target
end


function MoveComponent:StopAtCurrentPosition(battle, setAction)
    if not self.moving then
        return
    end
    self:_Reset()
    if setAction then
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_STOP_MOVE_ACTION, {
            entityId = self.owner:GetId(),
            currentPos = { x = math.floor(self.position.x), y = math.floor(self.position.y) },
        })
    end
    battle:FireEvent(Define.BATTLE_EVENT.ENTITY_STOP_MOVE_EVENT, self.owner:GetId())
end

function MoveComponent:PostUpdate(battle, dt)
    if not self.moving then
        return
    end
    local eTime = battle:GetExpireTime()
    if self.nextUpdateTime > eTime then
        return
    end
    local stateComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.STATE_COMPONENT)
    if not stateComponent:IsEnable(Define.ENTITY_ABILIT.MOVE) then
        self:StopAtCurrentPosition(battle, true)
        return
    end
    self:_Move(battle, dt)
    -- 20 为经验值
    self.nextUpdateTime = eTime + 20
end

function MoveComponent:_Move(battle, dt)
    local attrComponent = self.owner:GetComponent(Define.COMPONENT_TYPE.ATTR_COMPONENT)
    local speed = attrComponent:GetAttr(Define.ENTITY_ATTR.SPEED)
    if speed <= 0 then
        self.moving = false
        self:_Reset()
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_STOP_MOVE_ACTION, {
            entityId = self.owner:GetId(),
            currentPos = { x = math.floor(self.position.x), y = math.floor(self.position.y) },
        })
        return
    end
    local dist = speed * dt * 0.001
    self.currentPathMoved = self.currentPathMoved + dist
    if self.currentPathMoved >= self.currentPathLen then
        self.moving = false
        self.position.x = self.target.x
        self.position.y = self.target.y
        self:_Reset()
        battle:AddFrameAction(Define.BATTLE_ACTION.ENTITY_STOP_MOVE_ACTION, {
            entityId = self.owner:GetId(),
            currentPos = { x = math.floor(self.position.x), y = math.floor(self.position.y) },
        })
        battle:FireEvent(Define.BATTLE_EVENT.ENTITY_STOP_MOVE_EVENT, self.owner:GetId())
        return
    end

    local percent = self.currentPathMoved / self.currentPathLen
    self.position.x = (1 - percent) * self.startPosition.x + percent * self.target.x
    self.position.y = (1 - percent) * self.startPosition.y + percent * self.target.y
end

function MoveComponent:GetPosition()
    return self.position
end

function MoveComponent:GetTarget()
    return self.target
end

function MoveComponent:IsMoving()
    return self.moving
end

function MoveComponent:Pack(package)
    package.pos = {}
    package.pos.x = self.position.x
    package.pos.y = self.position.y
end

return MoveComponent
