import json
import boto3

def get_todos(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('todos')
    res = [
        { 'ctime': str(table.creation_date_time) }
    ]
    return {
        "isBase64Encoded": False,
        "statusCode": 200,
        # "headers": { "headerName": "headerValue", ... },
        "body": json.dumps(res)
    }
