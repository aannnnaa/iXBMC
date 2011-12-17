//
//  NSManagedObjectContext+Additions.h
//  Shopify_Mobile
//
//  Created by Matthew Newberry on 7/12/10.
//  Copyright 2010 Shopify. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface NSManagedObjectContext (NSManagedObjectContext_Additions)

- (BOOL) save;
- (NSArray *)fetchObjectsForEntityName:(NSString *)newEntityName
					   withPredicate:(id)stringOrPredicate, ...;

@end
