/*
 *  Copyright (c) 2012-2013, Daniel Bridges & Wade Tregaskis
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *      * Redistributions of source code must retain the above copyright
 *        notice, this list of conditions and the following disclaimer.
 *      * Redistributions in binary form must reproduce the above copyright
 *        notice, this list of conditions and the following disclaimer in the
 *        documentation and/or other materials provided with the distribution.
 *      * Neither the name of the Daniel Bridges nor Wade Tregaskis nor the
 *        names of its contributors may be used to endorse or promote products
 *        derived from this software without specific prior written permission.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 *  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 *  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 *  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 *  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 *  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 *  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.*
 */

#ifdef DEBUG
#define DLOG(fmt, args...) NSLog(@"%s:%d "fmt,__FILE__,__LINE__,args)
#else
#define DLOG(fmt, args...)
#endif

#include <stdio.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QTKit/QTKit.h>

void usage() {
    fprintf(stderr, "%s","Usage: tlassemble INPUTDIRECTORY OUTPUTFILENAME [OPTIONS]\n"
            "Try 'tlassemble --help' for more information.\n");
}

void help() {
    printf("%s","\nUsage: tlassemble INPUTDIRECTORY OUTPUTFILENAME [OPTIONS]\n\n"
           "EXAMPLES\n"
           "tlassemble ./images time_lapse.mov\n"
           "tlassemble ./images time_lapse.mov -fps 30 -height 720 -codec h264 -quality high\n"
           "tlassemble ./images time_lapse.mov -quiet yes\n\n"
           "OPTIONS\n"
           "-fps: Frames per second for final movie can be anywhere between 0.1 and 60.0.\n"
           "-height: If specified images are resized proportionally to height given.\n"
           "-codec: Codec to use to encode can be 'h264' 'photojpeg' 'raw' or 'mpv4'.\n"
           "-quality: Quality to encode with can be 'high' 'normal' 'low'.\n"
           "-quiet: Set to 'yes' to suppress output during encoding.\n"
           "-reverse: Set to 'yes' to reverse the order that images are displayed in the movie.\n"
           "\n"
           "DEFAULTS\n"
           "fps = 30\n"
           "height = original image size\n"
           "codec = h264\n"
           "quality = high\n\n"
           "tlassemble-wade 1.0\n\n"
           "This software is provided in the hope that it will be useful, but without any warranty, without even the implied warranty for merchantability or fitness for a particular purpose. The software is provided as is and its designer is not to be held responsible for any lost data or other corruption.\n\n");
}

