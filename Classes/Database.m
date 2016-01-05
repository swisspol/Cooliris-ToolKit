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
#import <sqlite3.h>
#import <unistd.h>
#import <pthread.h>

#import "Database.h"
#import "SmartDescription.h"
#import "Logging.h"

enum {
  kObjectStatement_CountAll = 0,
  kObjectStatement_SelectAll,
  kObjectStatement_SelectExistsWithRowID,
  kObjectStatement_SelectWithRowID,
  kObjectStatement_Insert,
  kObjectStatement_Replace,
  kObjectStatement_UpdateWithRowID,
  kObjectStatement_DeleteWithRowID,
  kObjectStatement_DeleteAll,
  kObjectStatementCount
};

enum {
  kDatabaseStatement_BeginTransaction = 0,
  kDatabaseStatement_Release,
  kDatabaseStatement_Rollback,
  kDatabaseStatementCount
};

#define kBusyMaxRetries 10
#define kBusyRetryDelay 10  // ms

struct DatabaseSQLColumnDefinition {
  NSString* name;
  DatabaseSQLColumnType columnType;
  NSString* columnName;
  DatabaseSQLColumnOptions columnOptions;
  NSString* columnForeignKey;
  SEL getter;
  SEL setter;
  
  // Set by _InitializeSQLTable()
  size_t size;
  ptrdiff_t offset;
  Class valueClass;
};
typedef struct DatabaseSQLColumnDefinition DatabaseSQLColumnDefinition;

struct DatabaseSQLTableDefinition {
  Class class;
  NSString* tableName;
  NSSet* indices;
  NSString* fetchStatement;
  NSString* fetchOrder;
  unsigned int columnCount;
  DatabaseSQLColumnDefinition* columnList;
  
  // Set by _InitializeSQLTable()
  size_t storageSize;
  char* sql;
  char* statements[kObjectStatementCount];
  
  // For bridged tables only
  DatabaseSchemaTable* schemaTable;
};
typedef struct DatabaseSQLTableDefinition DatabaseSQLTableDefinition;

// Keep in sync with DatabaseSQLColumnType
typedef union {
  int _int;
  double _double;
} ScalarValue;

// Keep in sync with DatabaseSQLColumnType
#define COLUMN_TYPE_IS_SCALAR(__TYPE__) (((__TYPE__) == kDatabaseSQLColumnType_Int) || ((__TYPE__) == kDatabaseSQLColumnType_Double))
#define COLUMN_TYPE_IS_OBJECT(__TYPE__) (((__TYPE__) == kDatabaseSQLColumnType_String) || ((__TYPE__) == kDatabaseSQLColumnType_URL) || \
                                         ((__TYPE__) == kDatabaseSQLColumnType_Date) || ((__TYPE__) == kDatabaseSQLColumnType_Data))


// Keep in sync with DatabaseSQLColumnType
static const NSString* _typeMapping[] = {
                                          nil,
                                          @"INTEGER",
                                          @"REAL",
                                          @"TEXT",
                                          @"TEXT",
                                          @"REAL",
                                          @"BLOB"
                                        };

#ifdef NDEBUG
#define LOCK_CONNECTION()
#define UNLOCK_CONNECTION()
#else
#define LOCK_CONNECTION() CHECK(OSSpinLockTry(&_lock))
#define UNLOCK_CONNECTION() OSSpinLockUnlock(&_lock)
#endif

@interface DatabaseObject ()
@property(nonatomic, readonly) void* _storage;
@property(nonatomic) DatabaseSQLRowID sqlRowID;
- (id) initWithSQLTable:(DatabaseSQLTable)table;
@end

@interface DatabaseSchemaColumn ()
@property(nonatomic, assign) DatabaseSQLColumn sqlColumn;
- (id) initWithSQLColumn:(DatabaseSQLColumn)column;
@end

@interface DatabaseSchemaTable ()
- (id) initWithSQLTable:(DatabaseSQLTable)table;
@end

@interface DatabaseConnection ()
+ (BOOL) initializeDatabaseAtPath:(NSString*)path
                   usingSQLTables:(DatabaseSQLTable*)tables
                            count:(NSUInteger)count
               extraSQLStatements:(NSString*)sql;
@end

@interface DatabasePoolConnection : DatabaseConnection {
@private
  DatabaseConnectionPool* _pool;
}
@property(nonatomic, assign) DatabaseConnectionPool* pool;
@end

static CFMutableDictionaryRef _tableCache = NULL;

static inline DatabaseSQLTable _SQLTableForClass(Class class) {
  DatabaseSQLTable table = (DatabaseSQLTable)CFDictionaryGetValue(_tableCache, class);
  CHECK(table);
  return table;
}

static char* _CopyAsCString(NSString* string) {
  const char* cString = [string UTF8String];
  size_t cLength = strlen(cString);
  char* copy = malloc(cLength + 1);
  bcopy(cString, copy, cLength + 1);
  return copy;
}

static void _InitializeSQLTable(DatabaseSQLTable table) {
  table->storageSize = 0;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    DatabaseSQLColumn column = &table->columnList[i];
    switch (column->columnType) {
      
      case kDatabaseSQLColumnType_Int:
        column->size = sizeof(int);
        column->valueClass = [NSNumber class];
        break;
      
      case kDatabaseSQLColumnType_Double:
        column->size = sizeof(double);
        column->valueClass = [NSNumber class];
        break;
      
      case kDatabaseSQLColumnType_String:
        column->size = sizeof(id);
        column->valueClass = [NSString class];
        break;
      
      case kDatabaseSQLColumnType_URL:
        column->size = sizeof(id);
        column->valueClass = [NSURL class];
        break;
      
      case kDatabaseSQLColumnType_Date:
        column->size = sizeof(id);
        column->valueClass = [NSDate class];
        break;
      
      case kDatabaseSQLColumnType_Data:
        column->size = sizeof(id);
        column->valueClass = [NSData class];
        break;
      
      default:
        NOT_REACHED();
      
    }
    if (table->storageSize % sizeof(long)) {
      table->storageSize = (table->storageSize / sizeof(long) + 1) * sizeof(long);  // Add padding if necessary
    }
    column->offset = table->storageSize;
    table->storageSize += column->size;
  }
  
  if (table->columnCount) {
    {
      NSString* statement = [[NSString alloc] initWithFormat:@"SELECT Count(*) FROM %@", table->tableName];
      table->statements[kObjectStatement_CountAll] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSMutableString* statement = [[NSMutableString alloc] initWithString:table->fetchStatement];
      if (table->fetchOrder) {
        [statement appendFormat:@" ORDER BY %@", table->fetchOrder];
      }
      table->statements[kObjectStatement_SelectAll] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSString* statement = [[NSString alloc] initWithFormat:@"%@ WHERE %@=?1", table->fetchStatement, kDatabaseColumnName_RowID];
      table->statements[kObjectStatement_SelectWithRowID] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSString* statement = [[NSString alloc] initWithFormat:@"SELECT 1 FROM %@ WHERE %@=?1", table->tableName, kDatabaseColumnName_RowID];
      table->statements[kObjectStatement_SelectExistsWithRowID] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSMutableString* statement = [[NSMutableString alloc] init];
      [statement appendFormat:@"INSERT INTO %@ (", table->tableName];
      [statement appendString:table->columnList[0].columnName];
      for (unsigned int i = 1; i < table->columnCount; ++i) {
        if (table->columnList[i].setter) {
          [statement appendFormat:@", %@", table->columnList[i].columnName];
        }
      }
      [statement appendString:@") VALUES (?1"];
      for (unsigned int i = 1; i < table->columnCount; ++i) {
        if (table->columnList[i].setter) {
          [statement appendFormat:@", ?%i", i + 1];
        }
      }
      [statement appendString:@")"];
      table->statements[kObjectStatement_Insert] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSMutableString* statement = [[NSMutableString alloc] init];
      [statement appendFormat:@"REPLACE INTO %@ (", table->tableName];
      [statement appendString:table->columnList[0].columnName];
      for (unsigned int i = 1; i < table->columnCount; ++i) {
        if (table->columnList[i].setter) {
          [statement appendFormat:@", %@", table->columnList[i].columnName];
        }
      }
      [statement appendString:@") VALUES (?1"];
      for (unsigned int i = 1; i < table->columnCount; ++i) {
        if (table->columnList[i].setter) {
          [statement appendFormat:@", ?%i", i + 1];
        }
      }
      [statement appendString:@")"];
      table->statements[kObjectStatement_Replace] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSMutableString* statement = [[NSMutableString alloc] init];
      [statement appendFormat:@"UPDATE %@ SET ", table->tableName];
      [statement appendFormat:@"%@=?2", table->columnList[0].columnName];
      for (unsigned int i = 1; i < table->columnCount; ++i) {
        if (table->columnList[i].setter) {
          [statement appendFormat:@", %@=?%i", table->columnList[i].columnName, i + 2];
        }
      }
      [statement appendFormat:@" WHERE %@=?1", kDatabaseColumnName_RowID];
      table->statements[kObjectStatement_UpdateWithRowID] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSString* statement = [[NSString alloc] initWithFormat:@"DELETE FROM %@ WHERE %@=?1", table->tableName, kDatabaseColumnName_RowID];
      table->statements[kObjectStatement_DeleteWithRowID] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSString* statement = [[NSString alloc] initWithFormat:@"DELETE FROM %@", table->tableName];
      table->statements[kObjectStatement_DeleteAll] = _CopyAsCString(statement);
      [statement release];
    }
    {
      NSMutableString* statement = [[NSMutableString alloc] init];
      [statement appendFormat:@"CREATE TABLE %@ (%@ INTEGER PRIMARY KEY AUTOINCREMENT", table->tableName, kDatabaseColumnName_RowID];
      for (unsigned int i = 0; i < table->columnCount; ++i) {
        [statement appendFormat:@", %@ %@", table->columnList[i].columnName, _typeMapping[table->columnList[i].columnType]];
        DatabaseSQLColumnOptions options = table->columnList[i].columnOptions;
        if (options & kDatabaseSQLColumnOption_CaseInsensitive_ASCII) {
          [statement appendString:@" NOCASE"];
        } else if (options & kDatabaseSQLColumnOption_CaseInsensitive_UTF8) {
          [statement appendString:@" COLLATE utf8"];
        }
        if (options & kDatabaseSQLColumnOption_Unique) {
          [statement appendString:@" UNIQUE"];
        }
        if (options & kDatabaseSQLColumnOption_NotNull) {
          [statement appendString:@" NOT NULL"];
        }
      }
      for (unsigned int i = 0; i < table->columnCount; ++i) {
        if (table->columnList[i].columnForeignKey) {
          [statement appendFormat:@", FOREIGN KEY(%@) REFERENCES %@", table->columnList[i].columnName, table->columnList[i].columnForeignKey];
        }
      }
      [statement appendString:@")"];
      table->sql = _CopyAsCString(statement);
      [statement release];
    }
  }
}

