#!/bin/bash

#example: gcalcli add --calendar [calendar] --title "title" --when 15:00 --duration 3 --description "desc" --allday --noprompt

IS_SUCCESS=false

while [ $IS_SUCCESS = false ]; do
	IS_SUCCESS=true
	if [ $IS_SUCCESS = true ]; then
		break
	fi
	sleep 300 #in seconds
done

dunstify -t 3000 "Event added to Google Calendar successfully" #in millisecs
