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

#import <objc/runtime.h>
#import <objc/message.h>

#import "SmartDescription.h"
#import "Logging.h"

@implementation NSObject (Extensions)

+ (NSString*) miniDescription {
  return [NSString stringWithFormat:@"<%@>", self];
}

- (NSString*) miniDescription {
  return [NSString stringWithFormat:@"<%@ %p>", [self class], self];
}

- (NSString*) smartDescription {
  NSMutableString* string = [NSMutableString string];
  
  // Append base description
  [string appendString:[self miniDescription]];
  
  // Retrieve values of all compatible object properties
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];
  Class class = [self class];
  while (class != [NSObject class]) {
    unsigned int count = 0;
    objc_property_t* properties = class_copyPropertyList(class, &count);
    if (properties) {
      for (unsigned int i = 0; i < count; ++i) {
        // Get property attributes and make sure the first one is the type
        const char* attributes = property_getAttributes(properties[i]);
        if (attributes[0] == 'T') {
          const char* name = property_getName(properties[i]);
          
          // Check if the getter for the property has a special name
          SEL getter = NULL;
          const char* start = strstr(attributes, ",G");
          if (start) {
            const char* end = strstr(start + 2, ",");
            if (end == NULL) {
              end = start + 2 + strlen(start + 2);
            }
            char buffer[end - start - 2 + 1];
            bcopy(start + 2, buffer, sizeof(buffer));
            buffer[sizeof(buffer) - 1] = 0;
            getter = sel_getUid(buffer);
          } else {
            getter = sel_getUid(name);
          }
          CHECK([self respondsToSelector:getter]);
          
          // Call the getter to retrieve the property value
          NSString* property = [NSString stringWithUTF8String:name];
          NSString* description = nil;
          switch (attributes[1]) {
            
            case 'c': {  // char
              char (*callback)(id, SEL) = (char(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%i", callback(self, getter)];
              break;
            }
            
            case 'C': {  // unsigned char
              unsigned char (*callback)(id, SEL) = (unsigned char(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%u", callback(self, getter)];
              break;
            }
            
            case 's': {  // short
              short (*callback)(id, SEL) = (short(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%i", callback(self, getter)];
              break;
            }
            
            case 'S': {  // unsigned short
              unsigned short (*callback)(id, SEL) = (unsigned short(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%u", callback(self, getter)];
              break;
            }
            
#if !__LP64__
            case 'l':  // long (32 bits)
#endif
            case 'i': {  // int
              int (*callback)(id, SEL) = (int(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%i", callback(self, getter)];
              break;
            }
            
#if !__LP64__
            case 'L':  // unsigned long (32 bits)
#endif
            case 'I': {  // unsigned int
              unsigned int (*callback)(id, SEL) = (unsigned int(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%u", callback(self, getter)];
              break;
            }
            
#if __LP64__
            case 'l':  // long (64 bits)
#endif
            case 'q': {  // long long
              long long (*callback)(id, SEL) = (long long(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%qi", callback(self, getter)];
              break;
            }

#if __LP64__
            case 'L':  // unsigned long (64 bits)
#endif
            case 'Q': {  // unsigned long long
              unsigned long long (*callback)(id, SEL) = (unsigned long long(*)(id, SEL))objc_msgSend;
              description = [NSString stringWithFormat:@"%qu", callback(self, getter)];
              break;
            }
            
            case 'f': {  // float
#if defined(__i386__)
              float (*callback)(id, SEL) = (float(*)(id, SEL))objc_msgSend_fpret;
#else
              float (*callback)(id, SEL) = (float(*)(id, SEL))objc_msgSend;
#endif
              description = [NSString stringWithFormat:@"%f", callback(self, getter)];
              break;
            }
            
            case 'd': {  // double
#if defined(__i386__)
              double (*callback)(id, SEL) = (double(*)(id, SEL))objc_msgSend_fpret;
#else
              double (*callback)(id, SEL) = (double(*)(id, SEL))objc_msgSend;
#endif
              description = [NSString stringWithFormat:@"%f", callback(self, getter)];
              break;
            }
            
            case '@': {  // id
              id (*callback)(id, SEL) = (id(*)(id, SEL))objc_msgSend;
              id object = callback(self, getter);
              if (object == self) {
                description = @"<SELF>";
              } else if ([object isKindOfClass:[NSString class]]) {
                description = [object stringByReplacingOccurrencesOfString:@"\n" withString:@"\n  "];
              } else if ([object isKindOfClass:[NSData class]]) {
                description = [NSString stringWithFormat:@"<DATA | %i BYTES>", [object length]];
              } else if ([object isKindOfClass:[NSDate class]] || [object isKindOfClass:[NSValue class]] ||
                [object isKindOfClass:[NSURL class]]) {
                description = [object description];
              } else if ([object isKindOfClass:[NSArray class]] || [object isKindOfClass:[NSSet class]]) {
                description = [NSMutableString string];
                [(NSMutableString*)description appendFormat:@"[%@]\n  (", NSStringFromClass([object class])];
                NSUInteger index = 0;
                for (id value in object) {
                  value = [[value smartDescription] stringByReplacingOccurrencesOfString:@"\n" withString:@"\n    "];
                  [(NSMutableString*)description appendFormat:@"\n    [%i] ", index++];
                  [(NSMutableString*)description appendString:value];
                }
                [(NSMutableString*)description appendString:@"\n  )"];
              } else if ([object isKindOfClass:[NSDictionary class]]) {
                description = [NSMutableString string];
                [(NSMutableString*)description appendFormat:@"[%@]\n  (", NSStringFromClass([object class])];
                for (id key in object) {
                  id value = [[[object objectForKey:key] smartDescription] stringByReplacingOccurrencesOfString:@"\n"
                                                                                                     withString:@"\n    "];
                  [(NSMutableString*)description appendFormat:@"\n    \"%@\" ", key];
                  [(NSMutableString*)description appendString:value];
                }
                [(NSMutableString*)description appendString:@"\n  )"];
              } else if (object) {
                description = [object miniDescription];  // Calling -description might end up calling -smartDescription recursively
              } else {
                description = @"<NIL>";
              }
              break;
            }
            
            case ':': {  // SEL
              SEL (*callback)(id, SEL) = (SEL(*)(id, SEL))objc_msgSend;
              SEL selector = callback(self, getter);
              description = selector ? NSStringFromSelector(selector) : @"<NULL>";
              break;
            }
            
          }
          [dictionary setValue:description forKey:property];
        }
      }
      free(properties);
    }
    class = [class superclass];
  }
  if (dictionary.count) {
    NSArray* array = [[dictionary allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];  // Sort alphabetically
    [string appendFormat:@"\n{"];
    for (NSString* key in array) {
      [string appendFormat:@"\n  %@ = %@", key, [dictionary valueForKey:key]];
    }
    [string appendFormat:@"\n}"];
  }
  [dictionary release];
  
  return string;
}

@end
