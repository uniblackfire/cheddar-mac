//
//  CDMListsViewController.m
//  Cheddar for Mac
//
//  Created by Indragie Karunaratne on 2012-08-13.
//  Copyright (c) 2012 Nothing Magical. All rights reserved.
//

#import "CDMListsViewController.h"
#import "CDMListTableRowView.h"
#import "CDMTasksViewController.h"
#import "CDMColorView.h"
#import "CDMShadowTableView.h"
#import "CDMListsPlaceholderView.h"
#import "CDMLoadingView.h"
#import <QuartzCore/QuartzCore.h>

typedef NS_ENUM(NSInteger, CDMListsMenuItemTag) {
    CDMListsRenameListItemTag = 0,
    CDMListsArchiveAllTasksItemTag = 1,
    CDMListsArchiveCompletedTasksItemTag = 2,
    CDMListsArchiveListItemTag = 3
};

static NSString *const kCDMNoListsNibName = @"NoLists";
static NSString *const kCDMLoadingListsNibName = @"LoadingLists";
static NSString *const kCDMListsDragTypeRearrange = @"CDMListsDragTypeRearrange";
static CGFloat const kCDMListsViewControllerAddListAnimationDuration = 0.15f;

@interface CDMListsViewController ()
- (void)_setNoListsViewVisible:(BOOL)visible;
- (void)_setLoadingListsViewVisible:(BOOL)visible;
// Menu Item Actions
- (void)_renameList:(NSMenuItem *)menuItem;
- (void)_archiveAllTasks:(NSMenuItem *)menuItem;
- (void)_archiveCompletedTasks:(NSMenuItem *)menuItem;
- (void)_archiveList:(NSMenuItem *)menuItem;
@end

@implementation CDMListsViewController {
    BOOL _awakenFromNib;
    BOOL _isLoading;
    CDMColorView *_overlayView;
}

#pragma mark - NSObject

- (void)awakeFromNib {
    [super awakeFromNib];
    
    [self.tableView registerForDraggedTypes:[NSArray arrayWithObjects:kCDMListsDragTypeRearrange, kCDMTasksDragTypeMove, nil]];
	
    if (_awakenFromNib) {
        return;
    }
		
    self.arrayController.managedObjectContext = [CDKList mainContext];
	self.arrayController.sortDescriptors = [CDKList defaultSortDescriptors];
    [self.arrayController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:NULL];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload:) name:kCDKCurrentUserChangedNotificationName object:nil];

    [self reload:nil];
    _awakenFromNib = YES;
}

- (void)dealloc
{
    [_arrayController removeObserver:self forKeyPath:@"arrangedObjects"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"arrangedObjects"]) {
        if ([self.loadingListsView superview])
            [self _setLoadingListsViewVisible:![[self.arrayController arrangedObjects] count]];
        [self _setNoListsViewVisible:![[self.arrayController arrangedObjects] count]];
    }
}

#pragma mark - Actions

- (CDKList *)selectedList {
    NSInteger row = [self.tableView selectedRow];
    if (row != -1) {
        return [[self.arrayController arrangedObjects] objectAtIndex:row];
    }
    return nil;
}

- (IBAction)reload:(id)sender {
    [self _setLoadingListsViewVisible:![[self.arrayController arrangedObjects] count]];
    [self _setNoListsViewVisible:NO];
    self.arrayController.fetchPredicate = [NSPredicate predicateWithFormat:@"archivedAt = nil && user = %@", [CDKUser currentUser]];
    [[CDKHTTPClient sharedClient] getListsWithSuccess:^(AFJSONRequestOperation *operation, id responseObject) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.arrayController fetch:nil];
            [self _setLoadingListsViewVisible:NO];
            [self _setNoListsViewVisible:![self.arrayController arrangedObjects]];
        });
    } failure:^(AFJSONRequestOperation *operation, NSError *error) {
        NSLog(@"Failed to get lists: %@", error);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _setLoadingListsViewVisible:NO];
        });
    }];
	[[CDKHTTPClient sharedClient] updateCurrentUserWithSuccess:nil failure:nil];
}


