#!/bin/sh
set -e
psql "$DATABASE_URL" -f /app/init.sql
exec gunicorn app:app --bind 0.0.0.0:8002 --workers 2
