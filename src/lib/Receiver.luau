--!native

local common = require("./common")
export type Mode = "am" | "lsb" | "usb"

local Receiver = {}
export type Receiver = setmetatable<
    {
        --- Options
        _target_frequency: number,
        _centre_frequency: number,
        _rf_sample_rate: number,
        _af_sample_rate: number,
        _rf_gain: number,
        _af_gain: number,
        _mode: Mode,

        --- Internal State
        _configured: boolean,
        _phase: number,
    },
    typeof(Receiver)
>

Receiver.__index = Receiver

function Receiver.new(): Receiver
    return setmetatable({
        --- Rx configuration
        _target_frequency = 0,
        _centre_frequency = 0,
        _mode = "am",
        _rf_sample_rate = 0,
        _af_sample_rate = 44100,
        _rf_gain = 1,
        _af_gain = 1,

        --- Inter-process state.
        _configured = false,
        _phase = 0,
    }, Receiver)
end

function Receiver.set_target_frequency(self: Receiver, value: number | string): Receiver
    self._target_frequency = (if type(value) == "string" then common.parse_frequency(value) else value)
        or error(`invalid frequency {value}`)
    return self
end

function Receiver.target_frequency(self: Receiver): number
    return self._target_frequency
end

function Receiver.set_centre_frequency(self: Receiver, value: number | string): Receiver
    self._centre_frequency = (if type(value) == "string" then common.parse_frequency(value) else value)
        or error(`invalid frequency {value}`)
    return self
end

function Receiver.centre_frequency(self: Receiver): number
    return self._centre_frequency
end

function Receiver.set_rf_sample_rate(self: Receiver, value: number | string): Receiver
    self._rf_sample_rate = (if type(value) == "string" then common.parse_frequency(value) else value)
        or error(`invalid frequency {value}`)
    return self
end

function Receiver.rf_sample_rate(self: Receiver): number
    return self._rf_sample_rate
end

function Receiver.set_af_sample_rate(self: Receiver, value: number | string): Receiver
    self._af_sample_rate = (if type(value) == "string" then common.parse_frequency(value) else value)
        or error(`invalid frequency {value}`)
    return self
end

function Receiver.af_sample_rate(self: Receiver): number
    return self._af_sample_rate
end

function Receiver.set_rf_gain(self: Receiver, value: number): Receiver
    self._rf_gain = value
    return self
end

function Receiver.rf_gain(self: Receiver): number
    return self._rf_gain
end

function Receiver.set_af_gain(self: Receiver, value: number): Receiver
    self._af_gain = value
    return self
end

function Receiver.af_gain(self: Receiver): number
    return self._af_gain
end

function Receiver.set_mode(self: Receiver, value: Mode): Receiver
    self._mode = value
    return self
end

function Receiver.mode(self: Receiver): Mode
    return self._mode
end

--[=[
	digital down converter impl w/ boxcar filter & decimation
]=]
local function down_convert(self: Receiver, input: { vector }, i: number, j: number): { vector }
    local decimation_factor = self._rf_sample_rate / self._af_sample_rate

    local slice_width = j - i + 1
    local output_count = math.floor(slice_width / decimation_factor)
    local output: { vector } = table.create(output_count, vector.zero)

    local frequency_offset = self._target_frequency - self._centre_frequency
    local omega = 2 * math.pi * (frequency_offset / self._rf_sample_rate)
    local TWO_PI = 2 * math.pi

    local accumulator = vector.zero
    local output_i = 1

    local sample_weight = 0.0

    for idx = i, j do
        local input_sample = input[idx]

        local phase = (self._phase + omega) % TWO_PI
        self._phase = phase

        local lo = vector.create(math.cos(phase), math.sin(phase))
        local tuned_sample = vector.create(vector.dot(input_sample, lo), vector.cross(lo, input_sample).z)

        accumulator += tuned_sample
        sample_weight += 1.0

        if sample_weight >= decimation_factor then
            if output_i <= output_count then
                output[output_i] = accumulator * (1 / sample_weight)
                output_i += 1
            end

            accumulator = vector.zero
            sample_weight -= decimation_factor
        end
    end

    return output
end

local function demodulate(self: Receiver, samples: { vector }): { number }
    local sample_count = #samples
    local output = table.create(sample_count, 0)
    local mode = self._mode

    if mode == "am" then
        for i = 1, sample_count do
            output[i] = vector.magnitude(samples[i])
        end
    elseif mode == "lsb" then
        for i = 1, sample_count do
            local sample = samples[i]
            output[i] = sample.x - sample.y
        end
    elseif mode == "usb" then
        for i = 1, sample_count do
            local sample = samples[i]
            output[i] = sample.x + sample.y
        end
    else
        error(`unknown mode {self._mode}`)
    end

    return output
end

local function gain(samples: { number } | { vector }, multiplier_db: number, i: number?, j: number?)
    local samples = samples :: { number }
    local i = i or 1
    local j = j or #samples
    local linear_multiplier = 10 * (multiplier_db / 20)

    for sample = i, j do
        samples[sample] *= linear_multiplier
    end
end

local function dc_eliminate(self: Receiver, samples: { vector })
    --- TODO
end

function Receiver.process(self: Receiver, rf: { vector }, i: number?, j: number?): { number }
    local i = i or 1
    local j = j or #rf

    gain(rf, self._rf_gain)
    local if_ = down_convert(self, rf, i, j)

    dc_eliminate(self, if_)

    local af = demodulate(self, if_)
    gain(af, self._af_gain)

    return af
end

return table.freeze(Receiver)
