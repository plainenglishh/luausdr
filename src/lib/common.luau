local common = {}

function common.parse_frequency(input: string): number?
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

return common