static void _FinalizeSQLTable(DatabaseSQLTable table) {
  [table->tableName release];
  [table->indices release];
  [table->fetchStatement release];
  [table->fetchOrder release];
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    [table->columnList[i].name release];
    [table->columnList[i].columnName release];
    [table->columnList[i].columnForeignKey release];
  }
  free(table->columnList);
  if (table->sql) {
    free(table->sql);
  }
  for (unsigned int i = 0; i < kObjectStatementCount; ++i) {
    if (table->statements[i]) {
      free(table->statements[i]);
    }
  }
  free(table);
}

@implementation DatabaseObject

@synthesize sqlTable=__table, sqlRowID=__rowID, _storage=__storage, modified=__modified;

static inline int _GetField_Int(DatabaseObject* self, DatabaseSQLColumn column) {
  int* ptr = (int*)((char*)self->__storage + column->offset);
  return *ptr;
}

static inline void _SetField_Int(DatabaseObject* self, DatabaseSQLColumn column, int value) {
  int* ptr = (int*)((char*)self->__storage + column->offset);
  if (self->__modified || (*ptr != value)) {
    *ptr = value;
    self->__modified = YES;
  }
}

static inline double _GetField_Double(DatabaseObject* self, DatabaseSQLColumn column) {
  double* ptr = (double*)((char*)self->__storage + column->offset);
  return *ptr;
}

static inline void _SetField_Double(DatabaseObject* self, DatabaseSQLColumn column, double value) {
  double* ptr = (double*)((char*)self->__storage + column->offset);
  if (self->__modified || (*ptr != value)) {
    *ptr = value;
    self->__modified = YES;
  }
}

static inline id _GetField_Object(DatabaseObject* self, DatabaseSQLColumn column) {
  id* ptr = (id*)((char*)self->__storage + column->offset);
  return *ptr;  // TODO: Should we retain / autorelease?
}

static inline void _SetField_Object(DatabaseObject* self, DatabaseSQLColumn column, id object) {
  id* ptr = (id*)((char*)self->__storage + column->offset);
  if (object != *ptr) {
    if (self->__modified || (!object && *ptr) || (object && !*ptr) || ![object isEqual:*ptr]) {
      [*ptr release];  // TODO: Should we autorelease?
      *ptr = [object copy];
      self->__modified = YES;
    }
  }
}

- (id) initWithSQLTable:(DatabaseSQLTable)table {
  DCHECK([self class] == table->class);
  if ((self = [super init])) {
    __table = table;
    if (__table->columnCount) {
      __storage = calloc(1, __table->storageSize);
    }
  }
  return self;
}

- (void) dealloc {
  if (__storage) {
    for (unsigned int i = 0; i < __table->columnCount; ++i) {
      if (COLUMN_TYPE_IS_OBJECT(__table->columnList[i].columnType)) {
        id* ptr = (id*)((char*)__storage + __table->columnList[i].offset);
        if (*ptr) {
          [*ptr release];
        }
      }
    }
    free(__storage);
  }
  
  [super dealloc];
}

- (void) clearModified {
  __modified = NO;
}

- (NSUInteger)hash {
  return __rowID;
}

- (BOOL) isEqual:(id)object {
  return ([object class] == [self class]) && ([(DatabaseObject*)object sqlRowID] == __rowID);
}

- (NSString*) description {
  return [super smartDescription];
}

@end

@implementation DatabaseObject (ObjCBridge)

static inline DatabaseSQLColumn _SQLColumnForGetter(DatabaseSQLTable table, SEL getter) {
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if (table->columnList[i].getter == getter) {
      return &table->columnList[i];
    }
  }
  NOT_REACHED();
  return NULL;
}

static inline DatabaseSQLColumn _SQLColumnForSetter(DatabaseSQLTable table, SEL setter) {
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if (table->columnList[i].setter == setter) {
      return &table->columnList[i];
    }
  }
  NOT_REACHED();
  return NULL;
}

static int _Getter_Int(DatabaseObject* self, SEL cmd) {
  return _GetField_Int(self, _SQLColumnForGetter(self->__table, cmd));
}

static void _Setter_Int(DatabaseObject* self, SEL cmd, int value) {
  _SetField_Int(self, _SQLColumnForSetter(self->__table, cmd), value);
}

static double _Getter_Double(DatabaseObject* self, SEL cmd) {
  return _GetField_Double(self, _SQLColumnForGetter(self->__table, cmd));
}

static void _Setter_Double(DatabaseObject* self, SEL cmd, double value) {
  _SetField_Double(self, _SQLColumnForSetter(self->__table, cmd), value);
}

static id _Getter_Object(DatabaseObject* self, SEL cmd) {
  return _GetField_Object(self, _SQLColumnForGetter(self->__table, cmd));
}

static void _Setter_Object(DatabaseObject* self, SEL cmd, id object) {
  _SetField_Object(self, _SQLColumnForSetter(self->__table, cmd), object);
}

static DatabaseSQLTable _RegisterSQLTableFromDatabaseObjectSubclass(Class class) {
  DatabaseSQLTable table = calloc(1, sizeof(DatabaseSQLTableDefinition));
  table->class = class;
  table->tableName = [[class sqlTableName] copy];
  table->indices = [[class sqlPropertyIndices] copy];
  table->fetchStatement = [[class sqlFetchStatement] copy];
  table->fetchOrder = [[class sqlTableFetchOrder] copy];
  
  table->columnCount = 0;
  table->columnList = malloc(0);
  
  CFMutableDictionaryRef properties = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, NULL);
  Class superclass = class;
  do {
    unsigned int columnCount;
    objc_property_t* propertyList = class_copyPropertyList(superclass, &columnCount);
    for (unsigned int i = 0; i < columnCount; ++i) {
      if (!strstr(property_getAttributes(propertyList[i]), ",D,")) {  // Ignore non-dynamic properties
        continue;
      }
      NSString* name = [NSString stringWithUTF8String:property_getName(propertyList[i])];
      CFDictionarySetValue(properties, name, propertyList[i]);
    }
    free(propertyList);
    superclass = [superclass superclass];
  } while (superclass != [DatabaseObject class]);
  CFIndex count = CFDictionaryGetCount(properties);
  if (count) {
    void* keys = malloc(count * sizeof(NSString*));
    CFDictionaryGetKeysAndValues(properties, keys, NULL);
    NSArray* array = [[NSArray alloc] initWithObjects:keys count:count];
    NSArray* names = [class sqlMappedProperties:array];
    [array release];
    free(keys);
    count = [names count];
    
    if (count) {
      table->columnList = realloc(table->columnList, (table->columnCount + count) * sizeof(DatabaseSQLColumnDefinition));
      DatabaseSQLColumn column = &table->columnList[table->columnCount];
      for (NSString* name in names) {
        objc_property_t property = (objc_property_t)CFDictionaryGetValue(properties, name);
        DCHECK(property);
        const char* attributes = property_getAttributes(property);
        size_t length = strlen(attributes);
        
        column->name = [name copy];
        column->columnName = [[class sqlColumnNameForProperty:name] copy];
        column->columnOptions = [class sqlColumnOptionsForProperty:name];
        column->columnForeignKey = [[class sqlForeignKeyForProperty:name] copy];
        column->getter = sel_registerName([name UTF8String]);
        if (strcmp(&attributes[length - 6], ",R,D,N")) {
          column->setter = sel_registerName([[NSString stringWithFormat:@"set%@%@:", [[name substringToIndex:1] uppercaseString],
                                                                              [name substringFromIndex:1]] UTF8String]);
        } else {
          column->setter = NULL;
        }
        switch (attributes[1]) {
          
          case 'i': {
            column->columnType = kDatabaseSQLColumnType_Int;
            class_addMethod(class, column->getter, (IMP)&_Getter_Int, "i@:");
            if (column->setter) {
              CHECK(!strcmp(&attributes[length - 4], ",D,N"));
              class_addMethod(class, column->setter, (IMP)&_Setter_Int, "v@:i");
            }
            break;
          }
          
          case 'd': {
            column->columnType = kDatabaseSQLColumnType_Double;
            class_addMethod(class, column->getter, (IMP)&_Getter_Double, "d@:");
            if (column->setter) {
              CHECK(!strcmp(&attributes[length - 4], ",D,N"));
              class_addMethod(class, column->setter, (IMP)&_Setter_Double, "v@:d");
            }
            break;
          }
          
          case '@': {
            if (!strncmp(&attributes[3], "NSString", 8)) {
              column->columnType = kDatabaseSQLColumnType_String;
            } else if (!strncmp(&attributes[3], "NSURL", 5)) {
              column->columnType = kDatabaseSQLColumnType_URL;
            } else if (!strncmp(&attributes[3], "NSDate", 6)) {
              column->columnType = kDatabaseSQLColumnType_Date;
            } else if (!strncmp(&attributes[3], "NSData", 6)) {
              column->columnType = kDatabaseSQLColumnType_Data;
            } else {
              NOT_REACHED();
            }
            class_addMethod(class, column->getter, (IMP)&_Getter_Object, "@@:");
            if (column->setter) {
              CHECK(!strcmp(&attributes[length - 6], ",C,D,N"));
              class_addMethod(class, column->setter, (IMP)&_Setter_Object, "v@:@");
            }
            break;
          }
          
          default:
            NOT_REACHED();
            break;
          
        }
        ++column;
      }
      table->columnCount += count;
    }
  }
  CFRelease(properties);
  
  _InitializeSQLTable(table);
  
  return table;
}

