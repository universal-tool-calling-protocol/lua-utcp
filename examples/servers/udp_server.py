import socket, json
HOST='127.0.0.1'; PORT=9001
with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as s:
    s.bind((HOST,PORT)); print(f'UDP server listening on {HOST}:{PORT}')
    while True:
        data,addr=s.recvfrom(65535)
        try: response={'result':json.loads(data)}
        except Exception as e: response={'error':str(e)}
        s.sendto(json.dumps(response).encode(),addr)
