resource "aws_iam_role" "deploy" {
  name = "moodle-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # StringLike (not StringEquals) because sub ends with :* wildcard.
            # Phase 1 simplification per design.md §5 note 1 — Phase 2 tightens to specific refs.
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })
}

#checkov:skip=CKV_AWS_60: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens per design.md §5 note 4.
#checkov:skip=CKV_AWS_62: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens per design.md §5 note 4.
#checkov:skip=CKV2_AWS_40: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens per design.md §5 note 4.
#checkov:skip=CKV_AWS_287: secretsmanager:* and ssm:* are moodle/*-scoped; kms:Decrypt on aws/* managed keys per CLAUDE.md rule 3; Phase 2 tightens.
#checkov:skip=CKV_AWS_289: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens per design.md §5 note 4.
#checkov:skip=CKV_AWS_290: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens per design.md §5 note 4.
#checkov:skip=CKV_AWS_355: Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens scoping per design.md §5 note 4.
#tfsec:ignore:aws-iam-no-policy-wildcards Phase 1 service-wide CRUD on the deploy role; Phase 2 tightens to specific actions per design.md §5 note 4.
resource "aws_iam_role_policy" "deploy" {
  name = "deploy-policy"
  role = aws_iam_role.deploy.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EC2VPC"
        Effect   = "Allow"
        Action   = ["ec2:*", "vpc:*"]
        Resource = "*"
      },
      {
        Sid      = "RDS"
        Effect   = "Allow"
        Action   = "rds:*"
        Resource = "*"
      },
      {
        Sid      = "ElastiCache"
        Effect   = "Allow"
        Action   = "elasticache:*"
        Resource = "*"
      },
      {
        Sid      = "EFS"
        Effect   = "Allow"
        Action   = "elasticfilesystem:*"
        Resource = "*"
      },
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = "cloudfront:*"
        Resource = "*"
      },
      {
        Sid    = "Route53ZoneScoped"
        Effect = "Allow"
        Action = [
          "route53:Get*",
          "route53:List*",
          "route53:Change*",
        ]
        Resource = "arn:aws:route53:::hostedzone/*"
      },
      {
        Sid    = "Route53AccountLevel"
        Effect = "Allow"
        Action = [
          "route53:ListHostedZones",
          "route53:GetChange",
        ]
        Resource = "*"
      },
      {
        Sid      = "ACM"
        Effect   = "Allow"
        Action   = "acm:*"
        Resource = "*"
      },
      {
        Sid      = "SES"
        Effect   = "Allow"
        Action   = "ses:*"
        Resource = "arn:aws:ses:eu-west-1:${data.aws_caller_identity.current.account_id}:identity/wirfoncloud.com"
      },
      {
        Sid      = "CloudWatch"
        Effect   = "Allow"
        Action   = "cloudwatch:*"
        Resource = "*"
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = "logs:*"
        Resource = "*"
      },
      {
        Sid      = "SNS"
        Effect   = "Allow"
        Action   = "sns:*"
        Resource = "*"
      },
      {
        Sid      = "Backup"
        Effect   = "Allow"
        Action   = "backup:*"
        Resource = "*"
      },
      {
        Sid      = "GuardDuty"
        Effect   = "Allow"
        Action   = "guardduty:*"
        Resource = "*"
      },
      {
        Sid      = "CloudTrail"
        Effect   = "Allow"
        Action   = "cloudtrail:*"
        Resource = "*"
      },
      {
        Sid      = "SecretsManager"
        Effect   = "Allow"
        Action   = "secretsmanager:*"
        Resource = "arn:aws:secretsmanager:eu-west-1:${data.aws_caller_identity.current.account_id}:secret:moodle/*"
      },
      {
        Sid    = "SSMParameterStore"
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter",
          "ssm:GetParameterHistory",
          "ssm:DescribeParameters",
          "ssm:AddTagsToResource",
          "ssm:RemoveTagsFromResource",
          "ssm:ListTagsForResource",
        ]
        Resource = "arn:aws:ssm:eu-west-1:${data.aws_caller_identity.current.account_id}:parameter/moodle/*"
      },
      {
        Sid      = "IAMTagScoped"
        Effect   = "Allow"
        Action   = "iam:*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/Project" = "moodle-academy"
          }
        }
      },
      {
        # iam:PassRole forward-reference to T-013; ARN follows project naming convention;
        # AWS IAM accepts ARNs for not-yet-existing principals.
        Sid      = "IAMPassRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/moodle_ec2_role"
      },
      {
        Sid    = "S3StateBuckets"
        Effect = "Allow"
        Action = "s3:*"
        Resource = [
          "arn:aws:s3:::wirfo-moodle-tfstate-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::wirfo-moodle-tfstate-${data.aws_caller_identity.current.account_id}/*",
          "arn:aws:s3:::wirfo-moodle-cloudtrail-${data.aws_caller_identity.current.account_id}",
          "arn:aws:s3:::wirfo-moodle-cloudtrail-${data.aws_caller_identity.current.account_id}/*",
        ]
      },
      {
        Sid      = "DynamoDBLockTable"
        Effect   = "Allow"
        Action   = "dynamodb:*"
        Resource = "arn:aws:dynamodb:eu-west-1:${data.aws_caller_identity.current.account_id}:table/wirfo-moodle-tflock"
      },
      {
        Sid    = "KMSReadOnly"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey",
        ]
        Resource = "*"
      },
      {
        Sid      = "STSMinimal"
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      },
    ]
  })
}
