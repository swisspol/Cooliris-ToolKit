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

#import <libxml/HTMLParser.h>

#import "LibXMLParser.h"
#import "SmartDescription.h"
#import "Logging.h"

#define IS_TEXT_NODE(__NODE__) (((__NODE__)->type == XML_TEXT_NODE) || ((__NODE__)->type == XML_CDATA_SECTION_NODE))
#define IS_ELEMENT_NODE(__NODE__) ((__NODE__)->type == XML_ELEMENT_NODE)
#define IS_VALID_NODE(__NODE__) (IS_TEXT_NODE(__NODE__) || IS_ELEMENT_NODE(__NODE__))

@interface LibXMLData : NSData {
@private
  id _owner;
  const void* _bytes;
  NSUInteger _length;
}
- (id) initWithOwner:(id)owner bytes:(const void*)bytes length:(NSUInteger)length;
@end

@interface LibXMLNode ()
- (id) initWithParser:(LibXMLParser*)parser node:(xmlNodePtr)node;
@end

@interface LibXMLParser ()
- (id) initWithUTF8Data:(NSData*)data isHTML:(BOOL)flag;
@end

static LogLevel _xmlLogLevel = kLogLevel_Debug;

static inline BOOL _IsNodeMatchingName(xmlNodePtr node, const xmlChar* name) {
  if (node->name) {
    int length = node->ns && node->ns->prefix ? xmlUTF8Strlen(node->ns->prefix) : 0;
    if (length) {
      if (*name != kLibXMLSeparator_Namespace) {
        if (xmlStrncmp(node->ns->prefix, name, length)) {
          return NO;
        }
        name += length;
        if (*name != kLibXMLSeparator_Namespace) {
          return NO;
        }
      }
      name += 1;
    } else if (*name == kLibXMLSeparator_Namespace) {
      name += 1;
    }
    return !xmlStrcmp(node->name, name);
  }
  return NO;
}

static xmlNodePtr _ChildWithNameAndAttribute(xmlNodePtr child, const xmlChar* name, const xmlChar* attribute, const xmlChar* value) {
  while (child) {
    // Check if the name matches if specified
    if (IS_VALID_NODE(child) && (!name || _IsNodeMatchingName(child, name))) {
      // Check if the attribute matches if specified
      if (attribute) {
        xmlAttrPtr property = child->properties;
        if (value) {
          // Return first node with this attribute and value
          while (property) {
            if (property->children && !property->children->next) {
              if (!xmlStrcmp(property->name, attribute) && !xmlStrcmp(property->children->content, value)) {
                return child;
              }
            }
            property = property->next;
          }
        } else {
          // Return first node without this attribute
          while (property) {
            if (property->children && !property->children->next) {
              if (!xmlStrcmp(property->name, attribute)) {
                break;
              }
            }
            property = property->next;
          }
          if (property == NULL) {
            return child;
          }
        }
      } else {
        return child;
      }
    }
    child = child->next;
  }
  return NULL;
}

static xmlNodePtr _FirstNodeWithNameAndAttribute(xmlNodePtr root, const xmlChar* name, const xmlChar* attribute, const xmlChar* value) {
  xmlNodePtr node = _ChildWithNameAndAttribute(root->children, name, attribute, value);
  if (node == NULL) {
    xmlNodePtr child = root->children;
    while (child) {
      if (IS_VALID_NODE(child)) {
        xmlNodePtr node = _FirstNodeWithNameAndAttribute(child, name, attribute, value);
        if (node) {
          return node;
        }
      }
      child = child->next;
    }
  }
  return node;
}

