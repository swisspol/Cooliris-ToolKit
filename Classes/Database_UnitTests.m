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

#import "Database.h"
#import "UnitTest.h"

@interface BaseObject : DatabaseObject
@property(nonatomic) int foo;
@property(nonatomic) double bar;
@end

@implementation BaseObject

@dynamic foo, bar;

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  if ([property isEqualToString:@"foo"]) {
    return kDatabaseSQLColumnOption_Unique;
  }
  return [super sqlColumnOptionsForProperty:property];
}

+ (NSString*) sqlTableFetchOrder {
  return @"foo ASC";
}

@end

@interface TestObject : BaseObject {
  BOOL unused;
}
@property(nonatomic, copy) NSString* string;
@property(nonatomic, copy) NSURL* url;
@property(nonatomic, copy) NSDate* date;
@property(nonatomic, copy) NSData* data;
@property(nonatomic, readonly) int result1;
@property(nonatomic, readonly) NSString* result2;
@property(nonatomic) BOOL unused;
@end

@implementation TestObject

@dynamic string, url, date, data, result1, result2;
@synthesize unused;

+ (DatabaseSQLColumnOptions) sqlColumnOptionsForProperty:(NSString*)property {
  if ([property isEqualToString:@"url"]) {
    return kDatabaseSQLColumnOption_Unique;
  }
  if ([property isEqualToString:@"string"]) {
    return kDatabaseSQLColumnOption_CaseInsensitive_UTF8;
  }
  return [super sqlColumnOptionsForProperty:property];
}

@end

@interface DatabaseTests : UnitTest {
  NSConditionLock* _conditionLock;
}
@end

@implementation DatabaseTests

+ (void) initialize {
  [[NSFileManager defaultManager] removeItemAtPath:[DatabaseConnection defaultDatabasePath] error:NULL];
}

- (void) setUp {
  _conditionLock = [[NSConditionLock alloc] initWithCondition:0];
}

- (void) cleanUp {
  [_conditionLock release];
}

- (void) testProperties {
  TestObject* object = [[TestObject alloc] init];
  AssertEqual(object.sqlRowID, (DatabaseSQLRowID)0);
  object.foo = 2;
  AssertEqual(object.foo, 2);
  object.bar = -3.0;
  AssertEqual(object.bar, -3.0);
  object.string = @"Hello World";
  AssertEqualObjects(object.string, @"Hello World");
  object.url = [NSURL URLWithString:@"file://locahost"];
  AssertEqualObjects(object.url, [NSURL URLWithString:@"file://locahost"]);
  object.date = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
  AssertEqualObjects(object.date, [NSDate dateWithTimeIntervalSinceReferenceDate:0.0]);
  object.data = [NSData dataWithBytes:"DEAD" length:4];
  AssertEqualObjects(object.data, [NSData dataWithBytes:"DEAD" length:4]);
  AssertTrue([object respondsToSelector:@selector(result1)]);
  AssertFalse([object respondsToSelector:@selector(setResult1:)]);
  AssertTrue([object respondsToSelector:@selector(result2)]);
  AssertFalse([object respondsToSelector:@selector(setResult2:)]);
  [object release];
}

- (void) testConnection {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  AssertTrue([DatabaseConnection initializeDatabaseAtPath:[DatabaseConnection defaultDatabasePath]]);
  
  AssertEqual([[connection fetchAllObjectsOfClass:[BaseObject class]] count], (NSUInteger)0);
  AssertEqual([[connection fetchAllObjectsOfClass:[TestObject class]] count], (NSUInteger)0);
  
  AssertTrue([connection vacuum]);
  AssertTrue([connection executeRawSQLStatements:@"SELECT MIN(foo) FROM TestObject; SELECT MAX(foo) FROM TestObject;"]);
}

