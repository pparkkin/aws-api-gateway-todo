provider "aws" {
  region = "${var.region}"
}

resource "aws_api_gateway_rest_api" "TODOAPI" {
  name        = "MyTODO"
  description = "My first API with Amazon API Gateway"
  body = "${file("api.json")}"
}

resource "aws_api_gateway_deployment" "TODOAPIDeployment" {
  rest_api_id = "${aws_api_gateway_rest_api.TODOAPI.id}"
  stage_name  = "test"
  # Workaround for deployment not being updated when API changes
  # see https://github.com/hashicorp/terraform/issues/6613
  stage_description = "${md5(file("api.json"))}"
}

output "api_id" {
  value = "${aws_api_gateway_rest_api.TODOAPI.id}"
}

output "api_invoke_url" {
  value = "${aws_api_gateway_deployment.TODOAPIDeployment.invoke_url}"
}
