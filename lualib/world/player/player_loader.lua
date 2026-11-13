local Player = require "world.player.player"
local PlayerLoader = {}
local Guid = 1

function PlayerLoader.LoadPlayer(fd, addr)
    local player = Player.new()
    player.fd = fd
    player.account = addr
    player.uid = Guid
    Guid = Guid + 1
    return player
end

return PlayerLoader