- (void) testObjectCreation {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  TestObject* object = [[TestObject alloc] init];
  AssertNotNil(object);
  
  AssertEqual(object.sqlRowID, (DatabaseSQLRowID)0);
  AssertEqual(object.foo, 0);
  AssertEqual(object.bar, 0.0);
  AssertEqualObjects(object.string, nil);
  AssertEqualObjects(object.url, nil);
  AssertEqualObjects(object.date, nil);
  AssertEqualObjects(object.data, nil);
  
  AssertTrue([connection insertObject:object]);
  AssertGreaterThan(object.sqlRowID, (DatabaseSQLRowID)0);
  
  AssertTrue([connection hasObjectOfClass:[TestObject class] withSQLRowID:object.sqlRowID]);
  AssertFalse([connection hasObjectOfClass:[TestObject class] withSQLRowID:1234]);
  
  AssertEqual([[connection fetchAllObjectsOfClass:[TestObject class]] count], (NSUInteger)1);
  
  TestObject* copy = [connection fetchObjectOfClass:[TestObject class] withSQLRowID:object.sqlRowID];
  AssertNotNil(copy);
  AssertNotEqual(object, copy);
  AssertEqualObjects(object, copy);
  AssertEqual(copy.sqlRowID, object.sqlRowID);
  AssertEqual(copy.foo, 0);
  AssertEqual(copy.bar, 0.0);
  AssertEqualObjects(copy.string, nil);
  AssertEqualObjects(copy.url, nil);
  AssertEqualObjects(copy.date, nil);
  AssertEqualObjects(copy.data, nil);
  
  AssertTrue([connection deleteObject:object]);
  AssertEqual(object.sqlRowID, (DatabaseSQLRowID)0);
  
  AssertEqual([[connection fetchAllObjectsOfClass:[TestObject class]] count], (NSUInteger)0);
  
  TestObject* zombie = [connection fetchObjectOfClass:[TestObject class] withSQLRowID:copy.sqlRowID];
  AssertNil(zombie);
  
  [object release];
}

- (void) testObjectDeletion {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  TestObject* object1 = [[TestObject alloc] init];
  AssertNotNil(object1);
  object1.foo = 1;
  AssertTrue([connection insertObject:object1]);
  
  TestObject* object2 = [[TestObject alloc] init];
  AssertNotNil(object2);
  object2.foo = 2;
  AssertTrue([connection insertObject:object2]);
  
  AssertTrue([connection deleteObjectsOfClass:[TestObject class] withProperty:@"foo" matchingValue:nil]);
  AssertTrue([connection deleteObjectsOfClass:[TestObject class] withProperty:@"foo" matchingValue:[NSNumber numberWithInt:2]]);
  AssertNotEqual(object1.sqlRowID, (DatabaseSQLRowID)0);
  AssertNotEqual(object2.sqlRowID, (DatabaseSQLRowID)0);
  AssertTrue([connection refetchObject:object1]);
  AssertFalse([connection refetchObject:object2]);
  AssertNotEqual(object1.sqlRowID, (DatabaseSQLRowID)0);
  AssertEqual(object2.sqlRowID, (DatabaseSQLRowID)0);
  
  [object2 release];
  [object1 release];
}

- (void) testObjectProperties {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  TestObject* object = [[TestObject alloc] init];
  AssertNotNil(object);
  object.foo = 2;
  object.bar = -3.0;
  object.string = @"Hello World";
  object.url = [NSURL URLWithString:@"file://locahost"];
  object.date = [NSDate dateWithTimeIntervalSinceReferenceDate:0.0];
  object.data = [NSData dataWithBytes:"DEAD" length:4];
  AssertTrue([connection insertObject:object]);
  
  TestObject* copy = [connection fetchObjectOfClass:[TestObject class] withSQLRowID:object.sqlRowID];
  AssertNotNil(copy);
  AssertEqual(copy.sqlRowID, object.sqlRowID);
  AssertEqual(copy.foo, 2);
  AssertEqual(copy.bar, -3.0);
  AssertEqualObjects(copy.string, @"Hello World");
  AssertEqualObjects(copy.url, [NSURL URLWithString:@"file://locahost"]);
  AssertEqualObjects(copy.date, [NSDate dateWithTimeIntervalSinceReferenceDate:0.0]);
  AssertEqualObjects(copy.data, [NSData dataWithBytes:"DEAD" length:4]);
  
  object.bar = 5.0;
  AssertTrue([connection updateObject:object]);
  
  AssertTrue([connection refetchObject:copy]);
  AssertEqual(copy.bar, 5.0);
  
  AssertEqual([connection countObjectsOfClass:[TestObject class]], (NSUInteger)2);
  {
    TestObject* result = [connection fetchObjectOfClass:[TestObject class]
                                     withUniqueProperty:@"url"
                                          matchingValue:[NSURL URLWithString:@"file://locahost"]];
    AssertNotNil(result);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class]
                                          withProperty:@"foo"
                                         matchingValue:[NSNumber numberWithInt:2]];
    AssertEqual(results.count, (NSUInteger)1);
    AssertEqualObjects([results objectAtIndex:0], copy);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class]
                                          withProperty:@"bar"
                                         matchingValue:[NSNumber numberWithDouble:5.0]];
    AssertEqual(results.count, (NSUInteger)1);
    AssertEqualObjects([results objectAtIndex:0], copy);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class]
                                          withProperty:@"string"
                                         matchingValue:@"hello world"];
    AssertEqual(results.count, (NSUInteger)1);
    AssertEqualObjects([results objectAtIndex:0], copy);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class]
                                          withProperty:@"url"
                                         matchingValue:[NSURL URLWithString:@"file://locahost"]];
    AssertEqual(results.count, (NSUInteger)1);
    AssertEqualObjects([results objectAtIndex:0], copy);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class] withSQLWhereClause:@"1"];
    AssertEqual(results.count, (NSUInteger)2);
  }
  {
    NSArray* results = [connection fetchObjectsOfClass:[TestObject class] withSQLWhereClause:@"foo=2"];
    AssertEqual(results.count, (NSUInteger)1);
  }
  {
    NSArray* results = [connection executeRawSQLStatement:@"SELECT * from TestObject"];
    AssertEqual(results.count, (NSUInteger)2);
  }
  {
    NSArray* results = [connection executeRawSQLStatement:@"SELECT COUNT(*) AS count from TestObject"];
    AssertEqualObjects(results,
                       [NSArray arrayWithObject:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:2] forKey:@"count"]]);
  }
  
  [object release];
}

