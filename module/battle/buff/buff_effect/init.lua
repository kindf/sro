local ConfigHelper = require "config.config_helper"
local AddAttr = require "buff.buff_effect.add_attr"
local Bleed = require "buff.buff_effect.bleed"
local Shield = require "buff.buff_effect.shield"
local AddMP = require "buff.buff_effect.add_mp"
local DamageIncrease = require "buff.buff_effect.damage_increase"
local DamageReduction = require "buff.buff_effect.damage_reduction"
local SetAbnormalState = require "buff.buff_effect.set_abnormal_state"

ConfigHelper.RegisterConfigClass("AddAttr", AddAttr)
ConfigHelper.RegisterConfigClass("Bleed", Bleed)
ConfigHelper.RegisterConfigClass("Shield", Shield)
ConfigHelper.RegisterConfigClass("AddMP", AddMP)
ConfigHelper.RegisterConfigClass("DamageIncrease", DamageIncrease)
ConfigHelper.RegisterConfigClass("DamageReduction", DamageReduction)
ConfigHelper.RegisterConfigClass("SetAbnormalState", SetAbnormalState)
