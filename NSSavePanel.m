/*
 * NSSavePanel — a panel over the file system: the listing, the name, the accept, and the three ways to run it.
 *
 * Copyright © 2026 Kyle J. Cardoza. MIT licensed — see LICENSE.
 * SPDX-License-Identifier: MIT
 *
 * One browser serves both panels. The listing is the directory's contents with the delegate's filters applied, sorted
 * with the delegate's comparator when it answers one; a directory is navigated or chosen by the open panel's flags; the
 * accept path builds a URL, appends the required extension for a save, offers the proposed name to the delegate, has the
 * URL validated, and only then finishes. The panel finishes through `-endSheet:returnCode:` when it is a sheet, through
 * `-stopModalWithCode:` when it is modal, and by ordering out and calling the block when it is modeless.
 */
#import "NSSavePanel.h"
#import "NSSavePanel_internal.h"
#import "NSApplication.h"
#import "NSEvent.h"
#import "NSButton.h"
#import "NSFont.h"
#import "NSGraphics.h"
#import "NSScrollView.h"
#import "NSTableColumn.h"
#import "NSTableView.h"
#import "NSTextField.h"
#import "NSView.h"
#import "NSWindow.h"

#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSData.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSString.h>
#import <Foundation/NSURL.h>

#include <Block.h>	/* Block_copy/Block_release: this runtime's blocks are not `-copy` objects */
#include <stdio.h>

#define AG_PANEL_WIDTH 500.0
#define AG_PANEL_HEIGHT 440.0
#define AG_PANEL_MARGIN 12.0
#define AG_PANEL_ACCESSORY_HEIGHT 44.0

/* A LABEL IS A FIELD WITH ITS FOUR EDGES TURNED OFF, the same shape the demonstration uses for its captions. */
static NSTextField *fn_label(NSRect frame, NSString *text, NSFont *font)
{
	NSTextField *field = [[NSTextField alloc] initWithFrame:frame];

	[field setStringValue:(text != nil) ? text : @""];
	[field setEditable:NO];
	[field setSelectable:NO];
	[field setBordered:NO];
	[field setBezeled:NO];
	[field setDrawsBackground:NO];
	if (font != nil) {
		[field setFont:font];
	}
	return field;
}

static NSButton *fn_button(NSRect frame, NSString *title, id target, SEL action)
{
	NSButton *button = [[NSButton alloc] initWithFrame:frame];

	[button setTitle:title];
	[button setTarget:target];
	[button setAction:action];
	return button;
}

/* THE TWO COMPARISONS, with the delegate's deprecated one consulted first when it answers. */
static NSComparisonResult fn_compare_names(NSSavePanel *panel, id delegate, NSString *left, NSString *right)
{
	if (delegate != nil
	    && [delegate respondsToSelector:@selector(panel:compareFilename:with:caseSensitive:)]) {
		return [delegate panel:panel compareFilename:left with:right caseSensitive:NO];
	}
	return [left caseInsensitiveCompare:right];
}

static NSArray *fn_sorted_names(NSSavePanel *panel, id delegate, NSArray *names)
{
	NSMutableArray *sorted = [NSMutableArray array];
	NSUInteger i;

	for (i = 0; i < [names count]; i++) {
		NSString *name = [names objectAtIndex:i];
		NSUInteger at = 0;

		while (at < [sorted count]
		       && fn_compare_names(panel, delegate, [sorted objectAtIndex:at], name) != NSOrderedDescending) {
			at++;
		}
		[sorted insertObject:name atIndex:at];
	}
	return sorted;
}

static BOOL fn_extension_is_allowed(NSString *name, NSArray *types)
{
	NSString *extension = [name pathExtension];
	NSUInteger i;

	if ([types count] == 0) {
		return YES;
	}
	if ([extension length] == 0) {
		return NO;
	}
	for (i = 0; i < [types count]; i++) {
		if ([[types objectAtIndex:i] caseInsensitiveCompare:extension] == NSOrderedSame) {
			return YES;
		}
	}
	return NO;
}

/* ==================================================================================================
 * THE TABLE'S DATA SOURCE. It borrows the panel (the panel owns it), so the cycle is one way.
 * ================================================================================================ */

@interface AGSavePanelSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
{
	NSSavePanel *_panel;
}
- (instancetype)initWithPanel:(NSSavePanel *)panel;
@end

@implementation AGSavePanelSource

