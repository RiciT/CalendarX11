#!/bin/bash

# kill any other running instances of this script
MYPID=$$
pgrep -f "$(basename "${BASH_SOURCE[0]}")" | while read -r PID; do
	[ "$PID" -ne "$MYPID" ] && kill "$PID"
done

MAX_ITER=10
DID_FAIL=false

SCRIPT_DIR="$(\cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUM_EVENTS="$(\cat "$SCRIPT_DIR/events.jsonl" | jq -r '.date // empty' | wc -l)"
CAL="$(awk -F '=' '{print $2}' "$SCRIPT_DIR/.env")"

while [ "$MAX_ITER" -ne 0 ]; do
	((MAX_ITER--))
	while [ "$NUM_EVENTS" -ne 0 ]; do
		# parsing - need to parse the actual details from the json
		DATE="$(jq -r -n 'input | .date' "$SCRIPT_DIR/events.jsonl")"
		DATE_END="$(jq -r -n 'input | .dateEnd // ""' "$SCRIPT_DIR/events.jsonl")"
		WHOLE_DAY="$(jq -r -n 'input | .wholeDay' "$SCRIPT_DIR/events.jsonl")"
		TIME_START=""
		TIME_END=""
		if [ "$WHOLE_DAY" = false ]; then
			TIME_START="$(jq -r -n 'input | .timeStart' "$SCRIPT_DIR/events.jsonl")"
			TIME_END="$(jq -r -n 'input | .timeEnd' "$SCRIPT_DIR/events.jsonl")"
		fi
		TITLE="$(jq -r -n 'input | .title' "$SCRIPT_DIR/events.jsonl")"
		DESCRIPTION="$(jq -r -n 'input | .description' "$SCRIPT_DIR/events.jsonl")"

		# build gcalcli command
		if [ "$WHOLE_DAY" = "true" ]; then
			WHEN="$DATE"
			if [ -n "$DATE_END" ]; then
				DURATION=$((($(date -d "$DATE_END" +%s) - $(date -d "$DATE" +%s)) / 86400 + 1))
			else
				DURATION=1
			fi
			if ! gcalcli add --calendar "$CAL" --title "$TITLE" --when "$WHEN" --duration "$DURATION" --description "$DESCRIPTION" --allday --noprompt; then
				dunstify -t 3000 "Can't add event to Google Calendar, will try again in 5 minutes"
				DID_FAIL=true
				break
			fi
		else
			WHEN="${DATE}T${TIME_START}"
			START_MINS=$(echo "$TIME_START" | awk -F: '{print $1*60+$2}')
			END_MINS=$(echo "$TIME_END" | awk -F: '{print $1*60+$2}')
			DURATION=$((END_MINS - START_MINS))
			[ "$DURATION" -le 0 ] && DURATION=$((DURATION * -1)) && WHEN="${DATE}T${TIME_END}" #will not work with overnight events if i ever implement them in the picker
			if ! gcalcli add --calendar "$CAL" --title "$TITLE" --when "$WHEN" --duration "$DURATION" --description "$DESCRIPTION" --noprompt; then
				dunstify -t 3000 "Can't add event to Google Calendar, will try again in 5 minutes"
				DID_FAIL=true
				break
			fi
		fi

		# delete the first entry so we can continue parsing
		jq -n '[inputs] | .[1:][] ' "$SCRIPT_DIR/events.jsonl" >"$SCRIPT_DIR/events.jsonl.tmp" &&
			mv "$SCRIPT_DIR/events.jsonl.tmp" "$SCRIPT_DIR/events.jsonl"

		((NUM_EVENTS--))
	done

	if [ $DID_FAIL = false ]; then
		break
	fi

	sleep 300 #in seconds
done

if [ "$DID_FAIL" = false ]; then
	rm --preserve-root "$SCRIPT_DIR/events.jsonl"
	dunstify -t 3000 "Event added to Google Calendar successfully"
fi
