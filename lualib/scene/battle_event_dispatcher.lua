local Class = require "common.class"

---@class BattleEventDispatcher
local BattleEventDispatcher = Class("BattleEventDispatcher")

function BattleEventDispatcher:Ctor()
    self.staticListeners = {}
    self.listeners = {}
end

function BattleEventDispatcher:AddStaticListener(eventType, callback)
    local group = self.staticListeners[eventType] or {}
    self.staticListeners[eventType] = group
    table.insert(group, callback)
end

function BattleEventDispatcher:Subscribe(eventType, owner, callback)
    local group = self.listeners[eventType] or {}
    self.listeners[eventType] = group
    group[owner] = callback
end

function BattleEventDispatcher:Unsubscribe(eventType, owner)
    local group = self.listeners[eventType]
    if group then
        group[owner] = nil
    end
end

function BattleEventDispatcher:Dispatch(event)
    local fixed = self.staticListeners[event.type]
    if fixed then
        for i = 1, #fixed do
            fixed[i](event)
        end
    end

    local group = self.listeners[event.type]
    if not group or not next(group) then
        return
    end
    local owners = {}
    for owner in pairs(group) do
        table.insert(owners, owner)
    end
    for _, owner in ipairs(owners) do
        local callback = group[owner]
        if callback then
            callback(event)
        end
    end
end

return BattleEventDispatcher