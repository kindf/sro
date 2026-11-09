local Player = require "world.player.player"
local PlayerLoader = {}

function PlayerLoader.LoadPlayer(fd, addr)
    local player = Player.new()
    player.fd = fd
    player.account = addr
    player.uid = os.time() -- 这里使用时间戳作为uid，实际应用中应该使用更合适的方式生成唯一的uid
    return player
end

return PlayerLoader