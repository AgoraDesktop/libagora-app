/*
 * AGPrintService.c — the print seam: libcups when it is configured in, nothing when it is not.
 *
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 *
 * **THE LIST IS CACHED ONCE, AND THAT IS A STATED LIMIT.** `cupsGetDests` is asked on the first call and its answer is
 * kept for the life of the process: a queue added while an application runs is invisible until relaunch, which is the
 * same trade `NSFontManager` makes with its face list and for the same reason — a per-call query would refresh the
 * strings out from under a caller that is holding them (this header promises they stay valid).
 *
 * **THE SUBMISSION IS THE IPP DOCUMENT PATH, NOT `cupsPrintFile`.** The job is already in memory as a PDF, so a
 * temporary file would be a copy made only to be read back: `cupsCreateJob` → `cupsStartDocument(…, "application/pdf")`
 * → `cupsWriteRequestData` → `cupsFinishDocument` sends exactly those bytes. Copies and the page range travel as IPP
 * options, which is where they belong.
 */
#include "AGPrintService.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef AG_HAVE_CUPS

#include <cups/cups.h>

static cups_dest_t *s_dests = NULL;
static int s_destCount = 0;
static int s_loaded = 0;
static char s_error[512];

static void fn_load(void)
{
	if (s_loaded) {
		return;
	}
	s_loaded = 1;
	s_destCount = cupsGetDests(&s_dests);
	if (s_destCount < 0) {
		s_destCount = 0;
	}
}

static const char *fn_option(cups_dest_t *dest, const char *name)
{
	return cupsGetOption(name, dest->num_options, dest->options);
}

int AGPrintServiceIsAvailable(void)
{
	return 1;
}

int AGPrintServicePrinterCount(void)
{
	fn_load();
	return s_destCount;
}

static cups_dest_t *fn_dest(int index)
{
	fn_load();
	if (index < 0 || index >= s_destCount) {
		return NULL;
	}
	return &s_dests[index];
}

const char *AGPrintServicePrinterName(int index)
{
	cups_dest_t *dest = fn_dest(index);

	return (dest != NULL) ? dest->name : NULL;
}

const char *AGPrintServicePrinterInfo(int index)
{
	cups_dest_t *dest = fn_dest(index);
	const char *info;

	if (dest == NULL) {
		return NULL;
	}
	info = fn_option(dest, "printer-info");
	return (info != NULL) ? info : "";
}

const char *AGPrintServicePrinterMake(int index)
{
	cups_dest_t *dest = fn_dest(index);
	const char *make;

	if (dest == NULL) {
		return NULL;
	}
	make = fn_option(dest, "printer-make-and-model");
	return (make != NULL) ? make : "";
}

const char *AGPrintServicePrinterLocation(int index)
{
	cups_dest_t *dest = fn_dest(index);
	const char *where;

	if (dest == NULL) {
		return NULL;
	}
	where = fn_option(dest, "printer-location");
	return (where != NULL) ? where : "";
}

int AGPrintServicePrinterIsDefault(int index)
{
	cups_dest_t *dest = fn_dest(index);

	return (dest != NULL && dest->is_default) ? 1 : 0;
}

/* COLOR IS A QUEUE ATTRIBUTE WHEN THE QUEUE SAYS SO, AND A WORD IN THE MODEL WHEN IT DOES NOT**: an IPP Everywhere
 * queue advertises `color-supported`, while a classic PPD queue is described by its make-and-model ("HP Color
 * LaserJet"). Both are checked, and a queue that says neither is treated as monochrome — which is the answer that
 * cannot disappoint a caller. */
int AGPrintServicePrinterIsColor(int index)
{
	cups_dest_t *dest = fn_dest(index);
	const char *supported;
	const char *make;

	if (dest == NULL) {
		return 0;
	}
	supported = fn_option(dest, "color-supported");
	if (supported != NULL) {
		return (strcasecmp(supported, "true") == 0 || strcmp(supported, "1") == 0) ? 1 : 0;
	}
	make = fn_option(dest, "printer-make-and-model");
	if (make != NULL && strcasestr(make, "color") != NULL) {
		return 1;
	}
	return 0;
}

int AGPrintServiceDefaultPrinterIndex(void)
{
	int i;

	fn_load();
	for (i = 0; i < s_destCount; i++) {
		if (s_dests[i].is_default) {
			return i;
		}
	}
	return -1;
}

const char *AGPrintServicePrinterMediaKeywords(int index)
{
	cups_dest_t *dest = fn_dest(index);

	if (dest == NULL) {
		return NULL;
	}
	/* `media-supported` IS THE LIST; `media-default` IS THE ONE THE QUEUE WOULD USE, and it is offered first so a
	 * caller reading the list in order sees the queue's own choice at the head. */
	{
		const char *supported = fn_option(dest, "media-supported");
		const char *fallback = fn_option(dest, "media-default");

		if (supported != NULL && supported[0] != '\0') {
			return supported;
		}
		return (fallback != NULL && fallback[0] != '\0') ? fallback : NULL;
	}
}

static void fn_set_error(const char *what, cups_dest_t *dest)
{
	snprintf(s_error, sizeof s_error, "%s for queue \"%s\" failed: %s", what,
		 dest != NULL ? dest->name : "(none)", cupsLastErrorString());
}

