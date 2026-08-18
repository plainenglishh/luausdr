# LuauSDR

An experimental pure-Luau Software Defined Radio DSP library.

## Features

- Three modes (`am`, `usb` and `lsb`).

## Usage

```luau
local luausdr = require("...")

local radio = luausdr.Radio.new()
radio.target_frequency = luausdr.khz(909)
radio.centre_frequency = luausdr.khz(1000)
radio.mode = "am"
radio.rf_sample_rate = luausdr.mhz(2) -- common value for RTLSDR
radio.af_sample_rate = luausdr.khz(44.1)

--- Example source
local rf_source: { get_samples: (_, ) -> buffer? } = nil
--- Example sink, assumes it buffers and plays samples at it's own rate.
local af_sink:  { play: (_, samples: {number}, sample_rate: number) -> () } = nil

while true do
    local rf = rf_source:get_samples()
    if not rf then
        break
    end

    local af = radio:process(rf)
    af_sync:play(af)
end
```

The library itself as no notion of a block size, it is up to the library user what sized blocks, if any set size at all, to give to Radio:process().

## CLI

The library comes with a CLI written with Lute:

```bash
lute src/cli/init.luau <input> <target_frequency> <centre_frequency> <mode> <rf_sample_rate> <af_sample_rate>
```

|Name|Description|
|-|-|
|`input`|A file path to a `.bin` file containing f32 IQ samples.|
|`target_frequency`|The frequency to tune to.|
|`centre_frequency`|The frequency the IQ data is centred on.|
|`mode`|The mode to demodulate.|
|`rf_sample_rate`|The sample rate of incoming RF data.|
|`af_sample_rate`|The sample rate of outgoing AF data.|

### Usage

While wav encoding/decoding are planned, the library currently only works with raw samples. The CLI is best used when piped to ffmpeg.

Currently the CLI can only accept a binary file of samples, and emit decoded samples to stdout.

For example:

```bash
# Decoding +2.2KHz LSB on an IQ file with an unknown centre.
lute src/cli/init.luau samples/40m.bin 22khz 0 lsb 333333 16000 | ffplay -f f32le -codec:a pcm_f32le -sample_rate 16000 -probesize 32 -
```

## Note

As this library is in very early stages, many features such as FIR filters, DC
correction, squelch, AGC, and more, are currently absent.