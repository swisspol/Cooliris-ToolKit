// Copyright 2011 Cooliris, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <CFNetwork/CFNetwork.h>
#else
#import <ApplicationServices/ApplicationServices.h>
#endif
#import <libkern/OSAtomic.h>
#import <sys/fcntl.h>
#import <netinet/in.h>
#import <sqlite3.h>
#import <assert.h>
#import <unistd.h>
#import <pthread.h>
#if !TARGET_OS_IPHONE
#import <execinfo.h>
#endif

#import "Logging.h"

#define kCaptureBufferSize 1024
#define kReadBufferSize 1024

@interface Logging : NSObject
@end

LogLevel LoggingMinimumLogLevel = -1;

static LoggingLiveCallback _loggingCallback = NULL;
static void* _loggingContext = NULL;
static const char* _levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION", "ABORT"};  // Must match LogLevel
static OSSpinLock _spinLock = OS_SPINLOCK_INIT;
static sqlite3* _database = NULL;
static sqlite3_stmt* _statement = NULL;
static CFSocketRef _socket = NULL;
static CFReadStreamRef _readStream = NULL;
static CFWriteStreamRef _writeStream = NULL;
static CFTimeInterval _startTime = 0.0;
static LoggingRemoteConnectCallback _remoteConnectCallback = NULL;
static LoggingRemoteMessageCallback _remoteMessageCallback = NULL;
static LoggingRemoteDisconnectCallback _remoteDisconnectCallback = NULL;
static void* _remoteContext = NULL;
static int _outputFD = 0;
static void* _stdoutCapture = NULL;
static void* _stderrCapture = NULL;

const char* LoggingGetLevelName(LogLevel level) {
  return _levelNames[level];
}

void LoggingSetMinimumLevel(LogLevel level) {
  LoggingMinimumLogLevel = level;
}

LogLevel LoggingGetMinimumLevel() {
  return LoggingMinimumLogLevel;
}

void LoggingResetMinimumLevel() {
  const char* level = getenv("logLevel");
  if (level) {
    LoggingSetMinimumLevel(atoi(level));
  } else {
#ifdef NDEBUG
    LoggingMinimumLogLevel = kLogLevel_Verbose;
#else
    LoggingMinimumLogLevel = kLogLevel_Debug;
#endif
  }
}

void LoggingSetCallback(LoggingLiveCallback callback, void* context) {
  _loggingCallback = callback;
  _loggingContext = context;
}

LoggingLiveCallback LoggingGetCallback() {
  return _loggingCallback;
}

static inline void _LogCapturedOutput(char* buffer, ssize_t size, LogLevel level) {
  if (buffer[size - 1] == '\n') {
    size -= 1;  // Strip ending newline if any
  }
  if (size > 0) {
    NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
    NSString* message;
    @try {
      message = [[NSString alloc] initWithBytesNoCopy:buffer length:size encoding:NSUTF8StringEncoding freeWhenDone:NO];
    }
    @catch (NSException* exception) {
      message = nil;
    }
    if (message) {
      LogRawMessage(level, message);
    }
    [message release];
    [localPool release];
  }
}

static void* _CaptureWriteFileDescriptor(int fd, LogLevel level) {
  int fildes[2];
  pipe(fildes);
  dup2(fildes[1], fd);
  close(fildes[1]);
  fd = fildes[0];
  assert(fd);
  
  char* buffer = malloc(kCaptureBufferSize);
  assert(buffer);
  fcntl(fd, F_SETFL, O_NONBLOCK);
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, queue);
  dispatch_source_set_event_handler(source, ^{
    ssize_t size = read(fd, buffer, kCaptureBufferSize);
    if (size > 0) {
      _LogCapturedOutput(buffer, size, level);
    }
  });
  dispatch_resume(source);
  return source;
}

void LoggingCaptureStdout() {
  if (_stdoutCapture == NULL) {
    _outputFD = dup(STDOUT_FILENO);
    assert(_outputFD > 0);
    _stdoutCapture = _CaptureWriteFileDescriptor(STDOUT_FILENO, kLogLevel_Info);
    assert(_stdoutCapture);
  }
}

BOOL LoggingIsStdoutCaptured() {
  return _stdoutCapture ? YES : NO;
}

void LoggingCaptureStderr() {
  if (_stderrCapture == NULL) {
    _stderrCapture = _CaptureWriteFileDescriptor(STDERR_FILENO, kLogLevel_Error);
    assert(_stderrCapture);
  }
}

BOOL LoggingIsStderrCaptured() {
  return _stderrCapture ? YES : NO;
}

BOOL LoggingIsHistoryEnabled() {
  return _database ? YES : NO;
}

