/* Copyright (c) 2007 Christopher J. W. Lloyd

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <CoreGraphics/CGDataProvider.h>
#import <Onyx2D/O2DataProvider.h>

CGDataProviderRef CGDataProviderRetain(CGDataProviderRef provider) {
    return (CGDataProviderRef)O2DataProviderRetain((O2DataProviderRef)provider);
}

void CGDataProviderRelease(CGDataProviderRef provider) {
    O2DataProviderRelease((O2DataProviderRef)provider);
}

CGDataProviderRef CGDataProviderCreateWithCFData(CFDataRef data) {
    return (CGDataProviderRef)O2DataProviderCreateWithCFData(data);
}

COREGRAPHICS_EXPORT CGDataProviderRef
CGDataProviderCreateWithData(void *info, const void *data, size_t size,
                             CGDataProviderReleaseDataCallback releaseCallback)
{
    return (CGDataProviderRef)O2DataProviderCreateWithData(info, data, size, releaseCallback);
}

COREGRAPHICS_EXPORT CFDataRef CGDataProviderCopyData(CGDataProviderRef self) {
    return (CFDataRef) O2DataProviderCopyData((O2DataProviderRef)self);
}

/* Mac OS X 10.0-10.4 callback providers (deprecated in 10.5, exported for pre-10.5 binaries). */
COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreate(void *info, const CGDataProviderCallbacks *callbacks) {
    if (callbacks == NULL)
        return NULL;
    return (CGDataProviderRef)O2DataProviderCreateWithSequentialCallbacks(info, callbacks->getBytes,
            callbacks->skipBytes, callbacks->rewind, callbacks->releaseProvider);
}

COREGRAPHICS_EXPORT CGDataProviderRef CGDataProviderCreateDirectAccess(void *info, size_t size,
        const CGDataProviderDirectAccessCallbacks *callbacks) {
    if (callbacks == NULL)
        return NULL;
    return (CGDataProviderRef)O2DataProviderCreateWithDirectAccessCallbacks(info, size, callbacks->getBytePointer,
            callbacks->releaseBytePointer, callbacks->getBytes, callbacks->releaseProvider);
}
