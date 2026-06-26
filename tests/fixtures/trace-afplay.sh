#!/usr/bin/env bash
printf 'afplay_start %s\n' "$(date +%s)" >>"${CODEX_NOTIFIER_TEST_TRACE:?}"
