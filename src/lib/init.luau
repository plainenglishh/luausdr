local luausdr = {}

local Receiver = require("@self/Receiver")
local common = require("@self/common")
export type Receiver = Receiver.Receiver
export type Mode = Receiver.Mode
luausdr.Receiver = Receiver

luausdr.parse_frequency = common.parse_frequency

function luausdr.khz(value: number): number
    return value * 1000
end

function luausdr.mhz(value: number): number
    return value * 1000 * 1000
end

function luausdr.ghz(value: number): number
    return value * 1000 * 1000 * 1000
end

return luausdr