int main(int argc, const char *argv[]) {
    // Command line options:
    //
    // codec (h264, mp4v, photojpeg, raw)
    // fps (between 0.1 and 60)
    // quality (high, normal, low)
    // width (resize proportionally)

    @autoreleasepool {
        // Parse command line options
        NSUserDefaults *args = [NSUserDefaults standardUserDefaults];
        if (argc == 2) {
            if (strcmp(argv[1], "--help") == 0 ||
                strcmp(argv[1], "-help") == 0) {
                help();
                return 1;
            }
        }
        if (argc < 3) {
            usage();
            return 1;
        }

        double height = [args doubleForKey:@"height"];
        double fps = [args doubleForKey:@"fps"];
        NSString *codecSpec = [args stringForKey:@"codec"];
        NSString *qualitySpec = [args stringForKey:@"quality"];
        const BOOL quiet = [args boolForKey:@"quiet"];
        const BOOL reverseArray = [args boolForKey:@"reverse"];

        NSDictionary *codec = @{ @"h264": @"avc1",
                                 @"mpv4": @"mpv4",
                                 @"photojpeg" : @"jpeg",
                                 @"raw": @"raw " };

        NSDictionary *quality = @{ @"low": @(codecLowQuality),
                                   @"normal": @(codecNormalQuality),
                                   @"high": @(codecMaxQuality) };

        if (fps == 0.0) {
            fps = 30.0;
        }

        if (fps < 0.1 || fps > 60) {
            fprintf(stderr, "%s","Error: Framerate must be between 0.1 and 60 fps.\n"
                    "Try 'tlassemble --help' for more information.\n");
            return 1;
        }

        if (codecSpec == nil) {
            codecSpec = @"h264";
        }

        if (![[codec allKeys] containsObject:codecSpec]) {
            usage();
            return 1;
        }

        if (qualitySpec == nil) {
            qualitySpec = @"high";
        }

        if ([[quality allKeys] containsObject:qualitySpec] == NO) {
            usage();
            return 1;
        }

        DLOG(@"quality: %@",qualitySpec);
        DLOG(@"codec: %@",codecSpec);
        DLOG(@"fps: %f",fps);
        DLOG(@"height: %f",height);
        DLOG(@"quiet: %i", quiet);

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *inputPath = [[NSURL fileURLWithPath:[[NSString stringWithUTF8String:argv[1]]
                                                       stringByExpandingTildeInPath]] path];
        NSString *destPath = [[NSURL fileURLWithPath:[[NSString stringWithUTF8String:argv[2]]
                                                      stringByExpandingTildeInPath]] path];

        if (![destPath hasSuffix:@".mov"]) {
            fprintf(stderr, "Error: Output filename must be of type '.mov'\n");
            return 1;
        }

        if ([fileManager fileExistsAtPath:destPath]) {
            fprintf(stderr, "Error: Output file already exists.\n");
            return 1;
        }

        BOOL isDir;
        if (!([fileManager fileExistsAtPath:[destPath stringByDeletingLastPathComponent]
                                isDirectory:&isDir] && isDir)) {
            fprintf(stderr,
                    "Error: Output file is not writable. "
                    "Does the destination directory exist?\n");
            return 1;
        }

        DLOG(@"Input Path: %@", inputPath);
        DLOG(@"Destination Path: %@", destPath);

        if ((([fileManager fileExistsAtPath:inputPath isDirectory:&isDir] && isDir) &&
             [fileManager isWritableFileAtPath:inputPath]) == NO) {
            fprintf(stderr, "%s","Error: Input directory does not exist.\n"
                    "Try 'tlassemble --help' for more information.\n");
            return 1;
        }

        NSDictionary *imageAttributes = @{ QTAddImageCodecType: [codec objectForKey:codecSpec],
                                           QTAddImageCodecQuality: [quality objectForKey:qualitySpec],
                                           QTTrackTimeScaleAttribute: @100000 };

        DLOG(@"%@",imageAttributes);

        NSError *err = nil;
        NSArray *imageFiles = [fileManager contentsOfDirectoryAtPath:inputPath error:&err];
        imageFiles = [imageFiles sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        int imageCount = 0;

        if (reverseArray) {
            NSMutableArray *reversedArray = [NSMutableArray arrayWithCapacity:[imageFiles count]];
            for (NSString *element in [imageFiles reverseObjectEnumerator]) {
                [reversedArray addObject:element];
            }
            imageFiles = reversedArray;
        }

        for (NSString *file in imageFiles) {
            if ([[file pathExtension] caseInsensitiveCompare:@"jpeg"] == NSOrderedSame ||
                [[file pathExtension] caseInsensitiveCompare:@"png"] == NSOrderedSame ||
                [[file pathExtension] caseInsensitiveCompare:@"nef"] == NSOrderedSame ||
                [[file pathExtension] caseInsensitiveCompare:@"jpg"] == NSOrderedSame) {
                imageCount++;
            }
        }

        if (imageCount == 0) {
            fprintf(stderr, "Error: Directory '%s' %s",
                    [[inputPath stringByAbbreviatingWithTildeInPath] UTF8String],
                    "does not contain any jpeg images.\n"
                    "Try 'tlassemble --help' for more information.\n");
            return 1;

        }


        QTMovie *movie = [[QTMovie alloc] initToWritableFile:destPath error:NULL];
        if (movie == nil) {
            fprintf(stderr, "%s","Error: Unable to initialize QT object.\n"
                    "Try 'tlassemble --help' for more information.\n");
            return 1;
        }
        [movie setAttribute:@YES forKey:QTMovieEditableAttribute];

        const long timeScale = 100000;
        const long long timeValue = (long long) ceil((double) timeScale / fps);
        const QTTime duration = QTMakeTime(timeValue, timeScale);
        double width = 0;
        int counter = 0;

        for (NSString *file in imageFiles) {
            NSString *fullFilename = [inputPath stringByAppendingPathComponent:file];
            if ([[fullFilename pathExtension] caseInsensitiveCompare:@"jpeg"] == NSOrderedSame ||
                [[fullFilename pathExtension] caseInsensitiveCompare:@"png"] == NSOrderedSame ||
                [[fullFilename pathExtension] caseInsensitiveCompare:@"nef"] == NSOrderedSame ||
                [[fullFilename pathExtension] caseInsensitiveCompare:@"jpg"] == NSOrderedSame) {
                @autoreleasepool {
                    NSImage *image = [[NSImage alloc] initWithContentsOfFile:fullFilename];

                    if (image) {
                        const double width = (height
                                              ? height * (image.size.width / image.size.height)
                                              : image.size.width);

                        if (!height) {
                            height = image.size.height;
                        }

                        const double kSafeHeightLimit = 2512;
                        if (height > kSafeHeightLimit) {
                            static BOOL warnedOnce = NO;

                            if (!warnedOnce) {
                                fprintf(stderr, "Warning: movies with heights greater than %lf pixels are known to not work sometimes (the resulting movie file will be essentially empty).\n", kSafeHeightLimit);
                                warnedOnce = YES;
                            }
                        }

                        // Always "render" the image, even if not actually resizing, as this ensures formats like NEF actually work (otherwise the output movie gets weird, with one empty, broken track per source image).
                        NSImage *renderedImage = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];

                        if (renderedImage) {
                            [renderedImage lockFocus];
                            [image drawInRect:NSMakeRect(0.f, 0.f, width, height)
                                     fromRect:NSZeroRect
                                    operation:NSCompositeSourceOver fraction:1.f];
                            [renderedImage unlockFocus];

                            [movie addImage:renderedImage
                                forDuration:duration
                             withAttributes:imageAttributes];
                        } else {
                            fprintf(stderr, "Unable to create render buffer for frame \"%s\" with size %lf x %lf (%i of %i)\n", [file UTF8String], width, height, counter, imageCount);
                        }
                    } else {
                        fprintf(stderr, "Unable to read \"%s\" (%i of %i)\n", [file UTF8String], counter, imageCount);
                    }
                }

                counter++;
                if (!quiet) {
                    printf("Processed %s (%i of %i)\n", [file UTF8String], counter, imageCount);
                }
            }
        }

        const BOOL successful = [movie updateMovieFile];
        if (!successful) {
            fprintf(stderr, "Unable to complete creation of movie.\n");
        } else {
            if (!quiet) {
                printf("Successfully created %s\n",[[destPath stringByAbbreviatingWithTildeInPath] UTF8String]);
            }
        }

        return (successful ? 0 : -1);
    }
}

