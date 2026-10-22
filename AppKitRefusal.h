// Copyright © 2026 Kyle J. Cardoza.
// SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
// SPDX-License-Identifier: LGPL-3.0-or-later
// Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
//
//  AppKitRefusal.h
//  AppKit
//
//  **ONE REFUSAL MESSAGE IN ONE PLACE.** Several doors across NSWindow and NSView exist so that a ported program
//  gets a NAMED refusal instead of a link error, and each names the subsystem this tier has not got. The wording
//  lives here rather than once per class because two copies of a reason are two chances for them to disagree about
//  it — the same economy NSBitmapImageRep's `fn_refuseEncoder` uses.
//
//  A REFUSAL IS NOT A STUB: it answers the door's own type's empty value AND says what is missing, so a caller can
//  tell "this tier cannot do that" from "this tier did it and the answer was empty".

#ifndef APPKIT_REFUSAL_H
#define APPKIT_REFUSAL_H

#include <stdio.h>

static inline void fn_refuse_window(const char *which, const char *needs)
{
	fprintf(stderr, "APPKIT-REFUSE: %s needs %s; this tier has not got it, so the door answers its type's "
			"empty value rather than approximating the work\n", which, needs);
}

#endif
