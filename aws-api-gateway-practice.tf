provider "aws" {
  region = "${var.region}"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = "${file("lambda-role.json")}"
}

resource "aws_lambda_function" "get_todos" {
  filename = "get_todos.zip"
  function_name = "get_todos"
  role = "${aws_iam_role.iam_for_lambda.arn}"
  handler = "get_todos.get_todos"
  source_code_hash = "${base64sha256(file("get_todos.zip"))}"
  runtime = "python3.6"
}

resource "aws_api_gateway_rest_api" "TODOAPI" {
  name        = "MyTODO"
  description = "My first API with Amazon API Gateway"
}

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
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.get_todos.arn}"
  principal     = "apigateway.amazonaws.com"

  # More: http://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-control-access-using-iam-policies-to-invoke-api.html
  source_arn = "arn:aws:execute-api:${var.region}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.TODOAPI.id}/*/${aws_api_gateway_method.TODOAPI_todos_get.http_method}${aws_api_gateway_resource.TODOAPI_todos.path}"
}

resource "aws_api_gateway_deployment" "TODOAPI_deployment" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  stage_name  = "test"
  depends_on = ["aws_api_gateway_integration.TODOAPI_todos_get_integration"]
}

output "api_id" {
  value = "${aws_api_gateway_rest_api.TODOAPI.id}"
}

output "api_invoke_url" {
  value = "${aws_api_gateway_deployment.TODOAPI_deployment.invoke_url}"
}
