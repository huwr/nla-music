//
//  MUSDataController.m
//  nla-music
//
//  Copyright © 2012 Jake MacMullin
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of
//  this software and associated documentation files (the "Software"), to deal in
//  the Software without restriction, including without limitation the rights to
//  use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
//  of the Software, and to permit persons to whom the Software is furnished to do
//  so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

#import "MUSDataController.h"
#import <CoreData/CoreData.h>
#import "Page.h"
#import "AFNetworking.h"

static NSString * kFavouritesKey = @"favourite-scores";
static int kMaximumNumberOfPagesToCache = 10;

@interface MUSDataController()

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSPersistentStoreCoordinator *coordinator;
@property (nonatomic, strong) NSManagedObjectContext *context;

@property (nonatomic, strong) NSArray *cachedDecades;

@property (nonatomic, strong) NSString *decadeOfCachedScores;
@property (nonatomic, strong) NSArray *cachedScores;
@property (nonatomic, strong) NSString *composerOfCachedScores;
@property (nonatomic, strong) NSArray *cachedScoresByComposer;

@property (nonatomic, strong) NSArray *favouriteScores;

@property (nonatomic, strong) NSOperationQueue *imageDownloadQueue;

- (NSArray *)fetchDecades;
- (NSArray *)fetchIdentifiersOfFavourites;

@end

@implementation MUSDataController

+ (MUSDataController *)sharedController
{
    static MUSDataController *sharedInstance = nil;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (NSIndexPath *)indexOfFirstScoreWithLetter:(NSString *)letter inDecade:(NSString *)decade
{
    BOOL found = NO;
    int i=0;
    for (Score *score in self.cachedScores) {
        if ([score.sortTitle.lowercaseString hasPrefix:letter.lowercaseString]) {
            found = YES;
            break;
        }
        i++;
    }
    
    NSIndexPath *indexPath = nil;
    
    if (found==YES) {
        indexPath = [NSIndexPath indexPathForItem:i-1 inSection:0];
    }
    
    return indexPath;
}

- (Score *)scoreAtIndex:(NSIndexPath *)indexPath inDecade:(NSString *)decade
{
    if ([self.decadeOfCachedScores isEqualToString:decade] && self.cachedScores!=nil) {
        return [self.cachedScores objectAtIndex:indexPath.row];
    }
    
    NSFetchRequest *scoresFetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Score"];
    
    // Sort order
    NSSortDescriptor *titleSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"sortTitle" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    [scoresFetchRequest setSortDescriptors:@[titleSortDescriptor]];
    
    // Only get scores for the given decade
    NSPredicate *decadePredicate = [NSPredicate predicateWithFormat:@"%K == %@", @"date", decade, nil];
    [scoresFetchRequest setPredicate:decadePredicate];
    
    NSArray *scores = [self.context executeFetchRequest:scoresFetchRequest error:NULL];
    
    // we're caching scores for a given decade (with no composer)
    // so forget the previously cached scores with a given composer
    [self setComposerOfCachedScores:nil];
    [self setCachedScoresByComposer:nil];
    
    [self setCachedScores:scores];
    [self setDecadeOfCachedScores:decade];
    
    return [self.cachedScores objectAtIndex:indexPath.row];
}

- (Score *)scoreAtIndex:(NSIndexPath *)indexPath inDecade:(NSString *)decade byComposer:(NSString *)composer
{
    if ([self.decadeOfCachedScores isEqualToString:decade] &&
        [self.composerOfCachedScores isEqualToString:composer] &&
        self.cachedScoresByComposer!=nil) {
        return [self.cachedScoresByComposer objectAtIndex:indexPath.row];
    }

    NSFetchRequest *scoresFetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Score"];
    
    // Sort order
    NSSortDescriptor *titleSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"sortTitle" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    [scoresFetchRequest setSortDescriptors:@[titleSortDescriptor]];
    
    // Only get scores for the given decade and composer
    NSPredicate *decadePredicate = [NSPredicate predicateWithFormat:@"date == %@ AND creator == %@", decade, composer, nil];
    [scoresFetchRequest setPredicate:decadePredicate];
    
    NSArray *scores = [self.context executeFetchRequest:scoresFetchRequest error:NULL];
    
    // we're caching scores for a given decade (with a given composer)
    // so forget the previously cached scores without a given composer
    [self setCachedScores:nil];
    
    [self setCachedScoresByComposer:scores];
    [self setDecadeOfCachedScores:decade];
    [self setComposerOfCachedScores:composer];
    
    return [self.cachedScoresByComposer objectAtIndex:indexPath.row];
}

#pragma mark - Core Data Stack

- (NSManagedObjectContext *)context {
    if (_context == nil) {
        // Create the managed object model
        NSManagedObjectModel *model = [NSManagedObjectModel mergedModelFromBundles:nil];
        [self setModel:model];
        
        // Create the persistent store coordinator
        NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
        [self setCoordinator:coordinator];
        
        // Create the persistent store itself (if it is not already there)
        
        // copy the core-data database to the documents directory if it isn't already there
        BOOL expandTilde = YES;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, expandTilde);
        NSString *documentPath = [paths objectAtIndex:0];
        NSString *dataStorePath = [documentPath stringByAppendingPathComponent:@"data.sqlite"];
        NSURL *storeURL = [[NSURL alloc] initFileURLWithPath:dataStorePath];
        BOOL isDir = NO;
        NSError *error;
        if (! [[NSFileManager defaultManager] fileExistsAtPath:dataStorePath isDirectory:&isDir] && isDir == NO) {
            [[NSFileManager defaultManager] createDirectoryAtPath:documentPath withIntermediateDirectories:YES attributes:nil error:&error];
            NSURL *bundleURL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:@"data" ofType:@"sqlite"]];
            NSError *error;
            [[NSFileManager defaultManager] copyItemAtURL:bundleURL toURL:storeURL error:&error];
        }
        
        NSError *storeError;
        if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType
                                       configuration:nil
                                                 URL:storeURL
                                             options:nil
                                               error:&storeError]) {
            NSLog(@"There was an error creating the persistent store");
        }
        
        // Create the context
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [context setPersistentStoreCoordinator:self.coordinator];
        
        // Get the 'score' entity from the model and specify the sort order for the
        // 'orderedPages' fetched property
        NSEntityDescription *scoreEntityDescription = [NSEntityDescription entityForName:@"Score" inManagedObjectContext:context];
        NSFetchedPropertyDescription *orderedPagesDescription = [[scoreEntityDescription propertiesByName] objectForKey:@"orderedPages"];
        
        NSFetchRequest *fetchRequest = orderedPagesDescription.fetchRequest;
        [fetchRequest setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES]]];
        
        [self setContext:context];
    }
    return _context;
}


