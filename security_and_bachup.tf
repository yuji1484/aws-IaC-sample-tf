provider "aws" {
  region = "ap-northeast-1"
}

# --------------------------------------
# S3 バケット（バックアップ保存用 / Immutable Backup）
# --------------------------------------
resource "aws_s3_bucket" "backup" {
  bucket = "company-backup-bucket"
}

resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = 365  # 1年間の保管期間（要件に応じて調整）
    }
  }
}

resource "aws_s3_bucket_encryption" "backup" {
  bucket = aws_s3_bucket.backup.id
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

# --------------------------------------
# AWS Backup - 自動バックアップ管理
# --------------------------------------
resource "aws_backup_vault" "default" {
  name = "backup-vault"
  kms_key_arn = aws_kms_key.backup.arn
}

resource "aws_backup_plan" "default" {
  name = "daily-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.default.name
    schedule          = "cron(0 2 * * ? *)" # 毎日 UTC 2:00 に実行
    lifecycle {
      delete_after = 180 # 180日後に自動削除
    }
  }
}

resource "aws_backup_selection" "backup_resources" {
  name          = "backup-selection"
  iam_role_arn  = aws_iam_role.backup_role.arn
  plan_id       = aws_backup_plan.default.id
  resources     = ["arn:aws:ec2:*:*:instance/*", "arn:aws:rds:*:*:db:*"]
}

# --------------------------------------
# CloudTrail - API コールログの取得
# --------------------------------------
resource "aws_cloudtrail" "main" {
  name                          = "cloudtrail"
  s3_bucket_name                = aws_s3_bucket.backup.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_logging                = true
}

# --------------------------------------
# AWS Config - 設定変更の記録
# --------------------------------------
resource "aws_config_configuration_recorder" "main" {
  name     = "config-recorder"
  role_arn = aws_iam_role.config_role.arn
}

resource "aws_config_delivery_channel" "main" {
  name           = "config-delivery"
  s3_bucket_name = aws_s3_bucket.backup.id
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
}

# --------------------------------------
# CloudWatch Logs - 180日以上のログ保存
# --------------------------------------
resource "aws_cloudwatch_log_group" "application_logs" {
  name              = "/aws/application/logs"
  retention_in_days = 180
}

resource "aws_cloudwatch_log_group" "security_logs" {
  name              = "/aws/security/logs"
  retention_in_days = 365
}

# --------------------------------------
# GuardDuty - セキュリティ異常検知
# --------------------------------------
resource "aws_guardduty_detector" "main" {
  enable = true
}

# --------------------------------------
# Security Hub - セキュリティ統合監視
# --------------------------------------
resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0"
}

# --------------------------------------
# IAM ロール（AWS Backup, AWS Config 用）
# --------------------------------------
resource "aws_iam_role" "backup_role" {
  name = "AWSBackupRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backup_role_policy" {
  role       = aws_iam_role.backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role" "config_role" {
  name = "AWSConfigRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "config_role_policy" {
  role       = aws_iam_role.config_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

# --------------------------------------
# KMS キー（バックアップデータ暗号化用）
# --------------------------------------
resource "aws_kms_key" "backup" {
  description = "KMS key for backup encryption"
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "backup" {
  name          = "alias/backup-key"
  target_key_id = aws_kms_key.backup.key_id
}