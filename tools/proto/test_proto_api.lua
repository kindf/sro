-- test_proto_api.lua
-- 用 LuaJIT 跑：luajit64.exe test_proto_api.lua
-- 验证 proto_map.lua 能加载、关键条目正确、遍历数量一致。

-- 以脚本所在目录为模块目录，避免硬编码路径
local _src = debug.getinfo(1, "S").source
local _dir = _src:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
package.path = package.path .. ";" .. _dir .. "/?.lua;./?.lua"

local api = require "proto_api"

local function check(cond, msg)
    if not cond then
        error("FAIL: " .. msg, 2)
    end
end

-- 1. 总量
check(api.count() == 1649, "total should be 1649, got " .. api.count())
check(api.count_client() == 978, "client should be 978, got " .. api.count_client())
check(api.count_gate() == 609, "gate should be 609, got " .. api.count_gate())

-- 2. 移动协议
local move_id = 1128751369
check(api.name(move_id) == "PTCC2G_MOVEOPERATIONREQ", "move name")
check(api.dir(move_id) == "C->G", "move dir")
check(api.req(move_id) == "KKSG.MoveInfo", "move req")
check(api.kind(move_id) == "ptc", "move kind")
check(api.is_gate(move_id), "move is gate")
check(not api.is_empty(move_id), "move not empty")

-- 3. 空包
local ping_id = 1129623050
check(api.name(ping_id) == "PTCC2T_KEEPALIVEPINGACK", "ping name")
check(api.is_empty(ping_id), "ping is empty")
check(api.req(ping_id) == nil, "ping req nil")

-- 4. 老协议（id 不编码方向，靠名字前缀）
local legacy_id = 7369
check(api.name(legacy_id) == "PTCG2C_SKILLRESULT", "legacy name")
check(api.dir(legacy_id) == "G->C", "legacy dir")

-- 5. 遍历
local n = 0
for _ in api.iter_client() do n = n + 1 end
check(n == 978, "iter_client count")

local m = 0
for _ in api.iter_gate() do m = m + 1 end
check(m == 609, "iter_gate count")

print(string.format("OK total=%d client=%d gate=%d", api.count(), api.count_client(), api.count_gate()))
