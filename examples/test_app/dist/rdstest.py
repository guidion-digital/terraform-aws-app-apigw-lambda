import boto3
import pymysql
import os

# WIP this file needs adjusting and double checking, it is LLM code as a starting point

def get_rds_connection():
    username = os.environ.get('RDS_USERNAME')
    db_name = os.environ.get('RDS_DB_NAME')
    rds_host = os.environ.get('RDS_HOST')

    # Get password from Secrets Manager
    secret_name = os.environ.get('RDS_PASSWORD_SECRET_NAME')
    session = boto3.session.Session()
    client = session.client('secretsmanager')

    try:
        secret_response = client.get_secret_value(SecretId=secret_name)
        password = secret_response['SecretString']

        conn = pymysql.connect(
            host=rds_host,
            user=username,
            passwd=password,
            db=db_name,
            connect_timeout=5
        )
        return conn
    except Exception as e:
        print(f"Error connecting to RDS or getting secret: {e}")
        return None

def handler(event, context):
    # Get required parameters
    try:
        table_name = event['queryStringParameters']['table-name']
        id = event['queryStringParameters']['id']
        bar = event['queryStringParameters']['bar']
    except KeyError:
        return {
            'statusCode': 400,
            'body': f"Missing required parameters. Received: {event['queryStringParameters']}",
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }

    conn = get_rds_connection()
    if not conn:
        return {
            'statusCode': 500,
            'body': "Failed to connect to RDS",
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }

    try:
        with conn.cursor() as cursor:
            if event['httpMethod'] == 'GET':
                sql = f"SELECT * FROM {table_name} WHERE id = %s"
                cursor.execute(sql, (id,))
                result = cursor.fetchone()

                if result:
                    response_body = f"Found item: {result}"
                else:
                    response_body = "Item not found"

            elif event['httpMethod'] == 'PUT':
                sql = f"INSERT INTO {table_name} (id, bar) VALUES (%s, %s) ON DUPLICATE KEY UPDATE bar = %s"
                cursor.execute(sql, (id, bar, bar))
                conn.commit()
                response_body = f"Successfully updated item with id {id}"

        return {
            'statusCode': 200,
            'body': response_body,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }

    except Exception as e:
        return {
            'statusCode': 500,
            'body': f"Error processing request: {str(e)}",
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }

    finally:
        conn.close()

if __name__ == "__main__":
    test_event = {
        'httpMethod': 'GET',
        'queryStringParameters': {
            'table-name': 'test_table',
            'id': '5',
            'bar': 'foo'
        }
    }
    print(handler(test_event, None))
