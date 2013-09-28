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
#define DLOG(fmt, ...) NSLog(@"%s:%d " fmt, __FILE__, __LINE__, ## __VA_ARGS__)
#else
#define DLOG(fmt, ...)
#endif

#include <errno.h>
#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <QTKit/QTKit.h>


int main(int argc, char* const argv[]) {
    @autoreleasepool {
        static const struct option longOptions[] = {
            {"codec",   required_argument,  NULL, 1},
            {"filter",  required_argument,  NULL, 9},
            {"fps",     required_argument,  NULL, 2},
            {"height",  required_argument,  NULL, 3},
            {"help",    no_argument,        NULL, 4},
            {"quality", required_argument,  NULL, 5},
            {"quiet",   no_argument,        NULL, 6},
            {"reverse", no_argument,        NULL, 7},
            {"sort",    required_argument,  NULL, 8},
            {NULL,      0,                  NULL, 0}
        };

        double fps = 30.0;
        long height = 0;
        NSString *codec = @"avc1";
        NSNumber *quality = @(codecMaxQuality);
        BOOL quiet = NO;
        BOOL reverseOrder = NO;
        NSString *sortAttribute = @"creation";
        NSMutableDictionary *filter = [NSMutableDictionary dictionary];

        NSDictionary *codecCodes = @{ @"h264": @"avc1",
                                      @"mpv4": @"mpv4",
                                      @"photojpeg" : @"jpeg",
                                      @"raw": @"raw " };
        NSDictionary *qualityConstants = @{ @"low": @(codecLowQuality),
                                            @"normal": @(codecNormalQuality),
                                            @"high": @(codecMaxQuality) };

        NSDictionary *sortComparators = @{
            @"name": ^(NSURL *a, NSURL *b) {
                return [(reverseOrder ? b : a).lastPathComponent compare:(reverseOrder ? a : b).lastPathComponent
                                                                 options:(   NSCaseInsensitiveSearch
                                                                           | NSNumericSearch
                                                                           | NSDiacriticInsensitiveSearch
                                                                           | NSWidthInsensitiveSearch
                                                                           | NSForcedOrderingSearch)];
            },
            @"creation": ^(NSURL *a, NSURL *b) {
                id aCreationDate = nil, bCreationDate = nil;
                NSError *err = nil;

                if (![a getResourceValue:&aCreationDate forKey:NSURLCreationDateKey error:&err]) {
                    fprintf(stderr, "Unable to determine the creation date of \"%s\".\n", a.path.UTF8String);
                    return (reverseOrder ? NSOrderedAscending : NSOrderedDescending);
                } else if (![b getResourceValue:&bCreationDate forKey:NSURLCreationDateKey error:&err]) {
                    fprintf(stderr, "Unable to determine the creation date of \"%s\".\n", b.path.UTF8String);
                    return (reverseOrder ? NSOrderedDescending : NSOrderedAscending);
                } else {
                    return (reverseOrder ? [bCreationDate compare:aCreationDate] : [aCreationDate compare:bCreationDate]);
                }
            }
        };
        NSDictionary *sortFileAttributeKeys = @{ @"name" : @[],
                                                 @"creation": @[NSURLCreationDateKey] };

        int optionIndex = 0;
        while (-1 != (optionIndex = getopt_long(argc, argv, "", longOptions, NULL))) {
            switch (optionIndex) {
                case 1:
                    codec = codecCodes[@(optarg)];
                    if (!codec) {
                        fprintf(stderr, "Unsupported codec \"%s\".  Supported codecs are:", optarg);

                        for (NSString *code in codecCodes) {
                            fprintf(stderr, " %s", code.UTF8String);
                        }

                        fprintf(stderr, "\n");

                        return EINVAL;
                    }
                    break;
                case '2': {
                    char *end = NULL;
                    fps = strtod(optarg, &end);
                    if (!end || *end || (0 >= fps)) {
                        fprintf(stderr, "Invalid argument \"%s\" to --fps.  Should be a non-zero, positive real value (e.g. 24.0, 29.97, etc).\n", optarg);
                        return EINVAL;
                    }
                    break;
                }
                case 3: {
                    char *end = NULL;
                    height = strtol(optarg, &end, 0);
                    if (!end || *end || (0 >= height)) {
                        fprintf(stderr, "Invalid argument \"%s\" to --height.  Should be a non-zero, positive integer.\n", optarg);
                        return EINVAL;
                    }
                    break;
                }
                case 4:
                    printf("Usage: %s [FLAGS...] SOURCE [SOURCE...] DESTINATION.MOV\n"
                           "\n"
                           "SOURCE must be specified at least once.  Each instance is the name or path to an image file or a folder containing images.  Folders are searched exhaustively and recursively (but symlinks are not followed).  Images which cannot be opened will be skipped.  If no valid images are found, the program will fail and return a non-zero exit status.\n"
                           "\n"
                           "DESTINATION specifies the output file for the movie.  It must end with a '.mov' suffix and must not already exist.\n"
                           "\n"
                           "FLAGS:\n"
                           "\t--codec: Codec with which to compress the resulting movie.  Defaults to 'h264'.\n"
                           "\t--fps: Frame rate of the movie.  Defaults to 30.\n"
                           "\t--height: The desired height of the movie; source frames will be proportionately resized.  If unspecified the height is taken from the source frames.\n"
                           "\t--quality: Quality level to encode with can.  Defaults to 'high'.\n"
                           "\t--quiet: Supresses non-error output.  Off by default.\n"
                           "\t--reverse: Reverse the sort order.\n"
                           "\t--sort: Sort method for the input images.  Defaults to 'creation'.\n"
                           "\n"
                           "EXAMPLES\n"
                           "\t%s ./images time_lapse.mov\n"
                           "\t%s --fps 30 --height 720 --codec h264 --quality high imagesA imagesB time_lapse.mov\n"
                           "\t%s --quiet image01.jpg image02.jpg image03.jpg time_lapse.mov\n"
                           "\n"
                           "WARRANTY\n"
                           "There isn't one.  This software is provided in the hope that it will be useful, but without any warranty, without even the implied warranty for merchantability or fitness for a particular purpose.  The software is provided as-is and its authors are not to be held responsible for any harm that may result from its use, including (but not limited to) data loss or corruption.\n",
                           argv[0], argv[0], argv[0], argv[0]);
                    return 0;
                case 5:
                    quality = qualityConstants[@(optarg)];
                    if (!quality) {
                        fprintf(stderr, "Unsupported quality \"%s\".  Supported qualities are:", optarg);

                        for (NSString *qualityConstant in qualityConstants) {
                            fprintf(stderr, " %s", qualityConstant.UTF8String);
                        }

                        fprintf(stderr, "\n");

                        return EINVAL;
                    }
                    break;
                case 6:
                    quiet = YES;
                    break;
                case 7:
                    reverseOrder = YES;
                    break;
                case 8:
                    sortAttribute = @(optarg);
                    if (!sortComparators[sortAttribute]) {
                        fprintf(stderr, "Unsupported sort method \"%s\".  Supported methods are:", optarg);

                        for (NSString *method in sortComparators) {
                            fprintf(stderr, " %s", method.UTF8String);
                        }

                        fprintf(stderr, "\n");

                        return EINVAL;
                    }
                    break;
                case 9: {
                    NSArray *pair = [@(optarg) componentsSeparatedByString:@"="];

                    if (2 == pair.count) {
                        NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
                        filter[[pair[0] stringByTrimmingCharactersInSet:whitespace]] = [pair[1] stringByTrimmingCharactersInSet:whitespace];
                    } else {
                        fprintf(stderr, "Unable to parse filter argument \"%s\" - expected something like 'property = value'.\n", optarg);
                        return EINVAL;
                    }

                    break;
                }
                default:
                    fprintf(stderr, "Invalid arguments (%d).\n", optionIndex);
                    return EINVAL;
            }
        }
        const char *invocationString = argv[0];
        argc -= optind;
        argv += optind;

        if (2 > argc) {
            fprintf(stderr, "Usage: %s [FLAGS...] SOURCE [SOURCE...] DESTINATION.MOV\n", invocationString);
            return EINVAL;
        }

        DLOG(@"filter: %@", filter);
        DLOG(@"fps: %f", fps);
        DLOG(@"height: %ld", height);
        DLOG(@"codec: %@", codec);
        DLOG(@"quality: %@", quality);
        DLOG(@"quiet: %s", (quiet ? "YES" : "NO"));
        DLOG(@"sort: %@ (%s)", sortAttribute, (reverseOrder ? "reversed" : "normal"));

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *destPath = [[NSURL fileURLWithPath:[[NSString stringWithUTF8String:argv[argc - 1]]
                                                      stringByExpandingTildeInPath]] path];
        DLOG(@"Destination Path: %@", destPath);

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

        NSMutableArray *imageFiles = [NSMutableArray array];

        for (int i = 0; i < argc - 1; ++i) {
            NSURL *inputPath = [NSURL fileURLWithPath:[[NSString stringWithUTF8String:argv[i]] stringByExpandingTildeInPath]];

            DLOG(@"Input Path: %@", inputPath);

            if (![fileManager fileExistsAtPath:inputPath.path isDirectory:&isDir]) {
                fprintf(stderr, "Error: \"%s\" does not exist.\n", argv[i]);
                return EINVAL;
            }

            if (isDir) {
                NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL:inputPath
                                                               includingPropertiesForKeys:sortFileAttributeKeys[sortAttribute]
                                                                                  options:(   NSDirectoryEnumerationSkipsHiddenFiles
                                                                                            | NSDirectoryEnumerationSkipsPackageDescendants)
                                                                             errorHandler:^(NSURL *url, NSError *error) {
                    fprintf(stderr, "Error while looking for images in \"%s\": %s\n", url.path.UTF8String, error.localizedDescription.UTF8String);
                    return YES;
                }];

                if (!directoryEnumerator) {
                    fprintf(stderr, "Unable to enumerate files in \"%s\".\n", inputPath.path.UTF8String);
                    return -1;
                }

                for (NSURL *file in directoryEnumerator) {
                    [imageFiles addObject:file];
                }
            } else {
                [imageFiles addObject:inputPath];
            }
        }

        if (0 == imageFiles.count) {
            fprintf(stderr, "No files found in input path(s).\n");
            return -1;
        }
        
        [imageFiles sortWithOptions:NSSortConcurrent usingComparator:sortComparators[sortAttribute]];

        QTMovie *movie = [[QTMovie alloc] initToWritableFile:destPath error:nil];
        if (movie == nil) {
            fprintf(stderr, "%s","Error: Unable to initialize QT object.\n"
                    "Try 'tlassemble --help' for more information.\n");
            return 1;
        }
        [movie setAttribute:@YES forKey:QTMovieEditableAttribute];

        NSDictionary *imageAttributes = @{ QTAddImageCodecType: codec,
                                           QTAddImageCodecQuality: quality,
                                           QTTrackTimeScaleAttribute: @100000 };

        DLOG(@"%@",imageAttributes);

        NSDictionary *imageSourceOptions = @{ (__bridge NSString*)kCGImageSourceShouldAllowFloat: @YES };

        const long timeScale = 100000;
        const long long timeValue = (long long) ceil((double) timeScale / fps);
        const QTTime duration = QTMakeTime(timeValue, timeScale);
        unsigned long fileIndex = 1;  // Human-readable, so 1-based.
        unsigned long framesAddedSuccessfully = 0;
        NSSize lastFrameSize = {0, 0};

        for (NSURL *file in imageFiles) {
            @autoreleasepool {
                CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)file, (__bridge CFDictionaryRef)imageSourceOptions);

                if (imageSource) {
                    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageSourceOptions));

                    if (imageProperties) {
                        NSLog(@"Properties of \"%@\" are: %@", file.path, imageProperties);

                        CGImageRef rawImage = CGImageSourceCreateImageAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageSourceOptions);

                        if (rawImage) {
                            NSImage *image = [[NSImage alloc] initWithCGImage:rawImage size:NSZeroSize];

                            if (image) {
                                if ((0 != lastFrameSize.width) && (0 != lastFrameSize.height)) {
                                    if ((lastFrameSize.width != image.size.width) || (lastFrameSize.height != image.size.height)) {
                                        fprintf(stderr,
                                                "Frame #%lu had the size %llu x %llu, but frame #%lu has size %llu x %llu.  The resulting movie will probably be deformed.\n",
                                                fileIndex - 1,
                                                (unsigned long long)lastFrameSize.width,
                                                (unsigned long long)lastFrameSize.height,
                                                fileIndex,
                                                (unsigned long long)image.size.width,
                                                (unsigned long long)image.size.height);
                                    }
                                }
                                lastFrameSize = image.size;

                                const long width = (height
                                                    ? height * (image.size.width / image.size.height)
                                                    : image.size.width);

                                if (!height) {
                                    height = image.size.height;
                                }

                                const unsigned long kSafeHeightLimit = 2512;
                                if (height > kSafeHeightLimit) {
                                    static BOOL warnedOnce = NO;

                                    if (!warnedOnce) {
                                        fprintf(stderr, "Warning: movies with heights greater than %lu pixels are known to not work sometimes (the resulting movie file will be essentially empty).\n", kSafeHeightLimit);
                                        warnedOnce = YES;
                                    }
                                }

                                // Always "render" the image, even if not actually resizing, as this ensures formats like NEF work reliably (as otherwise there seems to be some intermitent glitching).
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

                                    ++framesAddedSuccessfully;

                                    if (!quiet) {
                                        printf("Processed %s (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                                    }
                                } else {
                                    fprintf(stderr, "Unable to create render buffer for frame \"%s\" with size %ld x %ld (%lu of %lu)\n", file.path.UTF8String, width, height, fileIndex, imageFiles.count);
                                }
                            } else {
                                fprintf(stderr, "Unable to Cocoaify \"%s\" (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                            }

                            CGImageRelease(rawImage);
                        } else {
                            fprintf(stderr, "Unable to render \"%s\" (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                        }
                    } else {
                        fprintf(stderr, "Unable to get metadata for \"%s\" (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                    }

                    CFRelease(imageSource);
                } else {
                    fprintf(stderr, "Unable to read \"%s\" (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                }
            }

            ++fileIndex;
        }

        if (0 < framesAddedSuccessfully) {
            if (![movie updateMovieFile]) {
                fprintf(stderr, "Unable to complete creation of movie (usually meaning QTKitServer just crashed due to a bug - sorry, not my fault).\n");
                return -1;
            } else {
                if (framesAddedSuccessfully != imageFiles.count) {
                    fprintf(stderr, "Warning: source folder contained %lu files but only %lu were readable as images.\n", imageFiles.count, framesAddedSuccessfully);
                } else {
                    if (!quiet) {
                        printf("Successfully created %s\n", [destPath stringByAbbreviatingWithTildeInPath].UTF8String);
                    }
                }

                return 0;
            }
        } else {
            fprintf(stderr, "None of the %lu input files were readable as images.\n", imageFiles.count);
            return -1;
        }
    }
}

