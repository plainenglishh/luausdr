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

return cli
