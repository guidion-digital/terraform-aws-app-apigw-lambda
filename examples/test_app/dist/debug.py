import json

def handler(event, context):

    try:
        event['headers'].pop('x-api-key', "NONE")
        event['requestContext']['identity'].pop('apiKey', "NONE")
    except KeyError:
        print("Didn't delete API key, because this is a local context. Probably")

    return {
        'statusCode': 200,
        'body': json.dumps(event)
    }