+ (void) initialize {
  if (self == [DatabaseObject class]) {
    DCHECK(_tableCache == NULL);
    _tableCache = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
    
    const char* name = class_getImageName(self);
    unsigned int count;
    const char** classes = objc_copyClassNamesForImage(name, &count);
    for (unsigned int i = 0; i < count; ++i) {
      Class class = objc_getClass(classes[i]);
      Class superclass = class;
      do {
        superclass = class_getSuperclass(superclass);
      } while (superclass && (superclass != self));
      if (!superclass || ![class sqlTableName]) {
        continue;
      }
      DatabaseSQLTable table = _RegisterSQLTableFromDatabaseObjectSubclass(class);
      
      table->schemaTable = [[DatabaseSchemaTable alloc] initWithSQLTable:table];
      CFDictionarySetValue(_tableCache, table->class, table);
    }
    free(classes);
  }
}

+ (NSString*) sqlTableName {
  return NSStringFromClass(self);
}

+ (NSArray*) sqlMappedProperties:(NSArray*)properties {
  return [properties sortedArrayUsingSelector:@selector(compare:)];
}

+ (NSString*) sqlColumnNameForProperty:(NSString*)property {
  return property;
}

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  return kDatabaseSQLColumnOptionsNone;
}

+ (NSString*) sqlForeignKeyForProperty:(NSString*)property {
  return nil;
}

+ (NSSet*) sqlPropertyIndices {
  return nil;
}

+ (NSString*) sqlFetchStatement {
  NSString* tableName = [self sqlTableName];
  return [NSString stringWithFormat:@"SELECT %@.* FROM %@", tableName, tableName];
}

+ (NSString*) sqlTableFetchOrder {
  return nil;
}

+ (DatabaseSQLTable) sqlTable {
  return _SQLTableForClass(self);
}

+ (DatabaseSQLColumn) sqlColumnForProperty:(NSString*)property {
  return _SQLColumnForGetter(_SQLTableForClass(self), NSSelectorFromString(property));
}

- (id) init {
  return [self initWithSQLTable:_SQLTableForClass([self class])];
}

- (void) setValue:(id)value forProperty:(NSString*)property {
  DatabaseSQLColumn column = _SQLColumnForGetter(__table, NSSelectorFromString(property));
  CHECK(!value || [value isKindOfClass:column->valueClass]);
  switch (column->columnType) {
    
    case kDatabaseSQLColumnType_Int:
      _SetField_Int(self, column, [(NSNumber*)value intValue]);
      break;
    
    case kDatabaseSQLColumnType_Double:
      _SetField_Double(self, column, [(NSNumber*)value doubleValue]);
      break;
    
    case kDatabaseSQLColumnType_String:
    case kDatabaseSQLColumnType_URL:
    case kDatabaseSQLColumnType_Date:
    case kDatabaseSQLColumnType_Data:
      _SetField_Object(self, column, value);
      break;
    
    default:
      NOT_REACHED();
    
  }
}

- (id) valueForProperty:(NSString*)property {
  DatabaseSQLColumn column = _SQLColumnForGetter(__table, NSSelectorFromString(property));
  switch (column->columnType) {
    
    case kDatabaseSQLColumnType_Int:
      return [NSNumber numberWithInt:_GetField_Int(self, column)];
    
    case kDatabaseSQLColumnType_Double:
      return [NSNumber numberWithDouble:_GetField_Double(self, column)];
    
    case kDatabaseSQLColumnType_String:
    case kDatabaseSQLColumnType_URL:
    case kDatabaseSQLColumnType_Date:
    case kDatabaseSQLColumnType_Data:
      return _GetField_Object(self, column);
    
    default:
      NOT_REACHED();
    
  }
  return nil;
}

@end

@implementation DatabaseObject (SQL)

- (void) setInt:(int)value forSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && (column->columnType == kDatabaseSQLColumnType_Int));
  _SetField_Int(self, column, value);
}

- (void) setDouble:(double)value forSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && (column->columnType == kDatabaseSQLColumnType_Double));
  _SetField_Double(self, column, value);
}

- (void) setObject:(id)object forSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && (!object || [object isKindOfClass:column->valueClass]));
  _SetField_Object(self, column, object);
}

- (int) intForSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && (column->columnType == kDatabaseSQLColumnType_Int));
  return _GetField_Int(self, column);
}

- (double) doubleForSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && (column->columnType == kDatabaseSQLColumnType_Double));
  return _GetField_Double(self, column);
}

- (id) objectForSQLColumn:(DatabaseSQLColumn)column {
  DCHECK(column && COLUMN_TYPE_IS_OBJECT(column->columnType));
  return _GetField_Object(self, column);
}

@end

@implementation DatabaseConnection

@synthesize rawHandle=_database;

+ (void) initialize {
  CHECK(sqlite3_threadsafe());
  
  [DatabaseObject class];
}

static int _CaseInsensitiveUTF8Compare(void* context, int length1, const void* bytes1, int length2, const void* bytes2) {
  CFStringRef string1 = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes1, length1, kCFStringEncodingUTF8, false, kCFAllocatorNull);
  CFStringRef string2 = CFStringCreateWithBytesNoCopy(kCFAllocatorDefault, bytes2, length2, kCFStringEncodingUTF8, false, kCFAllocatorNull);
  CFComparisonResult result = CFStringCompare(string1, string2, kCFCompareCaseInsensitive);
  CFRelease(string2);
  CFRelease(string1);
  return result;
}

static int _OpenDatabase(NSString* path, int flags, sqlite3** database) {
  const char* filename = path ? (path.length ? [path fileSystemRepresentation] : "") : ":memory:";
  int result = sqlite3_open_v2(filename, database, flags | SQLITE_OPEN_NOMUTEX, NULL);  // http://www.sqlite.org/threadsafe.html
  if (result == SQLITE_OK) {
    result = sqlite3_create_collation(*database, "utf8", SQLITE_UTF8, NULL, _CaseInsensitiveUTF8Compare);
  }
  if (result == SQLITE_OK) {
    result = sqlite3_exec(*database, "PRAGMA foreign_keys = ON", NULL, NULL, NULL);
  }
  return result;
}

static int _ExecTableCallback(void* context, int count, char** row, char** columns) {
  DCHECK(count == 2);
  if (row[0] && row[1]) {
    [(NSMutableDictionary*)context setObject:[NSString stringWithUTF8String:row[1]] forKey:[NSString stringWithUTF8String:row[0]]];
  }
  return SQLITE_OK;
}

static int _ExecIndexCallback(void* context, int count, char** row, char** columns) {
  DCHECK(count == 2);
  if (row[0] && row[1]) {
    [(NSMutableDictionary*)context setObject:[NSString stringWithUTF8String:row[1]] forKey:[NSString stringWithUTF8String:row[0]]];
  }
  return SQLITE_OK;
}

static int _InitializeDatabase(sqlite3* database, DatabaseSQLTable* tables, NSUInteger count, NSString* sql) {
  NSMutableDictionary* tableDictionary = [[NSMutableDictionary alloc] init];
  NSMutableDictionary* indexDictionary = [[NSMutableDictionary alloc] init];
  int result = sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION", NULL, NULL, NULL);
  if (result == SQLITE_OK) {
    result = sqlite3_exec(database, "SELECT name,sql FROM sqlite_master WHERE type='table'", _ExecTableCallback, tableDictionary, NULL);
  }
  if (result == SQLITE_OK) {
    result = sqlite3_exec(database, "SELECT name,sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL", _ExecIndexCallback, indexDictionary, NULL);
  }
  if (result == SQLITE_OK) {
    for (NSUInteger i = 0; i < count; ++i) {
      const DatabaseSQLTableDefinition* table = tables[i];
      NSString* string = [tableDictionary objectForKey:table->tableName];
      if (string) {
        if (![string isEqualToString:[NSString stringWithUTF8String:table->sql]]) {
          LOG_ERROR(@"Database is already initialized with incompatible table:\n%@\n%@", string,
                    [NSString stringWithUTF8String:table->sql]);
          result = SQLITE_ERROR;
        }
      } else {
        result = sqlite3_exec(database, table->sql, NULL, NULL, NULL);
      }
      if (result == SQLITE_OK) {
        for (NSArray* properties in table->indices) {
          NSString* name = [[NSString alloc] initWithFormat:@"%@_%@", table->tableName, [properties componentsJoinedByString:@"_"]];
          NSString* string = [indexDictionary objectForKey:name];
          NSString* statement = [[NSString alloc] initWithFormat:@"CREATE INDEX %@ ON %@ (%@)", name, table->tableName,
                                 [properties componentsJoinedByString:@","]];
          if (string) {
            if (![string isEqualToString:statement]) {
              LOG_ERROR(@"Database is already initialized with incompatible index:\n%@\n%@", string, statement);
              result = SQLITE_ERROR;
            }
          } else {
            result = sqlite3_exec(database, [statement UTF8String], NULL, NULL, NULL);
          }
          [statement release];
          [name release];
          if (result != SQLITE_OK) {
            break;
          }
        }
      }
      if (result != SQLITE_OK) {
        break;
      }
    }
    if (sql && (result == SQLITE_OK)) {
      result = sqlite3_exec(database, [sql UTF8String], NULL, NULL, NULL);
    }
    if (result == SQLITE_OK) {
      result = sqlite3_exec(database, "COMMIT TRANSACTION", NULL, NULL, NULL);
    }
  }
  [indexDictionary release];
  [tableDictionary release];
  return result;
}

