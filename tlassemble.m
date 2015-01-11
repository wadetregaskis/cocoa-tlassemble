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

#include <errno.h>
#include <getopt.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <VideoToolbox/VideoToolbox.h>
#import <VideoToolbox/VTVideoEncoderList.h>


static unsigned long logLevel = 0;

static const unsigned long V_CONFIGURATION = 1;
static const unsigned long V_CONFIGURATION_OPTIONS = 2;
static const unsigned long V_FRAME_METADATA = 3;

#define DLOG(level, fmt, ...) ({ if (level <= logLevel) { NSLog(@"%s:%d " fmt, __FILE__, __LINE__, ## __VA_ARGS__); } })

#define LOG_WARNING(format, ...) ({ fflush(stdout); fprintf(stderr, "%s", [NSString stringWithFormat:@"WARNING: " format "\n", ## __VA_ARGS__].UTF8String); fflush(stderr); })
#define LOG_ERROR(format, ...) ({ fflush(stdout); fprintf(stderr, "%s", [NSString stringWithFormat:@"ERROR: " format "\n", ## __VA_ARGS__].UTF8String); fflush(stderr); })

static const double kDefaultFPS = 30;


static const char* DescriptionOfCVReturn(CVReturn status) {
    switch (status) {
        case kCVReturnError:
            return "An otherwise undefined error occurred.";
        case kCVReturnInvalidArgument:
            return "Invalid function parameter. For example, out of range or the wrong type.";
        case kCVReturnAllocationFailed:
            return "Memory allocation for a buffer or buffer pool failed.";
        case kCVReturnInvalidDisplay:
            return "The display specified when creating a display link is invalid.";
        case kCVReturnDisplayLinkAlreadyRunning:
            return "The specified display link is already running.";
        case kCVReturnDisplayLinkNotRunning:
            return "The specified display link is not running.";
        case kCVReturnDisplayLinkCallbacksNotSet:
            return "No callback registered for the specified display link. You must set either the output callback or both the render and display callbacks.";
        case kCVReturnInvalidPixelFormat:
            return "The buffer does not support the specified pixel format.";
        case kCVReturnInvalidSize:
            return "The buffer cannot support the requested buffer size (usually too big).";
        case kCVReturnInvalidPixelBufferAttributes:
            return "A buffer cannot be created with the specified attributes.";
        case kCVReturnPixelBufferNotOpenGLCompatible:
            return "The pixel buffer is not compatible with OpenGL due to an unsupported buffer size, pixel format, or attribute.";
        case kCVReturnWouldExceedAllocationThreshold:
            return "Allocation for a pixel buffer failed because the threshold value set for the kCVPixelBufferPoolAllocationThresholdKey key in the CVPixelBufferPoolCreatePixelBufferWithAuxAttributes function would be surpassed.";
        case kCVReturnPoolAllocationFailed:
            return "Allocation for a buffer pool failed, most likely due to a lack of resources. Check to make sure your parameters are in range.";
        case kCVReturnInvalidPoolAttributes:
            return "A buffer pool cannot be created with the specified attributes.";
        default:
            return "Unknown.";
    }
}

static CVPixelBufferRef CreatePixelBufferFromCGImage(CGImageRef image, NSSize frameSize) {
    // I've seen the following two settings recommended, but I'm not sure why we'd bother overriding them?
    //NSDictionary *pixelBufferOptions = @{kCVPixelBufferCGImageCompatibilityKey: @NO,
    //                                     kCVPixelBufferCGBitmapContextCompatibilityKey, @NO};
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameSize.width,
                                          frameSize.height,
                                          kCVPixelFormatType_32ARGB,
                                          NULL,
                                          &pixelBuffer);

    if (kCVReturnSuccess == status) {
        status = CVPixelBufferLockBaseAddress(pixelBuffer, 0);

        if (kCVReturnSuccess == status) {
            void *data = CVPixelBufferGetBaseAddress(pixelBuffer);

            if (data) {
                CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();

                if (colourSpace) {
                    CGContextRef context = CGBitmapContextCreate(data,
                                                                 frameSize.width,
                                                                 frameSize.height,
                                                                 8, // Bits per component
                                                                 CVPixelBufferGetBytesPerRow(pixelBuffer),
                                                                 colourSpace,
                                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst); // + kCGBitmapByteOrder32Big?  Or 16Big?

                    if (context) {
                        CGContextDrawImage(context,
                                           CGRectMake(0, 0, frameSize.width, frameSize.height),
                                           image);
                        CGContextRelease(context);
                    } else {
                        LOG_ERROR("Unable to create a new bitmap context around the pixel buffer.");
                        status = kCVReturnError;
                    }

                    CGColorSpaceRelease(colourSpace);
                } else {
                    LOG_ERROR("Unable to create a device RGB colour space.");
                }
            } else {
                LOG_ERROR("Unable to get a raw pointer to the pixel buffer.");
                status = kCVReturnError;
            }

            const CVReturn nonFatalStatus = CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

            if (kCVReturnSuccess != nonFatalStatus) {
                LOG_WARNING("Unable to unlock pixel buffer, error #%d: %s", nonFatalStatus, DescriptionOfCVReturn(nonFatalStatus));
            }
        } else {
            LOG_ERROR("Unable to lock pixel buffer, error #%d: %s", status, DescriptionOfCVReturn(status));
        }
    } else {
        LOG_ERROR("Unable to create a pixel buffer, error #%d: %s", status, DescriptionOfCVReturn(status));
    }

    if (kCVReturnSuccess != status) {
        CVPixelBufferRelease(pixelBuffer), pixelBuffer = NULL;
    }

    return pixelBuffer;
}

const char* NameOfAVAssetWriterStatus(AVAssetWriterStatus status) {
    switch (status) {
        case AVAssetWriterStatusUnknown:
            return "Unknown";
        case AVAssetWriterStatusWriting:
            return "Writing";
        case AVAssetWriterStatusCompleted:
            return "Completed";
        case AVAssetWriterStatusFailed:
            return "Failed";
        case AVAssetWriterStatusCancelled:
            return "Cancelled";
        default:
            return "Especially unknown";
    }
}

@interface FrameOutputContext : NSObject
@property(readwrite) AVAssetWriter *assetWriter;
@property(readwrite) AVAssetWriterInput *assetWriterInput;
@property(readwrite) BOOL quiet;
@end

