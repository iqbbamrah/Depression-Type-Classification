# Extends the official Airflow image with the packages the DAG's tasks
# actually shell out to: dbt (for the data pipeline) and the sklearn/jupyter
# stack (to execute the modeling notebook headlessly).
FROM apache/airflow:3.3.2

COPY requirements.txt /requirements.txt
RUN pip install --no-cache-dir -r /requirements.txt
