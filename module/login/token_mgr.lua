local Logger = require "public.logger"
local DEFINE = require "public.define"

local TokenManager = {
    token2Info = {},
    seqCounter = 0,
}

function TokenManager:GetNextSeq()
    self.seqCounter = self.seqCounter + 1
    return self.seqCounter
end

function TokenManager:GenerateToken()
    return string.format("LTK_%d_%d_%d",
        os.time(), math.random(100000, 999999), self:GetNextSeq())
end

function TokenManager:Issue(account, gateNode, gateHost, gatePort)
    local token = self:GenerateToken()
    local info = {
        account = account,
        token = token,
        gateNode = gateNode,
        gateHost = gateHost,
        gatePort = gatePort,
        createTime = os.time(),
        expireTime = os.time() + DEFINE.TOKEN_EXPIRE_TIME,
    }

    self.token2Info[token] = info
    return info
end

function TokenManager:Consume(account, token, gateNode)
    local info = self.token2Info[token]
    if not info then
        return false
    end

    self.token2Info[token] = nil

    if info.account ~= account then
        return false
    end

    if gateNode and info.gateNode ~= gateNode then
        return false
    end

    if os.time() > info.expireTime then
        return false
    end

    return true, info
end

function TokenManager:Cleanup()
    local expired = {}
    local now = os.time()

    for token, info in pairs(self.token2Info) do
        if now > info.expireTime then
            table.insert(expired, token)
        end
    end

    for _, token in ipairs(expired) do
        self.token2Info[token] = nil
    end

    if #expired > 0 then
        Logger.Debug("LoginTokenManager:Cleanup removed %d expired tokens", #expired)
    end
end

return TokenManager