- (IBAction)addList:(id)sender {
    if ([self.addListView superview]) {
        [self closeAddList:nil];
        return;
    }
    NSScrollView *scrollView = [self.tableView enclosingScrollView];
    NSRect beforeAddFrame = [self.addListView frame];
    beforeAddFrame.origin.y = NSMaxY([scrollView frame]);
    beforeAddFrame.size.width = [scrollView frame].size.width;
    [self.addListView setFrame:beforeAddFrame];
    [self.addListField setStringValue:@""];
    NSView *parentView = [scrollView superview] ;
    [parentView addSubview:self.addListView positioned:NSWindowBelow relativeTo:[[parentView subviews] objectAtIndex:0]];
    _overlayView = [[CDMColorView alloc] initWithFrame:[scrollView frame]];
    [_overlayView setBackgroundColor:[NSColor colorWithDeviceWhite:1.f alpha:0.9f]];
    [_overlayView setAlphaValue:0.f];
    [_overlayView setAutoresizingMask:[scrollView autoresizingMask]];
    [parentView addSubview:_overlayView positioned:NSWindowAbove relativeTo:scrollView];
    NSRect newScrollFrame = [scrollView frame];
    newScrollFrame.size.height -= [self.addListView frame].size.height;
    NSRect newAddFrame = beforeAddFrame;
    newAddFrame.origin.y = NSMaxY(newScrollFrame);
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kCDMListsViewControllerAddListAnimationDuration];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [[self.addListField window] makeFirstResponder:self.addListField];
    }];
    [[scrollView animator] setFrame:newScrollFrame];
    [[self.addListView animator] setFrame:newAddFrame];
    [[_overlayView animator] setFrame:newScrollFrame];
    [[_overlayView animator] setAlphaValue:1.f];
    [NSAnimationContext endGrouping];
}

- (IBAction)closeAddList:(id)sender {
    if (![self.addListView superview]) { return; }
    NSScrollView *scrollView = [self.tableView enclosingScrollView];
    NSRect newScrollFrame = [scrollView frame];
    newScrollFrame.size.height += [self.addListView frame].size.height;
    [[scrollView animator] setFrame:newScrollFrame];
    NSRect newAddFrame = [self.addListView frame];
    newAddFrame.origin.y = NSMaxY(newScrollFrame);
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:kCDMListsViewControllerAddListAnimationDuration];
    [[NSAnimationContext currentContext] setCompletionHandler:^{
        [self.addListView removeFromSuperview];
        [_overlayView removeFromSuperview];
        _overlayView = nil;
    }];
    [[scrollView animator] setFrame:newScrollFrame];
    [[self.addListView animator] setFrame:newAddFrame];
    [[_overlayView animator] setFrame:newScrollFrame];
    [[_overlayView animator] setAlphaValue:0.f];
    [NSAnimationContext endGrouping];
}

- (IBAction)createList:(id)sender {
    NSString *listName = [self.addListField stringValue];
    [self.addListField setStringValue:@""];
    [[self.tableView window] makeFirstResponder:self.tableView];
    if ([listName length]) {
        CDKList *list = [[CDKList alloc] init];
        list.title = listName;
        list.position = [NSNumber numberWithInteger:INT32_MAX];
        list.user = [CDKUser currentUser];
        [list createWithSuccess:^{
            NSUInteger index = [[self.arrayController arrangedObjects] indexOfObject:list];
            if (index != NSNotFound) {
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
                [self tableViewSelectionDidChange:nil];
            }
            [self.tasksViewController focusTaskField:nil];
        } failure:^(AFJSONRequestOperation *remoteOperation, NSError *error) {
			NSLog(@"Error creating list: %@, %@", error, [error userInfo]);
			
			NSDictionary *response = remoteOperation.responseJSON;
			if ([response[@"error"] isEqualToString:@"plus_required"]) {
				NSInteger choice = NSRunAlertPanel(@"Cheddar Plus Required", @"You need Cheddar Plus to create more than 2 lists. Upgrading takes less than a minute", @"Upgrade", @"Later", nil);
				if (choice == NSAlertDefaultReturn) {
					[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://cheddarapp.com/account#plus"]];
				}
			} else {
				NSRunAlertPanel(@"Error", @"Sorry, there was an error creating your list. Try again later.", @"Darn", nil, nil);
			}
        }];
    }
    [self closeAddList:nil];
}


#pragma mark - NSControlTextEditingDelegate

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (command == @selector(cancelOperation:)) {
        [[control window] makeFirstResponder:[control window]];
        [self closeAddList:nil];
        return YES;
    }
    return NO;
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{
    id sender = [aNotification object];
    NSInteger row = [self.tableView rowForView:sender];
    if (row != -1) {
        CDKList *list = [[self.arrayController arrangedObjects] objectAtIndex:row];
        [list save];
        [list update];
    }
}

#pragma mark - NSTableViewDelegate

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self willChangeValueForKey:@"selectedList"];
    [self didChangeValueForKey:@"selectedList"];
    NSInteger selectedRow = [self.tableView selectedRow];
    if (selectedRow != -1) {
        CDKList *list = [[self.arrayController arrangedObjects] objectAtIndex:selectedRow];
        [self.tasksViewController setSelectedList:list];
    }
}


- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
	return [[CDMListTableRowView alloc] initWithFrame:CGRectZero];
}


- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
	return 38.0f;
}


#pragma mark - NSTableViewDataSource

- (BOOL)tableView:(NSTableView *)aTableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard {
    [pboard declareTypes:[NSArray arrayWithObject:kCDMListsDragTypeRearrange] owner:self];
	
    NSData *archivedData = [NSKeyedArchiver archivedDataWithRootObject:rowIndexes];
    [pboard setData:archivedData forType:kCDMListsDragTypeRearrange];
	
    return YES;
}


- (NSDragOperation)tableView:(NSTableView *)aTableView validateDrop:(id < NSDraggingInfo >)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)operation {
    NSPasteboard *pboard = [info draggingPasteboard];
    return ([pboard dataForType:kCDMTasksDragTypeMove] && operation == NSTableViewDropOn) || ([pboard dataForType:kCDMListsDragTypeRearrange] && operation == NSTableViewDropAbove);
}


- (BOOL)tableView:(NSTableView *)aTableView acceptDrop:(id < NSDraggingInfo >)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)operation {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    NSManagedObjectContext *context = [self.arrayController managedObjectContext];

	if (operation == NSTableViewDropAbove) {
        NSMutableArray *lists = [[self.arrayController arrangedObjects] mutableCopy];
        NSIndexSet *originalIndexes = [NSKeyedUnarchiver unarchiveObjectWithData:[pasteboard dataForType:kCDMListsDragTypeRearrange]];
        NSUInteger originalListIndex = [originalIndexes firstIndex];
        NSUInteger selectedRow = [aTableView selectedRow];
        NSUInteger destinationRow = (row > originalListIndex) ? row - 1 : row;
        [NSAnimationContext beginGrouping];
        [[NSAnimationContext currentContext] setDuration:kCDMTableViewAnimationDuration];
        [[NSAnimationContext currentContext] setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [[NSAnimationContext currentContext] setCompletionHandler:^{
            CDKList *list = [self.arrayController.arrangedObjects objectAtIndex:originalListIndex];
            [lists removeObject:list];
            [lists insertObject:list atIndex:destinationRow];
            
            NSInteger i = 0;
            for (list in lists) {
                list.position = [NSNumber numberWithInteger:i++];
            }
            [context save:nil];
            
            [CDKList sortWithObjects:lists];
            if (selectedRow == originalListIndex) {
                
                [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:destinationRow] byExtendingSelection:NO];
                [self tableViewSelectionDidChange:nil];
            }
        }];
        [self.tableView moveRowAtIndex:originalListIndex toIndex:destinationRow];
        [NSAnimationContext endGrouping];
    } else {
        NSURL *URI = [NSKeyedUnarchiver unarchiveObjectWithData:[pasteboard dataForType:kCDMTasksDragTypeMove]];
        NSPersistentStoreCoordinator *coordinator = [context persistentStoreCoordinator];
        NSManagedObjectID *objectID = [coordinator managedObjectIDForURIRepresentation:URI];

		CDKTask *task = (CDKTask*)[context existingObjectWithID:objectID error:nil];
        CDKList *list = [[self.arrayController arrangedObjects] objectAtIndex:row];
        [task moveToList:list];
    }
    return YES;
}

