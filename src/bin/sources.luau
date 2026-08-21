local fs = require("@std/fs")
local io = require("@std/io")
local time = require("@std/time")
local cli = require("./cli")

export type SourceHandle = {
    get_samples: () -> ({ vector }, number),
    close: () -> (),
    closed: () -> boolean,
}

export type Source = {
    name: string,
    available: () -> boolean,
    loopable: boolean,
    get: (ctx: SourceGetCtx, ...any) -> SourceHandle,
}

export type SourceGetCtx = {
    block_size_samples: number,
    loop: boolean,
}

local bytes_per_sample = 8 -- 2x f32s

local function decode_samples(b: buffer, samples: { vector }): ({ vector }, number)
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

local sources = {}

sources.stdin = {
    name = "stdin",
    loopable = false,

    available = function(): boolean
        return true
    end,

    get = function(ctx: SourceGetCtx): SourceHandle
        local block_size_samples = ctx.block_size_samples
        local block_size_bytes = block_size_samples * bytes_per_sample

        local closed = false
        local samples = table.create(block_size_samples, vector.zero)

        return {
            get_samples = function(): ({ vector }, number)
                if closed then
                    return {}, 0
                end

                local raw_samples, eof = io.input.read(block_size_bytes, time.seconds(30))
                if eof then
                    closed = true
                    return {}, 0
                end
                local raw_samples = buffer.fromstring(raw_samples or cli.error("invalid samples"))
                local samples, sample_count = decode_samples(raw_samples, samples)
                if sample_count == 0 then
                    closed = true
                    return {}, 0
                end

                return samples, sample_count
            end,

            close = function()
                closed = true
            end,

            closed = function(): boolean
                return closed
            end,
        }
    end,
}

sources.file = {
    name = "file",
    loopable = true,

    available = function()
        return true
    end,

    get = function(ctx: SourceGetCtx, path: string): SourceHandle
        local block_size_samples = ctx.block_size_samples
        local block_size_bytes = block_size_samples * bytes_per_sample

        local closed = false
        local samples = table.create(block_size_samples, vector.zero)
        local raw_samples = buffer.create(block_size_bytes)
        local file_offset = 0
        local file = fs.file.from(path)
        local length = file:size()

        return {
            get_samples = function(): ({ vector }, number)
                if closed then
                    return {}, 0
                end

                local bytes_left = length - file_offset
                local count = math.min(block_size_bytes, bytes_left)
                file:readbytes(file_offset, count, raw_samples, 0)
                file_offset += count

                if count < block_size_bytes then
                    if ctx.loop then
                        file_offset = 0
                    else
                        closed = true
                    end
                end

                local samples, sample_count = decode_samples(raw_samples, samples)
                if sample_count == 0 then
                    closed = true
                end

                return samples, sample_count
            end,

            close = function()
                closed = true
            end,

            closed = function(): boolean
                return closed
            end,
        }
    end,
}

return sources :: { [keyof<typeof(sources)>]: Source }