@implementation FrameOutputContext
@end

static void compressedFrameOutput(void *rawContext,
                                  void *frameNumber,
                                  OSStatus status,
                                  VTEncodeInfoFlags infoFlags,
                                  CMSampleBufferRef sampleBuffer) {
    if (0 != status) {
        LOG_ERROR("Unable to compress frame #%"PRIuPTR", error #%d.", (uintptr_t)frameNumber, status);
        exit(1);
    }

    FrameOutputContext *context = (__bridge FrameOutputContext*)rawContext;

    if (context) {
        if (context.assetWriterInput) {
            if ([context.assetWriterInput appendSampleBuffer:sampleBuffer]) {
                if (!context.quiet) {
                    printf("Completed frame #%"PRIuPTR".\n", (uintptr_t)frameNumber);
                }
            } else {
                LOG_ERROR("Unable to append compressed frame #%"PRIuPTR" to file, status = %s (%s).",
                          (uintptr_t)frameNumber,
                          NameOfAVAssetWriterStatus(context.assetWriter.status),
                          context.assetWriter.error.description.UTF8String);
                exit(1);
            }
        }
    }
}

#ifndef countof
#define countof(_x_) (sizeof(_x_) / sizeof(*_x_))
#endif

static BOOL applyTimeSuffix(double *value, const char *suffix, BOOL invert) {
    const struct {
        char suffix[3];
        double multiplier;
    } suffixes[] = {
        {"w", 604800.0},
        {"d", 86400.0},
        {"h", 3600.0},
        {"m", 60.0},
        {"s", 1.0},
        {"ms", 0.001},
        {"us", 0.000001},
        {"µs", 0.000001},
        {"ns", 0.000000001},
        {"ps", 0.000000000001},
    };

    for (int i = 0; i < countof(suffixes); ++i) {
        if (0 == strcmp(suffix, suffixes[i].suffix)) {
            if (invert) {
                *value /= suffixes[i].multiplier;
            } else {
                *value *= suffixes[i].multiplier;
            }

            return YES;
        }
    }

    return NO;
}

static BOOL applyBitSuffix(double *value, const char *suffix) {
    const char kModifiers[] = "KMGTPEZY";
    const char *modifier = (('k' == suffix[0]) ? kModifiers : strchr(kModifiers, suffix[0]));

    if (modifier) {
        const uintptr_t factor = (uintptr_t)modifier - (uintptr_t)kModifiers + 1;
        const BOOL baseTwo = ('i' == suffix[1]);

        *value *= (baseTwo ? exp2(factor * 10) : __exp10(factor * 3));
        ++suffix;

        if (baseTwo) {
            ++suffix;
        }
    }

    switch (suffix[0]) {
        case 'b':
            // Do nothing.
            break;
        case 'B':
            *value *= 8;
            break;
        case 0:
            // Do nothing.
            break;
        default:
            return NO;
    }

    return YES;
}

static BOOL applyBitRateSuffix(double *value, const char *suffix) {
    char *divider = strchr(suffix, '/');

    if (divider) {
        char *bytePortion = strndup(suffix, divider - suffix);
        assert(bytePortion);

        BOOL allGood = applyBitSuffix(value, bytePortion);
        free(bytePortion);

        if (allGood) {
            return applyTimeSuffix(value, divider + 1, YES);
        } else {
            return NO;
        }
    } else {
        return applyBitSuffix(value, suffix);
    }
}

static BOOL determineBitsPerTimeInterval(double *bits, double *timeInterval, const char *suffix) {
    char *divider = strchr(suffix, '/');

    if (divider) {
        char *bytePortion = strndup(suffix, divider - suffix);
        assert(bytePortion);

        BOOL allGood = applyBitSuffix(bits, bytePortion);
        free(bytePortion);

        if (allGood) {
            char *end = NULL;
            double timeScalar = strtod(divider + 1, &end);

            if (end) {
                if (end == divider + 1) {
                    timeScalar = 1;
                }

                *timeInterval *= timeScalar;

                if (*end) {
                    return applyTimeSuffix(timeInterval, end, YES);
                } else {
                    return YES;
                }
            } else {
                return NO;
            }
        } else {
            return NO;
        }
    } else {
        return applyBitSuffix(bits, suffix);
    }
}

void prescanFile(NSURL *file, const double speed, NSDate **earliestFrame, NSDate **latestFrame, NSMutableDictionary *fileCreationDates, NSMutableArray *imageFiles) {
    BOOL fileLooksGood = YES;

    if (0 < speed) {
        // Unfortunately the file system's idea of creation date is often not very precise, nor accurate - some cameras (e.g. D7100) can end up creating files roughly simultaneously, despite the images of course being sequential (presumably as some kind of batching optimisation when emptying the in-camera image buffer).  So we try to get the actual recording time of the image out of the EXIF metadata, and only fall back to the file's creation date as a last resort.

        id creationDate;
        NSError *err;

        NSDictionary *imageSourceOptions = @{ (__bridge NSString*)kCGImageSourceShouldAllowFloat: @YES,
                                              (__bridge NSString*)kCGImageSourceShouldCache: @NO,
                                              (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageIfAbsent: @NO,
                                              (__bridge NSString*)kCGImageSourceCreateThumbnailFromImageAlways: @NO };

        CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)file, (__bridge CFDictionaryRef)imageSourceOptions);

        if (imageSource) {
            NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageSourceOptions));

            if (imageProperties) {
                NSDictionary *exifProperties = imageProperties[(__bridge NSString*)kCGImagePropertyExifDictionary];

                if (exifProperties) {
                    NSString *dateAsString = exifProperties[(__bridge NSString*)kCGImagePropertyExifDateTimeOriginal];
                    DLOG(V_FRAME_METADATA, @"Raw creation date for \"%@\": %@", file.path, dateAsString);
                    creationDate = [NSDate dateWithNaturalLanguageString:dateAsString];
                }
            } else {
                LOG_ERROR("Unable to get image metadata for \"%@\".", file.path);
                fileLooksGood = NO;
            }

            CFRelease(imageSource);
        } else {
            LOG_ERROR("Unable to create an image source for \"%@\".", file.path);
            fileLooksGood = NO;
        }

        if (!creationDate) {
            if (![file getResourceValue:&creationDate forKey:NSURLCreationDateKey error:&err]) {
                LOG_ERROR("Unable to determine the creation date of \"%@\".", file.path);
                fileLooksGood = NO;
            }
        }

        if (creationDate) {
            DLOG(V_FRAME_METADATA, @"Creation date of \"%@\": %@", file.path, creationDate);
            fileCreationDates[file] = creationDate;

            *earliestFrame = (*earliestFrame ? [*earliestFrame earlierDate:creationDate] : creationDate);
            *latestFrame = (*latestFrame ? [*latestFrame laterDate:creationDate] : creationDate);
        }
    }

    if (fileLooksGood) {
        [imageFiles addObject:file];
    }
}

