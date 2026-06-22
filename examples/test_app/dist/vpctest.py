import json
import socket

def handler(event, context):

    try:
        host = event['queryStringParameters']['host']
        port = event['queryStringParameters']['port']
    except KeyError as e:
        return {
            'statusCode': 500,
            'body': f"Missing parameter(s)?: {e}"
        }

    try:
        socket.setdefaulttimeout(1)
        socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect((host, int(port)))

        return {
            'statusCode': 200,
            'body': json.dumps(event['queryStringParameters'])
        }
    except socket.error as ex:
        return {
            'statusCode': 500,
            'body': json.dumps(f"Couldn't do the things: {ex}")
            }

if __name__ == "__main__":
    event = {'queryStringParameters' : {'host' : '8.8.8.8', 'port' : 53}}

    print(handler(event, context=''))