#pragma mark - Decades

- (NSArray *)fetchDecades
{
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Score"];
    
    NSEntityDescription *scoreEntityDescription = [NSEntityDescription entityForName:@"Score" inManagedObjectContext:self.context];
    NSAttributeDescription *dateAttributeDescription = [scoreEntityDescription.attributesByName valueForKey:@"date"];
    NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:@"title"];
    NSExpression *countExpression = [NSExpression expressionForFunction:@"count:" arguments:@[keyPathExpression]];
    NSExpressionDescription *expressionDescription = [[NSExpressionDescription alloc] init];
    [expressionDescription setName:@"count"];
    [expressionDescription setExpression:countExpression];
    [expressionDescription setExpressionResultType:NSInteger32AttributeType];
    
    [fetchRequest setPropertiesToFetch:@[dateAttributeDescription, expressionDescription]];
    [fetchRequest setPropertiesToGroupBy:@[dateAttributeDescription]];
    [fetchRequest setResultType:NSDictionaryResultType];
    
    NSSortDescriptor *dateSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
    [fetchRequest setSortDescriptors:@[dateSortDescriptor]];
    
    NSArray *results = [self.context executeFetchRequest:fetchRequest error:NULL];
    [self setCachedDecades:results];
    return results;
}

- (NSArray *)decadesInWhichMusicWasPublished
{
    if (self.cachedDecades != nil) {
        return self.cachedDecades;
    }
    
    NSArray *results = [self fetchDecades];
    return results;
}

- (int)numberOfScoresInDecade:(NSString *)decade
{
    NSArray *decades;
    if (self.cachedDecades!=nil) {
        decades = self.cachedDecades;
    } else {
        decades = [self fetchDecades];
    }
    
    for (NSDictionary *dict in decades) {
        if ([[dict valueForKey:@"date"] isEqualToString:decade]) {
            return [[dict valueForKey:@"count"] intValue];
        }
    }
    
    return 0;
}

