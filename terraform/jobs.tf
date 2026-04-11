resource "databricks_job" "subscription_churn_pipeline" {
  name = local.pipeline_job_name

  git_source {
    url      = var.git_url
    provider = var.git_provider
    branch   = var.git_branch
  }

  schedule {
    quartz_cron_expression = var.job_cron_expression
    timezone_id            = var.job_timezone
    pause_status           = var.job_pause_status
  }

  task {
    task_key = "generate_subscription_events"

    spark_python_task {
      python_file = var.subscription_events_script_path
      source      = "WORKSPACE"
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "generate_viewing_sessions"

    spark_python_task {
      python_file = var.viewing_sessions_script_path
      source      = "WORKSPACE"
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "create_bronze_tables"

    depends_on {
      task_key = "generate_subscription_events"
    }

    depends_on {
      task_key = "generate_viewing_sessions"
    }

    spark_python_task {
      python_file = var.bronze_loader_script_path
      source      = "WORKSPACE"
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "dbt_seed"

    depends_on {
      task_key = "create_bronze_tables"
    }

    # Each dbt task runs deps first because Databricks task workspaces are isolated.
    # This keeps task-level observability while ensuring dbt_packages exists.
    dbt_task {
      commands = [
        "dbt deps",
        "dbt seed"
      ]
      source       = "GIT"
      warehouse_id = var.warehouse_id
      catalog      = var.dbt_catalog
      schema       = var.dbt_schema
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "dbt_run_silver"

    depends_on {
      task_key = "dbt_seed"
    }

    # Install packages in this task as well because Databricks does not share
    # dbt_packages from dbt_seed with downstream dbt tasks.
    dbt_task {
      commands = [
        "dbt deps",
        "dbt run --select models/silver"
      ]
      source       = "GIT"
      warehouse_id = var.warehouse_id
      catalog      = var.dbt_catalog
      schema       = var.dbt_schema
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "dbt_run_gold"

    depends_on {
      task_key = "dbt_run_silver"
    }

    # Install packages in this task as well because each dbt task is isolated.
    dbt_task {
      commands = [
        "dbt deps",
        "dbt run --select models/gold"
      ]
      source       = "GIT"
      warehouse_id = var.warehouse_id
      catalog      = var.dbt_catalog
      schema       = var.dbt_schema
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "dbt_test"

    depends_on {
      task_key = "dbt_run_gold"
    }

    # Install packages before testing so generic tests from packages are available.
    dbt_task {
      commands = [
        "dbt deps",
        "dbt test"
      ]
      source       = "GIT"
      warehouse_id = var.warehouse_id
      catalog      = var.dbt_catalog
      schema       = var.dbt_schema
    }

    environment_key = local.python_env_key
  }

  environment {
    environment_key = local.python_env_key

    spec {
      dependencies = [
        "faker",
        "pandas",
        "numpy",
        "dbt-databricks==1.11.6"
      ]

      environment_version = "4"
    }
  }

  queue {
    enabled = true
  }
}
