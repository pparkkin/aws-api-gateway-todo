import json
import boto3

def post_todos(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('todos')
    res = {
      "id": "rickysnickle"
    }
    return {
        "isBase64Encoded": False,
        "statusCode": 200,
        # "headers": { "headerName": "headerValue", ... },
        "body": json.dumps(res)
    }