+ (BOOL) initializeDatabaseAtPath:(NSString*)path
                   usingSQLTables:(DatabaseSQLTable*)tables
                            count:(NSUInteger)count
               extraSQLStatements:(NSString*)sql {
  sqlite3* database = NULL;
  int result = _OpenDatabase(path, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, &database);
  if (result == SQLITE_OK) {
    result = _InitializeDatabase(database, tables, count, sql);
  }
  if (result != SQLITE_OK) {
    LOG_ERROR(@"Failed initializing database at \"%@\": %s (%i)", path, sqlite3_errmsg(database), result);
  }
  if (database) {
    sqlite3_close(database);
  }
  return (result == SQLITE_OK);
}

- (id) init {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (id) initWithDatabaseAtPath:(NSString*)path {
  return [self initWithDatabaseAtPath:path readWrite:YES];
}

static void __ReleaseStatementCallBack(CFAllocatorRef allocator, const void* value) {
  sqlite3_finalize((sqlite3_stmt*)value);
}

- (id) initWithDatabaseAtPath:(NSString*)path readWrite:(BOOL)readWrite {
  if ((self = [super init])) {
    int result = _OpenDatabase(path, readWrite ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY, (sqlite3**)&_database);
    if (result != SQLITE_OK) {
      LOG_ERROR(@"Failed opening database at \"%@\": %s (%i)", path, sqlite3_errmsg(_database), result);
      [self release];
      return nil;
    }
    CFDictionaryValueCallBacks callbacks = {0, NULL, __ReleaseStatementCallBack, NULL, NULL};
    _statements = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, &callbacks);
#ifndef NDEBUG
    _lock = OS_SPINLOCK_INIT;
#endif
  }
  return self;
}

- (void) dealloc {
  if (_statements) {
    CFRelease(_statements);
  }
  if (_database) {
    sqlite3_close(_database);
  }
  
  [super dealloc];
}

static inline int _RetryDelay(int retry) {
  return retry * kBusyRetryDelay + random() % kBusyRetryDelay;
}

static inline int _PrepareStatement(sqlite3* database, const char* sql, sqlite3_stmt** statement, const char** tail) {
  int result;
  for (int retry = 0; retry <= kBusyMaxRetries; ++retry) {
    result = sqlite3_prepare_v2(database, sql, -1, statement, tail);
    if ((result != SQLITE_BUSY) && (result != SQLITE_LOCKED)) {
      break;
    }
    int delay = _RetryDelay(retry);
    LOG_VERBOSE(@"SQLite database is busy: preparing statement again in %i ms (thread = %p | retries = %i)", delay, pthread_self(), retry);
    usleep(delay * 1000);
  }
  return result;
}

static inline int _GetCachedStatement(DatabaseConnection* self, char* sql, sqlite3_stmt** statement) {
  int result;
  *statement = (sqlite3_stmt*)CFDictionaryGetValue(self->_statements, sql);
  if (*statement == NULL) {
    result = _PrepareStatement(self->_database, sql, statement, NULL);
    if (result == SQLITE_OK) {
      CFDictionarySetValue(self->_statements, sql, *statement);
    }
  } else {
    result = SQLITE_OK;
  }
  return result;
}

static inline int _ExecuteStatement(sqlite3_stmt* statement) {
  int result;
  for (int retry = 0; retry <= kBusyMaxRetries; ++retry) {
    result = sqlite3_step(statement);
    if ((result != SQLITE_BUSY) && (result != SQLITE_LOCKED)) {
      break;
    }
    int delay = _RetryDelay(retry);
    LOG_VERBOSE(@"SQLite database is busy: executing statement again in %i ms (thread = %p | retries = %i)", delay, pthread_self(), retry);
    usleep(delay * 1000);
  }
  return result;
}

- (BOOL) setValue:(id)value forPragma:(NSString*)pragma {
  return [self executeRawSQLStatements:[NSString stringWithFormat:@"PRAGMA %@ = %@", pragma, value]];
}

- (id) valueForPragma:(NSString*)pragma {
  NSArray* result = [self executeRawSQLStatement:[NSString stringWithFormat:@"PRAGMA %@", pragma]];
  return result.count == 1 ? [[result objectAtIndex:0] objectForKey:pragma] : nil;
}

- (BOOL) writeUserVersion:(NSUInteger)version {
  return [self setValue:[NSNumber numberWithInteger:version] forPragma:@"user_version"];
}

- (NSUInteger) readUserVersion {
  NSNumber* version = [self valueForPragma:@"user_version"];
  return version ? [version intValue] : NSNotFound;
}

- (BOOL) _addSavepoint {
LOCK_CONNECTION();
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, "SAVEPOINT mark", &statement);
  if (result == SQLITE_OK) {
    result = _ExecuteStatement(statement);
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed adding savepoint in %@: %s (%i)", self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);

UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) beginTransaction {
  return [self _addSavepoint];
}

- (BOOL) _releaseSavepoint:(BOOL)rollback {
LOCK_CONNECTION();
  int result;
  
  if (rollback) {
    sqlite3_stmt* statement;
    result = _GetCachedStatement(self, "ROLLBACK TO mark", &statement);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
    if (result != SQLITE_DONE) {
      LOG_ERROR(@"Failed rolling back savepoint in %@: %s (%i)", self, sqlite3_errmsg(_database), result);
    }
    sqlite3_reset(statement);
  } else {
    result = SQLITE_DONE;
  }
  
  if (result == SQLITE_DONE) {
    sqlite3_stmt* statement;
    result = _GetCachedStatement(self, "RELEASE mark", &statement);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
    if (result != SQLITE_DONE) {
      LOG_ERROR(@"Failed releasing savepoint in %@: %s (%i)", self, sqlite3_errmsg(_database), result);
    }
    sqlite3_reset(statement);
  }
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) commitTransaction {
  return [self _releaseSavepoint:NO];
}

- (BOOL) rollbackTransaction {
  return [self _releaseSavepoint:YES];
}

static int _BindStatementValue(sqlite3_stmt* statement, void* ptr, DatabaseSQLColumn column, unsigned int index) {
  int result = SQLITE_OK;
  switch (column->columnType) {
    
    case kDatabaseSQLColumnType_Int: {
      result = sqlite3_bind_int(statement, index, *((int*)ptr));
      break;
    }
    
    case kDatabaseSQLColumnType_Double: {
      result = sqlite3_bind_double(statement, index, *((double*)ptr));
      break;
    }
    
    case kDatabaseSQLColumnType_String: {
      NSString* string = *((NSString**)ptr);
      if (string) {
        result = sqlite3_bind_text(statement, index, [string UTF8String], -1, SQLITE_STATIC);
      } else {
        result = sqlite3_bind_null(statement, index);
      }
      break;
    }
    
    case kDatabaseSQLColumnType_URL: {
      NSURL* url = *((NSURL**)ptr);
      if (url) {
        result = sqlite3_bind_text(statement, index, [[url absoluteString] UTF8String], -1, SQLITE_STATIC);
      } else {
        result = sqlite3_bind_null(statement, index);
      }
      break;
    }
    
    case kDatabaseSQLColumnType_Date: {
      NSDate* date = *((NSDate**)ptr);
      if (date) {
        result = sqlite3_bind_double(statement, index, [date timeIntervalSinceReferenceDate]);
      } else {
        result = sqlite3_bind_null(statement, index);
      }
      break;
    }
    
    case kDatabaseSQLColumnType_Data: {
      NSData* data = *((NSData**)ptr);
      if (data) {
        result = sqlite3_bind_blob(statement, index, data.bytes, (int)data.length, SQLITE_STATIC);  // Equivalent to sqlite3_bind_null() for zero-length
      } else {
        result = sqlite3_bind_null(statement, index);
      }
      break;
    }
    
    default:
      NOT_REACHED();
      break;
      
  }
  return result;
}

static int _BindStatementBoxedValue(sqlite3_stmt* statement, id value, DatabaseSQLColumn column, unsigned int index) {
  CHECK(!value || [value isKindOfClass:column->valueClass]);
  ScalarValue scalar;
  void* valuePtr;
  switch (column->columnType) {
    
    case kDatabaseSQLColumnType_Int:
      scalar._int = [(NSNumber*)value intValue];
      valuePtr = &scalar;
      break;
      
    case kDatabaseSQLColumnType_Double:
      scalar._double = [(NSNumber*)value doubleValue];
      valuePtr = &scalar;
      break;
      
    default:
      valuePtr = &value;
      break;
    
  }
  return _BindStatementValue(statement, valuePtr, column, index);
}

static inline int _BindStatementValues(sqlite3_stmt* statement, void* storage, DatabaseSQLTable table, unsigned int offset) {
  int result = SQLITE_OK;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if (table->columnList[i].setter) {
      result = _BindStatementValue(statement, (char*)storage + table->columnList[i].offset, &table->columnList[i], i + offset);
      if (result != SQLITE_OK) {
        break;
      }
    }
  }
  return result;
}

