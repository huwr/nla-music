//
//  MUSComposersTableViewController.h
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

#import <UIKit/UIKit.h>
#import "MUSDataController.h"

@class MUSComposersTableViewController;

/**
 Classes that wish to be informed when a composer
 is selected should implement this delegate protocol.
 */
@protocol MUSComposersTableViewControllerDelegate <NSObject>

- (void)composersTableViewControllerDidSelectAllComposers:(MUSComposersTableViewController *)controller;

- (void)composersTableViewController:(MUSComposersTableViewController *)controller didSelectComposerWithInfo:(NSDictionary *)composerInfo;

@end

@interface MUSComposersTableViewController : UITableViewController

/**
 The decade whose composers should be displayed.
 */
@property (nonatomic, strong) NSString *decade;

@property (nonatomic, strong) MUSDataController *dataController;

@property (nonatomic, assign) id<MUSComposersTableViewControllerDelegate> delegate;

@property (nonatomic) NSInteger selectedSegmentIndex;
@property (nonatomic, strong) NSIndexPath *selectedIndexPath;


@property (nonatomic, strong) IBOutlet UISegmentedControl *orderSwitcher;

- (IBAction)switchSortOrder:(id)sender;

@end
