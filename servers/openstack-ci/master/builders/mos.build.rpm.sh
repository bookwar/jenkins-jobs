#!/bin/bash

set -o xtrace
set -o errexit

START_TS=$(date +%s)
if bash build-rpm.sh; then
  echo FAILED=false >> ci_status_params
  RESULT=0
else
  echo FAILED=true >> ci_status_params
  RESULT=1
fi
TIME_ELAPSED=$(( $(date +%s) - ${START_TS} ))
echo "RESULT=${RESULT}" > setenvfile
echo "TIME_ELAPSED='$(date -u -d @${TIME_ELAPSED} +'%Hh %Mm %Ss' | sed 's|^00h ||; s|^00m ||')'" >> setenvfile