int main(int argc, char* const argv[]) {
    @autoreleasepool {
        static const struct option longOptions[] = {
            {"assume-preceding-frames",     no_argument,        NULL, 16},
            {"assume-succeeding-frames",    no_argument,        NULL, 17},
            {"average-bit-rate",            required_argument,  NULL, 14},
            {"codec",                       required_argument,  NULL,  1},
            {"dryrun",                      no_argument,        NULL, 10},
            {"entropy-mode",                required_argument,  NULL, 18},
            {"file-type",                   required_argument,  NULL, 20},
            {"filter",                      required_argument,  NULL,  9},
            {"fps",                         required_argument,  NULL,  2},
            {"frame-limit",                 required_argument,  NULL, 22},
            {"height",                      required_argument,  NULL,  3},
            {"help",                        no_argument,        NULL,  4},
            {"key-frames-only",             no_argument,        NULL, 12},
            {"max-frame-delay",             required_argument,  NULL, 19},
            {"max-key-frame-period",        required_argument,  NULL, 11},
            {"quality",                     required_argument,  NULL,  5},
            {"quiet",                       no_argument,        NULL,  6},
            {"rate-limit",                  required_argument,  NULL, 15},
            {"reverse",                     no_argument,        NULL,  7},
            {"speed",                       required_argument,  NULL, 21},
            {"sort",                        required_argument,  NULL,  8},
            {"strict-frame-ordering",       no_argument,        NULL, 13},
            {"verbosity",                   required_argument,  NULL, 23},
            {NULL,                          0,                  NULL,  0}
        };

        NSMutableDictionary *compressionSettings = [NSMutableDictionary dictionary];

        double fps = 0.0;
        double speed = 0.0;
        long height = 0;
        CMVideoCodecType codec = 'avc1';
        NSString *encoderID;
        NSString *fileType;
        BOOL quiet = NO;
        BOOL reverseOrder = NO;
        NSString *sortAttribute = @"creation";
        NSMutableDictionary *filter = [NSMutableDictionary dictionary];
        BOOL dryrun = NO;
        unsigned long long frameLimit = -1;

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
                    LOG_ERROR("Unable to determine the creation date of \"%@\".", a.path);
                    return (reverseOrder ? NSOrderedAscending : NSOrderedDescending);
                } else if (![b getResourceValue:&bCreationDate forKey:NSURLCreationDateKey error:&err]) {
                    LOG_ERROR("Unable to determine the creation date of \"%@\".", b.path);
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
                case 1: {
                    CFArrayRef supportedVideoEncoders = NULL;
                    const OSStatus status = VTCopyVideoEncoderList(NULL, &supportedVideoEncoders);

                    if (0 != status) {
                        LOG_ERROR("Unable to determine the supported video codecs, error #%d.", status);
                        return 1;
                    }

                    NSMutableDictionary *codecMap = [NSMutableDictionary dictionary];
                    NSMutableDictionary *encoderMap = [NSMutableDictionary dictionary];

                    for (NSDictionary *codecSpec in CFBridgingRelease(supportedVideoEncoders)) {
                        NSString *codecName = codecSpec[(__bridge NSString*)kVTVideoEncoderList_DisplayName];

                        if (codecMap[codecName]) {
                            LOG_WARNING("Found two encoders with the same name - \"%@\".", codecName);
                        }

                        codecMap[codecName] = codecSpec[(__bridge NSString*)kVTVideoEncoderList_CodecType];
                        encoderMap[codecName] = codecSpec[(__bridge NSString*)kVTVideoEncoderList_EncoderID];
                    }

                    codec = ((NSNumber*)codecMap[@(optarg)]).intValue;
                    encoderID = encoderMap[@(optarg)];

                    if (!codec || !encoderID) {
                        LOG_ERROR("Unrecognised codec \"%s\".  Supported codecs are:", optarg);

                        for (NSString *code in [codecMap.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
                            LOG_ERROR("    %@", code);
                        }

                        return EINVAL;
                    }

                    break;
                }
                case '2': {
                    char *end = NULL;
                    fps = strtod(optarg, &end);

                    if (!end || (end == optarg) || *end || (0 >= fps)) {
                        LOG_ERROR("Invalid argument \"%s\" to --fps.  Should be a non-zero, positive real value (e.g. 24.0, 29.97, etc).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 3: {
                    char *end = NULL;
                    height = strtol(optarg, &end, 0);

                    if (!end || (end == optarg) || *end || (0 >= height)) {
                        LOG_ERROR("Invalid argument \"%s\" to --height.  Should be a non-zero, positive integer.", optarg);
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
                           "\n",
                           argv[0]);
                    printf("FLAGS:\n"
                           "\t--assume-preceding-frames: Assume additional frames will be prefixed to the output movie file later, so adjust encoding settings to accomodate.\n"
                           "\t--assume-succeeding-frames: Assume additional frames will be appended to the output movie file later, so adjust encoding settings to accomodate.\n"
                           "\t--average-bit-rate: The target average bitrate, e.g. \"3mb\" or \"450kB\".  Actual bitrate may fluctuate above and below this goal.\n"
                           "\t--codec: Codec with which to compress the resulting movie.  Defaults to 'h264'.\n"
                           "\t--dryrun: Don't actually create the output movie.  Simulates most of the process, however, to give you a good idea of how it'd go.  Off by default.\n"
                           "\t--entropy-mode: Either \"CAVLC\" or \"CABAC\".  CABAC generally yields better compression, at the expense of higher CPU usage in encoding and playback.\n"
                           "\t--file-type: The format for the output file - one of \"mov\", \"mp4\" or \"m4v\".  The default is \"mov\", or derived from the output file name (if specified and with a file extension).\n"
                           "\t--filter: Specify a filter on the image metadata for each frame.  e.g. 'Model=Nikon D5200'.  May be specified multiple times to add successive filters.  Filters are case insensitive.\n"
                           "\t--fps: Frame rate of the movie.  Defaults to 30.\n"
                           "\t--frame-limit: The maximum number of frames to encode.  This is mainly useful for encoding testing and 'dry-running', by letting you limit the encode to just an initial subset of the full movie.\n"
                           "\t--height: The desired height of the movie; source frames will be proportionately resized.  If unspecified the height is taken from the source frames.\n"
                           "\t--help: Prints out this usage information.\n"
                           "\t--key-frames-only: Use only 'key' frames (I-frames).  This yields larger video files, but ones which may exhibit less quality loss as a result of subsequent editing (e.g. in Final Cut Pro or iMovie).\n"
                           "\t--max-frame-delay: The maximum number of frames that the encoder may hold in its internal buffer, during compression.  This basically limits how far, forward or back, the encoder can go to reference other frames during temporal compression.  Smaller values typically make the output video slightly larger, but compatible with a wider range of playback devices.\n"
                           "\t--max-key-frame-period: The maximum amount of time (if a time unit is specified, e.g. \"5s\" or \"10ms\") or number of frames (if just a number is specified, e.g. \"25\" or \"10\") between key frames (I-frames).  Higher values permit better compression, but make the output video more difficult for subsequent editing software to use [without losing quality], and may prevent correct playback on some devices.\n"
                           "\t--quality: Quality level to encode with can.  Defaults to 'high'.\n"
                           "\t--quiet: Supresses non-error output.  Off by default.\n"
                           "\t--rate-limit: The absolute date rate limit (as opposed to --average-bit-rate, for example).  Useful for compatibility with lesser playback devices, which may not be able to handle bitrates above a certain threshold.\n"
                           "\t--reverse: Reverse the sort order.\n"
                           "\t--sort: Sort method for the input images.  Defaults to 'creation'.\n"
                           "\t--speed: How much to speed up the frames versus real time (when they were captured).  By default each frame is simply blindly played back a fixed interval of time after the previous (i.e. 1 / --fps).  When this parameter is specified, the real time relation between each frame is preserved (albeit shrunk by this multiplier).  This is particularly useful if your interval between frames changed during shooting (e.g. due to changing light changing shutter speed).  It can also yield more natural results if there are missing frames or otherwise gaps in recording.\n"
                           "\t--strict-frame-ordering: If specified, disables frame reordering.  Resulting output files will be compatible with more playback devices but the video quality may suffer.\n"
                           "\t--verbosity: A numeric verbosity level, either 0 (i.e. verbose logging off, the default), 1, 2, or 3 (corresponding to increasing levels of detail).  Typically useful only for debugging and development.\n"

                           "\n");
                    printf("EXAMPLES\n"
                           "\t%s ./images time_lapse.mov\n"
                           "\t%s --fps 30 --height 720 --codec h264 --quality high imagesA imagesB time_lapse.mov\n"
                           "\t%s --quiet image01.jpg image02.jpg image03.jpg time_lapse.mov\n"
                           "\n"
                           "WARRANTY\n"
                           "There isn't one.  This software is provided in the hope that it will be useful, but without any warranty, without even the implied warranty for merchantability or fitness for a particular purpose.  The software is provided as-is and its authors are not to be held responsible for any harm that may result from its use, including (but not limited to) data loss or corruption.\n",
                           argv[0], argv[0], argv[0]);
                    return 0;
                case 5: {
                    char *end = NULL;
                    const double quality = strtod(optarg, &end);

                    if (end && (end != optarg) && !*end && (0.0 <= quality) && (1.0 >= quality)) {
                        compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_Quality] = @(quality);
                    } else {
                        LOG_ERROR("Invalid --quality argument \"%s\" - expect a floating-point value between 0.0 and 1.0 (inclusive).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 6:
                    quiet = YES;
                    break;
                case 7:
                    reverseOrder = YES;
                    break;
                case 8:
                    sortAttribute = @(optarg);

                    if (!sortComparators[sortAttribute]) {
                        LOG_ERROR("Unsupported sort method \"%s\".  Supported methods are:", optarg);

                        for (NSString *method in sortComparators) {
                            LOG_ERROR("    %@", method);
                        }

                        return EINVAL;
                    }

                    break;
                case 9: {
                    NSArray *pair = [@(optarg) componentsSeparatedByString:@"="];

                    if (2 == pair.count) {
                        NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
                        filter[[pair[0] stringByTrimmingCharactersInSet:whitespace].lowercaseString] = [pair[1] stringByTrimmingCharactersInSet:whitespace];
                    } else {
                        LOG_ERROR("Unable to parse filter argument \"%s\" - expected something like 'property = value'.", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 10:
                    dryrun = YES;
                    break;
                case 11: {
                    BOOL allGood = NO;
                    char *end = NULL;
                    double max = strtod(optarg, &end);

                    if (end && (end != optarg)) {
                        if (*end) {
                            if (applyTimeSuffix(&max, end, NO)) {
                                compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration] = @(max);
                                allGood = YES;
                            }
                        } else {
                            compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_MaxKeyFrameInterval] = @(lround(max));
                            allGood = YES;
                        }
                    }

                    if (!allGood) {
                        LOG_ERROR("Invalid parameter \"%s\" to --max_key_frame_period.  Expected an integer number of frames or a floating-point unit of time with appropriate suffix (e.g. 's', 'ms', etc).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 12:
                    compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_AllowTemporalCompression] = @(NO);
                    break;
                case 13:
                    compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_AllowFrameReordering] = @(NO);
                    break;
                case 14: {
                    char *end = NULL;
                    double averageBitRate = strtod(optarg, &end);
                    BOOL allGood = NO;

                    if (end && (end != optarg)) {
                        if (*end) {
                            if (applyBitRateSuffix(&averageBitRate, end)) {
                                allGood = YES;
                            }
                        } else {
                            allGood = YES;
                        }
                    }

                    if (allGood) {
                        compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_AverageBitRate] = @(averageBitRate);
                    } else {
                        LOG_ERROR("Invalid --average-bit-rate argument \"%s\" - expected a floating-point number optionally followed by units (e.g. 'Mb' [implied per second] or 'kB/ms' etc).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 15: {
                    char *end = NULL;
                    double rateLimit = strtod(optarg, &end);
                    double interval = 1;
                    BOOL allGood = NO;

                    if (end && (end != optarg)) {
                        if (*end) {
                            if (determineBitsPerTimeInterval(&rateLimit, &interval, end)) {
                                allGood = YES;
                            }
                        } else {
                            allGood = YES;
                        }
                    }

                    if (allGood) {
                        if (!compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_DataRateLimits]) {
                            compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_DataRateLimits] = [NSMutableArray array];
                        }

                        [compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_DataRateLimits] addObject:@(rateLimit)];
                        [compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_DataRateLimits] addObject:@(interval)];
                    } else {
                        LOG_ERROR("Invalid --rate-limit argument \"%s\" - expected a floating-point number optionally followed by units (e.g. 'Mb' [implied per second] or 'kB/ms' or 'b/10s' etc).", optarg);
                        return EINVAL;
                    }
                    
                    break;
                }
                case 16:
                    compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_MoreFramesBeforeStart] = @(YES);
                    break;
                case 17:
                    compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_MoreFramesAfterEnd] = @(YES);
                    break;
                case 18: {
                    NSDictionary *entropyModes = @{@"cavlc": (__bridge NSString*)kVTH264EntropyMode_CAVLC,
                                                   @"cabac": (__bridge NSString*)kVTH264EntropyMode_CABAC};
                    NSString *mode = entropyModes[[@(optarg) lowercaseString]];

                    if (mode) {
                        compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_H264EntropyMode] = mode;
                    } else {
                        LOG_ERROR("Unrecognised entropy mode \"%s\".", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 19: {
                    char *end = NULL;
                    const unsigned long long maxFrameDelay = strtoull(optarg, &end, 0);

                    if (end && (end != optarg) && !*end) {
                        compressionSettings[(__bridge NSString*)kVTCompressionPropertyKey_MaxFrameDelayCount] = @(maxFrameDelay);
                    } else {
                        LOG_ERROR("Invalid --max-frame-delay argument \"%s\" - expect a positive integer (or zero).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 20:
                    fileType = @(optarg);
                    break;
                case 21: { // --speed
                    char *end = NULL;

                    speed = strtod(optarg, &end);

                    if (!end || (end == optarg) || *end || (0 >= speed)) {
                        LOG_ERROR("Invalid --speed argument \"%s\" - expect a positive floating-point number.", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 22: { // --frame-limit
                    char *end = NULL;
                    frameLimit = strtoll(optarg, &end, 0);

                    if (!end || (end == optarg) || *end || (0 >= frameLimit)) {
                        LOG_ERROR("Invalid --frame-limit argument \"%s\" - expect a positive integer.", optarg);
                        return EINVAL;
                    }

                    break;
                }
                case 23: { // --verbosity
                    char *end = NULL;
                    logLevel = strtoul(optarg, &end, 0);

                    if (!end || (end == optarg) || *end) {
                        LOG_ERROR("Invalid --verbosity argument \"%s\" - expect a positive integer (or zero).", optarg);
                        return EINVAL;
                    }

                    break;
                }
                default:
                    LOG_ERROR("Invalid arguments (%d).", optionIndex);
                    return EINVAL;
            }
        }
        const char *invocationString = argv[0];
        argc -= optind;
        argv += optind;

        if (2 > argc) {
            LOG_ERROR("Expect additional parameters specifying the source & destination.");
            fprintf(stderr, "Usage: %s [FLAGS...] SOURCE [SOURCE...] DESTINATION.MOV\n", invocationString);
            return EINVAL;
        }

        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *destPath = [NSURL fileURLWithPath:[@(argv[argc - 1]) stringByExpandingTildeInPath]];
        DLOG(V_CONFIGURATION, @"Destination Path: %@", destPath);

        if (!fileType) {
            NSString *fileExtension = destPath.pathExtension.lowercaseString;

            if (fileExtension) {
                NSDictionary *fileTypeFromExtension = @{@"mov": AVFileTypeQuickTimeMovie,
                                                        @"mp4": AVFileTypeMPEG4,
                                                        @"m4v": AVFileTypeAppleM4V};

                fileType = fileTypeFromExtension[fileExtension];
            }

            if (!fileType) {
                fileType = AVFileTypeQuickTimeMovie;
            }
        }

        if ([fileManager fileExistsAtPath:destPath.path]) {
            LOG_ERROR("Output file (\"%@\") already exists.", destPath.path);
            return 1;
        }

        BOOL isDir;
        if (!([fileManager fileExistsAtPath:[destPath.path stringByDeletingLastPathComponent]
                                isDirectory:&isDir]
              && isDir)) {
            LOG_ERROR("Output file (\"%@\") is not writable.  Does the destination directory exist?", destPath.path);
            return 1;
        }

        NSMutableArray *filePropertyKeys = [sortFileAttributeKeys[sortAttribute] mutableCopy];

        if (0 < speed) {
            if (![filePropertyKeys containsObject:NSURLCreationDateKey]) {
                [filePropertyKeys addObject:NSURLCreationDateKey];
            }
        }

        NSMutableArray *imageFiles = [NSMutableArray array];
        NSDate *earliestFrame, *latestFrame;
        NSMutableDictionary *fileCreationDates = (0 < speed) ? [NSMutableDictionary dictionary] : nil;

        if (!quiet) {
            printf("Scanning inputs to find input images...\n");
        }

        for (int i = 0; i < argc - 1; ++i) {
            NSURL *inputPath = [NSURL fileURLWithPath:[@(argv[i]) stringByExpandingTildeInPath]];

            DLOG(V_CONFIGURATION, @"Input Path: %@", inputPath);

            if (![fileManager fileExistsAtPath:inputPath.path isDirectory:&isDir]) {
                LOG_ERROR("Input file/folder \"%@\" does not exist.", inputPath.path);
                return EINVAL;
            }

            if (isDir) {
                NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtURL:inputPath
                                                               includingPropertiesForKeys:filePropertyKeys
                                                                                  options:(   NSDirectoryEnumerationSkipsHiddenFiles
                                                                                            | NSDirectoryEnumerationSkipsPackageDescendants)
                                                                             errorHandler:^(NSURL *url, NSError *error) {
                    LOG_ERROR("Error while looking for images in \"%@\": %@", url.path, error.localizedDescription);
                    return YES;
                }];

                if (!directoryEnumerator) {
                    LOG_ERROR("Unable to enumerate files in \"%@\".", inputPath.path);
                    return -1;
                }

                for (NSURL *file in directoryEnumerator) {
                    prescanFile(file, speed, &earliestFrame, &latestFrame, fileCreationDates, imageFiles);
                }
            } else {
                prescanFile(inputPath, speed, &earliestFrame, &latestFrame, fileCreationDates, imageFiles);
            }
        }

        if (0 == imageFiles.count) {
            LOG_ERROR("No suitable image files found in input path(s).");
            return -1;
        }
        
        [imageFiles sortWithOptions:NSSortConcurrent usingComparator:sortComparators[sortAttribute]];

        if (0 < frameLimit) {
            if (imageFiles.count > frameLimit) {
                [imageFiles removeObjectsInRange:NSMakeRange(frameLimit, imageFiles.count - frameLimit)];
            }
        }

        NSError *err = nil;
        AVAssetWriter *movie = (dryrun ? nil : [AVAssetWriter assetWriterWithURL:destPath fileType:fileType error:&err]);
        AVAssetWriterInput *movieWriter;
        const int32_t timeScale = INT32_MAX;

        if (!dryrun) {
            if (!movie) {
                LOG_ERROR("Unable to initialize AVAssetWriter: %@.  Try 'tlassemble --help' for more information.", err.localizedDescription);
                return 1;
            }
        }

        VTCompressionSessionRef compressionSession = NULL;

        const double realTimeDuration = ((0 < speed) ? [latestFrame timeIntervalSinceDate:earliestFrame] : 0.0);

        if (0 == fps) {
            if (0 < speed) {
                fps = imageFiles.count / (realTimeDuration / speed);
            } else {
                fps = kDefaultFPS;
            }
        }

        const long long timeValue = llround((double)timeScale / fps);
        const double expectedMovieDuration = ((0 < speed) ? (realTimeDuration / speed): imageFiles.count / fps);
        unsigned long fileIndex = 1;  // Human-readable, so 1-based.
        unsigned long framesFilteredOut = 0;
        __block unsigned long framesAddedSuccessfully = 0;
        NSSize frameSize = {0, 0};

        DLOG(V_CONFIGURATION, @"Filter: %@", filter);
        DLOG(V_CONFIGURATION, @"FPS: %f", fps);
        DLOG(V_CONFIGURATION, @"Frame limit: %lld", frameLimit);
        DLOG(V_CONFIGURATION, @"Height: %ld", height);
        DLOG(V_CONFIGURATION, @"Quiet: %s", (quiet ? "YES" : "NO"));
        DLOG(V_CONFIGURATION, @"Movie duration: %f", expectedMovieDuration);
        DLOG(V_CONFIGURATION, @"Real time duration: %f", realTimeDuration);
        DLOG(V_CONFIGURATION, @"Sort: %@ (%s)", sortAttribute, (reverseOrder ? "reversed" : "normal"));
        DLOG(V_CONFIGURATION, @"Speed: %f", speed);
        DLOG(V_CONFIGURATION, @"Time value: %lld", timeValue);

        FrameOutputContext *frameOutputContext = [FrameOutputContext new];
        NSDictionary *imageSourceOptions = @{ (__bridge NSString*)kCGImageSourceShouldAllowFloat: @YES };

        dispatch_queue_t encodingQueue = dispatch_queue_create("Encoding", DISPATCH_QUEUE_SERIAL);

        if (!encodingQueue) {
            LOG_ERROR("Unable to create encoding queue.");
            exit(-1);
        }

        if (!quiet) {
            printf("Creating video...\n");
        }

        for (NSURL *file in imageFiles) {
            @autoreleasepool {
                NSDate *creationDate;

                if (0 < speed) {
                    creationDate = fileCreationDates[file];

                    if (!creationDate) {
                        LOG_ERROR("Expected to have already determined the creation date of \"%@\", yet there is no record of it.", file.path);
                    }
                }

                CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)file, (__bridge CFDictionaryRef)imageSourceOptions);

                if (imageSource) {
                    NSDictionary *imageProperties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageSourceOptions));

                    if (imageProperties) {
                        DLOG(V_FRAME_METADATA, @"Image properties of \"%s\": %s", file.path.UTF8String, imageProperties.description.UTF8String);

                        BOOL filteredOut = NO;

                        if (0 < filter.count) {
                            NSMutableSet *matches = [NSMutableSet set];

                            NSMutableArray *subdictionaries = [NSMutableArray array];
                            NSDictionary *currentDictionary = imageProperties;

                            while (currentDictionary && (filter.count > matches.count)) {
                                [currentDictionary enumerateKeysAndObjectsUsingBlock:^void(NSString *key, id obj, BOOL *stop) {
                                    if ([obj isKindOfClass:NSDictionary.class]) {
                                        [subdictionaries addObject:obj];
                                    } else {
                                        NSString *filterValue = filter[key.lowercaseString];

                                        if (filterValue) {
                                            if (NSOrderedSame == [filterValue localizedCaseInsensitiveCompare:((NSObject*)obj).description]) {
                                                [matches addObject:key];
                                            }
                                        }
                                    }
                                }];

                                currentDictionary = subdictionaries.lastObject;

                                if (currentDictionary) {
                                    [subdictionaries removeLastObject];
                                }
                            }

                            filteredOut = (filter.count != matches.count);
                        }

                        if (!filteredOut) {
                            CGImageRef image = CGImageSourceCreateImageAtIndex(imageSource, 0, (__bridge CFDictionaryRef)imageSourceOptions);

                            if (image) {
                                if ((0 != frameSize.width) && (0 != frameSize.height)) {
                                    if (    (frameSize.width != CGImageGetWidth(image))
                                         || (frameSize.height != CGImageGetHeight(image))) {
                                        LOG_WARNING("First frame (and thus output movie) has size %llu x %llu, but frame #%lu has size %zu x %zu.  The resulting movie may be deformed.\n",
                                                    (unsigned long long)frameSize.width,
                                                    (unsigned long long)frameSize.height,
                                                    fileIndex,
                                                    CGImageGetWidth(image),
                                                    CGImageGetHeight(image));
                                    }
                                } else {
                                    frameSize = NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image));
                                }

                                const long width = (height
                                                    ? llround(height * ((double)CGImageGetWidth(image) / CGImageGetHeight(image)))
                                                    : CGImageGetWidth(image));

                                if (!height) {
                                    height = CGImageGetHeight(image);
                                }

                                const unsigned long kSafeHeightLimit = 2496;
                                if (height > kSafeHeightLimit) {
                                    static BOOL warnedOnce = NO;

                                    if (!warnedOnce) {
                                        LOG_WARNING("Movies with heights greater than %lu pixels are known to not work (either they'll fail immediately with an error from the compression engine, or appear to work but the resulting movie file will be essentially empty).", kSafeHeightLimit); fflush(stderr);
                                        warnedOnce = YES;
                                    }
                                }

                                {
                                    static BOOL haveLoggedDimensions = NO;
                                    if (!haveLoggedDimensions) {
                                        DLOG(V_CONFIGURATION, @"Movie dimensions: %ld x %ld", width, height);
                                        haveLoggedDimensions = YES;
                                    }
                                }

                                CVPixelBufferRef pixelBuffer = CreatePixelBufferFromCGImage(image, NSMakeSize(width, height));

                                if (pixelBuffer) {
                                    if (!compressionSession) {
                                        // Now that we have our exemplar frame, we can create the asset writer.  We have to wait until now to do this because the asset writer, in pass-through mode, needs to know some basic info about the compressed frames it'll be receiving (i.e. size for a start).

                                        {
                                            CMVideoFormatDescriptionRef videoFormatDescription = NULL;
                                            OSStatus status = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                                                                             codec,
                                                                                             width,
                                                                                             height,
                                                                                             NULL,
                                                                                             &videoFormatDescription);

                                            if (0 != status) {
                                                LOG_ERROR("Unable to create video format description hint, error #%d.", status);
                                                return 1;
                                            }

                                            movieWriter = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                                             outputSettings:nil
                                                                                           sourceFormatHint:videoFormatDescription];

                                            CFRelease(videoFormatDescription);
                                        }

                                        if (!movieWriter) {
                                            LOG_ERROR("Unable to initialize AVAssetWriterInput.");
                                            return 1;
                                        }

                                        movieWriter.expectsMediaDataInRealTime = NO;

                                        [movie addInput:movieWriter];

                                        if (![movie startWriting]) {
                                            LOG_ERROR("Unable to start writing movie file: %@", movie.error.localizedDescription);
                                            return 1;
                                        }
                                        
                                        [movie startSessionAtSourceTime:CMTimeMake(0, timeScale)];

                                        // Now create the actual compression session to do the real work and output the result to the asset writer we just created.

                                        frameOutputContext.assetWriter = movie;
                                        frameOutputContext.assetWriterInput = movieWriter;
                                        frameOutputContext.quiet = quiet;

                                        OSStatus status = VTCompressionSessionCreate(NULL,
                                                                                     width,
                                                                                     height,
                                                                                     codec,
                                                                                     (encoderID
                                                                                      ? (__bridge CFDictionaryRef)@{(__bridge NSString*)kVTVideoEncoderSpecification_EncoderID: encoderID}
                                                                                      : nil),
                                                                                     NULL, // TODO: Consider pre-defining a pixel buffer pool.  Though is this done automatically if we don't do it explicitly?
                                                                                     NULL,
                                                                                     compressedFrameOutput,
                                                                                     (void*)CFBridgingRetain(frameOutputContext),
                                                                                     &compressionSession);
                                        
                                        if (0 != status) {
                                            LOG_ERROR("Unable to create compression session, error #%d.", status);
                                            return 1;
                                        }

                                        CFDictionaryRef supportedPropertyInfo = NULL;
                                        status = VTSessionCopySupportedPropertyDictionary(compressionSession, &supportedPropertyInfo);

                                        if (0 != status) {
                                            LOG_WARNING("Unable to determine supported compression properties, error #%d.  Will try setting them blindly, but this is likely to fail.", status);
                                        }

                                        DLOG(V_CONFIGURATION_OPTIONS, @"Tweakable compression settings: %@", supportedPropertyInfo);

                                        NSSet *supportedProperties = [NSSet setWithArray:((NSDictionary*)CFBridgingRelease(supportedPropertyInfo)).allKeys];
                                        NSSet *specifiedProperties = [NSSet setWithArray:compressionSettings.allKeys];

                                        if (![specifiedProperties isSubsetOfSet:supportedProperties]) {
                                            NSMutableSet *unsupportedProperties = specifiedProperties.mutableCopy;
                                            [unsupportedProperties minusSet:supportedProperties];

                                            LOG_WARNING("The following compression properties are not supported in this configuration, and will be ignored:");

                                            for (NSString *property in unsupportedProperties) {
                                                LOG_WARNING("    %@", property);
                                                [compressionSettings removeObjectForKey:property];
                                            }
                                        }

                                        // Use of a H.264-specific default profile setting is questionable, but at time of writing it appears that the H.264 codec is the only one that supports that property anyway, so it doesn't actually cause any practical problems.
                                        NSDictionary *defaultCompressionSettings = @{(__bridge NSString*)kVTCompressionPropertyKey_RealTime: @(NO),
                                                                                     (__bridge NSString*)kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: @(YES),
                                                                                     (__bridge NSString*)kVTCompressionPropertyKey_ExpectedFrameRate: @(fps),
                                                                                     (__bridge NSString*)kVTCompressionPropertyKey_H264EntropyMode: (__bridge NSString*)kVTH264EntropyMode_CABAC,
                                                                                     (__bridge NSString*)kVTCompressionPropertyKey_ProfileLevel: (__bridge NSString*)kVTProfileLevel_H264_High_AutoLevel,
                                                                                     (__bridge NSString*)kVTCompressionPropertyKey_ExpectedDuration: @(expectedMovieDuration)};

                                        NSMutableSet *applicableDefaultPropertyKeys = [NSMutableSet setWithArray:defaultCompressionSettings.allKeys];
                                        [applicableDefaultPropertyKeys minusSet:specifiedProperties];
                                        [applicableDefaultPropertyKeys intersectSet:supportedProperties];

                                        for (NSString *key in applicableDefaultPropertyKeys) {
                                            compressionSettings[key] = defaultCompressionSettings[key];
                                        }

                                        status = VTSessionSetProperties(compressionSession, (__bridge CFDictionaryRef)compressionSettings);

                                        if (0 != status) {
                                            LOG_ERROR("Unable to set compression properties, error #%d, to: %@", status, compressionSettings.description);
                                            return 1;
                                        }

                                        DLOG(V_CONFIGURATION, @"Applied compression settings: %@", compressionSettings);

                                        status = VTCompressionSessionPrepareToEncodeFrames(compressionSession);

                                        if (0 != status) {
                                            LOG_ERROR("Unable to prepare compression session, error #%d.", status);
                                            return 1;
                                        }

                                    }

                                    const CMTime frameTime = (0 < speed) ? CMTimeMakeWithSeconds([creationDate timeIntervalSinceDate:earliestFrame] / speed, timeScale)
                                                                         : CMTimeMake(framesAddedSuccessfully * timeValue, timeScale);

                                    DLOG(V_FRAME_METADATA,
                                         @"Compressing frame %lu of %lu with movie time %f (of %f) [%"PRId64" / %"PRId32" - %"PRIx32", based on date of %@ vs earliest frame's date %@, which is a difference of %f, then divided by speed of %f to give %f, then multiplied by the time scale of %"PRId32"]...",
                                         fileIndex,
                                         imageFiles.count,
                                         CMTimeGetSeconds(frameTime),
                                         expectedMovieDuration,
                                         frameTime.value,
                                         frameTime.timescale,
                                         frameTime.flags,
                                         creationDate,
                                         earliestFrame,
                                         [creationDate timeIntervalSinceDate:earliestFrame],
                                         speed,
                                         ([creationDate timeIntervalSinceDate:earliestFrame] / speed),
                                         timeScale);

                                    dispatch_async(encodingQueue, ^{
                                        OSStatus status = VTCompressionSessionEncodeFrame(compressionSession,
                                                                                          pixelBuffer,
                                                                                          frameTime,
                                                                                          kCMTimeInvalid,
                                                                                          NULL, // TODO: Investigate per-frame properties.
                                                                                          (void*)(framesAddedSuccessfully + 1),
                                                                                          NULL); // TODO: Check if any of these flags are useful.
                                        if (0 == status) {
#if 1
                                            if (compressionSession) {
                                                status = VTCompressionSessionCompleteFrames(compressionSession, kCMTimePositiveInfinity);

                                                if (0 != status) {
                                                    LOG_WARNING("Unable to complete compression session, error #%d.", status);
                                                    // TODO: Maybe abort encoding completely?
                                                }
                                            }
#endif

                                            ++framesAddedSuccessfully;

                                            if (!quiet) {
                                                printf("Processed %s (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                                            }
                                        } else {
                                            LOG_ERROR("Unable to compress frame from \"%@\" (%lu of %lu), error #%d.", file.path, fileIndex, imageFiles.count, status);
                                        }

                                        CVPixelBufferRelease(pixelBuffer);
                                    });
                                } else {
                                    LOG_ERROR("Unable to create pixel buffer from \"%@\" (%lu of %lu).", file.path, fileIndex, imageFiles.count);
                                    return 1;
                                }

                                CGImageRelease(image);
                            } else {
                                LOG_ERROR("Unable to render \"%@\" (%lu of %lu).", file.path, fileIndex, imageFiles.count);
                            }
                        } else {
                            ++framesFilteredOut;

                            if (!quiet) {
                                printf("Skipping \"%s\" that doesn't match filter (%lu of %lu)\n", file.path.UTF8String, fileIndex, imageFiles.count);
                            }
                            //NSLog(@"Properties of \"%@\" are: %@", file.path, imageProperties);
                        }
                    } else {
                        LOG_ERROR("Unable to get metadata for \"%@\" (%lu of %lu).", file.path, fileIndex, imageFiles.count);
                    }

                    CFRelease(imageSource);
                } else {
                    LOG_ERROR("Unable to read \"%@\" (%lu of %lu).", file.path, fileIndex, imageFiles.count);
                }
            }

            ++fileIndex;
        }

#if 0
        if (compressionSession) {
            const OSStatus status = VTCompressionSessionCompleteFrames(compressionSession, kCMTimePositiveInfinity);

            if (0 != status) {
                LOG_WARNING("Unable to complete compression session, error #%d.", status);
                return 1;
            }
        }
#endif

        if (movie) {
            dispatch_semaphore_t barrier = dispatch_semaphore_create(0);

            [movie finishWritingWithCompletionHandler:^{
                if (AVAssetWriterStatusCompleted != movie.status) {
                    LOG_ERROR("Unable to complete movie: %@", movie.error.localizedDescription);
                    exit(1);
                }

                dispatch_semaphore_signal(barrier);
            }];

            dispatch_semaphore_wait(barrier, DISPATCH_TIME_FOREVER);
        }

        if (compressionSession) {
            CFRelease((__bridge CFTypeRef)frameOutputContext);
        }
        
        if (0 < framesAddedSuccessfully) {
            if (framesAddedSuccessfully != imageFiles.count) {
                LOG_WARNING("Source folder contained %lu files but only %lu were readable as images (of which %lu were filtered out).", imageFiles.count, framesAddedSuccessfully, framesFilteredOut);
            } else {
                if (dryrun) {
                    printf("Would probably have successfully created \"%s\" out of %lu images (%lu others being filtered out, and %lu other files not being readable).\n",
                           [destPath.path stringByAbbreviatingWithTildeInPath].UTF8String,
                           framesAddedSuccessfully,
                           framesFilteredOut,
                           imageFiles.count - (framesAddedSuccessfully + framesFilteredOut));
                } else {
                    if (!quiet) {
                        printf("Successfully created %s out of %lu images (%lu others filtered out).\n",
                               [destPath.path stringByAbbreviatingWithTildeInPath].UTF8String,
                               framesAddedSuccessfully,
                               framesFilteredOut);
                    }
                }
            }

            return 0;
        } else {
            LOG_ERROR("None of the %lu input files were readable as images.", imageFiles.count);
            return -1;
        }
    }
}

