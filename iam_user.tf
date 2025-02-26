provider "aws" {
  region = "ap-northeast-1"
}

# IAMユーザーの作成
resource "aws_iam_user" "example_user" {
  name = "example-user"
}

# IAMユーザーのログインプロファイル（初回ログイン時のパスワード設定）
resource "aws_iam_user_login_profile" "example_user" {
  user                    = aws_iam_user.example_user.name
  password_length         = 16
  password_reset_required = true
}

# IAMアクセスキーの作成
resource "aws_iam_access_key" "example_user" {
  user = aws_iam_user.example_user.name
}

# MFA（多要素認証）の必須化
resource "aws_iam_user_policy" "require_mfa" {
  name   = "require-mfa"
  user   = aws_iam_user.example_user.name
  policy = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
EOT
}

# パスワードポリシーの設定
resource "aws_iam_account_password_policy" "password_policy" {
  minimum_password_length        = 14
  require_symbols                = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 5
  hard_expiry                    = true
}

# セッション時間の制限（最大1時間）
resource "aws_iam_policy" "limit_session_duration" {
  name        = "LimitSessionDuration"
  description = "Restrict session duration to 1 hour"
  policy      = <<EOT
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "sts:AssumeRole",
      "Resource": "*",
      "Condition": {
        "NumericGreaterThan": {
          "aws:MultiFactorAuthAge": "3600"
        }
      }
    }
  ]
}
EOT
}

# IAMユーザーにポリシーをアタッチ
resource "aws_iam_user_policy_attachment" "attach_session_limit" {
  user       = aws_iam_user.example_user.name
  policy_arn = aws_iam_policy.limit_session_duration.arn
}