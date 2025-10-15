#!/bin/sh
set -e

LAST_API_URL_FILE="/app/scripts/LAST_API_URL"

OLD_API_URL=""
if [ -f "$LAST_API_URL_FILE" ] && [ -s "$LAST_API_URL_FILE" ]; then
	OLD_API_URL=$(cat "$LAST_API_URL_FILE")
fi

if [ -z "$OLD_API_URL" ]; then
	OLD_API_URL="__API_URL_PLACEHOLDER__"
fi

ESCAPED_OLD_API_URL=$(echo "$OLD_API_URL" | sed 's/\//\\\//g')
ESCAPED_NEXT_PUBLIC_API_URL=$(echo "${NEXT_PUBLIC_API_URL}" | sed 's/\//\\\//g')

if [ "$ESCAPED_OLD_API_URL" != "$ESCAPED_NEXT_PUBLIC_API_URL" ]; then
	find /app/ctfile-downloader-panel -type f \( -name '*.js' -o -name '*.html' \) | while read -r file; do
		sed -i "s|${ESCAPED_OLD_API_URL}|${ESCAPED_NEXT_PUBLIC_API_URL}|g" "$file"
	done

	echo "${NEXT_PUBLIC_API_URL}" >"$LAST_API_URL_FILE"
fi

/usr/bin/shttpd -threads $(nproc) -ports 3000
