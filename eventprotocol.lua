--[[
事件处理器
]]
require("basefunctions")

local EventProtocol = gf_class()

function EventProtocol:ctor()
    self.listeners_ = {}
    self.nextListenerHandleIndex_ = 0
end

function EventProtocol:addEventListener(eventName, listener)
    assert(type(eventName) == "string" and eventName ~= "", "EventProtocol:addEventListener() - invalid eventName")
    eventName = string.upper(eventName)
    if self.listeners_[eventName] == nil then
        self.listeners_[eventName] = {}
    end

    self.nextListenerHandleIndex_ = self.nextListenerHandleIndex_ + 1
    local handle = tostring(self.nextListenerHandleIndex_)
    self.listeners_[eventName][handle] = listener

    return handle
end

function EventProtocol:removeEventListenersByEvent(eventName)
    self.listeners_[string.upper(eventName)] = nil
end

function EventProtocol:removeEventListener(handleToRemove)
    for eventName, listenersForEvent in pairs(self.listeners_) do
        for handle, _ in pairs(listenersForEvent) do
            if handle == handleToRemove then
                listenersForEvent[handle] = nil
            end
        end
    end
end

function EventProtocol:removeAllEventListeners()
    self.listeners_ = {}
end

function EventProtocol:hasEventListener(eventName)
    eventName = string.upper(tostring(eventName))
    local t = self.listeners_[eventName]
    for _, __ in pairs(t) do
        return true
    end
    return false
end

function EventProtocol:dispatchEvent(event)
    event.name = string.upper(tostring(event.name))
    local eventName = event.name

    if self.listeners_[eventName] == nil then
        return
    end
    event.stop_ = false
    event.stop = function(self)
        self.stop_ = true
    end

    for handle, listener in pairs(self.listeners_[eventName]) do
        listener(event)
        if event.stop_ then
            break
        end
    end
end

return EventProtocol
