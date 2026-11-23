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

#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSStream.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSValue.h>
#import <Onyx2D/O2DataProvider.h>
#import <string.h>

@implementation O2DataProvider

- initWithData: (NSData *) data {
    _inputStream = [[NSInputStream inputStreamWithData: data] retain];
    [_inputStream open];
    _data = [data retain];
    _isDirectAccess = YES;
    _bytes = [data bytes];
    _length = [data length];
    return self;
}

- initWithBytes: (const void *) bytes length: (size_t) length {
    NSData *data = [NSData dataWithBytesNoCopy: (void *) bytes
                                        length: length
                                  freeWhenDone: NO];
    return [self initWithData: data];
}

- initWithFilename: (const char *) pathCString {
    // why doesn't O2DataProvider use CFString's, ugh
    NSUInteger len = strlen(pathCString);
    _path = [[[NSFileManager defaultManager]
            stringWithFileSystemRepresentation: pathCString
                                        length: len] copy];
    _inputStream = [[NSInputStream inputStreamWithFileAtPath: _path] retain];
    [_inputStream open];
    _data = nil;
    _isDirectAccess = NO;
    _bytes = nil;
    _length = 0;
    return self;
}

- initWithURL: (NSURL *) url {
    NSData *data = (url != nil) ? [[NSData alloc] initWithContentsOfURL: url] : nil;

    if (data == nil) {
        // Unreadable or missing file: CGDataProviderCreateWithURL returns NULL.
        [self release];
        return nil;
    }

    id result = [self initWithData: data];

    [data release];

    return result;
}

O2DataProviderRef
O2DataProviderCreateWithData(void *info, const void *data, size_t size,
                             O2DataProviderReleaseDataCallback releaseCallback)
{
    return [[O2DataProvider alloc] initWithBytes: data length: size];
}

O2DataProviderRef O2DataProviderCreateWithCFData(CFDataRef data) {
    return [[O2DataProvider alloc] initWithData: (NSData *) data];
}

O2DataProviderRef O2DataProviderCreateWithURL(NSURL *url) {
    return [[O2DataProvider alloc] initWithURL: url];
}

O2DataProviderRef O2DataProviderCreateWithFilename(const char *pathCString) {
    return [[O2DataProvider alloc] initWithFilename: pathCString];
}

O2DataProviderRef O2DataProviderRetain(O2DataProviderRef self) {
    return (self != NULL) ? (O2DataProviderRef) CFRetain(self) : NULL;
}

void O2DataProviderRelease(O2DataProviderRef self) {
    if (self != NULL)
        CFRelease(self);
}

CFDataRef O2DataProviderCopyData(O2DataProviderRef self) {
    // CGDataProviderCopyData returns NULL for a NULL provider.
    if (self == NULL)
        return NULL;
    [self _o2MaterializeIfNeeded];
    if (self->_data == nil && self->_path == nil)
        return NULL;
    if (self->_data != nil)
        return (CFDataRef)[self->_data copy];
    else
        return (CFDataRef) [[NSData alloc] initWithContentsOfFile: self->_path];
}

- (void) dealloc {
    [_inputStream close];
    [_inputStream release];
    [_data release];
    [_path release];
    [super dealloc];
}

// Base providers already hold their bytes (or a path); callback providers override this.
- (void) _o2MaterializeIfNeeded {
}

- (NSString *) path {
    return _path;
}

- (NSInputStream *) inputStream {
    return _inputStream;
}

- (BOOL) isDirectAccess {
    return _isDirectAccess;
}

- (NSData *) data {
    return _data;
}

- (const void *) bytes {
    return _bytes;
}

- (size_t) length {
    return _length;
}

- (void) rewind {
    NSNumber *number = [[NSNumber alloc] initWithInt: 0];

    [_inputStream setProperty: number forKey: NSStreamFileCurrentOffsetKey];

    [number release];
}

