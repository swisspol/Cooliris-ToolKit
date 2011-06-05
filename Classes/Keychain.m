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

#import <Security/Security.h>

#import "Keychain.h"
#import "Logging.h"

@implementation Keychain

+ (Keychain*) sharedKeychain {
  static Keychain* keychain = nil;
  if (keychain == nil) {
    keychain = [[Keychain alloc] init];
  }
  return keychain;
}

- (BOOL) setPassword:(id)password forAccount:(NSString*)account {
  CHECK(password);
  CHECK(account);
  NSString* error = nil;
  NSData* data = [NSPropertyListSerialization dataFromPropertyList:password
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                  errorDescription:&error];
  if (data == nil) {
    LOG_ERROR(@"Failed serializing item for account \"%@\" for Keychain: %@", account, error);
    return NO;
  }
#if TARGET_OS_IPHONE
  NSMutableDictionary* query = [[NSMutableDictionary alloc] init];
  [query setObject:account forKey:(id)kSecAttrAccount];
  [query setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
  NSMutableDictionary* attributes = [[NSMutableDictionary alloc] init];
  [attributes setObject:data forKey:(id)kSecValueData];
  OSStatus status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)attributes);
  if (status == errSecItemNotFound) {
    [attributes addEntriesFromDictionary:query];
    status = SecItemAdd((CFDictionaryRef)attributes, NULL);
  }
  [attributes release];
  [query release];
#else
  const char* name = [account UTF8String];
  OSStatus status = SecKeychainAddGenericPassword(NULL, strlen(name), name, strlen(name), name, data.length, data.bytes, NULL);
#endif
  if (status != noErr) {
    LOG_ERROR(@"Failed adding item for account \"%@\" to Keychain (%i)", account, status);
    return NO;
  }
  return YES;
}

- (id) passwordForAccount:(NSString*)account {
  CHECK(account);
  id password = nil;
  NSData* data = nil;
#if TARGET_OS_IPHONE
  NSMutableDictionary* query = [[NSMutableDictionary alloc] init];
  [query setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
  [query setObject:account forKey:(id)kSecAttrAccount];
  [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
  OSStatus status = SecItemCopyMatching((CFDictionaryRef)query, (CFTypeRef*)&data);
  [query release];
#else
  UInt32 length = 0;
  void* bytes = 0;
  const char* name = [account UTF8String];
  OSStatus status = SecKeychainFindGenericPassword(NULL, strlen(name), name, strlen(name), name, &length, &bytes, NULL);
  if (status == noErr) {
    data = [[NSData alloc] initWithBytes:bytes length:length];
    SecKeychainItemFreeContent(NULL, bytes);
  }
#endif
  if (status == noErr) {
    NSString* error = nil;
    password = [NSPropertyListSerialization propertyListFromData:(NSData*)data
                                                mutabilityOption:NSPropertyListImmutable
                                                          format:NULL
                                                errorDescription:&error];
    if (password == nil) {
      LOG_ERROR(@"Failed deserializing item for account \"%@\" from Keychain: %@", account, error);
    }
    [data release];
  } else if (status != errSecItemNotFound) {
    LOG_ERROR(@"Failed retrieving item for account \"%@\" from Keychain (%i)", account, status);
  }
  return password;
}

- (BOOL) removePasswordForAccount:(NSString*)account {
  CHECK(account);
#if TARGET_OS_IPHONE
  NSMutableDictionary* query = [[NSMutableDictionary alloc] init];
  [query setObject:(id)kSecClassGenericPassword forKey:(id)kSecClass];
  [query setObject:account forKey:(id)kSecAttrAccount];
  OSStatus status = SecItemDelete((CFDictionaryRef)query);
  [query release];
#else
  SecKeychainItemRef item = NULL;
  const char* name = [account UTF8String];
  OSStatus status = SecKeychainFindGenericPassword(NULL, strlen(name), name, strlen(name), name, NULL, NULL, &item);
  if (status == noErr) {
    status = SecKeychainItemDelete(item);  // TODO: Should we call CFRelease() on the item as well?
  }
#endif
  if ((status != noErr) && (status != errSecItemNotFound)) {
    LOG_ERROR(@"Failed deleting item for account \"%@\" from Keychain (%i)", account, status);
    return NO;
  }
  return YES;
}

@end