static void _CopyRowValues(sqlite3_stmt* statement, void* storage, DatabaseSQLTable table, unsigned int offset) {
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    void* ptr = (char*)storage + table->columnList[i].offset;
    switch (table->columnList[i].columnType) {
      
      case kDatabaseSQLColumnType_Int: {
        *((int*)ptr) = sqlite3_column_int(statement, i + offset);
        break;
      }
      
      case kDatabaseSQLColumnType_Double: {
        *((double*)ptr) = sqlite3_column_double(statement, i + offset);
        break;
      }
      
      case kDatabaseSQLColumnType_String: {
        const unsigned char* text = sqlite3_column_text(statement, i + offset);
        if (text) {
          NSString* string = [NSString stringWithUTF8String:(const char*)text];
          if (string != *((NSString**)ptr)) {
            [*((NSString**)ptr) release];  // TODO: Should we autorelease?
            *((NSString**)ptr) = [string copy];
          }
        } else {
          [*((NSString**)ptr) release];
          *((NSString**)ptr) = nil;
        }
        break;
      }
      
      case kDatabaseSQLColumnType_URL: {
        const unsigned char* text = sqlite3_column_text(statement, i + offset);
        if (text) {
          NSURL* url = [NSURL URLWithString:[NSString stringWithUTF8String:(const char*)text]];
          if (url != *((NSURL**)ptr)) {
            [*((NSURL**)ptr) release];  // TODO: Should we autorelease?
            *((NSURL**)ptr) = [url copy];
          }
        } else {
          [*((NSURL**)ptr) release];  // TODO: Should we autorelease?
          *((NSURL**)ptr) = nil;
        }
        break;
      }
      
      case kDatabaseSQLColumnType_Date: {
        int type = sqlite3_column_type(statement, i + offset);
        double time = type != SQLITE_NULL ? sqlite3_column_double(statement, i + offset) : kCFAbsoluteTimeIntervalSince1904;  // Backward compatibility with the fact we used to store nil dates as kCFAbsoluteTimeIntervalSince1904
        if (time != kCFAbsoluteTimeIntervalSince1904) {
          NSDate* date = [NSDate dateWithTimeIntervalSinceReferenceDate:time];
          if (date != *((NSDate**)ptr)) {
            [*((NSDate**)ptr) release];  // TODO: Should we autorelease?
            *((NSDate**)ptr) = [date copy];
          }
        } else {
          [*((NSDate**)ptr) release];  // TODO: Should we autorelease?
          *((NSDate**)ptr) = nil;
        }
        break;
      }
      
      case kDatabaseSQLColumnType_Data: {
        const void* bytes = sqlite3_column_blob(statement, i + offset);
        if (bytes) {
          int length = sqlite3_column_bytes(statement, i + offset);
          NSData* data = [NSData dataWithBytes:bytes length:length];
          if (data != *((NSData**)ptr)) {
            [*((NSData**)ptr) release];  // TODO: Should we autorelease?
            *((NSData**)ptr) = [data copy];
          }
        } else {
          [*((NSData**)ptr) release];
          *((NSData**)ptr) = nil;
        }
        break;
      }
      
      default:
        NOT_REACHED();
        break;
      
    }
  }
}

// Assumes connection lock is taken
- (int) _executeSelectStatement:(sqlite3_stmt*)statement withSQLTable:(DatabaseSQLTable)table results:(NSMutableArray*)results {
  int result;
  while (1) {
    result = _ExecuteStatement(statement);
    if (result != SQLITE_ROW) {
      break;
    }
    DatabaseObject* object = [[table->class alloc] initWithSQLTable:table];
    object.sqlRowID = sqlite3_column_int(statement, 0);
    _CopyRowValues(statement, object._storage, table, 1);
    [results addObject:object];
    [object release];
  }
  return result;
}

- (BOOL) refetchObject:(DatabaseObject*)object {
LOCK_CONNECTION();
  CHECK(object.sqlRowID);
  DatabaseSQLTable table = object.sqlTable;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_SelectWithRowID], &statement);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_int(statement, 1, object.sqlRowID);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    DCHECK(object.sqlRowID == sqlite3_column_int(statement, 0));
    _CopyRowValues(statement, object._storage, table, 1);
    [object clearModified];
  } else if (result == SQLITE_DONE) {
    object.sqlRowID = 0;
  } else {
    LOG_ERROR(@"Failed refetching %@ from %@: %s (%i)", [object miniDescription], self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_ROW);
}

- (BOOL) insertObject:(DatabaseObject*)object {
LOCK_CONNECTION();
  CHECK(object && !object.sqlRowID);
  DatabaseSQLTable table = object.sqlTable;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_Insert], &statement);
  if (result == SQLITE_OK) {
    result = _BindStatementValues(statement, object._storage, table, 1);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_DONE) {
    object.sqlRowID = (DatabaseSQLRowID)sqlite3_last_insert_rowid(_database);
    [object clearModified];
  } else {
    LOG_ERROR(@"Failed inserting %@ into %@: %s (%i)", [object miniDescription], self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) replaceObject:(DatabaseObject*)object {
LOCK_CONNECTION();
  CHECK(object && !object.sqlRowID);
  DatabaseSQLTable table = object.sqlTable;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_Replace], &statement);
  if (result == SQLITE_OK) {
    result = _BindStatementValues(statement, object._storage, table, 1);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_DONE) {
    object.sqlRowID = (DatabaseSQLRowID)sqlite3_last_insert_rowid(_database);
    [object clearModified];
  } else {
    LOG_ERROR(@"Failed replacing %@ into %@: %s (%i)", [object miniDescription], self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) updateObject:(DatabaseObject*)object {
LOCK_CONNECTION();
  CHECK(object.sqlRowID);
  DatabaseSQLTable table = object.sqlTable;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_UpdateWithRowID], &statement);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_int(statement, 1, object.sqlRowID);
    if (result == SQLITE_OK) {
      result = _BindStatementValues(statement, object._storage, table, 2);
      if (result == SQLITE_OK) {
        result = _ExecuteStatement(statement);
      }
    }
  }
  if (result == SQLITE_DONE) {
    [object clearModified];
  } else {
    LOG_ERROR(@"Failed updating %@ into %@: %s (%i)", [object miniDescription], self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) updateObject:(DatabaseObject*)object usingSQLRowID:(DatabaseSQLRowID)rowID {
  CHECK(object && !object.sqlRowID);
  CHECK(rowID);
  object.sqlRowID = rowID;
  BOOL success = [self updateObject:object];
  if (success == NO) {
    object.sqlRowID = 0;
  }
  return success;
}

- (BOOL) _deleteObjectWithSQLTable:(DatabaseSQLTable)table rowID:(DatabaseSQLRowID)rowID {
LOCK_CONNECTION();
  CHECK(rowID);
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_DeleteWithRowID], &statement);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_int(statement, 1, rowID);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed deleting %@ object with SQL row ID (%i) from %@: %s (%i)", table->class, rowID, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);

UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) deleteObject:(DatabaseObject*)object {
  CHECK(object.sqlRowID);
  if (![self _deleteObjectWithSQLTable:object.sqlTable rowID:object.sqlRowID]) {
    return NO;
  }
  object.sqlRowID = 0;
  return YES;
}

- (BOOL) vacuum {
  return [self executeRawSQLStatements:@"VACUUM"];
}

- (NSArray*) executeRawSQLStatement:(NSString*)sql {
  return [self executeRawSQLStatement:sql usingRowClass:[NSMutableDictionary class] primaryKey:nil];
}

- (id) executeRawSQLStatement:(NSString*)sql usingRowClass:(Class)class primaryKey:(NSString*)key {
LOCK_CONNECTION();
  CHECK(sql);
  id results = nil;
  
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [sql UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    const char* utf8Key = [key UTF8String];
    if (utf8Key) {
      results = [NSMutableDictionary dictionary];
    } else {
      results = [NSMutableArray array];
    }
    while (1) {
      result = _ExecuteStatement(statement);
      if (result != SQLITE_ROW) {
        break;
      }
      id row = class ? [[class alloc] init] : [NSNull null];
      id primary = nil;
      int count = sqlite3_column_count(statement);
      for (int i = 0; i < count; ++i) {
        id object = nil;
        switch (sqlite3_column_type(statement, i)) {
          
#if 0
          case SQLITE_NULL: {
            object = [NSNull null];
            break;
          }
#endif
          
          case SQLITE_INTEGER: {
            object = [[NSNumber alloc] initWithInt:sqlite3_column_int(statement, i)];
            break;
          }
          
          case SQLITE_FLOAT: {
            object = [[NSNumber alloc] initWithDouble:sqlite3_column_double(statement, i)];
            break;
          }
          
          case SQLITE_TEXT: {
            const unsigned char* text = sqlite3_column_text(statement, i);
            if (text) {
              object = [[NSString alloc] initWithCString:(const char*)text encoding:NSUTF8StringEncoding];
            }
            break;
          }
          
          case SQLITE_BLOB: {
            const void* bytes = sqlite3_column_blob(statement, i);
            if (bytes) {
              int length = sqlite3_column_bytes(statement, i);
              object = [[NSData alloc] initWithBytes:bytes length:length];
            }
            break;
          }
          
        }
        const char* columnName = sqlite3_column_name(statement, i);
        if (utf8Key && !strcmp(utf8Key, columnName)) {
          primary = [object retain];
        } else if (class) {
          [row setValue:object forKey:[NSString stringWithUTF8String:sqlite3_column_name(statement, i)]];
        } else {
          [row release];
          row = [object retain];
        }
        [object release];
      }
      if (utf8Key) {
        if (primary) {
          [results setValue:row forKey:primary];
          [primary release];
        }
      } else {
        [results addObject:row];
      }
      [row release];
    }
    if (result != SQLITE_DONE) {
      LOG_ERROR(@"Failed executing raw SQL statement \"%@\": %s (%i)", sql, sqlite3_errmsg(_database), result);
    }
    sqlite3_finalize(statement);
  } else {
    LOG_ERROR(@"Failed preparing raw SQL statement \"%@\": %s (%i)", sql, sqlite3_errmsg(_database), result);
  }
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE ? results : nil);
}

