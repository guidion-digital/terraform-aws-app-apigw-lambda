import boto3

client = boto3.client('sqs')


def handler(event, context):

    try:
      queue_name = event['queryStringParameters']['queue-name']
    except KeyError:
      return {
          'statusCode': 500,
          'body': f"Couldn't find some keys. The parameters were: {event['queryStringParameters']}",
          'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
          },
      }

    queue_url = client.get_queue_url(QueueName=queue_name)["QueueUrl"]
    messages = client.receive_message(
        QueueUrl=queue_url
    )
    return {
      'statusCode': 200,
      'body': f"Success with: {event['queryStringParameters']} — Message: {messages}",
      'headers': {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
  }

if __name__ == "__main__":
    event = {'queryStringParameters' : {'queue-name' : 'test-app-queue-x' }}
    print(handler(event, context=''))
