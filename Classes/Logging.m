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
#import <netinet/in.h>
#import <sqlite3.h>
#import <assert.h>
#import <unistd.h>

#import "Logging.h"

@interface Logging : NSObject
@end

#ifdef NDEBUG
LogLevel _minimumLogLevel = kLogLevel_Verbose;
#else
LogLevel _minimumLogLevel = kLogLevel_Debug;
#endif

static LoggingLiveCallback _loggingCallback = NULL;
static const char* _levelNames[] = {"DEBUG", "VERBOSE", "INFO", "WARNING", "ERROR", "EXCEPTION", "ABORT"};  // Must match LogLevel
static OSSpinLock _spinLock = 0;
static sqlite3* _database = NULL;
static sqlite3_stmt* _statement = NULL;
static CFSocketRef _socket = NULL;
static CFWriteStreamRef _stream = NULL;

const char* LoggingGetLevelName(LogLevel level) {
  return _levelNames[level];
}

void LoggingSetMinimumLevel(LogLevel level) {
  _minimumLogLevel = level;
}

LogLevel LoggingGetMinimumLevel() {
  return _minimumLogLevel;
}

void LoggingSetCallback(LoggingLiveCallback callback) {
  _loggingCallback = callback;
}

LoggingLiveCallback LoggingGetCallback() {
  return _loggingCallback;
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
                                                       appVersion];
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

void LoggingReplayHistory(LoggingReplayCallback callback, void* context, BOOL backward) {
  OSSpinLockLock(&_spinLock);
  if (_database && callback) {
    NSString* string = [NSString stringWithFormat:@"SELECT version, timestamp, level, message FROM history ORDER BY timestamp %@",
                                                  backward ? @"DESC" : @"ASC"];
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

void LoggingEnumerateHistory(BOOL backward,
                             void (^block)(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message)) {
  LoggingReplayHistory(_BlockReplayCallback, block, backward);
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
static void _AppendStream(NSString* message) {
  const char* cString = [message UTF8String];
  if (cString) {
    size_t length = strlen(cString);
    CFIndex count = length;
    while (count > 0) {
      CFIndex result = CFWriteStreamWrite(_stream, (UInt8*)cString + length - count, count);
      if (result <= 0) {
        break;
      }
      count -= result;
    }
  }
}

static void _AcceptCallBack(CFSocketRef socket, CFSocketCallBackType type, CFDataRef address, const void* data, void* info) {
  if (type == kCFSocketAcceptCallBack) {
    CFSocketNativeHandle handle = *(CFSocketNativeHandle*)data;
    OSSpinLockLock(&_spinLock);
    if (_stream == NULL) {
      CFStreamCreatePairWithSocket(kCFAllocatorDefault, handle, NULL, &_stream);
      if (_stream) {
        if (CFWriteStreamOpen(_stream)) {
          CFWriteStreamSetProperty(_stream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
          
          NSBundle* bundle = [NSBundle mainBundle];
          if (bundle) {
            NSString* message = [[NSString alloc] initWithFormat:@"**************************************************\n"
                                                                  "%@ %@ (%@)\n"
                                                                  "**************************************************\n\n",
                                                                 [bundle objectForInfoDictionaryKey:@"CFBundleName"],
                                                                 [bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                                                                 [bundle objectForInfoDictionaryKey:@"CFBundleVersion"]];
            _AppendStream(message);
            [message release];
          }
        } else {
          CFRelease(_stream);
          close(handle);
        }
      } else {
        close(handle);
      }
    } else {
      close(handle);
    }
    OSSpinLockUnlock(&_spinLock);
  }
}

BOOL LoggingEnableRemoteAccess(NSUInteger port) {
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
  if (!keepConnectionAlive && _stream) {
    CFWriteStreamClose(_stream);
    CFRelease(_stream);
    _stream = NULL;
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
  LogMessageExtended(level, format, arguments);
  va_end(arguments);
}

void LogMessageExtended(LogLevel level, NSString* format, va_list arguments) {
  NSString* string = [[NSString alloc] initWithFormat:format arguments:arguments];
  const char* cString = [string UTF8String];
  printf("[%s] %s\n", _levelNames[level], cString);
  if (_loggingCallback) {
    (*_loggingCallback)(level, string);
  }
  if (_database && (level > kLogLevel_Debug)) {
    OSSpinLockLock(&_spinLock);
    if (_database) {
      _AppendHistory(CFAbsoluteTimeGetCurrent(), level, cString);
    }
    OSSpinLockUnlock(&_spinLock);
  }
  if (_stream) {
    NSString* content = [[NSString alloc] initWithFormat:@"[%s] %@\n", _levelNames[level], string];
    OSSpinLockLock(&_spinLock);
    if (_stream) {
      if (CFWriteStreamGetStatus(_stream) == kCFStreamStatusOpen) {
        _AppendStream(content);
      } else {
        CFWriteStreamClose(_stream);
        CFRelease(_stream);
        _stream = NULL;
      }
    }
    OSSpinLockUnlock(&_spinLock);
    [content release];
  }
  [string autorelease];  // Needs autorelease as NSZombieEnabled reports that this is somehow accessed afterwards (at least under GDB)
  
#ifdef NDEBUG
  if (level >= kLogLevel_Abort)
#else
  if ((level >= kLogLevel_Error) && !getenv("logNoAbort"))
#endif
  {
    LoggingDisableHistory();  // Ensure database is in a clean state
#ifdef NDEBUG
    abort();
#else
#if defined(__ppc__)
    asm {trap}
#elif defined(__i386__)
    __asm {int 3}
#elif defined(__arm__)
    __builtin_trap();
#else
#error Unsupported architecture!
#endif
#endif
  }
}

@implementation Logging

+ (void) load {
  const char* level = getenv("logLevel");
  if (level) {
    LoggingSetMinimumLevel(atoi(level));
  }
}

@end
