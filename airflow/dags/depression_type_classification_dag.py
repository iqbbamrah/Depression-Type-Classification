"""Orchestrates the Depression Type Classification pipeline with layer-by-layer
data-quality gates: each dbt layer (seeds -> staging -> intermediate -> marts)
is built *and tested* before the next one starts, a quality report then
summarises every test in the run, and the classifier only trains once that
report has no blocking failures.

Run via Docker: `cd airflow && docker compose up` (see the Orchestration
section of the main README). The whole repo is mounted into the container at
PROJECT_DIR, so tasks operate on the same dbt/ project and notebook documented
in the README.
"""

from __future__ import annotations

import json
from pathlib import Path

import pendulum

from airflow.providers.standard.operators.bash import BashOperator
from airflow.sdk import DAG, task

PROJECT_DIR = "/opt/airflow/project"
DBT_DIR = f"{PROJECT_DIR}/dbt"
# Must go *after* the dbt subcommand (`dbt build <flags>`), not before it.
DBT_FLAGS = "--profiles-dir . --project-dir ."

# (layer name, dbt selector), in build order.
LAYERS = [
    ("seeds", "resource_type:seed"),
    ("staging", "staging"),
    ("intermediate", "intermediate"),
    ("marts", "marts"),
]


def dbt_build_command(layer: str, selector: str) -> str:
    """dbt command that builds and tests one layer.

    - `dbt build` runs + tests each node in dependency order, so a failing
      test skips everything downstream of it.
    - `--indirect-selection buildable` only runs tests whose parents have all
      been built by this point, e.g. the staging->mart row-count test waits
      for the marts layer instead of running against a stale mart here.
    - A separate target path per layer keeps each layer's run_results.json
      for the quality report. It's deleted first so a layer that didn't run
      this time can't leave stale results behind from an earlier run.
    """
    target = f"target/{layer}"
    return (
        f"rm -f {target}/run_results.json && "
        f"dbt build {DBT_FLAGS} --select {selector} --indirect-selection buildable "
        f"--target-path {target}"
    )


with DAG(
    dag_id="depression_type_classification_pipeline",
    description="Layered dbt build with data-quality gates -> model training -> dbt docs",
    # No cron schedule: the source data is a static, one-time survey export,
    # so an automatic schedule would just be decorative. Trigger manually (UI
    # or `airflow dags trigger`) when the dbt models, seed, or notebook change.
    schedule=None,
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    catchup=False,
    tags=["dbt", "data-quality", "depression-type-classification"],
) as dag:
    build_tasks = [
        BashOperator(
            task_id=f"dbt_build_{layer}",
            bash_command=dbt_build_command(layer, selector),
            cwd=DBT_DIR,
        )
        for layer, selector in LAYERS
    ]

    # all_done: runs even when a layer failed, so a broken run still produces
    # a readable summary of *which* tests broke, not just a red task.
    @task(trigger_rule="all_done")
    def quality_report() -> dict[str, int]:
        """Summarise every dbt test result from this run; fail on any blocking one."""
        counts: dict[str, int] = {}
        problems: list[str] = []

        for layer, _ in LAYERS:
            results_path = Path(DBT_DIR, "target", layer, "run_results.json")
            if not results_path.exists():
                problems.append(f"{layer}: did not run")
                continue
            for result in json.loads(results_path.read_text())["results"]:
                if not result["unique_id"].startswith("test."):
                    continue
                status = result["status"]
                counts[status] = counts.get(status, 0) + 1
                if status != "pass":
                    problems.append(
                        f"{layer}: {status.upper()} {result['unique_id']} "
                        f"({result.get('failures')} failing rows)"
                    )

        print(f"Test results: {counts}")
        for line in problems:
            print(line)
        print(
            "Failing rows for any test are queryable in DuckDB at "
            "main_dbt_test__audit.<test_name> (store_failures is on)."
        )

        # warn-severity tests are reported above but don't block training.
        blocking = counts.get("fail", 0) + counts.get("error", 0)
        if blocking or any(p.endswith("did not run") for p in problems):
            raise RuntimeError(
                f"{blocking} blocking test failure(s) - not training on this data."
            )
        return counts

    train_and_evaluate_model = BashOperator(
        task_id="train_and_evaluate_model",
        # --ExecutePreprocessor.kernel_name=python3 overrides the notebook's
        # own stale kernelspec metadata, which doesn't exist in this container.
        bash_command=(
            "jupyter nbconvert --to notebook --execute --inplace "
            "--ExecutePreprocessor.kernel_name=python3 "
            '"Depression Type Classification Analysis.ipynb"'
        ),
        cwd=PROJECT_DIR,
    )

    dbt_docs_generate = BashOperator(
        task_id="dbt_docs_generate",
        bash_command=f"dbt docs generate {DBT_FLAGS}",
        cwd=DBT_DIR,
    )

    # Strictly linear on purpose: DuckDB allows only one read-write process
    # per database file, so two tasks opening it at once can fail with a lock
    # error (docs generation and training used to run in parallel).
    for upstream, downstream in zip(build_tasks, build_tasks[1:]):
        upstream >> downstream
    build_tasks[-1] >> quality_report() >> train_and_evaluate_model >> dbt_docs_generate
