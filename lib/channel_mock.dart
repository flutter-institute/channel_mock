// Copyright (c) 2018, Brian Armstrong. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:collection/collection.dart';

/// Type for the callback for the `thenResponse` callback
typedef void ChannelMockResponseCallback(dynamic decodedResult);

/// Wrap a channel in a mock implementation
///
/// This mock allows you to override specific methods for the channel
/// and replace them with customer handlers.
class ChannelMock {
  final MethodChannel _channel;

  int _mockHandleId;
  Map<String, List<dynamic>> _callLog;
  Map<String, List<MockInvocation>> _callHandlers;
  MockInvocation _defaultHandler;

  ChannelMock(this._channel) {
    reset();
  }

  void reset() {
    _mockHandleId = 0;
    _callLog = new Map<String, List<dynamic>>();
    _callHandlers = new Map<String, List<MockInvocation>>();
    _defaultHandler = null;

    _channel.setMockMethodCallHandler(_methodCallHandler);
  }

  Map<String, List<dynamic>> get log => _callLog;

  Future<dynamic> _methodCallHandler(MethodCall methodCall) async {
    final String method = methodCall.method;
    final dynamic arguments = methodCall.arguments;

    // Log the call for verification later
    List<dynamic> calls;
    if (_callLog.containsKey(method)) {
      calls = _callLog[method];
    } else {
      calls = _callLog[method] = <dynamic>[];
    }
    calls.add(arguments);

    // Handle if with our invocations, if we have one
    final int handle = _mockHandleId++;
    if (_callHandlers.containsKey(method)) {
      // Find the first invocation that matches
      final MockInvocation toInvoke = _callHandlers[method]
          .firstWhere((matcher) => matcher._matches(arguments));

      // Only execute and return the value from the first match
      if (toInvoke != null) {
        return toInvoke._run(handle, arguments);
      }
    }

    // No matching invocation, use the default handler, if we have one
    if (_defaultHandler != null) {
      return _defaultHandler._run(handle, methodCall);
    }

    // By default, just return null
    return null;
  }

  /// Add a default handler as a catchall
  MockInvocation otherwise() {
    return _defaultHandler = new MockInvocation._(this);
  }

  /// Add a mock implementation for the given method
  ///
  /// Only the first matching invocation is executed when the mock is called
  /// If you want to have a catchall (no arguments), make sure it comes last
  MockInvocation when(String method, [ArgumentMatcher argMatcher]) {
    List<MockInvocation> invocations;
    if (_callHandlers.containsKey(method)) {
      invocations = _callHandlers[method];
    } else {
      invocations = _callHandlers[method] = <MockInvocation>[];
    }

    final MockInvocation nextInvocation =
        new MockInvocation._(this, argMatcher);
    invocations.add(nextInvocation);

    return nextInvocation;
  }

// TODO add `verify()` handling to validate that channel methods were called with the expected arguments
}

/// Function that mocks a call to the channel
typedef dynamic MockCallHandler(int handle, dynamic arguments);

/// Function that generates the arguments to use in a channel response
typedef dynamic ResponseArgumentGenerator(
    int callHandle, dynamic callArguments);

/// Class to handle mocking invocations of our channel methods
///
/// This class allows you to specify the arguments associated with this invocation
/// And the behavior for what the invocation should do
class MockInvocation {
  final ChannelMock _parent;
  ArgumentMatcher _argumentMatcher;
  MockCallHandler _executor;

  MockInvocation._(this._parent, [this._argumentMatcher]);

  bool _matches(dynamic arguments) {
    // If (no arguments or arguments match) and has an executor
    return (_argumentMatcher == null || _argumentMatcher._matches(arguments)) &&
        _executor != null;
  }

  dynamic _run(int handle, dynamic arguments) {
    if (_executor != null) {
      return _executor(handle, arguments);
    }
    return null;
  }

  /// Return the handle for the call
  ChannelMock thenReturnHandle() {
    _executor = (handle, _) => handle;
    return _parent;
  }

  /// Return a static value
  ChannelMock thenReturn(dynamic value) {
    _executor = (_, __) => value;
    return _parent;
  }

  /// Throw an error on this call.
  /// This error will be wrapped in a PlatformException when it gets back to the caller
  ChannelMock thenThrow(throwable) {
    _executor = (_, __) {
      throw throwable;
    };
    return _parent;
  }

  /// Call a user-supplied callback to handle the data
  ChannelMock thenCall(MockCallHandler handler) {
    _executor = handler;
    return _parent;
  }

  /// Send a mock response back along the channel
  ChannelMock thenRespond(
    String responseMethod, [
    ResponseArgumentGenerator createResponseArguments,
    ChannelMockResponseCallback responseCallback,
  ]) {
    _executor = (handle, arguments) {
      dynamic responseArguments;
      if (createResponseArguments != null) {
        responseArguments = createResponseArguments(handle, arguments);
      }

      BinaryMessages.handlePlatformMessage(
        _parent._channel.name,
        _parent._channel.codec.encodeMethodCall(
          new MethodCall(responseMethod, responseArguments),
        ),
        (respBytes) {
          if (responseCallback != null) {
            dynamic channelResponse =
                _parent._channel.codec.decodeEnvelope(respBytes);
            responseCallback(channelResponse);
          }
        },
      );

      // We always return the handle from a response method
      // Mostly this is because we are triggering a platform message from a "listen" style event
      // The listeners use the handle to determine which message goes where
      return handle;
    };
    return _parent;
  }
}

enum _MatcherType { Exact, Partial }

/// Class to handle logic for matching arguments for Mock Invocations
class ArgumentMatcher {
  final _MatcherType _type;
  final dynamic _args;

  final collectionEquality = const DeepCollectionEquality.unordered();

  /// Method arguments must match exactly.
  /// This uses an `unordered` compare if _args is a collection
  ArgumentMatcher.exactly(this._args) : _type = _MatcherType.Exact;

  /// Method arguments must contain certain values
  /// This assumes you are using "named"-style arguments with a map
  /// Arguments are compared key-by-key
  ArgumentMatcher.contains(Map<String, dynamic> args)
      : _type = _MatcherType.Partial,
        _args = args;

  bool _matches(dynamic arguments) {
    switch (_type) {
      case _MatcherType.Exact:
        return _args == arguments ||
            collectionEquality.equals(arguments, _args);

      case _MatcherType.Partial:
        if (arguments is Map && _args is Map) {
          final Map<dynamic, dynamic> argMap = arguments;
          final Map<String, dynamic> match = _args;

          // Make sure each specified key matches. Ignore the others.
          return match.keys.every((key) =>
              argMap.containsKey(key) &&
              (argMap[key] == match[key] ||
                  collectionEquality.equals(match[key], argMap[key])));
        }
        break;
    }

    return false;
  }
}
