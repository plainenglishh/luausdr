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

The library comes with a CLI written with [Seal](https://github.com/seal-runtime/seal):

```bash
seal r <direction> -i=<input> -o=<output> -f=<target_frequency> -c=<centre_frequency> -m=<mode> -r=<rf_rate> -a=<af_rate> [-l]
```

|Name|Description|
|-|-|
|`direction`|The direction, only `rx` is supported currently.|
|`input`, `i`|A file path to a `.bin` file containing f32 IQ samples, or `-`/`stdin` for stdin.|
|`output`, `o`|A file path to write a `.bin` file containing f32 IQ samples, `-`/`stdout` for stdout or `ffplay`.|
|`target_frequency`, `f`|The frequency to tune to.|
|`centre_frequency`, `c`|The frequency the IQ data is centred on.|
|`mode`, `m`|The mode to demodulate.|
|`rf_rate`, `r`|The sample rate of incoming RF data.|
|`af_rate`, `a`|The sample rate of outgoing AF data.|
|`loop`, `l`|Whether to loop a non-streamed input.`|

### Usage

While wav encoding/decoding are planned, the library currently only works with raw samples. 

The CLI is best used with the ffplay output option:

```bash
# Decoding +22KHz LSB on an IQ file with an unknown centre.
seal r rx -i=samples/airband.bin -f=900khz -c=0 -m=am -r=3mhz -a=44.1khz -o=ffplay -b=5000
```

## Note

As this library is in very early stages, many features such as FIR filters, DC
correction, squelch, AGC, and more, are currently absent.