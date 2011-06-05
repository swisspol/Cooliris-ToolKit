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

// Required header search path: "${SDKROOT}/usr/include/libxml2"
// Required library: "${SDKROOT}/usr/lib/libxml2.dylib"

#import "Logging.h"

#define kLibXMLSeparator_Path ':'
#define kLibXMLSeparator_Namespace '@'
#define kLibXMLSeparator_Attribute '|'
#define kLibXMLSeparator_Value '='

#define LIBXML_IS_NEWLINE(C) (((C) == '\r') || ((C) == '\n'))
#define LIBXML_IS_WHITESPACE(C) (((C) == ' ') || ((C) == '\t'))
#define LIBXML_IS_WHITESPACE_OR_NEWLINE(C) (LIBXML_IS_WHITESPACE(C) || LIBXML_IS_NEWLINE(C))

@class LibXMLNode;

typedef enum {
  kLibXMLNodeApplierPreFunctionState_Abort = -1,
  kLibXMLNodeApplierPreFunctionState_Skip = 0,
  kLibXMLNodeApplierPreFunctionState_Continue = 1
} LibXMLNodeApplierPreFunctionState;

// Name is UTF-8 C string or NULL for text nodes
typedef LibXMLNodeApplierPreFunctionState (*LibXMLNodeApplierPreFunction)(const unsigned char* name, LibXMLNode* node, void* context);
typedef void (*LibXMLNodeApplierPostFunction)(const unsigned char* name, void* context);
typedef BOOL (*LibXMLNodeSkipFunction)(const unsigned char* name, LibXMLNode* node, void* context);

// LibXMLParser is case-sensitive for paths and attribute names
@interface LibXMLParser : NSObject {
@private
  void* _xmlDoc;
}
@property(nonatomic, readonly) LibXMLNode* rootNode;
+ (void) setErrorReportingLogLevel:(LogLevel)level;
+ (LogLevel) errorReportingLogLevel;  // Default is kLogLevel_Debug
- (id) initWithXMLUTF8Data:(NSData*)data;
- (id) initWithHTMLUTF8Data:(NSData*)data;
- (LibXMLNode*) firstChildAtPath:(NSString*)path;
- (LibXMLNode*) firstDescendantWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value;
@end

// Passing a non-nil attribute but a nil value returns the first node with this attribute not defined
@interface LibXMLNode : NSObject {
@private
  LibXMLParser* _parser;
  void* _xmlNode;
  NSString* _name;
  NSArray* _children;
  NSString* _content;
  NSMutableDictionary* _attributes;
}
@property(nonatomic, readonly) LibXMLNode* previousNode;
@property(nonatomic, readonly) LibXMLNode* nextNode;
@property(nonatomic, readonly) LibXMLNode* parentNode;
@property(nonatomic, readonly) NSArray* children; // nil for text nodes
@property(nonatomic, readonly) NSString* name;  // nil for text nodes
@property(nonatomic, readonly) NSString* content;
@property(nonatomic, readonly) NSDictionary* attributes; // nil for text nodes
@property(nonatomic, readonly) NSData* rawContent;
@property(nonatomic, readonly) void* nativeNode;
- (NSString*) valueForAttribute:(NSString*)attribute;
- (void) applyFunctionsToChildren:(LibXMLNodeApplierPreFunction)preFunction
                     postFunction:(LibXMLNodeApplierPostFunction)postFunction
                          context:(void*)context;
#if NS_BLOCKS_AVAILABLE
- (void) enumerateChildrenUsingPreBlock:(LibXMLNodeApplierPreFunctionState (^)(const unsigned char* name, LibXMLNode* node))preBlock
                              postBlock:(void (^)(const unsigned char* name))postBlock;
#endif
- (LibXMLNode*) firstChildAtPath:(NSString*)path;
- (LibXMLNode*) firstDescendantWithName:(NSString*)name;
- (LibXMLNode*) firstDescendantWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value;
- (LibXMLNode*) firstChildWithName:(NSString*)name;
- (LibXMLNode*) firstChildWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value;
- (LibXMLNode*) nextSiblingWithName:(NSString*)name;
- (LibXMLNode*) nextSiblingWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value;
- (NSArray*) childrenWithName:(NSString*)name;
- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace;  // Trim from both ends
- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace
                          skipFunction:(LibXMLNodeSkipFunction)function
                               context:(void*)context;  // Node and its descendants are skipped if function returns YES
#if NS_BLOCKS_AVAILABLE
- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace
                          skipBlock:(BOOL (^)(const unsigned char* name, LibXMLNode* node))block;  // Node and its descendants are skipped if function returns YES
#endif
- (NSData*) mergeRawContentFromChildren;
- (NSString*) extractTextFromMergedHTML;
@end
