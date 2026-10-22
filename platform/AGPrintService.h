/*
 * AGPrintService.h — the seam a print job leaves AppKit through.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE PRINT SYSTEM IS TWO LAYERS, AND THIS IS THE BOTTOM ONE.** `NSPrintOperation` renders a view into a PDF and
 * decides where the bytes go; this header is the "where" — a narrow C seam with two implementations, chosen at build
 * time exactly the way the window server's backends are:
 *
 *   - `AG_HAVE_CUPS` — libcups: the queue list (`cupsGetDests`), each queue's facts, its paper keywords and the
 *     submission itself (`cupsCreateJob` / `cupsStartDocument` with `application/pdf`). CUPS is a SYSTEM library
 *     (Apache-2.0 since 2.3, dynamically linked, no systemd dependency) and is OPTIONAL at configure time, the same
 *     shape `libagora-app` already uses for `gbm`.
 *   - otherwise — no print service: no queues, and a submission answers "unavailable". A job can still be saved to a
 *     file or previewed, which is what `NSPrintInfo`'s dispositions are for.
 *
 * **THE JOB IS ALWAYS A PDF.** That is not a shortcut: driverless (IPP Everywhere / AirPrint) printers take
 * `application/pdf` as their native format, and CUPS filters it for everything older. Nothing here speaks PostScript.
 *
 * **STRINGS ARE BORROWED.** Every `const char *` below is owned by the implementation and stays valid until the next
 * call that refreshes the list (in practice: for the life of the process — the list is cached on first use). A caller
 * that needs to keep one copies it.
 */
#ifndef AG_PRINT_SERVICE_H
#define AG_PRINT_SERVICE_H

#include <stddef.h>

/* Whether a print service is compiled in AND reachable. A compiled-in CUPS with a stopped daemon still answers YES:
 * the queue list is then empty, which is a fact about the machine rather than about the build. */
int AGPrintServiceIsAvailable(void);

/* THE QUEUES. An index outside 0..count-1 answers NULL / -1 / 0 rather than a crash. */
int AGPrintServicePrinterCount(void);
const char *AGPrintServicePrinterName(int index);
const char *AGPrintServicePrinterInfo(int index);	/* the queue's description, "" when it has none */
const char *AGPrintServicePrinterMake(int index);	/* make-and-model, "" when it has none */
const char *AGPrintServicePrinterLocation(int index);
int AGPrintServicePrinterIsDefault(int index);
int AGPrintServicePrinterIsColor(int index);
int AGPrintServiceDefaultPrinterIndex(void);		/* -1 when there is none */

/* **THE QUEUE'S PAPER KEYWORDS**, space-separated (`na_letter_8.5x11in iso_a4_210x297mm …`), or NULL when the queue
 * reports none. The mapping from a keyword to points is AppKit's (`NSPrinter -pageSizeForPaper:`), because a keyword is
 * a string and a size is this layer's business. */
const char *AGPrintServicePrinterMediaKeywords(int index);

/* **THE SUBMISSION.** `bytes` is a complete PDF. `copies` below 1 means one; `firstPage`/`lastPage` of 0 mean all
 * pages. Answers 0 on success and fills `*jobID` with a malloc'd "queue/job" string the caller frees with
 * `AGPrintServiceFree`; a non-zero answer is a failure and `AGPrintServiceLastError` says why. */
int AGPrintServiceSubmitPDF(int index, const char *jobName, int copies, int firstPage, int lastPage,
			    const void *bytes, size_t length, char **jobID);
int AGPrintServiceCancelJob(const char *jobID);

/* The last failure's text, owned by the implementation and cleared by the next successful call. */
const char *AGPrintServiceLastError(void);

void AGPrintServiceFree(void *pointer);

#endif /* AG_PRINT_SERVICE_H */
