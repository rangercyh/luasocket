--[[
封装luasocket
]]
require("basefunctions")

local socket = require("socket.core")

local scheduler = require("scheduler")

local Eventprotocol = require("eventprotocol")

local Exbuffer = require("exbuffer")

--状态
local STATUS_CLOSED = "closed"
local STATUS_NOT_CONNECTED = "socket is not connected"
local STATUS_ALREADY_CONNECTED = "already connected"
local STATUS_ALREADY_IN_PROGRESS = "operation already in progress"
local STATUS_TIMEOUT = "timeout"

local SocketTCP = gf_class()
SocketTCP.SOCKET_TICK_TIME = 0.1 			-- check socket data interval
SocketTCP.SOCKET_RECONNECT_TIME = 5			-- socket reconnect try interval
SocketTCP.SOCKET_CONNECT_FAIL_TIMEOUT = 3	-- socket failure timeout
SocketTCP._VERSION = socket._VERSION
SocketTCP._DEBUG = socket._DEBUG
SocketTCP.SOCKET_HEALTH_TIME = 1 * 60

--事件名
SocketTCP.EVENT_DATA = "SOCKET_TCP_DATA"
SocketTCP.EVENT_CLOSE = "SOCKET_TCP_CLOSE"
SocketTCP.EVENT_CLOSED = "SOCKET_TCP_CLOSED"
SocketTCP.EVENT_CONNECTED = "SOCKET_TCP_CONNECTED"
SocketTCP.EVENT_CONNECT_FAILURE = "SOCKET_TCP_CONNECT_FAILURE"

function SocketTCP:ctor(__host, __port, __retryConnectWhenFailure, __endian)
	self.eventprotocol = Eventprotocol.new()
	self.buf = Exbuffer.new(__endian)
    self.host = __host
    self.port = __port
	self.tickScheduler = nil			-- timer for data
	self.reconnectScheduler = nil		-- timer for reconnect
	self.connectTimeTickScheduler = nil	-- timer for connect timeout
	self.tcp = nil
	self.isRetryConnect = __retryConnectWhenFailure
	self.isConnected = false
	self.dataTime = 0

	return self
end

function SocketTCP:setTickTime(__time)
	self.SOCKET_TICK_TIME = __time
	return self
end

function SocketTCP:setReconnTime(__time)
	self.SOCKET_RECONNECT_TIME = __time
	return self
end

function SocketTCP:setConnFailTime(__time)
	self.SOCKET_CONNECT_FAIL_TIMEOUT = __time
	return self
end

function SocketTCP:connect(__host, __port, __retryConnectWhenFailure)
	if __host then
		self.host = __host
	end
	if __port then
		self.port = __port
	end
	if __retryConnectWhenFailure ~= nil then
		self.isRetryConnect = __retryConnectWhenFailure
	end
	assert(self.host or self.port, "Host and port are necessary!")
	self.tcp = socket.tcp()
	self.tcp:settimeout(0)

	local function __checkConnect()
		local __succ = self:_connect()
		if __succ then
			print("连接成功")
			self:_onConnected()
		end
		return __succ
	end

	if not __checkConnect() then
		-- check whether connection is success
		-- the connection is failure if socket isn't connected after SOCKET_CONNECT_FAIL_TIMEOUT seconds
		local __connectTimeTick = function ()
			if self.isConnected then
				return
			end
			self.waitConnect = self.waitConnect or 0
			self.waitConnect = self.waitConnect + self.SOCKET_TICK_TIME
			if self.waitConnect >= self.SOCKET_CONNECT_FAIL_TIMEOUT then
				self.waitConnect = nil
				self:close()
				self:_connectFailure()
				print(self.SOCKET_CONNECT_FAIL_TIMEOUT, " 秒，连接超时，不连了")
				return
			end
			print("请求重连")
			__checkConnect()
		end
		print("间隔 ", self.SOCKET_TICK_TIME, " 秒进行重连")
		self.connectTimeTickScheduler = scheduler.scheduleGlobal(__connectTimeTick, self.SOCKET_TICK_TIME)
	end
end

function SocketTCP:send(__data)
	assert(self.isConnected, " is not connected.")
	self.tcp:send(__data)
	self.dataTime = socket.gettime()
end

function SocketTCP:close( ... )
	self.tcp:close()
	if self.connectTimeTickScheduler then
		scheduler.unscheduleGlobal(self.connectTimeTickScheduler)
	end
	if self.tickScheduler then
		scheduler.unscheduleGlobal(self.tickScheduler)
	end
	self.eventprotocol:dispatchEvent({ name = SocketTCP.EVENT_CLOSE })
end

