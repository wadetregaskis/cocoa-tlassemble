# tlassemble
tlassemble is a simple Mac OS X command line utility that combines a sequence of images into a movie.  It was originally developed by Daniel Bridges (https://github.com/dbridges/cocoa-tlassemble).

###Building and Installation
To build you must install XCode and the XCode developer tools, then:

```bash
$ git clone https://github.com/wadetregaskis/cocoa-tlassemble.git
$ cd cocoa-tlassemble
$ make
$ sudo cp tlassemble /usr/local/bin/ # or your own local bin directory
```

###Usage
```bash
$ tlassemble [FLAGS...] SOURCE [SOURCE...] DESTINATION
```

###Examples
```bash
$ tlassemble ./images time_lapse.mov
$ tlassemble --fps 30 --height 720 --codec h264 --quality high imagesA imagesB time_lapse.mov
$ tlassemble --quiet image01.jpg image02.jpg image03.jpg time_lapse.mov
```

###Flags
```
--assume-preceding-frames: Assume additional frames will be prefixed to the output movie file later, so adjust encoding settings to accomodate.
--assume-succeeding-frames: Assume additional frames will be appended to the output movie file later, so adjust encoding settings to accomodate.
--average-bit-rate: The target average bitrate, e.g. "3mb" or "450kB".  Actual bitrate may fluctuate above and below this goal.
--codec: Codec with which to compress the resulting movie.  Defaults to 'h264'.
--dryrun: Don't actually create the output movie.  Simulates most of the process, however, to give you a good idea of how it'd go.  Off by default.
--entropy-mode: Either "CAVLC" or "CABAC".  CABAC generally yields better compression, at the expense of higher CPU usage in encoding and playback.
--file-type: The format for the output file - one of "mov", "mp4" or "m4v".  The default is "mov", or derived from the output file name (if specified and with a file extension).
--filter: Specify a filter on the image metadata for each frame.  e.g. 'Model=Nikon D5200'.  May be specified multiple times to add successive filters.  Filters are case insensitive.
--fps: Frame rate of the movie.  Defaults to 30.
--frame-limit: The maximum number of frames to encode.  This is mainly useful for encoding testing and 'dry-running', by letting you limit the encode to just an initial subset of the full movie.
--height: The desired height of the movie; source frames will be proportionately resized.  If unspecified the height is taken from the source frames.
--help: Prints out a usage guide, similar to this file, and exits.
--key-frames-only: Use only 'key' frames (I-frames).  This yields larger video files, but ones which may exhibit less quality loss as a result of subsequent editing (e.g. in Final Cut Pro or iMovie).
--max-frame-delay: The maximum number of frames that the encoder may hold in its internal buffer, during compression.  This basically limits how far, forward or back, the encoder can go to reference other frames during temporal compression.  Smaller values typically make the output video slightly larger, but compatible with a wider range of playback devices.
--max-key-frame-period: The maximum amount of time (if a time unit is specified, e.g. "5s" or "10ms") or number of frames (if just a number is specified, e.g. "25" or "10") between key frames (I-frames).  Higher values permit better compression, but make the output video more difficult for subsequent editing software to use [without losing quality], and may prevent correct playback on some devices.
--quality: Quality level to encode with can.  Defaults to 'high'.
--quiet: Supresses non-error output.  Off by default.
--rate-limit: The absolute date rate limit (as opposed to --average-bit-rate, for example).  Useful for compatibility with lesser playback devices, which may not be able to handle bitrates above a certain threshold.
--reverse: Reverse the sort order.
--sort: Sort method for the input images.  Defaults to 'creation'.
--speed: How much to speed up the frames versus real time (when they were captured).  By default each frame is simply blindly played back a fixed interval of time after the previous (i.e. 1 / --fps).  When this parameter is specified, the real time relation between each frame is preserved (albeit shrunk by this multiplier).  This is particularly useful if your interval between frames changed during shooting (e.g. due to changing light changing shutter speed).  It can also yield more natural results if there are missing frames or otherwise gaps in recording.
--strict-frame-ordering: If specified, disables frame reordering.  Resulting output files will be compatible with more playback devices but the video quality may suffer.
--verbosity: A numeric verbosity level, either 0 (i.e. verbose logging off, the default), 1, 2, or 3 (corresponding to increasing levels of detail).  Typically useful only for debugging and development.
```

###License
tlassemble can be distributed in accordance with the BSD New license.  See the top of [tlassemble.m](https://github.com/wadetregaskis/cocoa-tlassemble/blob/master/tlassemble.m) for full license terms.

