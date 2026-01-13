# Use the variables
locals {
  input_bucket_name  = "request-input-${var.bucket_name_suffix}"
  output_bucket_name = "response-output-${var.bucket_name_suffix}"
}

# 1. Create the input S3 bucket
resource "aws_s3_bucket" "input_bucket" {
  bucket        = local.input_bucket_name
  force_destroy = true # Allows the bucket to be deleted even if not empty (for 'terraform destroy')
}

# Create the 'input/' folder by uploading a dummy object (optional but good practice)
resource "aws_s3_object" "input_folder" {
  bucket = aws_s3_bucket.input_bucket.id
  key    = "input/"
}

# 2. Create the output S3 bucket
resource "aws_s3_bucket" "output_bucket" {
  bucket        = local.output_bucket_name
  force_destroy = true
}

# Create the 'output/' folder
resource "aws_s3_object" "output_folder" {
  bucket = aws_s3_bucket.output_bucket.id
  key    = "output/"
}

# 3. Create the IAM Role for Lambda
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_translate_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# 4. Attach IAM Policies to the Role
# Policy for Lambda basic execution (writing to CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Custom policy for S3, Translate, and CloudWatch permissions
resource "aws_iam_policy" "lambda_translate_policy" {
  name        = "lambda_translate_policy"
  description = "Policy for Lambda to read S3, use Translate, and write to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.input_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.output_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "translate:TranslateText"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_translate_attachment" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_translate_policy.arn
}

# 5. Create the Lambda function
# First, create a ZIP archive of the Lambda code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "index.py"
  output_path = "lambda_function.zip"
}

# Now create the Lambda function, using the ZIP file
resource "aws_lambda_function" "translate_function" {
  filename         = "lambda_function.zip"
  function_name    = "s3_triggered_translator"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Inject the output bucket name as an environment variable
  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
    }
  }
}

# 6. Allow S3 to invoke the Lambda function
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.translate_function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input_bucket.arn
}

# 7. Configure S3 Event Notification to trigger Lambda
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.input_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.translate_function.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/" # Only trigger for objects in the 'input/' folder
    filter_suffix       = ".json"  # Only trigger for .json files
  }

  depends_on = [aws_lambda_permission.allow_bucket] # Ensure permission is set first
}

# 8. Output the bucket names for easy reference
output "input_bucket_name" {
  value = aws_s3_bucket.input_bucket.bucket
}

output "output_bucket_name" {
  value = aws_s3_bucket.output_bucket.bucket
}