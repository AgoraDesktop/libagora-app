/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 */
/*
 * NSOutlineView.h — the table's tree: items, children, disclosure and expansion.
 *
 * **AN OUTLINE IS A TABLE WITH A FLATTENED TREE.** The rows a person sees are a depth-first walk of the roots the
 * data source gives, expanded where an item is open. This class owns that walk, the expanded set, and the disclosure
 * triangle; everything else — columns, geometry, selection, the header and the ink — is `NSTableView`'s. That is why
 * it is a subclass and not a second table.
 *
 * **THE OUTLINE COLUMN IS THE ONE THAT GETS THE TRIANGLE AND THE INDENTATION.** `-outlineTableColumn` names it; the
 * cell frame in that column is inset by `level * indentationPerLevel` plus the triangle's box, and the triangle is
 * drawn in the space that was reserved. The other columns are untouched, which is what makes a source list's text
 * line up while its icons and dates do not move.
 *
 * **WHAT THIS SLICE DOES NOT DO**: drag and drop, persistent objects, autosaved expansion, variable row heights and
 * cell editing are the table's own absences and stay absent here. The outline's expansion set is by ITEM IDENTITY,
 * not by a persistent-object protocol, so reloading a model with new item objects starts collapsed — stated rather
 * than hidden behind an invented archive format.
 *
 * Written from `NSOutlineView.h` in the MacOSX10.6 SDK (see PROVENANCE.md).
 */
#ifndef APPKIT_NSOUTLINEVIEW_H
#define APPKIT_NSOUTLINEVIEW_H

#import <AppKit/NSTableView.h>

NS_ASSUME_NONNULL_BEGIN

@class NSMutableArray;
@class NSTableColumn;
@class NSOutlineView;

extern NSString *NSOutlineViewItemKey;
extern NSString *NSOutlineViewItemWillExpandNotification;
extern NSString *NSOutlineViewSelectionDidChangeNotification;
extern NSString *NSOutlineViewSelectionIsChangingNotification;
extern NSString *NSOutlineViewItemDidExpandNotification;
extern NSString *NSOutlineViewItemWillCollapseNotification;
extern NSString *NSOutlineViewItemDidCollapseNotification;

