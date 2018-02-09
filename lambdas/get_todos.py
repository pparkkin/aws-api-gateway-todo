import json

import boto3

def get_todos(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('todos')
    res = table.scan()
    if res is None:
        items = []
    else:
        items = res.get("Items", [])
    return {
        "isBase64Encoded": False,
        "statusCode": 200,
        # "headers": { "headerName": "headerValue", ... },
        "body": json.dumps(items)
    }
