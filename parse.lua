--[[
使用lpack实现的数据缓冲
]]

require("script/lib/basefunctions")

local protocol = require("script/core/network/proto")

require("lpack.core")
local cjson = require("cjson.core")
local zlib = require("zlib.core")

local Exbuffer = {}

--[[
package bit struct
2 bytes LEN(Big endian) + 2 bytes msgid(Big endian) + body
]]
Exbuffer.PACKAGE_LEN = 2
Exbuffer.MSGID_LEN = 2
Exbuffer.STATUS_LEN = 2
Exbuffer.PACKET_MAX_LEN = 65535

function readUShort(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 2), '>H')
	if status then
		return value, pos + 2
	end
	return nil
end

function readShort(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 2), '>h')
	if status then
		return value, pos + 2
	end
	return nil
end

function readUInt(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 4), '>I')
	if status then
		return value, pos + 4
	end
	return nil
end

function readInt(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 4), '>i')
	if status then
		return value, pos + 4
	end
	return nil
end

function Exbuffer:readFloat(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 4), '>f')
	if status then
		return value, pos + 4
	end
	return nil
end

function readChar(buf, pos)
	local status, _, value = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 1), 'c')
	if status then
		return string.char(value), pos + 1
	end
	return nil
end

function readString(buf, pos)
	local status, _, len = pcall(string.unpack, table.concat(buf, "", pos + 1, pos + 2), '>H')
	if status then
		local ret, _, value = pcall(string.unpack, table.concat(buf, "", pos + 3, pos + 2 + len), 'A'..len)
		if ret then
			return value, pos + len + 2
		end
	end
	return nil
end

function Exbuffer:unpackMsg(buf, msgid)
	local data = {}
	if not(msgid) or not(protocol[msgid]) then
		print("unpackMsg：msgid错误", msgid)
	else
		local types = protocol[msgid]["types"]
		local keys = protocol[msgid]["keys"]
		local offset = self.PACKAGE_LEN + self.MSGID_LEN + self.STATUS_LEN
		for pos, typemark in ipairs(types) do
			if typemark == 'S' then
				data[keys[pos]], offset = readString(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'h' then
				data[keys[pos]], offset = readShort(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'H' then
				data[keys[pos]], offset = readUShort(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'i' then
				data[keys[pos]], offset = readInt(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'I' then
				data[keys[pos]], offset = readUInt(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'c' then
				data[keys[pos]], offset = readChar(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			elseif typemark == 'f' then
				data[keys[pos]], offset = readFloat(buf, offset)
				if not(data[keys[pos]]) then
					print('unpackMsg：解析错误', keys[pos])
					return {}
				end
			end
		end
	end
	return data
end

function Exbuffer:parseMsg(tbBytes)
	local buf = {}
	-- copy bytes to buffer
	for i = 1, #tbBytes do
		buf[#buf + 1] = string.char(tbBytes[i])
	end

	local packlen = readUShort(buf, 0)
	if packlen and (packlen < self.PACKET_MAX_LEN) then
		if (#buf - self.PACKAGE_LEN) >= packlen then
			local msgid = readUShort(buf, self.PACKAGE_LEN)
			if not(msgid) then
				print("解析msgid错误")
				return nil
			end
			local status = readUShort(buf, self.PACKAGE_LEN + self.MSGID_LEN)
			if status ~= 600 then
				print("status = ", status)
				return nil
			end
			local msg = {}
			msg.id = msgid
			msg.data = self:unpackMsg(buf, msgid)
			return msg
		end
	end
	print("服务端消息解析错误")
	return nil
end

function Exbuffer:packMsg(msgid, data)
	if not(msgid) or not(protocol[msgid]) then
		print("packMsg：msgid错误")
		return nil
	end

	local types = protocol[msgid]["types"]
	local keys = protocol[msgid]["keys"]
	local fmt = { '>H', '>H' }
	local len = 0
	local buffer = {}
	for pos, typemark in ipairs(types) do
		if not (data[keys[pos]]) then
			return nil
		end
		if typemark == 'S' then
			fmt[#fmt + 1] = 'HA'
			len = len + string.len(data[keys[pos]]) + 2
			buffer[#buffer + 1] = string.len(data[keys[pos]])
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
		buffer[#buffer + 1] = data[keys[pos]]
	end

	local status, content = pcall(string.pack, table.concat(fmt, ""), len + 2, msgid, unpack(buffer))
	if status then
		return content
	end
	return nil
end

return Exbuffer

