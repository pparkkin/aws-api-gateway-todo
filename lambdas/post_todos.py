import json
import uuid

import boto3

def post_todos(event, context):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('todos')
    body = json.loads(event.get('body', "{}"))
    todo = body.get('todo', None)
    res = {
      "success": True
    }
    if todo is not None:
        # store in table
        todoid = str(uuid.uuid1())
        item = { "TodoId": todoid, "todo": todo }
        table.put_item(Item = item)
        res["TodoId"] = todoid
    return {
        "isBase64Encoded": False,
        "statusCode": 200,
        # "headers": { "headerName": "headerValue", ... },
        "body": json.dumps(res)
    }