@protocol NSOutlineViewDataSource <NSObject>
@required
- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item;
- (nullable id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(nullable id)item;
@optional
- (nullable id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
		     byItem:(nullable id)item;
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(nullable id)object
     forTableColumn:(nullable NSTableColumn *)tableColumn byItem:(nullable id)item;
- (void)outlineView:(NSOutlineView *)outlineView sortDescriptorsDidChange:(NSArray *)oldDescriptors;
@end

@protocol NSOutlineViewDelegate <NSObject>
@optional
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(nullable NSTableColumn *)tableColumn item:(nullable id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(nullable NSTableColumn *)tableColumn
	       item:(nullable id)item;
- (BOOL)selectionShouldChangeInOutlineView:(NSOutlineView *)outlineView;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(nullable id)item;
- (nullable NSIndexSet *)outlineView:(NSOutlineView *)outlineView
    selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectTableColumn:(nullable NSTableColumn *)tableColumn;
- (void)outlineView:(NSOutlineView *)outlineView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn;
- (void)outlineView:(NSOutlineView *)outlineView didClickTableColumn:(NSTableColumn *)tableColumn;
- (void)outlineView:(NSOutlineView *)outlineView didDragTableColumn:(NSTableColumn *)tableColumn;
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(nullable id)item;
- (nullable NSCell *)outlineView:(NSOutlineView *)outlineView
	 dataCellForTableColumn:(nullable NSTableColumn *)tableColumn item:(nullable id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldExpandItem:(nullable id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(nullable id)item;
- (void)outlineView:(NSOutlineView *)outlineView willDisplayOutlineCell:(id)cell
     forTableColumn:(nullable NSTableColumn *)tableColumn item:(nullable id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(nullable id)item;
- (void)outlineViewSelectionDidChange:(NSNotification *)notification;
- (void)outlineViewSelectionIsChanging:(NSNotification *)notification;
@end

@interface NSOutlineView : NSTableView <NSSecureCoding>
{
	NSMutableArray *_rootItems;		/* RETAINED: the roots' borrowed objects are not retained, the array is */
	NSMutableArray *_flattenedItems;	/* RETAINED: item identity, depth-first */
	NSMutableArray *_flattenedLevels;	/* RETAINED: NSNumber per row */
	NSMutableArray *_expandedItems;		/* RETAINED: identity, not value equality */
	NSTableColumn *_outlineTableColumn;	/* NOT RETAINED: the table owns its columns */
	CGFloat _indentationPerLevel;
	BOOL _indentationMarkerFollowsCell;
	BOOL _autoresizesOutlineColumn;
	BOOL _autosaveExpandedItems;
	/* **AND THE DROP TARGET, WHICH IS A RECORD RATHER THAN A GESTURE.** `-setDropItem:dropChildIndex:` is what a data
	 * source (or the table's own drag path) says before the rows are redrawn: WHICH item the drop would land on and WHICH
	 * child index it would take. The item is borrowed — the tree owns its items — and -1 in the index means "on the item". */
	id _dropItem;			/* NOT RETAINED */
	NSInteger _dropChildIndex;
}

- (void)setDataSource:(nullable id <NSOutlineViewDataSource>)aSource;
- (nullable id <NSOutlineViewDataSource>)dataSource;
- (void)setDelegate:(nullable id <NSOutlineViewDelegate>)delegate;
- (nullable id <NSOutlineViewDelegate>)delegate;

/* THE COLUMN WHOSE TEXT IS INDENTED AND WHOSE ROWS GET THE TRIANGLE. */
- (void)setOutlineTableColumn:(nullable NSTableColumn *)outlineTableColumn;
- (nullable NSTableColumn *)outlineTableColumn;

/* THE TREE. `item` nil is the ROOT in the data source's own vocabulary; `-itemAtRow:` names the item at a visible
 * row and `-rowForItem:` answers -1 when an item is collapsed or not in the tree. */
- (BOOL)isExpandable:(nullable id)item;
- (void)expandItem:(nullable id)item expandChildren:(BOOL)expandChildren;
- (void)expandItem:(nullable id)item;
- (void)collapseItem:(nullable id)item collapseChildren:(BOOL)collapseChildren;
- (void)collapseItem:(nullable id)item;
- (void)reloadItem:(nullable id)item reloadChildren:(BOOL)reloadChildren;
- (void)reloadItem:(nullable id)item;
- (nullable id)parentForItem:(nullable id)item;
- (nullable id)itemAtRow:(NSInteger)row;
- (NSInteger)rowForItem:(nullable id)item;
- (NSInteger)levelForItem:(nullable id)item;
- (NSInteger)levelForRow:(NSInteger)row;
- (BOOL)isItemExpanded:(nullable id)item;

/* THE INDENTATION AND THE MARKER. */
- (void)setIndentationPerLevel:(CGFloat)indentationPerLevel;
- (CGFloat)indentationPerLevel;
- (void)setIndentationMarkerFollowsCell:(BOOL)drawInCell;
- (BOOL)indentationMarkerFollowsCell;
- (void)setAutoresizesOutlineColumn:(BOOL)resize;
- (BOOL)autoresizesOutlineColumn;

/* THE DISCLOSURE'S BOX FOR A ROW, in the table's coordinates. */
- (NSRect)frameOfOutlineCellAtRow:(NSInteger)row;

/* THE EXPANSION FLAGS THIS SLICE RECORDS BUT DOES NOT PERSIST. */
- (BOOL)autosaveExpandedItems;
- (void)setAutosaveExpandedItems:(BOOL)save;

/* **THE DROP TARGET, SET AND NOT DRAWN.** Apple's door records where a drag would land so the table can draw its
 * insertion indicator; this tier records the pair so a data source and a subclass can read it back, and the indicator
 * itself is the table row drawing's, which follows the same record when it arrives. */
- (void)setDropItem:(nullable id)item dropChildIndex:(NSInteger)index;

/* **AND THE AUTO-EXPANDED COLLAPSE QUESTION, WHICH IS A POLICY THE APP ANSWERS.** Apple's default is YES (items a drag
 * expanded are collapsed again when it ends); `deposited` distinguishes a completed drop from a cancelled one, and both
 * answer YES here because this tier has no auto-expansion to collapse — the flag is the app's to override. */
- (BOOL)shouldCollapseAutoExpandedItemsForDeposited:(BOOL)deposited;

@end

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSOUTLINEVIEW_H */