- (void) testTransactions {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  TestObject* object = [[TestObject alloc] init];
  AssertTrue([connection beginTransaction]);
  AssertTrue([connection insertObject:object]);
  object.bar = 5.0;
  AssertTrue([connection updateObject:object]);
  AssertTrue([connection commitTransaction]);
  AssertTrue([connection deleteObject:object]);
  [object release];
  
  AssertTrue([connection beginTransaction]);
  AssertTrue([connection beginTransaction]);
  AssertTrue([connection commitTransaction]);
  AssertTrue([connection commitTransaction]);
  
  AssertTrue([connection beginTransaction]);
  AssertTrue([connection rollbackTransaction]);
  
  AssertTrue([connection beginTransaction]);
  AssertTrue([connection commitTransaction]);
}

- (void) _contentionThread:(id)argument {
  [_conditionLock lockWhenCondition:0];
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  DatabaseConnection* connection = [[DatabaseConnection alloc] initWithDatabaseAtPath:[DatabaseConnection defaultDatabasePath]];
  AssertNotNil(connection);
  [_conditionLock unlockWithCondition:1];
  
  for (NSInteger i = 0; i < 100; ++i) {
    TestObject* object = [[TestObject alloc] init];
    AssertNotNil(object);
    object.foo = 1000 + i;
    AssertTrue([connection insertObject:object]);
    [object release];
  }
  
  [_conditionLock lockWhenCondition:2];
  [connection release];
  [pool release];
  [_conditionLock unlockWithCondition:3];
}

- (void) testContention {
  DatabaseConnection* connection = [DatabaseConnection defaultDatabaseConnection];
  AssertNotNil(connection);
  
  [NSThread detachNewThreadSelector:@selector(_contentionThread:) toTarget:self withObject:nil];
  [_conditionLock lockWhenCondition:1];
  [_conditionLock unlockWithCondition:2];
  
  for (NSInteger i = 0; i < 100; ++i) {
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    AssertNotNil([connection fetchAllObjectsOfClass:[TestObject class]]);
    [pool release];
  }
  
  [_conditionLock lockWhenCondition:3];
  [_conditionLock unlockWithCondition:0];
  
  AssertTrue([connection deleteAllObjectsOfClass:[TestObject class]]);
}

