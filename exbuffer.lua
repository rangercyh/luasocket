--[[
使用lpack实现的数据缓冲
]]

require("basefunctions")

local protocol = require("proto")

require("lpack.core")


ENDIAN_BIG = 1
ENDIAN_LITTLE = 2

local Exbuffer = gf_class()

--[[
package bit struct
2 bytes LEN(Big endian) + 2 bytes msgid(Big endian) + body
]]
Exbuffer.PACKAGE_LEN = 2
Exbuffer.MSGID_LEN = 2
Exbuffer.PACKET_MAX_LEN = 2100000000

--[[
为了减少字符串拼接的过程，这里就去掉对小端的设置，默认全部用大端字节流
endian 1 长度、msgid、为大端
       2 小端
]]
function Exbuffer:ctor(endian)
	-- self._endian = endian or ENDIAN_BIG
	self._buf = {}	-- 之后把 buf 弄成字符串优化
	self.offset = 0
end

function Exbuffer:parseMsg(__bytes)
	local msgs = {}
	-- copy bytes to buffer
	print("__bytes = ", string.len(__bytes))
	for i = 1, string.len(__bytes) do
		self._buf[#self._buf + 1] = string.sub(__bytes, i, i)
	end

	while self:getBufferLen() >= self.PACKAGE_LEN do
		local packlen = self:readUShort(self.offset)
		if packlen < self.PACKET_MAX_LEN then
			if (self:getBufferLen() - self.PACKAGE_LEN) >= packlen then
				local msgid = self:readUShort(self.offset + self.PACKAGE_LEN)
				local msg = {}
				msg.id = msgid
				msg.data = self:unpackMsg(msgid)
				msgs[#msgs + 1] = msg
				self.offset = self.offset + self.PACKAGE_LEN + packlen
			end
		else
			print("致命错误，服务端消息长度错误", packlen)
			break
		end
	end

	local leaveLen = self:getBufferLen()
	if leaveLen <= 0 then
		self._buf = {}
	else
		local tmp = {}
		for i = 1, leaveLen do
			tmp[i] = self._buf[self.offset + i]
		end
		self._buf = tmp
	end
	self.offset = 0
	return msgs
end

function Exbuffer:readUShort(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 2), '>H')
	return __v, pos + 2
end

function Exbuffer:readShort(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 2), '>h')
	return __v, pos + 2
end

function Exbuffer:readUInt(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 4), '>I')
	return __v, pos + 4
end

function Exbuffer:readInt(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 4), '>i')
	return __v, pos + 4
end

function Exbuffer:readFloat(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 4), '>f')
	return __v, pos + 4
end

function Exbuffer:readChar(pos)
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 1, pos + 1), 'c')
	return string.char(__v), pos + 1
end

function Exbuffer:readString(pos)
	local _, len = string.unpack(table.concat(self._buf, "", pos + 1, pos + 2), '>H')
	local __, __v = string.unpack(table.concat(self._buf, "", pos + 3, pos + 2 + len), 'A'..len)
	return __v, pos + len + 2
end

function Exbuffer:getBufferLen()
	return #self._buf - self.offset
end

function Exbuffer:packMsg(msgid, data)
	if not(msgid) or not(protocol[msgid]) then
		print("packMsg：msgid错误")
		return nil
	end

	local types = protocol[msgid]["types"]
	local fmt = { '>H', '>H' }
	local len = 0
	local buffer = {}
	for pos, typemark in ipairs(types) do
		if typemark == 'S' then
			fmt[#fmt + 1] = 'HA'
			len = len + string.len(data[pos]) + 2
			buffer[#buffer + 1] = string.len(data[pos])
		elseif typemark == 'h' then
			fmt[#fmt + 1] = '>h'
			len = len + 2
		elseif typemark == 'H' then
			fmt[#fmt + 1] = '>H'
			len = len + 2
		elseif typemark == 'i' then
			fmt[#fmt + 1] = '>i'
			len = len + 4
		elseif typemark == 'I' then
			fmt[#fmt + 1] = '>I'
			len = len + 4
		elseif typemark == 'c' then
			fmt[#fmt + 1] = 'c'
			len = len + 1
		elseif typemark == 'f' then
			fmt[#fmt + 1] = '>f'
			len = len + 4
		end
		buffer[#buffer + 1] = data[pos]
	end

	local packdata = string.pack(table.concat(fmt, ""), len + 2, msgid, unpack(buffer))
	return packdata
end

function Exbuffer:unpackMsg(msgid)
	local data = {}
	if not(msgid) or not(protocol[msgid]) then
		print("unpackMsg：msgid错误", msgid)
	else
		local types = protocol[msgid]["types"]
		local keys = protocol[msgid]["keys"]
		local offset = self.offset + self.PACKAGE_LEN + self.MSGID_LEN
		for pos, typemark in ipairs(types) do
			if typemark == 'S' then
				data[keys[pos]], offset = self:readString(offset)
			elseif typemark == 'h' then
				data[keys[pos]], offset = self:readShort(offset)
			elseif typemark == 'H' then
				data[keys[pos]], offset = self:readUShort(offset)
			elseif typemark == 'i' then
				data[keys[pos]], offset = self:readInt(offset)
			elseif typemark == 'I' then
				data[keys[pos]], offset = self:readUInt(offset)
			elseif typemark == 'c' then
				data[keys[pos]], offset = self:readChar(offset)
			elseif typemark == 'f' then
				data[keys[pos]], offset = self:readFloat(offset)
			end
		end
	end
	return data
end

return Exbuffer