- (instancetype)initWithPanel:(NSSavePanel *)panel
{
	self = [super init];
	if (self != nil) {
		_panel = panel;	/* NOT RETAINED: the panel owns this object */
	}
	return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	(void)tableView;
	return [_panel cg_entryCount];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	return [_panel cg_displayNameAtIndex:row];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell
   forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	(void)tableView;
	(void)tableColumn;
	if ([_panel cg_entryIsDirectoryAtIndex:row]) {
		[cell setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
	} else {
		[cell setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	(void)notification;
	[_panel cg_selectionDidChange];
}

@end

/* ================================================================================================== */

@implementation NSSavePanel

+ (NSSavePanel *)savePanel
{
	return [[[NSSavePanel alloc] init] autorelease];
}

- (instancetype)init
{
	return [self initWithContentRect:NSMakeRect(0.0, 0.0, AG_PANEL_WIDTH, AG_PANEL_HEIGHT)
			       styleMask:(NSTitledWindowMask | NSClosableWindowMask)
				 backing:NSBackingStoreBuffered
				   defer:NO];
}

- (instancetype)initWithContentRect:(NSRect)contentRect
			  styleMask:(NSUInteger)styleMask
			    backing:(NSBackingStoreType)bufferingType
			      defer:(BOOL)flag
{
	self = [super initWithContentRect:contentRect styleMask:styleMask backing:bufferingType defer:flag];
	if (self != nil) {
		[self setReleasedWhenClosed:NO];
		[self cg_buildWithSize:contentRect.size];
	}
	return self;
}

- (void)dealloc
{
	[_directoryURL release];
	[_url release];
	[_urls release];
	[_allowedFileTypes release];
	[_requiredFileType release];
	[_prompt release];
	[_nameFieldLabel release];
	[_message release];
	[_accessoryView release];
	[_entries release];
	[_source release];
	Block_release((const void *)_completionHandler);
	[super dealloc];
}

/* ---- THE LISTING ---------------------------------------------------------------------------------- */

- (void)cg_buildWithSize:(NSSize)size
{
	CGFloat width = (size.width > 100.0) ? size.width : AG_PANEL_WIDTH;
	CGFloat height = (size.height > 100.0) ? size.height : AG_PANEL_HEIGHT;
	NSRect bounds = NSMakeRect(0.0, 0.0, width, height);
	NSView *content = [[NSView alloc] initWithFrame:bounds];
	CGFloat tableHeight = (height - 72.0) - 150.0;
	NSTableColumn *column;
	NSScrollView *scroll;
	NSTableView *table;
	NSTextField *field;
	NSButton *button;

	[self setContentView:content];
	[content release];
	[self setTitle:@"Save"];

	_directoryURL = [[NSURL fileURLWithPath:NSHomeDirectory()] retain];
	_prompt = [@"Save" copy];
	_nameFieldLabel = [@"Save As:" copy];
	_canCreateDirectories = YES;
	_allowsOtherFileTypes = NO;
	_canChooseFiles = YES;
	_canChooseDirectories = NO;
	_allowsMultipleSelection = NO;
	_resolvesAliases = YES;

	/* THE MESSAGE, the line that says what the panel is for (a save panel's "Choose a name" and a caller's own text). */
	field = fn_label(NSMakeRect(AG_PANEL_MARGIN, height - 30.0, width - 2.0 * AG_PANEL_MARGIN, 18.0),
			 @"", [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
	_messageLabel = field;
	[content addSubview:field];
	[field release];

	/* THE DIRECTORY AND THE WAY UP. */
	field = fn_label(NSMakeRect(AG_PANEL_MARGIN, height - 62.0, width - 2.0 * AG_PANEL_MARGIN - 70.0, 22.0),
			 @"", [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
	_pathLabel = field;
	[content addSubview:field];
	[field release];

	button = fn_button(NSMakeRect(width - AG_PANEL_MARGIN - 58.0, height - 62.0, 58.0, 24.0),
			   @"Up", self, @selector(cg_goUp:));
	_upButton = button;
	[content addSubview:button];
	[button release];

	/* THE LIST. */
	scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(AG_PANEL_MARGIN, 150.0,
							       width - 2.0 * AG_PANEL_MARGIN, tableHeight)];
	[scroll setBorderType:NSBezelBorder];
	[scroll setHasVerticalScroller:YES];
	table = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0, 0.0, width - 2.0 * AG_PANEL_MARGIN - 15.0,
							     tableHeight)];
	[table setRowHeight:20.0];
	[table setAllowsEmptySelection:YES];
	[table setAllowsMultipleSelection:NO];
	[table setHeaderView:nil];
	column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	[column setWidth:width - 2.0 * AG_PANEL_MARGIN - 15.0];
	[table addTableColumn:column];
	[column release];
	_source = [[AGSavePanelSource alloc] initWithPanel:self];
	[table setDataSource:_source];
	[table setDelegate:_source];
	[table setDoubleAction:@selector(cg_tableDoubleClicked:)];
	[scroll setDocumentView:table];
	_table = table;
	[content addSubview:scroll];
	_scroll = scroll;
	[scroll release];

	/* THE NAME. */
	field = fn_label(NSMakeRect(AG_PANEL_MARGIN, 118.0, 72.0, 22.0), @"Save As:",
			 [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]);
	_nameLabel = field;
	[content addSubview:field];
	[field release];

	field = [[NSTextField alloc] initWithFrame:NSMakeRect(AG_PANEL_MARGIN + 76.0, 118.0,
							      width - 2.0 * AG_PANEL_MARGIN - 76.0, 22.0)];
	[field setStringValue:@"Untitled"];
	_nameField = field;
	[content addSubview:field];
	[field release];

	button = fn_button(NSMakeRect(AG_PANEL_MARGIN + 76.0, 96.0, 220.0, 18.0), @"Hide extension",
			   self, @selector(cg_toggleExtension:));
	[button setButtonType:NSSwitchButton];
	[button setState:NSOffState];
	[button setHidden:YES];
	_extensionButton = button;
	[content addSubview:button];
	[button release];

	/* THE BUTTONS. */
	button = fn_button(NSMakeRect(AG_PANEL_MARGIN, 12.0, 110.0, 24.0), @"New Folder",
			   self, @selector(cg_newFolder:));
	_newFolderButton = button;
	[content addSubview:button];
	[button release];

	button = fn_button(NSMakeRect(width - AG_PANEL_MARGIN - 206.0, 12.0, 90.0, 24.0), @"Cancel",
			   self, @selector(cancel:));
	_cancelButton = button;
	[content addSubview:button];
	[button release];

	button = fn_button(NSMakeRect(width - AG_PANEL_MARGIN - 110.0, 12.0, 90.0, 24.0), @"Save",
			   self, @selector(ok:));
	_okButton = button;
	[content addSubview:button];
	[button release];

	[self cg_updateLabels];
	[self cg_reloadEntries];
}

- (void)cg_updateLabels
{
	if (_messageLabel != nil) {
		[_messageLabel setStringValue:(_message != nil) ? _message : @""];
	}
	if (_nameLabel != nil) {
		[_nameLabel setStringValue:(_nameFieldLabel != nil) ? _nameFieldLabel : @""];
	}
	if (_okButton != nil) {
		[_okButton setTitle:(_prompt != nil) ? _prompt : (_isOpenPanel ? @"Open" : @"Save")];
	}
	if (_pathLabel != nil) {
		[_pathLabel setStringValue:(_directoryURL != nil) ? [_directoryURL path] : @""];
	}
}

- (void)cg_reloadEntries
{
	NSMutableArray *directories = [NSMutableArray array];
	NSMutableArray *files = [NSMutableArray array];
	NSMutableArray *entries;
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *path = (_directoryURL != nil) ? [_directoryURL path] : nil;
	NSArray *names;
	NSUInteger i;

	[_entries release];
	_entries = nil;
	if (path == nil) {
		_entries = [[NSArray alloc] init];
		if (_table != nil) {
			[_table reloadData];
		}
		return;
	}
	/* ".." IS THE WAY UP IN THE LIST, and the root has no parent to go to. */
	if (![path isEqualToString:@"/"]) {
		[directories addObject:[NSDictionary dictionaryWithObjectsAndKeys:
			@"..", @"name", [NSNumber numberWithBool:YES], @"dir", nil]];
	}
	names = [manager contentsOfDirectoryAtPath:path error:NULL];
	names = fn_sorted_names(self, _panelDelegate, (names != nil) ? names : [NSArray array]);
	for (i = 0; i < [names count]; i++) {
		NSString *name = [names objectAtIndex:i];
		NSString *fullPath;
		BOOL isDirectory = NO;
		NSDictionary *entry;

		if (!_showsHiddenFiles && [name hasPrefix:@"."]) {
			continue;
		}
		fullPath = [path stringByAppendingPathComponent:name];
		if (![manager fileExistsAtPath:fullPath isDirectory:&isDirectory]) {
			continue;
		}
		if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:shouldShowFilename:)]
		    && ![(_panelDelegate) panel:self shouldShowFilename:fullPath]) {
			continue;
		}
		if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:shouldEnableURL:)]
		    && ![(_panelDelegate) panel:self shouldEnableURL:[NSURL fileURLWithPath:fullPath]]) {
			continue;
		}
		/* **THE OPEN PANEL FILTERS BY TYPE; THE SAVE PANEL DOES NOT.** A save panel must be able to name a file it is
		 * about to overwrite even when its extension is not the preferred one; an open panel is choosing something to
		 * read, so a type it cannot read is not offered. `-allowsOtherFileTypes` turns the filter off. */
		if (!isDirectory && _isOpenPanel && [_allowedFileTypes count] > 0 && !_allowsOtherFileTypes
		    && !fn_extension_is_allowed(name, _allowedFileTypes)) {
			continue;
		}
		entry = [NSDictionary dictionaryWithObjectsAndKeys:
			name, @"name", [NSNumber numberWithBool:isDirectory], @"dir", nil];
		[isDirectory ? directories : files addObject:entry];
	}
	entries = [NSMutableArray arrayWithArray:directories];
	[entries addObjectsFromArray:files];
	_entries = [entries copy];
	if (_table != nil) {
		[_table reloadData];
		[_table deselectAll:nil];
	}
}