// Assumes spinlock is already taken
static void _AppendHistory(double timestamp, int level, const char* message) {
  if (message) {
    int result;
    
    result = sqlite3_bind_double(_statement, 1, timestamp);
    assert(result == SQLITE_OK);
    result = sqlite3_bind_int(_statement, 2, level);
    assert(result == SQLITE_OK);
    result = sqlite3_bind_text(_statement, 3, message, -1, SQLITE_STATIC);
    assert(result == SQLITE_OK);
    
    result = sqlite3_step(_statement);
    assert(result == SQLITE_DONE);
    result = sqlite3_reset(_statement);
    assert(result == SQLITE_OK);
    
    result = sqlite3_clear_bindings(_statement);
    assert(result == SQLITE_OK);
  }
}

BOOL LoggingEnableHistory(NSString* path, NSUInteger appVersion) {
  OSSpinLockLock(&_spinLock);
  if (_database == NULL) {
    int result = sqlite3_open([path fileSystemRepresentation], &_database);
    assert(result == SQLITE_OK);
    if (result == SQLITE_OK) {
      result = sqlite3_exec(_database, "CREATE TABLE IF NOT EXISTS history (version INTEGER, timestamp REAL, level INTEGER, message TEXT)",
                            NULL, NULL, NULL);
      assert(result == SQLITE_OK);
    }
    if (result == SQLITE_OK) {
      NSString* statement = [NSString stringWithFormat:@"INSERT INTO history (version, timestamp, level, message) VALUES (%i, ?1, ?2, ?3)",
                                                       (int)appVersion];
      result = sqlite3_prepare_v2(_database, [statement UTF8String], -1, &_statement, NULL);
      assert(result == SQLITE_OK);
    }
    if (result != SQLITE_OK) {  // TODO: Check sqlite3_errmsg()
      result = sqlite3_close(_database);
      assert(result == SQLITE_OK);
      _database = NULL;
    }
  }
  OSSpinLockUnlock(&_spinLock);
  return _database ? YES : NO;
}

void LoggingPurgeHistory(NSTimeInterval maxAge) {
  OSSpinLockLock(&_spinLock);
  if (_database) {
    int result;
    if (maxAge > 0.0) {
      NSString* statement = [NSString stringWithFormat:@"DELETE FROM history WHERE timestamp < %f",
                                                       CFAbsoluteTimeGetCurrent() - maxAge];
      result = sqlite3_exec(_database, [statement UTF8String], NULL, NULL, NULL);
      assert(result == SQLITE_OK);
    } else {
      result = sqlite3_exec(_database, "DELETE FROM history", NULL, NULL, NULL);
      assert(result == SQLITE_OK);
    }
    result = sqlite3_exec(_database, "VACUUM", NULL, NULL, NULL);
    assert(result == SQLITE_OK);
  }
  OSSpinLockUnlock(&_spinLock);
}

void LoggingReplayHistory(LoggingReplayCallback callback, void* context, BOOL backward, NSUInteger limit) {
  OSSpinLockLock(&_spinLock);
  if (_database && callback) {
    NSString* string = [NSString stringWithFormat:@"SELECT version, timestamp, level, message FROM history ORDER BY timestamp %@",
                                                  backward ? @"DESC" : @"ASC"];
    if (limit > 0) {
      string = [string stringByAppendingFormat:@" LIMIT %i", (int)limit];
    }
    sqlite3_stmt* statement = NULL;
    int result = sqlite3_prepare_v2(_database, [string UTF8String], -1, &statement, NULL);
    assert(result == SQLITE_OK);
    if (result == SQLITE_OK) {
      while (1) {
        result = sqlite3_step(statement);
        assert((result == SQLITE_ROW) || (result == SQLITE_DONE));
        if (result != SQLITE_ROW) {
          break;
        }
        int version = sqlite3_column_int(statement, 0);
        assert(version >= 0);
        double timestamp = sqlite3_column_double(statement, 1);
        assert(timestamp >= 0.0);
        int level = sqlite3_column_int(statement, 2);
        assert(level >= 0);
        const unsigned char* message = sqlite3_column_text(statement, 3);
        assert(message != nil);
        (*callback)(version, timestamp, level, [NSString stringWithUTF8String:(char*)message], context);
      }
    }
    result = sqlite3_finalize(statement);
    assert(result == SQLITE_OK);
  }
  OSSpinLockUnlock(&_spinLock);
}

#if NS_BLOCKS_AVAILABLE

static void _BlockReplayCallback(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message, void* context) {
  void (^callback)(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message) = context;
  callback(appVersion, timestamp, level, message);
}

void LoggingEnumerateHistory(BOOL backward, NSUInteger limit,
                             void (^block)(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message)) {
  LoggingReplayHistory(_BlockReplayCallback, block, backward, limit);
}

