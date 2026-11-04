
local BattleContext = class("BattleContext")

function BattleContext:Ctor()
    self.debug = false
    self.frameCount = 0
    self.actionList = {}
    self.frameActionList = {}
    self.currentFrameActions = {}
    self.pass = {}
end

function BattleContext:OnStart()
    self:PushFrameActions()
    self.frameCount = self.frameCount + 1
end

function BattleContext:OnEnd()
    self:PushFrameActions()
    self.frameCount = self.frameCount + 1
end

function BattleContext:OnFrame()
    self:PushFrameActions()
    self.frameCount = self.frameCount + 1
end

function BattleContext:PushFrameActions()
    if #self.currentFrameActions > 0 then
        table.insert(self.frameActionList, {
            frame = self.frameCount,
            frameActions = self.currentFrameActions,
        })
    end
    self.currentFrameActions = {}
end

function BattleContext:GetFrameCount()
    return self.frameCount
end

function BattleContext:AddAction(action)
    table.insert(self.actionList, action)
end

function BattleContext:AddFrameAction(action)
    table.insert(self.currentFrameActions, action)
end

function BattleContext:GetActionList()
    return self.actionList
end

function BattleContext:GetFrameActionList()
    return self.frameActionList
end

return BattleContext