#pragma mark - NSMenuDelegate

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    BOOL enableItem = [self.tableView selectedRow] != -1 && [[self.tableView window] isVisible] && [[(CDKList *)[[_arrayController arrangedObjects] objectAtIndex:[self.tableView selectedRow]] tasks] count];
    for (NSMenuItem *item in [menu itemArray]) {
        [item setEnabled:enableItem];
        [item setTarget:self];
        switch ([item tag]) {
            case CDMListsRenameListItemTag:
                [item setAction:@selector(_renameList:)];
                break;
            case CDMListsArchiveAllTasksItemTag:
                [item setAction:@selector(_archiveAllTasks:)];
                break;
            case CDMListsArchiveCompletedTasksItemTag:
                [item setAction:@selector(_archiveCompletedTasks:)];
                break;
            case CDMListsArchiveListItemTag:
                [item setAction:@selector(_archiveList:)];
                break;
            default:
                break;
        }
    }
}


- (void)_renameList:(NSMenuItem *)menuItem {
    NSTableRowView *row = [self.tableView rowViewAtRow:[self.tableView selectedRow] makeIfNecessary:NO];
    NSTableCellView *cell = [row viewAtColumn:0];
    [[cell.textField window] makeFirstResponder:cell.textField];
}


- (void)_archiveAllTasks:(NSMenuItem *)menuItem {
    
    NSInteger row = [self.tableView selectedRow];
    CDKList *list = [[_arrayController arrangedObjects] objectAtIndex:row];
    [list archiveAllTasks];
}


- (void)_archiveCompletedTasks:(NSMenuItem *)menuItem {
    NSInteger row = [self.tableView selectedRow];
    CDKList *list = [[_arrayController arrangedObjects] objectAtIndex:row];
    [list archiveCompletedTasks];
}


- (void)_archiveList:(NSMenuItem *)menuItem {
    CDKList *list = [[_arrayController arrangedObjects] objectAtIndex:[self.tableView selectedRow]];
    list.archivedAt = [NSDate date];
	[list save];
	[list update];
    [self.tableView reloadData];
}

- (void)_setNoListsViewVisible:(BOOL)visible {
    if (visible && ![self.noListsView superview]) {
        if (!self.noListsView) {
			self.noListsView = [[CDMListsPlaceholderView alloc] init];
        }

		self.noListsView.frame = self.tableView.bounds;
		[self.tableView addSubview:self.noListsView];
    } else if (!visible && [self.noListsView superview]) {
        [self.noListsView removeFromSuperview];
    }
}


- (void)_setLoadingListsViewVisible:(BOOL)visible {
    if (visible && ![self.loadingListsView superview]) {
        _isLoading = YES;
        if (!self.loadingListsView) {
            self.loadingListsView = [[CDMLoadingView alloc] init];
        }

		self.loadingListsView.frame = self.tableView.bounds;
		[self.tableView addSubview:self.loadingListsView];
    } else if (!visible && [self.loadingListsView superview]) {
        _isLoading = NO;
        [self.loadingListsView removeFromSuperview];
    }
}


#pragma mark - Table View Menu Items

- (IBAction)renameList:(id)sender {
    NSInteger row = [self.tableView clickedRow];
    if (row != -1) {
        NSTableRowView *rowView = [self.tableView rowViewAtRow:row makeIfNecessary:NO];
        NSTableCellView *cellView = [rowView viewAtColumn:0];
        [[self.tableView window] makeFirstResponder:cellView.textField];
    }
}


- (IBAction)archiveList:(id)sener {
    NSInteger row = [self.tableView clickedRow];
    if (row != -1) {
        CDKList *list = [[self.arrayController arrangedObjects] objectAtIndex:row];
        list.archivedAt = [NSDate date];
        [list save];
        [list update];
        [self.tableView reloadData];
    }
}


- (IBAction)deleteList:(id)sender {
    NSInteger row = [self.tableView clickedRow];
    if (row != -1) {
        CDKList *list = [[self.arrayController arrangedObjects] objectAtIndex:row];
        [list delete];
        [self.tableView reloadData];
    }
}

@end
