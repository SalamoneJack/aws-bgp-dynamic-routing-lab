import boto3
import json
import time
import os

ssm = boto3.client('ssm')

INSTANCE_IDS = {
    'cloud':  os.environ['CLOUD_INSTANCE_ID'],
    'onprem': os.environ['ONPREM_INSTANCE_ID'],
}

COMMANDS = {
    'bgp-summary': 'vtysh -c "show ip bgp summary"',
    'bgp-table':   'vtysh -c "show ip bgp"',
    'route-table': 'vtysh -c "show ip route"',
    'interfaces':  'vtysh -c "show interface brief"',
}

HEADERS = {'Content-Type': 'application/json'}


def lambda_handler(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') == 'OPTIONS':
        return {'statusCode': 200, 'headers': HEADERS, 'body': ''}

    params = event.get('queryStringParameters') or {}
    cmd_key    = params.get('cmd', 'bgp-summary')
    router_key = params.get('router', 'cloud')

    if cmd_key not in COMMANDS:
        return {
            'statusCode': 400,
            'headers': HEADERS,
            'body': json.dumps({'error': 'invalid command'}),
        }

    instance_id = INSTANCE_IDS.get(router_key, INSTANCE_IDS['cloud'])

    try:
        resp = ssm.send_command(
            InstanceIds=[instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={'commands': [COMMANDS[cmd_key]]},
        )
        cmd_id = resp['Command']['CommandId']

        for _ in range(20):
            time.sleep(1)
            inv = ssm.get_command_invocation(CommandId=cmd_id, InstanceId=instance_id)
            if inv['Status'] not in ('Pending', 'InProgress', 'Delayed'):
                break

        if inv['Status'] == 'Success':
            return {
                'statusCode': 200,
                'headers': HEADERS,
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
        'headers': HEADERS,
        'body': json.dumps({
            'output': 'BGP router unavailable — instance may be stopped.',
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S UTC'),
            'status': 'down',
        }),
    }
