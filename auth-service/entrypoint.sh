#!/bin/sh
set -e
psql "$DATABASE_URL" -f /app/init.sql
exec /app/auth-service
