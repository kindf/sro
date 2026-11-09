local Logger = require "common.logger"
local ProtocolHelper = require "protocol.protocol_helper"

---@param player Player
local function ReqTest(player, req, resp)
    Logger.Info("[ClientHandler]ReqTest: uid:%s, msg:%s", tostring(player.uid), tostring(req.test))
    resp.test = req.test
end
ProtocolHelper.RegisterRpcHandler("test.ReqTest", "test.RespTest", ReqTest)