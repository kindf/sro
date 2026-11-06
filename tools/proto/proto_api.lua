-- proto_api.lua
-- 协议表访问器。纯 Lua 5.1 / LuaJIT / Lua 5.4 兼容，不依赖 bit 库。
--
-- 用法：
--   package.path = package.path .. ";F:/RO/tools/proto/?.lua"
--   local proto = require "proto_api"
--   proto.name(1128751369)        --> "PTCC2G_MOVEOPERATIONREQ"
--   proto.dir(1128751369)         --> "C->G"
--   proto.req(1128751369)         --> "KKSG.MoveInfo"
--   for id, e in proto.iter_gate() do ... end

local map = require "proto_map"

local M = {}

local FLAG_EMPTY = 1
local FLAG_CLIENT = 2
local KIND = { [1] = "ptc", [2] = "rpc" }

-- 预建有序索引，避免每次遍历 1649 条
local all_ids = {}
local client_ids = {}
local gate_ids = {}

for id, e in pairs(map) do
    all_ids[#all_ids + 1] = id
    local flags = e[8]
    if math.floor(flags / FLAG_CLIENT) % 2 == 1 then
        client_ids[#client_ids + 1] = id
        local f, t = e[6], e[7]
        if (f == "C" and (t == "G" or t == "T"))
            or (t == "C" and (f == "G" or f == "T")) then
            gate_ids[#gate_ids + 1] = id
        end
    end
end

table.sort(all_ids)
table.sort(client_ids)
table.sort(gate_ids)

local function entry(id)
    return map[id]
end

function M.get(id)
    return entry(id)
end

function M.exists(id)
    return entry(id) ~= nil
end

function M.name(id)
    local e = entry(id)
    return e and e[1]
end

function M.cls(id)
    local e = entry(id)
    return e and e[2]
end

function M.kind(id)
    local e = entry(id)
    return e and KIND[e[3]]
end

function M.req(id)
    local e = entry(id)
    if not e then return nil end
    return e[4] or nil
end

function M.res(id)
    local e = entry(id)
    if not e then return nil end
    return e[5] or nil
end

function M.from(id)
    local e = entry(id)
    return e and e[6]
end

function M.to(id)
    local e = entry(id)
    return e and e[7]
end

function M.dir(id)
    local e = entry(id)
    return e and (e[6] .. "->" .. e[7])
end

function M.is_empty(id)
    local e = entry(id)
    return e ~= nil and (e[8] % 2 == FLAG_EMPTY)
end

function M.is_client(id)
    local e = entry(id)
    return e ~= nil and math.floor(e[8] / FLAG_CLIENT) % 2 == 1
end

function M.is_gate(id)
    local e = entry(id)
    if not e then return false end
    local f, t = e[6], e[7]
    return (f == "C" and (t == "G" or t == "T"))
        or (t == "C" and (f == "G" or f == "T"))
end

function M.count()
    return #all_ids
end

function M.count_client()
    return #client_ids
end

function M.count_gate()
    return #gate_ids
end

-- 迭代器：for id in proto.iter_all() do ... end
local function make_iter(list)
    local i = 0
    return function()
        i = i + 1
        local id = list[i]
        if id ~= nil then
            return id, map[id]
        end
    end
end

function M.iter_all()
    return make_iter(all_ids)
end

function M.iter_client()
    return make_iter(client_ids)
end

function M.iter_gate()
    return make_iter(gate_ids)
end

function M.stats()
    return {
        total = #all_ids,
        client = #client_ids,
        gate = #gate_ids,
    }
end

return M
