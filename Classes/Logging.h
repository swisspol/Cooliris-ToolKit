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

#import <Foundation/Foundation.h>

typedef enum {
  kLogLevel_Debug = 0,
  kLogLevel_Verbose,
  kLogLevel_Info,
  kLogLevel_Warning,
  kLogLevel_Error,  // Traps in Debug builds
  kLogLevel_Exception,  // Traps in Debug builds
  kLogLevel_Abort,  // Always traps
} LogLevel;

#define LOG_MESSAGE(__LEVEL__, ...) { if ((__LEVEL__) >= _minimumLogLevel) LogMessage(__LEVEL__, __VA_ARGS__); }

#ifdef NDEBUG
#define LOG_DEBUG(...)
#else
#define LOG_DEBUG(...) LOG_MESSAGE(kLogLevel_Debug, __VA_ARGS__)
#endif
#define LOG_VERBOSE(...) LOG_MESSAGE(kLogLevel_Verbose, __VA_ARGS__)
#define LOG_INFO(...) LOG_MESSAGE(kLogLevel_Info, __VA_ARGS__)
#define LOG_WARNING(...) LOG_MESSAGE(kLogLevel_Warning, __VA_ARGS__)
#define LOG_ERROR(...) LOG_MESSAGE(kLogLevel_Error, __VA_ARGS__)
#define LOG_EXCEPTION(__EXCEPTION__) LOG_MESSAGE(kLogLevel_Exception, @"Exception \"%@\": %@", \
                                                 [(__EXCEPTION__) name], [(__EXCEPTION__) reason])
#define LOG_ABORT(...) LOG_MESSAGE(kLogLevel_Abort, __VA_ARGS__)

#ifdef NDEBUG

#define CHECK(__CONDITION__) \
do { \
  if (!(__CONDITION__)) { \
    LOG_ABORT(@"<CONDITION FAILED>"); \
  } \
} while (0)

#define DCHECK(__CONDITION__)
#define RCHECK(__CONDITION__) CHECK(__CONDITION__)

#define NOT_REACHED() \
do { \
  LOG_ABORT(@"<INTERNAL INCONSISTENCY>"); \
} while (0)

#define DNOT_REACHED()
#define RNOT_REACHED() NOT_REACHED()

#else

#define CHECK(__CONDITION__) \
do { \
  if (!(__CONDITION__)) { \
    LOG_ABORT(@"<CONDITION FAILED> \"%s\" @ %s:%i", #__CONDITION__, __FILE__, __LINE__); \
  } \
} while (0)

#define DCHECK(__CONDITION__) CHECK(__CONDITION__)
#define RCHECK(__CONDITION__)

#define NOT_REACHED() \
do { \
  LOG_ABORT(@"<INTERNAL INCONSISTENCY> @ %s:%i", __FILE__, __LINE__); \
} while (0)

#define DNOT_REACHED() NOT_REACHED()
#define RNOT_REACHED()

#endif

typedef void (*LoggingLiveCallback)(LogLevel level, NSString* message);
typedef void (*LoggingReplayCallback)(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message, void* context);

#ifdef __cplusplus
extern "C" {
#endif
void LogMessage(LogLevel level, NSString* format, ...);
void LogMessageExtended(LogLevel level, NSString* format, va_list arguments);

const char* LoggingGetLevelName(LogLevel level);
void LoggingSetMinimumLevel(LogLevel level);  // Default is kLogLevel_Debug unless overridden by "logLevel" environment variable
LogLevel LoggingGetMinimumLevel();

void LoggingSetCallback(LoggingLiveCallback callback);  // Callback must be thread-safe - Parameter "timestamp" is undefined
LoggingLiveCallback LoggingGetCallback();

BOOL LoggingIsHistoryEnabled();
BOOL LoggingEnableHistory(NSString* path, NSUInteger appVersion);  // Create if non-existing - Pass nil to close
void LoggingPurgeHistory(NSTimeInterval maxAge);  // Pass 0.0 to clear entirely
void LoggingReplayHistory(LoggingReplayCallback callback, void* context, BOOL backward);
#if NS_BLOCKS_AVAILABLE
void LoggingEnumerateHistory(BOOL backward,
                             void (^block)(NSUInteger appVersion, NSTimeInterval timestamp, LogLevel level, NSString* message));
#endif
void LoggingDisableHistory();

BOOL LoggingIsRemoteAccessEnabled();
BOOL LoggingEnableRemoteAccess(NSUInteger port);
void LoggingDisableRemoteAccess(BOOL keepConnectionAlive);

// For internal use only, do NOT use directly
LogLevel _minimumLogLevel;
#ifdef __cplusplus
}
#endif
