import boto3
import json
import time
import os

ssm = boto3.client('ssm')

INSTANCE_ID = os.environ['INSTANCE_ID']

COMMANDS = {
    'bgp-summary': 'vtysh -c "show ip bgp summary"',
    'bgp-table':   'vtysh -c "show ip bgp"',
    'route-table': 'vtysh -c "show ip route"',
    'interfaces':  'vtysh -c "show interface brief"',
}

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET',
    'Content-Type': 'application/json',
}


def lambda_handler(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    cmd_key = (event.get('queryStringParameters') or {}).get('cmd', 'bgp-summary')

    if cmd_key not in COMMANDS:
        return {
            'statusCode': 400,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'invalid command'}),
        }

    try:
        resp = ssm.send_command(
            InstanceIds=[INSTANCE_ID],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': [COMMANDS[cmd_key]]},
        )
        cmd_id = resp['Command']['CommandId']

        for _ in range(20):
            time.sleep(1)
            inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=INSTANCE_ID)
            if inv['Status'] not in ('Pending', 'InProgress', 'Delayed'):
                break

        if inv['Status'] == 'Success':
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps({
                    'output': inv['StandardOutputContent'].strip(),
                    'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC'),
                    'status': 'up',
                }),
            }

    except Exception:
        pass

    return {
        'statusCode': 200,
        'headers': CORS_HEADERS,
        'body': json.dumps({
            'output': 'BGP router unavailable — instance may be stopped.',
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC'),
            'status': 'down',
        }),
    }
