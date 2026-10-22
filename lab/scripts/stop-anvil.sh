#!/usr/bin/env bash
pidof anvil >/dev/null && kill $(pidof anvil) && echo "anvil stopped" || echo "anvil not running"