-- disconnect on user's own initiative.
function SocketTCP:disconnect()
	self:_disconnect()
	self.isRetryConnect = false -- initiative to disconnect, no reconnect.
end

function SocketTCP:parseMsg(__bytes)
	return self.buf:parseMsg(__bytes)
end

--------------------
-- private
--------------------

--- When connect a connected socket server, it will return "already connected"
-- @see: http://lua-users.org/lists/lua-l/2009-10/msg00584.html
function SocketTCP:_connect()
	local __succ, __status = self.tcp:connect(self.host, self.port)
	return __succ == 1 or __status == STATUS_ALREADY_CONNECTED
end

function SocketTCP:_disconnect()
	self.isConnected = false
	self.tcp:shutdown()
	self.eventprotocol:dispatchEvent({ name = SocketTCP.EVENT_CLOSED })
end

function SocketTCP:_onDisconnect()
	self.isConnected = false
	self.eventprotocol:dispatchEvent({ name = SocketTCP.EVENT_CLOSED })
	self:_reconnect()
end

function SocketTCP:_sendHealthPackage()
	if self.isConnected then
		local msgid = 2000
		local data = { self.dataTime }
		print("发送心跳包！", self.dataTime)
		self:send(self.buf:packMsg(msgid, data))
	end
end

-- connecte success, cancel the connection timerout timer
function SocketTCP:_onConnected()
	self.isConnected = true
	self.dataTime = socket.gettime()
	self.eventprotocol:dispatchEvent({ name = SocketTCP.EVENT_CONNECTED })
	if self.connectTimeTickScheduler then
		scheduler.unscheduleGlobal(self.connectTimeTickScheduler)
	end

	local __tick = function()
		while true do
			-- if use "*l" pattern, some buffer will be discarded, why?
			local __body, __status, __partial = self.tcp:receive("*a")	-- read the package body
    	    if __status == STATUS_CLOSED or __status == STATUS_NOT_CONNECTED then
		    	self:close()
		    	if self.isConnected then
		    		self:_onDisconnect()
		    	else
		    		self:_connectFailure()
		    	end
	    	end
		    if (__body and string.len(__body) == 0) or
				(__partial and string.len(__partial) == 0) then
				return
			end
			if __body and __partial then
				__body = __body .. __partial
			end

			local msgs = self.buf:parseMsg(__body or __partial)
			if #msgs > 0 then
				for i = 1, #msgs do
					self.eventprotocol:dispatchEvent({
						name = SocketTCP.EVENT_DATA,
						msgid = msgs[i].id,
						data = msgs[i].data,
					})
				end
			end

			-- 心跳的检测
			if (socket.gettime() - self.dataTime) > self.SOCKET_HEALTH_TIME then
				self:_sendHealthPackage()
			end
		end
	end

	-- 通信测试
	-- self:send(self.buf:packMsg(1000, { "dfasdfasdfasdfasdf" }))
	-- self:send(self.buf:packMsg(1000, { " " }))
	-- self:send(self.buf:packMsg(1000, { " &^$%^#@%!*(#213123125465890@^$(*_)(+>?}" }))
	-- self:send(self.buf:packMsg(1001, { -6497, 123, -54675534, 564767656, -123.4324 }))
	-- self:send(self.buf:packMsg(1002, { string.byte('c') }))
	-- self:send(self.buf:packMsg(1003, { 12314345, "My name is caiyiheng !", 3422 }))
	-- self:send(self.buf:packMsg(1004, { 999999999, string.byte('a'), 1234.436 }))
	-- self:send(self.buf:packMsg(1005, { 999.999, string.byte('s') }))
	-- self:send(self.buf:packMsg(1006, { "asdf", string.byte('x'), "gggg", string.byte('A'), string.byte('B'), "www.baidu.com", "www.google.com", string.byte('z') }))


	-- start to read TCP data
	self.tickScheduler = scheduler.scheduleGlobal(__tick, self.SOCKET_TICK_TIME)
end

function SocketTCP:_connectFailure(status)
	self.eventprotocol:dispatchEvent({ name = SocketTCP.EVENT_CONNECT_FAILURE })
	self:_reconnect()
end

-- if connection is initiative, do not reconnect
function SocketTCP:_reconnect(__immediately)
	if not self.isRetryConnect then
		return
	end
	if __immediately then
		self:connect()
		return
	end
	if self.reconnectScheduler then
		scheduler.unscheduleGlobal(self.reconnectScheduler)
	end
	local __doReConnect = function ()
		self:connect()
	end
	self.reconnectScheduler = scheduler.performWithDelayGlobal(__doReConnect, self.SOCKET_RECONNECT_TIME)
end

return SocketTCP
