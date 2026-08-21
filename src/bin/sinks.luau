local io = require("@std/io")
local process = require("@std/process")
local cli = require("./cli")

export type SinkHandle = {
    play: (samples: { number }) -> (),
    close: () -> (),
    closed: () -> boolean,
    wait: () -> (),
    info: () -> string?,
}

export type Sink = {
    name: string,
    available: () -> boolean,
    get: (ctx: SinkGetCtx, ...any) -> SinkHandle,
}

export type SinkGetCtx = {
    af_sample_rate: number,
}

local function encode_samples(samples: { number }): buffer
    local b = buffer.create(#samples * 4)
    for i = 1, #samples do
        local offset = (i - 1) * 4
        buffer.writef32(b, offset, samples[i])
    end
    return b
end

local sinks = {}

sinks.stdout = {
    name = "stdout",

    available = function()
        return true
    end,

    get = function(ctx: SinkGetCtx): SinkHandle
        local closed = false

        return {
            play = function(samples: { number })
                io.output.write(encode_samples(samples))
            end,

            close = function()
                closed = true
            end,

            closed = function(): boolean
                return closed
            end,

            wait = function() end,

            info = function()
                return nil
            end,
        }
    end,
}

sinks.ffplay = {
    name = "ffplay",

    available = function()
        return true
    end,

    get = function(ctx: SinkGetCtx): SinkHandle
        local ffplay = process.spawn({
            program = "ffplay",
            args = {
                "-f",
                "f32le",
                "-codec:a",
                "pcm_f32le",
                "-sample_rate",
                tostring(ctx.af_sample_rate),
                "-probesize",
                "32",
                "-nodisp",
                "-autoexit",
                "-",
            },
            stdio = "Pipe",
        })

        local ffplay_pipe = ffplay.stdin or cli.error("failed to get ffplay pipe")
        repeat
        until ffplay:alive()

        return {
            play = function(samples: { number })
                ffplay_pipe:write(buffer.tostring(encode_samples(samples)))
            end,

            close = function()
                ffplay_pipe:close()
            end,

            closed = function(): boolean
                return not ffplay:alive()
            end,

            wait = function()
                while ffplay:alive() do
                    -- horrible busy wait
                end
            end,

            info = function()
                if not ffplay.stderr then
                    return nil
                end

                return ffplay.stderr:read()
            end,
        }
    end,
}

return sinks :: { [keyof<typeof(sinks)>]: Sink }
