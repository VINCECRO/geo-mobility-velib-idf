# airflow/dags/velib_dbt_transformation.py
from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.standard.sensors.external_task import ExternalTaskSensor
from airflow.exceptions import AirflowSkipException, AirflowException
from datetime import datetime, timedelta
import subprocess
import logging
import re


DBT_DIR = "/opt/airflow/dbt"


def get_latest_ingestion_time(dt):
    """Finds the most recent completed ingestion"""
    minutes = (dt.minute // 5) * 5
    target_time = dt.replace(minute=minutes, second=0, microsecond=0)

    # If exactly on a cycle boundary, step back 5 min
    if dt.minute % 5 == 0:
        target_time = target_time - timedelta(minutes=5)

    return target_time


def run_dbt_with_check(**context):
    """
    Runs dbt run and analyses the output.

    Behaviour:
      - All OK            → success (green)
      - Partial errors    → AirflowSkipException (orange)
      - All fail          → AirflowException (red)
    """
    logger = logging.getLogger(__name__)

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                          DBT RUN                              ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")

    result = subprocess.run(
        ["dbt", "run"],
        cwd=DBT_DIR,
        capture_output=True,
        text=True
    )

    # Full log in the Airflow journal
    logger.info("=== DBT RUN OUTPUT ===")
    for line in result.stdout.splitlines():
        logger.info(line)

    if result.stderr:
        logger.warning("=== DBT STDERR ===")
        for line in result.stderr.splitlines():
            logger.warning(line)

    stdout = result.stdout

    # --- Parse the dbt summary line ---
    # Example dbt output: "Done. PASS=5 WARN=1 ERROR=2 SKIP=0 TOTAL=8"
    pass_count  = int(re.search(r'PASS=(\d+)',  stdout).group(1)) if re.search(r'PASS=(\d+)',  stdout) else 0
    error_count = int(re.search(r'ERROR=(\d+)', stdout).group(1)) if re.search(r'ERROR=(\d+)', stdout) else 0
    warn_count  = int(re.search(r'WARN=(\d+)',  stdout).group(1)) if re.search(r'WARN=(\d+)',  stdout) else 0
    skip_count  = int(re.search(r'SKIP=(\d+)',  stdout).group(1)) if re.search(r'SKIP=(\d+)',  stdout) else 0

    logger.info("")
    logger.info(f"📊 dbt run summary → PASS={pass_count} | ERROR={error_count} | WARN={warn_count} | SKIP={skip_count}")
    logger.info("")

    # ❌ All models failed → RED task
    if error_count > 0 and pass_count == 0:
        raise AirflowException(
            f"❌ DBT RUN FAILED: {error_count} model(s) in error, "
            f"no model was loaded. Check the dbt logs."
        )

    # 🟠 Partial errors → ORANGE task
    if error_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT RUN PARTIAL: {pass_count} model(s) OK / {error_count} error(s) / "
            f"{skip_count} skipped. Some models were not transformed!"
        )

    # 🟠 Warnings only → ORANGE task
    if warn_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT RUN with warnings: {pass_count} model(s) OK / {warn_count} warning(s). "
            f"Check data quality."
        )

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                   DBT RUN - COMPLETED                         ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")
    logger.info(f"✅ DBT RUN SUCCESS: {pass_count} model(s) successfully transformed.")


def run_dbt_test_with_check(**context):
    """
    Runs dbt test and analyses the output.

    Behaviour:
      - All OK           → success (green)
      - Failed tests     → AirflowSkipException (orange)
      - Critical error   → AirflowException (red)
    """
    logger = logging.getLogger(__name__)

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                   DBT TEST - VALIDATION                       ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")

    result = subprocess.run(
        ["dbt", "test"],
        cwd=DBT_DIR,
        capture_output=True,
        text=True
    )

    # Full log in the Airflow journal
    logger.info("=== DBT TEST OUTPUT ===")
    for line in result.stdout.splitlines():
        logger.info(line)

    if result.stderr:
        logger.warning("=== DBT STDERR ===")
        for line in result.stderr.splitlines():
            logger.warning(line)

    stdout = result.stdout

    pass_count  = int(re.search(r'PASS=(\d+)',  stdout).group(1)) if re.search(r'PASS=(\d+)',  stdout) else 0
    fail_count  = int(re.search(r'FAIL=(\d+)',  stdout).group(1)) if re.search(r'FAIL=(\d+)',  stdout) else 0
    error_count = int(re.search(r'ERROR=(\d+)', stdout).group(1)) if re.search(r'ERROR=(\d+)', stdout) else 0
    warn_count  = int(re.search(r'WARN=(\d+)',  stdout).group(1)) if re.search(r'WARN=(\d+)',  stdout) else 0

    logger.info("")
    logger.info(f"📊 dbt test summary → PASS={pass_count} | FAIL={fail_count} | ERROR={error_count} | WARN={warn_count}")
    logger.info("")

    # ❌ Critical error (e.g. lost DB connection) → RED task
    if error_count > 0 and pass_count == 0 and fail_count == 0:
        raise AirflowException(
            f"❌ DBT TEST CRITICAL ERROR: {error_count} execution error(s). "
            f"Tests could not run."
        )

    # 🟠 Failed tests → ORANGE task
    if fail_count > 0 or error_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT TEST: {fail_count} test(s) failed / {error_count} error(s) / "
            f"{pass_count} OK. Data quality is not guaranteed!"
        )

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                   DBT TEST - COMPLETED                        ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")
    logger.info(f"✅ DBT TEST SUCCESS: {pass_count} test(s) passed successfully.")


with DAG(
    dag_id="dbt_dag",
    start_date=datetime(2026, 1, 23),
    schedule='3,33 * * * *',
    is_paused_upon_creation=False,
    max_active_runs=1,
    catchup=False,
) as dag:

    wait_for_ingestion = ExternalTaskSensor(
        task_id='wait_for_ingestion_complete',
        external_dag_id='velib_extract_ingestion_dag',
        external_task_id='load_stations_status',
        execution_date_fn=get_latest_ingestion_time,
        allowed_states=['success'],
        failed_states=['failed', 'skipped'],
        mode='reschedule',
        poke_interval=15,
        timeout=180,
    )

    dbt_run = PythonOperator(
        task_id="dbt_run",
        python_callable=run_dbt_with_check,
    )

    dbt_test = PythonOperator(
        task_id="dbt_test",
        python_callable=run_dbt_test_with_check,
    )

    dbt_docs_generate = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"""
        cd {DBT_DIR}
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║                   DBT DOCS - GENERATION                       ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        dbt docs generate
        echo ""
        echo "╔═══════════════════════════════════════════════════════════════╗"
        echo "║                   DBT DOCS - COMPLETED                        ║"
        echo "╚═══════════════════════════════════════════════════════════════╝"
        echo ""
        """
    )

    # Task order
    wait_for_ingestion >> dbt_run >> dbt_test >> dbt_docs_generate