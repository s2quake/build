#!/bin/bash
pwsh -executionpolicy remotesigned -File $(dirname $0)/build-crema.ps1 "$@"
