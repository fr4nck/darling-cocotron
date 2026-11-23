/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreFoundation/CFData.h>
#import <CoreGraphics/CoreGraphicsExport.h>

typedef struct CF_BRIDGED_TYPE(id) O2DataProvider *CGDataProviderRef;

typedef void (*CGDataProviderReleaseDataCallback)(void *info, const void *data, size_t size);

typedef size_t (*CGDataProviderGetBytesCallback)(void* info, void* buffer, size_t count);
typedef off_t (*CGDataProviderSkipForwardCallback)(void* info, off_t count);
typedef void (*CGDataProviderRewindCallback)(void* info);
typedef void (*CGDataProviderReleaseInfoCallback)(void* info);

/* Mac OS X 10.0-10.4 provider callbacks (deprecated in 10.5, still exported by the 10.6 CoreGraphics that
   pre-10.5 binaries link against). Types as recorded by the PyObjC 2.5.1 Quartz bindings built against the
   Apple SDK: four function pointers, no version field; DirectAccess takes a size_t size and offset. */
typedef void (*CGDataProviderSkipBytesCallback)(void* info, size_t count);

typedef struct CGDataProviderCallbacks {
	CGDataProviderGetBytesCallback getBytes;
	CGDataProviderSkipBytesCallback skipBytes;
	CGDataProviderRewindCallback rewind;
	CGDataProviderReleaseInfoCallback releaseProvider;
} CGDataProviderCallbacks;

typedef const void* (*CGDataProviderGetBytePointerCallback)(void* info);
typedef void (*CGDataProviderReleaseBytePointerCallback)(void* info, const void* pointer);
typedef size_t (*CGDataProviderGetBytesAtOffsetCallback)(void* info, void* buffer, size_t offset, size_t count);

typedef struct CGDataProviderDirectAccessCallbacks {
	CGDataProviderGetBytePointerCallback getBytePointer;
	CGDataProviderReleaseBytePointerCallback releaseBytePointer;
	CGDataProviderGetBytesAtOffsetCallback getBytes;
	CGDataProviderReleaseInfoCallback releaseProvider;
} CGDataProviderDirectAccessCallbacks;

typedef struct CGDataProviderSequentialCallbacks {
	unsigned int version;
	CGDataProviderGetBytesCallback getBytes;
	CGDataProviderSkipForwardCallback skipForward;
	CGDataProviderRewindCallback rewind;
	CGDataProviderReleaseInfoCallback releaseInfo;
} CGDataProviderSequentialCallbacks;

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider);
COREGRAPHICS_EXPORT void CGDataProviderRelease(CGDataProviderRef provider);

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data);

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateWithData(void *info, const void *data, size_t size, CGDataProviderReleaseDataCallback releaseCallback);

COREGRAPHICS_EXPORT CGDataProviderRef __nullable CGDataProviderCreateSequential(void* info, const CGDataProviderSequentialCallbacks* callbacks);

COREGRAPHICS_EXPORT CGDataProviderRef __nullable CGDataProviderCreate(void* info, const CGDataProviderCallbacks* callbacks);

COREGRAPHICS_EXPORT CGDataProviderRef __nullable CGDataProviderCreateDirectAccess(void* info, size_t size, const CGDataProviderDirectAccessCallbacks* callbacks);

COREGRAPHICS_EXPORT CFDataRef CGDataProviderCopyData(CGDataProviderRef self);

CF_IMPLICIT_BRIDGING_DISABLED
