provider "aws" {
  region = "${var.region}"
}

data "aws_caller_identity" "current" {}

# == IAM roles

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = "${file("lambda-role.json")}"
}

resource "aws_iam_policy" "iam_for_s3" {
  name = "iam_for_s3"
  policy = "${file("s3-policy.json")}"
}

resource "aws_iam_policy_attachment" "lambda_s3" {
  name       = "lambda_s3"
  roles      = ["${aws_iam_role.iam_for_lambda.name}"]
  policy_arn = "${aws_iam_policy.iam_for_s3.arn}"
}

resource "aws_iam_policy" "iam_for_dynamodb" {
  name = "iam_for_dynamodb"
  policy = "${file("dynamodb-policy.json")}"
}

resource "aws_iam_policy_attachment" "lambda_dynamodb" {
  name       = "lambda_dynamodb"
  roles      = ["${aws_iam_role.iam_for_lambda.name}"]
  policy_arn = "${aws_iam_policy.iam_for_dynamodb.arn}"
}

# == DynamoDB Table

resource "aws_dynamodb_table" "todos" {
  name = "todos"
  hash_key = "TodoId"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "TodoId"
    type = "S"
  }
}

# == Lambdas

data "archive_file" "lambdas" {
  type = "zip"
  source_dir = "lambdas"
  output_path = "lambdas.zip"
}

resource "aws_lambda_function" "get_todos" {
  filename = "lambdas.zip"
  function_name = "get_todos"
  role = "${aws_iam_role.iam_for_lambda.arn}"
  handler = "get_todos.get_todos"
  source_code_hash = "${data.archive_file.lambdas.output_base64sha256}"
  runtime = "python3.6"
}

resource "aws_lambda_function" "post_todos" {
  filename = "lambdas.zip"
  function_name = "post_todos"
  role = "${aws_iam_role.iam_for_lambda.arn}"
  handler = "post_todos.post_todos"
  source_code_hash = "${data.archive_file.lambdas.output_base64sha256}"
  runtime = "python3.6"
}

# == API Gateway

resource "aws_api_gateway_rest_api" "TODOAPI" {
  name        = "MyTODO"
  description = "My first API with Amazon API Gateway"
}

# == /

resource "aws_s3_bucket" "TODOAPI_root" {
  bucket = "todoapi"
  acl = "private"
}

resource "aws_s3_bucket_object" "TODOAPI_index" {
  bucket = "${aws_s3_bucket.TODOAPI_root.id}"
  key = "index"
  source = "index.html"
  content_type = "text/html"
  etag = "${md5(file("index.html"))}"
}

resource "aws_api_gateway_method" "TODOAPI_root_get" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_rest_api.TODOAPI.root_resource_id}"
  http_method = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "TODOAPI_root_get_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_rest_api.TODOAPI.root_resource_id}"
  http_method = "${aws_api_gateway_method.TODOAPI_root_get.http_method}"
  type = "AWS"
  credentials = "${aws_iam_role.iam_for_lambda.arn}"
  uri = "arn:aws:apigateway:${var.region}:s3:path/${aws_s3_bucket.TODOAPI_root.id}/index"
  integration_http_method = "GET"
}

resource "aws_api_gateway_method_response" "200" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_rest_api.TODOAPI.root_resource_id}"
  http_method = "${aws_api_gateway_method.TODOAPI_root_get.http_method}"
  status_code = "200"
  response_parameters = {
    "method.response.header.Content-Type" = true
  }
}

resource "aws_api_gateway_integration_response" "TODOAPI_root_get_integration_response" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_rest_api.TODOAPI.root_resource_id}"
  http_method = "${aws_api_gateway_method.TODOAPI_root_get.http_method}"
  status_code = "${aws_api_gateway_method_response.200.status_code}"
  selection_pattern = "-" # make default
  response_parameters = {
    "method.response.header.Content-Type" = "integration.response.header.Content-Type"
  }
  # Explicit depends to fix race condition
  depends_on = [
    "aws_api_gateway_integration.TODOAPI_root_get_integration"
  ]
}

# == /todos

resource "aws_api_gateway_resource" "TODOAPI_todos" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  parent_id = "${aws_api_gateway_rest_api.TODOAPI.root_resource_id}"
  path_part = "todos"
}

resource "aws_api_gateway_method" "TODOAPI_todos_get" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_resource.TODOAPI_todos.id}"
  http_method = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "TODOAPI_todos_get_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_resource.TODOAPI_todos.id}"
  http_method = "${aws_api_gateway_method.TODOAPI_todos_get.http_method}"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.get_todos.arn}/invocations"
  # This needs to be POST for the integration to work.
  # Does not need to match the API method.
  # https://github.com/hashicorp/terraform/issues/9271
  integration_http_method = "POST"
}

# This is very important, and very picky about the configuration values!
# If this is not set up correctly the integration will not have permission
# to call the lambda, and the API calls will fail.
# see:
# - https://github.com/awslabs/aws-apigateway-importer/issues/170
# - https://www.terraform.io/docs/providers/aws/r/api_gateway_integration.html#lambda-integration
resource "aws_lambda_permission" "apigw_lambda_get_todos" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.get_todos.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.TODOAPI.id}/*/${aws_api_gateway_method.TODOAPI_todos_get.http_method}${aws_api_gateway_resource.TODOAPI_todos.path}"
}

resource "aws_api_gateway_method" "TODOAPI_todos_post" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_resource.TODOAPI_todos.id}"
  http_method = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "TODOAPI_todos_post_integration" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  resource_id = "${aws_api_gateway_resource.TODOAPI_todos.id}"
  http_method = "${aws_api_gateway_method.TODOAPI_todos_post.http_method}"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.post_todos.arn}/invocations"
  # This needs to be POST for the integration to work.
  # Does not need to match the API method.
  # https://github.com/hashicorp/terraform/issues/9271
  integration_http_method = "POST"
}

# This is very important, and very picky about the configuration values!
# If this is not set up correctly the integration will not have permission
# to call the lambda, and the API calls will fail.
# see:
# - https://github.com/awslabs/aws-apigateway-importer/issues/170
# - https://www.terraform.io/docs/providers/aws/r/api_gateway_integration.html#lambda-integration
resource "aws_lambda_permission" "apigw_lambda_post_todos" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.post_todos.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.TODOAPI.id}/*/${aws_api_gateway_method.TODOAPI_todos_post.http_method}${aws_api_gateway_resource.TODOAPI_todos.path}"
}

# == API Deployment

resource "aws_api_gateway_deployment" "TODOAPI_deployment" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  stage_name  = "test"
  # Need to explicitly depend on the integrations to make sure they're all set
  # up before deploying the API.
  depends_on = [
    "aws_api_gateway_integration.TODOAPI_todos_get_integration",
    "aws_api_gateway_integration.TODOAPI_root_get_integration"
  ]
}

# == Outputs

output "api_id" {
  value = "${aws_api_gateway_rest_api.TODOAPI.id}"
}

output "api_invoke_url" {
  value = "${aws_api_gateway_deployment.TODOAPI_deployment.invoke_url}"
}
