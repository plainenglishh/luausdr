local cli = require("@self/cli")
local sinks = require("@self/sinks")
local luausdr = require("./lib")
local sources = require("@self/sources")

local options = cli.args()

local bytes_per_sample = 8 -- 2x f32s
local block_size_bytes = options.block_size * bytes_per_sample

local source = if options.input == "stdin" then sources.stdin else sources.file
cli.assert(if options.loop then source.loopable else true, `cant loop a {source.name} source`)
cli.assert(source.available(), `{source.name} is unavailable`)

local source_handle = source.get({ block_size_samples = options.block_size, loop = options.loop }, options.input)

local sink = if options.output == "stdout"
    then sinks.stdout
    elseif options.output == "ffplay" then sinks.ffplay
    else error("")

cli.assert(sink.available(), `{sink.name} is unavailable`)
local sink_handle = sink.get({ af_sample_rate = options.af_rate })

local rx = luausdr.Receiver
    .new()
    :set_target_frequency(options.frequency)
    :set_centre_frequency(options.centre_frequency)
    :set_mode(options.mode)
    :set_rf_sample_rate(options.rf_rate)
    :set_af_sample_rate(options.af_rate)
    :set_af_gain(20)

cli.info(`source/sink:         {options.input} -> {options.output}`)
cli.info(`looping:             {options.loop}`)
cli.info(`target frequency:    {options.frequency}hz`)
cli.info(`centre frequency:    {options.centre_frequency}hz`)
cli.info(`frequency offset:    {options.frequency - options.centre_frequency}hz`)
cli.info(`block size:          {options.block_size} samples, {block_size_bytes} bytes`)
cli.info(
    `sample rate (rf/af): {options.rf_rate}sps ({math.round((options.rf_rate * bytes_per_sample)) / 1000}KB/s) / {options.af_rate}sps ({math.round(
        (options.af_rate * 4)
    ) / 1000}KB/s)`
)
cli.info(`gain (rf/af):        {rx:rf_gain()}db / {rx:af_gain()}db`)

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

    local af_samples = rx:process(rf_samples, 1, rf_sample_count)
    sink_handle.play(af_samples)
end

source_handle.close()
sink_handle.close()
sink_handle.wait()
