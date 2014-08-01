--[[
-- author: xjdrew
-- date: 2014-07-31
--]]

local class      = require "levent.class"
local hub        = require "levent.hub"
local timeout    = require "levent.timeout"
local exceptions = require "levent.exceptions"

--[[
-- A synchronization primitive that allows one coroutine to wake up one or more others.
-- see tests/test_event.lua for example
--]]
local Event = class("Event")

function Event:_init()
    self.links = {}
    self.todo = {}
    self.flag = false
    self.notifier = false
end

function Event:set()
    self.flag = true
    for k,v in pairs(self.links) do
        self.todo[k] = v
    end

    if not self.notifier then
        self.notifier = true
        hub.loop:run_callback(self._notify, self)
    end
end

function Event:clear()
    self.flag = false
end

function Event:wait(sec)
    if self.flag then
        return self.flag
    end

    local t = timeout.start_new(sec)
    local waiter = hub:waiter()
    self.links[waiter] = true
    local ok, val = pcall(waiter.get, waiter)
    self.links[waiter] = nil
    t:cancel()
    if not ok then
        error(val)
    end
    return ok
end

function Event:_notify()
    while true do
        local waiter = next(self.todo)
        if not waiter then
            break
        end
        self.todo[waiter] = nil
        waiter:switch(true)
    end
    self.notifier = false
end

--[[
-- A one-time event that stores a value or an exception.
--]]
local AsyncResult = class("AsyncResult")
function AsyncResult:_init()
    self.links = {}
    self.value = nil
    self.exception = false
end

function AsyncResult:_set(val, exception)
    assert(self.exception == false, "repeated set result")
    self.value = val
    self.exception = exception
    hub.loop:run_callback(self._notify, self)
end

function AsyncResult:set(val)
    self:_set(val, nil)
end

function AsyncResult:set_exception(exception)
    assert(exceptions.is_exception(exception), exception)
    self:_set(nil, exception)
end

function AsyncResult:get(sec)
    if self.exception == false then
        local t = timeout.start_new(sec)
        local waiter = hub:waiter()
        self.links[waiter] = true
        local ok, val = pcall(waiter.get, waiter)
        self.links[waiter] = nil
        t:cancel()
        if not ok then
            error(val)
        end
    end

    if self.exception then
        error(self.exception)
    else
        return self.value
    end
end

function AsyncResult:_notify()
    while true do
        local waiter = next(self.links)
        if not waiter then
            break
        end
        self.links[waiter] = nil
        waiter:switch(true)
    end
end

local event = {}
event.event = Event.new
event.async_result = AsyncResult.new
return event