- (NSInteger)cg_entryCount
{
	return (NSInteger)[_entries count];
}

- (NSString *)cg_entryNameAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_entries count]) {
		return nil;
	}
	return [[_entries objectAtIndex:(NSUInteger)index] objectForKey:@"name"];
}

- (BOOL)cg_entryIsDirectoryAtIndex:(NSInteger)index
{
	if (index < 0 || index >= (NSInteger)[_entries count]) {
		return NO;
	}
	return [[[_entries objectAtIndex:(NSUInteger)index] objectForKey:@"dir"] boolValue];
}

- (NSString *)cg_displayNameAtIndex:(NSInteger)index
{
	NSString *name = [self cg_entryNameAtIndex:index];

	if (name != nil && [self cg_entryIsDirectoryAtIndex:index]) {
		return [name stringByAppendingString:@"/"];
	}
	return name;
}

- (NSArray *)cg_visibleFilenames
{
	NSMutableArray *names = [NSMutableArray array];
	NSInteger i;

	for (i = 0; i < [self cg_entryCount]; i++) {
		[names addObject:[self cg_displayNameAtIndex:i]];
	}
	return names;
}

- (BOOL)cg_selectFilename:(NSString *)name
{
	return [self cg_selectFilenames:[NSArray arrayWithObject:name]];
}

