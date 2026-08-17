local fs = require("@std/fs")
local process = require("@std/process")
local luausdr = require("./lib")
local args = process.args

-- args[1] = script/bundle path
local path = args[2]
local target_frequency = tonumber(args[3]) or error("invalid target_frequency")
local centre_frequency = tonumber(args[4]) or error("invalid centre_frequency")
local mode = string.lower(args[5])
local rf_sample_rate = tonumber(args[6]) or error("invalid rf_sample_rate")
local af_sample_rate = tonumber(args[7]) or error("invalid af_sample_rate")

local BLOCK_SIZE_SAMPLES = 8192
local BYTES_PER_SAMPLE = 8 -- 2x f32s
local BLOCK_SIZE_BYTES = BLOCK_SIZE_SAMPLES * BYTES_PER_SAMPLE

local radio = luausdr.Radio.new()

radio.target_frequency = target_frequency
radio.centre_frequency = centre_frequency
radio.mode = mode :: luausdr.Mode
radio.rf_sample_rate = rf_sample_rate
radio.af_sample_rate = af_sample_rate
radio.af_gain = 20

local input = fs.open(path, "r")
local stdout = fs.open("/dev/stdout", "w")
local stderr = fs.open("/dev/stderr", "w")

local function eprint(...: any)
	for i = 1, select("#", ...) do
		fs.write(stderr, tostring(select(i, ...)))
		fs.write(stderr, "  ")
	end
	fs.write(stderr, "\n")
end

local raw_block = buffer.create(BLOCK_SIZE_BYTES)
local rf = table.create(BLOCK_SIZE_SAMPLES, vector.zero)
local file_offset = 0

process.onSignal("SIGINT", function()
	process.exit(1)
end)

while true do
	local bytes_read = fs.readIntoBuffer(input, raw_block, file_offset, BLOCK_SIZE_BYTES)
	if bytes_read <= 0 then
		file_offset = 0
		continue
	end

	file_offset += bytes_read
	local rf_sample_count = bytes_read // BYTES_PER_SAMPLE

	for sample_i = 1, rf_sample_count do
		local offset = (sample_i - 1) * BYTES_PER_SAMPLE

		local i = buffer.readf32(raw_block, offset)
		local q = buffer.readf32(raw_block, offset + 4)
		rf[sample_i] = vector.create(i, q)
	end

	local af = radio:process_block(rf, 1, rf_sample_count)
	local af_sample_count = #af

	local output_block = buffer.create(#af * 4)

	for i = 1, af_sample_count do
		local offset = (i - 1) * 4
		buffer.writef32(output_block, offset, af[i])
	end

	fs.write(stdout, buffer.tostring(output_block))
end
