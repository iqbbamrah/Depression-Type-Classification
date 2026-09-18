"""Orchestrates the Depression Type Classification pipeline: builds the dbt
data layer (seed -> run -> test), then, once the data has passed its tests,
generates dbt docs and trains/evaluates the classifier in parallel.

Run via Docker: `cd airflow && docker compose up` (see airflow/README section
in the main repo README). The whole repo is mounted read/write into the
container at PROJECT_DIR below, so this DAG's tasks operate on the same
files documented in the main README's "Running it locally" instructions -
this is the same `dbt seed && dbt run && dbt test` and notebook-execution
sequence, just orchestrated instead of run by hand.
"""

from __future__ import annotations

import pendulum

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG

PROJECT_DIR = "/opt/airflow/project"
DBT_DIR = f"{PROJECT_DIR}/dbt"

with DAG(
    dag_id="depression_type_classification_pipeline",
    description="dbt seed/run/test -> docs + model training for the Depression Type Classification project",
    # No cron schedule: the source data is a static, one-time survey export,
    # not something new arrives for on a recurring basis, so an automatic
    # schedule would just be decorative. Trigger manually (UI or `airflow
    # dags trigger`) when the dbt models, seed data, or notebook change.
    schedule=None,
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["dbt", "depression-type-classification"],
) as dag:
    dbt_seed = BashOperator(
        task_id="dbt_seed",
        bash_command="dbt seed --profiles-dir . --project-dir .",
        cwd=DBT_DIR,
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command="dbt run --profiles-dir . --project-dir .",
        cwd=DBT_DIR,
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command="dbt test --profiles-dir . --project-dir .",
        cwd=DBT_DIR,
    )

    # Documentation and model training both only need data that has passed
    # dbt_test, and don't depend on each other, so they fan out and run
    # concurrently rather than being forced into one long chain.
    dbt_docs_generate = BashOperator(
        task_id="dbt_docs_generate",
        bash_command="dbt docs generate --profiles-dir . --project-dir .",
        cwd=DBT_DIR,
    )

    train_and_evaluate_model = BashOperator(
        task_id="train_and_evaluate_model",
        # --ExecutePreprocessor.kernel_name=python3 overrides the notebook's
        # own stale kernelspec metadata (left over from wherever it was
        # originally authored), which doesn't exist in this container.
        bash_command=(
            "jupyter nbconvert --to notebook --execute --inplace "
            "--ExecutePreprocessor.kernel_name=python3 "
            '"Depression Type Classification Analysis.ipynb"'
        ),
        cwd=PROJECT_DIR,
    )

    dbt_seed >> dbt_run >> dbt_test >> [dbt_docs_generate, train_and_evaluate_model]
