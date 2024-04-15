#!/bin/env bash

mkdir -p  "$ARR_DATA_DIR" && chown abc: "$ARR_DATA_DIR"
mkdir -p  "$ARR_DATA_DIR/$ARR_APP_NAME" && chown abc: "$ARR_DATA_DIR/$ARR_APP_NAME"
CONFIGPATH="$ARR_DATA_DIR/$ARR_APP_NAME/config.xml"

# If the config file doesn't exist yet, use the embedded default.
if [ ! -f "$CONFIGPATH" ]; then
    cp /config/config.xml "$CONFIGPATH" && chown abc: "$CONFIGPATH"
fi