require "init"
require "util.tool"
local attackerHeros = require "example.attacker_heros"
local defenderHeros = require "example.defender_heros"
local PvpBattle = require "battle.pvp_battle"

local function PVPBattle()
    local st = os.clock()
    local id = os.time()
    local battle = PvpBattle.new(15, id)
    -- debug模式
    battle:SetDebugger()
    battle:SetCamp(1, 2)
    battle:SetAttackerHeroList(attackerHeros)
    battle:SetDefenderHeroList(defenderHeros)
    battle:Init()
    battle:Run()
    local frameActionList = battle.context.frameActionList
    local isWin = battle:IsWin()
    battle:Destroy()
    local et = os.clock()
    -- local filename = string.format("battle_result/%s.txt", id)
    local filename = "battle_result/battle_result.txt"
    local file, err = io.open(filename, "w")
    if not file then
        print(string.format("创建文件失败: %s", err))
        return false
    end
    file:write(string.format("战斗结束. 结果:%s 耗时:%s\n", isWin and "胜利" or "失败", et - st))
    file:write(table.dump(frameActionList))
    file:close()
    print(string.format("战斗结果已保存到文件: %s", filename))
    return true
end

PVPBattle()
