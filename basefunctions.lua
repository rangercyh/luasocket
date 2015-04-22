--创建一个类，暂时不支持继承，继承方法参照quick的class函数
--[[
添加一个new方法
使用它的类可以把初始化操作放进 ctor 函数里，会自动调用
]]
function gf_class()
    local cls = { ctor = function() end }
    cls.__index = cls

    function cls.new(...)
        local instance = setmetatable({}, cls)
        instance:ctor(...)
        return instance
    end

    return cls
end
