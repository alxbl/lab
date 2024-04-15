#!/bin/env bash

BASEPATH="/media/.config"
mkdir -p  "$BASEPATH" && chown abc: "$BASEPATH"
mkdir -p  "$BASEPATH/$APP" && chown abc: "$BASEPATH/$APP"
CONFIGPATH="$BASEPATH/$APP/config.xml"

# If the config file doesn't exist yet, use the embedded default.
if [ ! -f "$CONFIGPATH" ]; then
    cp /config/config.xml "$CONFIGPATH" && chown abc: "$CONFIGPATH"
fi