#endif

void LoggingDisableHistory() {
  OSSpinLockLock(&_spinLock);
  if (_database) {
    int result = sqlite3_finalize(_statement);
    assert(result == SQLITE_OK);
    result = sqlite3_close(_database);
    assert(result == SQLITE_OK);
    _database = NULL;
  }
  OSSpinLockUnlock(&_spinLock);
}

BOOL LoggingIsRemoteAccessEnabled() {
  return _socket ? YES : NO;
}

// Assumes spinlock is already taken
static void _CloseStreams() {
  if (_readStream) {
    CFReadStreamClose(_readStream);
    CFRelease(_readStream);
    _readStream = NULL;
  }
  if (_writeStream) {
    CFWriteStreamClose(_writeStream);
    CFRelease(_writeStream);
    _writeStream = NULL;
  }
  if (_remoteDisconnectCallback) {
    (*_remoteDisconnectCallback)(_remoteContext);
  }
}

// Assumes spinlock is already taken
static void _WriteStream(NSString* message) {
  const char* cString = [message UTF8String];
  if (cString) {
    size_t length = strlen(cString);
    CFIndex count = length;
    while (count > 0) {
      CFIndex result = CFWriteStreamWrite(_writeStream, (UInt8*)cString + length - count, count);
      if (result <= 0) {
        break;
      }
      count -= result;
    }
  }
}

// Assume is called on main thread
static void _ReadStream() {
  DCHECK([NSThread isMainThread]);
  unsigned char buffer[kReadBufferSize];
  CFIndex count = CFReadStreamRead(_readStream, buffer, kReadBufferSize);
  if (_remoteMessageCallback && (count > 2)) {
    if (buffer[count - 1] == '\n') {
      count -= 1;
    }
    if (buffer[count - 1] == '\r') {
      count -= 1;
    }
    NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
    NSString* message = [[NSString alloc] initWithBytes:buffer length:count encoding:NSUTF8StringEncoding];
    if (message) {
      NSString* response = _remoteMessageCallback(message, _remoteContext);
      if (response) {
        OSSpinLockLock(&_spinLock);
        _WriteStream([response stringByAppendingString:@"\n"]);
        OSSpinLockUnlock(&_spinLock);
      }
      [message release];
    } else {
      OSSpinLockLock(&_spinLock);
      _WriteStream(@"<SYNTAX ERROR>\n");
      OSSpinLockUnlock(&_spinLock);
    }
    [localPool release];
  }
}

static void _ReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void* clientCallBackInfo) {
  switch (type) {
    
    case kCFStreamEventHasBytesAvailable:
      _ReadStream();
      break;
    
    case kCFStreamEventEndEncountered:
      OSSpinLockLock(&_spinLock);
      _CloseStreams();
      OSSpinLockUnlock(&_spinLock);
      break;
    
    default:
      break;
    
  }
}

