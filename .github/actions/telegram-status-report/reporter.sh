#!/usr/bin/env bash
set -euo pipefail

STATUS="${STATUS:-unknown}"
JOB="${JOB_NAME:-$GITHUB_JOB}"
MSG="${EXTRA_MESSAGE:-}"

EMOJI="⁉️"
case "$STATUS" in
  success) EMOJI="✅" ;;
  failure) EMOJI="❌" ;;
  cancelled) EMOJI="⚠️" ;;
esac

# exit early if success (no report needed)
if [ "$STATUS" = "success" ]; then exit 0; fi

# build msg text
TEXT="$EMOJI *CI ${STATUS}*
Repo: \`${GITHUB_REPOSITORY}\`
Workflow: \`${GITHUB_WORKFLOW}\`
Job: \`${JOB}\`
Branch: \`${GITHUB_REF_NAME}\`
Commit: \`${GITHUB_SHA}\`
${MSG}
Logs: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

# send to telegram
RES=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "parse_mode=Markdown" \
    -d "text=$TEXT")

# check if sent successfully
if echo "$RES" | grep -q '"ok":false'; then
    echo "❌ Failed to send Telegram message"
    echo $RES
    exit 1
fi

echo "✅ Telegram message sent successfully"
