resource "databricks_job" "generating" {
  name = local.generating_job_name

  schedule {
    quartz_cron_expression = var.job_cron_expression
    timezone_id            = var.job_timezone
    pause_status           = "UNPAUSED"
  }


  # Task 1: Generate Subscription Events (runs in parallel with Task 2)
  task {
    task_key = "generate_subscription_events"

    spark_python_task {
      python_file = "${local.repo_base_path}/generate_subscription_events.py"
    }

    environment_key = local.python_env_key
  }

  # Task 2: Generate Viewing Sessions (runs in parallel with Task 1)
  task {
    task_key = "generate_viewing_sessions"

    spark_python_task {
      python_file = "${local.repo_base_path}/generate_viewing_sessions.py"
    }

    environment_key = local.python_env_key
  }

  # Task 3: Create Bronze Tables (waits for Task 1 & 2 to complete)
  task {
    task_key = "create_bronze_tables"

    depends_on {
      task_key = "generate_subscription_events"
    }
    depends_on {
      task_key = "generate_viewing_sessions"
    }

    spark_python_task {
      python_file = "${local.repo_base_path}/createTable.py"
    }

    environment_key = local.python_env_key
  }

  # Serverless environment for Task 1, 2 and 3
  environment {
    environment_key = local.python_env_key
    spec {
      dependencies        = ["faker", "pandas", "numpy"]
      environment_version = "4"
    }
  }

  queue {
    enabled = true
  }
}
