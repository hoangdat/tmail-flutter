#!/usr/bin/env bash
python3 -m http.server 8081 --directory "$(dirname "$0")"
