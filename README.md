# tlassemble
tlassemble is a simple Mac OS X command line utility that combines a sequence of images into a movie. A GUI version, [Time Lapse Assembler](http://www.dayofthenewdan.com/projects/time-lapse-assembler-1), is also available for download.

If you find this software useful, please consider making a small donation to fund future development.
[Donate now](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=9465YBPSUC9YL)

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
$ tlassemble [FLAGS...] SOURCE [SOURCE...] DESTINATION.MOV
```

###Examples
```bash
$ tlassemble ./images time_lapse.mov
$ tlassemble --fps 30 --height 720 --codec h264 --quality high imagesA imagesB time_lapse.mov
$ tlassemble --quiet image01.jpg image02.jpg image03.jpg time_lapse.mov
```

###Flags
```
--codec: Codec with which to compress the resulting movie.  Defaults to 'h264'.
--dryrun: Don't actually create the output movie.  Simulates most of the process, however, to give you a good idea of how it'd go.  Off by default.
--filter: Specify a filter on the image metadata for each frame.  e.g. 'Model=Nikon D5200'.  May be specified multiple times to add successive filters.  Filters are case insensitive.
--fps: Frame rate of the movie.  Defaults to 30.
--height: The desired height of the movie; source frames will be proportionately resized.  If unspecified the height is taken from the source frames.
--quality: Quality level to encode with can.  Defaults to 'high'.
--quiet: Supresses non-error output.  Off by default.
--reverse: Reverse the sort order.
--sort: Sort method for the input images.  Defaults to 'creation'.
```

###License
tlassemble can be distributed in accordance with the BSD New license.  See the top of [tlassemble.m](https://github.com/wadetregaskis/cocoa-tlassemble/blob/master/tlassemble.m) for full license terms.