- (BOOL)cg_selectFilenames:(NSArray *)names
{
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	NSInteger i;
	BOOL found = NO;

	for (i = 0; i < [self cg_entryCount]; i++) {
		NSString *raw = [self cg_entryNameAtIndex:i];
		NSString *display = [self cg_displayNameAtIndex:i];
		NSUInteger j;

		for (j = 0; j < [names count]; j++) {
			NSString *wanted = [names objectAtIndex:j];

			if ([wanted isEqualToString:raw] || [wanted isEqualToString:display]) {
				[indexes addIndex:(NSUInteger)i];
				found = YES;
			}
		}
	}
	if (!found) {
		return NO;
	}
	[_table selectRowIndexes:indexes byExtendingSelection:NO];
	[_table scrollRowToVisible:(NSInteger)[indexes firstIndex]];
	return YES;
}

/* ---- NAVIGATION ----------------------------------------------------------------------------------- */

- (void)cg_navigateToURL:(NSURL *)url
{
	NSURL *standard;
	NSURL *old;

	if (url == nil) {
		return;
	}
	standard = [url standardizedURL];
	old = _directoryURL;
	_directoryURL = [(standard != nil) ? standard : url retain];

	[_url release];
	_url = nil;
	[_urls release];
	_urls = nil;
	[self cg_reloadEntries];
	[self cg_updateLabels];
	[old release];

	if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:didChangeToDirectoryURL:)]) {
		[_panelDelegate panel:self didChangeToDirectoryURL:_directoryURL];
	}
	if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:directoryDidChange:)]) {
		[_panelDelegate panel:self directoryDidChange:[_directoryURL path]];
	}
}

