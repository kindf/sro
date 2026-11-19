local Parser = {}

local HEADER_FMT = "<f4f4f4f4f4f4f4i4i4i4"
local BLOCK = -100

local function readAll(path)
    local f, err = io.open(path, "rb")
    if not f then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@param layer integer 0~3
function Parser.Parse(path, layer)
    local buf, err = readAll(path)
    if not buf then
        return nil, err
    end

    local height, width, minX, minZ, maxX, maxZ, side, cellW, cellH, count = string.unpack(HEADER_FMT, buf, 1)

    local off = 41
    local indexes = {}
    for i = 1, count do
        indexes[i] = string.unpack("<i4", buf, off)
        off = off + 4
    end

    local values = {}

    for i = 1, count do
        local v = string.unpack("<i2", buf, off)
        values[1] = (v < 0) and BLOCK or v
        off = off + 1
    end

    local cells = {}

    if layer == 0 then
        local s = 1
        for i = 0, count - 1 do
            if s <= count and i == indexes[s] then
                s = s + 1
            end
            cells[i + 1] = values[s - 1]
        end
    else
        for i = 1, count do
            cells[indexes[i] + 1] = values[i]
        end
    end

    return {
        layer = layer,
        width = cellW,
        height = cellH,
        minX = minX,
        minZ = minZ,
        maxX = maxX,
        maxZ = maxZ,
        cell = side,
        count = count,
        cells = cells,
    }
end

return Parser