- (NSInteger) getBytes: (void *) bytes range: (NSRange) range {
    if (_data != nil) {
        NSUInteger length = [_data length];

        if (NSMaxRange(range) <= length) {
            [_data getBytes: bytes range: range];
            return range.length;
        } else if (range.location < length) {
            range.length = length - range.location;
            [_data getBytes: bytes range: range];
            return range.length;
        } else
            return -1;
    } else {
        NSInteger check = -1;
        NSNumber *number = [[NSNumber alloc] initWithInt: range.location];

        if ([_inputStream setProperty: number
                               forKey: NSStreamFileCurrentOffsetKey])
            check = [_inputStream read: bytes maxLength: range.length];

        [number release];

        return check;
    }
}

@end


/* Callback-backed providers: CGDataProviderCreate (10.0-10.4 sequential callbacks) and
   CGDataProviderCreateDirectAccess. A subclass keeps the O2DataProvider instance layout unchanged.
   On the first request for bytes the provider reads everything once through the callbacks into an
   NSData it owns, then behaves like a data provider (isDirectAccess, bytes, length, inputStream).
   The sequential stream is rewound once before that read; skipBytes is never needed because the
   whole stream is read (Quartz calls rewind/skip on demand, the client must not rely on either).
   A byte pointer obtained from getBytePointer is copied and handed back with releaseBytePointer at
   once, so the provider never keeps a pointer into the client's buffer. releaseInfo runs exactly once,
   from -dealloc, whether or not the bytes were read. */
#define O2_CALLBACK_PROVIDER_MAX_BYTES ((size_t) 1 << 30)

enum { O2CallbackSequential = 1, O2CallbackDirectAccess = 2 };

@interface O2DataProvider_callbacks : O2DataProvider {
@public   // file-private class: filled by the two C creators below
    int _cbMode;
    void *_cbInfo;
    size_t _cbSize;
    size_t (*_cbGetBytes)(void *, void *, size_t);
    void (*_cbSkipBytes)(void *, size_t);
    void (*_cbRewind)(void *);
    const void *(*_cbGetBytePointer)(void *);
    void (*_cbReleaseBytePointer)(void *, const void *);
    size_t (*_cbGetBytesAtOffset)(void *, void *, size_t, size_t);
    void (*_cbReleaseInfo)(void *);
    BOOL _cbMaterialized;
    BOOL _cbFailed;
}
@end

@implementation O2DataProvider_callbacks

- (void) _o2MaterializeIfNeeded {
    if (_cbMaterialized)
        return;
    _cbMaterialized = YES;
    NSMutableData *data = nil;

    if (_cbMode == O2CallbackSequential) {
        // The stream is read once, from its beginning: rewind first, as Quartz does when it
        // needs to read from the beginning of the provider's data stream.
        if (_cbRewind != NULL)
            _cbRewind(_cbInfo);
        data = [[NSMutableData alloc] init];
        if (data == nil)
            _cbFailed = YES;
        uint8_t chunk[65536];
        while (!_cbFailed) {
            size_t n = _cbGetBytes(_cbInfo, chunk, sizeof(chunk));
            if (n == 0)
                break;
            if (n > sizeof(chunk) || [data length] + n > O2_CALLBACK_PROVIDER_MAX_BYTES) {
                NSLog(@"O2DataProvider: sequential getBytes returned %zu bytes (limit exceeded), provider unusable", n);
                _cbFailed = YES;
                break;
            }
            [data appendBytes: chunk length: n];
        }
    } else if (_cbMode == O2CallbackDirectAccess) {
        if (_cbSize > O2_CALLBACK_PROVIDER_MAX_BYTES) {
            NSLog(@"O2DataProvider: direct-access size %zu exceeds the supported limit", _cbSize);
            _cbFailed = YES;
        } else {
            const void *pointer = (_cbGetBytePointer != NULL) ? _cbGetBytePointer(_cbInfo) : NULL;
            if (pointer != NULL) {
                data = [[NSMutableData alloc] initWithBytes: pointer length: _cbSize];
                if (_cbReleaseBytePointer != NULL)
                    _cbReleaseBytePointer(_cbInfo, pointer);
                if (data == nil)
                    _cbFailed = YES;   // allocation failure: no bytes, never a pointer into freed client memory
            } else if (_cbGetBytesAtOffset != NULL) {
                data = [[NSMutableData alloc] initWithLength: _cbSize];
                uint8_t *bytes = [data mutableBytes];
                size_t offset = 0;
                if (data == nil || (_cbSize > 0 && bytes == NULL)) {
                    // allocation failure: never hand the client a NULL-based buffer
                    NSLog(@"O2DataProvider: cannot allocate %zu bytes for a direct-access provider", _cbSize);
                    _cbFailed = YES;
                    offset = _cbSize;
                }
                while (!_cbFailed && offset < _cbSize) {
                    size_t n = _cbGetBytesAtOffset(_cbInfo, bytes + offset, offset, _cbSize - offset);
                    if (n == 0)
                        break;
                    if (n > _cbSize - offset) {
                        NSLog(@"O2DataProvider: direct-access getBytes returned more than requested");
                        _cbFailed = YES;
                        break;
                    }
                    offset += n;
                }
                if (!_cbFailed && offset < _cbSize)
                    [data setLength: offset];
            } else {
                // getBytePointer returned NULL and there is no getBytes callback: no bytes available.
                _cbFailed = YES;
            }
        }
    }

    if (_cbFailed) {
        [data release];
        return;
    }
    _data = data;
    _bytes = [data bytes];
    _length = [data length];
    _isDirectAccess = YES;
    _inputStream = [[NSInputStream inputStreamWithData: data] retain];
    [_inputStream open];
}