- (void)cg_goUp:(id)sender
{
	(void)sender;
	[self cg_navigateToURL:[_directoryURL URLByDeletingLastPathComponent]];
}

- (void)cg_newFolder:(id)sender
{
	NSFileManager *manager = [NSFileManager defaultManager];
	NSString *path = [_directoryURL path];
	NSString *name = @"untitled folder";
	NSInteger suffix = 2;

	(void)sender;
	if (!_canCreateDirectories || path == nil) {
		return;
	}
	while ([manager fileExistsAtPath:[path stringByAppendingPathComponent:name]]) {
		name = [NSString stringWithFormat:@"untitled folder %ld", (long)suffix++];
	}
	if ([manager createDirectoryAtPath:[path stringByAppendingPathComponent:name]
	       withIntermediateDirectories:NO attributes:nil error:NULL]) {
		[self cg_reloadEntries];
		(void)[self cg_selectFilename:name];
	}
}

/* ---- SELECTION ------------------------------------------------------------------------------------ */

- (void)cg_selectionDidChange
{
	NSInteger row = [_table selectedRow];

	if (row >= 0 && ![self cg_entryIsDirectoryAtIndex:row]) {
		[self setNameFieldStringValue:[self cg_entryNameAtIndex:row]];
	}
	if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panelSelectionDidChange:)]) {
		[_panelDelegate panelSelectionDidChange:self];
	}
}

- (void)cg_tableDoubleClicked:(id)sender
{
	(void)sender;
	if ([_table clickedRow] < 0) {
		return;
	}
	if ([self cg_entryIsDirectoryAtIndex:[_table clickedRow]]) {
		[self cg_navigateToURL:[self cg_urlForName:[self cg_entryNameAtIndex:[_table clickedRow]]]];
		return;
	}
	(void)[self cg_accept];
}

/* ---- THE ACCEPT ----------------------------------------------------------------------------------- */

- (NSURL *)cg_urlForName:(NSString *)name
{
	NSURL *url;
	NSURL *standard;

	if (name == nil) {
		return nil;
	}
	name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) {
		return nil;
	}
	if ([name isAbsolutePath]) {
		url = [NSURL fileURLWithPath:name];
	} else {
		url = [_directoryURL URLByAppendingPathComponent:name];
	}
	standard = [url standardizedURL];
	return (standard != nil) ? standard : url;
}

- (BOOL)cg_validateURL:(NSURL *)url
{
	if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:validateURL:error:)]) {
		NSError *error = nil;

		if (![_panelDelegate panel:self validateURL:url error:&error]) {
			fprintf(stderr, "save panel: the delegate refused \"%s\": %s\n",
				[[url path] UTF8String],
				(error != nil) ? [[error localizedDescription] UTF8String] : "no reason given");
			return NO;
		}
		return YES;
	}
	if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:isValidFilename:)]) {
		return [_panelDelegate panel:self isValidFilename:[[url path] lastPathComponent]];
	}
	return YES;
}

- (void)cg_appendURLForEntryAtIndex:(NSInteger)index to:(NSMutableArray *)urls
{
	NSURL *url;
	BOOL isDirectory = [self cg_entryIsDirectoryAtIndex:index];

	if (isDirectory ? !_canChooseDirectories : !_canChooseFiles) {
		return;
	}
	url = [self cg_urlForName:[self cg_entryNameAtIndex:index]];
	if (url != nil) {
		[urls addObject:url];
	}
}