- (int)numberOfScoresInDecade:(NSString *)decade byComposer:(NSString *)composer
{
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Score"];
    
    NSEntityDescription *scoreEntityDescription = [NSEntityDescription entityForName:@"Score" inManagedObjectContext:self.context];
    NSAttributeDescription *dateAttributeDescription = [scoreEntityDescription.attributesByName valueForKey:@"date"];
    NSAttributeDescription *composerAttributeDescription = [scoreEntityDescription.attributesByName valueForKey:@"creator"];
    NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:@"title"];
    NSExpression *countExpression = [NSExpression expressionForFunction:@"count:" arguments:@[keyPathExpression]];
    NSExpressionDescription *expressionDescription = [[NSExpressionDescription alloc] init];
    [expressionDescription setName:@"count"];
    [expressionDescription setExpression:countExpression];
    [expressionDescription setExpressionResultType:NSInteger32AttributeType];
    
    NSPredicate *decadeAndComposerPredicate = [NSPredicate predicateWithFormat:@"date == %@ AND creator == %@", decade, composer];
    
    [fetchRequest setPropertiesToFetch:@[dateAttributeDescription, expressionDescription, composerAttributeDescription]];
    [fetchRequest setPropertiesToGroupBy:@[dateAttributeDescription, composerAttributeDescription]];
    [fetchRequest setResultType:NSDictionaryResultType];
    [fetchRequest setPredicate:decadeAndComposerPredicate];
    
    NSSortDescriptor *dateSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"date" ascending:YES];
    [fetchRequest setSortDescriptors:@[dateSortDescriptor]];
    
    NSArray *results = [self.context executeFetchRequest:fetchRequest error:NULL];
    
    // There should be a single row
    assert(results.count == 1); // TODO: error handling
    
    NSDictionary *resultDict = (NSDictionary *)results.lastObject;
    
    int count = [[resultDict valueForKey:@"count"] intValue];
    
    return count;
}

#pragma mark - Composers

- (NSArray *)composersWithMusicPublishedIn:(NSString *)decade
{
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Score"];
    
    NSEntityDescription *scoreEntityDescription = [NSEntityDescription entityForName:@"Score" inManagedObjectContext:self.context];
    NSAttributeDescription *composerAttributeDescription = [scoreEntityDescription.attributesByName valueForKey:@"creator"];
    NSExpression *keyPathExpression = [NSExpression expressionForKeyPath:@"title"];
    NSExpression *countExpression = [NSExpression expressionForFunction:@"count:" arguments:@[keyPathExpression]];
    NSExpressionDescription *expressionDescription = [[NSExpressionDescription alloc] init];
    [expressionDescription setName:@"count"];
    [expressionDescription setExpression:countExpression];
    [expressionDescription setExpressionResultType:NSInteger32AttributeType];
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"creator.length > 0 AND date == %@", decade];
    
    [fetchRequest setPredicate:predicate];
    [fetchRequest setPropertiesToFetch:@[composerAttributeDescription, expressionDescription]];
    [fetchRequest setPropertiesToGroupBy:@[composerAttributeDescription]];
    [fetchRequest setResultType:NSDictionaryResultType];
    
    NSSortDescriptor *composerSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"creator" ascending:YES];
    [fetchRequest setSortDescriptors:@[composerSortDescriptor]];
    
    NSArray *results = [self.context executeFetchRequest:fetchRequest error:NULL];
    return results;
}


#pragma mark - Favourites

- (int)numberOfFavouriteScores
{
    return [self fetchIdentifiersOfFavourites].count;
}

- (Score *)scoreAtIndexInFavourites:(int)index
{
    if (self.favouriteScores!=nil) {
        return self.favouriteScores[index];
    }
    
    NSArray *identifiers = [self fetchIdentifiersOfFavourites];
    
    NSFetchRequest *scoresFetchRequest = [[NSFetchRequest alloc] initWithEntityName:@"Score"];
    
    // Sort order
    NSSortDescriptor *titleSortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"sortTitle" ascending:YES selector:@selector(caseInsensitiveCompare:)];
    [scoresFetchRequest setSortDescriptors:@[titleSortDescriptor]];
    
    // Only get scores for the given identifiers
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"%K IN %@", @"identifier", identifiers, nil];
    [scoresFetchRequest setPredicate:predicate];
    
    NSArray *scores = [self.context executeFetchRequest:scoresFetchRequest error:NULL]; // TODO: Error handling
    [self setFavouriteScores:scores];
    
    return [self.favouriteScores objectAtIndex:index];
}

- (NSArray *)fetchIdentifiersOfFavourites
{
    // TODO: consider caching the list of favourites instead of querying the user defaults
    // each time.

    NSArray *favourites;
    NSString *identifiersOfFavouriteScores = [[NSUserDefaults standardUserDefaults] stringForKey:kFavouritesKey];
    if (identifiersOfFavouriteScores!=nil) {
        favourites = [identifiersOfFavouriteScores componentsSeparatedByString:@","];
    } else {
        favourites = @[];
    }
    return favourites;
}


- (BOOL)isScoreMarkedAsFavourite:(Score *)score
{
    for (NSString *identifier in [self fetchIdentifiersOfFavourites]) {
        if ([identifier isEqualToString:score.identifier]) {
            return YES;
        }
    }
    return NO;
}


