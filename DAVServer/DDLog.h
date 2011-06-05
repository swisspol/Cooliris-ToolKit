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

// Fake DDLog implementation that redirects to Logging

#if 1
#import "../Classes/Logging.h"
#else
#define LOG_ERROR(...) NSLog(__VA_ARGS__)
#define LOG_WARNING(...) NSLog(__VA_ARGS__)
#define LOG_INFO(...) NSLog(__VA_ARGS__)
#define LOG_VERBOSE(...) NSLog(__VA_ARGS__)
#endif

#define LOG_FLAG_ERROR    (1 << 0)  // 0...0001
#define LOG_FLAG_WARN     (1 << 1)  // 0...0010
#define LOG_FLAG_INFO     (1 << 2)  // 0...0100
#define LOG_FLAG_VERBOSE  (1 << 3)  // 0...1000

#define THIS_FILE [(id)CFSTR(__FILE__) lastPathComponent]
#define THIS_METHOD NSStringFromSelector(_cmd)

#define LOG_OBJC_MAYBE(sync, lvl, flg, ctx, frmt, ...) \
  do { \
    if ((flg) & LOG_FLAG_ERROR) { \
      LOG_ERROR(frmt, ##__VA_ARGS__) \
    } else if ((flg) & LOG_FLAG_WARN) { \
      LOG_WARNING(frmt, ##__VA_ARGS__) \
    } else if ((flg) & LOG_FLAG_INFO) { \
      LOG_INFO(frmt, ##__VA_ARGS__) \
    } else if ((flg) & LOG_FLAG_VERBOSE) { \
      LOG_VERBOSE(frmt, ##__VA_ARGS__) \
    } \
  } while (0)
