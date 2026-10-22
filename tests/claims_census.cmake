# Copyright © 2026 Kyle J. Cardoza.
# SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
# SPDX-License-Identifier: GPL-3.0-or-later
# Portions of this file may derive from GNUstep; see THIRD-PARTY.md.

# The claims census, checked in both directions — one script, two kinds of claim.
#
# usage: cmake -DSOURCE_DIR=<dir> -DCENSUS=<file> -DEXTENSION=<.m|.h> -DNEEDLE=<regex> -P claims_census.cmake
#
# **TWO KINDS OF CLAIM, ONE INSTRUMENT.** A REFUSAL is a place the library says "not this" and returns, marked
# `APPKIT-REFUSE` in the sources; an OWED NOTE is a place the header says what this layer does not do yet, marked with
# the word OWED. Both are claims about the same subject — what this layer cannot do — and both drift the same way, so
# both are counted per file and compared in both directions.
#
# **AND THE NEEDLE IS A REGEX RATHER THAN A WORD, WHICH THE FIRST VERSION OF THIS FILE LEARNED THE HARD WAY.** The owed
# notes were first counted as the substring `OWED`, which matched inside `MAC_OS_X_VERSION_MAX_ALLOWED` and `BORROWED`
# — TWENTY-ONE of the thirty-eight hits were parts of other words, and the census was inflated by more than half before
# it existed. The instrument has to be about the thing it claims to measure.
#
# A CENSUS RATHER THAN A CEILING, because a count that may only fall says nothing about WHERE a refusal is: moving one
# from a class that needed it to a class that did not would pass. So the census is per FILE, and it is compared both
# ways — a file holding a refusal the census does not name fails, and a census line whose count has moved fails. The
# only way to change the answer is to edit the census, which is the point: it makes adding or removing a refusal a
# deliberate act with a diff, instead of a side effect of a slice nobody re-read afterwards.
#
# THIS IS THE APPKIT HALF OF `libagora-text`'s `owed_symbols.cmake`, and it exists for the same reason that one does:
# the tree's claims about what it cannot do are held by prose, and prose drifts. It cannot use the same instrument —
# `nm` answers for C symbols, and every door here is an Objective-C METHOD, which is dispatched dynamically and appears
# in no symbol table — so this counts the SITES instead, which is the census the prose actually makes.

if(NOT SOURCE_DIR OR NOT CENSUS OR NOT EXTENSION OR NOT NEEDLE)
  message(FATAL_ERROR "claims_census.cmake needs -DSOURCE_DIR, -DCENSUS, -DEXTENSION and -DNEEDLE")
endif()

file(GLOB sources "${SOURCE_DIR}/*${EXTENSION}")
file(READ "${CENSUS}" census_text)

# THE TOTAL IS ITSELF A LINE IN THE FILE, as a comment, so the sum is checked against a number a reader can see.
set(recorded_total -1)
if(census_text MATCHES "# total: ([0-9]+)")
  set(recorded_total "${CMAKE_MATCH_1}")
endif()

# THE CENSUS, parsed: "file count" lines, blank lines and `#` comments skipped.
set(expected_names "")
set(expected_total 0)
# **AND THE COMMENT LINES COME OUT BEFORE THE NEWLINES TURN INTO LIST SEPARATORS, WHICH IS A TRAP THIS FILE HAD.**
# `string(REPLACE "\n" ";" ...)` splits on SEMICOLONS as well as newlines, and a comment line is prose — so the moment
# a reader puts one `;` in a sentence above the counts, that line fragments and its second half is read as a census line
# that is not `file count`, with an error naming prose rather than the cause. Both censuses happened to be
# semicolon-free, so nothing had failed yet; the instrument should not depend on that. ONLY THE BODY IS FILTERED:
# `census_text` keeps its comments, because the recorded total is read out of one.
string(REGEX REPLACE "(^|\n)[ \t]*#[^\n]*" "\\1" census_body "${census_text}")
string(REPLACE "\n" ";" census_lines "${census_body}")
foreach(line IN LISTS census_lines)
  string(STRIP "${line}" line)
  if(line STREQUAL "" OR line MATCHES "^#")
    continue()
  endif()
  if(NOT line MATCHES "^([^ ]+) +([0-9]+)$")
    message(FATAL_ERROR "the census has a line that is not `file count`: `${line}`")
  endif()
  set(name "${CMAKE_MATCH_1}")
  set(count "${CMAKE_MATCH_2}")
  set(expected_names ${expected_names} "${name}")
  math(EXPR expected_total "${expected_total} + ${count}")
  set(expected_${name} "${count}")
endforeach()

# THE SOURCES, counted.
set(actual_total 0)
set(offenders "")
foreach(source IN LISTS sources)
  get_filename_component(name "${source}" NAME)
  file(READ "${source}" text)
  string(REGEX MATCHALL "${NEEDLE}" sites "${text}")
  list(LENGTH sites actual)
  math(EXPR actual_total "${actual_total} + ${actual}")
  set(recorded 0)
  if(DEFINED expected_${name})
    set(recorded "${expected_${name}}")
  endif()
  if(NOT actual EQUAL recorded)
    list(APPEND offenders "${name}: the census says ${recorded}, the source has ${actual}")
  endif()
endforeach()

# AND A CENSUS LINE WITH NO REFUSALS LEFT IS AS WRONG AS A REFUSAL WITH NO LINE.
foreach(name IN LISTS expected_names)
  if(NOT EXISTS "${SOURCE_DIR}/${name}")
    list(APPEND offenders "${name}: named by the census and not in the source directory")
  endif()
endforeach()

if(NOT recorded_total EQUAL actual_total)
  list(APPEND offenders "the census says ${recorded_total} in total, the sources have ${actual_total}")
endif()

if(offenders)
  string(REPLACE ";" "\n    " report "${offenders}")
  message(FATAL_ERROR "the census (${NEEDLE} in *${EXTENSION}) and the sources disagree:\n    ${report}")
endif()
message(STATUS "census (${EXTENSION}, ${NEEDLE}): ${actual_total} claim(s) over the recorded files, exactly as recorded")
