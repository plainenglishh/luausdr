local luausdr = {}

local Radio = require("@self/Radio")
export type Radio = Radio.Radio
export type Mode = Radio.Mode
luausdr.Radio = Radio

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
