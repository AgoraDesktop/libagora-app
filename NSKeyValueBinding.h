/*
 * NSKeyValueBinding.h — the controller-marker predicate.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 *
 * **ONE FUNCTION, AND ITS ANSWER HERE IS NO FOR EVERYTHING.** Apple's controller markers are four shared singleton
 * objects an `NSController` substitutes for "not applicable", "multiple values" and the rest; this tier has no binding
 * controllers at all — the whole `NSController` family is in the API census's missing list — so no object can be one.
 * The door is implemented rather than refused because "NO" is the documented answer for every object that is not a
 * marker, and that is exactly the truth here, where there are none.
 */

#ifndef APPKIT_NSKEYVALUEBINDING_H
#define APPKIT_NSKEYVALUEBINDING_H

#import <Foundation/NSObject.h>

NS_ASSUME_NONNULL_BEGIN

BOOL NSIsControllerMarker(id _Nullable object);

NS_ASSUME_NONNULL_END

#endif /* APPKIT_NSKEYVALUEBINDING_H */
