#!/bin/bash
pwsh -executionpolicy remotesigned -File $(pwd)/$(dirname $0)/build-font-generator.ps1 "$@"
