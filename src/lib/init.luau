local luausdr = {}

local Radio = require("@self/Radio")
export type Radio = Radio.Radio
export type Mode = Radio.Mode
luausdr.Radio = Radio

return luausdr
