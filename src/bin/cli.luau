local luausdr = require("../lib")
local env = require("@std/env")
local dir = require("@std/fs/dir")
local io = require("@std/io")
local process = require("@std/process")

local RED = "\x1b[31m"
local YELLOW = "\x1b[33m"
local BOLD = "\x1b[1m"
local RESET = "\x1b[0m"

local ERROR = `{RED}{BOLD}error:{RESET} `
local WARN = `{YELLOW}{BOLD}warn:{RESET} `

local cli = {}

function cli.error(message: string): never
    io.output.ewriteln(`{ERROR}{message}`)
    return process.exit(1)
end

function cli.assert<T>(cond: T, message: string): T
    if not cond then
        cli.error(message)
    end
    return cond
end

function cli.warn(message: string)
    io.output.ewriteln(`{WARN}{message}`)
end

function cli.info(message: string)
    io.output.ewriteln(`{message}`)
end

export type Mode = "am" | "lsb" | "usb" | "adsb" | "rtty"

type BaseCliArgs = {
    direction: "rx",
    frequency: number,
    centre_frequency: number,
    input: "stdin" | string,
    output: "ffplay" | "stdout" | string,
    block_size: number,
    loop: boolean,
    rf_rate: number,
}

export type CliArgs = BaseCliArgs & {
    mode: "am" | "lsb" | "usb",
    af_rate: number,
}

local function normalise(str: string?): string?
    if not str then
        return nil
    end
    str = str:gsub("%-", "_")
    return str
end

local function get_flag(name: string, short: string?): boolean
    local matched = false
    for _, arg in env.args do
        local long_name = normalise(string.match(arg, "^%-%-(.+)$"))
        local short_name = normalise(string.match(arg, "^%-(.+)$"))

        if (long_name == name) or (short_name == short) then
            matched = true
        end
    end
    return matched
end

local function get_opt(name: string, short: string?): string?
    local value: string? = nil
    local match_count = 0

    for _, arg in env.args do
        local long_name = normalise(string.match(arg, "^%-%-([^=]+)=.+$"))
        local short_name = normalise(string.match(arg, "^%-([^=]+)=.+$"))

        if (long_name == name) or (short_name == short) then
            match_count += 1
            value = string.match(arg, "=(.+)$")
        end
    end

    if match_count > 1 then
        error(`'{name}' is ambiguous`)
    end

    return value
end

local function get_frequency(long: string, short: string?): number?
    local raw = get_opt(long, short)
    if not raw then
        return nil
    end

    return luausdr.parse_frequency(raw) or cli.error(`invaild {long}`)
end

export type Direction = "rx" | "tx"

local DIRECTION_ALIASES: { [string]: Direction } = {
    rx = "rx",
    r = "rx",
    receive = "rx",
    tx = "tx",
    t = "tx",
    transmit = "tx",
}

function cli.args(): CliArgs
    local direction = DIRECTION_ALIASES[env.args[1] or cli.error("specify direction")]
        or cli.error(`invalid direction {env.args[1]}`)
    cli.assert(direction == "rx", `transmit is not yet supported`)

    local frequency = get_frequency("frequency", "f") or cli.error(`specify --frequency/-f`)
    local centre_frequency: number = get_frequency("centre_frequency", "c") or 0
    local rf_rate = get_frequency("rf_rate", "r") or cli.error(`specify --rf_rate/-r`)
    local input = get_opt("input", "i") or "stdin"
    input = if input == "-" then "stdin" else input

    local output = get_opt("output", "o") or "stdout"
    output = if output == "-" then "stdout" else output

    local block_size = tonumber(get_opt("block_size", "b") or "8192") or cli.error("invalid block_size")

    local options: BaseCliArgs = {
        direction = "rx",
        frequency = frequency,
        centre_frequency = centre_frequency,
        rf_rate = rf_rate,
        input = input,
        output = output,
        block_size = block_size,
        loop = get_flag("loop", "l"),
    }

    local mode = string.lower(get_opt("mode", "m") or cli.error(`specify --mode/-m`)) :: Mode

    if mode == "am" or mode == "lsb" or mode == "usb" then
        local af_rate = get_frequency("af_rate", "a") or cli.error(`specify --af_rate/-a`)

        local options = options :: any
        options.mode = mode
        options.af_rate = af_rate

        return options :: CliArgs
    else
        return cli.error(`invalid mode`)
    end
end

return cli
