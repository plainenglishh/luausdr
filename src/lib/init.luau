local luausdr = {}

local Receiver = require("@self/Receiver")
export type Receiver = Receiver.Receiver
export type Mode = Receiver.Mode
luausdr.Receiver = Receiver

function luausdr.khz(value: number): number
    return value * 1000
end

function luausdr.mhz(value: number): number
    return value * 1000 * 1000
end

function luausdr.ghz(value: number): number
    return value * 1000 * 1000 * 1000
end

function luausdr.parse_frequency(input: string): number?
    input = string.lower(input):gsub("_", "")

    local freq_str, suffix = string.match(input, "^([%d%.]+)%s*(%a*)$")
    if not freq_str then
        return nil
    end

    local value = tonumber(freq_str)
    if not value then
        return nil
    end

    if suffix == "mhz" or suffix == "m" then
        value *= 1_000_000
    elseif suffix == "khz" or suffix == "k" then
        value *= 1_000
    elseif suffix == "ghz" or suffix == "g" then
        value *= 1_000_000_000
    elseif suffix ~= "hz" and suffix ~= "" then
        return nil
    end

    return math.floor(value)
end

return luausdr