- (BOOL) isDirectAccess {
    [self _o2MaterializeIfNeeded];
    return _isDirectAccess;
}

- (NSData *) data {
    [self _o2MaterializeIfNeeded];
    return _data;
}

- (const void *) bytes {
    [self _o2MaterializeIfNeeded];
    return _bytes;
}

- (size_t) length {
    [self _o2MaterializeIfNeeded];
    return _length;
}

- (NSInputStream *) inputStream {
    [self _o2MaterializeIfNeeded];
    return _inputStream;
}

- (void) rewind {
    [self _o2MaterializeIfNeeded];
    if (_inputStream != nil)
        [super rewind];
}

- (NSInteger) getBytes: (void *) bytes range: (NSRange) range {
    [self _o2MaterializeIfNeeded];
    if (_data == nil)
        return -1;
    return [super getBytes: bytes range: range];
}

- (void) dealloc {
    if (_cbReleaseInfo != NULL)
        _cbReleaseInfo(_cbInfo);
    _cbReleaseInfo = NULL;
    [super dealloc];
}

@end

O2DataProviderRef O2DataProviderCreateWithSequentialCallbacks(void *info,
        size_t (*getBytes)(void *, void *, size_t), void (*skipBytes)(void *, size_t),
        void (*rewind)(void *), void (*releaseInfo)(void *))
{
    if (getBytes == NULL)
        return NULL;
    O2DataProvider_callbacks *self = [[O2DataProvider_callbacks alloc] init];
    self->_cbMode = O2CallbackSequential;
    self->_cbInfo = info;
    self->_cbGetBytes = getBytes;
    self->_cbSkipBytes = skipBytes;
    self->_cbRewind = rewind;
    self->_cbReleaseInfo = releaseInfo;
    return self;
}

O2DataProviderRef O2DataProviderCreateWithDirectAccessCallbacks(void *info, size_t size,
        const void *(*getBytePointer)(void *), void (*releaseBytePointer)(void *, const void *),
        size_t (*getBytesAtOffset)(void *, void *, size_t, size_t), void (*releaseInfo)(void *))
{
    if (getBytePointer == NULL && getBytesAtOffset == NULL)
        return NULL;
    O2DataProvider_callbacks *self = [[O2DataProvider_callbacks alloc] init];
    self->_cbMode = O2CallbackDirectAccess;
    self->_cbInfo = info;
    self->_cbSize = size;
    self->_cbGetBytePointer = getBytePointer;
    self->_cbReleaseBytePointer = releaseBytePointer;
    self->_cbGetBytesAtOffset = getBytesAtOffset;
    self->_cbReleaseInfo = releaseInfo;
    return self;
}
