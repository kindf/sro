-- tests/unit/test_head_codec.lua
-- 运行：C:\Users\QQ\Desktop\lua53\lua.exe F:\RO\sro\tests\unit\test_head_codec.lua

package.path = "F:/RO/sro/?.lua;F:/RO/sro/lualib/?.lua;" .. package.path

local HeadCodec = require "protocol.head_codec"

local function fromhex(h)
    h = h:gsub("%s+", "")
    return (h:gsub("%x%x", function(x)
        return string.char(tonumber(x, 16))
    end))
end

local function tohex(s)
    return (s:gsub(".", function(c)
        return string.format("%02X", string.byte(c))
    end))
end

local function check(cond, msg)
    if not cond then
        error("FAIL: " .. msg, 2)
    end
end

-- 1. 移动 PTC
local cmd, flag, tag, body = HeadCodec.Decode(
    fromhex("09 61 47 43 00 01 02 03 04"), 9)
check(cmd == 1128751369, "move cmd")
check(flag == 0, "move flag")
check(tag == nil, "move tag")
check(body == "\1\2\3\4", "move body")

-- 2. 放技能 RPC 请求
cmd, flag, tag, body = HeadCodec.Decode(
    fromhex("ED 52 47 43 03 07 00 00 00"), 9)
check(cmd == 1128747757, "rpc cmd")
check(flag == 3, "rpc flag")
check(tag == 7, "rpc tag")
check(body == "", "rpc body")

-- 3. 心跳
cmd, flag, tag, body = HeadCodec.Decode(fromhex("01 00 47 43 10"), 5)
check(cmd == 1128726529, "keepalive cmd")
check(flag == 16, "keepalive flag")
check(tag == nil, "keepalive tag")
check(body == "", "keepalive body")

-- 4. 压缩 PTC
cmd, flag, tag, body = HeadCodec.Decode(
    fromhex("09 61 47 43 04 78 9C 01"), 8)
check(flag == 4, "compressed flag")
check(body == string.char(0x78, 0x9C, 0x01), "compressed body")

-- 5. encode 移动 PTC
local packet = HeadCodec.Encode("\1\2\3\4", 1128751369, 0)
check(tohex(packet) == "0009096147430001020304", "encode move: " .. tohex(packet))

-- 6. encode RPC 请求
packet = HeadCodec.Encode("", 1128747757, 3, 7)
check(tohex(packet) == "0009ED5247430307000000", "encode rpc: " .. tohex(packet))

-- 7. 往返：最大 tag
local full = HeadCodec.Encode("AB", 1128747757, 1, 0xFFFFFFFF)
cmd, flag, tag, body = HeadCodec.Decode(full:sub(3), #full - 2)
check(cmd == 1128747757, "roundtrip cmd")
check(flag == 1, "roundtrip flag")
check(tag == 0xFFFFFFFF, "roundtrip tag")
check(body == "AB", "roundtrip body")

-- 8. 错误
check(HeadCodec.Decode(fromhex("09 61 47 43"), 4) == nil, "short packet")
check(HeadCodec.Decode(fromhex("ED 52 47 43 03"), 5) == nil, "short rpc")
check(HeadCodec.Encode("", 1, 3) == nil, "rpc without tag")

-- 9. 长度边界
check(HeadCodec.Encode(string.rep("A", 65530), 1, 0) ~= nil, "max ptc body")
check(HeadCodec.Encode(string.rep("A", 65531), 1, 0) == nil, "too long ptc")

print("OK head_codec")
