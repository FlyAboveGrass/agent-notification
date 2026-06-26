#!/usr/bin/env bash
sleep "${CODEX_NOTIFIER_TEST_NOTIFIER_DELAY_SECONDS:-1}"
printf 'notifier_done %s\n' "$(date +%s)" >>"${CODEX_NOTIFIER_TEST_TRACE:?}"
