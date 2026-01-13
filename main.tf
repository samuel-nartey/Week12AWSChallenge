# =========================
# Local variables
# =========================
locals {
  input_bucket_name  = "request-input-${var.bucket_name_suffix}"
  output_bucket_name = "response-output-${var.bucket_name_suffix}"
}

# =========================
# 1. Input S3 bucket
# =========================
resource "aws_s3_bucket" "input_bucket" {
  bucket        = local.input_bucket_name
  force_destroy = true
}

resource "aws_s3_object" "input_folder" {
  bucket = aws_s3_bucket.input_bucket.id
  key    = "input/"
}

# =========================
# 2. Output S3 bucket
# =========================
resource "aws_s3_bucket" "output_bucket" {
  bucket        = local.output_bucket_name
  force_destroy = true
}

resource "aws_s3_object" "output_folder" {
  bucket  = aws_s3_bucket.output_bucket.id
  key     = "output/"
  content = ""
}

# =========================
# 3. IAM Role for Lambda
# =========================
resource "aws_iam_role" "lambda_exec_role" {
  name_prefix = "lambda-translate-exec-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# =========================
# 4. IAM Policies
# =========================

# Basic Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom Translate + S3 policy (FIXED)
resource "aws_iam_policy" "lambda_translate_policy" {
  name_prefix = "lambda-translate-policy-"
  description = "Policy for Lambda to read input S3, write output S3, and call Amazon Translate"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.input_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.output_bucket.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["translate:TranslateText"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_translate_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_translate_policy.arn
}

# =========================
# 5. Lambda function
# =========================
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/index.py"
  output_path = "${path.module}/lambda_function.zip"
}


resource "aws_lambda_function" "translate_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-triggered-translator"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
    }
  }
}

# =========================
# 6. Allow S3 → Lambda
# =========================
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translate_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

# =========================
# 7. S3 event notification
# =========================
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.translate_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# =========================
# 8. Outputs
# =========================
output "input_bucket_name" {
  value = aws_s3_bucket.input_bucket.bucket
}

output "output_bucket_name" {
  value = aws_s3_bucket.output_bucket.bucket
}
