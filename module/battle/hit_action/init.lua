local ConfigHelper = require "config.config_helper"
local AttackHitAction = require "hit_action.attack_hit_action"
local HealthHitAction = require "hit_action.health_hit_action"
local ButtleHitAction = require "hit_action.buttle_hit_action"
local BombHitAction = require "hit_action.bomb_hit_action"
local BuffHitAction = require "hit_action.buff_hit_action"

ConfigHelper.RegisterConfigClass("AttackHitAction", AttackHitAction)
ConfigHelper.RegisterConfigClass("HealthHitAction", HealthHitAction)
ConfigHelper.RegisterConfigClass("ButtleHitAction", ButtleHitAction)
ConfigHelper.RegisterConfigClass("BombHitAction", BombHitAction)
ConfigHelper.RegisterConfigClass("BuffHitAction", BuffHitAction)