static void _OpenStreams(CFSocketNativeHandle handle) {
  CFStreamCreatePairWithSocket(kCFAllocatorDefault, handle, &_readStream, &_writeStream);
  if (_writeStream) {
    CFWriteStreamSetProperty(_writeStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    if (CFWriteStreamOpen(_writeStream)) {
      NSAutoreleasePool* localPool = [[NSAutoreleasePool alloc] init];
      
      NSString* message = nil;
      if (_remoteConnectCallback) {
        message = (*_remoteConnectCallback)(_remoteContext);
      }
      if (message == nil) {
        NSBundle* bundle = [NSBundle mainBundle];
        if (bundle) {
          message = [NSString stringWithFormat:@"**************************************************\n"
                     "%@ %@ (%@)\n"
                     "**************************************************\n\n",
                     [bundle objectForInfoDictionaryKey:@"CFBundleName"],
                     [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                     [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
        }
      }
      if (message) {
        _WriteStream(message);
      }
      
      [localPool release];
    } else {
      CFRelease(_writeStream);
      _writeStream = NULL;
      DNOT_REACHED();
    }
  } else {
    DNOT_REACHED();
  }
  if (_readStream) {
    CFReadStreamSetProperty(_readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
    if (CFReadStreamOpen(_readStream)) {
      CFStreamClientContext context = {0};
      CFReadStreamSetClient(_readStream, kCFStreamEventHasBytesAvailable | kCFStreamEventErrorOccurred | kCFStreamEventEndEncountered, _ReadStreamClientCallBack, &context);
      CFReadStreamScheduleWithRunLoop(_readStream, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    } else {
      CFRelease(_readStream);
      _readStream = NULL;
      DNOT_REACHED();
    }
  } else {
    DNOT_REACHED();
  }
}

static void _AcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void* data, void* info) {
  if (type == kCFSocketAcceptCallBack) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle*)data;
    OSSpinLockLock(&_spinLock);
    if (!_readStream && !_writeStream) {
      _OpenStreams(handle);
    } else {
      close(handle);
    }
    OSSpinLockUnlock(&_spinLock);
  }
}

BOOL LoggingEnableRemoteAccess(NSUInteger port, LoggingRemoteConnectCallback connectCallback, LoggingRemoteMessageCallback messageCallback, LoggingRemoteDisconnectCallback disconnectCallback, void* context) {
  OSSpinLockLock(&_spinLock);
  if (_socket == NULL) {
    _socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, kCFSocketAcceptCallBack, _AcceptCallBack, NULL);
    if (_socket) {
      int yes = 1;
      setsockopt(CFSocketGetNative(_socket), SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
      
      struct sockaddr_in addr4;
      bzero(&addr4, sizeof(addr4));
      addr4.sin_len = sizeof(addr4);
      addr4.sin_family = AF_INET;
      addr4.sin_port = htons(port);
      addr4.sin_addr.s_addr = htonl(INADDR_ANY);
      if (CFSocketSetAddress(_socket, (CFDataRef)[NSData dataWithBytes:&addr4 length:sizeof(addr4)]) == kCFSocketSuccess) {
        CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, _socket, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        
        _remoteConnectCallback = connectCallback;
        _remoteMessageCallback = messageCallback;
        _remoteDisconnectCallback = disconnectCallback;
        _remoteContext = context;
      } else {
        CFRelease(_socket);
        _socket = NULL;
      }
    }
  }
  OSSpinLockUnlock(&_spinLock);
  return _socket ? YES : NO;
}

void LoggingDisableRemoteAccess(BOOL keepConnectionAlive) {
  OSSpinLockLock(&_spinLock);
  if (!keepConnectionAlive && (_readStream || _writeStream)) {
    _CloseStreams();
  }
  if (_socket) {
    CFSocketInvalidate(_socket);
    CFRelease(_socket);
    _socket = NULL;
  }
  OSSpinLockUnlock(&_spinLock);
}

void LogMessage(LogLevel level, NSString* format, ...) {
  va_list arguments;
  va_start(arguments, format);
  NSMutableString* string = [[NSMutableString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  LogRawMessage(level, string);
  [string autorelease];  // Needs autorelease as NSZombieEnabled reports that this is somehow accessed afterwards (at least under GDB)
}

void LogRawMessage(LogLevel level, NSString* message) {
#if !TARGET_OS_IPHONE
  if (level >= kLogLevel_Exception) {
    void* backtraceFrames[128];
    int frameCount = backtrace(backtraceFrames, sizeof(backtraceFrames) / sizeof(void*));
    char** frameStrings = backtrace_symbols(backtraceFrames, frameCount);
    if (frameStrings) {
      message = [NSMutableString stringWithString:message];
      for (int i = 1; i < frameCount; ++i) {
        [(NSMutableString*)message appendFormat:@"\n%s", frameStrings[i]];
      }
      free(frameStrings);  // No need to free individual strings
    }
  }
#endif
  CFTimeInterval timestamp = CFAbsoluteTimeGetCurrent();
  CFTimeInterval relativeTime = timestamp - _startTime;
  NSString* content = [[NSString alloc] initWithFormat:@"[%s | %.3f] %@\n", _levelNames[level], relativeTime, message];
  NSData* data = [content dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
  write(_outputFD, data.bytes, data.length);
  if (_loggingCallback) {
    (*_loggingCallback)(timestamp, level, message, _loggingContext);
  }
  if (_database && (level >= kLogLevel_Info)) {  // Don't record debug or verbose levels
    OSSpinLockLock(&_spinLock);
    if (_database) {
      _AppendHistory(timestamp, level, [message UTF8String]);
    }
    OSSpinLockUnlock(&_spinLock);
  }
  if (_writeStream) {
    OSSpinLockLock(&_spinLock);
    if (_writeStream) {
      if (CFWriteStreamGetStatus(_writeStream) == kCFStreamStatusOpen) {
        _WriteStream(content);
      } else {
        _CloseStreams();
      }
    }
    OSSpinLockUnlock(&_spinLock);
  }
  [content release];
  
  if (level >= kLogLevel_Abort) {
    LoggingDisableHistory();  // Ensure database is in a clean state
    abort();
  }
}

@implementation Logging

+ (void) load {
  LoggingResetMinimumLevel();
  
  _startTime = CFAbsoluteTimeGetCurrent();
  
  _outputFD = STDOUT_FILENO;
}

@end