- (BOOL)cg_accept
{
	NSInteger row = [_table selectedRow];
	BOOL selectedIsDirectory = (row >= 0 && [self cg_entryIsDirectoryAtIndex:row]);
	NSString *name = [self nameFieldStringValue];

	/* **A DIRECTORY IN A SAVE PANEL IS ALWAYS A WAY IN**, and in an open panel it is a way in unless the panel is allowed
	 * to choose directories. The same press does the same thing on both panels when the flags say the same thing. */
	if (selectedIsDirectory && (!_isOpenPanel || !_canChooseDirectories)) {
		[self cg_navigateToURL:[self cg_urlForName:[self cg_entryNameAtIndex:row]]];
		return NO;
	}

	if (!_isOpenPanel) {
		NSURL *url;
		NSString *required;
		NSString *extension;
		BOOL isDirectory = NO;

		if ([name length] == 0) {
			return NO;
		}
		url = [self cg_urlForName:name];
		if (url == nil) {
			return NO;
		}
		if ([[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDirectory]
		    && isDirectory) {
			[self cg_navigateToURL:url];
			return NO;
		}
		required = ([_requiredFileType length] > 0) ? _requiredFileType
			: ([_allowedFileTypes count] > 0 ? [_allowedFileTypes objectAtIndex:0] : nil);
		extension = [url pathExtension];
		if ([required length] > 0) {
			if ([extension length] == 0) {
				url = [url URLByAppendingPathExtension:required];
			} else if (!_allowsOtherFileTypes
				   && [extension caseInsensitiveCompare:required] != NSOrderedSame) {
				url = [[url URLByDeletingPathExtension] URLByAppendingPathExtension:required];
			}
			if (url == nil) {
				return NO;
			}
		}
		if (_panelDelegate != nil && [_panelDelegate respondsToSelector:@selector(panel:userEnteredFilename:confirmed:)]) {
			NSString *renamed = [_panelDelegate panel:self userEnteredFilename:[[url path] lastPathComponent]
						    confirmed:YES];

			if (renamed != nil) {
				url = [self cg_urlForName:renamed];
			}
		}
		if (url == nil || ![self cg_validateURL:url]) {
			return NO;
		}
		[self setNameFieldStringValue:[[url path] lastPathComponent]];
		[_url release];
		_url = [url retain];
		[_urls release];
		_urls = nil;
		[self cg_finishWithCode:NSOKButton];
		return YES;
	}

	/* THE OPEN PANEL: THE SELECTION, OR THE TYPED NAME WHEN NOTHING IS SELECTED. */
	{
		NSMutableArray *chosen = [NSMutableArray array];
		NSMutableArray *accepted = [NSMutableArray array];
		NSIndexSet *rows = [_table selectedRowIndexes];
		NSURL *typed;
		BOOL typedIsDirectory = NO;
		NSUInteger i;

		if (_allowsMultipleSelection) {
			for (i = 0; i < (NSUInteger)[self cg_entryCount]; i++) {
				if ([rows containsIndex:i]) {
					[self cg_appendURLForEntryAtIndex:(NSInteger)i to:chosen];
				}
			}
		} else if (row >= 0) {
			[self cg_appendURLForEntryAtIndex:row to:chosen];
		}
		if ([chosen count] == 0) {
			if ([name length] == 0) {
				return NO;
			}
			typed = [self cg_urlForName:name];
			if (typed == nil
			    || ![[NSFileManager defaultManager] fileExistsAtPath:[typed path] isDirectory:&typedIsDirectory]) {
				return NO;
			}
			if (typedIsDirectory) {
				if (!_canChooseDirectories) {
					[self cg_navigateToURL:typed];
					return NO;
				}
			} else if (!_canChooseFiles) {
				return NO;
			}
			[chosen addObject:typed];
		}
		for (i = 0; i < [chosen count]; i++) {
			NSURL *url = [chosen objectAtIndex:i];

			if (_resolvesAliases) {
				NSURL *resolved = [url URLByResolvingSymlinksInPath];

				if (resolved != nil) {
					url = resolved;
				}
			}
			if (![self cg_validateURL:url]) {
				return NO;
			}
			[accepted addObject:url];
		}
		if ([accepted count] == 0) {
			return NO;
		}
		[_urls release];
		_urls = [accepted copy];
		[_url release];
		_url = [[accepted objectAtIndex:0] retain];
		[self setNameFieldStringValue:[[_url path] lastPathComponent]];
		[self cg_finishWithCode:NSOKButton];
		return YES;
	}
}

/* ---- RUNNING IT ----------------------------------------------------------------------------------- */

- (void)cg_retainSession
{
	if (!_sessionRetained) {
		_sessionRetained = YES;
		[self retain];
	}
}

- (void)cg_callCompletion:(NSInteger)code
{
	if (_completionHandler != nil) {
		id handler = _completionHandler;

		_completionHandler = nil;
		((void (^)(NSInteger))handler)(code);
		Block_release((const void *)handler);
	}
	if (_sessionRetained) {
		_sessionRetained = NO;
		[self autorelease];
	}
}

- (void)cg_finishWithCode:(NSInteger)code
{
	_modalReturnCode = code;
	if (_sheetParent != nil) {
		[[NSApplication sharedApplication] endSheet:self returnCode:code];
		return;
	}
	if (_runningModal) {
		_runningModal = NO;
		[self orderOut:nil];
		[[NSApplication sharedApplication] stopModalWithCode:code];
		return;
	}
	[self orderOut:nil];
	[self cg_callCompletion:code];
}

- (void)cg_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)code contextInfo:(void *)contextInfo
{
	(void)sheet;
	(void)contextInfo;
	[self orderOut:nil];
	_sheetParent = nil;
	[self cg_callCompletion:code];
}

