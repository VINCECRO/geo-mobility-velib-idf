#!/bin/bash
set -e

echo "==============================="
echo " Airflow initialisation"
echo "==============================="

# Attente que la base PostgreSQL soit prête
echo "⏳ Waiting for PostgreSQL..."
until pg_isready -h postgres -p 5432 -U velib; do
  echo "PostgreSQL is unavailable - sleeping"
  sleep 2
done

# echo "👤 Configuring admin user..."
# envsubst < /opt/airflow/users.yaml > /opt/airflow/users_processed.yaml
# export AIRFLOW__AUTH_MANAGER__SIMPLE_AUTH_MANAGER__USERS_FILE=/opt/airflow/users_processed.yaml

echo "🗄️ Migrating Airflow DB..."
airflow db migrate
echo "👤 Creating admin user..."
# python /opt/airflow/init_script/create_admin.py
airflow users create \
    --firstname ${AIRFLOW_ADMIN_FIRSTNAME} \
    --lastname ${AIRFLOW_ADMIN_LASTNAME} \
    --username ${AIRFLOW_ADMIN_USERNAME} \
    --password ${AIRFLOW_ADMIN_PASSWORD} \
    --email ${AIRFLOW_ADMIN_EMAIL} \
    --role Admin \



echo "✅ Airflow initialization completed"

airflow api-server --port 8080 &
airflow scheduler