// Copyright (c) 2018, Brian Armstrong. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

import 'package:channel_mock/channel_mock.dart';

void main() {
  MethodChannel channel;
  ChannelMock mock;
  List<MethodCall> channelLog;

  setUp(() {
    channelLog = [];

    channel = new MethodChannel(
      'plugins.flutter.institute/channel_mock',
    );
    channel.setMethodCallHandler((MethodCall methodCall) async {
      channelLog.add(methodCall);

      switch (methodCall.method) {
        case 'identity':
          return methodCall.arguments;
      }

      return true;
    });

    mock = new ChannelMock(channel);
  });

  test('default handler', () async {
    // Returns null before being set
    dynamic result =
        await channel.invokeMethod('identity', {'channel': 'test'});
    expect(result, isNull);

    // Set up the handle to return an object
    Map<String, String> expected = {'result': 'our mock is functional'};
    mock.otherwise().thenReturn(expected);

    result = await channel.invokeMethod('identity', {'channel': 'test'});
    expect(result, equals(expected));

    // Overrides to return a different value
    mock.otherwise().thenReturn(true);
    result = await channel.invokeMethod('identity', {'channel': 'test'});
    expect(result, isTrue);
  });

  test('when differentiates calls', () async {
    // Just to make sure we're not accidentally always calling the same handler
    mock.when('first').thenReturn('first');
    mock.when('second').thenReturn('second');

    dynamic result = await channel.invokeMethod('first');
    expect(result, equals('first'));
    result = await channel.invokeMethod('second');
    expect(result, equals('second'));
  });

  test('when.returnHandle', () async {
    mock.when('handler').thenReturnHandle();

    dynamic result = await channel.invokeMethod('handler');
    expect(result, equals(0));
    result = await channel.invokeMethod('handler');
    expect(result, equals(1));
    result = await channel.invokeMethod('handler');
    expect(result, equals(2));
  });

  test('when.return', () async {
    mock.when('handler').thenReturn(true);
    dynamic result = await channel.invokeMethod('handler');
    expect(result, isTrue);

    mock.reset();
    mock.when('handler').thenReturn('this is my string');
    result = await channel.invokeMethod('handler');
    expect(result, equals('this is my string'));

    mock.reset();
    Map<String, String> expected = {'result': 'our mock is functional'};
    mock.when('handler').thenReturn(expected);
    result = await channel.invokeMethod('handler');
    expect(result, equals(expected));
  });

  test('when.throw', () async {
    mock.when('exception').thenThrow('my error');

    expect(() async {
      await channel.invokeMethod('exception');
    }, throwsException);
  });

  test('when.call', () async {
    bool wasCalled = false;
    Map args = {'key': 'value'};

    mock.when('calling').thenCall((handle, arguments) {
      wasCalled = true;
      expect(handle, equals(0));
      expect(arguments, equals(args));
      return 'my value';
    });

    dynamic result = await channel.invokeMethod('calling', args);
    expect(wasCalled, isTrue);
    expect(result, equals('my value'));
  });

  test('when.response', () async {
    Completer completer = new Completer();

    mock.when('ping').thenRespond(
      'identity',
      (handle, args) => {
            'callArgs': args,
            'genArgs': [1, 2, 3],
          },
      (result) {
        completer.complete(result);
      },
    );

    dynamic result = await channel.invokeMethod('ping', {'key': 'value'});
    expect(result, equals(0)); // The handle

    // Wait for the callback to finish
    dynamic callbackResult = await completer.future;

    // This is what our generated arguments should look like
    Map<String, dynamic> expectedResult = {
      'callArgs': {'key': 'value'},
      'genArgs': [1, 2, 3],
    };
    expect(callbackResult, equals(expectedResult));

    expect(channelLog, hasLength(1));
    MethodCall call = channelLog[0];
    expect(call.method, equals('identity'));
    expect(call.arguments, equals(expectedResult));
  });

//  test('invocation inside when.call', () async {});

  test('when calls catchall if declared first', () async {
    mock.when('catchit').thenReturn('was default');
    mock
        .when('catchit', new ArgumentMatcher.exactly(1))
        .thenReturn('was other');

    dynamic result = await channel.invokeMethod('catchit', 1);
    expect(result, equals('was default'));
  });

  test('when with ArgumentMatcher.exactly', () async {
    final Map<String, String> objectArg = {'this': 'object', 'has': 'values'};
    mock
        .when('handler', new ArgumentMatcher.exactly(objectArg))
        .thenReturn('was object');
    mock
        .when('handler', new ArgumentMatcher.exactly([1, 2, 3]))
        .thenReturn('was list');
    mock
        .when('handler', new ArgumentMatcher.exactly(true))
        .thenReturn('was boolean');
    mock
        .when('handler', new ArgumentMatcher.exactly('my string'))
        .thenReturn('was string');
    mock.when('handler').thenReturn('was default');

    dynamic result = await channel.invokeMethod('handler', 'my string');
    expect(result, equals('was string'));

    result = await channel.invokeMethod('handler', objectArg);
    expect(result, equals('was object'));
    result = await channel
        .invokeMethod('handler', {'this': 'object', 'has': 'values'});
    expect(result, equals('was object'));

    result = await channel.invokeMethod('handler', [1, 2, 3]);
    expect(result, equals('was list'));

    result = await channel.invokeMethod('handler', true);
    expect(result, equals('was boolean'));

    result = await channel.invokeMethod('handler', 'other string');
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', {'other': 'object'});
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', ['other', 'list']);
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', false);
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler');
    expect(result, equals('was default'));
  });

  test('when with ArgumentMatcher.contains', () async {
    final Map<String, dynamic> args = {
      'string': 'my string',
      'int': 12345,
      'double': 3.141,
      'list': [1, 2, 3, 4, 5],
      'obj': {'key': 'value', 'second': 'entry'},
    };

    mock
        .when('handler', new ArgumentMatcher.contains({'string': 'my string'}))
        .thenReturn('was string');
    mock
        .when('handler', new ArgumentMatcher.contains({'double': 3.141}))
        .thenReturn('was double');
    mock
        .when('handler', new ArgumentMatcher.contains({'int': 12345}))
        .thenReturn('was int');
    mock
        .when(
            'handler',
            new ArgumentMatcher.contains({
              'obj': {'key': 'value', 'second': 'entry'}
            }))
        .thenReturn('was obj');
    mock
        .when(
            'handler',
            new ArgumentMatcher.contains({
              'list': [1, 2, 3, 4, 5]
            }))
        .thenReturn('was list');
    mock.when('handler').thenReturn('was default');

    // Matches in-order
    dynamic result = await channel.invokeMethod('handler', args);
    expect(result, equals('was string'));
    args.remove('string');

    result = await channel.invokeMethod('handler', args);
    expect(result, equals('was double'));
    args.remove('double');

    result = await channel.invokeMethod('handler', args);
    expect(result, equals('was int'));
    args.remove('int');

    result = await channel.invokeMethod('handler', args);
    expect(result, equals('was obj'));
    // Keys is other order
    result = await channel.invokeMethod('handler', {
      'obj': {'second': 'entry', 'key': 'value'}
    });
    expect(result, equals('was obj'));
    args.remove('obj');

    result = await channel.invokeMethod('handler', args);
    expect(result, equals('was list'));
    // Entries in other order
    result = await channel.invokeMethod('handler', {
      'list': [5, 4, 3, 2, 1]
    });
    expect(result, equals('was list'));
    args.remove('list');

    // `args` is now empty
    result = await channel.invokeMethod('handler', args);
    expect(result, equals('was default'));

    // Check that keys with wrong value don't match
    result = await channel.invokeMethod('handler', {'string': 'other value'});
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', {'int': 54321});
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', {'double': 6.282});
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', {
      'list': [1, 2, 3]
    });
    expect(result, equals('was default'));
    result = await channel.invokeMethod('handler', {
      'obj': {'key': 'value'}
    });
    expect(result, equals('was default'));
  });
}
