#-------Target and Source-------#
TARGET = tlassemble
SRC = $(TARGET).m

#-------Compiler Flags-------#
CFLAGS = -mmacosx-version-min=10.8 -fobjc-arc -pedantic -Wno-gnu
CFLAGS += -framework ApplicationServices # To prevent a stupid runtime error re. framework versions.
CFLAGS += -framework AppKit
CFLAGS += -framework AVFoundation
CFLAGS += -framework CoreFoundation
CFLAGS += -framework CoreGraphics
CFLAGS += -framework CoreMedia
CFLAGS += -framework CoreVideo
CFLAGS += -framework Foundation
CFLAGS += -framework ImageIO
CFLAGS += -framework VideoToolbox

DEBUG = -D DEBUG

all:
	clang $(CFLAGS) $(SRC) -o $(TARGET)

debug:
	clang $(DEBUG) $(CFLAGS) $(SRC) -o $(TARGET)
