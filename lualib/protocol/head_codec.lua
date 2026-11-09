-- lualib/protocol/head_codec.lua
-- 客户端协议头编解码。
--
-- 线上格式（长度由 skynet netpack 负责，这里只处理长度之后的 payload）：
--   cmd(4, LE) + flag(1) + [tag(4, LE)] + body
--
-- encode 返回整包：2B 大端长度 + 上面的 payload；发送用 socket.write(fd, packet)。
-- decode 收 netpack 去长度后的 payload，或 (lightuserdata, size)。

local HeadCodec = {}

-- flag 位
local FLAG_RPC = 1
local FLAG_REQUEST = 2
local FLAG_COMPRESS = 4
local FLAG_KEEPALIVE = 16

local netpack

-- 延迟加载 netpack：本地单测没有 skynet 也能跑。
local function getNetpack()
    if netpack == nil then
        local ok, mod = pcall(require, "skynet.netpack")
        netpack = ok and mod or false
    end
    return netpack or nil
end

-- 编码。
-- 参数 body: 包体字符串。
-- 参数 cmd: 协议号，4 字节小端。
-- 参数 flag: 1 字节标志。
-- 参数 tag: RPC 时必填，4 字节小端。
-- 返回：整包字符串；失败 nil, err。
function HeadCodec.Encode(body, cmd, flag, tag)
    body = body or ""
    flag = flag or 0

    if type(cmd) ~= "number" or cmd < 0 or cmd > 0xFFFFFFFF then
        return nil, "invalid cmd"
    end
    if flag < 0 or flag > 0xFF then
        return nil, "invalid flag"
    end
    cmd = math.floor(cmd)
    flag = math.floor(flag)

    local head
    if flag % 2 == FLAG_RPC then
        if type(tag) ~= "number" or tag < 0 or tag > 0xFFFFFFFF then
            return nil, "rpc without valid tag"
        end
        tag = math.floor(tag)
        head = string.pack("<I4I1I4", cmd, flag, tag)
    else
        head = string.pack("<I4I1", cmd, flag)
    end

    local ok, packet = pcall(string.pack, ">s2", head .. body)
    if not ok then
        return nil, "packet too long"
    end
    return packet
end

-- 解码。
-- 参数 buffer: netpack 去长度后的 payload 字符串，或 lightuserdata。
-- 参数 sz: buffer 是 lightuserdata 时必填；是字符串时可省略。
-- 返回：cmd, flag, tag, body；失败 nil, err。
function HeadCodec.Decode(buffer, sz)
    if type(buffer) ~= "string" then
        local np = getNetpack()
        if not np then
            return nil, "netpack unavailable"
        end
        -- tostring 会释放 lightuserdata，调用方不要再使用 buffer
        buffer = np.tostring(buffer, sz)
        sz = nil
    end

    local len = sz or #buffer
    if len < 5 then
        return nil, "packet too short"
    end

    local cmd, flag = string.unpack("<I4I1", buffer)
    local tag, body

    if flag % 2 == FLAG_RPC then
        if len < 9 then
            return nil, "rpc packet too short"
        end
        tag = string.unpack("<I4", buffer, 6)
        body = string.sub(buffer, 10, len)
    else
        body = string.sub(buffer, 6, len)
    end

    return cmd, flag, tag, body
end

HeadCodec.FLAG_RPC = FLAG_RPC
HeadCodec.FLAG_REQUEST = FLAG_REQUEST
HeadCodec.FLAG_COMPRESS = FLAG_COMPRESS
HeadCodec.FLAG_KEEPALIVE = FLAG_KEEPALIVE

return HeadCodec