- (void)markScore:(Score *)score asFavourite:(BOOL)isFavourite
{
    // invalidate the cached favourites
    [self setFavouriteScores:nil];
    
    NSMutableArray *modifiedFavourites = [[self fetchIdentifiersOfFavourites] mutableCopy];
    
    if (isFavourite == YES) {
        // if we're marking the score as a favourite, we'll need to add its
        // identifier to the list of identifiers.
        if ([self isScoreMarkedAsFavourite:score] == NO) {
            [modifiedFavourites addObject:score.identifier];
        }
        
        // download the first n pages of the score and save them
        // in the cache directory
        if (self.imageDownloadQueue == nil) {
            NSOperationQueue *queue = [[NSOperationQueue alloc] init];
            [self setImageDownloadQueue:queue];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *error;
            if (![fileManager fileExistsAtPath:score.cacheDirectory]) {
                [fileManager createDirectoryAtPath:score.cacheDirectory withIntermediateDirectories:YES attributes:nil error:&error];
            }
        }
        
        int numberOfPagesToDownload = MIN(score.orderedPages.count, kMaximumNumberOfPagesToCache);
        
        for (int i=0; i<numberOfPagesToDownload; i++) {
            Page *page = (Page *)score.orderedPages[i];
            NSURL *pageImageURL = page.imageURL;
            
            NSURLRequest *request = [NSURLRequest requestWithURL:pageImageURL];
            
            void (^successBlock)(NSURLRequest *, NSHTTPURLResponse *, UIImage *);
            successBlock = ^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
                NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
                [imageData writeToFile:page.cachedImagePath atomically:YES];
            };

            AFImageRequestOperation *imageRequestOperation;
            imageRequestOperation = [AFImageRequestOperation imageRequestOperationWithRequest:request
                                                                         imageProcessingBlock:nil
                                                                                      success:successBlock
                                                                                      failure:nil];
            [self.imageDownloadQueue addOperation:imageRequestOperation];
            
            NSURL *thumbnailImageURL = page.thumbnailURL;
            NSURLRequest *thumbnailRequest = [NSURLRequest requestWithURL:thumbnailImageURL];
            
            void (^thumbnailSuccessBlock)(NSURLRequest *, NSHTTPURLResponse *, UIImage *);
            thumbnailSuccessBlock = ^(NSURLRequest *request, NSHTTPURLResponse *response, UIImage *image) {
                NSData *imageData = UIImageJPEGRepresentation(image, 1.0);
                [imageData writeToFile:page.cachedThumbnailImagePath atomically:YES];
            };
            
            AFImageRequestOperation *thumbnailRequestOperation;
            thumbnailRequestOperation = [AFImageRequestOperation imageRequestOperationWithRequest:thumbnailRequest
                                                                         imageProcessingBlock:nil
                                                                                      success:thumbnailSuccessBlock
                                                                                      failure:nil];
            [self.imageDownloadQueue addOperation:thumbnailRequestOperation];
        }
        
    } else {
        // otherwise, we'll need to remove its identifier from the list
        if ([self isScoreMarkedAsFavourite:score] == YES) {
            
            NSString *identifierToRemove = nil;
            
            for (NSString *identifier in modifiedFavourites) {
                if ([identifier isEqualToString:score.identifier]) {
                    identifierToRemove = identifier;
                }
            }
            
            if (identifierToRemove!=nil) {
                [modifiedFavourites removeObject:identifierToRemove];
            }
            
            // delete any cached images
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *error;
            for (Page *page in score.pages) {
                if ([fileManager fileExistsAtPath:page.cachedImagePath]) {
                    [fileManager removeItemAtPath:page.cachedImagePath error:&error];
                }
                
                // and thumbnails                
                if ([fileManager fileExistsAtPath:page.cachedThumbnailImagePath]) {
                    [fileManager removeItemAtPath:page.cachedThumbnailImagePath error:&error];
                }

            }
            if ([fileManager fileExistsAtPath:score.cacheDirectory]) {
                [fileManager removeItemAtPath:score.cacheDirectory error:&error];
            }
            
        }
    }
    
    // Save the modified list of favourites
    NSMutableString *identifiersString = [[NSMutableString alloc] init];
    for (NSString *identifier in modifiedFavourites) {
        [identifiersString appendString:identifier];
        if (modifiedFavourites.lastObject!=identifier) {
            [identifiersString appendString:@","];
        }
    }
    if (identifiersString.length==0) {
        [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kFavouritesKey];
    } else {
        [[NSUserDefaults standardUserDefaults] setObject:identifiersString forKey:kFavouritesKey];
    }

}


@end
