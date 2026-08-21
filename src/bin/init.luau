local cli = require("@self/cli")
local sinks = require("@self/sinks")
local luausdr = require("./lib")
local sources = require("@self/sources")
local env = require("@std/env")

local function get_flag(name: string, short: string?): boolean
    for _, arg in env.args do
        local long_name, short_name = string.match(arg, "^%-%-(.+)$"), string.match(arg, "^%-(.+)$")
        if not (long_name or short_name) then
            continue
        end

        if long_name ~= name and short_name ~= short then
            continue
        end

        return true
    end

    return false
end

local function get_opt(name: string, short: string?): string?
    for _, arg in env.args do
        local long_name, short_name = string.match(arg, "^%-%-(.+)=.+$"), string.match(arg, "^%-(.+)=.+$")
        if not (long_name or short_name) then
            continue
        end

        if long_name ~= name and short_name ~= short then
            continue
        end

        if long_name and short_name then
            error(`passing both {name} and {short} is amigious`)
        end

        local value = string.match(arg, "=(.+)$")
        return value
    end

    return nil
end

local function get_frequency(long: string, short: string?): number?
    local raw = get_opt(long, short)
    if not raw then
        return nil
    end

    return luausdr.parse_frequency(raw) or cli.error(`invald {long}`)
end

local target_frequency = get_frequency("frequency", "f") or cli.error("specify frequency")
local centre_frequency = get_frequency("centre_frequency", "c") or 0
local mode = get_opt("mode", "m") or cli.error("specify mode")
local rf_sample_rate = get_frequency("rf_sps", "r") or cli.error("specify rf_sps (iq snapshot bandwidth)")
local af_sample_rate = get_frequency("af_sps", "a") or 44100
local input_path = get_opt("input", "i") or cli.error("specify input")
local output_path = get_opt("output", "o") or cli.error("specify output")
local block_size_samples = tonumber(get_opt("block_size", "b") or "8192") or cli.error("invalid block_size")
local loop = get_flag("loop", "l")

local bytes_per_sample = 8 -- 2x f32s
local block_size_bytes = block_size_samples * bytes_per_sample

local source = if input_path == "-" or input_path == "stdin" then sources.stdin else sources.file
cli.assert(if loop then source.loopable else true, `cant loop a {source.name} source`)
cli.assert(source.available(), `{source.name} is unavailable`)
local source_handle = source.get({ block_size_samples = block_size_samples, loop = loop }, input_path)

local sink = if output_path == "-" or output_path == "stdout"
    then sinks.stdout
    elseif output_path == "ffplay" then sinks.ffplay
    else error("")

cli.assert(sink.available(), `{sink.name} is unavailable`)
local sink_handle = sink.get({ af_sample_rate = af_sample_rate })

local radio = luausdr.Radio.new()

radio.target_frequency = target_frequency
radio.centre_frequency = centre_frequency
radio.mode = mode :: luausdr.Mode
radio.rf_sample_rate = rf_sample_rate
radio.af_sample_rate = af_sample_rate
radio.af_gain = 20

cli.info(
    `source/sink:         {if input_path == "-" then "stdin" else input_path} -> {if output_path == "-"
        then "stdout"
        else output_path}`
)
cli.info(`looping:             {loop}`)
cli.info(`target frequency:    {target_frequency}hz`)
cli.info(`centre frequency:    {centre_frequency}hz`)
cli.info(`frequency offset:    {target_frequency - centre_frequency}hz`)
cli.info(`block size:          {block_size_samples} samples, {block_size_bytes} bytes`)
cli.info(
    `sample rate (rf/af): {rf_sample_rate}sps ({math.round((rf_sample_rate * bytes_per_sample)) / 1000}KB/s) / {af_sample_rate}sps ({math.round(
        (af_sample_rate * 4)
    ) / 1000}KB/s)`
)
cli.info(`gain (rf/af):        {radio.rf_gain}db / {radio.af_gain}db`)

while true do
    if source_handle.closed() then
        break
    end

    if sink_handle.closed() then
        cli.error("sink closed unexpectedly")
        break
    end

    local rf_samples, rf_sample_count = source_handle.get_samples()
    if rf_sample_count == 0 then
        break
    end

    local af_samples = radio:process(rf_samples, 1, rf_sample_count)
    sink_handle.play(af_samples)
end

source_handle.close()
sink_handle.close()
sink_handle.wait()
