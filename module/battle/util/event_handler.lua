local EventHandler = class("EventHandler")

function EventHandler:Ctor()
    self.handlers = {}
    self.uid = 0
end

function EventHandler:Destroy()
    self.handlers = {}
end

function EventHandler:GetOrCreateEventHandlers(eventId)
    local handlers = self.handlers[eventId]
    if not handlers then
        handlers = {
            longV = 0,
            pEventHandlers = {},
        }
        self.handlers[eventId] = handlers
    end
    return handlers
end

function EventHandler:RegisterEventHandler(eventId, host, handleName, priority)
    return self:RegEventHandlerWithExtraData(eventId, host, handleName, nil, priority)
end

function EventHandler:RegEventHandlerWithExtraData(eventId, host, handleName, extraData, priority)
    local p = priority or 0
    assert(p < 64 and eventId and handleName)
    local handlers = self:GetOrCreateEventHandlers(eventId)
    handlers.longV = handlers.longV | (1 << p)
    local pHandlers = handlers.pEventHandlers[p]
    if not pHandlers then
        pHandlers = {}
        handlers.pEventHandlers[p] = pHandlers
    end
    local uid = self.uid
    self.uid = self.uid + 1
    pHandlers[uid] = { host, handleName, extraData }
    return function()
        local ph = self:GetOrCreateEventHandlers(eventId)
        local eh = ph.pEventHandlers[p]
        if not eh then
            return
        end
        eh[uid] = nil
        if not next(eh) then
            ph.pEventHandlers[p] = nil
            ph.longV = ph.longV & ~(1 << p)
        end
    end
end

local function ctz64(x)
    local r = 63
    x = x & (~x + 1)
    if ((x & 0x00000000FFFFFFFF) ~= 0) then r = r - 32 end
    if ((x & 0x0000FFFF0000FFFF) ~= 0) then r = r - 16 end
    if ((x & 0x00FF00FF00FF00FF) ~= 0) then r = r - 8 end
    if ((x & 0x0F0F0F0F0F0F0F0F) ~= 0) then r = r - 4 end
    if ((x & 0x3333333333333333) ~= 0) then r = r - 2 end
    if ((x & 0x5555555555555555) ~= 0) then r = r - 1 end
    return r
end

local function ffs64(x)
    if x == 0 then
        return 0
    end
    return ctz64(x) + 1
end

function EventHandler:FireEvent(eventId, param)
    local handlers = self.handlers[eventId]
    if not handlers then
        return
    end
    local v = handlers.longV
    repeat
        local idx = ffs64(v) - 1
        v = v & ~(1 << idx)
        local pHandlers = handlers.pEventHandlers[idx]
        if not pHandlers then
            break
        end
        for _, t in pairs(pHandlers) do
            local host, handler, extraData = t[1], t[2], t[3]
            host[handler](host, eventId, param, extraData)
        end
    until v == 0
end

return EventHandler
