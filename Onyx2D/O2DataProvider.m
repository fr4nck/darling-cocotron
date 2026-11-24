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
#import <stdlib.h>
#import <pthread.h>

// Private: callback-backed providers read their bytes on first use (see the end of this file).
@interface O2DataProvider ()
- (void) _o2MaterializeIfNeeded;
@end

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
   CGDataProviderCreateDirectAccess. A private subclass keeps the O2DataProvider instance layout unchanged.
   On the first request for bytes the provider reads everything once through the callbacks into a buffer
   it owns, then behaves like a data provider (isDirectAccess, bytes, length, inputStream).
   - The sequential stream is rewound once before that read; skipBytes is never needed because the whole
     stream is read (Quartz calls rewind/skip on demand, the client must not rely on either).
   - A byte pointer obtained from getBytePointer is copied and handed back with releaseBytePointer at once,
     so the provider never keeps a pointer into the client's buffer.
   - The read happens under a lock: concurrent first uses see either nothing yet (they wait) or the
     complete bytes, never a half-read provider. A callback re-entering its own provider gets no bytes.
   - Allocation failures and the size limit are not fatal: the provider then has no bytes
     (CGDataProviderCopyData returns NULL, images built on it draw nothing).
   - releaseInfo runs exactly once, from -dealloc, whether or not the bytes were read. */
#define O2_CALLBACK_PROVIDER_MAX_BYTES ((size_t) 1 << 30)

enum { O2CallbackSequential = 1, O2CallbackDirectAccess = 2 };

__attribute__((visibility("hidden")))
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
    pthread_mutex_t _cbLock;
    BOOL _cbMaterialized;
    BOOL _cbReading;
}
@end

@implementation O2DataProvider_callbacks

// Reads the whole provider into a malloc'd buffer. Returns NULL (and frees everything) on failure.
- (uint8_t *) _o2ReadAll: (size_t *) lengthOut {
    uint8_t *buffer = NULL;
    size_t length = 0;
    if (_cbMode == O2CallbackSequential) {
        size_t capacity = 65536;
        if (_cbRewind != NULL)
            _cbRewind(_cbInfo);
        buffer = malloc(capacity);
        if (buffer == NULL)
            return NULL;
        for (;;) {
            if (length == capacity) {
                if (capacity >= O2_CALLBACK_PROVIDER_MAX_BYTES) {
                    NSLog(@"O2DataProvider: sequential provider larger than %zu bytes, no data", capacity);
                    free(buffer);
                    return NULL;
                }
                size_t newCapacity = capacity * 2;
                if (newCapacity > O2_CALLBACK_PROVIDER_MAX_BYTES)
                    newCapacity = O2_CALLBACK_PROVIDER_MAX_BYTES;
                uint8_t *grown = realloc(buffer, newCapacity);
                if (grown == NULL) {
                    NSLog(@"O2DataProvider: cannot grow a sequential provider to %zu bytes, no data", newCapacity);
                    free(buffer);
                    return NULL;
                }
                buffer = grown;
                capacity = newCapacity;
            }
            size_t n = _cbGetBytes(_cbInfo, buffer + length, capacity - length);
            if (n == 0)
                break;
            if (n > capacity - length) {
                NSLog(@"O2DataProvider: sequential getBytes returned more than requested, no data");
                free(buffer);
                return NULL;
            }
            length += n;
        }
    } else {
        if (_cbSize > O2_CALLBACK_PROVIDER_MAX_BYTES) {
            NSLog(@"O2DataProvider: direct-access size %zu exceeds the supported limit, no data", _cbSize);
            return NULL;
        }
        buffer = malloc(_cbSize > 0 ? _cbSize : 1);
        if (buffer == NULL) {
            NSLog(@"O2DataProvider: cannot allocate %zu bytes for a direct-access provider, no data", _cbSize);
            return NULL;
        }
        const void *pointer = (_cbGetBytePointer != NULL) ? _cbGetBytePointer(_cbInfo) : NULL;
        if (pointer != NULL) {
            memcpy(buffer, pointer, _cbSize);
            if (_cbReleaseBytePointer != NULL)
                _cbReleaseBytePointer(_cbInfo, pointer);
            length = _cbSize;
        } else if (_cbGetBytesAtOffset != NULL) {
            while (length < _cbSize) {
                size_t n = _cbGetBytesAtOffset(_cbInfo, buffer + length, length, _cbSize - length);
                if (n == 0)
                    break;
                if (n > _cbSize - length) {
                    NSLog(@"O2DataProvider: direct-access getBytes returned more than requested, no data");
                    free(buffer);
                    return NULL;
                }
                length += n;
            }
        } else {
            // getBytePointer returned NULL and there is no getBytes callback: no bytes available.
            free(buffer);
            return NULL;
        }
    }
    *lengthOut = length;
    return buffer;
}

- (void) _o2MaterializeIfNeeded {
    pthread_mutex_lock(&_cbLock);
    if (!_cbMaterialized && !_cbReading) {
        _cbReading = YES;
        size_t length = 0;
        uint8_t *buffer = [self _o2ReadAll: &length];
        NSData *data = nil;
        if (buffer != NULL) {
            data = [[NSData alloc] initWithBytesNoCopy: buffer length: length freeWhenDone: YES];
            if (data == nil)
                free(buffer);
        }
        if (data != nil) {
            _data = data;
            _bytes = [data bytes];
            _length = [data length];
            _isDirectAccess = YES;
            _inputStream = [[NSInputStream alloc] initWithData: data];   // owned, not autoreleased
            [_inputStream open];
        }
        _cbReading = NO;
        _cbMaterialized = YES;   // set only once the read is complete (or has definitively failed)
    }
    pthread_mutex_unlock(&_cbLock);
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
    pthread_mutex_destroy(&_cbLock);
    [super dealloc];
}

@end

static O2DataProvider_callbacks *O2CallbackProviderAlloc(void) {
    O2DataProvider_callbacks *self = [[O2DataProvider_callbacks alloc] init];
    if (self == nil)
        return nil;
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);   // a re-entering callback must not deadlock
    if (pthread_mutex_init(&self->_cbLock, &attributes) != 0) {
        pthread_mutexattr_destroy(&attributes);
        [self release];
        return nil;
    }
    pthread_mutexattr_destroy(&attributes);
    return self;
}

O2DataProviderRef O2DataProviderCreateWithSequentialCallbacks(void *info,
        size_t (*getBytes)(void *, void *, size_t), void (*skipBytes)(void *, size_t),
        void (*rewind)(void *), void (*releaseInfo)(void *))
{
    if (getBytes == NULL)
        return NULL;
    O2DataProvider_callbacks *self = O2CallbackProviderAlloc();
    if (self == nil)
        return NULL;
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
    O2DataProvider_callbacks *self = O2CallbackProviderAlloc();
    if (self == nil)
        return NULL;
    self->_cbMode = O2CallbackDirectAccess;
    self->_cbInfo = info;
    self->_cbSize = size;
    self->_cbGetBytePointer = getBytePointer;
    self->_cbReleaseBytePointer = releaseBytePointer;
    self->_cbGetBytesAtOffset = getBytesAtOffset;
    self->_cbReleaseInfo = releaseInfo;
    return self;
}
