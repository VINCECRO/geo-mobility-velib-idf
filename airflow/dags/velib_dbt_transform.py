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
    """Cherche l'ingestion la plus récente terminée"""
    minutes = (dt.minute // 5) * 5
    target_time = dt.replace(minute=minutes, second=0, microsecond=0)

    # Si on tombe pile sur un cycle, recule de 5 min
    if dt.minute % 5 == 0:
        target_time = target_time - timedelta(minutes=5)

    return target_time


def run_dbt_with_check(**context):
    """
    Lance dbt run et analyse la sortie.

    Comportements :
      - Tout OK           → succès (vert)
      - Erreurs partielles → AirflowSkipException (orange)
      - Tout échoue        → AirflowException (rouge)
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

    # Log complet dans le journal Airflow
    logger.info("=== DBT RUN OUTPUT ===")
    for line in result.stdout.splitlines():
        logger.info(line)

    if result.stderr:
        logger.warning("=== DBT STDERR ===")
        for line in result.stderr.splitlines():
            logger.warning(line)

    stdout = result.stdout

    # --- Parser la ligne de résumé dbt ---
    # Exemple de sortie dbt : "Done. PASS=5 WARN=1 ERROR=2 SKIP=0 TOTAL=8"
    pass_count  = int(re.search(r'PASS=(\d+)',  stdout).group(1)) if re.search(r'PASS=(\d+)',  stdout) else 0
    error_count = int(re.search(r'ERROR=(\d+)', stdout).group(1)) if re.search(r'ERROR=(\d+)', stdout) else 0
    warn_count  = int(re.search(r'WARN=(\d+)',  stdout).group(1)) if re.search(r'WARN=(\d+)',  stdout) else 0
    skip_count  = int(re.search(r'SKIP=(\d+)',  stdout).group(1)) if re.search(r'SKIP=(\d+)',  stdout) else 0

    logger.info("")
    logger.info(f"📊 Résumé dbt run → PASS={pass_count} | ERROR={error_count} | WARN={warn_count} | SKIP={skip_count}")
    logger.info("")

    # ❌ Tous les modèles ont échoué → tâche ROUGE
    if error_count > 0 and pass_count == 0:
        raise AirflowException(
            f"❌ DBT RUN FAILED : {error_count} modèle(s) en erreur, "
            f"aucun modèle n'a été chargé. Vérifiez les logs dbt."
        )

    # 🟠 Erreurs partielles → tâche ORANGE
    if error_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT RUN PARTIEL : {pass_count} modèle(s) OK / {error_count} erreur(s) / "
            f"{skip_count} skipped. Certains modèles n'ont pas été transformés !"
        )

    # 🟠 Warnings uniquement → tâche ORANGE
    if warn_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT RUN avec warnings : {pass_count} modèle(s) OK / {warn_count} warning(s). "
            f"Vérifiez la qualité des données."
        )

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                   DBT RUN - COMPLETED                         ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")
    logger.info(f"✅ DBT RUN SUCCESS : {pass_count} modèle(s) transformés avec succès.")


def run_dbt_test_with_check(**context):
    """
    Lance dbt test et analyse la sortie.

    Comportements :
      - Tout OK          → succès (vert)
      - Tests échoués    → AirflowSkipException (orange)
      - Erreur critique  → AirflowException (rouge)
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

    # Log complet dans le journal Airflow
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
    logger.info(f"📊 Résumé dbt test → PASS={pass_count} | FAIL={fail_count} | ERROR={error_count} | WARN={warn_count}")
    logger.info("")

    # ❌ Erreur critique (ex: connexion DB perdue) → tâche ROUGE
    if error_count > 0 and pass_count == 0 and fail_count == 0:
        raise AirflowException(
            f"❌ DBT TEST ERROR CRITIQUE : {error_count} erreur(s) d'exécution. "
            f"Les tests n'ont pas pu s'exécuter."
        )

    # 🟠 Tests échoués → tâche ORANGE
    if fail_count > 0 or error_count > 0:
        raise AirflowSkipException(
            f"⚠️ DBT TEST : {fail_count} test(s) échoué(s) / {error_count} erreur(s) / "
            f"{pass_count} OK. La qualité des données n'est pas garantie !"
        )

    logger.info("")
    logger.info("╔═══════════════════════════════════════════════════════════════╗")
    logger.info("║                   DBT TEST - COMPLETED                        ║")
    logger.info("╚═══════════════════════════════════════════════════════════════╝")
    logger.info("")
    logger.info(f"✅ DBT TEST SUCCESS : {pass_count} test(s) passés avec succès.")


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