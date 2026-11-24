return function(value)
    return (string.unpack("<f", string.pack("<f", value)))
end