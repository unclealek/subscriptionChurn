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
    task_key = "dbt_deps"

    depends_on {
      task_key = "create_bronze_tables"
    }

    dbt_task {
      commands     = ["dbt deps"]
      source       = "GIT"
      warehouse_id = var.warehouse_id
      catalog      = var.dbt_catalog
      schema       = var.dbt_schema
    }

    environment_key = local.python_env_key
  }

  task {
    task_key = "dbt_seed"

    depends_on {
      task_key = "dbt_deps"
    }

    dbt_task {
      commands     = ["dbt seed"]
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

    dbt_task {
      commands     = ["dbt run --select models/silver"]
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

    dbt_task {
      commands     = ["dbt run --select models/gold"]
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

    dbt_task {
      commands     = ["dbt test"]
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
