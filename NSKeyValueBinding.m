/*
 * NSKeyValueBinding.m — `NSIsControllerMarker`.
 *
 * © 2026 Kyle J. Cardozo. MIT licence (see LICENSE at the repository root).
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **NO IS THE TRUE ANSWER HERE RATHER THAN A PLACEHOLDER.** An Apple controller marker is one of four shared
 * singleton objects that a binding controller substitutes for "not applicable" or "multiple values". This tier has no
 * binding controllers — the entire `NSController` family is in the API census's missing list — so there are no marker
 * objects for any object to be. When the controller family lands, this function gains its four comparisons; until then
 * a `NO` that a caller can trust beats a `NO` that is a stub, and the difference is that this note says which it is.
 */
#import <AppKit/NSKeyValueBinding.h>

BOOL NSIsControllerMarker(id object)
{
	(void)object;
	return NO;
}