- (BOOL) executeRawSQLStatements:(NSString*)sql {
LOCK_CONNECTION();
  CHECK(sql);
  
  const char* zSql = [sql UTF8String];
  int result = SQLITE_DONE;
  while (zSql[0]) {
    sqlite3_stmt* statement = NULL;
    const char* tail = NULL;
    result = _PrepareStatement(_database, zSql, &statement, &tail);
    if (result == SQLITE_OK) {
      do {
        result = _ExecuteStatement(statement);
      } while (result == SQLITE_ROW);
      sqlite3_finalize(statement);
      if (result != SQLITE_DONE) {
        LOG_ERROR(@"Failed executing raw SQL statements \"%@\": %s (%i)", sql, sqlite3_errmsg(_database), result);
        break;
      }
      zSql = tail;
    } else {
      LOG_ERROR(@"Failed preparing raw SQL statements \"%@\": %s (%i)", sql, sqlite3_errmsg(_database), result);
      break;
    }
  }
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) backupToDatabaseAtPath:(NSString*)path {
LOCK_CONNECTION();
  
  sqlite3* database = NULL;
  int result = _OpenDatabase(path, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, &database);
  if (result == SQLITE_OK) {
    sqlite3_backup* backup = sqlite3_backup_init(database, "main", _database, "main");
    if (backup) {
      sqlite3_backup_step(backup, -1);
      sqlite3_backup_finish(backup);
      result = sqlite3_errcode(database);
    }
    if (result != SQLITE_OK) {
      LOG_ERROR(@"Failed performing backup to database \"%@\": %s (%i)", path, sqlite3_errmsg(database), sqlite3_errcode(database));
    }
  } else {
    LOG_ERROR(@"Failed opening database at \"%@\": %s (%i)", path, sqlite3_errmsg(database), result);
  }
  if (database) {
    sqlite3_close(database);
  }
  
UNLOCK_CONNECTION();
  return (result == SQLITE_OK);
}

- (BOOL) restoreFromDatabaseAtPath:(NSString*)path {
  LOCK_CONNECTION();
  
  sqlite3* database = NULL;
  int result = _OpenDatabase(path, SQLITE_OPEN_READONLY, &database);
  if (result == SQLITE_OK) {
    sqlite3_backup* backup = sqlite3_backup_init(_database, "main", database, "main");
    if (backup) {
      sqlite3_backup_step(backup, -1);
      sqlite3_backup_finish(backup);
      result = sqlite3_errcode(_database);
    }
    if (result != SQLITE_OK) {
      LOG_ERROR(@"Failed performing restore from database \"%@\": %s (%i)", path, sqlite3_errmsg(database), sqlite3_errcode(database));
    }
  } else {
    LOG_ERROR(@"Failed opening database at \"%@\": %s (%i)", path, sqlite3_errmsg(database), result);
  }
  if (database) {
    sqlite3_close(database);
  }
  
  UNLOCK_CONNECTION();
  return (result == SQLITE_OK);
}

- (NSString*) description {
  return [super smartDescription];
}

@end

@implementation DatabaseConnection (ObjCBridge)

+ (NSString*) defaultDatabasePath {
  static NSString* databasePath = nil;
  if (databasePath == nil) {
#if TARGET_OS_IPHONE
    NSString* documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    CHECK(documentsPath);
#else
    NSString* documentsPath = [[NSFileManager defaultManager] currentDirectoryPath];
#endif
    databasePath = [[documentsPath stringByAppendingPathComponent:@"Database.db"] retain];
  }
  return databasePath;
}

+ (DatabaseConnection*) defaultDatabaseConnection {
  static DatabaseConnection* connection = nil;
  if (connection == nil) {
    if ([self initializeDatabaseAtPath:[DatabaseConnection defaultDatabasePath]]) {
      connection = [[DatabaseConnection alloc] initWithDatabaseAtPath:[DatabaseConnection defaultDatabasePath]];
    }
  }
  return connection;
}

+ (BOOL) initializeDatabaseAtPath:(NSString*)path {
  return [self initializeDatabaseAtPath:path usingObjectClasses:nil extraSQLStatements:nil];
}

+ (BOOL) initializeDatabaseAtPath:(NSString*)path usingObjectClasses:(NSSet*)classes extraSQLStatements:(NSString*)sql {
  NSUInteger count = CFDictionaryGetCount(_tableCache);
  DatabaseSQLTable values[count];
  CFDictionaryGetKeysAndValues(_tableCache, NULL, (const void**)values);
  DatabaseSQLTable tables[count];
  NSUInteger index = 0;
  for (NSUInteger i = 0; i < count; ++i) {
    if (!classes || [classes containsObject:values[i]->class]) {
      tables[index++] = values[i];
    }
  }
  return [self initializeDatabaseAtPath:path usingSQLTables:tables count:index extraSQLStatements:sql];
}

- (BOOL) hasObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID {
  return [self hasObjectInSQLTable:_SQLTableForClass(class) withSQLRowID:rowID];
}

- (id) fetchObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID {
  return [self fetchObjectInSQLTable:_SQLTableForClass(class) withSQLRowID:rowID];
}

- (DatabaseSQLRowID) hasObjectOfClass:(Class)class withUniqueProperty:(NSString*)property matchingValue:(id)value {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column && (column->columnOptions & kDatabaseSQLColumnOption_Unique));
  return [self hasObjectInSQLTable:table withUniqueSQLColumn:column matchingValue:value];
}

- (id) fetchObjectOfClass:(Class)class withUniqueProperty:(NSString*)property matchingValue:(id)value {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column && (column->columnOptions & kDatabaseSQLColumnOption_Unique));
  return [self fetchObjectInSQLTable:table withUniqueSQLColumn:column matchingValue:value];
}

- (NSArray*) fetchObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column);
  return [self fetchObjectsInSQLTable:table withSQLColumn:column matchingValue:value];
}

- (id) fetchObjectsOfClass:(Class)class
              withProperty:(NSString*)property
            matchingValues:(NSArray*)values
       extraSQLWhereClause:(NSString*)clause
                     limit:(NSUInteger)limit {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column);
  return [self fetchObjectsInSQLTable:table withSQLColumn:column matchingValues:values extraSQLWhereClause:clause limit:limit];
}

- (NSArray*) fetchObjectsOfClass:(Class)class withSQLWhereClause:(NSString*)clause limit:(NSUInteger)limit {
  return [self fetchObjectsInSQLTable:_SQLTableForClass(class) withSQLWhereClause:clause limit:limit];
}

- (NSArray*) fetchObjectsOfClass:(Class)class
           joiningObjectsOfClass:(Class)joinClass
                      onProperty:(NSString*)joinProperty
              withSQLWhereClause:(NSString*)clause
                           limit:(NSUInteger)limit {
  DatabaseSQLTable table = _SQLTableForClass(class);
  CHECK(table);
  DatabaseSQLTable joinTable = _SQLTableForClass(joinClass);
  DatabaseSQLColumn joinColumn = NULL;
  for (unsigned int i = 0; i < joinTable->columnCount; ++i) {
    if ([joinProperty isEqualToString:joinTable->columnList[i].name]) {
      joinColumn = &joinTable->columnList[i];
      break;
    }
  }
  CHECK(joinColumn);
  return [self fetchObjectsInSQLTable:table joiningSQLTable:joinTable onSQLColumn:joinColumn withSQLWhereClause:clause limit:limit];
}

- (NSArray*) fetchObjectsOfClass:(Class)class withSQL:(NSString*)sql {
  return [self fetchObjectsInSQLTable:_SQLTableForClass(class) withSQL:sql];
}

- (NSUInteger) countObjectsOfClass:(Class)class {
  return [self countObjectsInSQLTable:_SQLTableForClass(class)];
}

- (NSUInteger) countObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column);
  return [self countObjectsInSQLTable:table withSQLColumn:column matchingValue:value];
}

- (NSArray*) fetchAllObjectsOfClass:(Class)class {
  return [self fetchAllObjectsInSQLTable:_SQLTableForClass(class)];
}

- (BOOL) deleteAllObjectsOfClass:(Class)class {
  return [self deleteAllObjectsInSQLTable:_SQLTableForClass(class)];
}

- (BOOL) deleteObjectOfClass:(Class)class withSQLRowID:(DatabaseSQLRowID)rowID {
  return [self deleteObjectInSQLTable:_SQLTableForClass(class) withSQLRowID:rowID];
}

- (BOOL) deleteObjectsOfClass:(Class)class withProperty:(NSString*)property matchingValue:(id)value {
  DatabaseSQLTable table = _SQLTableForClass(class);
  DatabaseSQLColumn column = NULL;
  for (unsigned int i = 0; i < table->columnCount; ++i) {
    if ([property isEqualToString:table->columnList[i].name]) {
      column = &table->columnList[i];
      break;
    }
  }
  CHECK(column);
  return [self deleteObjectsInSQLTable:table withSQLColumn:column matchingValue:value];
}

- (BOOL) deleteObjectsOfClass:(Class)class withSQLWhereClause:(NSString*)clause {
  return [self deleteObjectsInSQLTable:_SQLTableForClass(class) withSQLWhereClause:clause];
}

@end

@implementation DatabaseSchemaColumn

@synthesize name=_name, type=_type, options=_options, sqlColumn=_column;

- (id) initWithSQLColumn:(DatabaseSQLColumn)column {
  if ((self = [super init])) {
    _name = [column->columnName retain];
    _type = column->columnType;
    _options = column->columnOptions;
    _column = column;
  }
  return self;
}

- (id) initWithName:(NSString*)name type:(DatabaseSQLColumnType)type options:(DatabaseSQLColumnOptions)options {
  CHECK(name.length);
  CHECK(COLUMN_TYPE_IS_SCALAR(type) || COLUMN_TYPE_IS_OBJECT(type));
  if ((self = [super init])) {
    _name = [name copy];
    _type = type;
    _options = options;
  }
  return self;
}

- (void) dealloc {
  [_name release];
  
  [super dealloc];
}

- (NSString*) description {
  return [self smartDescription];
}

@end

@implementation DatabaseSchemaTable

@synthesize name=_name, fetchStatement=_statement, fetchOrder=_order, columns=_columns, objectClass=_class, sqlTable=_table;

+ (DatabaseSchemaTable*) schemaTableFromObjectClass:(Class)class {
  return _SQLTableForClass(class)->schemaTable;
}

- (id) initWithSQLTable:(DatabaseSQLTable)table {
  DCHECK(table->class != [DatabaseObject class]);
  if ((self = [super init])) {
    _name = [table->tableName retain];
    _order = [table->fetchOrder retain];
    _columns = [[NSMutableArray alloc] init];
    for (unsigned int i = 0; i < table->columnCount; ++i) {
      DatabaseSchemaColumn* column = [[DatabaseSchemaColumn alloc] initWithSQLColumn:&table->columnList[i]];
      [(NSMutableArray*)_columns addObject:column];
      [column release];
    }
    
    _class = table->class;
    _table = table;
  }
  return self;
}

