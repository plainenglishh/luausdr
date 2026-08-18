export type Mode = "am" | "lsb" | "usb"

local function KHZ(value: number)
	return value * 1000
end

local function MHZ(value: number)
	return value * 1000 * 1000
end

local Radio = {}
export type Radio = setmetatable<
	{
		--- Options
		target_frequency: number,
		centre_frequency: number,
		rf_sample_rate: number,
		af_sample_rate: number,
		rf_gain: number,
		af_gain: number,
		mode: Mode,

		--- Internal State
		_phase: number,
	},
	typeof(Radio)
>

Radio.__index = Radio

function Radio.new(): Radio
	return setmetatable({
		target_frequency = KHZ(1000),
		centre_frequency = KHZ(1000),
		rf_sample_rate = MHZ(2),
		af_sample_rate = KHZ(8),
		rf_gain = 1,
		af_gain = 1,
		mode = "am",
		_phase = 0,
	}, Radio)
end

--[=[
	digital down converter impl w/ boxcar filter & decimation
]=]
local function down_convert(self: Radio, input: { vector }, i: number, j: number): { vector }
	local decimation_factor = self.rf_sample_rate / self.af_sample_rate

	local slice_width = j - i + 1
	local output_count = math.floor(slice_width / decimation_factor)
	local output: { vector } = table.create(output_count, vector.zero)

	local frequency_offset = self.target_frequency - self.centre_frequency
	local omega = 2 * math.pi * (frequency_offset / self.rf_sample_rate)
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

local function demodulate(self: Radio, samples: { vector }): { number }
	local sample_count = #samples
	local output = table.create(sample_count, 0)
	local mode = self.mode

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
		error(`unknown mode {self.mode}`)
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

local function convert_buffer(b: buffer): { vector }
	local len = buffer.len(b)
	assert(len % 8, "expected length to be a multiple of 8 (f32x2)")
	local sample_count = len // 8

	local block = table.create(sample_count, vector.zero)
	for i = 1, sample_count do
		local offset = (i - 1) * 8
		local i = buffer.readf32(b, offset)
		local q: number = buffer.readf32(b, offset + 4)
		block[i] = vector.create(i, q)
	end

	return block
end

function Radio.process(self: Radio, rf: { vector } | buffer, i: number?, j: number?): { number }
	local rf = if type(rf) == "table" then rf else convert_buffer(rf)
	local i = i or 1
	local j = j or #rf

	gain(rf, self.rf_gain)
	local if_ = down_convert(self, rf, i, j)
	local af = demodulate(self, if_)
	gain(af, self.af_gain)

	return af
end

return Radio
