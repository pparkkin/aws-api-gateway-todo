# AWS Lambda TODO API

A little experiment in AWS Lambda, API Gateway, and DynamoDB.

## Usage

Install the boto3 library for your lambda.

```
pip install boto3 -t ./lambdas
```

Deploy using Terraform.

```
terraform apply
```

Terraform will output the API endpoint URL, which you can use to call the API.

```
curl https://<api_invoke_url>/todos
```
