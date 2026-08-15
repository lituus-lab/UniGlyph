#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
set -eu
exec xcrun llvm-cov gcov "$@"
