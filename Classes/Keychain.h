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

// Password must be a property list object
@interface Keychain : NSObject
+ (Keychain*) sharedKeychain;
- (BOOL) setPassword:(id)content forAccount:(NSString*)account;
- (id) passwordForAccount:(NSString*)account;  // Returns nil if on error or if account does not exist
- (BOOL) removePasswordForAccount:(NSString*)account;  // Returns YES if account does not exist
@end
