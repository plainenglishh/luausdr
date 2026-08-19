local luausdr = require("./lib")

local function cli_error(e: string): never
    print(e)
    return zune.process.exit(1)
end

local function get_flag(name: string, short: string?): boolean
    for _, arg in zune.process.args do
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
    for _, arg in zune.process.args do
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

    return luausdr.parse_frequency(raw) or cli_error(`invald {long}`)
end

local function open_file(path: string)
    local handle = zune.process.create("cat", { path })
    return handle.stdout or error("")
end

local target_frequency = get_frequency("frequency", "f") or cli_error("specify frequency")
local centre_frequency = get_frequency("centre_frequency", "c") or 0
local mode = get_opt("mode", "m") or cli_error("specify mode")
local rf_sample_rate = get_frequency("rf_sps", "r") or cli_error("specify rf_sps (iq snapshot bandwidth)")
local af_sample_rate = get_frequency("af_sps", "a") or 44100
local input_path = get_opt("input", "i") or cli_error("specify input")
local output_path = get_opt("output", "o") or cli_error("specify output")
local block_size_samples = tonumber(get_opt("block_size", "b") or "8192") or cli_error("invalid block_size")
local loop = get_flag("loop", "l")

local bytes_per_sample = 8 -- 2x f32s
local block_size_bytes = block_size_samples * bytes_per_sample

--[=[
    Return 
]=]
local get_rf_samples: () -> ({ vector }, number)
local close_source: () -> ()
do
    local samples = table.create(block_size_samples, vector.zero)

    local function decode_samples(b: buffer): ({ vector }, number)
        local len = buffer.len(b)
        local sample_count = len // bytes_per_sample

        for sample_i = 1, sample_count do
            local offset = (sample_i - 1) * bytes_per_sample
            local i = buffer.readf32(b, offset)
            local q = buffer.readf32(b, offset + 4)
            samples[sample_i] = vector.create(i, q)
        end

        return samples, sample_count
    end

    if input_path == "-" or input_path == "stdin" then
        if loop then
            cli_error("cant loop a live stream")
        end

        function get_rf_samples()
            local raw_samples = zune.io.stdin:readSync(block_size_bytes, true)
            return decode_samples(raw_samples)
        end

        function close_source()
            --zune.io.stdin:close()
        end
    else
        local input = open_file(input_path)

        function get_rf_samples(): ({ vector }, number)
            local raw_samples = input:readSync(block_size_bytes, true)
            return decode_samples(raw_samples)
        end

        function close_source()
            input:close()
        end
    end
end

local write_af_samples: ({ number }) -> ()
local close_sink: () -> ()
do
    local function encode_samples(samples: { number }): buffer
        local b = buffer.create(#samples * 4)
        for i = 1, #samples do
            local offset = (i - 1) * 4
            buffer.writef32(b, offset, samples[i])
        end
        return b
    end

    if output_path == "-" or output_path == "stdout" then
        function write_af_samples(samples: { number })
            zune.io.stdout:writeSync(encode_samples(samples))
        end

        function close_sink() end
    elseif output_path == "ffplay" then
        local ffmpeg = zune.process.create("ffplay", {
            "-f",
            "f32le",
            "-codec:a",
            "pcm_f32le",
            "-sample_rate",
            tostring(af_sample_rate),
            "-probesize",
            "32",
            --"-nodisp",
            "-autoexit",
            "-",
        })

        function write_af_samples(samples: { number })
            local handle = ffmpeg.stdin or cli_error("cant get write handle")
            handle:writeSync(encode_samples(samples))
        end

        function close_sink()
            local handle = ffmpeg.stdin or cli_error("cant get write handle")
            handle:close()
        end

        zune.task.defer(function()
            ffmpeg:wait()
        end)
    else
        local output = zune.fs.openFile(output_path, { mode = "w" })
        function write_af_samples(samples: { number })
            output:writeSync(encode_samples(samples))
        end

        function close_sink()
            output:close()
        end
    end
end

zune.process.onSignal("INT", function()
    zune.task.defer(function()
        close_source()
        close_sink()
    end)
end)

local radio = luausdr.Radio.new()

radio.target_frequency = target_frequency
radio.centre_frequency = centre_frequency
radio.mode = mode :: luausdr.Mode
radio.rf_sample_rate = rf_sample_rate
radio.af_sample_rate = af_sample_rate
radio.af_gain = 20

print(
    `source/sink:         {if input_path == "-" then "stdin" else input_path} -> {if output_path == "-"
        then "stdout"
        else output_path}`
)
print(`looping:             {loop}`)
print(`target frequency:    {target_frequency}hz`)
print(`centre frequency:    {centre_frequency}hz`)
print(`frequency offset:    {target_frequency - centre_frequency}hz`)
print(`block size:          {block_size_samples} samples, {block_size_bytes} bytes`)
print(
    `sample rate (rf/af): {rf_sample_rate}sps ({math.round((rf_sample_rate * bytes_per_sample)) / 1000}KB/s) / {af_sample_rate}sps ({math.round(
        (af_sample_rate * 4)
    ) / 1000}KB/s)`
)
print(`gain (rf/af):        {radio.rf_gain}db / {radio.af_gain}db`)

while true do
    local rf_samples, rf_sample_count = get_rf_samples()
    if rf_sample_count == 0 then
        print("stream ended")
        break
    end

    local af_samples = radio:process(rf_samples, 1, rf_sample_count)
    write_af_samples(af_samples)
end

close_source()
close_sink()
