FROM apache/airflow:3.1.0-python3.12

# passer root pour installer dbt
USER airflow

# installer dbt pour Postgres
RUN pip install --no-cache-dir \
    dbt-core==1.8.2 \
    dbt-postgres==1.8.2

