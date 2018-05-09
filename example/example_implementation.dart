// Copyright (c) 2018, Brian Armstrong. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:channel_mock/channel_mock.dart';

// This library is meant for mocking flutter method channels during unit tests
// This example file is of a mock for FirebaseAuth
void main() {
  const MethodChannel channel = const MethodChannel(
    'plugins.flutter.io/firebase_auth',
  );

  ChannelMock mock;

  var mockUserData = {
    'uid': 'mock-uid',
    'providerData': [
      {
        'providerId': 'mock-provider',
        'uid': 'mock-provider-id',
      },
    ],
  };

  setUp(() {
    // This is all it takes, then we just need to use our methods
    mock = new ChannelMock(channel);
  });

  test('Simple return value', () async {
    // Whenever the 'getIdToken' method is called, it will return our mock token
    mock.when('currentUser').thenReturn(mockUserData);

    FirebaseUser user = await FirebaseAuth.instance.currentUser();
    expect(user.uid, equals('mock-uid'));
  });

  test('Mock a platform response after a call', () async {
    // With FirebaseAuth, a platform message is required for an auth state change to happen
    // So when we start listening, we have to emulate this platform call
    mock.when('startListeningAuthState').thenRespond(
        'onAuthStateChanged',
        (handle, _) => <String, dynamic>{
              'id': handle,
              'user': mockUserData,
            });

    // Use a Completer so we can wait on the results of `onAuthStateChanged`
    Completer doneListening = new Completer();

    // Trigger our code and complete with the found user
    FirebaseAuth.instance.onAuthStateChanged.then((user) {
      doneListening.complete(user);
    });

    // *magic*
    FirebaseUser user = await doneListening.future;
    expect(user.uid, equals('mock-uid'));
  });

  test('Mock a google sign in', () async {
    mock.when('signInWithGoogle').thenCall((handle, args) {
      // `handle` is an internally auto incremented number representing how many calls have been made
      // - it is often used internally with plugins for keeping data going down the right paths
      // `args` is whatever arguments were passed to `channel.invokeMethod`
      // - in this case, it's a Map<String, String>, but it varies by implementation
      Map newUser = new Map.from(mockUserData);
      newUser['email'] = '${args['idToken']}@${args['accessToken']}';

      // Whatever we return from this function is returned as if from `thenReturn`
      return newUser;
    });

    FirebaseUser result = await FirebaseAuth.instance.signInWithGoogle('mock-id-token', 'mock-access-token');
    expect(result.uid, equals('mock-uid'));
    expect(result.email, equals('mock-id-token@mock-access-token'));
  });

  test('We just want most things to return the user', () async {
    // ChannelMock.otherwise is the default value to return if the MethodCall's method has not been mocked
    mock.otherwise().thenReturn(mockUserData);

    // Because we didn't mock this method specifically, it just returns the mock user data
    FirebaseUser user = Firebase.instance.createUserWithEmailAndPassword('mock-email', 'mock-password');
    expect(user.uid, equals('mock-uid'));
  });
}
