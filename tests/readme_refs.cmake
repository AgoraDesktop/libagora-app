/*
 * Copyright © 2026 Kyle J. Cardoza.
 * SPDX-FileCopyrightText: 2026 Kyle J. Cardoza
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Portions of this file may derive from GNUstep; see THIRD-PARTY.md.
 */

# Every test file the README names exists.
#
# usage: cmake -DREADME=<path> -DTESTS_DIR=<path to libagora-app/tests> -P readme_refs.cmake
#
# **THE README IS AN INVENTORY AND IT CITED PROBES THAT THE TREE NO LONGER HAD.** Four of its "still owed" claims were
# found FALSE in one reading — two of them said a class did not exist that is the largest one in this layer — and the
# root cause was not a wrong sentence but a sentence nobody had to revisit when the thing it described landed. This is
# the one part of that problem a machine can hold: EVERY `tests/<name>.m` the document names must exist, so a probe that
# is renamed or deleted cannot leave a citation behind, and a citation cannot be invented for a file that is not there.
#
# **AND IT DOES NOT CLAIM TO DO MORE THAN THAT, WHICH IS THE POINT.** It cannot tell whether a sentence's claim is still
# TRUE — "the candidate list is owed" cites a real probe on both sides of its own contradiction — so what it holds is the
# REFERENCE, and a reader is what holds the meaning. A guard that pretended otherwise would be the same kind of comfort
# the stale sentences were.

if(NOT README OR NOT TESTS_DIR)
  message(FATAL_ERROR "readme_refs.cmake needs -DREADME and -DTESTS_DIR")
endif()

file(READ "${README}" text)
string(REGEX MATCHALL "tests/[A-Za-z0-9_]+\\.m" cited "${text}")
list(REMOVE_DUPLICATES cited)

# A REFERENCE IS `tests/<name>.m`, so the file it names is `<name>.m` IN the tests directory — the prefix is the
# document's convention for saying where it lives, not part of the path to join. The first version joined them and
# reported five files as missing that were sitting in the directory it was reading.set(missing "")
foreach(ref IN LISTS cited)
  get_filename_component(name "${ref}" NAME)
  if(NOT EXISTS "${TESTS_DIR}/${name}")
    list(APPEND missing "${ref}")
  endif()
endforeach()

if(missing)
  string(REPLACE ";" "\n    " report "${missing}")
  message(FATAL_ERROR "the README cites test files that do not exist:\n    ${report}")
endif()
list(LENGTH cited count)
message(STATUS "every one of the ${count} test file(s) the README cites exists")