- (void) testXSchema1 {  // Run last
  NSMutableArray* columns = [[NSMutableArray alloc] init];
  DatabaseSchemaColumn* column1 = [[DatabaseSchemaColumn alloc] initWithName:@"name"
                                                                        type:kDatabaseSQLColumnType_String
                                                                     options:(kDatabaseSQLColumnOption_NotNull | kDatabaseSQLColumnOption_CaseInsensitive_UTF8)];
  AssertNotNil(column1);
  [columns addObject:column1];
  DatabaseSchemaColumn* column2 = [[DatabaseSchemaColumn alloc] initWithName:@"age"
                                                                        type:kDatabaseSQLColumnType_Int
                                                                     options:0];
  AssertNotNil(column2);
  [columns addObject:column2];
  DatabaseSchemaTable* table = [[DatabaseSchemaTable alloc] initWithName:@"employee" fetchOrder:nil columns:columns];
  AssertNotNil(table);
  
  [[NSFileManager defaultManager] removeItemAtPath:[DatabaseConnection defaultDatabasePath] error:NULL];
  NSSet* schema = [[NSSet alloc] initWithObjects:&table count:1];
  AssertTrue([DatabaseConnection initializeDatabaseAtPath:[DatabaseConnection defaultDatabasePath]
                                              usingSchema:schema
                                       extraSQLStatements:nil]);
  [schema release];
  DatabaseConnection* connection = [[DatabaseConnection alloc] initWithDatabaseAtPath:[DatabaseConnection defaultDatabasePath]];
  AssertNotNil(connection);
  
  DatabaseObject* object = [[DatabaseObject alloc] initWithSQLTable:table.sqlTable];
  [object setValue:@"cooliris" forProperty:@"name"];
  DatabaseSQLColumn column = column2.sqlColumn;
  AssertNotEqual(column, NULL);
  [object setInt:30 forSQLColumn:column];
  AssertTrue(object.modified);
  AssertTrue([connection insertObject:object]);
  AssertFalse(object.modified);
  [object release];
  
  NSArray* results = [connection fetchObjectsInSQLTable:table.sqlTable withSQLColumn:column1.sqlColumn matchingValue:@"cooliris"];
  AssertEqual(results.count, (NSUInteger)1);
  object = [results objectAtIndex:0];
  AssertEqual([object intForSQLColumn:column2.sqlColumn], (int)30);
  
  [connection release];
  
  [column2 release];
  [column1 release];
  [table release];
  [columns release];
}

- (void) testXSchema2 {  // Run last
  NSMutableArray* columns = [[NSMutableArray alloc] init];
  DatabaseSchemaColumn* column = [[DatabaseSchemaColumn alloc] initWithName:@"guid"
                                                                       type:kDatabaseSQLColumnType_String
                                                                    options:(kDatabaseSQLColumnOption_NotNull | kDatabaseSQLColumnOption_Unique)];
  AssertNotNil(column);
  [columns addObject:column];
  DatabaseSchemaTable* table = [[DatabaseSchemaTable alloc] initWithObjectClass:[TestObject class]
                                                                           name:@"record"
                                                                     fetchOrder:nil
                                                                   extraColumns:columns];
  AssertNotNil(table);
  AssertEqual(table.columns.count, (NSUInteger)9);
  
  [[NSFileManager defaultManager] removeItemAtPath:[DatabaseConnection defaultDatabasePath] error:NULL];
  NSSet* schema = [[NSSet alloc] initWithObjects:&table count:1];
  AssertTrue([DatabaseConnection initializeDatabaseAtPath:[DatabaseConnection defaultDatabasePath]
                                              usingSchema:schema
                                       extraSQLStatements:nil]);
  [schema release];
  DatabaseConnection* connection = [[DatabaseConnection alloc] initWithDatabaseAtPath:[DatabaseConnection defaultDatabasePath]];
  AssertNotNil(connection);
  
  TestObject* object = [[table.objectClass alloc] initWithSQLTable:table.sqlTable];
  AssertTrue([object isKindOfClass:[TestObject class]]);
  object.foo = 1;
  object.string = @"Hello World!";
  [object setObject:@"123456" forSQLColumn:column.sqlColumn];
  AssertTrue([connection insertObject:object]);
  [object release];
  
  NSArray* results = [connection fetchObjectsInSQLTable:table.sqlTable
                                          withSQLColumn:[[table.columns objectAtIndex:3] sqlColumn]
                                          matchingValue:[NSNumber numberWithInt:1]];
  AssertEqual(results.count, (NSUInteger)1);
  object = [results objectAtIndex:0];
  AssertEqualObjects(object.string, @"Hello World!");
  
  [connection release];
  
  [column release];
  [table release];
  [columns release];
}

@end
