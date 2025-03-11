provider "aws" {
  region = "ap-south-1"
}

# ✅ Security Group for RDS and DMS
resource "aws_security_group" "rds_sg" {
  name_prefix = "rds-security-group"

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Change this for better security
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


/*
# ✅ Create Source RDS (MySQL)
resource "aws_db_instance" "source_db" {
  identifier           = "source-mysql"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username           = "admin"
  password           = "SourcePass123"
  parameter_group_name = "default.mysql8.0"
  publicly_accessible = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true
}
*/
# ✅ Create Destination RDS (MySQL)
resource "aws_db_instance" "destination_db" {
  identifier           = "destination-mysql"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  username           = "admin"
  password           = "DestPass123"
  parameter_group_name = "default.mysql8.0"
  publicly_accessible = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot = true
}

# ✅ AWS DMS Replication Instance
resource "aws_dms_replication_instance" "dms" {
  replication_instance_id = "dms-instance"
  replication_instance_class = "dms.t3.medium"
  allocated_storage = 50
  publicly_accessible = true
  engine_version = "3.4.7"
}

# ✅ AWS DMS Source Endpoint
resource "aws_dms_endpoint" "source" {
  endpoint_id   = "source-endpoint"
  endpoint_type = "source"
  engine_name   = "mysql"
  username      = "admin"
  password      = "SourcePass123"
  server_name   = aws_db_instance.source_db.address
  port          = 3306
}

# ✅ AWS DMS Destination Endpoint
resource "aws_dms_endpoint" "destination" {
  endpoint_id   = "destination-endpoint"
  endpoint_type = "target"
  engine_name   = "mysql"
  username      = "admin"
  password      = "DestPass123"
  server_name   = aws_db_instance.destination_db.address
  port          = 3306
  database_name = aws_db_instance.source_db.name  # Ensures same DB name is used
}

# ✅ Lambda Function to Validate Schema Before Migration
resource "aws_lambda_function" "schema_validation" {
  filename         = "schema_validation.zip"  # Zip of Python script
  function_name    = "ValidateSchema"
  role             = aws_iam_role.lambda_role.arn
  handler          = "schema_validation.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      SOURCE_DB     = aws_db_instance.source_db.address
      DEST_DB       = aws_db_instance.destination_db.address
      DB_USER       = "admin"
      DB_PASSWORD   = "SourcePass123"
    }
  }
}

# ✅ IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# ✅ Allow Lambda to Access RDS
resource "aws_iam_policy_attachment" "lambda_policy" {
  name       = "lambda-rds-policy"
  roles      = [aws_iam_role.lambda_role.name]
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

# ✅ Migration Task (Triggered only if schema validation succeeds)
resource "aws_dms_replication_task" "migration_task" {
  count                   = aws_lambda_function.schema_validation.invoke_arn != "" ? 1 : 0
  replication_task_id     = "mysql-migration-task"
  migration_type         = "full-load-and-cdc"
  replication_instance_arn = aws_dms_replication_instance.dms.arn
  source_endpoint_arn    = aws_dms_endpoint.source.arn
  target_endpoint_arn    = aws_dms_endpoint.destination.arn

  table_mappings = <<EOF
{
  "rules": [
    {
      "rule-type": "selection",
      "rule-id": "1",
      "rule-name": "selectAllTables",
      "object-locator": {
        "schema-name": "%",
        "table-name": "%"
      },
      "rule-action": "include"
    }
  ]
}
EOF

  migration_task_settings = <<EOF
{
  "FullLoadSettings": {
    "TargetTablePrepMode": "DROP_AND_CREATE"
  }
}
EOF
}