- (id) initWithName:(NSString*)name fetchStatement:(NSString*)statement fetchOrder:(NSString*)order columns:(NSArray*)columns {
  return [self initWithObjectClass:[DatabaseObject class] name:name fetchStatement:statement fetchOrder:order extraColumns:columns];
}

- (id) initWithObjectClass:(Class)class name:(NSString*)name fetchStatement:(NSString*)statement fetchOrder:(NSString*)order extraColumns:(NSArray*)columns {
  CHECK([class isSubclassOfClass:[DatabaseObject class]]);
  CHECK(name.length);
  CHECK(columns.count);
  if ((self = [super init])) {
    DatabaseSQLTable baseTable = class != [DatabaseObject class] ? _SQLTableForClass(class) : NULL;
    
    _name = [name copy];
    _statement = [statement copy];
    _order = [order copy];
    _columns = [[NSMutableArray alloc] init];
    
    _class = class;
    _table = calloc(1, sizeof(DatabaseSQLTableDefinition));
    _table->class = class;
    _table->tableName = [_name retain];
    _table->fetchStatement = [_statement retain];
    _table->fetchOrder = [_order retain];
    _table->columnCount = 0;
    _table->columnList = malloc(((baseTable ? baseTable->columnCount : 0) + columns.count) * sizeof(DatabaseSQLColumnDefinition));
    if (baseTable) {
      for (unsigned int i = 0; i < baseTable->columnCount; ++i) {
        DatabaseSQLColumn iColumn = &baseTable->columnList[i];
        DatabaseSQLColumn sqlColumn = &_table->columnList[_table->columnCount];
        sqlColumn->name = [iColumn->name retain];
        sqlColumn->columnType = iColumn->columnType;
        sqlColumn->columnName = [iColumn->columnName retain];
        sqlColumn->columnOptions = iColumn->columnOptions;
        sqlColumn->columnForeignKey = [iColumn->columnForeignKey retain];
        sqlColumn->getter = iColumn->getter;
        sqlColumn->setter = iColumn->setter;
        
        DatabaseSchemaColumn* column = [[DatabaseSchemaColumn alloc] initWithSQLColumn:sqlColumn];
        [_columns addObject:column];
        [column release];
        
        _table->columnCount += 1;
      }
    }
    for (DatabaseSchemaColumn* column in columns) {
      CHECK(column.sqlColumn == NULL);
      DatabaseSQLColumn sqlColumn = &_table->columnList[_table->columnCount];
      sqlColumn->name = [column.name retain];
      sqlColumn->columnType = column.type;
      sqlColumn->columnName = [column.name retain];
      sqlColumn->columnOptions = column.options;
      sqlColumn->columnForeignKey = nil;
      sqlColumn->getter = sel_registerName([sqlColumn->name UTF8String]);
      sqlColumn->setter = sel_registerName([[NSString stringWithFormat:@"set%@%@:", [[sqlColumn->name substringToIndex:1] uppercaseString],
                                                                       [sqlColumn->name substringFromIndex:1]] UTF8String]);
      column.sqlColumn = sqlColumn;
      [_columns addObject:column];
      
      _table->columnCount += 1;
    }
    _InitializeSQLTable(_table);
  }
  return self;
}

- (void) dealloc {
  [_name release];
  [_statement release];
  [_order release];
  [_columns release];
  
  if (_table) {
    DCHECK(_table->schemaTable == NULL);
    _FinalizeSQLTable(_table);
  }
  
  [super dealloc];
}

- (NSString*) description {
  return [self smartDescription];
}

@end

@implementation DatabaseConnection (SQL)

+ (BOOL) initializeDatabaseAtPath:(NSString*)path usingSchema:(NSSet*)schema extraSQLStatements:(NSString*)sql {
  DatabaseSQLTable tables[schema.count];
  NSUInteger index = 0;
  for (DatabaseSchemaTable* table in schema) {
    tables[index++] = table.sqlTable;
  }
  return [self initializeDatabaseAtPath:path usingSQLTables:tables count:index extraSQLStatements:sql];
}

- (BOOL) hasObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID {
LOCK_CONNECTION();
  CHECK(rowID > 0);
  BOOL exists = NO;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_SelectExistsWithRowID], &statement);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_int(statement, 1, rowID);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    if (sqlite3_column_int(statement, 0)) {
      exists = YES;
    }
  } else if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ object with rowID '%i' from %@: %s (%i)", table->class, rowID, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);

UNLOCK_CONNECTION();
  return exists;
}

- (id) fetchObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID {
LOCK_CONNECTION();
  CHECK(rowID > 0);
  DatabaseObject* object = nil;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_SelectWithRowID], &statement);
  if (result == SQLITE_OK) {
    result = sqlite3_bind_int(statement, 1, rowID);
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    object = [[[table->class alloc] initWithSQLTable:table] autorelease];
    object.sqlRowID = sqlite3_column_int(statement, 0);  // rowID
    _CopyRowValues(statement, object._storage, table, 1);
  } else if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ object with rowID '%i' from %@: %s (%i)", table->class, rowID, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);

UNLOCK_CONNECTION();
  return object;
}

- (DatabaseSQLRowID) hasObjectInSQLTable:(DatabaseSQLTable)table withUniqueSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value {
LOCK_CONNECTION();
  DatabaseSQLRowID rowID = 0;
  CHECK(value);
  
  NSString* string = value ? [NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE %@=?1", kDatabaseColumnName_RowID, table->tableName, column->columnName]
                           : [NSString stringWithFormat:@"SELECT %@ FROM %@ WHERE %@ IS NULL", kDatabaseColumnName_RowID, table->tableName, column->columnName];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = value ? _BindStatementBoxedValue(statement, value, column, 1) : SQLITE_OK;
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    rowID = sqlite3_column_int(statement, 0);
  } else if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ object with unique property '%@' matching '%@' from %@: %s (%i)", table->class, column->name,
              value, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return rowID;
}

- (id) fetchObjectInSQLTable:(DatabaseSQLTable)table withUniqueSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value {
LOCK_CONNECTION();
  DatabaseObject* object = nil;
  CHECK(value);
  
  NSString* string = value ? [NSString stringWithFormat:@"%@ WHERE %@=?1", table->fetchStatement, column->columnName]
                           : [NSString stringWithFormat:@"%@ WHERE %@ IS NULL", table->fetchStatement, column->columnName];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = value ? _BindStatementBoxedValue(statement, value, column, 1) : SQLITE_OK;
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    object = [[[table->class alloc] initWithSQLTable:table] autorelease];
    object.sqlRowID = sqlite3_column_int(statement, 0);  // rowID
    _CopyRowValues(statement, object._storage, table, 1);
  } else if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ object with unique property '%@' matching '%@' from %@: %s (%i)", table->class, column->name,
              value, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return object;
}

- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table
                      withSQLColumn:(DatabaseSQLColumn)column
                     matchingValues:(NSArray*)values
                extraSQLWhereClause:(NSString*)clause
                              limit:(NSUInteger)limit {
LOCK_CONNECTION();
  NSUInteger count = values.count;
  NSMutableArray* results = [NSMutableArray array];
  
  NSMutableString* list = [[NSMutableString alloc] init];
  for (NSUInteger i = 0 ; i < count; ++i) {
    if (i == 0) {
      [list appendString:@"?1"];
    } else {
      [list appendFormat:@", ?%i", (int)(i + 1)];
    }
  }
  NSMutableString* string = [NSMutableString stringWithFormat:@"%@ WHERE %@ IN (%@)", table->fetchStatement, column->columnName, list];
  [list release];
  if (clause) {
    [string appendFormat:@" AND %@", clause];
  }
  if (table->fetchOrder) {
    [string appendFormat:@" ORDER BY %@", table->fetchOrder];
  }
  if (limit > 0) {
    [string appendFormat:@" LIMIT %i", (int)limit];
  }
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    for (unsigned int i = 0 ; i < count; ++i) {
      result = _BindStatementBoxedValue(statement, [values objectAtIndex:i], column, i + 1);
      if (result != SQLITE_OK) {
        break;
      }
    }
    if (result == SQLITE_OK) {
      result = [self _executeSelectStatement:statement withSQLTable:table results:results];
    }
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ objects with property '%@' matching %@ from %@: %s (%i)", table->class, column->name,
              values, self, sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return results;
}

- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value {
LOCK_CONNECTION();
  NSMutableArray* results = [NSMutableArray array];
  
  NSMutableString* string = value ? [NSMutableString stringWithFormat:@"%@ WHERE %@=?1", table->fetchStatement, column->columnName]
                                  : [NSMutableString stringWithFormat:@"%@ WHERE %@ IS NULL", table->fetchStatement, column->columnName];
  if (table->fetchOrder) {
    [string appendFormat:@" ORDER BY %@", table->fetchOrder];
  }
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = value ? _BindStatementBoxedValue(statement, value, column, 1) : SQLITE_OK;
    if (result == SQLITE_OK) {
      result = [self _executeSelectStatement:statement withSQLTable:table results:results];
    }
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ objects with property '%@' matching '%@' from %@: %s (%i)", table->class, column->name,
              value, self, sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return results;
}

- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table withSQLWhereClause:(NSString*)clause limit:(NSUInteger)limit {
LOCK_CONNECTION();
  CHECK(clause);
  NSMutableArray* results = [NSMutableArray array];
  
  NSMutableString* string = [NSMutableString stringWithFormat:@"%@ WHERE %@", table->fetchStatement, clause];
  if (table->fetchOrder) {
    [string appendFormat:@" ORDER BY %@", table->fetchOrder];
  }
  if (limit > 0) {
    [string appendFormat:@" LIMIT %i", (int)limit];
  }
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = [self _executeSelectStatement:statement withSQLTable:table results:results];
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ objects with SQL where clause \"%@\" from %@: %s (%i)", table->class, clause, self,
              sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return results;
}

- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table
                    joiningSQLTable:(DatabaseSQLTable)joinTable
                        onSQLColumn:(DatabaseSQLColumn)joinColumn
                 withSQLWhereClause:(NSString*)clause
                              limit:(NSUInteger)limit {
LOCK_CONNECTION();
  NSMutableArray* results = [NSMutableArray array];
  
  NSMutableString* string = [NSMutableString stringWithFormat:@"%@ JOIN %@ ON %@.%@=%@.%@", table->fetchStatement, joinTable->tableName,
                                                              joinTable->tableName, joinColumn->columnName, table->tableName, kDatabaseColumnName_RowID];
  if (clause) {
    [string appendFormat:@" WHERE %@", clause];
  }
  if (table->fetchOrder) {
    [string appendFormat:@" ORDER BY %@", table->fetchOrder];
  }
  if (limit > 0) {
    [string appendFormat:@" LIMIT %i", (int)limit];
  }
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = [self _executeSelectStatement:statement withSQLTable:table results:results];
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ objects joined with %@ objects on property '%@' from %@: %s (%i)", table->class,
              joinTable->class, joinColumn->name, self, sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return results;
}

- (NSArray*) fetchObjectsInSQLTable:(DatabaseSQLTable)table withSQL:(NSString*)sql {
  LOCK_CONNECTION();
  CHECK(sql);
  NSMutableArray* results = [NSMutableArray array];
  
  NSString* string = [NSString stringWithFormat:@"%@ %@", table->fetchStatement, sql];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = [self _executeSelectStatement:statement withSQLTable:table results:results];
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching %@ objects with SQL \"%@\" from %@: %s (%i)", table->class, sql, self,
              sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_finalize(statement);
  
  UNLOCK_CONNECTION();
  return results;
}

- (NSUInteger) countObjectsInSQLTable:(DatabaseSQLTable)table {
LOCK_CONNECTION();
  NSUInteger count = 0;
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_CountAll], &statement);
  if (result == SQLITE_OK) {
    result = _ExecuteStatement(statement);
  }
  if (result == SQLITE_ROW) {
    count = sqlite3_column_int(statement, 0);
  } else {
    LOG_ERROR(@"Failed counting all %@ objects in %@: %s (%i)", table->class, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return count;
}

- (NSUInteger) countObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value {
LOCK_CONNECTION();
  NSUInteger count = 0;
  
  NSString* string = value ? [NSString stringWithFormat:@"SELECT Count(*) FROM %@ WHERE %@=?1", table->tableName,
                                                        column->columnName]
                           : [NSString stringWithFormat:@"SELECT Count(*) FROM %@ WHERE %@ IS NULL", table->tableName,
                                                        column->columnName];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = value ? _BindStatementBoxedValue(statement, value, column, 1) : SQLITE_OK;
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result == SQLITE_ROW) {
    count = sqlite3_column_int(statement, 0);
  } else {
    LOG_ERROR(@"Failed counting %@ objects with property '%@' matching '%@' from %@: %s (%i)", table->class, column->name,
              value, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return count;
}

- (NSArray*) fetchAllObjectsInSQLTable:(DatabaseSQLTable)table {
LOCK_CONNECTION();
  NSMutableArray* results = [NSMutableArray array];
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_SelectAll], &statement);
  if (result == SQLITE_OK) {
    result = [self _executeSelectStatement:statement withSQLTable:table results:results];
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed fetching all %@ objects from %@: %s (%i)", table->class, self, sqlite3_errmsg(_database), result);
    results = nil;
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);
  
UNLOCK_CONNECTION();
  return results;
}

- (BOOL) deleteAllObjectsInSQLTable:(DatabaseSQLTable)table {
LOCK_CONNECTION();
  
  sqlite3_stmt* statement;
  int result = _GetCachedStatement(self, table->statements[kObjectStatement_DeleteAll], &statement);
  if (result == SQLITE_OK) {
    result = _ExecuteStatement(statement);
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed deleting all %@ objects from %@: %s (%i)", table->class, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_reset(statement);
  sqlite3_clear_bindings(statement);

UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) deleteObjectInSQLTable:(DatabaseSQLTable)table withSQLRowID:(DatabaseSQLRowID)rowID {
  CHECK(rowID > 0);
  return [self _deleteObjectWithSQLTable:table rowID:rowID];
}

- (BOOL) deleteObjectsInSQLTable:(DatabaseSQLTable)table withSQLColumn:(DatabaseSQLColumn)column matchingValue:(id)value {
LOCK_CONNECTION();

  NSString* string = value ? [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@=?1", table->tableName,
                                                        column->columnName]
                           : [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ IS NULL", table->tableName,
                                                        column->columnName];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = value ? _BindStatementBoxedValue(statement, value, column, 1) : SQLITE_OK;
    if (result == SQLITE_OK) {
      result = _ExecuteStatement(statement);
    }
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed deleting %@ objects with property '%@' matching '%@' from %@: %s (%i)", table->class, column->name,
              value, self, sqlite3_errmsg(_database), result);
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

- (BOOL) deleteObjectsInSQLTable:(DatabaseSQLTable)table withSQLWhereClause:(NSString*)clause {
LOCK_CONNECTION();
  CHECK(clause);
  
  NSMutableString* string = [NSMutableString stringWithFormat:@"DELETE FROM %@ WHERE %@", table->tableName, clause];
  sqlite3_stmt* statement = NULL;
  int result = _PrepareStatement(_database, [string UTF8String], &statement, NULL);
  if (result == SQLITE_OK) {
    result = _ExecuteStatement(statement);
  }
  if (result != SQLITE_DONE) {
    LOG_ERROR(@"Failed deleting %@ objects with SQL where clause \"%@\" from %@: %s (%i)", table->class, clause, self,
              sqlite3_errmsg(_database), result);
  }
  sqlite3_finalize(statement);
  
UNLOCK_CONNECTION();
  return (result == SQLITE_DONE);
}

@end

@implementation DatabaseConnection (Memory)

- (id) initWithMemoryDatabase {
  return [self initWithDatabaseAtPath:nil readWrite:YES];
}

- (id) initWithInitializedMemoryDatabase {
  return [self initWithInitializedMemoryDatabaseUsingObjectClasses:nil extraSQLStatements:nil];
}

- (id) initWithInitializedMemoryDatabaseUsingObjectClasses:(NSSet*)classes extraSQLStatements:(NSString*)sql {
  if ((self = [self initWithMemoryDatabase])) {
    NSUInteger count = CFDictionaryGetCount(_tableCache);
    DatabaseSQLTable values[count];
    CFDictionaryGetKeysAndValues(_tableCache, NULL, (const void**)values);
    DatabaseSQLTable tables[count];
    NSUInteger index = 0;
    for (NSUInteger i = 0; i < count; ++i) {
      if (!classes || [classes containsObject:values[i]->class]) {
        tables[index++] = values[i];
      }
    }
    
    int result = _InitializeDatabase(_database, tables, index, sql);
    if (result != SQLITE_OK) {
      LOG_ERROR(@"Failed initializing memory database: %s (%i)", sqlite3_errmsg(_database), result);
      [self release];
      return nil;
    }
  }
  return self;
}

- (id) initWithInitializedMemoryDatabaseUsingSchema:(NSSet*)schema extraSQLStatements:(NSString*)sql {
  if ((self = [self initWithMemoryDatabase])) {
    DatabaseSQLTable tables[schema.count];
    NSUInteger index = 0;
    for (DatabaseSchemaTable* table in schema) {
      tables[index++] = table.sqlTable;
    }
    
    int result = _InitializeDatabase(_database, tables, index, sql);
    if (result != SQLITE_OK) {
      LOG_ERROR(@"Failed initializing memory database: %s (%i)", sqlite3_errmsg(_database), result);
      [self release];
      return nil;
    }
  }
  return self;
}

@end

@implementation DatabasePoolConnection

@synthesize pool=_pool;

@end

@implementation DatabaseConnectionPool

+ (DatabaseConnectionPool*) sharedPool {
  static DatabaseConnectionPool* pool = nil;
  if (pool == nil) {
    pool = [[DatabaseConnectionPool alloc] init];
  }
  return pool;
}

- (id) init {
  return [self initWithDatabasePath:[DatabaseConnection defaultDatabasePath]];
}

- (id) initWithDatabasePath:(NSString*)path readWrite:(BOOL)readWrite {
  CHECK(path);
  if ((self = [super init])) {
    _path = [path copy];
    _pool = [[NSMutableSet alloc] init];
    _lock = [[NSLock alloc] init];
    _readWrite = readWrite;
  }
  return self;
}

- (id) initWithDatabasePath:(NSString*)path {
  return [self initWithDatabasePath:path readWrite:YES];
}

- (void) dealloc {
  [_path release];
  for (DatabasePoolConnection* connection in _pool) {
    connection.pool = nil;
  }
  [_pool release];
  [_lock release];
  
  [super dealloc];
}

- (DatabaseConnection*) retrieveConnection {
  [_lock lock];
  DatabasePoolConnection* connection = [[_pool anyObject] retain];
  if (connection) {
    [_pool removeObject:connection];
  } else {
    connection = [[DatabasePoolConnection alloc] initWithDatabaseAtPath:_path readWrite:_readWrite];
    connection.pool = self;
  }
  [_lock unlock];
  return [connection autorelease];
}

- (void) recycleUsedConnection:(DatabaseConnection*)connection {
  DCHECK([connection isKindOfClass:[DatabasePoolConnection class]] && ([(DatabasePoolConnection*)connection pool] == self));
  [_lock lock];
  DCHECK(![_pool containsObject:connection]);
  [_pool addObject:connection];
  [_lock unlock];
}

- (void) purge {
  [_lock lock];
  for (DatabasePoolConnection* connection in _pool) {
    connection.pool = nil;
  }
  [_pool removeAllObjects];
  [_lock unlock];
}

@end
