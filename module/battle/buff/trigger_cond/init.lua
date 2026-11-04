
local ConfigHelper = require "config.config_helper"
local EffectTriggerCondCareer = require "buff.trigger_cond.career_cond"
local EffectTriggerCondSex = require "buff.trigger_cond.sex_cond"
local EffectTriggerCondNone = require "buff.trigger_cond.none_cond"

ConfigHelper.RegisterConfigClass("EffectTriggerCondCareer", EffectTriggerCondCareer)
ConfigHelper.RegisterConfigClass("EffectTriggerCondSex", EffectTriggerCondSex)
ConfigHelper.RegisterConfigClass("EffectTriggerCondNone", EffectTriggerCondNone)