int AGPrintServiceSubmitPDF(int index, const char *jobName, int copies, int firstPage, int lastPage,
			    const void *bytes, size_t length, char **jobID)
{
	cups_dest_t *dest = fn_dest(index);
	cups_option_t *options = NULL;
	int numOptions = 0;
	int job = 0;
	char number[32];

	s_error[0] = '\0';
	if (dest == NULL) {
		snprintf(s_error, sizeof s_error, "no queue at index %d", index);
		return -1;
	}
	if (bytes == NULL || length == 0) {
		snprintf(s_error, sizeof s_error, "no PDF bytes to submit");
		return -1;
	}
	if (copies > 1) {
		snprintf(number, sizeof number, "%d", copies);
		numOptions = cupsAddOption("copies", number, numOptions, &options);
	}
	if (firstPage > 0 && lastPage >= firstPage) {
		snprintf(number, sizeof number, "%d-%d", firstPage, lastPage);
		numOptions = cupsAddOption("page-ranges", number, numOptions, &options);
	}
	job = cupsCreateJob(CUPS_HTTP_DEFAULT, dest->name, jobName != NULL ? jobName : "Agora document", numOptions,
			    options);
	cupsFreeOptions(numOptions, options);
	if (job == 0) {
		fn_set_error("cupsCreateJob", dest);
		return -1;
	}
	{
		const char *documentName = (jobName != NULL) ? jobName : "Agora document";

		/* **THE JOB ID IS AN `int` HERE, WHICH IS THE ONE PLACE THE SEAM'S STRING ID IS TAKEN APART.** CUPS's own
		 * document API numbers the job, and the string this header promises is assembled from that number once the
		 * upload has been accepted. */
		if (cupsStartDocument(CUPS_HTTP_DEFAULT, dest->name, job, documentName, CUPS_FORMAT_PDF, 1) ==
		    HTTP_STATUS_CONTINUE) {
			http_status_t status = cupsWriteRequestData(CUPS_HTTP_DEFAULT, (const char *)bytes, length);
			ipp_status_t done = cupsFinishDocument(CUPS_HTTP_DEFAULT, documentName);

			if (status != HTTP_STATUS_CONTINUE || done != IPP_STATUS_OK) {
				fn_set_error("the document upload", dest);
				return -1;
			}
		} else {
			fn_set_error("cupsStartDocument", dest);
			return -1;
		}
	}
	if (jobID != NULL) {
		char text[512];

		snprintf(text, sizeof text, "%s/%d", dest->name, job);
		*jobID = strdup(text);
	}
	return 0;
}

int AGPrintServiceCancelJob(const char *jobID)
{
	char queue[256];
	const char *slash;
	int job;

	if (jobID == NULL) {
		return -1;
	}
	slash = strrchr(jobID, '/');
	if (slash == NULL || (size_t)(slash - jobID) >= sizeof queue) {
		snprintf(s_error, sizeof s_error, "a job id is \"queue/job\", and \"%s\" is not one", jobID);
		return -1;
	}
	memcpy(queue, jobID, (size_t)(slash - jobID));
	queue[slash - jobID] = '\0';
	job = atoi(slash + 1);
	if (cupsCancelJob2(CUPS_HTTP_DEFAULT, queue, job, 0) != IPP_STATUS_OK) {
		snprintf(s_error, sizeof s_error, "cancelling job %s failed: %s", jobID, cupsLastErrorString());
		return -1;
	}
	return 0;
}

const char *AGPrintServiceLastError(void)
{
	return s_error[0] != '\0' ? s_error : "no error";
}

void AGPrintServiceFree(void *pointer)
{
	free(pointer);
}

#else /* !AG_HAVE_CUPS */

/* **NO PRINT SERVICE, AND THAT IS A CONFIGURATION RATHER THAN A FAILURE.** Every door answers its empty value and the
 * AppKit side reads `AGPrintServiceIsAvailable` to choose a disposition: a job can still be saved or previewed. */
int AGPrintServiceIsAvailable(void)
{
	return 0;
}

int AGPrintServicePrinterCount(void)
{
	return 0;
}

const char *AGPrintServicePrinterName(int index)
{
	(void)index;
	return NULL;
}

const char *AGPrintServicePrinterInfo(int index)
{
	(void)index;
	return NULL;
}

const char *AGPrintServicePrinterMake(int index)
{
	(void)index;
	return NULL;
}

const char *AGPrintServicePrinterLocation(int index)
{
	(void)index;
	return NULL;
}

int AGPrintServicePrinterIsDefault(int index)
{
	(void)index;
	return 0;
}

int AGPrintServicePrinterIsColor(int index)
{
	(void)index;
	return 0;
}

int AGPrintServiceDefaultPrinterIndex(void)
{
	return -1;
}

const char *AGPrintServicePrinterMediaKeywords(int index)
{
	(void)index;
	return NULL;
}

int AGPrintServiceSubmitPDF(int index, const char *jobName, int copies, int firstPage, int lastPage,
			    const void *bytes, size_t length, char **jobID)
{
	(void)index;
	(void)jobName;
	(void)copies;
	(void)firstPage;
	(void)lastPage;
	(void)bytes;
	(void)length;
	if (jobID != NULL) {
		*jobID = NULL;
	}
	return -1;
}

int AGPrintServiceCancelJob(const char *jobID)
{
	(void)jobID;
	return -1;
}

const char *AGPrintServiceLastError(void)
{
	return "this build has no print service (configure with libcups to enable one)";
}

void AGPrintServiceFree(void *pointer)
{
	free(pointer);
}

#endif /* AG_HAVE_CUPS */
