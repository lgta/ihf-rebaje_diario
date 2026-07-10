#!/bin/bash
# usage: run_athena.sh <sqlfile>
# Ejecuta un SQL en Athena (db dev_datalake_master) y imprime el CSV resultante
set -e
SQL=$(cat "$1")
OUT=s3://aws-athena-query-results-882281946095-us-east-2/tmp-claude-rebaje/
QID=$(aws athena start-query-execution \
  --query-string "$SQL" \
  --query-execution-context Database=dev_datalake_master \
  --work-group primary \
  --result-configuration OutputLocation=$OUT \
  --query QueryExecutionId --output text)
echo "QID: $QID" >&2
while true; do
  STATE=$(aws athena get-query-execution --query-execution-id "$QID" --query 'QueryExecution.Status.State' --output text)
  case "$STATE" in
    SUCCEEDED) break ;;
    FAILED|CANCELLED)
      echo "ESTADO: $STATE" >&2
      aws athena get-query-execution --query-execution-id "$QID" --query 'QueryExecution.Status.StateChangeReason' --output text >&2
      exit 1 ;;
    *) sleep 3 ;;
  esac
done
aws s3 cp "${OUT}${QID}.csv" - 2>/dev/null