// TODO: Add support for element index with '#'
static xmlNodePtr _FirstNodeAtPath(xmlNodePtr root, const xmlChar* path) {
  if (path) {
    const xmlChar* componentStart = path;
    const xmlChar* componentEnd = path;
    while (*componentEnd) {
      // Scan until next component separator (:)
      while (*componentEnd && (*componentEnd != kLibXMLSeparator_Path)) {
        ++componentEnd;
      }
      
      // Find attribute separator inside component if any (|)
      const xmlChar* attributeSeparator = componentStart;
      while ((attributeSeparator != componentEnd) && (*attributeSeparator != kLibXMLSeparator_Attribute)) {
        ++attributeSeparator;
      }
      if (attributeSeparator == componentEnd) {
        attributeSeparator = NULL;
      }
      
      // Find value separator inside component if any (=)
      const xmlChar* valueSeparator = attributeSeparator;
      if (valueSeparator) {
        while ((valueSeparator != componentEnd) && (*valueSeparator != kLibXMLSeparator_Value)) {
          ++valueSeparator;
        }
        if (valueSeparator == componentEnd) {
          valueSeparator = NULL;
        }
      }
      
      // Extract name
      const xmlChar* nameStart = componentStart;
      const xmlChar* nameEnd = attributeSeparator && valueSeparator ? attributeSeparator : componentEnd;
      xmlChar name[nameEnd - nameStart + 1];
      bcopy(nameStart, name, nameEnd - nameStart);
      name[nameEnd - nameStart] = 0;
      
      // Extract attribute
      const xmlChar* attributeStart = attributeSeparator && valueSeparator ? attributeSeparator + 1 : NULL;
      const xmlChar* attributeEnd = attributeSeparator && valueSeparator ? valueSeparator : NULL;
      xmlChar attribute[attributeEnd - attributeStart + 1];
      bcopy(attributeStart, attribute, attributeEnd - attributeStart);
      attribute[attributeEnd - attributeStart] = 0;
      
      // Extract value
      const xmlChar* valueStart = attributeSeparator && valueSeparator ? valueSeparator + 1 : NULL;
      const xmlChar* valueEnd = attributeSeparator && valueSeparator ? componentEnd : NULL;
      xmlChar value[valueEnd - valueStart + 1];
      bcopy(valueStart, value, valueEnd - valueStart);
      value[valueEnd - valueStart] = 0;
      
      // Look for matching child
      xmlNodePtr node = _ChildWithNameAndAttribute(root->children, name, attribute[0] ? attribute : NULL, value[0] ? value : NULL);
      if (node == NULL) {
        break;
      }
      
      // Check if at end or skip component separator
      if (*componentEnd == kLibXMLSeparator_Path) {
        ++componentEnd;
        componentStart = componentEnd;
        root = node;
      } else {
        return node;
      }
    }
  }
  return NULL;
}

@implementation LibXMLData

- (id) initWithOwner:(id)owner bytes:(const void*)bytes length:(NSUInteger)length {
  if ((self = [super init])) {
    _owner = [owner retain];
    _bytes = bytes;
    _length = length;
  }
  return self;
}

- (void) dealloc {
  [_owner release];
  
  [super dealloc];
}

- (NSUInteger) length {
  return _length;
}

- (const void*) bytes {
  return _bytes;
}

@end

@implementation LibXMLNode

- (id) initWithParser:(LibXMLParser*)parser node:(xmlNodePtr)node {
  if ((self = [super init])) {
    _parser = [parser retain];
    _xmlNode = node;
  }
  return self;
}

- (void) dealloc {
  [_content release];
  [_children release];
  [_parser release];
  [_name release];
  [_attributes release];
  
  [super dealloc];
}

- (NSString*) name {
  if (!_name && IS_ELEMENT_NODE((xmlNodePtr)_xmlNode)) {
    _name = [[NSString alloc] initWithUTF8String:(const char*)((xmlNodePtr)_xmlNode)->name];
  }
  return _name;
}

- (NSArray*) _copyChildrenWithName:(NSString*)name {
  NSMutableArray* array = [NSMutableArray new];
  xmlNodePtr child = ((xmlNodePtr)_xmlNode)->children;
  xmlChar* nameUTF8 = (xmlChar*)[name UTF8String];
  
  while (child) {
    if (IS_VALID_NODE(child) && (!nameUTF8 || _IsNodeMatchingName(child, nameUTF8))) {
      LibXMLNode* node = [[LibXMLNode alloc] initWithParser:_parser node:child];
      [array addObject:node];
      [node release];
    }
    child = child->next;
  }
  
  return array;
}

- (LibXMLNode*) previousNode {
  xmlNodePtr node = ((xmlNodePtr)_xmlNode)->prev;
  return node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil;
}

- (LibXMLNode*) nextNode {
  xmlNodePtr node = ((xmlNodePtr)_xmlNode)->next;
  return node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil;
}

- (LibXMLNode*) parentNode {
  xmlNodePtr node = ((xmlNodePtr)_xmlNode)->parent;
  return node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil;
}

- (NSArray*) children {
  if (!_children && IS_ELEMENT_NODE((xmlNodePtr)_xmlNode)) {
    _children = [self _copyChildrenWithName:nil];
  }
  return _children;
}

