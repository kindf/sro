-- 第 01–07 课也能单独跑：读取该版本存放最终攻防的对象。
-- 一旦实体具备组件接口，就必须取到它自己的属性组件。
return function(unit)
    if not unit.GetComponent then return unit end
    return assert(unit:GetComponent(require "scene.attribute_component"), "战斗单位缺少属性组件")
end
