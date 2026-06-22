import boto3

client = boto3.client('dynamodb')

def handler(event, context):
  try:
    table_name = event['queryStringParameters']['table-name']
    id = event['queryStringParameters']['id']
    bar = event['queryStringParameters']['bar']
  except KeyError:
    return {
        'statusCode': 500,
        'body': f"Couldn't find some keys. The parameters were: {event['queryStringParameters']}",
        'headers': {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
    }

  data = client.put_item(
    TableName = table_name,
    Item = {
       'id': { 'N': id },
       'bar': {'S': bar }
    }
  )

  response = {
      'statusCode': 200,
      'body': f"Success with: {event['queryStringParameters']}",
      'headers': {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
  }

  return response

if __name__ == "__main__":
    event = {'queryStringParameters' : {'table-name' : 'test-app-footable', 'id' : '5', 'bar' : 'foo' }}
    print(handler(event, context=''))
