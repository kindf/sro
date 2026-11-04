local ConfigHelper = require "config.config_helper"
local CircleHitZone = require "hitzone.circle_hitzone"
local RectangleHitZone = require "hitzone.rectangle_hitzone"

ConfigHelper.RegisterConfigClass("CircleHitZone", CircleHitZone)
ConfigHelper.RegisterConfigClass("RectHitZone", RectangleHitZone)