- (void)ok:(id)sender
{
	(void)sender;
	(void)[self cg_accept];
}

- (void)cancel:(id)sender
{
	(void)sender;
	[_url release];
	_url = nil;
	[_urls release];
	_urls = nil;
	[self cg_finishWithCode:NSCancelButton];
}

- (void)beginSheetModalForWindow:(NSWindow *)window completionHandler:(void (^)(NSInteger result))handler
{
	if (window == nil) {
		return;
	}
	[self cg_retainSession];
	Block_release((const void *)_completionHandler);
	_completionHandler = (handler != NULL) ? Block_copy((const void *)handler) : nil;
	_sheetParent = window;
	[[NSApplication sharedApplication] beginSheet:self modalForWindow:window modalDelegate:self
				       didEndSelector:@selector(cg_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
	[self selectText:nil];
}

- (void)beginWithCompletionHandler:(void (^)(NSInteger result))handler
{
	[self cg_retainSession];
	Block_release((const void *)_completionHandler);
	_completionHandler = (handler != NULL) ? Block_copy((const void *)handler) : nil;
	[self center];
	[self makeKeyAndOrderFront:nil];
	[self selectText:nil];
}

- (NSInteger)runModal
{
	NSInteger code;

	[self center];
	[self makeKeyAndOrderFront:nil];
	[self selectText:nil];
	_runningModal = YES;
	code = [[NSApplication sharedApplication] runModalForWindow:self];
	_runningModal = NO;
	return code;
}

- (void)selectText:(id)sender
{
	(void)sender;
	if (_nameField != nil) {
		[self makeFirstResponder:_nameField];
		[_nameField selectText:nil];
	}
}

- (void)keyDown:(NSEvent *)event
{
	NSString *characters = [event characters];

	if ([characters length] > 0) {
		unichar key = [characters characterAtIndex:0];

		if (key == NSCarriageReturnCharacter || key == NSEnterCharacter) {
			[self ok:nil];
			return;
		}
		if (key == 0x1b) {	/* Escape, with no named constant in this header's era */
			[self cancel:nil];
			return;
		}
	}
	[super keyDown:event];
}

/* ---- THE PANEL'S PIECES --------------------------------------------------------------------------- */

- (NSURL *)URL
{
	return _url;
}

- (NSURL *)directoryURL
{
	return _directoryURL;
}

- (void)setDirectoryURL:(NSURL *)url
{
	if (url != nil && ![url isEqual:_directoryURL]) {
		[self cg_navigateToURL:url];
	}
}

- (NSArray *)allowedFileTypes
{
	return _allowedFileTypes;
}

- (void)setAllowedFileTypes:(NSArray *)types
{
	NSArray *held = [types copy];

	[_allowedFileTypes release];
	_allowedFileTypes = held;
	if (_isOpenPanel) {
		[self cg_reloadEntries];
	}
}

- (BOOL)allowsOtherFileTypes { return _allowsOtherFileTypes; }
- (void)setAllowsOtherFileTypes:(BOOL)flag
{
	_allowsOtherFileTypes = flag;
	if (_isOpenPanel) {
		[self cg_reloadEntries];
	}
}

- (BOOL)showsHiddenFiles { return _showsHiddenFiles; }
- (void)setShowsHiddenFiles:(BOOL)flag
{
	_showsHiddenFiles = flag;
	[self cg_reloadEntries];
}

- (void)validateVisibleColumns
{
	[self cg_reloadEntries];
}

- (NSView *)accessoryView { return _accessoryView; }
- (void)setAccessoryView:(NSView *)view
{
	if (view == _accessoryView) {
		return;
	}
	[_accessoryView removeFromSuperview];
	[_accessoryView release];
	_accessoryView = [view retain];
	if (_accessoryView != nil) {
		CGFloat width = [[self contentView] frame].size.width;

		[_accessoryView setFrame:NSMakeRect(AG_PANEL_MARGIN, AG_PANEL_ACCESSORY_HEIGHT, width - 2.0 * AG_PANEL_MARGIN,
						    AG_PANEL_ACCESSORY_HEIGHT)];
		[[self contentView] addSubview:_accessoryView];
	}
}

- (id <NSOpenSavePanelDelegate>)delegate { return _panelDelegate; }
- (void)setDelegate:(id <NSOpenSavePanelDelegate>)delegate
{
	_panelDelegate = delegate;
	/* **THE DELEGATE FILTERS THE LISTING, SO SETTING IT RE-READS THE LISTING.** A panel opened before its delegate was
	 * wired would otherwise show entries the delegate would have hidden until the next navigation — which is exactly the
	 * order an application uses when it builds a panel, sets its types and then sets the delegate. */
	if (_table != nil) {
		[self cg_reloadEntries];
	}
}

- (BOOL)canCreateDirectories { return _canCreateDirectories; }
- (void)setCanCreateDirectories:(BOOL)flag
{
	_canCreateDirectories = flag;
	[_newFolderButton setHidden:!flag];
}

- (BOOL)canSelectHiddenExtension { return _canSelectHiddenExtension; }
- (void)setCanSelectHiddenExtension:(BOOL)flag
{
	_canSelectHiddenExtension = flag;
	[_extensionButton setHidden:!flag];
}

- (BOOL)isExtensionHidden { return _extensionHidden; }
- (void)setExtensionHidden:(BOOL)flag
{
	_extensionHidden = flag;
	[_extensionButton setState:flag ? NSOnState : NSOffState];
}

- (NSString *)prompt { return _prompt; }
- (void)setPrompt:(NSString *)prompt
{
	NSString *held = [prompt copy];

	[_prompt release];
	_prompt = held;
	[self cg_updateLabels];
}

- (NSString *)title { return [super title]; }
- (void)setTitle:(NSString *)title { [super setTitle:title]; }

- (NSString *)nameFieldLabel { return _nameFieldLabel; }
- (void)setNameFieldLabel:(NSString *)label
{
	NSString *held = [label copy];

	[_nameFieldLabel release];
	_nameFieldLabel = held;
	[self cg_updateLabels];
}

- (NSString *)nameFieldStringValue { return [_nameField stringValue]; }
- (void)setNameFieldStringValue:(NSString *)value
{
	[_nameField setStringValue:(value != nil) ? value : @""];
}

- (NSString *)message { return _message; }
- (void)setMessage:(NSString *)message
{
	NSString *held = [message copy];

	[_message release];
	_message = held;
	[self cg_updateLabels];
}

- (void)cg_toggleExtension:(id)sender
{
	(void)sender;
	_extensionHidden = ([_extensionButton state] == NSOnState);
}

/* ---- THE 10.3 SPELLINGS --------------------------------------------------------------------------- */

- (NSString *)filename
{
	if (_isOpenPanel) {
		return (_url != nil) ? [[_url path] lastPathComponent] : nil;
	}
	return [self nameFieldStringValue];
}

- (NSString *)directory
{
	return (_directoryURL != nil) ? [_directoryURL path] : nil;
}

- (void)setDirectory:(NSString *)path
{
	[self setDirectoryURL:(path != nil) ? [NSURL fileURLWithPath:path] : nil];
}

- (NSString *)requiredFileType { return _requiredFileType; }
- (void)setRequiredFileType:(NSString *)type
{
	NSString *held = [type copy];

	[_requiredFileType release];
	_requiredFileType = held;
}

- (void)beginSheetForDirectory:(NSString *)path file:(NSString *)name modalForWindow:(NSWindow *)docWindow
		 modalDelegate:(id)delegate didEndSelector:(SEL)didEndSelector contextInfo:(void *)contextInfo
{
	if (path != nil) {
		[self setDirectory:path];
	}
	if (name != nil) {
		[self setNameFieldStringValue:name];
	}
	[self beginSheetModalForWindow:docWindow completionHandler:^(NSInteger result) {
		if (delegate != nil && didEndSelector != NULL && [delegate respondsToSelector:didEndSelector]) {
			typedef void (*AGPanelDidEndIMP)(id, SEL, id, NSInteger, void *);
			AGPanelDidEndIMP imp = (AGPanelDidEndIMP)[delegate methodForSelector:didEndSelector];

			imp(delegate, didEndSelector, self, result, contextInfo);
		}
	}];
}

- (NSInteger)runModalForDirectory:(NSString *)path file:(NSString *)name
{
	if (path != nil) {
		[self setDirectory:path];
	}
	if (name != nil) {
		[self setNameFieldStringValue:name];
	}
	return [self runModal];
}

@end
