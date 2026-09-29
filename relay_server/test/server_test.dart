import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  final port = '8080';
  final host = 'http://0.0.0.0:$port';
  final wsUrl = 'ws://0.0.0.0:$port/ws';
  late Process p;

  setUp(() async {
    p = await Process.start(
      'dart',
      ['run', 'bin/server.dart'],
      environment: {'PORT': port},
    );
    // Wait for server to start.
    await p.stdout.first;
  });

  tearDown(() => p.kill());

  test('Health check returns JSON status', () async {
    final response = await http.get(Uri.parse('$host/'));
    expect(response.statusCode, 200);

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    expect(body['status'], 'ok');
    expect(body['server'], 'iskolinic_relay_server');
    expect(body['clients'], isA<int>());
    expect(body['records'], isA<Map>());
  });

  test('WebSocket ping/pong', () async {
    final channel = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    await channel.ready;

    channel.sink.add(jsonEncode({'type': 'ping', 'nodeId': 'test-node'}));

    final response = await channel.stream.first;
    final msg = jsonDecode(response as String) as Map<String, dynamic>;
    expect(msg['type'], 'pong');

    await channel.sink.close();
  });

  test('sync_push broadcasts to other clients', () async {
    final sender = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    final receiver = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    await sender.ready;
    await receiver.ready;

    // Listen on receiver for the broadcast.
    final completer = Completer<Map<String, dynamic>>();
    receiver.stream.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      if (msg['type'] == 'sync_push') {
        completer.complete(msg);
      }
    });

    // Send a sync_push from sender.
    sender.sink.add(
      jsonEncode({
        'type': 'sync_push',
        'nodeId': 'node-a',
        'table': 'patients',
        'records': [
          {
            'id': 'p1',
            'studentName': 'Test Student',
            'hlc': '0000000000001:0001:node-a',
            'nodeId': 'node-a',
            'isDeleted': 0,
          },
        ],
      }),
    );

    final received = await completer.future.timeout(const Duration(seconds: 5));
    expect(received['type'], 'sync_push');
    expect(received['table'], 'patients');
    expect((received['records'] as List).length, 1);

    await sender.sink.close();
    await receiver.sink.close();
  });

  test('sync_request returns sync_response with stored records', () async {
    final pusher = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    await pusher.ready;

    // Push some records first.
    pusher.sink.add(
      jsonEncode({
        'type': 'sync_push',
        'nodeId': 'node-a',
        'table': 'patients',
        'records': [
          {
            'id': 'p1',
            'studentName': 'Alice',
            'hlc': '0000000000010:0001:node-a',
            'nodeId': 'node-a',
            'isDeleted': 0,
          },
          {
            'id': 'p2',
            'studentName': 'Bob',
            'hlc': '0000000000011:0001:node-a',
            'nodeId': 'node-a',
            'isDeleted': 0,
          },
        ],
      }),
    );

    // Give the server a moment to process.
    await Future.delayed(const Duration(milliseconds: 200));

    // New client connects and requests sync.
    final requester = IOWebSocketChannel.connect(Uri.parse(wsUrl));
    await requester.ready;

    final completer = Completer<Map<String, dynamic>>();
    requester.stream.listen((raw) {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      if (msg['type'] == 'sync_response') {
        completer.complete(msg);
      }
    });

    requester.sink.add(
      jsonEncode({
        'type': 'sync_request',
        'nodeId': 'node-b',
        'sinceHlc': '',
        'batchSize': 50,
      }),
    );

    final response = await completer.future.timeout(const Duration(seconds: 5));
    expect(response['type'], 'sync_response');
    expect(response['patients'], isA<List>());
    expect((response['patients'] as List).length, 2);
    expect(response['hasMore'], false);

    await pusher.sink.close();
    await requester.sink.close();
  });

  test('404 for unknown routes', () async {
    final response = await http.get(Uri.parse('$host/foobar'));
    expect(response.statusCode, 404);
  });
}