- (NSString*) content {
  if (_content == nil) {
    if (IS_TEXT_NODE((xmlNodePtr)_xmlNode)) {
      _content = [[NSString alloc] initWithCString:(const char*)((xmlNodePtr)_xmlNode)->content encoding:NSUTF8StringEncoding];
    } else {
      xmlNodePtr child = ((xmlNodePtr)_xmlNode)->children;
      if (child && (child->next == NULL) && IS_TEXT_NODE(child)) {
        _content = [[NSString alloc] initWithCString:(const char*)child->content encoding:NSUTF8StringEncoding];
      } else {  // In case there are multiple children text nodes, merge them
        NSMutableData* data = [[NSMutableData alloc] init];
        while (child) {
          if (IS_TEXT_NODE(child)) {
            [data appendBytes:child->content length:strlen((const char*)child->content)];
          }
          child = child->next;
        }
        _content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [data release];
      }
    }
  }
  return _content;
}

- (NSDictionary*) attributes {
  if (!_attributes && IS_ELEMENT_NODE((xmlNodePtr)_xmlNode)) {
    _attributes = [[NSMutableDictionary alloc] init];
    xmlAttrPtr attribute = ((xmlNodePtr)_xmlNode)->properties;
    while (attribute) {
      if (attribute->children && !attribute->children->next) {
        [_attributes setObject:[NSString stringWithUTF8String:(const char*)attribute->children->content]
                        forKey:[NSString stringWithUTF8String:(const char*)attribute->name]];
      }
      attribute = attribute->next;
    }
  }
  return _attributes;
}

- (NSData*) rawContent {
  const xmlChar* content = NULL;
  if (IS_TEXT_NODE((xmlNodePtr)_xmlNode)) {
    content = ((xmlNodePtr)_xmlNode)->content;
  } else {
    xmlNodePtr child = ((xmlNodePtr)_xmlNode)->children;
    if (child && (child->next == NULL) && IS_TEXT_NODE(child)) {
      content = child->content;
    }
  }
  if (content) {  // Use a custom NSData to avoid copying the bytes
    LibXMLData* data = [[LibXMLData alloc] initWithOwner:self bytes:content length:strlen((const char*)content)];
    return [data autorelease];
  }
  return nil;
}

- (void*) nativeNode {
  return _xmlNode;
}

- (NSString*) valueForAttribute:(NSString*)attribute {
  return [self.attributes objectForKey:attribute];
}

static BOOL _ApplyFunctions(LibXMLParser* parser, xmlNodePtr root, LibXMLNodeApplierPreFunction preFunction,
                            LibXMLNodeApplierPostFunction postFunction, void* context) {
  xmlNodePtr child = root->children;
  while (child) {
    if (IS_VALID_NODE(child)) {
      LibXMLNode* node = [[LibXMLNode alloc] initWithParser:parser node:child];
      LibXMLNodeApplierPreFunctionState state = preFunction
                                              ? (*preFunction)(IS_TEXT_NODE(child) ? NULL : child->name, node, context)
                                              : kLibXMLNodeApplierPreFunctionState_Continue;
      [node release];  // Don't keep the node around during recursion to avoid having too many in flight
      
      if (state == kLibXMLNodeApplierPreFunctionState_Continue) {
        if (!_ApplyFunctions(parser, child, preFunction, postFunction, context)) {
          state = kLibXMLNodeApplierPreFunctionState_Abort;
        }
      }
      
      if (postFunction) {
        (*postFunction)(IS_TEXT_NODE(child) ? NULL : child->name, context);
      }
      
      if (state == kLibXMLNodeApplierPreFunctionState_Abort) {
        return NO;
      }
    }
    child = child->next;
  }
  return YES;
}

- (void) applyFunctionsToChildren:(LibXMLNodeApplierPreFunction)preFunction
                     postFunction:(LibXMLNodeApplierPostFunction)postFunction
                          context:(void*)context {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  _ApplyFunctions(_parser, _xmlNode, preFunction, postFunction, context);
  [pool release];
}

#if NS_BLOCKS_AVAILABLE

static LibXMLNodeApplierPreFunctionState _BlockNodeApplierPreFunction(const unsigned char* name, LibXMLNode* node, void* context) {
  void** params = (void**)context;
  LibXMLNodeApplierPreFunctionState (^callback)(const unsigned char* name, LibXMLNode* node) = params[0];
  return callback(name, node);
}

static void _BlockNodeApplierPostFunction(const unsigned char* name, void* context) {
  void** params = (void**)context;
  void (^callback)(const unsigned char* name) = params[1];
  return callback(name);
}

- (void) enumerateChildrenUsingPreBlock:(LibXMLNodeApplierPreFunctionState (^)(const unsigned char* name, LibXMLNode* node))preBlock
                              postBlock:(void (^)(const unsigned char* name))postBlock {
  void* params[] = {preBlock, postBlock};
  [self applyFunctionsToChildren:_BlockNodeApplierPreFunction postFunction:_BlockNodeApplierPostFunction context:params];
}

#endif

- (LibXMLNode*) firstChildAtPath:(NSString*)path {
  xmlNodePtr node = _FirstNodeAtPath(_xmlNode, (const xmlChar*)[path UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil);
}

- (LibXMLNode*) firstDescendantWithName:(NSString*)name {
  return [self firstDescendantWithName:name attribute:nil value:nil];
}

- (LibXMLNode*) firstDescendantWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value {
  xmlNodePtr node = _FirstNodeWithNameAndAttribute(_xmlNode, (const xmlChar*)[name UTF8String],
                                                   (const xmlChar*)[attribute UTF8String], (const xmlChar*)[value UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil);
}

- (LibXMLNode*) firstChildWithName:(NSString*)name {
  return [self firstChildWithName:name attribute:nil value:nil];
}

- (LibXMLNode*) firstChildWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value {
  xmlNodePtr node = _ChildWithNameAndAttribute(((xmlNodePtr)_xmlNode)->children, (const xmlChar*)[name UTF8String],
                                               (const xmlChar*)[attribute UTF8String], (const xmlChar*)[value UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil);
}

- (LibXMLNode*) nextSiblingWithName:(NSString*)name {
  return [self nextSiblingWithName:name attribute:nil value:nil];
}

- (LibXMLNode*) nextSiblingWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value {
  xmlNodePtr node = _ChildWithNameAndAttribute(((xmlNodePtr)_xmlNode)->next, (const xmlChar*)[name UTF8String],
                                               (const xmlChar*)[attribute UTF8String], (const xmlChar*)[value UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:_parser node:node] autorelease] : nil);
}

- (NSArray*) childrenWithName:(NSString*)name {
  return [[self _copyChildrenWithName:name] autorelease];
}

static LibXMLNodeApplierPreFunctionState _MergeContentFunction(const unsigned char* name, LibXMLNode* node, void* context) {
  void** params = (void**)context;
  NSMutableData* data = params[0];
  LibXMLNodeSkipFunction skipFunction = params[1];
  void* skipContext = params[2];
  if (name) {
    if (skipFunction && (*skipFunction)(name, node, skipContext)) {
      return kLibXMLNodeApplierPreFunctionState_Skip;
    }
  } else {
    const xmlChar* content = ((xmlNodePtr)node->_xmlNode)->content;
    [data appendBytes:content length:strlen((const char*)content)];
  }
  return kLibXMLNodeApplierPreFunctionState_Continue;
}

- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace {
  return [self mergeContentFromChildren:trimTrailingWhitespace skipFunction:NULL context:NULL];
}

- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace
                          skipFunction:(LibXMLNodeSkipFunction)function
                               context:(void*)context {
  NSMutableData* data = [[NSMutableData alloc] init];
  void* params[] = {data, function, context};
  _ApplyFunctions(_parser, _xmlNode, _MergeContentFunction, NULL, params);
  const char* bytes = data.bytes;
  NSUInteger length = data.length;
  if (trimTrailingWhitespace) {
    while (length && LIBXML_IS_WHITESPACE_OR_NEWLINE(bytes[0])) {
      ++bytes;
      --length;
    }
    while (length && LIBXML_IS_WHITESPACE_OR_NEWLINE(bytes[length - 1])) {
      --length;
    }
  }
  NSString* string = [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding];
  [data release];
  return [string autorelease];
}

#if NS_BLOCKS_AVAILABLE

static BOOL _BlockNodeSkipFunction(const unsigned char* name, LibXMLNode* node, void* context) {
  BOOL (^callback)(const unsigned char* name, LibXMLNode* node) = context;
  return callback(name, node);
}

- (NSString*) mergeContentFromChildren:(BOOL)trimTrailingWhitespace
                          skipBlock:(BOOL (^)(const unsigned char* name, LibXMLNode* node))block {
  return [self mergeContentFromChildren:trimTrailingWhitespace skipFunction:_BlockNodeSkipFunction context:block];
}

#endif

- (NSData*) mergeRawContentFromChildren {
  NSMutableData* data = [[NSMutableData alloc] init];
  void* params[] = {data, NULL, NULL};
  _ApplyFunctions(_parser, _xmlNode, _MergeContentFunction, NULL, params);
  return [data autorelease];
}

static NSUInteger __CleanUTF8Text(const xmlChar* inBytes, NSUInteger inLength, char* outBytes) {
  NSUInteger outLength = 0;
  
  // Strip whitespace and newlines at the beginning
  while (inLength && LIBXML_IS_WHITESPACE_OR_NEWLINE(inBytes[0])) {
    ++inBytes;
    --inLength;
  }
  
  // Strip whitespace and newlines at the end
  while (inLength && LIBXML_IS_WHITESPACE_OR_NEWLINE(inBytes[inLength - 1])) {
    --inLength;
  }
  
  // Concatenate multiple whitespaces / newlines as a single whitespace or newline
  while (inLength) {
    if (LIBXML_IS_WHITESPACE_OR_NEWLINE(*inBytes)) {
      BOOL hasNewline = LIBXML_IS_NEWLINE(*inBytes);
      ++inBytes;
      --inLength;
      while (inLength) {
        if (LIBXML_IS_NEWLINE(*inBytes)) {
          hasNewline = YES;
        } else if (!LIBXML_IS_WHITESPACE(*inBytes)) {
          break;
        }
        ++inBytes;
        --inLength;
      }
      *outBytes++ = hasNewline ? '\n' : ' ';
      ++outLength;
    } else {
      *outBytes++ = *inBytes++;
      ++outLength;
      --inLength;
    }
  }
  
  return outLength;
}

static LibXMLNodeApplierPreFunctionState _ExtractTextPreFunction(const unsigned char* name, LibXMLNode* node, void* context) {
  NSMutableData* data = (NSMutableData*)context;
  if (name) {
    // Convert <br> to newlines
    if (!strcmp((char*)name, "br")) {
      char newline = '\n';
      [data appendBytes:&newline length:1];
    }
  } else {
    const xmlChar* contentBytes = ((xmlNodePtr)node->_xmlNode)->content;
    NSUInteger contentLength = strlen((const char*)contentBytes);
    NSUInteger oldLength = data.length;
    [data setLength:(oldLength + contentLength)];
    bcopy(contentBytes, (char*)data.bytes + oldLength, contentLength);
  }
  return kLibXMLNodeApplierPreFunctionState_Continue;
}

static void _ExtractTextPostFunction(const unsigned char* name, void* context) {
  NSMutableData* data = (NSMutableData*)context;
  if (name) {
    // Convert <p> and <tr> to newlines
    if (!strcmp((char*)name, "p") || !strcmp((char*)name, "tr")) {
      char newline = '\n';
      [data appendBytes:&newline length:1];
    }
    // Convert <td> to spaces
    else if (!strcmp((char*)name, "td")) {
      char space = ' ';
      [data appendBytes:&space length:1];
    }
  }
}

- (NSString*) extractTextFromMergedHTML {
  NSMutableData* rawData = [[NSMutableData alloc] init];
  _ApplyFunctions(_parser, _xmlNode, _ExtractTextPreFunction, _ExtractTextPostFunction, rawData);
  NSMutableData* cleanData = [[NSMutableData alloc] initWithLength:rawData.length];
  NSUInteger length = __CleanUTF8Text(rawData.mutableBytes, rawData.length, cleanData.mutableBytes);
  [cleanData setLength:length];
  NSString* string = [[NSString alloc] initWithData:cleanData encoding:NSUTF8StringEncoding];
  [cleanData release];
  [rawData release];
  return [string autorelease];
}

static void _AppendNodeDescription(xmlNodePtr node, NSMutableString* string, NSString* prefix) {
  NSString* content = node->content ? [NSString stringWithUTF8String:(const char*)node->content] : nil;
  content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@"¶"];  // 0x00B6
  if (IS_TEXT_NODE(node)) {
    [string appendFormat:@"%@TEXT = \"%@\"", prefix, content];
  } else if (IS_ELEMENT_NODE(node)) {
    if (content) {
      if (node->ns && node->ns->prefix) {
        [string appendFormat:@"%@<%s:%s> = \"%@\"", prefix, node->ns->prefix, node->name, content];
      } else {
        [string appendFormat:@"%@<%s> = \"%@\"", prefix, node->name, content];
      }
    } else {
      if (node->ns && node->ns->prefix) {
        [string appendFormat:@"%@<%s:%s>", prefix, node->ns->prefix, node->name];
      } else {
        [string appendFormat:@"%@<%s>", prefix, node->name];
      }
    }
    
    xmlAttrPtr attribute = node->properties;
    while (attribute) {
      if (attribute->children && !attribute->children->next) {
        [string appendFormat:@" | %s = \"%@\"", attribute->name,
                             [NSString stringWithUTF8String:(const char*)attribute->children->content]];
      }
      attribute = attribute->next;
    }
  } else {
    if (content) {
      [string appendFormat:@"%@NODE = \"%@\"", prefix, content];
    } else {
      [string appendFormat:@"%@NODE", prefix];
    }
  }
  [string appendString:@"\n"];
  
  node = node->children;
  if (node) {
    prefix = [prefix stringByAppendingString:@"\t"];
    while (node) {
      _AppendNodeDescription(node, string, prefix);
      node = node->next;
    }
  }
}

- (NSString*) description {
  NSMutableString* string = [NSMutableString stringWithString:[self miniDescription]];
  [string appendString:@"\n"];
  _AppendNodeDescription(_xmlNode, string, @"");
  return string;
}

@end

@implementation LibXMLParser

static void _xmlErrorHandler(void* ctx, const char* msg, ...) {
  va_list args;
  va_start(args, msg);
  NSString* message = [[NSString alloc] initWithFormat:[NSString stringWithUTF8String:msg] arguments:args];
  NSString* trimmed = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  [message release];
  LogMessage(_xmlLogLevel, @"LibXML: %@", trimmed);
  va_end(args);
}

+ (void) setErrorReportingLogLevel:(LogLevel)level {
  _xmlLogLevel = level;
}

+ (LogLevel) errorReportingLogLevel {
  return _xmlLogLevel;
}

- (id) initWithXMLUTF8Data:(NSData*)data {
  return [self initWithUTF8Data:data isHTML:NO];
}

- (id) initWithHTMLUTF8Data:(NSData*)data {
  return [self initWithUTF8Data:data isHTML:YES];
}

- (id) initWithUTF8Data:(NSData*)data isHTML:(BOOL)flag {
  if ((self = [super init])) {
    if (data) {
      BOOL enableLogging = _xmlLogLevel >= LoggingGetMinimumLevel() ? YES : NO;
      if (enableLogging) {
        xmlSetGenericErrorFunc(NULL, _xmlErrorHandler);  // Warning: only applies on the current thread
      }
      if (flag) {
        int options = HTML_PARSE_NONET | HTML_PARSE_RECOVER | HTML_PARSE_NOBLANKS | HTML_PARSE_COMPACT;
        if (!enableLogging) {
          options |= HTML_PARSE_NOWARNING | HTML_PARSE_NOERROR;
        }
        _xmlDoc = htmlReadMemory(data.bytes, data.length, NULL, NULL, options);  // libxml uses UTF-8 by default
      } else {
        int options = XML_PARSE_NONET | XML_PARSE_RECOVER | XML_PARSE_NOBLANKS | XML_PARSE_COMPACT;
        if (!enableLogging) {
          options |= XML_PARSE_NOWARNING | XML_PARSE_NOERROR;
        }
        _xmlDoc = xmlReadMemory(data.bytes, data.length, NULL, NULL, options);  // libxml uses UTF-8 by default
      }
      if (enableLogging) {
        xmlSetGenericErrorFunc(NULL, NULL);
      }
    }
    if (!_xmlDoc || !xmlDocGetRootElement(_xmlDoc)) {
      [self release];
      return nil;
    }
  }
  return self;
}

- (void) dealloc {
  if (_xmlDoc) {
    xmlFreeDoc(_xmlDoc);
  }
  
  [super dealloc];
}

- (LibXMLNode*) rootNode {
  return [[[LibXMLNode alloc] initWithParser:self node:xmlDocGetRootElement(_xmlDoc)] autorelease];
}

- (LibXMLNode*) firstChildAtPath:(NSString*)path {
  xmlNodePtr node = _FirstNodeAtPath(_xmlDoc, (const xmlChar*)[path UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:self node:node] autorelease] : nil);
}

- (LibXMLNode*) firstDescendantWithName:(NSString*)name attribute:(NSString*)attribute value:(NSString*)value {
  xmlNodePtr node = _FirstNodeWithNameAndAttribute(_xmlDoc, (const xmlChar*)[name UTF8String],
                                                   (const xmlChar*)[attribute UTF8String], (const xmlChar*)[value UTF8String]);
  return (node ? [[[LibXMLNode alloc] initWithParser:self node:node] autorelease] : nil);
}

- (NSString*) description {
  return [self smartDescription];
}

@end
